#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "${root}"
ruby -rtmpdir -rfileutils -ropen3 -e '
  scanner = File.expand_path("scripts/build-privacy")
  Dir.mktmpdir("zime-privacy-", "/private/tmp") do |root|
    app = File.join(root, "ZIME.app")
    FileUtils.mkdir_p(app)
    notice = File.join(app, "NOTICE.txt")
    File.write(notice, "ZIME and Linnet public names; https://github.com/zgat/ZIME")
    _, error, status = Open3.capture3(scanner, "scan", app)
    abort error unless status.success?
    [File.expand_path("."), "/Users/private-builder/source", "/Volumes/private-build", "/private/tmp/build-secret", "/Applications/Xcode.app/Contents/Developer"].each do |private_path|
      File.write(notice, "ZIME " + private_path)
      _, _, status = Open3.capture3(scanner, "scan", app)
      abort "private path passed: #{private_path}" if status.success?
    end
    File.write(notice, "ZIME")
    File.write(File.join(app, ".DS_Store"), "fixture")
    _, _, status = Open3.capture3(scanner, "scan", app)
    abort "private metadata name passed" if status.success?
  end
  puts "ZIME privacy: PASS (public names allowed, build/user/SDK/temp paths and private metadata rejected)"
'
