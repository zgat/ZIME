#!/usr/bin/env ruby
require "rbconfig"
require "tmpdir"
require_relative "test_process"

module TestRunnerTests
  RUBY = RbConfig.ruby.freeze
  RUNNER = File.join(__dir__, "run_test_process.rb").freeze
  def self.check(value, message)
    raise message unless value
  end

  def self.run(*arguments, **options)
    TestProcess.capture(RUBY, RUNNER, *arguments, timeout: 8, **options)
  end

  def self.wait_child(pid)
    deadline = TestProcess.now + 2
    loop do
      result = Process.waitpid2(pid, Process::WNOHANG)
      return result[1] if result
      raise "runtime owner did not exit within outer watchdog" if TestProcess.now >= deadline
      sleep 0.01
    end
  end

  def self.cancel_running(environment, command, ready, signal)
    sender = Thread.new do
      deadline = TestProcess.now + 4
      until File.file?(ready) && !File.read(ready).empty?
        raise "signal fixture not ready" if TestProcess.now >= deadline
        sleep 0.01
      end
      target = Integer(File.read(ready))
      raise "invalid signal fixture owner" unless target > 1 && target != Process.pid
      Process.kill(signal, target)
      TestProcess.now
    end
    sender.report_on_exception = false
    out, err, status = TestProcess.capture(environment, *command, timeout: 8)
    begin
      sent_at = sender.value
    rescue StandardError => error
      raise "#{signal}: #{error.message}; #{status.inspect}\n#{out}#{err}"
    end
    [out, err, status, TestProcess.now - sent_at]
  ensure
    # value above reports sender failures with the child output. Do not let
    # Thread#join replace that diagnostic while unwinding the same exception.
    begin sender&.join(5); rescue StandardError; end
  end

  def self.verify
    payload = ("a\0你\n" * 40_000).b
    arguments = ["5", RUBY, "-e", 'STDOUT.write(STDIN.read); STDERR.write(ARGV.join("|")); exit 7', "a b", '$(literal)']
    {"CLI" => [RUBY, RUNNER, *arguments],
      "shell" => ["/bin/bash", "-c", 'source "$1"; shift; linnet_test_run "$@"', "_",
        File.join(__dir__, "test_runner.sh"), *arguments]}.each do |owner, command|
      out, err, status = TestProcess.capture(*command, stdin_data: payload, timeout: 8)
      check(out.b == payload && err == 'a b|$(literal)' && status.exitstatus == 7, "#{owner} runtime IO/argv/status changed")
    end
    _, _, status = run("5", RUBY, "-e", 'Process.kill("TERM", Process.pid)')
    check(status.exitstatus == 143, "child signal status lost")
    [[], ["5"], ["0"], ["-1"], ["NaN"], ["Infinity"], ["invalid"]].each do |arguments|
      arguments += [RUBY, "-e", 'abort "unexpected spawn"'] unless arguments.empty? || arguments == ["5"]
      _, err, status = run(*arguments)
      check(status.exitstatus == 64 && !err.include?("unexpected spawn"), "invalid runtime limits spawned a child")
    end
    _, _, status = run("5", "/nonexistent/zime-runtime-fixture")
    check(status.exitstatus == 126, "spawn error status changed")
    _, _, status = run("5", "--chdir", "/nonexistent/zime-runtime-fixture", RUBY, "-e", "")
    check(status.exitstatus == 126, "missing working directory accepted")

    Dir.mktmpdir("zime runtime loader-") do |root|
      source = File.join(root, "probe.c")
      binary = File.join(root, "probe")
      File.write(source, <<~'C')
        #include <stdio.h>
        #include <stdlib.h>
        #include <unistd.h>
        int main(void) {
          char cwd[4096];
          if (!getcwd(cwd, sizeof(cwd))) return 3;
          const char *library = getenv("DYLD_LIBRARY_PATH");
          const char *fallback = getenv("DYLD_FALLBACK_LIBRARY_PATH");
          printf("%s\n%s\n%s\n", cwd, library ? library : "UNSET", fallback ? fallback : "UNSET");
          return 0;
        }
      C
      _, err, status = TestProcess.capture("xcrun", "clang", "-Wall", "-Wextra", "-Werror",
        source, "-o", binary, timeout: 30)
      check(status.success?, "native loader fixture compilation failed: #{err}")
      Dir.mkdir(File.join(root, "bin"))
      [RUBY, "/usr/bin/ruby"].uniq.each do |interpreter|
        executable = File.join(root, "bin/ruby")
        File.symlink(interpreter, executable)
        begin
          shell = <<~'SH'
            set -euo pipefail
            source "$RUNNER_HELPER"
            DYLD_LIBRARY_PATH='/fixture library path' DYLD_FALLBACK_LIBRARY_PATH='/fixture fallback' \
              linnet_test_run 5 --chdir "$RUNNER_CWD" "$RUNNER_PROBE"
            unset DYLD_LIBRARY_PATH DYLD_FALLBACK_LIBRARY_PATH
            linnet_test_run 5 --chdir "$RUNNER_CWD" "$RUNNER_PROBE"
          SH
          out, err, status = TestProcess.capture({"PATH" => "#{root}/bin:#{ENV.fetch('PATH')}",
            "RUNNER_HELPER" => File.join(__dir__, "test_runner.sh"), "RUNNER_CWD" => root, "RUNNER_PROBE" => binary},
            "/bin/bash", "-c", shell, timeout: 10)
          expected = [File.realpath(root), "/fixture library path", "/fixture fallback", File.realpath(root), "UNSET", "UNSET"]
          check(status.success? && out.lines.map(&:chomp) == expected, "#{interpreter}: loader relay/cwd isolation failed: #{out} #{err}")
        ensure
          File.unlink(executable)
        end
      end
    end

    # The finite descendant keeps stdout open. Failing to kill its process
    # group makes the *outer* capture wait for natural exit and fail this test.
    start = TestProcess.now
    out, err, status = run("0.2", RUBY, "-e", <<~'RUBY')
      STDOUT.sync = true
      trap("TERM", "IGNORE")
      fork { sleep 3; puts "descendant escaped" }
      puts "ready"
      sleep 3
    RUBY
    check(status.exitstatus == 124 && out == "ready\n" && err.include?("deadline exceeded") &&
      TestProcess.now - start < 2, "runtime deadline/group teardown failed")
    # Successful parents must not leave inherited-output descendants behind.
    start = TestProcess.now
    out, _, status = run("5", RUBY, "-e", 'fork { sleep 3; puts "escaped" }; exit! 0')
    check(status.success? && out.empty? && TestProcess.now - start < 2, "successful owner leaked descendants")

    # Both output streams share a pipe with no reader consuming it. This tests
    # the runtime deadline AND the final diagnostic against backpressure.
    reader, writer = IO.pipe
    pid = Process.spawn(RUBY, RUNNER, "0.2", RUBY, "-e",
      'trap("TERM", "IGNORE"); STDOUT.write("x" * 1_000_000); sleep 3',
      out: writer, err: writer, pgroup: true)
    writer.close
    begin
      check(wait_child(pid).exitstatus == 124, "slow output consumer lost timeout status")
      check(!reader.read.empty?, "slow consumer fixture did not produce output")
    ensure
      # Closing this pipe releases even a regressed child blocked in write.
      reader.close
      TestProcess.signal_group("KILL", pid)
      begin Process.waitpid(pid); rescue Errno::ECHILD; end
    end

    reader, writer = IO.pipe
    reader.close
    pid = Process.spawn(RUBY, RUNNER, "0.2", RUBY, "-e",
      'STDOUT.write("x" * 1_000_000)', out: writer, err: File::NULL, pgroup: true)
    writer.close
    begin
      check(!wait_child(pid).success?, "closed downstream output was reported as success")
    ensure
      TestProcess.signal_group("KILL", pid)
      begin Process.waitpid(pid); rescue Errno::ECHILD; end
    end

    Dir.mktmpdir("zime-runtime-signals-") do |root|
      %w[INT TERM HUP].each do |signal|
        # Signal the actual CLI owner, not its shell wrapper. The child exits
        # successfully on cancellation, so returning that status is a defect.
        ready = File.join(root, "cli-ready-#{signal}")
        child = <<~'RUBY'
          STDOUT.sync = true
          %w[INT TERM HUP].each { |signal| trap(signal) { puts "child cancelled #{signal}"; exit 0 } }
          fork { %w[INT TERM HUP].each { |s| trap(s, "IGNORE") }; sleep 3; puts "descendant escaped" }
          File.write(ENV.fetch("RUNNER_READY"), Process.ppid.to_s)
          sleep 3
          puts "child escaped"
        RUBY
        out, _, status, elapsed = cancel_running({"RUNNER_READY" => ready},
          [RUBY, RUNNER, "5", RUBY, "-e", child], ready, signal)
        check(status.exitstatus == 128 + Signal.list.fetch(signal), "#{signal}: CLI cancellation status lost")
        check(out == "child cancelled #{signal}\n" && elapsed < 2,
          "#{signal}: CLI cancellation failed to terminate its process group")

        ready = File.join(root, "ready-#{signal}")
        child = <<~'RUBY'
          STDOUT.sync = true
          %w[INT TERM HUP].each do |signal|
            trap(signal) do
              puts "child cancelled #{signal}; scratch=#{File.directory?(ENV.fetch('LINNET_SWIFT_TEST_SCRATCH'))}"
              exit 0
            end
          end
          fork { %w[INT TERM HUP].each { |s| trap(s, "IGNORE") }; sleep 3; puts "descendant escaped" }
          File.write(ENV.fetch("RUNNER_READY"), ENV.fetch("RUNNER_OWNER"))
          sleep 3
          puts "child escaped"
        RUBY
        shell = <<~'SH'
          set -euo pipefail
          source "$RUNNER_SCRATCH_HELPER"
          linnet_swift_scratch_init
          printf '%s\n' "$scratch"
          export RUNNER_OWNER=$$
          linnet_test_run 5 "$RUNNER_RUBY" -e "$RUNNER_CHILD"
          echo 'continued after cancellation'
        SH
        environment = {"RUNNER_READY" => ready, "RUNNER_RUBY" => RUBY, "RUNNER_CHILD" => child,
          "RUNNER_SCRATCH_HELPER" => File.join(__dir__, "swift_test_scratch.sh")}
        out, _, status, elapsed = cancel_running(environment, ["/bin/bash", "-c", shell], ready, signal)
        check(status.exitstatus == 128 + Signal.list.fetch(signal), "#{signal}: shell cancellation status lost")
        check(out.include?("child cancelled #{signal}; scratch=true") && !out.include?("escaped") &&
          !out.include?("continued after"), "#{signal}: cancellation was not forwarded before cleanup: #{out}")
        check(elapsed < 2 && !File.exist?(out.lines.first.strip),
          "#{signal}: waited for natural exit or leaked scratch")

        # Interrupt the exact launch/register window, not a probabilistic
        # sleep. DEBUG runs immediately before the parent's $! assignment.
        ready = File.join(root, "launch-ready-#{signal}")
        startup = <<~'SH'
          set -euo pipefail
          source "$RUNNER_SCRATCH_HELPER"
          linnet_swift_scratch_init
          printf '%s\n' "$scratch"
          export RUNNER_OWNER=$$
          cancel_before_registration() {
            [[ "$BASH_COMMAND" == 'LINNET_TEST_RUNNER_PID=$!' ]] || return 0
            trap - DEBUG
            "$RUNNER_RUBY" -e '
              deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
              until File.file?(ENV.fetch("RUNNER_READY"))
                abort "launch fixture not ready" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
                sleep 0.01
              end
            '
            kill -"$RUNNER_SIGNAL" "$$"
          }
          set -T
          trap cancel_before_registration DEBUG
          linnet_test_run 5 "$RUNNER_RUBY" -e "$RUNNER_CHILD"
          echo 'continued after cancellation'
        SH
        start = TestProcess.now
        out, err, status = TestProcess.capture(environment.merge("RUNNER_READY" => ready, "RUNNER_SIGNAL" => signal),
          "/bin/bash", "-c", startup, timeout: 8)
        check(status.exitstatus == 128 + Signal.list.fetch(signal) &&
          out.lines.size == 2 && out.lines.last.chomp == "child cancelled #{signal}; scratch=true" &&
          TestProcess.now - start < 2 && !File.exist?(out.lines.first.strip),
          "#{signal}: launch-window cancellation escaped registration/cleanup: #{out} #{err}")
      end
    end
    puts "Test runtime owner: PASS (CLI and shell binary IO/status; validation; cwd/SIP loader relay; deadlines; descendants; blocked/closed consumer; direct and shell INT/TERM/HUP; cleanup ordering)"
  end
end

TestRunnerTests.verify if $PROGRAM_NAME == __FILE__
