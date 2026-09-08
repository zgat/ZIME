#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/zime-tests/module-cache
ruby -e '
  host = File.read("sources/SquirrelInputController.swift")
  session = File.read("sources/SquirrelInputController+RimeSession.swift")
  fixture = File.read("tests/ZIMEHostRoutingFixture.swift")
  sections = {
    "SNAPSHOT" => session[/  struct CandidateItem:.*?(?=  func selectCandidate)/m],
    "HANDLE" => host[/  private func handleBilingualKeyDown\(.*?(?=  private func projectTranslationCandidates)/m],
    "PROJECT" => host[/  private func projectTranslationCandidates\(.*?(?=  func commit\(string:)/m],
    "SELECT" => session[/  func selectCandidate\(.*?(?=  \/\/\/ Refreshes annotations)/m]
  }
  sections.each do |key, source|
    abort "missing production method #{key}" unless source
    fixture.sub!("  // INJECT_#{key}", source.gsub("private func", "func"))
  end
  puts fixture
' > build/zime-tests/host-routing.swift
xcrun swiftc -warnings-as-errors -parse-as-library -enable-bare-slash-regex \
  -module-cache-path build/zime-tests/module-cache -framework AppKit \
  sources/LinnetPackContract.swift sources/LinnetDataChannel.swift \
  sources/LinnetDataRegistry.swift sources/LinnetDirectoryDelta.swift \
  sources/LinnetDataRegistryTransactions.swift sources/LinnetDataRegistryStorage.swift \
  sources/LinnetSettings/SettingsContract.swift sources/LinnetCandidatePresentation.swift \
  build/zime-tests/host-routing.swift -o build/zime-tests/host-routing
build/zime-tests/host-routing
