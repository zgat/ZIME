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
  notes = File.join(bridge_dir, "unused-notes.txt")
  File.write(notes, "unrelated documentation\n")
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
  File.write(notes, "edited unrelated documentation\n")
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
  helper = File.join(dir, "helper.swift")
  File.write(source, "print(Int(VALUE) + offset)\n")
  File.write(helper, "let offset = 10\n")
  multi = command.map { |arg| arg == alias_source ? source : arg } + [helper]
  run.call(false, 13, multi)
  run.call(true, 13, multi)
  File.write(helper, "let offset = 20\n")
  run.call(false, 23, multi)
end

# Private SDK overlay: never write through any link into the installed SDK.
Dir.mktmpdir("zime-swift-sdk-") do |dir|
  overlay = File.join(dir, "Probe.sdk")
  {"" => %w[usr System], "usr" => %w[include], "usr/include" => [],
    "System" => %w[Library], "System/Library" => %w[Frameworks],
    "System/Library/Frameworks" => []}.each do |relative, owned|
    destination = File.join(overlay, relative)
    FileUtils.mkdir_p(destination)
    Dir.children(File.join(sdk.strip, relative)).reject { |name| owned.include?(name) }.each { |name|
      File.symlink(File.join(sdk.strip, relative, name), File.join(destination, name))
    }
  end
  header, optional, shadow = %w[zime_cache_probe.h zime_optional_probe.h zime_shadow_probe.h].map { |name|
    path = File.join(overlay, "usr/include", name)
    check(!File.exist?(path) && !File.symlink?(path), "SDK fixture conflicts with installed header")
    path
  }
  sources, fallback, cache = %w[sources fallback cache].map { |name| File.join(dir, name) }
  [sources, fallback].each { |path| FileUtils.mkdir_p(path) }
  bridge, main = %w[bridge.h main.swift].map { |name| File.join(sources, name) }
  File.write(bridge, "#include <zime_cache_probe.h>\n")
  File.write(main, "print(ZIME_SDK_VALUE)\n")
  File.write(header, "#define ZIME_SDK_VALUE 1\n")
  output = File.join(dir, "output")
  command = [compiler.strip, "-sdk", overlay, "-module-cache-path", File.join(dir, "modules"),
    "-import-objc-header", bridge, "-Xcc", "-idirafter", "-Xcc", fallback, main]
  run = ->(expected_hit, expected) {
    started = TestProcess.now
    hit = SwiftTestCache.compile(dir, cache, output, "unchanged-sdk-settings", command)
    check(hit == expected_hit, "SDK dependency change returned wrong cache decision")
    out, err, status = TestProcess.capture(output, timeout: 5)
    check(status.success? && out == "#{expected}\n", "stale SDK executable: #{out}#{err}")
    puts "Swift SDK fixture: #{expected_hit ? 'warm' : 'changed'} #{(TestProcess.now - started).round(2)}s"
  }
  run.call(false, 1)
  run.call(true, 1)
  stamp = File.mtime(header)
  File.write(header, "#define ZIME_SDK_VALUE 2\n")
  File.utime(stamp, stamp, header) # Same size/mtime must not disguise new contents.
  run.call(false, 2)
  File.write(header, <<~HEADER)
    #if __has_include(<zime_optional_probe.h>)
    #define ZIME_SDK_VALUE 3
    #else
    #define ZIME_SDK_VALUE 4
    #endif
  HEADER
  run.call(false, 4)
  File.write(optional, "// Available, deliberately not included.\n")
  run.call(false, 3)
  run.call(true, 3)
  File.unlink(optional)
  run.call(false, 4)
  external_optional = File.join(fallback, File.basename(optional))
  File.write(external_optional, "// Available through -Xcc -idirafter.\n")
  run.call(false, 3)
  File.unlink(external_optional)
  run.call(false, 4)
  File.write(header, "#include <zime_shadow_probe.h>\n")
  lower = File.join(fallback, File.basename(shadow))
  File.write(lower, "#define ZIME_SDK_VALUE 5\n")
  run.call(false, 5)
  File.write(shadow, "#define ZIME_SDK_VALUE 6\n")
  run.call(false, 6)
  File.unlink(shadow)
  run.call(false, 5)
  previous = File.binread(output)
  File.unlink(lower)
  begin
    SwiftTestCache.compile(dir, cache, output, "unchanged-sdk-settings", command)
    raise "missing SDK dependency reused old executable"
  rescue RuntimeError => error
    raise unless error.message.include?("Swift compilation failed")
  end
  check(File.binread(output) == previous, "failed SDK scan replaced prior output")
  # canImport is also a negative lookup, even without an actual import.
  framework = File.join(overlay, "System/Library/Frameworks/ZIMECacheOptional.framework")
  check(!File.exist?(framework) && !File.symlink?(framework), "SDK module fixture conflicts")
  File.write(header, "#define ZIME_SDK_VALUE 1\n")
  File.write(main, "#if canImport(ZIMECacheOptional)\nprint(7)\n#else\nprint(8)\n#endif\n")
  run.call(false, 8)
  %w[Headers Modules].each { |name| FileUtils.mkdir_p(File.join(framework, name)) }
  File.write(File.join(framework, "Headers/ZIMECacheOptional.h"), "#define ZIME_OPTIONAL 7\n")
  File.write(File.join(framework, "Modules/module.modulemap"),
    "framework module ZIMECacheOptional { header \"ZIMECacheOptional.h\" export * }\n")
  run.call(false, 7)
  run.call(true, 7)
  File.rename(framework, File.join(dir, "retired-framework"))
  run.call(false, 8)
end
puts "Swift compile cache: PASS (actual compiler; warm hit; symlinks/cycles; flags/CPATH; SDK content/mtime/__has_include/canImport/include priority/missing input; shell failure propagation)"
