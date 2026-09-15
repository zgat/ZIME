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
  File.unlink(header)
  begin
    check.call(false)
    abort "deleted header was accepted"
  rescue RuntimeError => error
    raise unless error.message == "C++ compilation failed"
  end
end
puts "C++ compile cache: PASS (source/header/flags/integrity invalidation; missing inputs fail closed)"
