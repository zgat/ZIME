#!/usr/bin/env ruby
require_relative "compile_artifact_cache"
require_relative "test_process"

def check(value, message)
  raise message unless value
end

def rejects(pattern)
  yield
rescue StandardError => error
  raise unless error.message.match?(pattern)
else
  raise "expected rejection: #{pattern}"
end

def artifact(path, value)
  File.write(path, "#!/bin/sh\nprintf '%s' '#{value}'\n")
  File.chmod(0700, path)
end

def message(io)
  raise "cache fixture IPC timed out" unless IO.select([io], nil, nil, 8)
  io.read(1) || raise("cache fixture closed IPC unexpectedly")
end

def wait_child(pid)
  deadline = TestProcess.now + 8
  loop do
    result = Process.waitpid2(pid, Process::WNOHANG)
    return result if result
    raise "cache fixture worker timed out" if TestProcess.now >= deadline
    sleep 0.01
  end
end

Dir.mktmpdir("zime-artifact-cache-") do |dir|
  cache, output = %w[cache output].map { |name| File.join(dir, name) }
  inputs = {"source" => "a"}
  builds = 0
  fetch = -> {
    CompileArtifactCache.fetch(cache, "fixture", output, resolve: ->(_) { inputs.dup }) do |built|
      builds += 1
      artifact(built, inputs.fetch("source"))
    end
  }
  check(!fetch.call && fetch.call && builds == 1, "cache failed cold/warm reuse")
  slot = Dir[File.join(cache, "*")].fetch(0)
  manifest = File.join(slot, "manifest.json")
  ["{", "null", "[]", "{}", '{"inputs":{}}'].each do |bad|
    File.write(manifest, bad)
    check(!fetch.call, "malformed cache manifest reused: #{bad}")
  end
  File.write(File.join(slot, "binary"), "corrupt")
  check(!fetch.call, "binary corruption reused")
  inputs["source"] = "b"
  check(!fetch.call && File.read(output).include?("'b'"), "changed inputs reused")
  before = File.read(output)
  rejects(/inputs changed/) {
    CompileArtifactCache.fetch(cache, "unstable", output, resolve: ->(_) { inputs.dup }) do |built|
      artifact(built, "bad")
      inputs["source"] = "c"
    end
  }
  check(File.read(output) == before, "failed compile overwrote output")
  rejects(/compiler fixture failed/) {
    CompileArtifactCache.fetch(cache, "failed", output, resolve: ->(_) { {} }) { raise "compiler fixture failed" }
  }
  rejects(/did not produce an executable/) {
    CompileArtifactCache.fetch(cache, "empty", output, resolve: ->(_) { {} }) { |_built| }
  }

  outside = File.join(dir, "outside")
  File.write(outside, "protected")
  alias_output = File.join(dir, "output-alias")
  File.symlink(outside, alias_output)
  rejects(/unsafe test output/) {
    CompileArtifactCache.fetch(cache, "fixture", alias_output, resolve: ->(_) { inputs.dup }) { |b| artifact(b, "c") }
  }
  check(File.read(outside) == "protected", "output symlink clobbered target")
  directory_output = File.join(dir, "directory-output")
  Dir.mkdir(directory_output)
  File.symlink(outside, File.join(directory_output, "binary"))
  rejects(/unsafe test output/) {
    CompileArtifactCache.fetch(cache, "fixture", directory_output, resolve: ->(_) { inputs.dup }) { |b| artifact(b, "c") }
  }
  hardlink_output = File.join(dir, "hardlink-output")
  File.link(outside, hardlink_output)
  CompileArtifactCache.fetch(cache, "fixture", hardlink_output, resolve: ->(_) { inputs.dup }) { |b| artifact(b, "c") }
  check(File.read(outside) == "protected" && File.read(hardlink_output).include?("'c'"),
    "output publication followed a directory symlink or clobbered a hardlink")
  check(!File.identical?(outside, hardlink_output), "output was not atomically replaced")
  slot_alias = File.join(dir, "slot-alias")
  File.symlink(slot, slot_alias)
  rejects(/unsafe test output/) { CompileArtifactCache.publish(File.join(slot, "binary"), File.join(slot_alias, "binary")) }
  alias_root = File.join(dir, "cache-alias")
  File.symlink(cache, alias_root)
  rejects(/unsafe compiler cache directory/) {
    CompileArtifactCache.fetch(alias_root, "fixture", output, resolve: ->(_) { {} }) { |_b| }
  }
  lock = File.join(slot, "lock")
  File.unlink(lock)
  File.symlink(outside, lock)
  rejects(/symbolic links|symlink/i) { fetch.call }
  File.unlink(lock)
  check(fetch.call, "lock recovery lost valid binary")
  check(File.read(outside) == "protected", "lock symlink modified target")

  # Stop A during both compilation and output publication. B reports an actual
  # failed nonblocking lock attempt before A is allowed to continue.
  %w[compile publish].each do |phase|
    ready_r, ready_w = IO.pipe
    release_r, release_w = IO.pipe
    contender_r = contender_w = nil
    children = []
    begin
      children << fork do
        ready_r.close; release_w.close
        if phase == "publish"
          boundary = Module.new do
            define_method(:publish) do |binary, destination|
              ready_w.write("a"); ready_w.flush
              message(release_r)
              super(binary, destination)
            end
          end
          CompileArtifactCache.singleton_class.prepend(boundary)
        end
        CompileArtifactCache.fetch(cache, "race-#{phase}", File.join(dir, "a"), resolve: ->(_) { {"source" => "A"} }) do |built|
          artifact(built, "A")
          if phase == "compile"
            ready_w.write("a"); ready_w.flush
            message(release_r)
          end
        end
        exit! 0
      end
      ready_w.close; release_r.close
      message(ready_r)
      locked = Dir[File.join(cache, "*", "lock")].any? do |path|
        File.open(path, "r+") { |io| !io.flock(File::LOCK_EX | File::LOCK_NB) }
      end
      check(locked, "publication lock not held during #{phase}")
      contender_r, contender_w = IO.pipe
      children << fork do
        contender_r.close
        observer = Module.new do
          define_method(:flock) do |operation|
            if operation == File::LOCK_EX && File.basename(path) == "lock"
              raise "contender did not encounter publication lock" if super(operation | File::LOCK_NB)
              contender_w.write("b"); contender_w.flush
            end
            super(operation)
          end
        end
        File.prepend(observer)
        CompileArtifactCache.fetch(cache, "race-#{phase}", File.join(dir, "b"), resolve: ->(_) { {"source" => "B"} }) do |built|
          artifact(built, "B")
        end
        exit! 0
      end
      contender_w.close
      check(message(contender_r) == "b", "contender never requested the owned lock")
      release_w.write("g"); release_w.close
      children.dup.each do |pid|
        _, status = wait_child(pid)
        children.delete(pid)
        check(status.success?, "concurrent cache worker failed")
      end
      %w[a b].each { |v| check(File.read(File.join(dir, v)).include?("'#{v.upcase}'"), "concurrent cache returned another request's binary") }
    ensure
      children.each { |pid| Process.kill("KILL", pid); Process.waitpid(pid) }
      [ready_r, ready_w, release_r, release_w, contender_r, contender_w].compact.each { |io| io.close unless io.closed? }
    end
  end

  ready_r, ready_w = IO.pipe
  release_r, release_w = IO.pipe
  child = fork do
    ready_r.close; release_w.close
    CompileArtifactCache.fetch(cache, "interrupted", output, resolve: ->(_) { {} }) do |built|
      artifact(built, "unfinished")
      ready_w.write("s"); ready_w.flush
      message(release_r)
    end
    exit! 0
  end
  begin
    ready_w.close; release_r.close
    message(ready_r)
    Process.kill("KILL", child)
    Process.waitpid(child)
    child = nil
    abandoned = Dir[File.join(cache, "*", "compile-*")]
    check(abandoned.size == 1, "crash fixture did not leave its private stage")
    external_dir = File.join(dir, "protected-directory")
    FileUtils.mkdir_p(external_dir)
    File.write(File.join(external_dir, "keep"), "protected")
    stage_alias = File.join(File.dirname(abandoned.first), "compile-20260915-1-alias")
    File.symlink(external_dir, stage_alias)
    hit = CompileArtifactCache.fetch(cache, "interrupted", output, resolve: ->(_) { {} }) { |b| artifact(b, "recovered") }
    check(!hit && File.read(output).include?("'recovered'"), "interrupted publication poisoned cache")
    check(!File.exist?(abandoned.first), "abandoned compiler stage was not reclaimed")
    check(File.symlink?(stage_alias) && File.read(File.join(external_dir, "keep")) == "protected",
      "staging recovery followed an external symlink")
  ensure
    if child then Process.kill("KILL", child); Process.waitpid(child) end
    [ready_r, ready_w, release_r, release_w].each { |io| io.close unless io.closed? }
  end
end
puts "Compiler artifact cache: PASS (locking/race; integrity; malformed manifests; changing inputs; symlinks; crash recovery)"
