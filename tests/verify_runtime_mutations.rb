#!/usr/bin/env ruby
# Re-run the real owner tests against private semantic mutations. An unrelated
# crash/compiler failure is not evidence that the intended assertion works.
require "tmpdir"
require "rbconfig"
require_relative "test_process"

files = %w[test_process.rb run_test_process.rb exec_test_owner.rb test_runner.sh swift_test_scratch.sh
  verify_test_runner.rb verify_test_owner_chain.rb verify_nested_test_owner.rb verify_swift_units.sh verify_development.sh]
original = files.to_h { |file| [file, File.binread(File.join(__dir__, file))] }
mutations = {
  "lost-stdin" => ["verify_test_runner.rb", "test_runner.sh", '"$@" <&0 &', '"$@" &', "shell runtime IO/argv/status changed"],
  "cancel-reported-success" => ["verify_test_runner.rb", "run_test_process.rb", 'exit(128 + Signal.list.fetch(error.signal))',
    'exit 0', "CLI cancellation status lost"],
  "nested-foreground-wait" => ["verify_test_owner_chain.rb", "verify_swift_units.sh",
    'linnet_test_call bash tests/verify_swift_scratch.sh', 'bash tests/verify_swift_scratch.sh',
    "cancellation did not reach leaf before cleanup"],
  "inherited-int-ignored" => ["verify_test_owner_chain.rb", "exec_test_owner.rb",
    'Signal.trap(signal, "DEFAULT")', 'Signal.trap(signal, signal == "INT" ? "IGNORE" : "DEFAULT")',
    "cancellation did not reach leaf before cleanup"],
  "nested-owner-killed-first" => ["verify_nested_test_owner.rb", "test_process.rb",
    'if owner && !status && !killed', 'if false', "nested leaf survived owner cleanup"],
  "cancel-before-registration" => ["verify_test_runner.rb", "test_runner.sh",
    'if [[ "${LINNET_TEST_RUNNER_LAUNCHING}" -eq 1 ]]; then', 'if false; then',
    "launch-window cancellation escaped registration/cleanup"]
}
Dir.mktmpdir("zime runtime mutations-") do |root|
  baselines = mutations.values.map(&:first).uniq
  (baselines + mutations.keys).each do |name|
    original.each { |file, body| File.binwrite(File.join(root, file), body) }
    baseline = baselines.include?(name)
    test = name
    unless baseline
      test, file, before, after, expected = mutations.fetch(name)
      body = original.fetch(file)
      raise "ambiguous runtime mutation: #{name}" unless body.scan(before).size == 1
      File.binwrite(File.join(root, file), body.sub(before, after))
    end
    marker = {"verify_test_runner.rb" => "Test runtime owner: PASS",
      "verify_test_owner_chain.rb" => "Test owner chain: PASS",
      "verify_nested_test_owner.rb" => "Nested Ruby owners: PASS"}.fetch(test)
    # The suite includes a 30-second compiler budget plus many IO/cancellation
    # cases. Its enclosing watchdog must not consume the leaf's entire budget.
    out, err, status = TestProcess.capture(RbConfig.ruby, File.join(root, test), timeout: 120, owner: true)
    if baseline
      raise "runtime mutation baseline failed: #{out} #{err}" unless status.success? && out.include?(marker)
    else
      raise "runtime mutation escaped or failed for the wrong reason: #{name}: #{status.inspect}\n#{out}#{err}" unless
        status.exitstatus == 1 && err.include?(expected) && !out.include?(marker)
      puts "Runtime mutation rejected: #{name}"
    end
  end
end
puts "Runtime mutation gate: PASS (three executed baselines; #{mutations.size} semantic defects; exact assertion failures)"
