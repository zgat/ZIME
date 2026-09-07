import AppKit
import SwiftUI

/// Window-local key recording. No event tap, global monitor or accessibility
/// permission is needed; keys are observed only while this button has focus.
final class ZIMEShortcutRecordButton: NSButton {
  typealias Shortcut = LinnetSettingsDocument.Shortcut
  var shortcut: Shortcut? { didSet { refreshTitle() } }
  var allowsClearing = false
  var onRecord: ((Shortcut?) -> Bool)?
  private(set) var isRecording = false

  override var acceptsFirstResponder: Bool { true }

  init() {
    super.init(frame: .zero)
    bezelStyle = .rounded
    font = .systemFont(ofSize: 13)
    target = self
    action = #selector(toggleRecording)
    setButtonType(.momentaryPushIn)
    refreshTitle()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  @objc private func toggleRecording() {
    if isRecording { stopRecording() } else { beginRecording() }
  }

  func beginRecording() {
    guard isEnabled, window?.makeFirstResponder(self) == true else { return }
    isRecording = true
    refreshTitle()
  }

  func stopRecording() {
    isRecording = false
    refreshTitle()
  }

  override func resignFirstResponder() -> Bool {
    stopRecording()
    return super.resignFirstResponder()
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard isRecording, window?.firstResponder === self, event.type == .keyDown else {
      return super.performKeyEquivalent(with: event)
    }
    keyDown(with: event)
    return true
  }

  override func keyDown(with event: NSEvent) {
    guard isRecording else { super.keyDown(with: event); return }
    guard !event.isARepeat else { return }
    if event.keyCode == 53 { stopRecording(); return } // Escape cancels, never binds.
    if [51, 117].contains(event.keyCode), allowsClearing,
      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
      if onRecord?(nil) == true { shortcut = nil; stopRecording() }
      return
    }
    let value = Shortcut(keyCode: event.keyCode,
                         modifiers: event.modifierFlags.rawValue & Shortcut.modifierMask)
    if onRecord?(value) == true { shortcut = value; stopRecording() }
  }

  private func refreshTitle() {
    title = isRecording ? String(localized: "Press shortcut…")
      : shortcut?.displayName ?? String(localized: "Not assigned")
    setAccessibilityValue(title)
  }
}

struct ZIMEShortcutRecorder: NSViewRepresentable {
  let shortcut: LinnetSettingsDocument.Shortcut?
  let label: String
  let allowsClearing: Bool
  let onRecord: (LinnetSettingsDocument.Shortcut?) -> Bool
  @Environment(\.isEnabled) private var isEnabled

  func makeNSView(context: Context) -> ZIMEShortcutRecordButton { ZIMEShortcutRecordButton() }
  func updateNSView(_ button: ZIMEShortcutRecordButton, context: Context) {
    button.shortcut = shortcut
    button.allowsClearing = allowsClearing
    button.onRecord = onRecord
    button.isEnabled = isEnabled
    if !isEnabled { button.stopRecording() }
    button.setAccessibilityLabel(label)
    button.toolTip = String(localized: "Click, then press a shortcut. Escape cancels; Delete clears optional shortcuts.")
  }
  static func dismantleNSView(_ button: ZIMEShortcutRecordButton, coordinator: ()) {
    button.stopRecording()
    button.onRecord = nil
  }
}

struct ZIMEKeyboardShortcutSettings: View {
  typealias Action = LinnetSettingsDocument.Shortcuts.Action
  @Binding var shortcuts: LinnetSettingsDocument.Shortcuts
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Candidate shortcuts").font(.headline)
      ForEach(Action.allCases, id: \.rawValue) { action in
        HStack {
          Text(title(action))
          Spacer()
          ZIMEShortcutRecorder(shortcut: shortcuts[action], label: title(action),
            allowsClearing: action == .smartComplete) { value in
              guard value?.isValid != false else {
                error = String(localized: "Use Tab, Return, Space, a function key, or a modified key. Editing and system shortcuts are reserved.")
                return false
              }
              var updated = shortcuts
              updated[action] = value
              guard updated.isValid else {
                error = String(localized: "This shortcut is already assigned to another candidate action.")
                return false
              }
              shortcuts = updated
              error = nil
              return true
            }
            .frame(width: 140, height: 28)
            .accessibilityIdentifier("settings.shortcuts.\(action.rawValue)")
        }
      }
      if let error { Text(error).font(.caption).foregroundStyle(.red) }
      Text("Number keys 1–9 select candidates. Return submits the original input, even on the translation side. Click a shortcut to record a different binding.")
        .font(.caption).foregroundStyle(.secondary)
      Text("Smart completion fills the selected English suggestion into marked input. Return submits that input; completion never switches translation sides.")
        .font(.caption).foregroundStyle(.secondary)
      Button("Reset candidate shortcuts") { shortcuts = .default; error = nil }
        .font(.caption)
    }
  }

  private func title(_ action: Action) -> String {
    switch action {
    case .switchSourceTranslation: String(localized: "Switch source / translation")
    case .commitRawInput: String(localized: "Submit original input")
    case .smartComplete: String(localized: "Smart completion")
    }
  }
}
