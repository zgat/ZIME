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
    guard showTranslation else { cancel(); return snapshot }
    let currentConfiguration = loadConfiguration()
    if !configuration.hasSameService(as: currentConfiguration) || self.region != region {
      cancel()
      cache.removeAll()
      cooldownUntil = .distantPast
      self.region = region
    }
    configuration = currentConfiguration
    if !configuration.enabled { cancel() }
    var missing: [String] = []
    let items = snapshot.items.map { item -> SquirrelInputController.CandidateItem in
      let emojiSource = item.comment.hasPrefix(LinnetCandidatePresentation.emojiSourcePrefix)
        ? String(item.comment.dropFirst()) : nil
      let lookupText = emojiSource ?? item.text
      let original = LinnetCandidatePresentation.candidateComment(item.comment)
      let chinese = ZIMELocalLexicon.containsHan(lookupText)
      let annotation = chinese ? localLexicon.annotation(for: lookupText, region: region,
        includeDetails: configuration.showFullAnnotations) : nil
      // A direct Chinese dictionary definition outranks reverse English senses
      // such as surname romanizations. Neither the active script nor region can
      // block a real candidate's native/local definition or cloud fallback.
      let nativeTranslations = ZIMELocalLexicon.coreTranslations(original.translations)
      let translations = !nativeTranslations.isEmpty ? nativeTranslations
        : chinese ? [] : ZIMELocalLexicon.coreTranslations(localLexicon.translations(for: lookupText))
      let term = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
      let cached = cache[term].flatMap { $0.expires > Date() ? $0.text : nil }
      let canRequest = emojiSource == nil && configuration.enabled && item.page == snapshot.currentPage && term.count <= 64
        && !term.isEmpty && (chinese || item.comment.hasPrefix(LinnetCandidatePresentation.smartEnglishDetailPrefix))
        && !term.contains("@") && !term.contains("://")
      let comment: String
      if let annotation, !annotation.translations.isEmpty {
        comment = LinnetCandidatePresentation.bilingualComment(displayText: annotation.displayText,
          translations: annotation.translations,
          detailText: configuration.showFullAnnotations ? annotation.detailText : "")
      } else if !translations.isEmpty {
        // IPA and part-of-speech labels may remain in the English display,
        // but never enter the plain translation candidates used for commits.
        let display = original.belongsToSmartEnglish && !nativeTranslations.isEmpty
          ? ZIMELocalLexicon.coreDefinition(original.displayText)
          : translations.prefix(2).joined(separator: " / ")
        comment = LinnetCandidatePresentation.bilingualComment(displayText: display,
          translations: translations, detailText: configuration.showFullAnnotations
            ? (!nativeTranslations.isEmpty ? LinnetCandidatePresentation.fullCandidateComment(item.comment)
              : translations.joined(separator: "\n")) : "")
      } else if let cached {
        // Provider fields are translations, not CC-CEDICT definitions. Preserve
        // the entire accepted field as one commit candidate; labels are UI-only.
        let label = configuration.provider.candidateSourceLabel
        comment = LinnetCandidatePresentation.bilingualComment(displayText: "\(label):\(cached)",
          translations: [cached], detailText: "", sourceLabel: label)
      } else {
        // Unmarked comments are spelling hints, never English translations.
        if canRequest && cached == nil && cooldownUntil <= Date() {
          if !missing.contains(term) { missing.append(term) }
          comment = "译文查询中…"
        } else {
          comment = "无译文"
        }
      }
      var result = item
      result.comment = comment
      result.emphasizesPrimaryText = showTranslation
      return result
    }
    // Only the current source page is eligible for remote lookup.
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
          guard let self, self.generation == token,
            self.loadConfiguration().hasSameService(as: selected) else { return }
          let credentials = try self.loadCredentials(selected.credentialAccount)
          for (index, text) in missing.enumerated() {
            try Task.checkCancellation()
            guard self.generation == token, self.loadConfiguration().hasSameService(as: selected) else { return }
            if index > 0 { try await Task.sleep(nanoseconds: 1_000_000_000) }
            // Consent/provider may change in Settings during the rate-limit
            // wait, without another candidate update to cancel this task.
            guard self.generation == token, self.loadConfiguration().hasSameService(as: selected) else { return }
            let value = try await self.translate(selected, credentials, text, ZIMELocalLexicon.containsHan(text))
            guard self.generation == token, self.loadConfiguration().hasSameService(as: selected) else { return }
            if self.cache.count >= 512,
              let oldest = self.cache.min(by: { $0.value.expires < $1.value.expires })?.key {
              self.cache.removeValue(forKey: oldest)
            }
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
      highlightedItemIndex: snapshot.highlightedItemIndex, isLastPage: snapshot.isLastPage)
  }

}
