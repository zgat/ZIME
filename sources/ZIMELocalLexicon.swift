// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import SQLite3

/// Read-only indexed dictionary, with bounded hot/negative lookup caching.
/// Accessed on the input controller's main thread; never scans the dictionary.
final class ZIMELocalLexicon {
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

  func translations(for text: String) -> [String] {
    let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !term.isEmpty, term.count <= 128 else { return [] }
    let language = Self.containsHan(term) ? "zh" : "en"
    let normalized = language == "en" ? term.lowercased() : term
    let key = language + "/" + normalized
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
}
