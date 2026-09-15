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
      # Re-resolve includes even on a hit: a new higher-priority header or an
      # __has_include condition can change compilation without changing any old
      # dependency. Hash preprocessed output as well as the current input set.
      inputs, preprocessing = self.inputs(command, slot)
      begin
        record = JSON.parse(File.read(manifest))
        valid = File.executable?(binary) && !File.symlink?(binary) && !File.symlink?(manifest) &&
          Digest::SHA256.file(binary).hexdigest == record.fetch("binary") &&
          record.fetch("inputs") == inputs && record.fetch("preprocessing") == preprocessing
      rescue Errno::ENOENT, JSON::ParserError, KeyError
        valid = false
      end
      unless valid
        Dir.mktmpdir("compile-", slot) do |stage|
          built = File.join(stage, "binary")
          raise "C++ compilation failed" unless system(*command, "-o", built)
          record = {"binary" => Digest::SHA256.file(built).hexdigest,
            "inputs" => inputs, "preprocessing" => preprocessing}
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

  def self.inputs(command, slot)
    sources = command.select { |arg| arg.match?(/\.(?:c|cc|cpp|cxx|m|mm|C)\z/) && File.file?(arg) }
    raise "no C++ sources" if sources.empty?
    Dir.mktmpdir("dependencies-", slot) do |stage|
      preprocessed = []
      dependencies = sources.flat_map.with_index { |source, index|
        depfile = File.join(stage, "deps-#{index}")
        output = File.join(stage, "source-#{index}")
        preprocessing = command.reject { |arg|
          (sources.include?(arg) && arg != source) || arg.match?(/\.(?:dylib|a|o)\z/)
        }
        # One unit per invocation; -MD includes SDK/system headers. A stable
        # dependency target avoids injecting this scratch path into the digest.
        raise "C++ compilation failed" unless system(*preprocessing, "-E", "-MD", "-MF", depfile,
          "-MT", "probe", "-o", output)
        preprocessed << Digest::SHA256.file(output).hexdigest
        Shellwords.split(File.read(depfile).gsub(/\\\n/, " ").split(": ", 2).fetch(1))
      }
      paths = (dependencies + command.select { |arg| File.file?(arg) }).map { |p| File.expand_path(p) }.uniq.sort
      [paths.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] }, preprocessed]
    end
  end
end

if $PROGRAM_NAME == __FILE__
  abort "usage: cxx_test_cache.rb CACHE OUTPUT -- COMPILER ARGS..." unless ARGV.size >= 4 && ARGV[2] == "--"
  CxxTestCache.compile(ARGV[0], ARGV[1], ARGV.drop(3))
end
