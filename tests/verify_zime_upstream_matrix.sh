#!/usr/bin/env bash
# Compare retained pre-upgrade fixtures to current locked data without touching
# an installed IME. Output is an audit, not a general linguistic quality score.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "${root}"
audit="${1:?usage: retained-baseline-directory}"
[[ -d "${audit}/baseline-shared" && -d "${audit}/baseline-lib" && ! -e "${audit}/matrix" ]]
matrix="${audit}/matrix"
mkdir "${matrix}"
for edition in old new; do
  shared="${matrix}/${edition}-shared"
  user="${matrix}/${edition}-user"
  mkdir -p "${shared}/opencc" "${user}"
  if [[ "${edition}" == old ]]; then
    cp -R -X "${audit}/baseline-shared/." "${shared}/"
    runtime="${audit}/baseline-lib"
    deployer="${audit}/baseline-bin/rime_deployer"
  else
    cp -R -X data/plum/. "${shared}/"
    cp -R -X data/opencc/. "${shared}/opencc/"
    runtime="${root}/lib"
    deployer="${root}/bin/rime_deployer"
  fi
  ruby -ryaml -e '
    path = ARGV.fetch(0)
    value = YAML.load_file(path)
    value.fetch("grammar")["language"] = "wanxiang-lts-zh-hans"
    File.write(path, YAML.dump(value))
  ' "${shared}/linnet_grammar_active.yaml"
  export DYLD_LIBRARY_PATH="${runtime}:${runtime}/rime-plugins"
  "${deployer}" --build "${user}" "${shared}" "${user}/build" > "${matrix}/${edition}-deploy.log" 2>&1
  xcrun clang++ -isysroot "$(xcrun --show-sdk-path)" -std=c++17 -O2 -Wall -Wextra -Werror \
    -isystem librime/dist/include tests/rime_grammar_probe.cc "${runtime}/librime.1.dylib" \
    -o "${matrix}/${edition}-probe"
  for keys in ni nihao key shuai feic shurufa abeierjiang shengchengshirengongzhineng \
      wojintianxiangqugongyuan womenmingtianzaijian b; do
    "${matrix}/${edition}-probe" "${shared}" "${user}" "${keys}" \
      > "${matrix}/${edition}-${keys}.out" 2> "${matrix}/${edition}-${keys}.err"
  done
done
ruby -e '
  root = ARGV.fetch(0)
  puts "keys\told_top\tnew_top\told_ms\tnew_ms"
  Dir.glob(File.join(root, "new-*.out")).sort.each do |path|
    keys = File.basename(path).delete_prefix("new-").delete_suffix(".out")
    tops = %w[old new].map { |v| File.readlines(File.join(root, "#{v}-#{keys}.out")).first.split("\t")[1] }
    times = %w[old new].map { |v| File.read(File.join(root, "#{v}-#{keys}.err"))[/cold_ms=(\d+)/,1].to_i }
    abort "empty candidates: #{keys}" if tops.any?(&:empty?)
    abort "cold latency > 750 ms: #{keys}" if times[1] > 750
    puts ([keys] + tops + times).join("\t")
  end
' "${matrix}" | tee "${matrix}/comparison.tsv"
echo 'ZIME upstream matrix: PASS (11 cold queries; retained old vs new LTS; inspect candidate changes in comparison.tsv)'
