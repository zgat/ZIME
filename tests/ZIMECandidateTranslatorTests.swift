import Foundation

// Same snapshot fixture boundary used by the Rime snapshot-builder unit tests.
final class SquirrelInputController {
  struct CandidateItem: Equatable {
    let absoluteIndex: Int
    let page: Int
    let indexOnPage: Int
    let text: String
    var comment: String
    let selectionLabel: String?
    var sourceAbsoluteIndex: Int? = nil
    var commitOverride: String? = nil
    var emphasizesPrimaryText = false
  }
  struct CandidateSnapshot: Equatable {
    let items: [CandidateItem]
    let currentPage: Int
    let pageSize: Int
    let highlightedItemIndex: Int
    let isLastPage: Bool
    let canExpand: Bool
    let isExpanded: Bool
  }
}

@main
struct ZIMECandidateTranslatorTests {
  @MainActor static func main() async throws {
    let lexicon = ZIMELocalLexicon(url: URL(fileURLWithPath: "resources/zime-cedict.sqlite3"))
    var config = ZIMETranslationConfiguration()
    var sent: [String] = []
    var reads = 0
    var refreshes = 0
    let translator = ZIMECandidateTranslator(lexicon: lexicon, loadConfiguration: { config },
      loadCredentials: { _ in reads += 1; return .init(identifier: "fixture") },
      translate: { _, _, text, _ in
        sent.append(text)
        // Deliberately emulate a transport that completes after cancellation.
        try? await Task.sleep(nanoseconds: 150_000_000)
        return "fixture translation"
      })
    let words = ["帅", "下班", "你好", "ZIME测试未收录词"]
    let snapshot = SquirrelInputController.CandidateSnapshot(items: words.enumerated().map { i, text in
      .init(absoluteIndex: i, page: 0, indexOnPage: i, text: text, comment: "shuai", selectionLabel: String(i + 1))
    }, currentPage: 0, pageSize: 4, highlightedItemIndex: 0, isLastPage: true, canExpand: false, isExpanded: false)
    let local = translator.annotate(snapshot, showTranslation: true) { refreshes += 1 }
    precondition(local.items.map(\.text) == words && local.items.map(\.absoluteIndex) == [0,1,2,3])
    precondition(local.items.allSatisfy { $0.commitOverride == nil && !$0.comment.isEmpty })
    precondition(LinnetCandidatePresentation.candidateComment(local.items[0].comment).translations.first?.contains("handsome") == true)
    precondition(local.items[3].comment == "暂无本地译文")
    try await Task.sleep(nanoseconds: 650_000_000)
    precondition(sent.isEmpty && reads == 0 && refreshes == 0, "disabled cloud must access neither network nor credentials")

    config.enabled = true
    _ = translator.annotate(snapshot, showTranslation: true) { refreshes += 1 }
    // Cancel during debounce: even keychain access must not have happened.
    translator.cancel()
    try await Task.sleep(nanoseconds: 500_000_000)
    precondition(sent.isEmpty && reads == 0)
    _ = translator.annotate(snapshot, showTranslation: true) { refreshes += 1 }
    try await Task.sleep(nanoseconds: 450_000_000)
    translator.cancel()
    try await Task.sleep(nanoseconds: 250_000_000)
    precondition(sent == [words[3]] && refreshes == 0, "late response must not repaint a retired composition")

    _ = translator.annotate(snapshot, showTranslation: true) { refreshes += 1 }
    try await Task.sleep(nanoseconds: 700_000_000)
    let completed = translator.annotate(snapshot, showTranslation: true) { refreshes += 1 }
    precondition(LinnetCandidatePresentation.candidateComment(completed.items[3].comment).translations == ["fixture translation"])
    let count = sent.count
    _ = translator.annotate(snapshot, showTranslation: true) { refreshes += 1 }
    try await Task.sleep(nanoseconds: 500_000_000)
    precondition(sent.count == count, "cached translation must not trigger another request")
    print("ZIMECandidateTranslatorTests: PASS (mock transport only)")
  }
}
