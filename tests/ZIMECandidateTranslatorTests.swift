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
    let cloudText = "  fixture translation (informal, e.g. a nested (example)) / alternative; synonym\nsecond line  "
    let translator = ZIMECandidateTranslator(lexicon: lexicon, loadConfiguration: { config },
      loadCredentials: { _ in reads += 1; return .init(identifier: "fixture") },
      translate: { _, _, text, _ in
        sent.append(text)
        // Deliberately emulate a transport that completes after cancellation.
        try? await Task.sleep(nanoseconds: 150_000_000)
        return cloudText
      })
    let words = ["帅", "下班", "你好", "ZIME测试未收录词"]
    let snapshot = SquirrelInputController.CandidateSnapshot(items: words.enumerated().map { i, text in
      .init(absoluteIndex: i, page: 0, indexOnPage: i, text: text, comment: "shuai", selectionLabel: String(i + 1))
    }, currentPage: 0, pageSize: 4, highlightedItemIndex: 0, isLastPage: true)
    let local = translator.annotate(snapshot, showTranslation: true) { refreshes += 1 }
    precondition(local.items.map(\.text) == words && local.items.map(\.absoluteIndex) == [0,1,2,3])
    precondition(local.items.allSatisfy { $0.commitOverride == nil && !$0.comment.isEmpty })
    precondition(LinnetCandidatePresentation.candidateComment(local.items[0].comment).translations.first?.contains("handsome") == true)
    precondition(local.items[3].comment == "无译文")
    precondition(local.items.prefix(3).allSatisfy { LinnetCandidatePresentation.fullCandidateComment($0.comment).isEmpty },
      "full annotations must default off")
    let emojiSnapshot = SquirrelInputController.CandidateSnapshot(items: [
      .init(absoluteIndex: 0, page: 0, indexOnPage: 0, text: "😀", comment: "\u{001B}笑脸", selectionLabel: "1")
    ], currentPage: 0, pageSize: 5, highlightedItemIndex: 0, isLastPage: true)
    let annotatedEmoji = translator.annotate(emojiSnapshot, showTranslation: true) {}
    precondition(annotatedEmoji.items[0].text == "😀" &&
      !LinnetCandidatePresentation.candidateComment(annotatedEmoji.items[0].comment).translations.isEmpty,
      "emoji must keep its glyph and inherit a local definition from its source word")
    // Native metadata now also marks lowercase/mixed-case raw acronym rows
    // and acronyms from the Chinese phrase dictionary. The Host must retain
    // that definition even though the CC-CEDICT reverse index lacks ime.
    let acronymSpellings = ["ime", "Ime", "IME", "iMe", "iME"]
    let acronyms = SquirrelInputController.CandidateSnapshot(items: acronymSpellings.enumerated().map { i, text in
      .init(absoluteIndex: i, page: 0, indexOnPage: i, text: text,
        comment: "\u{001D}输入法编辑器", selectionLabel: String(i + 1))
    }, currentPage: 0, pageSize: 5, highlightedItemIndex: 0, isLastPage: true)
    let annotatedAcronyms = translator.annotate(acronyms, showTranslation: true) {}
    precondition(annotatedAcronyms.items.map(\.text) == acronymSpellings)
    precondition(annotatedAcronyms.items.map(\.absoluteIndex) == [0, 1, 2, 3, 4])
    precondition(annotatedAcronyms.items.allSatisfy {
      $0.commitOverride == nil && LinnetCandidatePresentation.candidateComment($0.comment).translations == ["输入法编辑器"]
    }, "case-insensitive native definitions were lost or changed commit text at the Host boundary")
    let regionalWords = ["你", "土豆", "德士", "妳", "帥", "髮", "發", "拟", "擬"]
    let regionalSnapshot = SquirrelInputController.CandidateSnapshot(items: regionalWords.enumerated().map { i, text in
      // Native fallback must never defeat the better direct headword lookup.
      .init(absoluteIndex: i, page: 0, indexOnPage: i, text: text,
        comment: "\u{001E}(Singapore, Malaysia) taxi", selectionLabel: String(i + 1))
    }, currentPage: 0, pageSize: 9, highlightedItemIndex: 0, isLastPage: true)
    for region in [ZIMELocalLexicon.RegionProfile.mainland, .traditionalRegions, .mainland] {
      let regional = translator.annotate(regionalSnapshot, showTranslation: true, region: region) {}
      precondition(regional.items.map(\.text) == regionalWords)
      precondition(regional.items.allSatisfy { $0.commitOverride == nil })
      precondition(regional.items.allSatisfy { !LinnetCandidatePresentation.candidateComment($0.comment).translations.isEmpty },
        "candidate lost its translation because of the active mode or region")
      let ni = LinnetCandidatePresentation.candidateComment(regional.items[0].comment)
      precondition(ni.displayText == "you" && ni.translations == ["you"],
        "annotation transport lost deduplication or exposed the detail payload")
      let niDetail = LinnetCandidatePresentation.fullCandidateComment(regional.items[0].comment)
      precondition(niDetail.isEmpty, "unrequested full notes leaked into hover/AX help")
      let potato = LinnetCandidatePresentation.candidateComment(regional.items[1].comment).translations
      precondition(potato.contains { $0.contains("peanut") } == (region == .traditionalRegions))
      precondition(LinnetCandidatePresentation.candidateComment(regional.items[2].comment).translations == ["taxi"])
    }
    config.showFullAnnotations = true
    let withDetails = translator.annotate(regionalSnapshot, showTranslation: true) {}
    precondition(LinnetCandidatePresentation.fullCandidateComment(withDetails.items[0].comment).contains("您[nin2]"))
    precondition(LinnetCandidatePresentation.candidateComment(withDetails.items[0].comment).translations == ["you"],
      "enabling hover annotations changed the committed translation")
    let nativeSnapshot = SquirrelInputController.CandidateSnapshot(items: [
      .init(absoluteIndex: 0, page: 0, indexOnPage: 0, text: "ZIME测试本地未收录", comment: "\u{001E}(HK) core meaning (usage note)", selectionLabel: "1"),
      .init(absoluteIndex: 1, page: 0, indexOnPage: 1, text: "test-acronym", comment: "\u{001D}/aɪ/ · n. 译文（注释：词性）; v. 翻译（注释：动词用法）", selectionLabel: "2")
    ], currentPage: 0, pageSize: 5, highlightedItemIndex: 0, isLastPage: true)
    let native = translator.annotate(nativeSnapshot, showTranslation: true) {}
    precondition(LinnetCandidatePresentation.candidateComment(native.items[0].comment).translations == ["core meaning"])
    precondition(LinnetCandidatePresentation.candidateComment(native.items[1].comment).translations == ["译文", "翻译"])
    precondition(LinnetCandidatePresentation.candidateComment(native.items[1].comment).displayText == "/aɪ/ · n. 译文; v. 翻译",
      "core gloss projection damaged IPA or part-of-speech display")
    precondition(LinnetCandidatePresentation.fullCandidateComment(native.items[1].comment).contains("注释"))
    config.showFullAnnotations = false
    try await Task.sleep(nanoseconds: 650_000_000)
    precondition(sent.isEmpty && reads == 0 && refreshes == 0, "disabled cloud must access neither network nor credentials")

    config.enabled = true
    let aliasWords = ["费城", "費城", "世博", "瞭解", "明天见", "妳", "髮"]
    let aliases = SquirrelInputController.CandidateSnapshot(items: aliasWords.enumerated().map { i, word in
      .init(absoluteIndex: i, page: 0, indexOnPage: i, text: word, comment: "", selectionLabel: String(i + 1))
    }, currentPage: 0, pageSize: 7, highlightedItemIndex: 0, isLastPage: true)
    let localAliases = translator.annotate(aliases, showTranslation: true) {}
    precondition(localAliases.items.allSatisfy { !LinnetCandidatePresentation.candidateComment($0.comment).translations.isEmpty })
    try await Task.sleep(nanoseconds: 650_000_000)
    precondition(sent.isEmpty && reads == 0, "local or referenced meanings must not access cloud or credentials")
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
    let cloudComment = LinnetCandidatePresentation.candidateComment(completed.items[3].comment)
    precondition(cloudComment.translations == [cloudText] && cloudComment.sourceLabel == "ai"
      && cloudComment.displayText == "ai:\(cloudText)", "online field and display-only source were conflated")
    let count = sent.count
    _ = translator.annotate(snapshot, showTranslation: true) { refreshes += 1 }
    try await Task.sleep(nanoseconds: 500_000_000)
    precondition(sent.count == count, "cached translation must not trigger another request")
    config.showFullAnnotations = true
    let cachedDetails = translator.annotate(snapshot, showTranslation: true) { refreshes += 1 }
    precondition(LinnetCandidatePresentation.fullCandidateComment(cachedDetails.items[3].comment).isEmpty)
    precondition(LinnetCandidatePresentation.candidateComment(cachedDetails.items[3].comment).translations == [cloudText])
    let translated = translator.annotate(regionalSnapshot, showTranslation: true, region: .mainland) { refreshes += 1 }
    precondition(LinnetCandidatePresentation.candidateComment(translated.items[2].comment).translations == ["taxi"])
    try await Task.sleep(nanoseconds: 650_000_000)
    precondition(sent.count == count, "details toggle or known regional word caused another API request")
    var failedRequests = 0
    let unavailable = ZIMECandidateTranslator(lexicon: lexicon, loadConfiguration: { config },
      loadCredentials: { _ in .init(identifier: "fixture") },
      translate: { _, _, _, _ in
        failedRequests += 1
        throw URLError(.timedOut)
      })
    let loading = unavailable.annotate(snapshot, showTranslation: true) {}
    precondition(loading.items[3].comment == "译文查询中…", "pending requests lost the loading state")
    try await Task.sleep(nanoseconds: 700_000_000)
    let failed = unavailable.annotate(snapshot, showTranslation: true) {}
    precondition(failedRequests == 1 && failed.items[3].comment == "无译文",
      "offline misses and unavailable cloud results must share one label")
    precondition(LinnetCandidatePresentation.candidateComment(failed.items[3].comment).translations.isEmpty,
      "the unavailable hint must never become a committable translation")
    precondition(failed.items[3].comment == local.items[3].comment)
    for provider in [ZIMETranslationConfiguration.Provider.deepl, .baidu, .tencent] {
      var providerConfig = config
      providerConfig.provider = provider
      let frozenConfiguration = providerConfig
      var providerRequests = 0
      let service = ZIMECandidateTranslator(lexicon: lexicon, loadConfiguration: { frozenConfiguration },
        loadCredentials: { _ in .init(identifier: "fixture", secret: "fixture") },
        translate: { _, _, _, _ in providerRequests += 1; return cloudText })
      _ = service.annotate(snapshot, showTranslation: true) {}
      try await Task.sleep(nanoseconds: 650_000_000)
      let annotated = service.annotate(snapshot, showTranslation: true) {}
      let result = LinnetCandidatePresentation.candidateComment(annotated.items[3].comment)
      precondition(providerRequests == 1 && result.sourceLabel == provider.candidateSourceLabel
        && result.displayText == "\(provider.candidateSourceLabel):\(cloudText)" && result.translations == [cloudText],
        "provider source label missing, or local meanings sent online")
    }
    var consent = config
    var consentReads = 0
    var consentRequests: [String] = []
    let consentService = ZIMECandidateTranslator(lexicon: lexicon, loadConfiguration: { consent },
      loadCredentials: { _ in consentReads += 1; return .init(identifier: "fixture") },
      translate: { _, _, text, _ in consentRequests.append(text); return cloudText })
    _ = consentService.annotate(snapshot, showTranslation: true) {}
    try await Task.sleep(nanoseconds: 200_000_000)
    consent.enabled = false
    try await Task.sleep(nanoseconds: 450_000_000)
    precondition(consentReads == 0 && consentRequests.isEmpty, "disabled during debounce still accessed credentials")
    consent.enabled = true
    let twoUnknowns = SquirrelInputController.CandidateSnapshot(items: ["ZIME测试未收录词一", "ZIME测试未收录词二"].enumerated().map { i, word in
      .init(absoluteIndex: i, page: 0, indexOnPage: i, text: word, comment: "", selectionLabel: String(i + 1))
    }, currentPage: 0, pageSize: 5, highlightedItemIndex: 0, isLastPage: true)
    _ = consentService.annotate(twoUnknowns, showTranslation: true) {}
    try await Task.sleep(nanoseconds: 650_000_000)
    consent.enabled = false
    try await Task.sleep(nanoseconds: 900_000_000)
    precondition(consentReads == 1 && consentRequests == ["ZIME测试未收录词一"],
      "disabled during rate-limit wait still sent a second candidate")
    print("ZIMECandidateTranslatorTests: PASS (mock transport only)")
  }
}
