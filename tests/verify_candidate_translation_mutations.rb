#!/usr/bin/env ruby
# Small semantic mutation set for the boundary owner. Compile temporary copies
# of the real source; never modify the checkout or access a real online service.
require_relative "test_process"
require "tmpdir"

abort "usage: #{$PROGRAM_NAME}" unless ARGV.empty?
root = File.expand_path("..", __dir__)
Dir.chdir(root)
source = File.read("sources/ZIMECandidateTranslator.swift")
runner = <<~SWIFT
  import Foundation
  @main struct ZIMECandidateTranslatorTests {
    @MainActor static func main() async throws {
      let lexicon = ZIMELocalLexicon(url: URL(fileURLWithPath: "resources/zime-cedict.sqlite3"))
      try await runBoundaries(lexicon: lexicon)
    }
  }
SWIFT
sources = %w[LinnetPackContract.swift LinnetDataChannel.swift LinnetDataRegistry.swift
  LinnetDirectoryDelta.swift LinnetDataRegistryTransactions.swift LinnetDataRegistryStorage.swift
  LinnetSettings/SettingsContract.swift LinnetCandidatePresentation.swift ZIMELocalLexicon.swift
  ZIMETranslationProvider.swift].map { |name| File.join(root, "sources", name) }
mutations = {
  "ttl-never-expires" => ["$0.expires > timing.now() ? $0.text : nil", "$0.text",
    "candidate translator fixture event deadline exceeded"],
  "capacity-too-large" => ["cache.count >= 512", "cache.count >= 1024",
    "candidate translator fixture event deadline exceeded"],
  "evict-newest" => ["$0.value.expires < $1.value.expires", "$0.value.expires > $1.value.expires",
    "capacity eviction removed a newer entry"],
  "cooldown-too-short" => ["addingTimeInterval(30)", "addingTimeInterval(29)",
    "failed provider bypassed its 30-second cooldown"],
  "allow-email" => ['!term.contains("@")', 'true', "ineligible term was scheduled"],
  "allow-65-characters" => ["term.count <= 64", "term.count <= 65", "ineligible term was scheduled"],
  "duplicates" => ["if !missing.contains(term) { missing.append(term) }", "missing.append(term)",
    "remote lookup crossed page, duplicate or nine-term boundary"],
  "page-cap" => [".prefix(9)", ".prefix(10)", "candidate translator fixture event deadline exceeded"],
  "hidden-query" => ["guard showTranslation else { cancel(); return snapshot }",
    "guard showTranslation else { return snapshot }", "candidate translator fixture event deadline exceeded"],
  "consent-after-wait" => [
    "guard self.generation == token, self.loadConfiguration().hasSameService(as: selected) else { return }\n          let value",
    "guard self.generation == token else { return }\n          let value",
    "consent withdrawal during rate-limit wait sent a second term"],
  "consent-before-wait" => [
    "try Task.checkCancellation()\n          guard self.generation == token, self.loadConfiguration().hasSameService(as: selected) else { return }",
    "try Task.checkCancellation()\n          guard self.generation == token else { return }",
    "withdrawn consent entered another rate-limit wait"],
  "early-credentials" => ["try await sleep(400_000_000)",
    "_ = try self?.loadCredentials(selected.credentialAccount)\n        try await sleep(400_000_000)",
    "credentials accessed before debounce"],
  "stale-failure" => ["guard let self, self.generation == token else { return }",
    "guard let self else { return }", "stale failure refreshed the retired composition"]
}
Dir.mktmpdir("zime-translator-mutations-") do |dir|
  fixture = File.join(dir, "main.swift")
  candidate = File.join(dir, "ZIMECandidateTranslator.swift")
  executable = File.join(dir, "candidate-boundaries")
  File.write(fixture, runner)
  compile = lambda do |text|
    File.write(candidate, text)
    out, err, status = TestProcess.capture("xcrun", "swiftc", "-warnings-as-errors", "-parse-as-library",
      "-module-cache-path", File.join(root, "build/test-module-cache"),
      "-framework", "Security", "-framework", "AppKit", *sources, candidate, fixture,
      File.join(root, "tests/ZIMECandidateTranslatorBoundaryTests.swift"),
      File.join(root, "tests/ZIMECandidateTranslatorTestSupport.swift"), "-o", executable, timeout: 120)
    abort "mutation fixture failed to compile:\n#{out}#{err}" unless status.success?
  end
  compile.call(source)
  out, err, status = TestProcess.capture(executable, timeout: 20)
  abort "unmodified boundary fixture failed:\n#{out}#{err}" unless status.success? && out.include?("boundaries: PASS")
  mutations.each do |name, (before, after, expected)|
    abort "mutation owner changed: #{name}" unless source.scan(before).size == 1
    compile.call(source.sub(before, after))
    out, err, status = TestProcess.capture(executable, timeout: 20)
    abort "mutation escaped the expected assertion: #{name}\n#{out}#{err}" unless
      status.exitstatus == 1 && (out + err).include?("ZIME test assertion failed:") && (out + err).include?(expected)
    puts "Candidate translation mutation rejected: #{name}"
  end
end
puts "Candidate translation mutation gate: PASS (unchanged baseline and #{mutations.size} semantic defects)"
