#!/usr/bin/env ruby
# Exercise the actual shell verifier; only compiler/runtime/signing leaves are
# replaced. Never execute the prohibited fixture command.
require "tmpdir"
require "fileutils"
require_relative "test_process"

Dir.mktmpdir("zime-installer-gate-") do |root|
  %w[tests scripts tools package/zime-installer-scripts bin].each { |name| FileUtils.mkdir_p(File.join(root, name)) }
  FileUtils.cp(File.join(__dir__, "verify_zime_installer.sh"), File.join(root, "tests"))
  File.write(File.join(root, "tests/verify_zime_installer_gate.rb"), "# Do not recursively run the fixture.\n")
  File.write(File.join(root, "tests/swift_test_scratch.sh"),
    "scratch='#{root}/scratch'\nlinnet_swift_scratch_init() { :; }\nlinnet_test_run() { :; }\n")
  %w[make codesign].each do |name|
    path = File.join(root, "bin", name)
    File.write(path, "#!/bin/sh\nexit 0\n"); File.chmod(0700, path)
  end
  paths = %w[scripts/install-zime scripts/update-zime-app scripts/build-zime-delivery package/zime-installer-scripts/postinstall tools/ZIMEInstallHelper.swift]
  paths.each { |name| File.write(File.join(root, name), "# fixture\n") }
  target = File.join(root, "scripts/install-zime")
  run = ->(expected) {
    out, err, status = TestProcess.capture({"PATH" => "#{root}/bin:#{ENV.fetch('PATH')}"},
      "/bin/bash", File.join(root, "tests/verify_zime_installer.sh"), timeout: 15)
    raise "installer forbidden-command oracle escaped: #{out}#{err}" unless
      status.exitstatus == expected && out.include?("ZIME installer entrypoints: PASS") == (expected == 0)
  }
  run.call(0)
  ["pkill ZIME", "kill -9 999999", "open -gj /fixture", "open -j /fixture"].each do |command|
    File.write(target, "#!/bin/zsh\n#{command}\n")
    run.call(1)
  end
  File.write(target, "# fixture\n")
  rg = File.join(root, "bin/rg")
  File.write(rg, "#!/bin/sh\nexit 42\n"); File.chmod(0700, rg)
  run.call(42)
end
puts "Installer command gate: PASS (clean baseline, four forbidden commands, scanner failure)"
