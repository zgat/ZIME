#!/usr/bin/env ruby
require "rbconfig"
require_relative "test_process"

def check(value, message)
  raise message unless value
end

def rejects(type)
  yield
rescue type => error
  return error
else
  raise "expected #{type}"
end

ruby = RbConfig.ruby
out, err, status = TestProcess.capture({"ZIME_PROCESS_FIXTURE" => "ok"}, ruby, "-e",
  'STDOUT.write(ENV.fetch("ZIME_PROCESS_FIXTURE")); STDERR.write("error"); exit 7', timeout: 5)
check([out, err, status.exitstatus] == ["ok", "error", 7], "lost output/environment/status")
payload = ("a\x00你\n" * 40_000).b
out, err, status = TestProcess.capture(ruby, "-e",
  'STDOUT.sync = STDERR.sync = true; STDERR.write("e" * 300_000); STDOUT.write(STDIN.read)',
  stdin_data: payload, timeout: 5)
check(status.success? && out.b == payload && err == "e" * 300_000, "pipe deadlock or truncated binary IO")
out, _, status = TestProcess.capture(ruby, "-e", 'STDIN.close; puts "closed"', stdin_data: payload, timeout: 5)
check(out == "closed\n" && status.success?, "early stdin close broke capture")

[:term, :kill, :descendant].each do |mode|
  # All fixtures also have a finite lifetime: a regressed runner cannot hang
  # this self-test forever. The descendant deliberately inherits both pipes.
  code = 'STDOUT.sync = true; puts Process.pid; '
  code += case mode
          when :term then 'sleep 2'
          when :kill then 'trap("TERM", "IGNORE"); sleep 2'
          when :descendant then 'fork { trap("TERM", "IGNORE"); sleep 2 }; exit! 0'
          end
  start = TestProcess.now
  error = rejects(TestProcess::DeadlineExceeded) {
    TestProcess.capture(ruby, "-e", code, timeout: 0.25, term_grace: 0.1, owner: false)
  }
  check(TestProcess.now - start < 1.5, "#{mode} deadline waited for natural process exit")
  pid = Integer(error.stdout.lines.first)
  rejects(Errno::ECHILD) { Process.waitpid(pid, Process::WNOHANG) }
end
rejects(TestProcess::OutputExceeded) {
  TestProcess.capture(ruby, "-e", 'STDOUT.write("x" * 300_000); sleep 2', timeout: 3, output_limit: 1024)
}
rejects(Errno::ENOENT) { TestProcess.capture("/nonexistent/zime-process-fixture", timeout: 1) }
[0, -1, Float::INFINITY, Float::NAN, nil, "1"].each do |limit|
  rejects(ArgumentError) { TestProcess.capture(ruby, "-e", "", timeout: limit) }
end
rejects(ArgumentError) { TestProcess.capture }
rejects(ArgumentError) { TestProcess.capture(ruby, stdin_data: nil) }
# Repeated success and spawn failure must close all six pipe ends.
GC.start
before = ObjectSpace.each_object(IO).count { |io| !io.closed? }
12.times do
  TestProcess.capture(ruby, "-e", "", timeout: 5)
  rejects(Errno::ENOENT) { TestProcess.capture("/nonexistent/zime-process-fixture") }
end
after = ObjectSpace.each_object(IO).count { |io| !io.closed? }
check(after == before, "subprocess runner leaked open IO: #{before} -> #{after}")
puts "Test subprocess owner: PASS (duplex IO; deadlines/TERM/KILL/descendants; output cap; reap; validation; FD cleanup)"
