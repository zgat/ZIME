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
  struct SourceEntry: Equatable {
    let traditional: String
    let simplified: String
    let pinyin: String
    let priority: Int
    let senses: [String]
  }
  struct Annotation: Equatable {
    let displayText: String
    let translations: [String]
    let detailText: String
  }
  private var database: OpaquePointer?
  private var statement: OpaquePointer?
  private var sourceStatement: OpaquePointer?
  private var cache: [String: [String]] = [:]
  private var sourceCache: [String: [SourceEntry]] = [:]
  private var annotationCache: [String: Annotation] = [:]

  init(url: URL?) {
    guard let url,
      sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK
    else { return }
    sqlite3_prepare_v2(database,
      "SELECT senses FROM entries WHERE language=? AND term=?", -1, &statement, nil)
    sqlite3_prepare_v2(database,
      "SELECT traditional,simplified,pinyin,priority,senses FROM source_entries WHERE traditional=?1 OR simplified=?1 ORDER BY priority,id",
      -1, &sourceStatement, nil)
  }

  deinit {
    sqlite3_finalize(statement)
    sqlite3_finalize(sourceStatement)
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
    if Self.containsHan(term) {
      let key = region.rawValue + "/" + term
      if let result = cache[key] { return result }
      let result = Self.regionalTranslations(orderedSenses(for: term, region: region).map(\.sense),
        for: term, region: region)
      if cache.count >= 2048 { cache.removeAll(keepingCapacity: true) }
      cache[key] = result
      return result
    }
    let language = "en"
    let normalized = term.lowercased()
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
    if cache.count >= 2048 { cache.removeAll(keepingCapacity: true) }
    cache[key] = result
    return result
  }

  func sourceEntries(for text: String, region: RegionProfile = .all) -> [SourceEntry] {
    let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !term.isEmpty, term.count <= 128 else { return [] }
    let all: [SourceEntry]
    if let cached = sourceCache[term] { all = cached }
    else {
      guard let sourceStatement else { return [] }
      defer { sqlite3_reset(sourceStatement); sqlite3_clear_bindings(sourceStatement) }
      let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
      sqlite3_bind_text(sourceStatement, 1, term, -1, transient)
      var result: [SourceEntry] = []
      func column(_ index: Int32) -> String {
        sqlite3_column_text(sourceStatement, index).map { String(cString: $0) } ?? ""
      }
      while sqlite3_step(sourceStatement) == SQLITE_ROW {
        guard let senses = try? JSONDecoder().decode([String].self, from: Data(column(4).utf8)) else { continue }
        result.append(.init(traditional: column(0), simplified: column(1), pinyin: column(2),
          priority: Int(sqlite3_column_int(sourceStatement, 3)), senses: senses))
      }
      if sourceCache.count >= 2048 { sourceCache.removeAll(keepingCapacity: true) }
      sourceCache[term] = result
      all = result
    }
    switch region {
    case .all: return all
    case .mainland: return all.filter { $0.simplified == term }
    case .traditionalRegions: return all.filter { $0.traditional == term }
    }
  }

  private func orderedSenses(for term: String, region: RegionProfile) -> [(entry: SourceEntry, sense: String)] {
    // Round-robin equally ranked source entries, so a long 發 entry cannot
    // push the distinct 髮 "hair" sense beyond all visible alternatives.
    sourceEntries(for: term, region: region).enumerated().flatMap { sourceIndex, entry in
      entry.senses.enumerated().map { senseIndex, sense in
        (entry: entry, sense: sense, sourceIndex: sourceIndex, senseIndex: senseIndex)
      }
    }.sorted { lhs, rhs in
      let left = lhs.entry.priority + (lhs.sense.hasPrefix("(bound form)") ? 2 : 0)
      let right = rhs.entry.priority + (rhs.sense.hasPrefix("(bound form)") ? 2 : 0)
      if left != right { return left < right }
      if lhs.senseIndex != rhs.senseIndex { return lhs.senseIndex < rhs.senseIndex }
      return lhs.sourceIndex < rhs.sourceIndex
    }.map { (entry: $0.entry, sense: $0.sense) }
  }

  /// Keep display-only notes separate from the untouched explicit commit
  /// alternatives. Only equal glosses / explanatory copies are coalesced.
  func annotation(for text: String, region: RegionProfile) -> Annotation {
    let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let key = region.rawValue + "/" + term
    if let result = annotationCache[key] { return result }
    var displayed: [String] = []
    var translations: [String] = []
    var details: [String] = []
    var seenDetails = Set<String>()
    var noteOnlyIndices = Set<Int>()
    let senses = orderedSenses(for: term, region: region)
    let hasDefinition = senses.contains { !Self.isPronunciationNote($0.sense) }
    for (entry, sense) in senses {
      guard let full = Self.regionalTranslations([sense], for: term, region: region).first else { continue }
      let projected = Self.inlineDefinition(full, headword: term)
      let heading = entry.traditional == entry.simplified ? entry.traditional : "\(entry.traditional) / \(entry.simplified)"
      let detail = "\(heading) [\(entry.pinyin)]\n\(full)"
      if seenDetails.insert(detail).inserted { details.append(detail) }
      if hasDefinition && Self.isPronunciationNote(full) { continue }
      if let same = displayed.firstIndex(of: projected.text) {
        if noteOnlyIndices.contains(same), !projected.isExplanatoryCopy {
          translations[same] = full
          noteOnlyIndices.remove(same)
        }
        continue
      }
      let bare = Self.withoutParentheticalAnnotations(projected.text)
      // A bare "you (Note: ...)" supplements an existing qualified "you";
      // it is not another translation. Never merge two qualified senses such
      // as capital (city) / capital (finance), or distinct 發/髮 definitions.
      if projected.isExplanatoryCopy,
        displayed.contains(where: { Self.withoutParentheticalAnnotations($0) == bare }) { continue }
      if let previous = displayed.indices.first(where: {
        noteOnlyIndices.contains($0) && Self.withoutParentheticalAnnotations(displayed[$0]) == bare
      }) {
        displayed[previous] = projected.text
        translations[previous] = full
        noteOnlyIndices.remove(previous)
      } else {
        if projected.isExplanatoryCopy { noteOnlyIndices.insert(displayed.count) }
        displayed.append(projected.text)
        translations.append(full)
      }
    }
    let result = Annotation(displayText: displayed.prefix(2).joined(separator: " / "),
      translations: Array(translations.prefix(3)), detailText: details.joined(separator: "\n\n"))
    if annotationCache.count >= 2048 { annotationCache.removeAll(keepingCapacity: true) }
    annotationCache[key] = result
    return result
  }

  static func inlineDefinition(_ definition: String, headword: String) -> (text: String, isExplanatoryCopy: Bool) {
    // Retain the distinguishing female-address sense when its source headword
    // is 妳, rather than treating the entire use restriction as a footnote.
    if headword == "妳", definition == "you (Taiwan: 妳 is used to address females.)" {
      return ("you (female)", false)
    }
    var result = definition
    var movedNote = false
    for annotation in parentheticalAnnotations(in: definition).reversed() {
      let text = annotation.text.lowercased()
      if ["note:", "mainland china:", "taiwan:", "abbr. for ", "abbreviation of ",
        "also written ", "also pr.", "taiwan pr.", "e.g.", "for example", "as in "]
        .contains(where: text.hasPrefix) {
        result.removeSubrange(annotation.range)
        movedNote = true
      } else if let comparison = annotation.text.range(of: ", as opposed to ") {
        // Keep the exact qualifier, move only its explanatory comparison.
        result.replaceSubrange(annotation.range, with: "(\(annotation.text[..<comparison.lowerBound]))")
      }
    }
    result = result.replacingOccurrences(
      of: #"\[[A-Za-züÜ:]+[1-5](?:[ '\-·]*[A-Za-züÜ:]+[1-5])*\]"#,
      with: "", options: .regularExpression)
      .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    // Grammar-only / unrecognized definitions must remain readable, never
    // disappear just because all of their text happens to be parenthetical.
    guard !result.isEmpty else { return (definition, false) }
    return (result, movedNote && result == withoutParentheticalAnnotations(result))
  }

  private static func isPronunciationNote(_ text: String) -> Bool {
    ["taiwan pr.", "also pr.", "also pronounced "].contains(where: text.lowercased().hasPrefix)
  }

  private static func withoutParentheticalAnnotations(_ text: String) -> String {
    var result = text
    for annotation in parentheticalAnnotations(in: text).reversed() { result.removeSubrange(annotation.range) }
    return result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
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
