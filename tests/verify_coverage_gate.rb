#!/usr/bin/env ruby
require_relative "zime_coverage_gate"
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
puts "Coverage gate: PASS (#{mutations.size} regression/scope/corruption negative cases)"
