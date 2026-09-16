#!/usr/bin/env ruby
# Cache compilation only. Every caller must still execute in its own fixture.
require "digest"
require "fileutils"
require "json"
require "open3"
require "shellwords"
require "tmpdir"
require_relative "compile_artifact_cache"
require_relative "test_process"

module CxxTestCache
  def self.compile(cache, output, command)
    raise ArgumentError, "missing compiler command" if command.empty? || command.include?("-o")
    # Dependency preprocessing cannot observe linker search results, framework
    # contents or response-file options. Do not guess them: compile in a private
    # stage and atomically publish only a successful result, without cache reuse.
    if command.any? { |arg| arg.start_with?("-l", "-Wl,", "@") ||
      %w[-framework -weak_framework -reexport_framework -Xlinker].include?(arg) }
      Dir.mktmpdir("zime-cxx-uncached-") do |stage|
        built = File.join(stage, "binary")
        build(command, built)
        CompileArtifactCache.publish(built, output)
      end
      puts "C++ test compile cache: BYPASS #{File.basename(output)} (indirect linker inputs)"
      return false
    end
    compiler, _, status = TestProcess.capture(command.first, "--version", timeout: 10, owner: false)
    raise "compiler identity unavailable" unless status.success?
    environment = ENV.select { |key, _| key.match?(/\A(CPATH|CPLUS_INCLUDE_PATH|LIBRARY_PATH|SDKROOT|DEVELOPER_DIR|MACOSX_DEPLOYMENT_TARGET)\z/) }
    identity = ["cxx", Dir.pwd, compiler, Digest::SHA256.file(__FILE__).hexdigest,
      Digest::SHA256.file(File.join(__dir__, "test_process.rb")).hexdigest, environment.sort, command]
    hit = CompileArtifactCache.fetch(cache, identity, output, resolve: ->(slot) { inputs(command, slot) }) do |built|
      build(command, built)
    end
    puts "C++ test compile cache: #{hit ? 'HIT' : 'MISS'} #{File.basename(output)}"
    hit
  end

  def self.build(command, output)
    out, err, status = TestProcess.capture(*command, "-o", output, timeout: 180, owner: false)
    warn(out + err) unless status.success?
    raise "C++ compilation failed" unless status.success?
  end

  def self.inputs(command, slot)
    sources = command.select { |arg| arg.match?(/\.(?:c|cc|cpp|cxx|m|mm|C)\z/) && File.file?(arg) }
    raise "no C++ sources" if sources.empty?
    Dir.mktmpdir("dependencies-", slot) do |stage|
      preprocessed = []
      dependencies = sources.flat_map.with_index { |source, index|
        depfile = File.join(stage, "deps-#{index}")
        output = File.join(stage, "source-#{index}")
        preprocessing = command.reject { |arg|
          (sources.include?(arg) && arg != source) || arg.match?(/\.(?:dylib|a|o)\z/)
        }
        # One unit per invocation; -MD includes SDK/system headers. A stable
        # dependency target avoids injecting this scratch path into the digest.
        out, err, status = TestProcess.capture(*preprocessing, "-E", "-MD", "-MF", depfile,
          "-MT", "probe", "-o", output, timeout: 60, owner: false)
        warn(out + err) unless status.success?
        raise "C++ compilation failed" unless status.success?
        preprocessed << Digest::SHA256.file(output).hexdigest
        Shellwords.split(File.read(depfile).gsub(/\\\n/, " ").split(": ", 2).fetch(1))
      }
      paths = (dependencies + command.select { |arg| File.file?(arg) }).map { |p| File.expand_path(p) }.uniq.sort
      [paths.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] }, preprocessed]
    end
  end
end

if $PROGRAM_NAME == __FILE__
  abort "usage: cxx_test_cache.rb CACHE OUTPUT -- COMPILER ARGS..." unless ARGV.size >= 4 && ARGV[2] == "--"
  CxxTestCache.compile(ARGV[0], ARGV[1], ARGV.drop(3))
end
