#!/usr/bin/env ruby
# Runtime boundary for standalone executables. Output is inherited, not held
# until completion; the same process-group owner also backs compiler capture.
require "fcntl"
require_relative "test_process"

def diagnostic(message)
  # A full/closed downstream stderr must not hang timeout teardown itself.
  flags = STDERR.fcntl(Fcntl::F_GETFL)
  STDERR.write_nonblock("#{message}\n", exception: false)
rescue IOError, SystemCallError
  nil
ensure
  STDERR.fcntl(Fcntl::F_SETFL, flags) if flags
end

begin
  raise ArgumentError, "usage: run_test_process.rb SECONDS [--chdir DIRECTORY] EXECUTABLE [ARGS...]" if ARGV.size < 2
  duration = Float(ARGV.shift)
  directory = nil
  if ARGV.first == "--chdir"
    ARGV.shift
    directory = ARGV.shift
    raise ArgumentError, "missing working directory or executable" if directory.nil? || ARGV.empty?
  end
  environment = {}
  # SIP can remove loader variables while starting /usr/bin/ruby. Restore only
  # the explicitly relayed test library paths on the actual native child.
  if ENV["LINNET_TEST_LOADER_RELAY"] == "1"
    %w[DYLD_LIBRARY_PATH DYLD_FALLBACK_LIBRARY_PATH].each do |key|
      environment[key] = ENV["LINNET_TEST_#{key}_SET"] == "x" ? ENV.fetch("LINNET_TEST_#{key}") : nil
    end
  end
  pending_signal = nil
  %w[INT TERM HUP].each { |signal| Signal.trap(signal) { pending_signal ||= signal } }
  _, _, status = TestProcess.capture(environment, *ARGV, timeout: duration, inherit_stdio: true,
    cancelled: -> { pending_signal }, chdir: directory)
  exit(status.exitstatus || 128 + status.termsig)
rescue TestProcess::Cancelled => error
  diagnostic(error.message)
  exit(128 + Signal.list.fetch(error.signal))
rescue TestProcess::DeadlineExceeded => error
  diagnostic(error.message)
  exit 124
rescue ArgumentError => error
  diagnostic(error.message)
  exit 64
rescue SystemCallError => error
  diagnostic("cannot execute test: #{error.message}")
  exit 126
end
