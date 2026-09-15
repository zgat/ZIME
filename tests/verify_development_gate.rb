#!/usr/bin/env ruby
# Execute the real shell control flow in a private repo, replacing only leaf
# commands. No test-only bypass is added to the production entrypoint.
require "fileutils"
require "tmpdir"
require_relative "test_process"

module DevelopmentGateTest
  class Mismatch < StandardError; end
  APP = "build/Local/Build/Products/Release/ZIME.app".freeze
  PREPARE = ["make\t--no-print-directory\tenglish-data-generator", "tests/verify_english_data_projection.sh"].freeze
  INFRASTRUCTURE = %w[verify_coverage_gate.rb verify_test_process.rb verify_compile_artifact_cache.rb
    verify_swift_test_cache.rb verify_cxx_test_cache.rb verify_development_gate.rb
    verify_rime_test_orchestration.sh verify_publication_owner.sh verify_release_automation.sh
    verify_zime_installer.sh verify_zime_privacy.sh].map { |name| "tests/#{name}" }.freeze
  TRANSLATION = %w[tests/verify_zime.sh tests/verify_zime_translation.sh].freeze
  SWIFT = ["tests/verify_swift_units.sh", *TRANSLATION, "tests/verify_candidate_translation_mutations.rb"].freeze
  NATIVE = [*%w[verify_lua_lifetime.sh verify_data_release_baseline.sh verify_chinese_upstream_workflow.sh].map { |n| "tests/#{n}" },
    "scripts/upstream-sync\tverify",
    *%w[verify_chinese_source_projection.sh verify_locked_release_asset.sh verify_chinese_grammar.sh
      verify_profile_golden.rb verify_chinese_learning_policy.sh verify_rime_runtime.sh].map { |n| "tests/#{n}" },
    *%w[zime-shortcuts zime-bilingual zime-case zime-paging profile-key-matrix zime-soak].map { |n| "tests/verify_rime_runtime.sh\t--#{n}-probe" }].freeze
  APP_CHECKS = ["tests/verify_zime_app.sh\t#{APP}\tlocal", "tests/verify_visible_settings_fixture.sh\t--verify\tlocal",
    *PREPARE, "tests/generate_m2_fixtures.rb\t--check", "scripts/build-privacy\tscan\t#{APP}"].freeze
  QUALITY = ["swiftlint\tlint\t--strict\t--config\t.swiftlint.yml", "scripts/run_periphery.sh", "tests/verify_zime_coverage.sh"].freeze
  PLANS = {
    "quick" => INFRASTRUCTURE + TRANSLATION,
    "full" => PREPARE + INFRASTRUCTURE + SWIFT + NATIVE,
    "core" => PREPARE + INFRASTRUCTURE + SWIFT + NATIVE,
    "swift" => INFRASTRUCTURE + SWIFT,
    "rime" => ["tests/verify_rime_test_orchestration.sh"] + NATIVE,
    "app" => APP_CHECKS,
    "all" => INFRASTRUCTURE + APP_CHECKS + SWIFT + NATIVE,
    "release" => INFRASTRUCTURE + APP_CHECKS + SWIFT + NATIVE + QUALITY
  }.freeze

  def self.write_executable(path, body)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    File.chmod(0700, path)
  end

  def self.fixture(root)
    recorder = File.join(root, "recorder")
    write_executable(recorder, <<~'SH')
      #!/bin/sh
      command=$1
      shift
      line=$command
      tab=$(printf '\t')
      for argument do
        case "$argument" in "$GATE_TEST_ROOT"/*) argument=${argument#"$GATE_TEST_ROOT"/} ;; esac
        line="$line$tab$argument"
      done
      printf '%s\n' "$line" >> "$GATE_TEST_TRACE"
      if [ -n "$GATE_FAIL_AT" ]; then
        count=0
        while IFS= read -r recorded; do count=$((count + 1)); done < "$GATE_TEST_TRACE"
        if [ "$count" -eq "$GATE_FAIL_AT" ]; then exit 37; fi
      fi
    SH
    names = PLANS.values.flatten.map { |line| line.split("\t").first }.uniq
    names.each do |name|
      path = File.join(root, name.include?("/") ? name : "bin/#{name}")
      write_executable(path, "#!/bin/sh\nexec \"$GATE_RECORDER\" '#{name}' \"$@\"\n")
    end
    %w[bash ruby].each do |name|
      write_executable(File.join(root, "bin", name), "#!/bin/sh\nexec \"$GATE_RECORDER\" \"$@\"\n")
    end
    write_executable(File.join(root, "bin/git"), "#!/bin/sh\nprintf '%s\\n' config/LinnetProduct.xcconfig\n")
    %w[config data/plum data/opencc lib].each { |path| FileUtils.mkdir_p(File.join(root, path)) }
    input = File.join(root, "config/LinnetProduct.xcconfig")
    File.write(input, "fixture\n")
    File.utime(Time.at(1), Time.at(1), input)
    [[APP, "ZIME", "com.zime.inputmethod.ZIME.local-build"],
      ["build/Local/Build/Products/Release/Settings.app", "Settings", "com.zime.inputmethod.ZIME.local-build.settings"],
      ["#{APP}/Contents/Applications/Settings.app", "Settings", "com.zime.inputmethod.ZIME.local-build.settings"]].each do |app, executable, identifier|
      write_executable(File.join(root, app, "Contents/MacOS", executable), "#!/bin/sh\nexit 0\n")
      File.write(File.join(root, app, "Contents/Info.plist"),
        "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>#{identifier}</string></dict></plist>")
    end
    File.write(File.join(root, "build/Local/Build/Products/Release/.linnet-build-complete"), "fixture\n")
  end

  def self.run(root, arguments, fail_at = nil)
    trace = File.join(root, "trace")
    File.write(trace, "")
    environment = {"PATH" => "#{root}/bin:#{ENV.fetch('PATH')}", "GATE_TEST_ROOT" => root,
      "GATE_RECORDER" => File.join(root, "recorder"), "GATE_TEST_TRACE" => trace,
      "GATE_FAIL_AT" => fail_at&.to_s}
    out, err, status = TestProcess.capture(environment, "/bin/bash",
      File.join(root, "tests/verify_development.sh"), *arguments, timeout: 20)
    [status.exitstatus, File.readlines(trace, chomp: true), out + err]
  end

  def self.validate(root, profile, fail_at = nil, arguments = [profile])
    expected = PLANS.fetch(profile)
    expected = expected.take(fail_at) if fail_at
    code, actual, output = run(root, arguments, fail_at)
    raise Mismatch, "#{profile}: wrong status #{code}: #{output}" unless code == (fail_at ? 37 : 0)
    raise Mismatch, "#{profile}: wrong execution plan\nexpected=#{expected.inspect}\nactual=#{actual.inspect}" unless actual == expected
  end

  def self.check(root, source)
    gate = File.join(root, "tests/verify_development.sh")
    File.write(gate, source)
    PLANS.each_key { |profile| validate(root, profile) }
    validate(root, "all", nil, [])
    [["unknown"], ["core", "extra"]].each do |arguments|
      code, trace, = run(root, arguments)
      raise "invalid profile did work or succeeded" unless code == 2 && trace.empty?
    end
    # Every release leaf must stop all later work. Also cover core/full's
    # prerequisite branch, which is deliberately absent from release.
    failures = 0
    {"release" => (1..PLANS.fetch("release").size), "full" => (1..PREPARE.size)}.each do |profile, indices|
      indices.each { |index| validate(root, profile, index); failures += 1 }
    end
    call = '  if [[ "${run_swift}" -eq 1 ]]; then ruby tests/verify_candidate_translation_mutations.rb; fi'
    raise "mutation owner changed" unless source.lines.map(&:chomp).count(call) == 1
    mutations = {
      "commented-call" => [source.sub(call, "  # ruby tests/verify_candidate_translation_mutations.rb"), nil],
      "echo-only" => [source.sub(call, "  echo tests/verify_candidate_translation_mutations.rb"), nil],
      "false-branch" => [source.sub(call, call.sub('"${run_swift}" -eq 1', "0 -eq 1")), nil],
      "duplicate-call" => [source.sub(call, call + "\n" + call), nil],
      "swallowed-failure" => [source.sub(call, call.sub(".rb; fi", ".rb || true; fi")),
        PLANS.fetch("release").index("tests/verify_candidate_translation_mutations.rb") + 1],
      "missing-coverage" => [source.sub("  tests/verify_zime_coverage.sh", "  # tests/verify_zime_coverage.sh"), nil],
      "duplicate-native-probe" => [source.sub('    tests/verify_rime_runtime.sh "${probe}"',
        '    tests/verify_rime_runtime.sh "${probe}"' + "\n" + '    tests/verify_rime_runtime.sh "${probe}"'), nil]
    }
    mutations.each do |name, (mutated, failure)|
      raise "mutation did not change script: #{name}" if mutated == source
      File.write(gate, mutated)
      _, err, status = TestProcess.capture("/bin/bash", "-n", gate, timeout: 5)
      raise "invalid mutation: #{name}: #{err}" unless status.success?
      begin
        validate(root, "release", failure)
      rescue Mismatch
        next
      end
      raise "development gate mutation escaped: #{name}"
    end
    puts "Development gate: PASS (8 profiles/default/invalid args; #{failures} fail-fast checks; #{mutations.size} semantic mutations; isolated leaf commands)"
  end
end

if $PROGRAM_NAME == __FILE__
  abort "usage: verify_development_gate.rb" unless ARGV.empty?
  source = File.read(File.join(__dir__, "verify_development.sh"))
  Dir.mktmpdir("zime-development-gate-") do |root|
    root = File.realpath(root)
    DevelopmentGateTest.fixture(root)
    DevelopmentGateTest.check(root, source)
  end
end
