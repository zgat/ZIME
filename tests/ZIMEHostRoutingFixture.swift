import AppKit
import Carbon

// Only IMK/Rime effects are mocked. Compile the complete production Bilingual
// extension, plus syntax-selected RimeSession selection/paging declarations.
struct FixtureShortcuts {
  enum Action { case switchSourceTranslation, commitRawInput, smartComplete }
  static let `default` = Self()
  func action(keyCode: UInt16, modifiers: UInt) -> Action? {
    if modifiers == NSEvent.ModifierFlags.option.rawValue && keyCode == UInt16(kVK_Tab) {
      return .smartComplete
    }
    guard modifiers == 0 else { return nil }
    if keyCode == UInt16(kVK_Tab) { return .switchSourceTranslation }
    if keyCode == UInt16(kVK_Return) { return .commitRawInput }
    return nil
  }
}
struct FixtureSettings { var shortcuts = FixtureShortcuts() }
final class FixtureTranslator {
  var cancellations = 0
  func cancel() { cancellations += 1 }
}
final class FixtureAPI {
  var chosen: Int?
  var translation: String?
  var input: NSString = "wor"
  var completed: String?
  var acceptsSelection = true
  var pages: [Bool] = []
  func get_input(_ session: Int) -> UnsafePointer<CChar>? { input.utf8String }
  func set_input(_ session: Int, _ text: UnsafePointer<CChar>) -> Bool {
    completed = String(cString: text); return true
  }
  func change_page(_ session: Int, _ up: Bool) -> Bool { pages.append(up); return true }
  func select_candidate(_ session: Int, _ index: Int) -> Bool { chosen = index; return acceptsSelection }
  func select_candidate_with_text(_ session: Int, _ index: Int, _ text: UnsafePointer<CChar>) -> Bool {
    chosen = index; translation = String(cString: text); return acceptsSelection
  }
}
final class FixturePanel {
  var candidateSnapshot: SquirrelInputController.CandidateSnapshot?
  var status: String?
  func updateStatus(long: String, short: String, controller: SquirrelInputController) { status = long }
}
final class FixtureDelegate {
  var activeSettingsDocument: FixtureSettings? = .init()
  var panel: FixturePanel? = .init()
  var canAcceptRimeInput = true
}
let fixtureDelegate = FixtureDelegate()
extension NSApplication { var squirrelAppDelegate: FixtureDelegate { fixtureDelegate } }

final class SquirrelInputController {
  let rimeAPI = FixtureAPI()
  let candidateTranslator = FixtureTranslator()
  let session = 1
  var activeClient: NSObject? = .init()
  var hasPendingRimeInput = true
  var inputModeIdentity: (schemaID: String, asciiMode: Bool)? = ("linnet_en", false)
  var bilingualTranslationMode = true
  var bilingualSourceSnapshot: CandidateSnapshot?
  var bilingualCandidates = LinnetCandidatePresentation.TranslationCandidates()
  var rawCommits = 0
  var currentSession = true
  var updates = 0
  func sessionIsCurrent() -> Bool { currentSession }
  func rimeUpdate() { updates += 1 }
  func commitActiveComposition(to: NSObject) { rawCommits += 1 }
}

