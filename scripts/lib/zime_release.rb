# SPDX-License-Identifier: GPL-3.0-or-later
require "digest"
require "json"
require "open3"
require "pathname"

module ZIMERelease
  class Invalid < StandardError; end
  module_function
  def check(value, reason)
    raise Invalid, reason unless value
  end
  def run(*args)
    out, err, status = Open3.capture3(*args)
    check(status.success?, "#{File.basename(args.first)} failed: #{err.strip}")
    out.strip
  end
  def product(root)
    fields = File.read(File.join(root, "config/LinnetProduct.xcconfig")).scan(/^([A-Z_]+) = (\S+)$/).to_h
    check(fields["LINNET_PRODUCT_NAME"] == "ZIME" &&
      fields["LINNET_BUNDLE_IDENTIFIER"] == "com.zime.inputmethod.ZIME", "not the ZIME product")
    check(fields["MARKETING_VERSION"].to_s.match?(/\A\d+\.\d+\.\d+\z/) &&
      fields["CURRENT_PROJECT_VERSION"].to_s.match?(/\A[1-9]\d*\z/), "invalid product version")
    fields
  end
  def asset_names(root, version)
    model = JSON.parse(File.read(File.join(root, "upstreams.lock.json"))).fetch("sources").fetch("rime_lmdg_grammar").fetch("asset")
    check(model.match?(/\A[A-Za-z0-9._-]+\.gram\z/), "unsafe locked model name")
    ["ZIME-#{version}-arm64.zip", "ZIME-#{version}-arm64.pkg", "ZIME-#{version}-arm64-core.zip", model].sort
  end
  def regular(path)
    check(File.file?(path) && !File.symlink?(path), "missing or linked file: #{path}")
  end
  def manifest(root, directory, revision)
    check(revision.match?(/\A[0-9a-f]{40}\z/), "invalid source revision")
    p = product(root)
    names = asset_names(root, p.fetch("MARKETING_VERSION"))
    names.each { |name| regular(File.join(directory, name)) }
    model = JSON.parse(File.read(File.join(root, "upstreams.lock.json"))).fetch("sources").fetch("rime_lmdg_grammar")
    model_path = File.join(directory, model.fetch("asset"))
    check(File.size(model_path) == model.fetch("bytes") &&
      Digest::SHA256.file(model_path).hexdigest == model.fetch("sha256"), "model differs from locked upstream")
    {"format" => 1, "product" => "ZIME", "version" => p.fetch("MARKETING_VERSION"),
     "build" => p.fetch("CURRENT_PROJECT_VERSION"), "architecture" => "arm64",
     "bundle_identifier" => p.fetch("LINNET_BUNDLE_IDENTIFIER"), "source_revision" => revision,
     "source_dirty" => false, "signing" => "ad-hoc", "package_signing" => "unsigned",
     "notarized" => false, "upstream_lock_sha256" => Digest::SHA256.file(File.join(root, "upstreams.lock.json")).hexdigest,
     "assets" => names.map { |name| path = File.join(directory, name)
       {"name" => name, "bytes" => File.size(path), "sha256" => Digest::SHA256.file(path).hexdigest} }}
  end
  def checksums(document)
    document.fetch("assets").map { |a| "#{a.fetch('sha256')}  #{a.fetch('name')}\n" }.join
  end
  def verify_manifest(root, directory, revision)
    check(File.directory?(directory) && !File.symlink?(directory), "unsafe delivery directory")
    names = asset_names(root, product(root).fetch("MARKETING_VERSION"))
    check(Dir.children(directory).sort == (names + %w[SHA256SUMS manifest.json]).sort, "unexpected or missing release assets")
    %w[manifest.json SHA256SUMS].each { |name| regular(File.join(directory, name)) }
    expected = manifest(root, directory, revision)
    check(JSON.parse(File.read(File.join(directory, "manifest.json"))) == expected,
      "manifest identity, source revision, policy, inventory, size or digest mismatch")
    check(File.read(File.join(directory, "SHA256SUMS")) == checksums(expected), "checksum list mismatch")
    expected
  end
  def safe_zip_names(names)
    check(!names.empty? && names.uniq == names, "empty archive or duplicate archive entries")
    names.each do |name|
      check(!name.empty? && !name.start_with?("/") && !name.match?(/[\\\x00-\x1f*?\[\]]/) &&
        !name.split("/").any? { |part| [".", ".."].include?(part) }, "unsafe archive entry")
    end
  end
  def safe_zip_links(names, links)
    safe_zip_names(names)
    entries = names.map { |name| name.delete_suffix("/") }
    links.each do |name, target|
      check(entries.include?(name) && !target.empty? && !target.start_with?("/") &&
        !target.match?(/[\\\x00-\x1f]/), "unsafe archive link")
      check(entries.none? { |entry| entry.start_with?(name + "/") }, "archive writes through a link")
      resolved = Pathname.new(File.join(File.dirname(name), target)).cleanpath.to_s
      check(!resolved.start_with?("../") && entries.include?(resolved), "archive link escapes or dangles")
      check(!links.key?(resolved) && links.keys.none? { |link| resolved.start_with?(link + "/") },
        "archive link chains are not part of the delivery contract")
    end
  end
  def preflight_zip(archive)
    names = run("/usr/bin/zipinfo", "-1", archive).lines.map(&:chomp)
    safe_zip_names(names)
    rows = run("/usr/bin/zipinfo", "-l", archive).lines.select { |line| line.match?(/\A[dl-][rwx-]{9}\s/) }
    check(rows.size == names.size, "unsupported archive entry type or mode")
    links = {}
    rows.zip(names).each do |row, name|
      fields = row.split(/\s+/, 10)
      check(fields.last.strip == name, "ambiguous archive inventory")
      links[name] = run("/usr/bin/unzip", "-p", archive, name) if row.start_with?("l")
    end
    safe_zip_links(names, links)
  end
  def tree_digest(root)
    root = File.realpath(root)
    rows = Dir.glob(File.join(root, "**/*"), File::FNM_DOTMATCH).reject { |p| [".", ".."].include?(File.basename(p)) }.sort.map do |path|
      relative = path.delete_prefix(root + "/")
      info = File.lstat(path)
      check(File.realpath(path).start_with?(root + "/"), "tree link escapes its root: #{relative}")
      value = if info.symlink? then "link:#{File.readlink(path)}"
      elsif info.directory? then "directory"
      elsif info.file? then Digest::SHA256.file(path).hexdigest
      else raise Invalid, "unsupported tree entry: #{relative}"
      end
      "#{relative}\t#{info.mode & 0777}\t#{value}\n"
    end
    Digest::SHA256.hexdigest(rows.join)
  end
  def verify_app(root, app, profile, revision = nil)
    check(%w[local release].include?(profile), "unknown App profile")
    check(File.directory?(app) && !File.symlink?(app), "unsafe App")
    p = product(root)
    expected_id = p.fetch("LINNET_BUNDLE_IDENTIFIER") + (profile == "local" ? ".local-build" : "")
    apps = [[app, expected_id, "ZIME"], [File.join(app, "Contents/Applications/Settings.app"), expected_id + ".settings", "Settings"]]
    apps.each do |bundle, id, executable|
      plist = File.join(bundle, "Contents/Info.plist")
      regular(plist)
      {"CFBundleIdentifier" => id, "CFBundleExecutable" => executable,
       "CFBundleShortVersionString" => p.fetch("MARKETING_VERSION"),
       "CFBundleVersion" => p.fetch("CURRENT_PROJECT_VERSION")}.each do |key, value|
        check(run("/usr/bin/plutil", "-extract", key, "raw", "-o", "-", plist) == value, "App #{key} mismatch")
      end
      if profile == "release"
        run("/usr/bin/codesign", "--verify", "--deep", "--strict", bundle)
        _, signing, status = Open3.capture3("/usr/bin/codesign", "-dv", "--verbose=4", bundle)
        check(status.success? && signing.include?("Signature=adhoc"), "unexpected preview signing policy")
      else
        check(!File.exist?(File.join(bundle, "Contents/_CodeSignature")), "local build unexpectedly signed")
      end
    end
    plist = JSON.parse(run("/usr/bin/plutil", "-convert", "json", "-o", "-", File.join(app, "Contents/Info.plist")))
    check(plist["LSMinimumSystemVersion"] == "13.0" && plist["LSUIElement"] == true &&
      plist["InputMethodConnectionName"] == "ZIME_Connection", "input method registration contract mismatch")
    modes = plist.fetch("ComponentInputModeDict").fetch("tsInputModeListKey")
    check(modes.keys.sort == %w[com.zime.inputmethod.ZIME.Hans com.zime.inputmethod.ZIME.Hant] &&
      modes.all? { |id, mode| mode["TISInputSourceID"] == id && mode["tsInputModeIsVisibleKey"] == true },
      "input mode identity/visibility mismatch")
    binaries = Dir.glob(File.join(app, "**/*")).select { |f| File.file?(f) && !File.symlink?(f) &&
      run("/usr/bin/file", "-b", f).include?("Mach-O") }
    check(binaries.size >= 6, "incomplete App runtime")
    binaries.each { |f| check(run("/usr/bin/lipo", "-archs", f) == "arm64", "non-arm64 App binary") }
    check(Digest::SHA256.file(File.join(app, "Contents/Resources/zime-cedict.sqlite3")).hexdigest ==
      Digest::SHA256.file(File.join(root, "resources/zime-cedict.sqlite3")).hexdigest, "stale bilingual dictionary")
    if profile == "release"
      meta = File.join(app, "Contents/Resources/ZIMERelease")
      version = JSON.parse(File.read(File.join(meta, "VERSION.json")))
      check(version["source_revision"] == revision && version["source_dirty"] == false &&
        version["version"] == p["MARKETING_VERSION"] && version["build"] == p["CURRENT_PROJECT_VERSION"] &&
        version["upstream_lock_sha256"] == Digest::SHA256.file(File.join(root, "upstreams.lock.json")).hexdigest,
        "App source/version/lock provenance mismatch")
      check(File.binread(File.join(meta, "upstreams.lock.json")) == File.binread(File.join(root, "upstreams.lock.json")), "App lock differs from source")
      check(Dir.glob(File.join(meta, "LICENSES/*")).size >= 14, "incomplete licenses")
    end
    run(File.join(root, "scripts/build-privacy"), "scan", app)
  end
end
