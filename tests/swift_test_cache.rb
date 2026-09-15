require_relative "compile_artifact_cache"
require_relative "test_process"
require_relative "swift_test_dependencies"

module SwiftTestCache
  INCLUDE_ENV = %w[CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH LIBRARY_PATH].freeze

  # Follow directory aliases too, but stop ancestry cycles. Tracking ancestors
  # (not a global visited set) preserves each search-path alias in the manifest.
  def self.tree_files(dir, ancestors = [], &block)
    real = File.realpath(dir)
    return if ancestors.include?(real)
    Dir.children(dir).sort.each do |entry|
      path = File.join(dir, entry)
      if File.directory?(path)
        tree_files(path, ancestors + [real], &block)
      elsif File.file?(path)
        block.call(path)
      end
    end
  end

  def self.inputs(repo, arguments)
    files = arguments.select { |arg| File.file?(arg) }
    directories = [File.join(repo, "librime/dist/include")]
    INCLUDE_ENV.each do |key|
      value = ENV[key]
      next if value.nil? || value.empty?
      directories.concat(value.split(File::PATH_SEPARATOR, -1).map { |p| p.empty? ? Dir.pwd : p })
    end
    arguments.each_with_index do |arg, i|
      if %w[-I -L -F].include?(arg)
        directories << arguments.fetch(i + 1)
      elsif arg.match?(/\A-[ILF].+/)
        directories << arg[2..-1]
      elsif arg == "-import-objc-header"
        # Relative quoted imports can live beside the bridging header.
        directories << File.dirname(arguments.fetch(i + 1))
      end
    end
    directories.uniq.each do |dir|
      next unless File.directory?(dir)
      tree_files(dir) { |path| files << path }
    end
    files << File.join(repo, "lib/librime.1.dylib") if File.file?(File.join(repo, "lib/librime.1.dylib"))
    SwiftTestDependencies.fingerprints(files)
  end

  def self.compile(repo, cache, output, environment_fingerprint, command)
    raise ArgumentError, "invalid Swift compiler command" if command.empty? || command.include?("-o")
    environment = ENV.select { |k, _| (INCLUDE_ENV + %w[SDKROOT DEVELOPER_DIR MACOSX_DEPLOYMENT_TARGET SWIFT_EXEC]).include?(k) }
    identity = ["swift", Dir.pwd, environment_fingerprint, command, environment.sort,
      *%w[swift_test_cache.rb swift_test_dependencies.rb test_process.rb].map { |file|
        Digest::SHA256.file(File.join(__dir__, file)).hexdigest
      }]
    resolve = ->(slot) { [inputs(repo, command), SwiftTestDependencies.resolve(command, slot)] }
    hit = CompileArtifactCache.fetch(cache, identity, output, resolve: resolve) do |built|
      out, err, status = TestProcess.capture(*command, "-o", built, timeout: 180)
      raise "Swift compilation failed:\n#{out}#{err}" unless status.success?
    end
    puts "Swift test compile cache: #{hit ? 'HIT' : 'MISS'} #{File.basename(output)}"
    hit
  end
end

if $PROGRAM_NAME == __FILE__
  abort "usage: swift_test_cache.rb REPO CACHE OUTPUT ENVIRONMENT -- COMPILER ARGS" unless ARGV.size >= 6 && ARGV[4] == "--"
  SwiftTestCache.compile(*ARGV.first(4), ARGV.drop(5))
end
