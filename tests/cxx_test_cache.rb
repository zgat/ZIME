#!/usr/bin/env ruby
# Cache compilation only. Every caller must still execute in its own fixture.
require "digest"
require "fileutils"
require "json"
require "open3"
require "shellwords"
require "tmpdir"

module CxxTestCache
  def self.compile(cache, output, command)
    raise ArgumentError, "missing compiler command" if command.empty? || command.include?("-o")
    compiler, status = Open3.capture2e(command.first, "--version")
    raise "compiler identity unavailable" unless status.success?
    environment = ENV.select { |key, _| key.match?(/\A(CPATH|CPLUS_INCLUDE_PATH|LIBRARY_PATH|SDKROOT|DEVELOPER_DIR|MACOSX_DEPLOYMENT_TARGET)\z/) }
    key = Digest::SHA256.hexdigest(JSON.generate([Dir.pwd, compiler,
      Digest::SHA256.file(__FILE__).hexdigest, environment.sort, command]))
    FileUtils.mkdir_p(cache)
    raise "unsafe compiler cache" if File.symlink?(cache)
    slot = File.join(cache, key)
    FileUtils.mkdir_p(slot)
    raise "unsafe compiler slot" if File.symlink?(slot)
    File.open(File.join(slot, "lock"), File::RDWR | File::CREAT, 0600) do |lock|
      lock.flock(File::LOCK_EX)
      binary = File.join(slot, "binary")
      manifest = File.join(slot, "manifest.json")
      begin
        record = JSON.parse(File.read(manifest))
        valid = File.executable?(binary) && !File.symlink?(binary) && !File.symlink?(manifest) &&
          Digest::SHA256.file(binary).hexdigest == record.fetch("binary") &&
          !record.fetch("inputs").empty? && record.fetch("inputs").all? { |path, digest|
            File.file?(path) && Digest::SHA256.file(path).hexdigest == digest
          }
      rescue Errno::ENOENT, JSON::ParserError, KeyError
        valid = false
      end
      unless valid
        Dir.mktmpdir("compile-", slot) do |stage|
          built = File.join(stage, "binary")
          # Collect each translation unit separately: clang -MD -MF with several
          # source files silently leaves only the LAST unit's dependencies.
          # -M includes SDK/system headers, unlike -MMD.
          sources = command.select { |arg| arg.match?(/\.(?:c|cc|cpp|cxx|m|mm|C)\z/) && File.file?(arg) }
          raise "no C++ sources" if sources.empty?
          dependencies = sources.flat_map.with_index { |source, index|
            depfile = File.join(stage, "deps-#{index}")
            preprocessing = command.reject { |arg|
              (sources.include?(arg) && arg != source) || arg.match?(/\.(?:dylib|a|o)\z/)
            }
            raise "C++ compilation failed" unless system(*preprocessing, "-M", "-MF", depfile)
            Shellwords.split(File.read(depfile).gsub(/\\\n/, " ").split(": ", 2).fetch(1))
          }
          raise "C++ compilation failed" unless system(*command, "-o", built)
          inputs = (dependencies + command.select { |arg| File.file?(arg) }).uniq.sort
          record = {"binary" => Digest::SHA256.file(built).hexdigest,
            "inputs" => inputs.to_h { |path| [File.expand_path(path), Digest::SHA256.file(path).hexdigest] }}
          File.write(File.join(stage, "manifest.json"), JSON.generate(record))
          File.rename(built, binary)
          File.rename(File.join(stage, "manifest.json"), manifest)
        end
      end
      FileUtils.cp(binary, output)
      puts "C++ test compile cache: #{valid ? 'HIT' : 'MISS'} #{File.basename(output)}"
      valid
    end
  end
end

if $PROGRAM_NAME == __FILE__
  abort "usage: cxx_test_cache.rb CACHE OUTPUT -- COMPILER ARGS..." unless ARGV.size >= 4 && ARGV[2] == "--"
  CxxTestCache.compile(ARGV[0], ARGV[1], ARGV.drop(3))
end
