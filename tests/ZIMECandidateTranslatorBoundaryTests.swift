import Foundation

// No sockets, credential store, private reflection or direct cache mutation.
// Tests observe annotate(), request/refresh events and an injected clock only.
@MainActor private final class TranslatorBoundaryState {
  var configuration: ZIMETranslationConfiguration = {
    var value = ZIMETranslationConfiguration()
    value.enabled = true
    return value
  }()
  var now = Date(timeIntervalSince1970: 10_000)
  var requests: [String] = []
  var credentialReads = 0
  var refreshes = 0
  var delays: [UInt64] = []
  var failure: Error?

  var immediateTiming: ZIMECandidateTranslator.Timing {
    .init(now: { self.now }, sleep: { delay in
      self.delays.append(delay)
      try Task.checkCancellation()
    })
  }

  func service(lexicon: ZIMELocalLexicon, timing: ZIMECandidateTranslator.Timing? = nil) -> ZIMECandidateTranslator {
    ZIMECandidateTranslator(lexicon: lexicon, loadConfiguration: { self.configuration },
      loadCredentials: { _ in self.credentialReads += 1; return .init(identifier: "synthetic") },
      translate: { _, _, term, _ in
        self.requests.append(term)
        if let failure = self.failure { throw failure }
        return "translated:\(term)"
      }, timing: timing ?? immediateTiming)
  }
}

@MainActor private final class TranslatorVirtualClock {
  private struct Wait {
    let id: UUID
    let deadline: UInt64
    let continuation: CheckedContinuation<Void, Error>
  }
  private var ticks: UInt64 = 0
  private var waits: [Wait] = []
  private(set) var delays: [UInt64] = []
  private(set) var completed = 0
  private(set) var cancelled = 0
  var pending: Int { waits.count }
  var timing: ZIMECandidateTranslator.Timing {
    .init(now: { Date(timeIntervalSinceReferenceDate: Double(self.ticks) / 1_000_000_000) },
      sleep: { try await self.sleep($0) })
  }

  private func sleep(_ delay: UInt64) async throws {
    try Task.checkCancellation()
    let id = UUID()
    delays.append(delay)
    defer { completed += 1 }
    try await withTaskCancellationHandler(operation: {
      try await withCheckedThrowingContinuation { continuation in
        waits.append(.init(id: id, deadline: ticks + delay, continuation: continuation))
      }
    }, onCancel: {
      Task { @MainActor in self.cancel(id) }
    })
    try Task.checkCancellation()
  }

  private func cancel(_ id: UUID) {
    guard let index = waits.firstIndex(where: { $0.id == id }) else { return }
    cancelled += 1
    waits.remove(at: index).continuation.resume(throwing: CancellationError())
  }

  func advance(_ nanoseconds: UInt64) {
    ticks += nanoseconds
    let ready = waits.filter { $0.deadline <= ticks }
    waits.removeAll { $0.deadline <= ticks }
    ready.forEach { $0.continuation.resume() }
  }
}

extension ZIMECandidateTranslatorTests {
  private static func boundarySnapshot(_ terms: [String], page: Int = 0,
    comments: [String]? = nil) -> SquirrelInputController.CandidateSnapshot {
    .init(items: terms.enumerated().map { index, term in
      .init(absoluteIndex: index, page: page, indexOnPage: index, text: term,
        comment: comments?[index] ?? "", selectionLabel: String(index + 1))
    }, currentPage: page, pageSize: 9, highlightedItemIndex: 0, isLastPage: true)
  }

  @MainActor private static func boundaryLoad(_ terms: [String], service: ZIMECandidateTranslator,
    state: TranslatorBoundaryState) async throws {
    let previous = state.refreshes
    let snapshot = boundarySnapshot(terms)
    _ = service.annotate(snapshot, showTranslation: true) { state.refreshes += 1 }
    try await waitUntil { state.refreshes >= previous + terms.count + 1 }
    let result = service.annotate(snapshot, showTranslation: true) { state.refreshes += 1 }
    check(result.items.map { LinnetCandidatePresentation.candidateComment($0.comment).translations }
      == terms.map { ["translated:\($0)"] }, "cache did not publish the completed provider field")
  }

