import AppKit
import Carbon

// Inject only IMK/Rime boundary effects; the three methods below are extracted
// verbatim from production for this executable test, not reimplemented here.
struct FixtureShortcuts {
  enum Action { case switchSourceTranslation, commitRawInput, smartComplete }
  static let `default` = Self()
  func action(keyCode: UInt16, modifiers: UInt) -> Action? {
    guard modifiers == 0 else { return nil }
    if keyCode == UInt16(kVK_Tab) { return .switchSourceTranslation }
    if keyCode == UInt16(kVK_Return) { return .commitRawInput }
    return nil
  }
}
struct FixtureSettings { var shortcuts = FixtureShortcuts() }
final class FixtureTranslator { func cancel() {} }
final class FixtureAPI {
  var chosen: Int?
  var translation: String?
  func get_input(_ session: Int) -> UnsafePointer<CChar>? { nil }
  func set_input(_ session: Int, _ text: UnsafePointer<CChar>) -> Bool { true }
  func select_candidate(_ session: Int, _ index: Int) -> Bool { chosen = index; return true }
  func select_candidate_with_text(_ session: Int, _ index: Int, _ text: UnsafePointer<CChar>) -> Bool {
    chosen = index; translation = String(cString: text); return true
  }
}
final class FixturePanel {
  var candidateSnapshot: FixtureController.CandidateSnapshot?
  func updateStatus(long: String, short: String, controller: FixtureController) {}
}
final class FixtureDelegate {
  var activeSettingsDocument: FixtureSettings? = .init()
  var panel: FixturePanel? = .init()
  var canAcceptRimeInput = true
}
let fixtureDelegate = FixtureDelegate()
extension NSApplication { var squirrelAppDelegate: FixtureDelegate { fixtureDelegate } }

final class FixtureController {
  // INJECT_SNAPSHOT
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
  func sessionIsCurrent() -> Bool { true }
  func rimeUpdate() {}
  func commitActiveComposition(to: NSObject) { rawCommits += 1 }
  func page(up: Bool) -> Bool { true }
  // INJECT_HANDLE
  // INJECT_PROJECT
  // INJECT_SELECT
}

@main struct ZIMEHostRoutingTests {
  static func main() {
    _ = NSApplication.shared
    func key(_ code: Int, _ characters: String, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
      NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
        timestamp: 0, windowNumber: 0, context: nil, characters: characters,
        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(code))!
    }
    let source = FixtureController.CandidateSnapshot(items: (0..<5).map { index in
      .init(absoluteIndex: index, page: 0, indexOnPage: index, text: "word\(index)",
        comment: LinnetCandidatePresentation.bilingualComment(displayText: "meaning", translations: ["one", "two", "three"], detailText: "detail"),
        selectionLabel: String(index + 1))
    }, currentPage: 0, pageSize: 5, highlightedItemIndex: 4, isLastPage: true)
    let owner = FixtureController()
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
    owner.bilingualTranslationMode = true
    precondition(owner.handleBilingualKeyDown(key(kVK_ANSI_1, "1"), modifiers: []) == true)
    precondition(owner.rimeAPI.chosen == page.items[0].sourceAbsoluteIndex &&
      owner.rimeAPI.translation == page.items[0].text && !owner.bilingualTranslationMode)
    for details in ["", "你 [ni3]\nyou (informal, as opposed to courteous 您[nin2])"] {
      let ni = FixtureController.CandidateSnapshot(items: [
        .init(absoluteIndex: 7, page: 1, indexOnPage: 2, text: "你",
          comment: LinnetCandidatePresentation.bilingualComment(displayText: "you", translations: ["you"], detailText: details),
          selectionLabel: "3")
      ], currentPage: 1, pageSize: 5, highlightedItemIndex: 0, isLastPage: true)
      owner.bilingualTranslationMode = true
      owner.bilingualCandidates.reset()
      let translated = owner.projectTranslationCandidates(from: ni)
      precondition(translated.items.map(\.text) == ["you"] && translated.items[0].commitOverride == "you")
      fixtureDelegate.panel!.candidateSnapshot = translated
      precondition(owner.handleBilingualKeyDown(key(kVK_ANSI_1, "1"), modifiers: []) == true)
      precondition(owner.rimeAPI.chosen == 7 && owner.rimeAPI.translation == "you",
        "numeric selection committed hover notes instead of the displayed core translation")
    }
    for label in ["ai", "腾讯", "百度", "DeepL"] {
      let raw = "  you (informal) / yourself; yours\n" + String(repeating: "完整译文", count: 100) + "  "
      let source = FixtureController.CandidateSnapshot(items: [
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
      precondition(owner.handleBilingualKeyDown(key(kVK_ANSI_1, "1"), modifiers: []) == true)
      precondition(owner.rimeAPI.chosen == 8 && owner.rimeAPI.translation == raw,
        "online numeric commit split, trimmed or included the source label")
    }
    print("ZIME production Host routing: missing digits, modified arrows, raw Return, paged identity and complete source-labeled online commits: PASS")
  }
}
