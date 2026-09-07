import AppKit
import Foundation
import SwiftUI

@main
struct ZIMEKeyboardShortcutTests {
  typealias Shortcut = LinnetSettingsDocument.Shortcut
  typealias Bindings = LinnetSettingsDocument.Shortcuts

  @MainActor static func main() throws {
    _ = NSApplication.shared
    let defaults = Bindings.default
    require(defaults.isValid, "defaults conflict")
    require(defaults.action(keyCode: 48, modifiers: 0) == .switchSourceTranslation, "Tab must only switch sides")
    require(defaults.action(keyCode: 36, modifiers: 0) == .commitRawInput, "Return must submit original input on either side")
    require(defaults.action(keyCode: 76, modifiers: 0) == .commitRawInput, "keypad Enter must also submit original input")
    require(defaults.action(keyCode: 48, modifiers: Shortcut.option) == .smartComplete, "completion must have a separate binding")
    require(defaults.action(keyCode: 48, modifiers: Shortcut.shift) == nil, "Shift-Tab is not implicitly stolen")
    require(defaults.action(keyCode: 48, modifiers: 1 << 16) == .switchSourceTranslation, "Caps Lock must not change shortcut identity")
    for code: UInt16 in [0, 3, 18, 51, 53, 123, 124, 125, 126, 55, 56] {
      require(!Shortcut(keyCode: code).isValid, "typing/editing/modifier key became a bare shortcut")
    }
    for value in [Shortcut(keyCode: 48, modifiers: Shortcut.command),
                  Shortcut(keyCode: 49, modifiers: Shortcut.command),
                  Shortcut(keyCode: 49, modifiers: Shortcut.control),
                  Shortcut(keyCode: 12, modifiers: Shortcut.command),
                  Shortcut(keyCode: 48, modifiers: 1 << 31)] {
      require(!value.isValid, "reserved or unknown shortcut was accepted")
    }
    var custom = defaults
    custom.commitRawInput = .init(keyCode: 40, modifiers: Shortcut.control | Shortcut.option)
    require(custom.isValid && custom.action(keyCode: 40, modifiers: Shortcut.control | Shortcut.option) == .commitRawInput,
      "recorded modifier chord did not route")
    custom.smartComplete = custom.commitRawInput
    require(!custom.isValid && custom.action(keyCode: 40, modifiers: Shortcut.control | Shortcut.option) == nil,
      "conflicting bindings did not fail closed")

    let legacy = Data(#"{"schemaVersion":15,"english":{"tabBehavior":"smart_complete","translationToggleKey":"tab","translationCommitKey":"enter"}}"#.utf8)
    let migrated = try JSONDecoder().decode(LinnetSettingsDocument.self, from: legacy)
    require(migrated.schemaVersion == 17 && migrated.shortcuts == .default, "old conflicting Tab defaults did not migrate")
    let customized = Data(#"{"schemaVersion":14,"english":{"tabBehavior":"pass","translationToggleKey":"option_return","translationCommitKey":"space"}}"#.utf8)
    let migratedCustom = try JSONDecoder().decode(LinnetSettingsDocument.self, from: customized)
    require(migratedCustom.shortcuts.switchSourceTranslation == .init(keyCode: 36, modifiers: Shortcut.option)
      && migratedCustom.shortcuts.commitRawInput == .init(keyCode: 49)
      && migratedCustom.shortcuts.smartComplete == nil, "explicit legacy choices were lost")
    let encoded = try JSONEncoder().encode(migratedCustom)
    let text = String(decoding: encoded, as: UTF8.self)
    require(!text.contains("tabBehavior") && !text.contains("translationCommitKey") && !text.contains("translationToggleKey") && !text.contains("commitCandidate"),
      "retired shortcut fields were written back")
    require(try JSONDecoder().decode(LinnetSettingsDocument.self, from: encoded) == migratedCustom, "recorded bindings did not round-trip")
    var invalid = migrated
    invalid.shortcuts.commitRawInput = .tab
    do { _ = try JSONEncoder().encode(invalid); fatalError("conflicting settings encoded") }
    catch is EncodingError { }
    let duplicate = Data(#"{"shortcuts":{"switchSourceTranslation":{"keyCode":36,"modifiers":0},"commitCandidate":{"keyCode":76,"modifiers":0}}}"#.utf8)
    do { _ = try JSONDecoder().decode(LinnetSettingsDocument.self, from: duplicate); fatalError("conflicting JSON decoded") }
    catch is DecodingError { }

    let previous = Data(#"{"schemaVersion":16,"shortcuts":{"switchSourceTranslation":{"keyCode":48,"modifiers":0},"commitCandidate":{"keyCode":76,"modifiers":0},"smartComplete":null}}"#.utf8)
    let upgraded = try JSONDecoder().decode(LinnetSettingsDocument.self, from: previous)
    require(upgraded.schemaVersion == 17 && upgraded.shortcuts.commitRawInput == .enter
      && upgraded.shortcuts.smartComplete == nil, "v16 recording or disabled completion was lost")
    let upgradedText = String(decoding: try JSONEncoder().encode(upgraded), as: UTF8.self)
    require(upgradedText.contains("commitRawInput") && !upgradedText.contains("commitCandidate"),
      "candidate confirmation survived v17 serialization")
    require(try JSONDecoder().decode(LinnetSettingsDocument.self, from: Data(upgradedText.utf8)) == upgraded,
      "disabled completion did not survive v17 round-trip")

    let window = NSPanel(contentRect: .init(x: -10000, y: -10000, width: 320, height: 100),
      styleMask: .nonactivatingPanel, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let button = ZIMEShortcutRecordButton()
    window.contentView = button
    window.orderFrontRegardless()
    defer { window.close() }
    var recorded: [Shortcut?] = []
    button.onRecord = { value in recorded.append(value); return value?.isValid ?? true }
    button.shortcut = .optionTab
    for (code, flags, characters): (UInt16, NSEvent.ModifierFlags, String) in [
      (48, [], "\t"), (36, [], "\r"), (76, [], "\r"),
      (40, [.control, .option], "k"), (99, [], "\u{f706}")
    ] {
      button.beginRecording()
      require(button.isRecording && window.firstResponder === button, "recorder did not obtain local focus")
      let event = key(code, flags: flags, characters: characters, window: window)
      if !window.performKeyEquivalent(with: event) { window.sendEvent(event) }
      require(recorded.last! == Shortcut(keyCode: code, modifiers: flags.rawValue) && !button.isRecording,
        "native Tab/Return/chord recording was intercepted by focus navigation")
    }
    let beforeCancel = recorded.count
    button.beginRecording()
    button.keyDown(with: key(53, characters: "\u{1b}", window: window))
    require(!button.isRecording && recorded.count == beforeCancel, "Escape did not cancel without saving")
    button.allowsClearing = true
    button.beginRecording()
    button.keyDown(with: key(51, characters: "\u{7f}", window: window))
    require(recorded.last! == nil && button.shortcut == nil, "Delete did not unbind completion")
    button.beginRecording()
    window.makeFirstResponder(nil)
    require(!button.isRecording, "recording continued after losing focus")
    let beforeIdle = recorded.count
    _ = button.performKeyEquivalent(with: key(48, characters: "\t", window: window))
    require(recorded.count == beforeIdle, "idle recorder captured a key")

    require(LinnetCandidatePresentation.smartCompletionText(input: "cluod", candidates: ["cloud"], highlighted: 0) == "cloud", "correction preedit")
    require(LinnetCandidatePresentation.smartCompletionText(input: "ear", candidates: ["early access"], highlighted: 0) == "early access", "phrase preedit")
    require(LinnetCandidatePresentation.smartCompletionText(input: "early ac", candidates: ["access"], highlighted: 0) == "early access", "completion dropped the phrase prefix")
    require(LinnetCandidatePresentation.smartCompletionText(input: "early access", candidates: ["access"], highlighted: 0) == nil, "repeated completion dropped the phrase prefix")
    for input in ["https://example.com", "foo_bar", "你好", "a\nb", "123"] {
      require(LinnetCandidatePresentation.smartCompletionText(input: input, candidates: ["cloud"], highlighted: 0) == nil, "unsafe preedit replaced")
    }
    require(LinnetCandidatePresentation.smartCompletionText(input: "cloud", candidates: ["cloud"], highlighted: 0) == nil, "already complete text changed")
    print("ZIMEKeyboardShortcutTests: PASS (recording, routing, conflicts, migration, focus and completion)")
  }

  private static func key(_ code: UInt16, flags: NSEvent.ModifierFlags = [], characters: String, window: NSWindow) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
      context: nil, characters: characters, charactersIgnoringModifiers: characters,
      isARepeat: false, keyCode: code)!
  }
  private static func require(_ value: Bool, _ message: String) {
    if !value { fatalError("ZIMEKeyboardShortcutTests: \(message)") }
  }
}