  @MainActor static func runBoundaries(lexicon: ZIMELocalLexicon) async throws {
    try await cacheBoundaries(lexicon: lexicon)
    try await requestBoundaries(lexicon: lexicon)
    try await timingBoundaries(lexicon: lexicon)
    try await staleFailure(lexicon: lexicon)
    try await reentrantRefresh(lexicon: lexicon)
    print("Candidate translator boundaries: PASS (TTL/512 eviction/cooldown; request eligibility/page cap; exact debounce; cancellation/consent; reentrant refresh)")
  }

  @MainActor private static func cacheBoundaries(lexicon: ZIMELocalLexicon) async throws {
    let state = TranslatorBoundaryState()
    let service = state.service(lexicon: lexicon)
    let word = "ZIME虚拟时钟缓存条目"
    let initial = state.now
    try await boundaryLoad([word], service: service, state: state)
    state.now = initial.addingTimeInterval(599.999)
    let cached = service.annotate(boundarySnapshot([word]), showTranslation: true) {}
    check(cached.items[0].comment.contains("translated:") && state.requests == [word], "cache expired before 600 seconds")
    state.now = initial.addingTimeInterval(600)
    try await boundaryLoad([word], service: service, state: state)
    check(state.requests == [word, word], "cache remained valid at the exact TTL boundary")
    // Service identity changes invalidate cache even when the candidate stays.
    state.configuration.provider = .tencent
    try await boundaryLoad([word], service: service, state: state)
    check(state.requests.count == 3, "provider change reused another service's cache")
    service.cancel()

    let capacity = TranslatorBoundaryState()
    let bounded = capacity.service(lexicon: lexicon)
    let terms = (0...512).map { "ZIME容量边界唯一词\($0)" }
    for index in 0..<512 {
      capacity.now = initial.addingTimeInterval(Double(index))
      try await boundaryLoad([terms[index]], service: bounded, state: capacity)
    }
    let atLimit = bounded.annotate(boundarySnapshot([terms[0], terms[511]]), showTranslation: true) {}
    check(atLimit.items.allSatisfy { $0.comment.contains("translated:") } && capacity.requests.count == 512,
      "cache evicted an entry before reaching capacity")
    capacity.now = initial.addingTimeInterval(512)
    try await boundaryLoad([terms[512]], service: bounded, state: capacity)
    let newest = bounded.annotate(boundarySnapshot([terms[1], terms[511], terms[512]]), showTranslation: true) {}
    check(newest.items.allSatisfy { $0.comment.contains("translated:") } && capacity.requests.count == 513,
      "capacity eviction removed a newer entry")
    try await boundaryLoad([terms[0]], service: bounded, state: capacity)
    check(capacity.requests.count == 514, "oldest entry was not evicted at 513 entries")
    bounded.cancel()

    let failure = TranslatorBoundaryState()
    failure.failure = URLError(.timedOut)
    let unavailable = failure.service(lexicon: lexicon)
    _ = unavailable.annotate(boundarySnapshot([word]), showTranslation: true) { failure.refreshes += 1 }
    try await waitUntil { failure.refreshes == 1 }
    failure.now = initial.addingTimeInterval(29.999)
    let cooling = unavailable.annotate(boundarySnapshot([word]), showTranslation: true) {}
    check(cooling.items[0].comment == "无译文" && failure.requests.count == 1,
      "failed provider bypassed its 30-second cooldown")
    failure.failure = nil
    failure.now = initial.addingTimeInterval(30)
    try await boundaryLoad([word], service: unavailable, state: failure)
    check(failure.requests.count == 2, "provider did not retry at cooldown expiry")
    unavailable.cancel()
  }

