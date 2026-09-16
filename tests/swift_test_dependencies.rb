require "set"
require_relative "compile_artifact_cache"
require_relative "test_process"

# The compiler owns import resolution. A fresh scan supplies real header/module
# inputs; the search-tree inventory also observes negative lookups (__has_include
# and canImport), which never appear in a successful dependency file list.
module SwiftTestDependencies
  SEARCH_FLAGS = %w[-I -F -Fsystem -isystem -iquote -idirafter -iframework
    -internal-isystem -internal-externc-isystem -internal-iframework -iapinotes-modules -resource-dir].freeze

  def self.search_paths(arguments)
    args = arguments.reject { |arg| arg == "-Xcc" }
    args.each_with_index.map do |arg, index|
      if SEARCH_FLAGS.include?(arg)
        args.fetch(index + 1)
      elsif arg == "-import-objc-header"
        # Observe relative negative lookups beside the bridge, without hashing
        # unrelated sibling source/document contents. Actual headers are hashed
        # from the compiler's bridgingHeader.sourceFiles dependency list.
        File.dirname(args.fetch(index + 1))
      elsif arg.match?(/\A-[IF].+/) && !arg.start_with?("-Fsystem")
        arg[2..-1]
      end
    end.compact
  end

  def self.fingerprints(files)
    files.map { |path| File.expand_path(path) }.uniq.sort.to_h { |path|
      [path, [File.realpath(path), Digest::SHA256.file(path).hexdigest]]
    }
  end

  def self.inventory(roots)
    entries, supplements, visited = [], [], Set.new
    walk = lambda do |path|
      unless File.exist?(path)
        entries << [path, "missing", File.symlink?(path) ? File.readlink(path) : nil]
        next
      end
      stat = File.stat(path)
      link = File.symlink?(path) ? File.readlink(path) : nil
      entries << [path, stat.ftype, link]
      if stat.directory?
        real = File.realpath(path)
        next unless visited.add?(real)
        Dir.children(path).sort.each { |name| walk.call(File.join(path, name)) }
      elsif stat.file? && path.match?(/\.(?:tbd|apinotes)\z/)
        # Linker stubs and API notes affect the result but aren't reliably
        # enumerated as sourceFiles by every supported Swift scanner.
        supplements << path
      end
    end
    roots.map { |path| File.expand_path(path) }.uniq.sort.each { |path| walk.call(path) }
    [Digest::SHA256.hexdigest(JSON.generate(entries)), fingerprints(supplements)]
  end

  def self.resolve(command, slot)
    Dir.mktmpdir("dependencies-", slot) do |stage|
      # The actual cache compile writes stage/binary, so preserve that inferred
      # module name when the caller doesn't supply one. Never hash scan outputs.
      name = command.include?("-module-name") ? [] : ["-module-name", "binary"]
      output = File.join(stage, "scan.json")
      # Scan all source files as one module. Otherwise swiftc creates one
      # primary-file job per source and rejects a single JSON -o destination.
      out, err, status = TestProcess.capture(*command, *name, "-disable-bridging-pch",
        "-scan-dependencies", "-whole-module-optimization", "-o", output, timeout: 60, owner: false)
      raise "Swift compilation failed during dependency scan:\n#{out}#{err}" unless status.success?
      graph = JSON.parse(File.read(output))
      modules = graph.fetch("modules").select { |item| item.key?("details") }
      raise "empty Swift dependency graph" if modules.empty?
      files, search = [], search_paths(command)
      modules.each do |mod|
        files.concat(mod.fetch("sourceFiles", []))
        mod.fetch("details").each do |kind, detail|
          raise "unsupported Swift dependency kind: #{kind}" unless %w[swift clang swiftPrebuiltExternal].include?(kind)
          files << mod.fetch("modulePath") if kind == "swiftPrebuiltExternal"
          %w[moduleInterfacePath moduleMapPath].each { |key| files << detail[key] if detail[key] }
          files.concat(detail.fetch("bridgingHeader", {}).fetch("sourceFiles", []))
          search.concat(search_paths(detail.fetch("commandLine", [])))
          search.concat(search_paths(detail.fetch("bridgingHeader", {}).fetch("commandLine", [])))
          files.concat(detail.fetch("compiledModuleCandidates", []).select { |path| File.file?(path) })
          detail.fetch("macroDependencies", []).each do |macro|
            # An in-process macro has a library but an empty executablePath.
            %w[libraryPath executablePath].each { |key| files << macro[key] if macro[key] && !macro[key].empty? }
          end
        end
      end
      out, err, status = TestProcess.capture(*command, "-print-target-info", timeout: 15, owner: false)
      raise "Swift target info failed:\n#{out}#{err}" unless status.success?
      paths = JSON.parse(out).fetch("paths")
      sdk = paths["sdkPath"]
      unless sdk
        sdk, err, status = TestProcess.capture("xcrun", "--show-sdk-path", timeout: 10, owner: false)
        raise "Swift default SDK unavailable: #{err}" unless status.success?
        sdk = sdk.strip
      end
      roots = [*search, sdk, paths.fetch("runtimeResourcePath"), *paths.fetch("runtimeLibraryImportPaths"),
        *paths.fetch("runtimeLibraryPaths")]
      [CompileArtifactCache.measure("Swift dependency fingerprints") { fingerprints(files) },
        CompileArtifactCache.measure("Swift search inventory") { inventory(roots) }]
    end
  end
end
