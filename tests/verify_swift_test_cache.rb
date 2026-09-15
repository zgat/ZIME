#!/usr/bin/env ruby
require_relative "swift_test_cache"

def check(value, message)
  raise message unless value
end

compiler, _, status = TestProcess.capture("xcrun", "--find", "swiftc", timeout: 10)
check(status.success?, "Swift compiler missing")
sdk, _, status = TestProcess.capture("xcrun", "--show-sdk-path", timeout: 10)
check(status.success?, "SDK missing")
Dir.mktmpdir("zime-swift-cache-") do |dir|
  cache, output, modules = %w[cache output modules].map { |name| File.join(dir, name) }
  source, alias_source, alternate = %w[main.swift source.swift alternate.swift].map { |name| File.join(dir, name) }
  headers, alias_headers = %w[headers alias-headers].map { |name| File.join(dir, name) }
  FileUtils.mkdir_p(headers)
  File.write(source, "print(VALUE)\n")
  File.write(alternate, "print(VALUE + 10)\n")
  File.symlink(source, alias_source)
  File.symlink(headers, alias_headers)
  File.symlink(headers, File.join(headers, "cycle"))
  bridge = File.join(dir, "bridge.h")
  header = File.join(headers, "value.h")
  File.write(bridge, "#include <value.h>\n")
  File.write(header, "#define VALUE 1\n")
  # Keep the bridge outside the include tree but don't let its directory scan
  # ingest this cache's output/staging files, which legitimately change mid-build.
  bridge_dir = File.join(dir, "bridge")
  FileUtils.mkdir_p(bridge_dir)
  File.rename(bridge, File.join(bridge_dir, "bridge.h"))
  bridge = File.join(bridge_dir, "bridge.h")
  command = [compiler.strip, "-sdk", sdk.strip, "-module-cache-path", modules,
    "-I", alias_headers, "-import-objc-header", bridge, alias_source]
  run = ->(expected_hit, expected_value, args = command) {
    hit = SwiftTestCache.compile(dir, cache, output, "fixture-environment", args)
    check(hit == expected_hit, "wrong Swift cache decision: #{hit}, expected #{expected_hit}")
    out, err, status = TestProcess.capture(output, timeout: 5)
    check(status.success? && out == "#{expected_value}\n", "stale Swift executable: #{out} #{err}")
  }
  run.call(false, 1)
  run.call(true, 1)
  File.write(header, "#define VALUE 2\n")
  run.call(false, 2)
  run.call(true, 2)
  File.unlink(alias_source)
  File.symlink(alternate, alias_source)
  run.call(false, 12)
  run.call(false, 12, command + ["-O"])
  run.call(true, 12, command + ["-O"])
  # A new header, including beneath a symlinked -I path, changes the key even
  # when an old dependency list could not have named it yet.
  before = SwiftTestCache.inputs(dir, command)
  optional = File.join(headers, "optional.h")
  File.write(optional, "// newly available\n")
  check(SwiftTestCache.inputs(dir, command) != before, "new symlink-directory header was omitted")
  env_before = ENV["CPATH"]
  begin
    ENV["CPATH"] = alias_headers
    before = SwiftTestCache.inputs(dir, [compiler.strip, alias_source])
    File.write(header, "#define VALUE 3\n")
    check(SwiftTestCache.inputs(dir, [compiler.strip, alias_source]) != before, "CPATH contents not tracked")
  ensure
    ENV["CPATH"] = env_before
  end
  # Bash disables errexit inside an if condition. The reusable shell function
  # must still propagate a failed compilation, not return its final assignment.
  bad = File.join(dir, "bad.swift")
  File.write(bad, "this is not valid Swift {\n")
  stale = File.join(dir, "rejected")
  File.write(stale, "old-output")
  script = <<~'BASH'
    set -eu
    source "$1/tests/swift_test_cache.sh"
    linnet_swift_cache_init "$1" "$2"
    if linnet_swift_compile rejected -sdk "$LINNET_MACOS_SDK" "$3"; then
      echo "compiler failure was swallowed" >&2
      exit 3
    fi
  BASH
  out, err, status = TestProcess.capture({"LINNET_SWIFT_UNIT_CACHE_ROOT" => cache,
    "SWIFT_MODULECACHE_PATH" => modules, "CLANG_MODULE_CACHE_PATH" => modules},
    "bash", "-c", script, "cache-fixture", File.expand_path("..", __dir__), dir, bad, timeout: 30)
  check(status.success? && (out + err).include?("Swift compilation failed") && File.read(stale) == "old-output",
    "shell cache wrapper swallowed failure or replaced prior output: #{out}#{err}")
end
puts "Swift compile cache: PASS (actual compiler; warm hit; bridged header; source/directory symlinks; cycles; flags; new header; CPATH; shell failure propagation)"