  @MainActor private static func requestBoundaries(lexicon: ZIMELocalLexicon) async throws {
    let state = TranslatorBoundaryState()
    let service = state.service(lexicon: lexicon)
    let blocked = ["", " \n", "ZIME隐私@example.invalid", "https://example.invalid/中文",
      String(repeating: "未知", count: 32) + "字", "unmarked-raw-english"]
    let snapshot = boundarySnapshot(blocked)
    let hidden = service.annotate(snapshot, showTranslation: false) { state.refreshes += 1 }
    check(hidden == snapshot, "hiding translation altered the source snapshot")
    let rejected = service.annotate(snapshot, showTranslation: true) { state.refreshes += 1 }
    check(rejected.items.allSatisfy { $0.comment == "无译文" } && state.delays.isEmpty
      && state.credentialReads == 0 && state.requests.isEmpty, "ineligible term was scheduled for remote lookup")
    state.configuration.showFullAnnotations = true
    let englishLocal = service.annotate(boundarySnapshot(["apple"]), showTranslation: true) {}
    let localGloss = LinnetCandidatePresentation.candidateComment(englishLocal.items[0].comment)
    check(localGloss.translations.contains("苹果") &&
      LinnetCandidatePresentation.fullCandidateComment(englishLocal.items[0].comment).contains("苹果") && state.delays.isEmpty,
      "English reverse-dictionary details were omitted or sent online")
    // The exact 64-character limit and explicitly marked English are eligible.
    let word64 = String(repeating: "未知", count: 32)
    let english = "zime-synthetic-English-unknown"
    let eligible = boundarySnapshot([word64, english], comments: ["", "\u{001D}"])
    _ = service.annotate(eligible, showTranslation: true) { state.refreshes += 1 }
    try await waitUntil { state.refreshes == 3 }
    check(state.requests == [word64, english], "valid boundary or marked English was incorrectly blocked")
    service.cancel()

    let pages = TranslatorBoundaryState()
    let pageService = pages.service(lexicon: lexicon)
    let words = (0..<12).map { "ZIME页内去重边界\($0)" }
    var pageItems = boundarySnapshot([words[0]] + words, page: 1).items
    pageItems += boundarySnapshot(["ZIME其他页面禁止请求"], page: 0).items
    let page = SquirrelInputController.CandidateSnapshot(items: pageItems, currentPage: 1,
      pageSize: 9, highlightedItemIndex: 0, isLastPage: false)
    _ = pageService.annotate(page, showTranslation: true) { pages.refreshes += 1 }
    try await waitUntil { pages.refreshes == 10 }
    check(pages.requests == Array(words.prefix(9)), "remote lookup crossed page, duplicate or nine-term boundary")
    check(pages.delays == [400_000_000] + Array(repeating: 1_000_000_000, count: 8),
      "page requests lost their debounce/rate limit")
    pageService.cancel()
  }

