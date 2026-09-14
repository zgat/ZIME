#!/usr/bin/env ruby
# Current ZIME contract and negative cases; historical authorization stays immutable.
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/zime_release"
abort "usage: verify_zime_publication.rb" unless ARGV.empty?
root = File.expand_path("..", __dir__)
ZIMERelease.product(root)
historical = {
  "config/linnet-community-signing.json" => "77902625466d754326f910ecc13a894e566a758453b96a3c26190578f85f35e5",
  "package/installer-scripts/candidate-app-identity.sh" => "8458b101e43cac160f424d9ca25e64414afdf928e076a8575102625404e08cf6",
  ".github/legacy/release-ci.yml" => "eca663ac17bd16689221f08503908129693bdfa1f629ffc92a13bc3178f7266c"
}
historical.each do |path, hash|
  ZIMERelease.check(Digest::SHA256.file(File.join(root, path)).hexdigest == hash, "historical Linnet evidence changed: #{path}")
end
%w[scripts/build-zime-release scripts/verify-zime-delivery scripts/build-zime-delivery scripts/stage-zime-preview tests/verify_zime_app.sh].each do |path|
  ZIMERelease.regular(File.join(root, path))
  ZIMERelease.check(File.executable?(File.join(root, path)), "non-executable entrypoint: #{path}")
end
builder = File.read(File.join(root, "scripts/build-zime-release"))
ZIMERelease.check(builder.include?("git status --porcelain=v1 --untracked-files=all") &&
  builder.include?("scripts/verify-zime-delivery") && !builder.match?(/\bgh\s+release|\bsecurity\s+import/), "unsafe candidate builder")
delivery = File.read(File.join(root, "scripts/build-zime-delivery"))
ZIMERelease.check(delivery.include?("--force --sign -") && delivery.include?('enable_localSystem="false"') &&
  delivery.include?("ZIME.staged.pkg") && delivery.match?(/install_helper.* check/), "preview packaging boundary missing")
gate = File.read(File.join(root, "tests/verify_development.sh"))
%w[verify_publication_owner.sh verify_release_automation.sh verify_zime_installer.sh verify_zime_privacy.sh verify_zime_app.sh].each do |name|
  ZIMERelease.check(gate.include?("tests/#{name}"), "unified gate omits #{name}")
end
def rejects(reason)
  begin
    yield
  rescue ZIMERelease::Invalid, Errno::ENOENT, JSON::ParserError
    return
  end
  raise "accepted invalid release: #{reason}"