@main struct ZIMEHostRoutingTests {
  static func main() {
    _ = NSApplication.shared
    func key(_ code: Int, _ characters: String, _ flags: NSEvent.ModifierFlags = [], repeatKey: Bool = false) -> NSEvent {
      NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
        timestamp: 0, windowNumber: 0, context: nil, characters: characters,
        charactersIgnoringModifiers: characters, isARepeat: repeatKey, keyCode: UInt16(code))!
    }
    let source = SquirrelInputController.CandidateSnapshot(items: (0..<5).map { index in
      .init(absoluteIndex: index, page: 0, indexOnPage: index, text: "word\(index)",
        comment: LinnetCandidatePresentation.bilingualComment(displayText: "meaning", translations: ["one", "two", "three"], detailText: "detail"),
        selectionLabel: String(index + 1))
    }, currentPage: 0, pageSize: 5, highlightedItemIndex: 4, isLastPage: true)
    let owner = SquirrelInputController()
    owner.bilingualSourceSnapshot = source
    let page = owner.projectTranslationCandidates(from: source)
    precondition(page.items.count == 5 && page.items[page.highlightedItemIndex].sourceAbsoluteIndex == 4)
    fixtureDelegate.panel!.candidateSnapshot = .init(items: Array(page.items.prefix(1)), currentPage: 0,
      pageSize: 5, highlightedItemIndex: 0, isLastPage: true)
    precondition(owner.handleBilingualKeyDown(key(kVK_ANSI_2, "2"), modifiers: []) == true)
    precondition(owner.rimeAPI.chosen == nil && owner.bilingualTranslationMode)
    for flags: NSEvent.ModifierFlags in [.command, .option, .shift, [.shift, .option]] {
      precondition(owner.handleBilingualKeyDown(key(kVK_LeftArrow, "\u{f702}", flags), modifiers: flags) == nil)
      precondition(owner.bilingualTranslationMode, "host chord changed candidate state")
    }
    precondition(owner.handleBilingualKeyDown(key(kVK_Return, "\r"), modifiers: []) == true)
    precondition(owner.rawCommits == 1 && owner.rimeAPI.chosen == nil)
    precondition(owner.candidateTranslator.cancellations == 1 &&
      !owner.bilingualTranslationMode && owner.bilingualSourceSnapshot == nil)
    precondition(!owner.bilingualCandidates.changePage(backward: true), "raw Return retained translation rows")
    precondition(owner.handleBilingualKeyDown(key(kVK_Tab, "\t"), modifiers: []) == nil,
      "raw Return left a source snapshot that can reopen retired candidates")
    owner.bilingualTranslationMode = true
    precondition(owner.handleBilingualKeyDown(key(kVK_ANSI_1, "1"), modifiers: []) == true)
    precondition(owner.rimeAPI.chosen == page.items[0].sourceAbsoluteIndex &&
      owner.rimeAPI.translation == page.items[0].text && !owner.bilingualTranslationMode)
    owner.bilingualTranslationMode = true
    fixtureDelegate.panel!.candidateSnapshot = page
    let highlighted = page.items[page.highlightedItemIndex]
    precondition(owner.handleBilingualKeyDown(key(kVK_Space, " "), modifiers: []) == true)
    precondition(owner.rimeAPI.chosen == highlighted.sourceAbsoluteIndex &&
      owner.rimeAPI.translation == highlighted.commitOverride && owner.rawCommits == 1)
    owner.rimeAPI.chosen = nil
    precondition(owner.handleBilingualKeyDown(key(kVK_Space, " "), modifiers: []) == nil,
      "source-side Space must reach the native selector")
    owner.bilingualTranslationMode = true
    for flags: NSEvent.ModifierFlags in [.command, .option, .control, .shift] {
      precondition(owner.handleBilingualKeyDown(key(kVK_Space, " ", flags), modifiers: flags) == nil)
      precondition(owner.rimeAPI.chosen == nil)
    }
    fixtureDelegate.panel!.candidateSnapshot = .init(items: [], currentPage: 0,
      pageSize: 5, highlightedItemIndex: 0, isLastPage: true)
    precondition(owner.handleBilingualKeyDown(key(kVK_Space, " "), modifiers: []) == true)
    precondition(owner.rimeAPI.chosen == nil, "empty translation menu must not select a hidden source")
    owner.hasPendingRimeInput = false
    precondition(owner.handleBilingualKeyDown(key(kVK_Space, " "), modifiers: []) == nil)
    precondition(!owner.bilingualTranslationMode, "idle Space retained stale translation mode")
    owner.hasPendingRimeInput = true
    for details in ["", "你 [ni3]\nyou (informal, as opposed to courteous 您[nin2])"] {
      let ni = SquirrelInputController.CandidateSnapshot(items: [
        .init(absoluteIndex: 7, page: 1, indexOnPage: 2, text: "你",
          comment: LinnetCandidatePresentation.bilingualComment(displayText: "you", translations: ["you"], detailText: details),
          selectionLabel: "3")
      ], currentPage: 1, pageSize: 5, highlightedItemIndex: 0, isLastPage: true)
      owner.bilingualTranslationMode = true
      owner.bilingualCandidates.reset()
      let translated = owner.projectTranslationCandidates(from: ni)
      precondition(translated.items.map(\.text) == ["you"] && translated.items[0].commitOverride == "you")
      fixtureDelegate.panel!.candidateSnapshot = translated
      precondition(owner.handleBilingualKeyDown(key(kVK_Space, " "), modifiers: []) == true)
      precondition(owner.rimeAPI.chosen == 7 && owner.rimeAPI.translation == "you",
        "Space committed hover notes instead of the displayed core translation")
    }
    for label in ["ai", "腾讯", "百度", "DeepL"] {
      let raw = "  you (informal) / yourself; yours\n" + String(repeating: "完整译文", count: 100) + "  "
      let source = SquirrelInputController.CandidateSnapshot(items: [
        .init(absoluteIndex: 8, page: 1, indexOnPage: 3, text: "你",
          comment: LinnetCandidatePresentation.bilingualComment(displayText: "\(label):\(raw)", translations: [raw],
            detailText: "", sourceLabel: label), selectionLabel: "4")
      ], currentPage: 1, pageSize: 5, highlightedItemIndex: 0, isLastPage: true)
      owner.bilingualTranslationMode = true
      owner.bilingualCandidates.reset()
      let translated = owner.projectTranslationCandidates(from: source)
      precondition(translated.items.count == 1 && translated.items[0].text == raw
        && translated.items[0].comment == "\(label):你" && translated.items[0].commitOverride == raw)
      fixtureDelegate.panel!.candidateSnapshot = translated
      for event in [key(kVK_ANSI_1, "1"), key(kVK_Space, " ")] {
        owner.bilingualTranslationMode = true
        precondition(owner.handleBilingualKeyDown(event, modifiers: []) == true)
        precondition(owner.rimeAPI.chosen == 8 && owner.rimeAPI.translation == raw,
          "online numeric/Space commit split, trimmed, appended spacing or included the source label")
      }
    }
    for pending in [false, true] {
      let guarded = SquirrelInputController()
      guarded.hasPendingRimeInput = pending
      if pending { guarded.activeClient = nil }
      precondition(guarded.handleBilingualKeyDown(key(kVK_Return, "\r"), modifiers: []) == nil)
      precondition(guarded.rawCommits == 0 && guarded.candidateTranslator.cancellations == 0)
    }
    for blocked in 0..<4 {
      let guarded = SquirrelInputController()
      if blocked == 0 { guarded.activeClient = nil }
      if blocked == 1 { guarded.currentSession = false }
      if blocked == 2 { fixtureDelegate.canAcceptRimeInput = false }
      precondition(!guarded.selectCandidate(absoluteIndex: blocked == 3 ? -1 : 0))
      precondition(guarded.rimeAPI.chosen == nil && guarded.updates == 0)
      fixtureDelegate.canAcceptRimeInput = true
    }
    let guarded = SquirrelInputController()
    guarded.rimeAPI.acceptsSelection = false
    precondition(!guarded.selectCandidate(absoluteIndex: 0))
    precondition(guarded.bilingualTranslationMode && guarded.updates == 0)