  @MainActor private static func timingBoundaries(lexicon: ZIMELocalLexicon) async throws {
    let state = TranslatorBoundaryState()
    let clock = TranslatorVirtualClock()
    let service = state.service(lexicon: lexicon, timing: clock.timing)
    let word = "ZIME定时器边界未收录"
    _ = service.annotate(boundarySnapshot([word]), showTranslation: true) { state.refreshes += 1 }
    try await waitUntil { clock.pending == 1 }
    clock.advance(399_999_999)
    check(state.requests.isEmpty && state.credentialReads == 0, "credentials accessed before debounce")
    clock.advance(1)
    try await waitUntil { state.refreshes == 2 }
    check(state.requests == [word] && clock.delays == [400_000_000], "debounce did not complete at 400 ms")
    let next = boundarySnapshot(["ZIME关闭显示未收录"])
    _ = service.annotate(next, showTranslation: true) { state.refreshes += 1 }
    try await waitUntil { clock.pending == 1 }
    check(service.annotate(next, showTranslation: false) {} == next)
    try await waitUntil { clock.cancelled == 1 && clock.pending == 0 }
    clock.advance(1_000_000_000)
    check(state.requests == [word] && state.refreshes == 2, "hidden panel retained an active query")

    let consent = TranslatorBoundaryState()
    let consentClock = TranslatorVirtualClock()
    let consentService = consent.service(lexicon: lexicon, timing: consentClock.timing)
    let two = ["ZIME限流同意边界一", "ZIME限流同意边界二"]
    _ = consentService.annotate(boundarySnapshot(two), showTranslation: true) { consent.refreshes += 1 }
    try await waitUntil { consentClock.pending == 1 }
    consentClock.advance(400_000_000)
    try await waitUntil { consent.requests.count == 1 && consentClock.pending == 1 }
    consent.configuration.enabled = false
    consentClock.advance(1_000_000_000)
    try await waitUntil { consentClock.completed == 2 }
    check(consent.requests == [two[0]] && consent.credentialReads == 1 && consent.refreshes == 1,
      "consent withdrawal during rate-limit wait sent a second term")
    consentService.cancel()

    let immediateConsent = TranslatorBoundaryState()
    let immediateService = immediateConsent.service(lexicon: lexicon)
    _ = immediateService.annotate(boundarySnapshot(two), showTranslation: true) {
      immediateConsent.refreshes += 1
      immediateConsent.configuration.enabled = false
    }
    try await waitUntil { immediateConsent.refreshes == 1 }
    check(immediateConsent.requests == [two[0]] && immediateConsent.delays == [400_000_000],
      "withdrawn consent entered another rate-limit wait")
    immediateService.cancel()

    let released = TranslatorBoundaryState()
    let releasedClock = TranslatorVirtualClock()
    var owner: ZIMECandidateTranslator? = released.service(lexicon: lexicon, timing: releasedClock.timing)
    weak var weakOwner: ZIMECandidateTranslator?
    weakOwner = owner
    _ = owner!.annotate(boundarySnapshot([word]), showTranslation: true) { released.refreshes += 1 }
    try await waitUntil { releasedClock.pending == 1 }
    owner = nil
    check(weakOwner == nil, "debounce retained the retired controller")
    releasedClock.advance(400_000_000)
    try await waitUntil { releasedClock.completed == 1 }
    check(released.credentialReads == 0 && released.requests.isEmpty && released.refreshes == 0,
      "retired controller continued translation")
  }

  @MainActor private static func staleFailure(lexicon: ZIMELocalLexicon) async throws {
    let state = TranslatorBoundaryState()
    var pending: CheckedContinuation<String, Error>?
    var hold = true
    var finished = false
    let service = ZIMECandidateTranslator(lexicon: lexicon, loadConfiguration: { state.configuration },
      loadCredentials: { _ in .init(identifier: "synthetic") },
      translate: { _, _, term, _ in
        state.requests.append(term)
        if hold {
          defer { finished = true }
          return try await withCheckedThrowingContinuation { pending = $0 }
        }
        return "translated:\(term)"
      }, timing: state.immediateTiming)
    let word = "ZIME迟到失败不能影响新查询"
    _ = service.annotate(boundarySnapshot([word]), showTranslation: true) { state.refreshes += 1 }
    try await waitUntil { pending != nil }
    service.cancel()
    hold = false
    pending!.resume(throwing: URLError(.notConnectedToInternet))
    pending = nil
    try await waitUntil { finished }
    check(state.refreshes == 0, "stale failure refreshed the retired composition")
    try await boundaryLoad([word], service: service, state: state)
    check(state.requests == [word, word], "stale failure cooled down the next composition")
    service.cancel()
  }

  @MainActor private static func reentrantRefresh(lexicon: ZIMELocalLexicon) async throws {
    let state = TranslatorBoundaryState()
    let service = state.service(lexicon: lexicon)
    let words = ["ZIME重入刷新第一页", "ZIME重入刷新第二页"]
    var moved = false
    _ = service.annotate(boundarySnapshot([words[0]]), showTranslation: true) {
      state.refreshes += 1
      if !moved {
        moved = true
        _ = service.annotate(boundarySnapshot([words[1]]), showTranslation: true) { state.refreshes += 1 }
      }
    }
    try await waitUntil { state.refreshes == 3 }
    check(state.requests == words, "old completion overwrote the reentrant page request")
    service.cancel()
  }
}
