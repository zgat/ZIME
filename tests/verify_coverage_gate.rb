#!/usr/bin/env ruby
require_relative "zime_coverage_gate"
require "tmpdir"
require "fileutils"
require "rbconfig"
require_relative "test_process"
policy = {"scope" => ["sources/a.swift"],
  "minimums" => {"sources/a.swift" => {"lines" => 90.0, "functions" => 80.0, "covered_functions" => 8}}}
document = {"type" => "llvm.coverage.json.export", "data" => [{"files" => [{
  "filename" => "/fixture/sources/a.swift", "summary" => {
    "lines" => {"count" => 100, "covered" => 90},
    "functions" => {"count" => 10, "covered" => 8},
    "regions" => {"count" => 100, "covered" => 20}
  }}]}]}
ZIMECoverageGate.validate(document, policy, "/fixture")
mutations = [
  ->(d) { d["data"][0]["files"][0]["summary"]["lines"]["covered"] = 89 },
  ->(d) { d["data"][0]["files"][0]["summary"]["functions"]["covered"] = 7 },
  ->(d) { d["data"][0]["files"][0]["summary"]["functions"] = {"count" => 7, "covered" => 7} },
  ->(d) { d["data"][0]["files"].clear },
  ->(d) { d["data"][0]["files"] *= 2 },
  ->(d) { d["data"][0]["files"][0]["filename"] = "/elsewhere/sources/a.swift" },
  ->(d) { d["data"][0]["files"][0]["filename"] = "/fixture/sources/b.swift" },
  ->(d) { d["data"][0]["files"][0]["summary"]["lines"]["count"] = 0 },
  ->(d) { d["data"][0]["files"][0]["summary"]["lines"]["covered"] = 101 },
  ->(d) { d["data"][0]["files"][0]["summary"]["lines"]["covered"] = Float::NAN },
  ->(d) { d.delete("data") }
]
mutations.each do |mutation|
  copy = Marshal.load(Marshal.dump(document))
  mutation.call(copy)
  begin
    ZIMECoverageGate.validate(copy, policy, "/fixture")
  rescue ZIMECoverageGate::Invalid
    next
  end
  abort "coverage negative case accepted"
end
Dir.mktmpdir("zime-coverage-provenance-") do |root|
  bin = File.join(root, "bin")
  Dir.mkdir(bin)
  git = File.join(bin, "git")
  File.write(git, <<~RUBY)
    #!/usr/bin/ruby
    mode = ENV.fetch("COVERAGE_GIT_FIXTURE")
    command = ARGV.fetch(2)
    exit 42 if mode == command + "-failure"
    if command == "rev-parse"
      puts(mode == "invalid" ? "invalid" : (mode == "mismatch" ? "b" : "a") * 40)
    elsif command == "status"
      puts " M source.swift" if mode == "dirty"
    else
      abort "unexpected Git command"
    end
  RUBY
  File.chmod(0700, git)
  current_policy = JSON.parse(File.read(File.join(__dir__, "zime_coverage_policy.json")))
  coverage = {"type" => "llvm.coverage.json.export", "data" => [{"files" => current_policy.fetch("scope").map { |name|
    {"filename" => File.join(root, name), "summary" => %w[lines functions regions].to_h { |kind|
      [kind, {"count" => 1000, "covered" => 1000}]
    }}
  }}]}
  [["clean", "a" * 40, 0], ["dirty", "a" * 40, 0], ["rev-parse-failure", "a" * 40, 1],
    ["status-failure", "a" * 40, 1], ["invalid", "a" * 40, 1], ["mismatch", "a" * 40, 1],
    ["clean", "", 1], ["clean", "invalid", 1]].each_with_index do |(mode, revision, expected), index|
    report = File.join(root, index.to_s)
    Dir.mkdir(report)
    File.write(File.join(report, "coverage.json"), JSON.generate(coverage))
    out, err, status = TestProcess.capture({"PATH" => "#{bin}:#{ENV.fetch('PATH')}", "COVERAGE_GIT_FIXTURE" => mode},
      RbConfig.ruby, File.join(__dir__, "zime_coverage_gate.rb"), root, report, revision, timeout: 15)
    summary = File.join(report, "summary.json")
    raise "coverage provenance failed open: #{mode}/#{revision}: #{out}#{err}" unless
      status.exitstatus == expected && File.exist?(summary) == (expected == 0)
    next unless expected == 0
    result = JSON.parse(File.read(summary))
    raise "coverage provenance incorrectly recorded" unless result["source_revision"] == revision &&
      result["source_dirty"] == (mode == "dirty")
  end
end
puts "Coverage gate: PASS (#{mutations.size} regression/scope/corruption negative cases; eight provenance cases)"
