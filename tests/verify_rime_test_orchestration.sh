#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${repo_root}"

ruby -ropen3 - tests/rime_smoke_test.cc tests/verify_rime_runtime.sh <<'RUBY'
smoke = File.binread(ARGV.fetch(0))
runtime = File.binread(ARGV.fetch(1))

warmup = smoke[/constexpr size_t kLatencyWarmupSamples = (\d+);/, 1]&.to_i
samples = smoke[/constexpr size_t kLatencySamples = (\d+);/, 1]&.to_i
abort "Rime latency sample contract is missing" unless warmup && samples
abort "Rime latency warm-up regained benchmark-scale repetition" unless warmup <= 1_024
abort "Rime latency gate regained benchmark-scale repetition" unless samples <= 8_192
abort "Rime p99 gate has fewer than 80 tail observations" unless samples / 100 >= 80

abort "Rime profile gate regained the full trigger/profile Cartesian product" if
  runtime.include?("for trigger in semicolon vertical_bar; do")

retired_probes = %w[
  --shift-probe --core-shift-overlap-probe --prediction-layout-probe
  --partial-return-probe --single-key-ranking-probe
]
returned = retired_probes.select { |probe| smoke.include?(probe) || runtime.include?(probe) }
abort "retired overlapping Rime probes returned: #{returned.join(", ")}" unless returned.empty?
listed, error, status = Open3.capture3('bash', ARGV.fetch(1), '--list-probes')
abort error unless status.success?
probes = listed.lines.map(&:strip)
abort "probe inventory contains duplicates" unless probes == probes.uniq
required = %w[--profile-key-matrix-probe --zime-shortcuts-probe --zime-bilingual-probe
  --zime-alphanumeric-probe --zime-case-probe --zime-paging-probe --zime-soak-probe]
abort "required native probe is absent" unless (required - probes).empty?
required.each do |probe|
  flag = probe.delete_prefix('--').tr('-', '_')
  abort "native dispatch missing for #{probe}" unless smoke.match?(/if \(#{flag}\) \{/)
end
gate_path = 'tests/verify_development.sh'
gate = File.binread(gate_path)
gate_probes = gate[/^  for probe in (.+); do$/, 1]&.split || []
required.each do |probe|
  if probe == '--zime-alphanumeric-probe'
    abort "duplicate alphanumeric probe in unified gate" if gate_probes.include?(probe)
    abort "default matrix lost alphanumeric coverage" unless
      smoke.scan(/ExpectAlphanumericComposition\s*\(api\)\s*;/).size == 2
  else
    abort "unified native gate omits #{probe}" unless gate_probes.include?(probe)
  end
end
abort "unified probes contain duplicates" unless gate_probes == gate_probes.uniq
%w[verify_swift_units.sh verify_zime.sh verify_zime_translation.sh
   verify_english_data_projection.sh verify_rime_runtime.sh
   verify_test_process.rb verify_compile_artifact_cache.rb
   verify_swift_test_cache.rb verify_cxx_test_cache.rb].each do |script|
  abort "unified core owner missing: #{script}" unless gate.include?("tests/#{script}")
end
[%w[--unknown-probe], %w[--zime-shortcuts-probe extra], %w[--list-probes extra]].each do |args|
  _, _, status = Open3.capture3('bash', ARGV.fetch(1), *args)
  abort "invalid runtime arguments were accepted" unless status.exitstatus == 64
end
[%w[unknown], %w[core extra]].each do |args|
  _, _, status = Open3.capture3('bash', gate_path, *args)
  abort "invalid development arguments were accepted" unless status.exitstatus == 2
end
%w[lean_data_trust runtime_footprint product package_architecture input_process_offline
   action_publication release_metadata data_channel_release package_lifecycle].each do |name|
  output, error, status = Open3.capture3('bash', "tests/verify_#{name}.sh")
  abort "historical test must fail clearly, not claim PASS: #{name}" unless
    status.exitstatus == 64 && (output + error).include?('ARCHIVED:')
end
abort "page-size matrix omits a supported setting" unless
  runtime.match?(/^for page_size in 3 4 5 6 7 8 9; do$/)

remaining_punctuation = smoke[/void ExpectNonFormalPunctuationBoundaries.*?^\}/m]
abort "the non-formal punctuation owner is missing" unless remaining_punctuation
formal_symbols = ["/", ",", ".", ":", ";", "'", "[", "]", "-", "=", "|", "+"]
duplicated = formal_symbols.select do |symbol|
  remaining_punctuation.match?(/,\s*"#{Regexp.escape(symbol)}",/)
end
abort "formal symbols returned to the generic punctuation owner: #{duplicated.join}" unless
  duplicated.empty?

matrix_source = runtime[/profile_cases=\(\n(.*?)\n\)/m, 1]
abort "Rime profile matrix is missing" unless matrix_source
actual = matrix_source.scan(/'([^']+)'/).flatten
expected = [
  "vertical_bar:natural",
  "vertical_bar:full_pinyin",
  "vertical_bar:flypy",
  "vertical_bar:microsoft",
  "vertical_bar:sogou",
  "vertical_bar:abc",
  "vertical_bar:ziguang",
  "vertical_bar:jiajia",
  "semicolon:microsoft",
]
abort "Rime profile matrix lost an owner or regained a redundant cross-product" unless
  actual == expected
RUBY

echo "Linnet Rime test orchestration: PASS (bounded latency sample and orthogonal profile/trigger matrix)"
