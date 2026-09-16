#!/usr/bin/env ruby
require_relative "cxx_test_cache"
Dir.mktmpdir("zime-cache-test-") do |dir|
  header = File.join(dir, "a header.h")
  source = File.join(dir, "main.cc")
  second = File.join(dir, "second.cc")
  second_header = File.join(dir, "second.h")
  output = File.join(dir, "probe")
  cache = File.join(dir, "cache")
  File.write(header, "#define VALUE 1\n")
  File.write(source, "#include \"a header.h\"\nint extra(); int main() { return VALUE + extra(); }\n")
  File.write(second_header, "#define EXTRA 0\n")
  File.write(second, "#include \"second.h\"\nint extra() { return EXTRA; }\n")
  compiler, status = Open3.capture2("xcrun", "--find", "clang++")
  abort "compiler missing" unless status.success?
  sdk, status = Open3.capture2("xcrun", "--show-sdk-path")
  abort "SDK missing" unless status.success?
  command = [compiler.strip, "-isysroot", sdk.strip, "-std=c++17", source, second]
  check = ->(expected, cmd = command) {
    actual = CxxTestCache.compile(cache, output, cmd)
    abort "wrong cache decision #{actual}, expected #{expected}" unless actual == expected
  }
  check.call(false)
  check.call(true)
  File.write(header, "#define VALUE 2\n")
  check.call(false)
  system(output)
  abort "stale header behavior" unless $?.exitstatus == 2
  check.call(true)
  File.write(second_header, "#define EXTRA 3\n")
  check.call(false)
  system(output)
  abort "stale second translation unit" unless $?.exitstatus == 5
  File.write(source, File.read(source) + "// source change\n")
  check.call(false)
  check.call(false, command + ["-O2"])
  check.call(true, command + ["-O2"])
  Dir[File.join(cache, "*", "binary")].each { |path| File.write(path, "corrupt") }
  check.call(false)
  Dir[File.join(cache, "*", "manifest.json")].each { |path| File.write(path, "{") }
  check.call(false)

  preferred = File.join(dir, "preferred")
  fallback = File.join(dir, "fallback")
  FileUtils.mkdir_p([preferred, fallback])
  File.write(File.join(fallback, "value.h"), "#define VALUE 1\n")
  File.write(source, "#include <value.h>\nint main() { return VALUE; }\n")
  shadow = [compiler.strip, "-isysroot", sdk.strip, "-I", preferred, "-I", fallback, source]
  check.call(false, shadow)
  check.call(true, shadow)
  File.write(File.join(preferred, "value.h"), "#define VALUE 2\n")
  check.call(false, shadow)
  system(output)
  abort "new preferred header used stale binary" unless $?.exitstatus == 2
  check.call(true, shadow)
  File.unlink(File.join(preferred, "value.h"))
  check.call(false, shadow)
  system(output)
  abort "removed preferred header did not restore fallback" unless $?.exitstatus == 1

  # Deliberately do NOT include optional.h; a dependency-list-only cache misses
  # this change even though __has_include affects the executable.
  File.write(source, <<~CPP)
    #if __has_include(<optional.h>)
    int main() { return 3; }
    #else
    int main() { return 4; }
    #endif
  CPP
  check.call(false, shadow)
  check.call(true, shadow)
  File.write(File.join(preferred, "optional.h"), "// available\n")
  check.call(false, shadow)
  system(output)
  abort "new optional header ignored" unless $?.exitstatus == 3
  File.unlink(File.join(preferred, "optional.h"))
  check.call(false, shadow)
  system(output)
  abort "removed optional header ignored" unless $?.exitstatus == 4

  # Indirect linker inputs must never reuse an untracked archive. Until the
  # linker owns a dependency manifest these commands deliberately compile fresh.
  library_source = File.join(dir, "value.cc")
  object = File.join(dir, "value.o")
  library = File.join(dir, "libvalue.a")
  File.write(source, "extern int value(); int main() { return value(); }\n")
  linked = [compiler.strip, "-isysroot", sdk.strip, source, "-L", dir, "-lvalue"]
  [1, 2, 2].each do |value|
    File.write(library_source, "int value() { return #{value}; }\n")
    [[compiler.strip, "-isysroot", sdk.strip, "-c", library_source, "-o", object],
      ["xcrun", "ar", "rcs", library, object]].each do |cmd|
      out, err, status = TestProcess.capture(*cmd, timeout: 30)
      raise "link fixture compilation failed: #{out}#{err}" unless status.success?
    end
    check.call(false, linked)
    _, _, status = TestProcess.capture(output, timeout: 5)
    raise "indirect linked library reused stale behavior" unless status.exitstatus == value
  end
  # A failed fallback cannot replace the preceding usable output.
  previous = File.binread(output)
  File.unlink(library)
  begin
    check.call(false, linked)
    abort "missing indirect library accepted"
  rescue RuntimeError => error
    raise unless error.message == "C++ compilation failed"
  end
  raise "failed fallback replaced output" unless File.binread(output) == previous
  File.write(source, "#include \"a header.h\"\nint main() { return VALUE; }\n")
  File.unlink(header)
  begin
    check.call(false)
    abort "deleted header was accepted"
  rescue RuntimeError => error
    raise unless error.message == "C++ compilation failed"
  end
end
puts "C++ compile cache: PASS (source/header/flags/integrity, include precedence and __has_include; missing inputs fail closed)"