    let toggled = SquirrelInputController()
    toggled.bilingualTranslationMode = false
    precondition(toggled.handleBilingualKeyDown(key(kVK_Tab, "\t"), modifiers: []) == nil)
    toggled.bilingualSourceSnapshot = source
    precondition(toggled.handleBilingualKeyDown(key(kVK_Tab, "\t"), modifiers: []) == true)
    precondition(toggled.bilingualTranslationMode)
    precondition(toggled.handleBilingualKeyDown(key(kVK_Tab, "\t", repeatKey: true), modifiers: []) == true)
    precondition(toggled.bilingualTranslationMode && toggled.updates == 1)
    precondition(toggled.handleBilingualKeyDown(key(kVK_Escape, "\u{1b}"), modifiers: []) == true)
    precondition(!toggled.bilingualTranslationMode)
    let plain = SquirrelInputController.CandidateSnapshot(items: [
      .init(absoluteIndex: 0, page: 0, indexOnPage: 0, text: "world", comment: "", selectionLabel: "1")
    ], currentPage: 0, pageSize: 5, highlightedItemIndex: 0, isLastPage: true)
    toggled.bilingualSourceSnapshot = plain
    precondition(toggled.handleBilingualKeyDown(key(kVK_Tab, "\t"), modifiers: []) == true)
    precondition(!toggled.bilingualTranslationMode && fixtureDelegate.panel?.status == "无译文")
    precondition(toggled.handleBilingualKeyDown(key(kVK_Tab, "\t", .option), modifiers: .option) == true)
    precondition(toggled.rimeAPI.completed == "world" && toggled.rawCommits == 0 && toggled.rimeAPI.chosen == nil)
    toggled.inputModeIdentity = ("linnet_zh_pinyin", false)
    toggled.rimeAPI.completed = nil
    precondition(toggled.handleBilingualKeyDown(key(kVK_Tab, "\t", .option), modifiers: .option) == nil)
    precondition(toggled.rimeAPI.completed == nil)
    toggled.bilingualTranslationMode = true
    for code in [kVK_ANSI_Minus, kVK_ANSI_Equal, kVK_PageUp, kVK_PageDown] {
      precondition(toggled.handleBilingualKeyDown(key(code, ""), modifiers: []) == true)
    }
    precondition(toggled.rimeAPI.pages.isEmpty && toggled.rawCommits == 0,
      "paging beyond first/last page must not commit or change the native page")
    print("ZIME production Host routing: guarded raw Return, cancellation, Space/digits, Tab/repeat/completion, paging boundaries, failed/stale selection and complete online commits: PASS")
  }
}
