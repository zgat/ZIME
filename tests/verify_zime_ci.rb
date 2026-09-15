#!/usr/bin/env ruby
require "yaml"
require_relative "../scripts/lib/zime_release"
abort "usage: verify_zime_ci.rb" unless ARGV.empty?
root = File.expand_path("..", __dir__)
REQUIRED_GATES = ["./action-install.sh", "make --no-print-directory release",
  "tests/verify_development.sh core", "tests/verify_development.sh app",
  "tests/verify_visible_settings_fixture.sh --ui-test", "tests/verify_zime_coverage.sh",
  "scripts/run_swiftlint.sh", "scripts/run_periphery.sh",
  "tests/verify_release_automation.sh", "tests/verify_publication_owner.sh"].freeze

def gate_indices(job)
  REQUIRED_GATES.to_h do |command|
    index = job.fetch("steps").index do |step|
      # Require an actual standalone command, not a comment/echo or `|| true`.
      commands = step.fetch("run", "").split("&&").map(&:strip)
      commands.include?(command) && (commands - REQUIRED_GATES).empty? &&
        !step.key?("if") && !step.fetch("continue-on-error", false)
    end
    ZIMERelease.check(index, "missing or skippable CI command: #{command}")
    [command, index]
  end
end

def validate(workflows)
  workflows.each do |name, value|
    ZIMERelease.check(value["permissions"] == {"contents" => "read"}, "#{name}: excessive workflow permissions")
    text = value.to_s
    ZIMERelease.check(!text.match?(/secrets\.|community-signing|Ares-X\/Linnet|gh release|pull_request_target/), "#{name}: retired or privileged publication path")
    value.fetch("jobs").each_value do |job|
      ZIMERelease.check(!job.key?("permissions") || job["permissions"] == {"contents" => "read"}, "excessive job permissions")
      job.fetch("steps").each do |step|
        if step["uses"]
          ZIMERelease.check(step["uses"] == "./.github/actions/restore-locked-build-cache" ||
            step["uses"].match?(/@[0-9a-f]{40}\z/), "unpinned action")
        end
        if step.fetch("uses", "").start_with?("actions/checkout@")
          ZIMERelease.check(step.dig("with", "persist-credentials") == false && step.dig("with", "fetch-depth") == 0,
            "checkout credential/history policy")
        end
      end
    end
  end
  %w[commit-ci.yml pull-request-ci.yml].each do |name|
    flow = workflows.fetch(name)
    job = flow.fetch("jobs").fetch("product")
    ZIMERelease.check(job.dig("strategy", "matrix", "os") == %w[macos-15 macos-26], "missing macOS matrix")
    ZIMERelease.check(job["runs-on"] == '$' + '{{ matrix.os }}', "matrix is not used")
    gates = gate_indices(job)
    ZIMERelease.check(gates.fetch("./action-install.sh") < gates.fetch("tests/verify_development.sh core"), "test prerequisites reordered")
    if name == "pull-request-ci.yml"
      ZIMERelease.check(flow["on"] == ["pull_request"], "PR trigger changed")
      cache = job["steps"].find { |s| s["uses"] == "./.github/actions/restore-locked-build-cache" }
      ZIMERelease.check(cache.dig("with", "save") == false, "PR acquired cache write permission")
    end
  end
  release = workflows.fetch("release-ci.yml")
  ZIMERelease.check(release.fetch("on").keys == ["workflow_dispatch"], "release must be explicitly requested")
  job = release.fetch("jobs").fetch("candidate")
  ZIMERelease.check(job["if"] == "github.repository == 'zgat/ZIME'", "release repository guard changed")
  gates = gate_indices(job)
  steps = job.fetch("steps")
  archive_index = steps.index { |s| s.fetch("run", "").start_with?("make --no-print-directory archive ") &&
    !s["run"].match?(/[;&|\n]/) &&
    !s.key?("if") && !s.fetch("continue-on-error", false) }
  ZIMERelease.check(archive_index && gates.values.all? { |i| i < archive_index }, "release archive precedes required gates")
  ZIMERelease.check(gates.fetch("./action-install.sh") < gates.fetch("tests/verify_development.sh core") &&
    gates.fetch("make --no-print-directory release") < gates.fetch("tests/verify_development.sh app"), "release prerequisites reordered")
  upload_index = steps.index { |s| s.dig("with", "name") == "zime-verified-candidate" }
  upload = upload_index && steps[upload_index]
  ZIMERelease.check(upload && upload.dig("with", "if-no-files-found") == "error" &&
    upload.dig("with", "retention-days") == 3 && !upload.key?("if") && upload_index > archive_index,
    "candidate upload must require successful preceding validation")
