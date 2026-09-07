// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import SQLite3

/// Read-only indexed dictionary, with bounded hot/negative lookup caching.
/// Accessed on the input controller's main thread; never scans the dictionary.
final class ZIMELocalLexicon {
  /// A product preference, not a claim that script determines regional usage.
  /// Singapore/Malaysia are included in the user's Traditional-region group.
  enum RegionProfile: String {
    case all, mainland, traditionalRegions
  }
  private var database: OpaquePointer?
  private var statement: OpaquePointer?
  private var cache: [String: [String]] = [:]

  init(url: URL?) {
    guard let url,
      sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK
    else { return }
    sqlite3_prepare_v2(database,
      "SELECT senses FROM entries WHERE language=? AND term=?", -1, &statement, nil)
  }

  deinit {
    sqlite3_finalize(statement)
    sqlite3_close(database)
  }

  static func containsHan(_ text: String) -> Bool {
    text.unicodeScalars.contains {
      (0x3400...0x9FFF).contains($0.value) || (0xF900...0xFAFF).contains($0.value)
        || (0x20000...0x323AF).contains($0.value)
    }
  }

  func translations(for text: String, region: RegionProfile = .all) -> [String] {
    let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !term.isEmpty, term.count <= 128 else { return [] }
    let language = Self.containsHan(term) ? "zh" : "en"
    let normalized = language == "en" ? term.lowercased() : term
    let key = region.rawValue + "/" + language + "/" + normalized
    if let result = cache[key] { return result }
    guard let statement else { return [] }
    defer { sqlite3_reset(statement); sqlite3_clear_bindings(statement) }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    sqlite3_bind_text(statement, 1, language, -1, transient)
    sqlite3_bind_text(statement, 2, normalized, -1, transient)
    var result: [String] = []
    if sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) {
      result = (try? JSONDecoder().decode([String].self, from: Data(String(cString: value).utf8))) ?? []
    }
    if language == "zh" { result = Self.regionalTranslations(result, for: term, region: region) }
    if cache.count >= 2048 { cache.removeAll(keepingCapacity: true) }
    cache[key] = result
    return result
  }

  /// Filter explicit usage labels only. Geographic mentions, examples,
  /// grammatical qualifiers and unclassified prose are never guessed away.
  static func regionalTranslations(_ senses: [String], for term: String,
    region: RegionProfile
  ) -> [String] {
    guard region != .all else { return senses }
    var seen = Set<String>()
    return senses.compactMap { sense -> String? in
      // Definition strings: CC BY-SA 4.0, see ZIME-Lexicon-NOTICE.txt.
      // Reviewed split of this exact mixed-region CC-CEDICT note. Matching the
      // complete source prevents future dictionary edits being silently lost.
      let pronounNote = "you (Note: In Taiwan, 妳 is used to address females, but in mainland China, it is not commonly used. Instead, 你 is used to address both males and females.)"
      if (term == "你" || term == "妳"), sense == pronounNote {
        return region == .mainland
          ? "you (Mainland China: 妳 is not commonly used; 你 is used to address both males and females.)"
          : "you (Taiwan: 妳 is used to address females.)"
      }
      let annotations = parentheticalAnnotations(in: sense)
      let regions = annotations.reduce(into: Set<RegionProfile>()) { result, annotation in
        result.formUnion(regionsForLabel(annotation.text))
      }
      guard regions.isEmpty || regions.contains(region) else { return nil }
      // Cross-region equivalence/pronunciation notes are not the headword's
      // usage label. Remove only a clearly labeled note for the other group.
      var projected = sense
      for annotation in annotations.reversed() {
        let note = annotation.text.lowercased()
        for (prefix, noteRegion) in [
          ("taiwan equivalent:", RegionProfile.traditionalRegions),
          ("tw equivalent:", .traditionalRegions),
          ("prc equivalent:", .mainland),
          ("taiwan pr.", .traditionalRegions)
        ] where note.hasPrefix(prefix) && noteRegion != region {
          projected.removeSubrange(annotation.range)
        }
      }
      // A standalone pronunciation sense has the same explicit provenance.
      if region == .mainland, sense.hasPrefix("Taiwan pr.") { return nil }
      return projected.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }.filter { !$0.isEmpty && seen.insert($0).inserted }
  }

  private static func regionsForLabel(_ label: String) -> Set<RegionProfile> {
    let labels = label.lowercased().components(separatedBy: ",")
      .map { $0.trimmingCharacters(in: .whitespaces) }
    let mainland = Set(["prc", "mainland china"])
    let traditional = Set(["tw", "hk", "hong kong", "macau", "macao", "singapore", "malaysia"])
    // Recognize a whole label, never a substring like "PRC proposal ...".
    guard labels.allSatisfy({ mainland.contains($0) || traditional.contains($0) }) else { return [] }
    var result = Set<RegionProfile>()
    if labels.contains(where: mainland.contains) { result.insert(.mainland) }
    if labels.contains(where: traditional.contains) { result.insert(.traditionalRegions) }
    return result
  }

  private static func parentheticalAnnotations(in text: String)
    -> [(text: String, range: Range<String.Index>)] {
    var result: [(String, Range<String.Index>)] = []
    var start: String.Index?
    var depth = 0
    for index in text.indices {
      if text[index] == "(" {
        if depth == 0 { start = index }
        depth += 1
      } else if text[index] == ")", depth > 0 {
        depth -= 1
        if depth == 0, let start {
          result.append((String(text[text.index(after: start)..<index]), start..<text.index(after: index)))
        }
      }
    }
    return result
  }
}
