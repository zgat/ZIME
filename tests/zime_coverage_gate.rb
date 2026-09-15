require "json"

module ZIMECoverageGate
  class Invalid < StandardError; end
  def self.check(condition, message)
    raise Invalid, message unless condition
  end

  def self.validate(document, policy, root)
    check(document.fetch("type") == "llvm.coverage.json.export", "unexpected coverage format")
    files = document.fetch("data").flat_map { |unit| unit.fetch("files") }
    prefix = File.expand_path(root) + "/"
    names = files.map { |file|
      path = file.fetch("filename")
      check(path.start_with?(prefix) && File.expand_path(path) == path, "unexpected source path: #{path}")
      path.delete_prefix(prefix)
    }
    scope = policy.fetch("scope")
    minimums = policy.fetch("minimums")
    check(scope.uniq == scope && !scope.empty?, "invalid policy scope")
    check(names.uniq == names, "duplicate source files")
    check(names.sort == scope.sort, "coverage scope drift: missing=#{scope - names}, extra=#{names - scope}")
    check(!minimums.empty? && (minimums.keys - scope).empty?, "invalid minimum scope")
    summaries = names.zip(files).to_h.transform_values { |file|
      %w[lines functions regions].to_h { |kind|
        metric = file.fetch("summary").fetch(kind)
        count, covered = metric.values_at("count", "covered")
        check(count.is_a?(Integer) && covered.is_a?(Integer) && count > 0 && covered.between?(0, count),
          "invalid coverage counts: #{kind}")
        [kind, {"count" => count, "covered" => covered, "percent" => 100.0 * covered / count}]
      }
    }
    minimums.each do |name, limits|
      %w[lines functions].each do |kind|
        floor = limits.fetch(kind)
        check(floor.is_a?(Numeric) && floor.finite? && floor > 0 && floor <= 100, "invalid coverage floor")
        actual = summaries.fetch(name).fetch(kind).fetch("percent")
        check(actual >= floor, "coverage regression: #{name} #{kind} #{actual.round(2)}% < #{floor}%")
      end
      floor = limits.fetch("covered_functions")
      check(floor.is_a?(Integer) && floor > 0, "invalid covered function floor")
      check(summaries[name]["functions"]["covered"] >= floor, "covered functions removed: #{name}")
    end
    totals = %w[lines functions regions].to_h { |kind|
      count = summaries.values.sum { |summary| summary[kind]["count"] }
      covered = summaries.values.sum { |summary| summary[kind]["covered"] }
      [kind, {"count" => count, "covered" => covered, "percent" => (100.0 * covered / count).round(2)}]
    }
    {"scope" => "selected Swift translation/settings-model/candidate-translator/installer fixtures and production dependencies; NOT whole-project coverage",
      "branch_coverage" => "not measured by this Swift instrumentation",
      "files" => summaries, "totals" => totals, "enforced_minimums" => minimums}
  rescue KeyError, TypeError, NoMethodError => error
    raise Invalid, "malformed coverage: #{error.message}"
  end
end

if $PROGRAM_NAME == __FILE__
  abort "usage: zime_coverage_gate.rb ROOT REPORT_DIR REVISION" unless ARGV.size == 3
  root, dir, revision = ARGV
  begin
    result = ZIMECoverageGate.validate(JSON.parse(File.read(File.join(dir, "coverage.json"))),
      JSON.parse(File.read(File.join(__dir__, "zime_coverage_policy.json"))), root)
    result["source_revision"] = revision
    result["source_dirty"] = !IO.popen(["git", "-C", root, "status", "--porcelain=v1"], &:read).empty?
    File.write(File.join(dir, "summary.json"), JSON.pretty_generate(result) + "\n")
    puts JSON.pretty_generate(result)
  rescue ZIMECoverageGate::Invalid => error
    abort error.message
  end
end