end
negative = 0
Dir.mktmpdir("zime-publication-", "/tmp") do |fixture|
  FileUtils.mkdir_p(File.join(fixture, "config"))
  FileUtils.cp(File.join(root, "config/LinnetProduct.xcconfig"), File.join(fixture, "config"))
  File.write(File.join(fixture, "upstreams.lock.json"), JSON.generate({"sources" => {"rime_lmdg_grammar" => {"asset" => "fixture.gram"}}}))
  output = File.join(fixture, "release")
  FileUtils.mkdir_p(output)
  revision = "a" * 40
  names = ZIMERelease.asset_names(fixture, ZIMERelease.product(fixture)["MARKETING_VERSION"])
  names.each { |name| File.binwrite(File.join(output, name), "fixture: #{name}\n") }
  model = File.join(output, "fixture.gram")
  File.write(File.join(fixture, "upstreams.lock.json"), JSON.generate({"sources" => {
    "rime_lmdg_grammar" => {"asset" => "fixture.gram", "bytes" => File.size(model),
      "sha256" => Digest::SHA256.file(model).hexdigest}}}))
  pristine = ZIMERelease.manifest(fixture, output, revision)
  save = ->(value) {
    File.write(File.join(output, "manifest.json"), JSON.pretty_generate(value) + "\n")
    File.write(File.join(output, "SHA256SUMS"), ZIMERelease.checksums(value))
  }
  save.call(pristine)
  ZIMERelease.verify_manifest(fixture, output, revision)
  {"bundle_identifier" => "io.github.ares-x.inputmethod.Linnet", "version" => "0.0.0",
   "build" => "0", "architecture" => "x86_64", "source_revision" => "b" * 40,
   "source_dirty" => true, "signing" => "community-cms", "package_signing" => "signed",
   "notarized" => true, "upstream_lock_sha256" => "0" * 64}.each do |key, value|
    mutated = Marshal.load(Marshal.dump(pristine)); mutated[key] = value
    save.call(mutated)
    rejects(key) { ZIMERelease.verify_manifest(fixture, output, revision) }; negative += 1
  end
  save.call(pristine)
  file = File.join(output, names.first)
  bytes = File.binread(file)
  File.write(file, "corrupt")
  rejects("corrupt asset") { ZIMERelease.verify_manifest(fixture, output, revision) }; negative += 1
  File.write(file, bytes)
  File.rename(file, file + ".missing")
  rejects("missing asset") { ZIMERelease.verify_manifest(fixture, output, revision) }; negative += 1
  File.rename(file + ".missing", file)
  File.unlink(file); File.symlink(File.join(fixture, "upstreams.lock.json"), file)
  rejects("symlink asset") { ZIMERelease.verify_manifest(fixture, output, revision) }; negative += 1
  File.unlink(file); File.write(file, bytes)
  File.write(File.join(output, "unexpected"), "extra")
  rejects("extra asset") { ZIMERelease.verify_manifest(fixture, output, revision) }; negative += 1
  File.unlink(File.join(output, "unexpected"))
  File.write(File.join(output, "SHA256SUMS"), "")
  rejects("empty checksums") { ZIMERelease.verify_manifest(fixture, output, revision) }; negative += 1
  save.call(pristine)
  [["../escape"], ["/absolute"], ["a/../../escape"], ["a\\b"], ["duplicate", "duplicate"], []].each do |names|
    rejects("unsafe archive") { ZIMERelease.safe_zip_names(names) }; negative += 1
  end
  ZIMERelease.safe_zip_names(["ZIME.app/", "ZIME.app/Contents/Info.plist"])
  linked_entries = %w[fixture/ fixture/data/ fixture/data/word fixture/runtime/ fixture/runtime/word]
  ZIMERelease.safe_zip_links(linked_entries, {"fixture/runtime/word" => "../data/word"})
  ["../../../escape", "/absolute", "../missing", ""].each do |target|
    rejects("unsafe archive link") { ZIMERelease.safe_zip_links(linked_entries, {"fixture/runtime/word" => target}) }
    negative += 1
  end
  rejects("write through archive link") {
    ZIMERelease.safe_zip_links(linked_entries + ["fixture/runtime/word/child"], {"fixture/runtime/word" => "../data"})
  }; negative += 1
  real_tree = File.join(fixture, "zip-fixture")
  FileUtils.mkdir_p(File.join(real_tree, "data"))
  FileUtils.mkdir_p(File.join(real_tree, "runtime"))
  File.write(File.join(real_tree, "data/word"), "fixture")
  File.symlink("../data/word", File.join(real_tree, "runtime/word"))
  archive = File.join(fixture, "fixture.zip")
  ZIMERelease.run("/usr/bin/ditto", "-c", "-k", "--keepParent", real_tree, archive)
  ZIMERelease.preflight_zip(archive)
  File.unlink(File.join(real_tree, "runtime/word"))
  File.symlink("../../../escape", File.join(real_tree, "runtime/word"))
  ZIMERelease.run("/usr/bin/ditto", "-c", "-k", "--keepParent", real_tree, File.join(fixture, "unsafe.zip"))
  rejects("real ZIP escaping link") { ZIMERelease.preflight_zip(File.join(fixture, "unsafe.zip")) }
  negative += 1
  File.write(model, "unlocked model")
  rejects("self-consistent manifest with unlocked model") { ZIMERelease.manifest(fixture, output, revision) }
  negative += 1
end
puts "ZIME publication owner: PASS (current identity/Ad-hoc policy, immutable Linnet history, #{negative} negative release cases; no authorization or network)"
