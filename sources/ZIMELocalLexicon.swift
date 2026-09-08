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
    var identity: String { "\(traditional)|\(simplified)[\(pinyin)]" }
  }
  struct Annotation: Equatable {
    let displayText: String
    let translations: [String]
    let detailText: String
  }
  private var database: OpaquePointer?
  private var statement: OpaquePointer?
  private var sourceStatement: OpaquePointer?
  private var annotationStatement: OpaquePointer?
  private var cache: [String: [String]] = [:]
  private var sourceCache: [String: [SourceEntry]] = [:]
  private var annotationCache: [String: Annotation] = [:]
  private var parsedSenseCache: [String: ParsedSense] = [:]

  init(url: URL?, usePreparedAnnotations: Bool = true) {
    guard let url,
      sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK
    else { return }
    sqlite3_prepare_v2(database,
      "SELECT senses FROM entries WHERE language=? AND term=?", -1, &statement, nil)
    sqlite3_prepare_v2(database,
      "SELECT traditional,simplified,pinyin,priority,senses FROM source_entries WHERE traditional=?1 OR simplified=?1 ORDER BY priority,id",
      -1, &sourceStatement, nil)
    if usePreparedAnnotations {
      sqlite3_prepare_v2(database,
        "SELECT CASE ?2 WHEN 'mainland' THEN COALESCE(mainland,all_senses) WHEN 'traditionalRegions' THEN COALESCE(traditional_regions,all_senses) ELSE all_senses END FROM annotations WHERE term=?1",
        -1, &annotationStatement, nil)
    }
  }

  deinit {
    sqlite3_finalize(statement)
    sqlite3_finalize(sourceStatement)
    sqlite3_finalize(annotationStatement)
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
        let parsed = parsedSense(sense)
        let rank: Int
        switch parsed.kind {
        case .meaning: rank = sense.hasPrefix("(bound form)") ? 1 : 0
        case .reference: rank = 2
        case .annotation: rank = 3
        }
        return (entry: entry, sense: sense, sourceIndex: sourceIndex, senseIndex: senseIndex, rank: rank)
      }
    }.sorted { lhs, rhs in
      // Keep standalone meanings ahead of bound forms (帅 -> handsome), but
      // never let usage/reference metadata outrank real bound-form meanings.
      let left = lhs.entry.priority
      let right = rhs.entry.priority
      if left != right { return left < right }
      if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
      if lhs.senseIndex != rhs.senseIndex { return lhs.senseIndex < rhs.senseIndex }
      return lhs.sourceIndex < rhs.sourceIndex
    }.map { (entry: $0.entry, sense: $0.sense) }
  }

  /// Look up the candidate's actual spelling, irrespective of the active input
  /// mode. Region is a sense preference, never permission to translate a glyph.
  /// Display and explicit commits share core glosses; full notes stay in help.
  func annotation(for text: String, region: RegionProfile, includeDetails: Bool = true) -> Annotation {
    let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !term.isEmpty, term.count <= 128 else { return .init(displayText: "", translations: [], detailText: "") }
    let key = region.rawValue + "/" + String(includeDetails) + "/" + term
    if let result = annotationCache[key] { return result }
    let prepared = preparedTranslations(for: term, region: region)
    let resolved = prepared != nil && !includeDetails ? [] : resolve(term: term, region: region, visited: [], depth: 0)
    let translations = prepared ?? Self.unique(resolved.map(\.core).filter { !$0.isEmpty })
    let result = Annotation(displayText: translations.prefix(2).joined(separator: " / "),
      translations: Array(translations.prefix(3)),
      detailText: includeDetails ? Self.unique(resolved.map(\.detail)).joined(separator: "\n\n") : "")
    if annotationCache.count >= 2048 { annotationCache.removeAll(keepingCapacity: true) }
    annotationCache[key] = result
    return result
  }

  private func preparedTranslations(for term: String, region: RegionProfile) -> [String]? {
    guard let annotationStatement else { return nil }
    defer { sqlite3_reset(annotationStatement); sqlite3_clear_bindings(annotationStatement) }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    sqlite3_bind_text(annotationStatement, 1, term, -1, transient)
    sqlite3_bind_text(annotationStatement, 2, region.rawValue, -1, transient)
    guard sqlite3_step(annotationStatement) == SQLITE_ROW,
      let value = sqlite3_column_text(annotationStatement, 0) else { return nil }
    return try? JSONDecoder().decode([String].self, from: Data(String(cString: value).utf8))
  }

  private struct ResolvedSense { let core: String; let detail: String }

  private func resolve(term: String, region: RegionProfile, visited: Set<String>, depth: Int,
    exactReference: Reference? = nil
  ) -> [ResolvedSense] {
    guard depth < 8 else { return [] }
    let all = orderedSenses(for: term, region: .all).filter { entry, _ in
      guard let reference = exactReference else { return true }
      return entry.traditional == reference.traditional && entry.simplified == reference.simplified
        && (reference.pinyin == nil || entry.pinyin == reference.pinyin)
    }
    func project(_ profile: RegionProfile) -> [ResolvedSense] {
      var output: [ResolvedSense] = []
      let senses = all.compactMap { entry, raw -> (SourceEntry, String, ParsedSense)? in
        guard !visited.contains(entry.identity),
          let regional = Self.regionalTranslations([raw], for: term, region: profile).first else { return nil }
        return (entry, raw, parsedSense(regional))
      }
      let hasDirectMeaning = senses.contains { !$0.2.core.isEmpty }
      for (entry, raw, parsed) in senses {
        let heading = entry.traditional == entry.simplified ? entry.traditional : "\(entry.traditional) / \(entry.simplified)"
        let detail = "\(heading) [\(entry.pinyin)]\n\(raw)"
        output.append(.init(core: parsed.core, detail: detail))
        // References fill missing meanings, not extra readings of a headword
        // that already has a direct gloss (妳 ni3 must not acquire 奶 nai3).
        // Mixed abbreviation lines already contain their own English meaning.
        if !hasDirectMeaning, parsed.core.isEmpty, let reference = parsed.reference, reference.inheritsMeaning {
          let inherited = resolve(term: reference.traditional, region: profile,
            visited: visited.union([entry.identity]), depth: depth + 1, exactReference: reference)
          output.append(contentsOf: inherited.prefix(128))
        }
      }
      return output
    }
    let preferred = project(region)
    return region == .all || preferred.contains(where: { !$0.core.isEmpty }) ? preferred : project(.all)
  }

  private static func unique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
  }

  struct Reference: Equatable {
    let relation: String
    let traditional: String
    let simplified: String
    let pinyin: String?
    var inheritsMeaning: Bool {
      ["variant of", "old variant of", "archaic variant of", "ancient variant of", "see", "same as",
        "unofficial variant of", "classical variant of", "japanese variant of", "taiwan variant of",
        "erhua variant of", "erhua form of", "contracted variant of", "contracted form of",
        "also written", "abbr. for", "abbr. of", "short for"].contains(relation)
    }
  }
  struct ParsedSense {
    enum Kind: String { case meaning, reference, annotation }
    let kind: Kind
    let core: String
    let reference: Reference?
  }

  private func parsedSense(_ raw: String) -> ParsedSense {
    if let parsed = parsedSenseCache[raw] { return parsed }
    let parsed = Self.parseSense(raw)
    if parsedSenseCache.count >= 4096 { parsedSenseCache.removeAll(keepingCapacity: true) }
    parsedSenseCache[raw] = parsed
    return parsed
  }

  private static let referenceTarget = try! NSRegularExpression(pattern: #"^([^\s\[\],;]+)(?:\[([^\]]+)\])?(.*)$"#)
  private static let numberedPinyin = try! NSRegularExpression(pattern: #"\[[A-Za-züÜ:]+[1-5](?:[ '\-·]*[A-Za-züÜ:]+[1-5])*\]"#)
  private static let pairedHeadword = try! NSRegularExpression(pattern: #"([\p{Han}A-Za-z0-9]+)\|([\p{Han}A-Za-z0-9]+)"#)

  /// Recognize a relation only when it has an actual dictionary headword
  /// target. Ordinary English such as "see you tomorrow" remains a meaning.
  private static func reference(in value: String) -> (Reference, String)? {
    let relations = ["contracted variant of", "contracted form of", "erhua variant of", "erhua form of",
      "unofficial variant of", "classical variant of", "japanese variant of", "taiwan variant of",
      "old variant of", "archaic variant of", "ancient variant of", "also known as", "also written",
      "variant of", "abbr. for", "abbr. of", "abbr. to", "short for", "see also", "same as",
      "also called", "used in", "see", "cf.", "cf"]
    let lower = value.lowercased()
    guard let relation = relations.first(where: { lower.hasPrefix($0 + " ") }) else { return nil }
    let tail = String(value.dropFirst(relation.count + 1))
    guard let match = referenceTarget.firstMatch(in: tail, range: NSRange(tail.startIndex..., in: tail)),
      let targetRange = Range(match.range(at: 1), in: tail) else { return nil }
    let target = String(tail[targetRange])
    let reading = Range(match.range(at: 2), in: tail).map { String(tail[$0]) }
    // Non-Han source heads (e.g. 3C or a Bopomofo character) require a reading.
    guard containsHan(target) || (reading != nil && target.contains(where: { !$0.isASCII || $0.isNumber || $0.isUppercase }))
    else { return nil }
    let forms = target.split(separator: "|", omittingEmptySubsequences: false)
    guard (1...2).contains(forms.count), forms.allSatisfy({ !$0.isEmpty }) else { return nil }
    let suffix = Range(match.range(at: 3), in: tail).map { String(tail[$0]) } ?? ""
    return (.init(relation: relation, traditional: String(forms[0]), simplified: String(forms.last!), pinyin: reading), suffix)
  }

  static func parseSense(_ definition: String) -> ParsedSense {
    let body = projectParentheses(definition).trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = body.lowercased()
    if body.isEmpty || (lower.hasPrefix("cl:") && containsHan(body)) ||
      (["taiwan pr.", "also pr.", "also pronounced "].contains(where: lower.hasPrefix) && body.contains("[")) {
      return .init(kind: .annotation, core: "", reference: nil)
    }
    if let (reference, suffix) = reference(in: body) {
      // Legacy abbreviation records may place the real English definition
      // after the reference, e.g. "abbr. for 世博..., World Expo".
      let mixed = reference.inheritsMeaning
        && suffix.trimmingCharacters(in: .whitespaces).hasPrefix(",")
      let core = mixed ? cleanReferenceMarkup(String(suffix.drop(while: { $0.isWhitespace || $0 == "," }))) : ""
      return .init(kind: core.isEmpty ? .reference : .meaning, core: core, reference: reference)
    }
    // Some legacy rows put the abbreviation note after an English definition.
    // Require a real referenced headword before separating the trailing note.
    for marker in [", abbr. for ", ", abbr. of ", ", abbr. to "] {
      if let boundary = body.range(of: marker, options: .caseInsensitive),
        let (reference, _) = reference(in: String(body[body.index(boundary.lowerBound, offsetBy: 2)...])) {
        return .init(kind: .meaning, core: cleanReferenceMarkup(String(body[..<boundary.lowerBound])), reference: reference)
      }
    }
    return .init(kind: .meaning, core: cleanReferenceMarkup(body), reference: nil)
  }

  /// Local dictionary projection only. Online translation fields bypass this.
  static func coreDefinition(_ definition: String) -> String {
    parseSense(definition).core
  }

  private static func projectParentheses(_ definition: String) -> String {
    var result = definition
    for annotation in parentheticalAnnotations(in: definition).reversed() {
      // Parentheses inside a spelling/formula are not usage notes: colo(u)r,
      // teacher(s), B(12), (CH3)2CO. Preserve those literal tokens.
      let before = annotation.range.lowerBound > definition.startIndex
        ? definition[definition.index(before: annotation.range.lowerBound)] : nil
      let after = annotation.range.upperBound < definition.endIndex
        ? definition[annotation.range.upperBound] : nil
      let token = !annotation.text.isEmpty && annotation.text.allSatisfy { $0.isLetter || $0.isNumber }
      if token && (after?.isNumber == true ||
        (before?.isLetter == true && (after?.isLetter == true || annotation.text == "s" || annotation.text.allSatisfy(\.isNumber)))) {
        continue
      }
      let whole = definition.trimmingCharacters(in: .whitespacesAndNewlines) == String(definition[annotation.range])
      let note = annotation.text.trimmingCharacters(in: .whitespacesAndNewlines)
      if isExplanatoryNote(note) || (!whole && (isUsageLabel(note) || reference(in: note) != nil)) {
        result.removeSubrange(annotation.range)
      } else if whole {
        // A whole grammatical/functional definition is not a disposable note.
        let core = note.components(separatedBy: ", literary equivalent of ").first ?? note
        result.replaceSubrange(annotation.range, with: core)
      }
      // Unknown qualifiers, negation, optional word parts and formulas remain
      // intact. No "remove all parentheses" fallback is permitted.
    }
    return result
  }

  private static func isExplanatoryNote(_ value: String) -> Bool {
    let lower = value.lowercased()
    return ["note:", "example:", "examples:", "e.g.", "esp.", "abbr. for ", "abbr. of ", "abbr. to ",
      "taiwan pr.", "also pr.", "loanword from ", "etymologically", "mainland china:",
      "taiwan:", "usage note", "注释", "示例"].contains(where: lower.hasPrefix)
  }

  private static func isUsageLabel(_ value: String) -> Bool {
    let lower = value.lowercased()
    let labels: Set<String> = ["informal", "formal", "courteous", "bound form", "coll.", "jocular", "slang",
      "internet slang", "idiom", "literary", "archaic", "old", "dialect", "loanword", "fig.", "lit.",
      "noun", "verb", "adjective", "adverb", "computing", "math.", "botany", "chemistry", "medicine",
      "physics", "prc", "tw", "hk", "hong kong", "mainland china", "singapore", "malaysia", "macau", "macao",
      "名词", "动词"]
    let parts = lower.components(separatedBy: CharacterSet(charactersIn: ",，"))
      .map { $0.trimmingCharacters(in: .whitespaces) }
    return labels.contains(lower) || parts.allSatisfy {
      labels.contains($0.trimmingCharacters(in: .whitespaces))
    } || (parts.count > 1 && labels.contains(parts[0]) && parts.dropFirst().allSatisfy(isExplanatoryNote))
      || ["informal, ", "of ", "used in relation to "].contains(where: lower.hasPrefix)
  }

  private static func cleanReferenceMarkup(_ value: String) -> String {
    var result = numberedPinyin.stringByReplacingMatches(in: value,
      range: NSRange(value.startIndex..., in: value), withTemplate: "")
    for match in pairedHeadword.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
      guard let whole = Range(match.range, in: result), let simple = Range(match.range(at: 2), in: result),
        containsHan(String(result[whole])) else { continue }
      result.replaceSubrange(whole, with: String(result[simple]))
    }
    return result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
      .trimmingCharacters(in: CharacterSet(charactersIn: ";；,， "))
  }

  static func coreTranslations(_ definitions: [String]) -> [String] {
    var seen = Set<String>()
    return definitions.map(coreDefinition).filter { !$0.isEmpty && seen.insert($0).inserted }
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
    var closing: [Character] = []
    for index in text.indices {
      if text[index] == "(" || text[index] == "（" {
        if closing.isEmpty { start = index }
        closing.append(text[index] == "(" ? ")" : "）")
      } else if text[index] == closing.last {
        closing.removeLast()
        if closing.isEmpty, let start {
          result.append((String(text[text.index(after: start)..<index]), start..<text.index(after: index)))
        }
      }
    }
    return result
  }
}
