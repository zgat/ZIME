// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// One controller owns each cancellable page request. Results are keyed by
/// exact text + provider configuration, never by candidate position.
final class ZIMECandidateTranslator {
  private static let lexicon = ZIMELocalLexicon(url: Bundle.main.url(forResource: "zime-cedict", withExtension: "sqlite3"))
  private let localLexicon: ZIMELocalLexicon
  private let loadConfiguration: () -> ZIMETranslationConfiguration
  private let loadCredentials: (String) throws -> ZIMETranslationCredentials
  private let translate: (ZIMETranslationConfiguration, ZIMETranslationCredentials, String, Bool) async throws -> String
  private var task: Task<Void, Never>?
  private var generation = UUID()
  private var pageKey: [String] = []
  private var configuration = ZIMETranslationConfiguration()
  private var region = ZIMELocalLexicon.RegionProfile.mainland
  private var cache: [String: (text: String, expires: Date)] = [:]
  private var cooldownUntil = Date.distantPast

  init(lexicon: ZIMELocalLexicon? = nil,
    loadConfiguration: @escaping () -> ZIMETranslationConfiguration = ZIMETranslationConfiguration.load,
    loadCredentials: @escaping (String) throws -> ZIMETranslationCredentials = { try ZIMETranslationCredentials.load(account: $0) },
    translate: @escaping (ZIMETranslationConfiguration, ZIMETranslationCredentials, String, Bool) async throws -> String = {
      try await ZIMETranslationHTTP.translate(configuration: $0, credentials: $1, text: $2, chinese: $3)
    }
  ) {
    localLexicon = lexicon ?? Self.lexicon
    self.loadConfiguration = loadConfiguration
    self.loadCredentials = loadCredentials
    self.translate = translate
  }

  func cancel() {
    task?.cancel()
    task = nil
    generation = UUID()
    pageKey = []
  }

  func annotate(_ snapshot: SquirrelInputController.CandidateSnapshot,
    showTranslation: Bool, region: ZIMELocalLexicon.RegionProfile = .mainland,
    refresh: @escaping () -> Void
  ) -> SquirrelInputController.CandidateSnapshot {
    let currentConfiguration = loadConfiguration()
    if configuration != currentConfiguration || self.region != region {
      cancel()
      cache.removeAll()
      cooldownUntil = .distantPast
      configuration = currentConfiguration
      self.region = region
    }
    if !showTranslation || !configuration.enabled { cancel() }
    var missing: [String] = []
    let items = snapshot.items.map { item -> SquirrelInputController.CandidateItem in
      let original = LinnetCandidatePresentation.candidateComment(item.comment)
      let chinese = ZIMELocalLexicon.containsHan(item.text)
      let allSenses = localLexicon.translations(for: item.text)
      let exact = localLexicon.translations(for: item.text, region: region)
      let excludedByRegion = chinese && !allSenses.isEmpty && exact.isEmpty
      let originalTranslations = chinese
        ? ZIMELocalLexicon.regionalTranslations(original.translations, for: item.text, region: region)
        : original.translations
      // A direct Chinese dictionary definition outranks reverse English senses
      // such as surname romanizations. Preserve English IPA when already known.
      let translations = excludedByRegion ? [] : chinese && !exact.isEmpty ? Array(exact.prefix(3))
        : !originalTranslations.isEmpty ? originalTranslations : Array(exact.prefix(3))
      let term = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
      let cached = cache[term].flatMap { $0.expires > Date() ? $0.text : nil }
      let canRequest = !excludedByRegion && showTranslation && configuration.enabled && item.page == snapshot.currentPage && term.count <= 64
        && !term.isEmpty && (chinese || item.comment.hasPrefix(LinnetCandidatePresentation.smartEnglishDetailPrefix))
        && !term.contains("@") && !term.contains("://")
      var comment = item.comment
      if showTranslation {
        if !translations.isEmpty {
          comment = !chinese && !original.translations.isEmpty ? item.comment : Self.comment(translations)
        } else if !excludedByRegion, let cached, !cached.isEmpty {
          comment = Self.comment([cached])
        } else {
          // Unmarked comments are spelling hints, never English translations.
          comment = excludedByRegion ? "当前地区暂无本地释义" : "暂无本地译文"
          if canRequest {
            if cached == nil && cooldownUntil <= Date() {
              if !missing.contains(term) { missing.append(term) }
              comment = "译文查询中…"
            } else { comment = "暂无译文 · 云翻译暂不可用" }
          }
        }
      }
      var result = item
      result.comment = comment
      result.emphasizesPrimaryText = showTranslation
      return result
    }
    // Limit requests to the selected page even if the user expanded browsing.
    let currentPageTerms = snapshot.items.filter { $0.page == snapshot.currentPage }.map {
      $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let currentTerms = Set(currentPageTerms)
    missing = Array(missing.filter { currentTerms.contains($0) }.prefix(9))
    if missing.isEmpty { cancel() }
    else if currentPageTerms != pageKey {
      cancel()
      pageKey = currentPageTerms
      let token = generation
      let selected = configuration
      task = Task { @MainActor [weak self] in
        do {
          try await Task.sleep(nanoseconds: 400_000_000)
          guard let self, self.generation == token else { return }
          let credentials = try self.loadCredentials(selected.credentialAccount)
          for (index, text) in missing.enumerated() {
            try Task.checkCancellation()
            guard self.generation == token, self.loadConfiguration() == selected else { return }
            if index > 0 { try await Task.sleep(nanoseconds: 1_000_000_000) }
            let value = try await self.translate(selected, credentials, text, ZIMELocalLexicon.containsHan(text))
            guard self.generation == token, self.loadConfiguration() == selected else { return }
            if self.cache.count >= 512 { self.cache.removeAll() }
            self.cache[text] = (value, Date().addingTimeInterval(600))
            refresh()
          }
          guard self.generation == token else { return }
          self.task = nil
          self.pageKey = []
          refresh()
        } catch is CancellationError {
          // A new composition owns the panel; never publish into the old one.
        } catch {
          guard let self, self.generation == token else { return }
          self.cooldownUntil = Date().addingTimeInterval(30)
          self.task = nil
          self.pageKey = []
          refresh()
        }
      }
    }
    return .init(items: items, currentPage: snapshot.currentPage, pageSize: snapshot.pageSize,
      highlightedItemIndex: snapshot.highlightedItemIndex, isLastPage: snapshot.isLastPage,
      canExpand: snapshot.canExpand, isExpanded: snapshot.isExpanded)
  }

  private static func comment(_ translations: [String]) -> String {
    LinnetCandidatePresentation.reverseEnglishDetailPrefix
      + translations.joined(separator: LinnetCandidatePresentation.translationAlternativeSeparator)
  }
}
