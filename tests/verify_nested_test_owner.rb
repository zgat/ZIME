#!/usr/bin/env ruby
require "rbconfig"
require "tmpdir"
require_relative "verify_test_runner"

owner_source = <<~'RUBY'
  require "rbconfig"
  helper, runner, depth, source = ARGV
  require helper
  ENV["NESTED_ROOT"] ||= Process.pid.to_s
  begin
    if depth.to_i > 0
      TestProcess.capture(RbConfig.ruby, "-e", source, helper, runner, (depth.to_i - 1).to_s, source,
        timeout: 10, owner: true)
    else
      leaf = <<~'LEAF'
        %w[INT TERM HUP].each { |signal| trap(signal, "IGNORE") }
        File.write(ENV.fetch("NESTED_PID"), Process.pid.to_s)
        File.write(ENV.fetch("RUNNER_READY"), ENV.fetch("NESTED_ROOT"))
        sleep 5
        File.write(ENV.fetch("NESTED_ESCAPED"), "escaped")
      LEAF
      TestProcess.capture(RbConfig.ruby, runner, "8", RbConfig.ruby, "-e", leaf, timeout: 10, owner: true)
    end
  ensure
    File.open(ENV.fetch("NESTED_ORDER"), "a") { |file| file.puts(depth) }
  end
RUBY

Dir.mktmpdir("zime nested ruby-") do |root|
  [0, 2].each do |depth|
    %w[INT TERM HUP timeout].each do |signal|
      paths = %w[ready pid escaped order].to_h { |name| [name, File.join(root, "#{depth}-#{signal}-#{name}")] }
      environment = {"RUNNER_READY" => paths["ready"], "NESTED_PID" => paths["pid"],
        "NESTED_ESCAPED" => paths["escaped"], "NESTED_ORDER" => paths["order"], "NESTED_ROOT" => nil}
      command = [RbConfig.ruby, "-e", owner_source, File.join(__dir__, "test_process.rb"),
        File.join(__dir__, "run_test_process.rb"), depth.to_s, owner_source]
      if signal == "timeout"
        begin
          TestProcess.capture(environment, *command, timeout: 2, owner: true)
          raise "nested owner timeout was not enforced"
        rescue TestProcess::DeadlineExceeded
          # All fixtures start and signal ready before the bounded deadline.
        end
      else
        _, err, status, elapsed = TestRunnerTests.cancel_running(environment, command, paths["ready"], signal)
        code = status.exitstatus || 128 + status.termsig
        TestRunnerTests.check(code == 128 + Signal.list.fetch(signal) && elapsed < 2,
          "nested owner cancellation status or deadline lost: #{err}")
      end
      TestRunnerTests.check(File.file?(paths["pid"]), "nested fixture never reached its leaf")
      begin
        Process.kill(0, Integer(File.read(paths["pid"])))
        raise "nested leaf survived owner cleanup"
      rescue Errno::ESRCH
        # Reaped before the owner returned and before scratch cleanup.
      end
      TestRunnerTests.check(!File.exist?(paths["escaped"]) &&
        File.readlines(paths["order"], chomp: true) == (0..depth).map(&:to_s),
        "nested owners did not unwind bottom-up")
    end
  end
end
puts "Nested Ruby owners: PASS (one/three Ruby layers; INT/TERM/HUP/deadline; leaf reaped before cleanup)"
