#!/usr/bin/env ruby
# Current product source ownership, not a substitute for runtime or UI tests.
require "json"
require "open3"

ROOT = File.expand_path("..", __dir__)

def verify(sources, project)
  retired = /\b(?:LinnetSettingsDownloadTransport|LinnetCorePackageDownloader|LinnetCloudRecoveryArchive|LinnetCloudSyncLocation|downloadCoreUpdate|exportCloudRecovery|setCloudSyncEnabled)\b/
  sources.each do |path, content|
    raise "retired product owner: #{path}" if content.match?(retired)
    if content.match?(/\b(?:URLSession|URLRequest|NWConnection|CFNetwork)\b/) &&
        path != "sources/ZIMETranslationProvider.swift"
      raise "unexpected network owner: #{path}"
    end
  end
  updater = sources.fetch("sources/LinnetSettings/LinnetSettingsUpdateChecker.swift")
  raise "installation identity is no longer read-only" if
    updater.match?(/Task|request\(|download|NSWorkspace|Timer|UserDefaults/)
  raise "verified identity reader missing" unless
    updater.include?("LinnetSettingsContract.productIdentity(startingAt: identityBundle)")

  objects = project.fetch("objects")
  compiled = objects.values.select { |item|
      item["isa"] == "PBXNativeTarget" && item["productType"] == "com.apple.product-type.application"
    }.flat_map { |item| item.fetch("buildPhases") }
    .map { |id| objects.fetch(id) }
    .select { |item| item["isa"] == "PBXSourcesBuildPhase" }
    .flat_map { |item| item.fetch("files") }
    .map { |id| objects.fetch(id) }
    .filter_map { |item| objects[item["fileRef"]] }
    .filter_map { |item| item["path"] }
    .select { |path| path.end_with?(".swift") }.uniq
  raise "no Swift product files" if compiled.empty?
  compiled.each do |path|
    raise "test fixture linked into product: #{path}" if path.start_with?("tests/")
    raise "missing product input: #{path}" unless sources.key?(path)
  end
  raise "bilingual keyboard owner not compiled" unless
    compiled.include?("sources/SquirrelInputController+Bilingual.swift")
  # Old-state producers are deliberately test-only; shipping readers and
  # interrupted-transaction recovery remain required production boundaries.
  production = sources.values.join("\n")
  %w[validDataChannelReceipt validatedLanguageTransaction recoverPreparedLanguageActivation].each do |owner|
    raise "legacy recovery reader removed: #{owner}" unless production.include?(owner)
  end
end

sources = Dir.glob(File.join(ROOT, "sources/**/*.swift")).to_h do |path|
  [path.delete_prefix(ROOT + "/"), File.read(path)]
end
json, error, status = Open3.capture3(
  "/usr/bin/plutil", "-convert", "json", "-o", "-",
  File.join(ROOT, "Linnet.xcodeproj/project.pbxproj"))
abort error unless status.success?
project = JSON.parse(json)
verify(sources, project)

negative = [
  ->(files, _) { files["sources/Injected.swift"] = "import Foundation\nlet session = URLSession.shared" },
  ->(files, _) { files["sources/Injected.swift"] = "struct LinnetCorePackageDownloader {}" },
  ->(files, _) { files["sources/LinnetSettings/LinnetSettingsUpdateChecker.swift"] += "\nlet task = Task {}" },
  ->(_, tree) {
    tree.fetch("objects")["TEST_REF"] = {"isa" => "PBXFileReference", "path" => "tests/fixtures/LegacyDataChannelProducer.swift"}
    tree.fetch("objects")["TEST_BUILD"] = {"isa" => "PBXBuildFile", "fileRef" => "TEST_REF"}
    target = tree.fetch("objects").values.find { |item| item["productType"] == "com.apple.product-type.application" }
    phase = target.fetch("buildPhases").map { |id| tree.fetch("objects").fetch(id) }
      .find { |item| item["isa"] == "PBXSourcesBuildPhase" }
    phase.fetch("files") << "TEST_BUILD"
  }
]
negative.each_with_index do |mutate, index|
  files = sources.transform_values(&:dup)
  tree = Marshal.load(Marshal.dump(project))
  mutate.call(files, tree)
  begin
    verify(files, tree)
  rescue RuntimeError
    next
  end
  abort "source boundary accepted negative case #{index + 1}"
end
puts "ZIME source boundaries: PASS (read-only Settings, one opt-in network owner, legacy recovery, four negative cases)"
