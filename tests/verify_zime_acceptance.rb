#!/usr/bin/env ruby
# Human evidence is attested, never inferred from a passing unit test.
require "json"
require "time"
CASES = %w[macos_13 macos_14 macos_15 macos_26 settings_ui
  textedit safari chrome vscode notes terminal wechat_primary wechat_secondary
  fresh_install core_upgrade full_upgrade repeated_upgrade uninstall
  online_compatible online_deepl online_baidu online_tencent endurance].freeze
def verify(value, revision)
  raise "revision mismatch" unless revision.match?(/\A[0-9a-f]{40}\z/) && value["source_revision"] == revision
  rows = value.fetch("cases")
  raise "missing or duplicate cases" unless rows.map { |r| r["id"] }.sort == CASES.sort
  rows.each do |row|
    raise "invalid status" unless %w[PASS FAIL NOT_EXERCISED].include?(row["status"])
    next if row["status"] == "NOT_EXERCISED"
    %w[tester environment evidence tested_at].each do |field|
      raise "missing #{field}: #{row['id']}" unless row[field].is_a?(String) && !row[field].strip.empty?
    end
    raise "future evidence timestamp" if Time.iso8601(row["tested_at"]) > Time.now + 300
  end
  rows.reject { |row| row["status"] == "PASS" }.map { |row| "#{row['id']}: #{row['status']}" }
end
def template(revision)
  {"format" => 1, "source_revision" => revision, "cases" => CASES.map { |id|
    {"id" => id, "status" => "NOT_EXERCISED", "tester" => "", "environment" => "", "evidence" => "", "tested_at" => ""}}}
end
begin
  case ARGV
  when ["--template"]
    puts JSON.pretty_generate(template("<full-tested-source-revision>"))
  when ["--self-test"]
    revision = "a" * 40
    document = template(revision)
    raise "unexecuted receipt passed" unless verify(document, revision).size == CASES.size
    valid = Marshal.load(Marshal.dump(document))
    valid["cases"].each { |row| row.merge!("status" => "PASS", "tester" => "synthetic fixture",
      "environment" => "synthetic, not UAT", "evidence" => "fixture", "tested_at" => Time.now.utc.iso8601) }
    raise "valid synthetic receipt rejected" unless verify(valid, revision).empty?
    [->(d) { d["source_revision"] = "b" * 40 },
     ->(d) { d["cases"].pop }, ->(d) { d["cases"][0]["evidence"] = "" },
     ->(d) { d["cases"][0]["status"] = "SKIP" },
     ->(d) { d["cases"][0]["tested_at"] = "2999-01-01T00:00:00Z" }].each do |mutate|
      changed = Marshal.load(Marshal.dump(valid)); mutate.call(changed)
      rejected = false
      begin
        verify(changed, revision)
      rescue StandardError
        rejected = true
      end
      raise "invalid evidence accepted" unless rejected
    end
    puts "ZIME acceptance receipt self-test: PASS (synthetic only; no real UAT claimed)"
  else
    abort "usage: #{$0} --template | --self-test | RECEIPT.json SOURCE_REVISION" unless ARGV.size == 2
    gaps = verify(JSON.parse(File.read(ARGV[0])), ARGV[1])
    unless gaps.empty?
      warn "INCOMPLETE:\n" + gaps.join("\n")
      exit 1
    end
    puts "PASS: complete maintainer-attested evidence inventory; authenticity requires human review."
  end
rescue StandardError => e
  warn "FAIL: #{e.message}"
  exit 1
end
