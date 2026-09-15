require "digest"
require "fileutils"
require "json"
require "tmpdir"

# Common publication boundary. Every read/copy and write is under the same
# per-command lock; each build has private staging files, never shared .nexts.
module CompileArtifactCache
  def self.directory(path)
    FileUtils.mkdir_p(path, mode: 0700)
    stat = File.lstat(path)
    raise "unsafe compiler cache directory" unless stat.directory? && stat.uid == Process.uid
  end

  def self.file?(path)
    stat = File.lstat(path)
    stat.file? && stat.uid == Process.uid
  rescue Errno::ENOENT
    false
  end

  def self.fetch(cache, identity, output, resolve:)
    directory(cache)
    key = Digest::SHA256.hexdigest(JSON.generate([identity, Digest::SHA256.file(__FILE__).hexdigest]))
    slot = File.join(cache, key)
    directory(slot)
    File.open(File.join(slot, "lock"), File::RDWR | File::CREAT | File::NOFOLLOW, 0600) do |lock|
      raise "unsafe compiler lock" unless lock.stat.file? && lock.stat.uid == Process.uid
      lock.flock(File::LOCK_EX)
      # A SIGKILL cannot run mktmpdir's ensure. Once this command's lock is
      # acquired, none of its private compile/dependency stages can be active.
      # Only reap our generated, owned directories; never follow a symlink.
      Dir.children(slot).grep(/\A(?:compile|dependencies)-\d{8}-\d+-[a-z0-9]+\z/).each do |name|
        path = File.join(slot, name)
        stat = File.lstat(path)
        FileUtils.remove_entry_secure(path) if stat.directory? && stat.uid == Process.uid
      end
      inputs = resolve.call(slot)
      binary, manifest = %w[binary manifest.json].map { |name| File.join(slot, name) }
      valid = false
      if file?(binary) && File.executable?(binary) && file?(manifest)
        begin
          record = JSON.parse(File.read(manifest))
          valid = record.is_a?(Hash) && record["inputs"] == inputs &&
            record["binary"] == Digest::SHA256.file(binary).hexdigest
        rescue JSON::ParserError
          valid = false
        end
      end
      unless valid
        Dir.mktmpdir("compile-", slot) do |stage|
          built = File.join(stage, "binary")
          yield built
          raise "compiler did not produce an executable" unless file?(built) && File.executable?(built)
          raise "inputs changed during test compilation" unless resolve.call(slot) == inputs
          record = {"inputs" => inputs, "binary" => Digest::SHA256.file(built).hexdigest}
          File.write(File.join(stage, "manifest.json"), JSON.generate(record))
          File.rename(built, binary)
          File.rename(File.join(stage, "manifest.json"), manifest)
        end
      end
      raise "unsafe test output" if File.symlink?(output) || File.expand_path(output) == File.expand_path(binary)
      FileUtils.cp(binary, output)
      valid
    end
  end
end
