#!/usr/bin/env bash
# Source-boundary checks complement the executable native and recorder tests.
set -euo pipefail
cd "$(dirname "$0")/.."
/usr/bin/ruby -e '
  host = File.read("sources/SquirrelInputController.swift")
  raw = host[/if action == \.commitRawInput \{(.*?)\n    \}/m, 1]
  abort "raw shortcut lost its guarded IMK boundary" unless raw &&
    raw.include?("guard hasPendingRimeInput, let targetClient = activeClient") &&
    raw.include?("candidateTranslator.cancel()") &&
    raw.include?("bilingualTranslationMode = false") &&
    raw.scan("commitActiveComposition(to: targetClient)").length == 1 &&
    !raw.include?("selectCandidate") && !raw.include?("highlighted")
  abort "candidate-confirmation shortcut returned" if host.include?(".commitCandidate")
  native = File.read("plugins/smart_english/smart_english.cc")
  abort "Return/Space candidate-confirmation owner returned" if native.include?("CommitSpaceSelection")
  abort "native original-input owner missing" unless native.include?("context->CommitRawInput()")
  abort "numeric translated-candidate selection disappeared" unless
    host.include?("selectCandidate(absoluteIndex: presented.items[index].absoluteIndex)")
  abort "global translation replacement returned" if host.include?("pendingCommitOverride")
  selection = File.read("sources/SquirrelInputController+RimeSession.swift")
  abort "translated selection can clear the entire composition" unless
    selection.include?("select_candidate_with_text") && !selection.include?("clear_composition")
  puts "ZIME original-input Host boundary: PASS (source contract, not UI automation)"
'