end
workflows = %w[commit-ci.yml pull-request-ci.yml release-ci.yml].to_h do |name|
  [name, YAML.load_file(File.join(root, ".github/workflows", name))]
end
validate(workflows)
%w[verify_zime_coverage.sh verify_zime_online.sh verify_zime_acceptance.rb].each do |name|
  path = File.join(root, "tests", name)
  ZIMERelease.regular(path)
  ZIMERelease.check(File.executable?(path), "missing executable test: #{name}")
end
ui = File.read(File.join(root, "tests/SettingsUITests/SettingsUITests.swift"))
%w[testFiveSettingsPagesRemainAlive testTranslationDraftControlsDoNotRequestOrSaveCredentials
   testShortcutRecorderRejectsConflictsAndCancelsRecording
   testDataPageKeepsReleaseLinkVisibleAndDisclosesLocalTools].each do |test|
  ZIMERelease.check(ui.include?("func #{test}("), "missing current Settings workflow: #{test}")
end
ZIMERelease.check(ui.include?('"com.zime.inputmethod.ZIME.local-build.settings"') &&
  ui.include?('"ZIME.app"') && !ui.include?('"Data & Updates"') &&
  !ui.include?('"Natural Code"'), "Settings UI fixture regained retired product controls")
fixture = File.read(File.join(root, "tests/verify_visible_settings_fixture.sh"))
ZIMERelease.check(fixture.include?("isolated UI account has existing development preferences") &&
  fixture.include?('LINNET_ISOLATED_UI_TEST_DESKTOP'), "UI fixture lost its isolation/refusal boundaries")
ZIMERelease.run("ruby", File.join(root, "tests/verify_zime_acceptance.rb"), "--self-test")
output, error, status = Open3.capture3("bash", File.join(root, "tests/verify_zime_online.sh"))
ZIMERelease.check(status.exitstatus == 64 && (output + error).include?("NOT_EXERCISED"),
  "online test no longer refuses implicit credential/network access")
mutations = [
  ->(w) { w["pull-request-ci.yml"]["permissions"]["contents"] = "write" },
  ->(w) { w["release-ci.yml"]["on"] = {"push" => {}} },
  ->(w) { w["commit-ci.yml"]["jobs"]["product"]["strategy"]["matrix"]["os"].pop },
  ->(w) { w["release-ci.yml"]["jobs"]["candidate"]["if"] = "true" },
  ->(w) { w["pull-request-ci.yml"]["jobs"]["product"]["steps"].reject! { |s| s["run"] == "tests/verify_development.sh core" } },
  ->(w) { w["commit-ci.yml"]["jobs"]["product"]["steps"][0]["uses"] = "actions/checkout@main" },
  ->(w) { w["pull-request-ci.yml"]["jobs"]["product"]["steps"][1]["with"]["save"] = true }
]
REQUIRED_GATES.each do |command|
  %i[delete skip tolerate echo short_circuit].each do |mode|
    mutations << ->(w) {
      steps = w["release-ci.yml"]["jobs"]["candidate"]["steps"]
      step = steps.find { |s| s.fetch("run", "").split(/&&|\n/).map(&:strip).include?(command) }
      case mode
      when :delete then steps.delete(step)
      when :skip then step["if"] = "false"
      when :tolerate then step["continue-on-error"] = true
      when :echo then step["run"] = "echo " + step["run"].gsub("&&", "; echo")
      when :short_circuit then step["run"] = "false && " + step["run"]
      end
    }
  end
end
mutations << ->(w) {
  steps = w["release-ci.yml"]["jobs"]["candidate"]["steps"]
  step = steps.find { |s| s["run"] == "tests/verify_zime_coverage.sh" }
  steps.delete(step); steps << step
}
mutations << ->(w) {
  steps = w["release-ci.yml"]["jobs"]["candidate"]["steps"]
  step = steps.find { |s| s.dig("with", "name") == "zime-verified-candidate" }
  steps.delete(step); steps.unshift(step)
}
mutations.each do |mutation|
  copy = Marshal.load(Marshal.dump(workflows)); mutation.call(copy)
  begin
    validate(copy)
  rescue ZIMERelease::Invalid
    next
  end
  abort "CI negative case was incorrectly accepted"
end
puts "ZIME CI: PASS (2 macOS runners, core/App/UI/coverage, pinned read-only workflows, no automatic publication, #{mutations.size} negative cases)"
