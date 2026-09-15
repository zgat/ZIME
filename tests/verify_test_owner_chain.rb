#!/usr/bin/env ruby
# Drive the real outer shell entrypoints; replace only their first expensive
# leaf. Finite workers keep failed cancellation tests bounded independently.
require "fileutils"
require "tmpdir"
require "rbconfig"
require_relative "verify_test_runner"

module TestOwnerChainTests
  def self.verify
    Dir.mktmpdir("zime-owner-chain-") do |root|
      tests = File.join(root, "tests")
      Dir.mkdir(tests)
      %w[verify_development.sh verify_swift_units.sh test_runner.sh exec_test_owner.rb
        run_test_process.rb test_process.rb swift_test_scratch.sh].each do |name|
        FileUtils.cp(File.join(__dir__, name), File.join(tests, name))
      end
      File.write(File.join(tests, "verify_coverage_gate.rb"), <<~'RUBY')
        ENV["RUNNER_OWNER"] = Process.ppid.to_s
        exec("/bin/bash", "tests/verify_swift_units.sh")
      RUBY
      File.write(File.join(tests, "verify_swift_scratch.sh"), <<~'SH')
        set -euo pipefail
        source tests/swift_test_scratch.sh
        linnet_swift_scratch_init
        printf '%s\n' "$scratch"
        export RUNNER_OWNER=${RUNNER_OWNER:-$PPID}
        if [[ "$RUNNER_LEAF" == compiler ]]; then
          linnet_test_call "$RUNNER_RUBY" -e "$RUNNER_COMPILER"
        else
          linnet_test_run 5 "$RUNNER_RUBY" -e "$RUNNER_CHILD"
        fi
        echo 'continued after cancellation'
      SH
      worker = <<~'RUBY'
        STDOUT.sync = true
        %w[INT TERM HUP].each do |signal|
          trap(signal) do
            puts "child cancelled #{signal}; scratch=#{File.directory?(ENV.fetch('LINNET_SWIFT_TEST_SCRATCH'))}"
            exit 0
          end
        end
        fork { %w[INT TERM HUP].each { |signal| trap(signal, "IGNORE") }; sleep 3; puts "descendant escaped" }
        File.write(ENV.fetch("RUNNER_READY"), ENV.fetch("RUNNER_OWNER"))
        sleep 3
        puts "child escaped"
      RUBY
      compiler = <<~'RUBY'
        require File.expand_path("tests/test_process")
        STDOUT.sync = true
        begin
          TestProcess.capture(ENV.fetch("RUNNER_RUBY"), "-e", '
            %w[INT TERM HUP].each { |signal| trap(signal, "IGNORE") }
            File.write(ENV.fetch("RUNNER_WORKER_PID"), Process.pid.to_s)
            File.write(ENV.fetch("RUNNER_READY"), ENV.fetch("RUNNER_OWNER"))
            sleep 3
            puts "compiler escaped"
          ', timeout: 5)
          puts "compiler returned naturally"
        ensure
          puts "compiler released; scratch=#{File.directory?(ENV.fetch('LINNET_SWIFT_TEST_SCRATCH'))}"
        end
      RUBY
      %w[swift development].each do |owner|
        %w[runtime compiler].each do |leaf|
          %w[INT TERM HUP].each do |signal|
            label = "#{owner}/#{leaf}/#{signal}"
            ready = File.join(root, "ready")
            File.unlink(ready) if File.exist?(ready)
            pid_file = File.join(root, "worker-pid")
            environment = {"RUNNER_READY" => ready, "RUNNER_RUBY" => RbConfig.ruby,
              "RUNNER_LEAF" => leaf, "RUNNER_CHILD" => worker, "RUNNER_COMPILER" => compiler,
              "RUNNER_WORKER_PID" => pid_file, "RUNNER_OWNER" => nil}
            command = ["/bin/bash", File.join(tests, "verify_#{owner == 'swift' ? 'swift_units' : 'development'}.sh")]
            command << "swift" if owner == "development"
            out, err, status, elapsed = TestRunnerTests.cancel_running(environment, command, ready, signal)
            expected = leaf == "runtime" ? "child cancelled #{signal}; scratch=true" : "compiler released; scratch=true"
            TestRunnerTests.check(status.exitstatus == 128 + Signal.list.fetch(signal), "#{label}: outer cancellation status lost: #{status} #{err}")
            TestRunnerTests.check(out.lines.size == 2 && out.lines.last.chomp == expected && elapsed < 2,
              "#{label}: cancellation did not reach leaf before cleanup: #{out} #{err}")
            TestRunnerTests.check(!File.exist?(out.lines.first.strip), "#{label}: scratch leaked")
            if leaf == "compiler"
              begin
                Process.kill(0, Integer(File.read(pid_file)))
                raise "#{label}: compiler subprocess not reaped"
              rescue Errno::ESRCH
                # The compiler owner reaped its native child before returning.
              end
            end
          end
        end
      end
    end
    puts "Test owner chain: PASS (real Swift/development entrypoints; runtime/compiler cancellation; INT/TERM/HUP; bottom-up teardown)"
  end
end

TestOwnerChainTests.verify if $PROGRAM_NAME == __FILE__
