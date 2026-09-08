// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import SQLite3

/// Build-time projection uses the exact parser/resolver shipped by the Host.
/// No network, model, credentials or installed input-method state is accessed.
@main
struct ZIMELexiconProjectionBuilder {
  static func main() throws {
    let args = CommandLine.arguments
    guard args.count == 3 else { throw CocoaError(.fileReadInvalidFileName) }
    let lexicon = ZIMELocalLexicon(url: URL(fileURLWithPath: args[1]), usePreparedAnnotations: false)
    var db: OpaquePointer?
    guard sqlite3_open_v2(args[1], &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw CocoaError(.fileReadCorruptFile) }
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db,
      "SELECT traditional FROM source_entries UNION SELECT simplified FROM source_entries ORDER BY 1",
      -1, &statement, nil) == SQLITE_OK else { throw CocoaError(.fileReadCorruptFile) }
    defer { sqlite3_finalize(statement) }
    guard !FileManager.default.fileExists(atPath: args[2]),
      FileManager.default.createFile(atPath: args[2], contents: nil) else { throw CocoaError(.fileWriteFileExists) }
    let output = try FileHandle(forWritingTo: URL(fileURLWithPath: args[2]))
    defer { try? output.close() }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    func json(_ strings: [String]) throws -> String { String(decoding: try encoder.encode(strings), as: UTF8.self) }
    var count = 0
    var status = sqlite3_step(statement)
    while status == SQLITE_ROW {
      let term = String(cString: sqlite3_column_text(statement, 0))
      let all = lexicon.annotation(for: term, region: .all, includeDetails: false).translations
      let mainland = lexicon.annotation(for: term, region: .mainland, includeDetails: false).translations
      let traditional = lexicon.annotation(for: term, region: .traditionalRegions, includeDetails: false).translations
      // Most entries have no regional difference. Store their shared projection
      // only once, instead of duplicating long definitions three times.
      let fields = [term, try json(all), mainland == all ? "" : try json(mainland),
        traditional == all ? "" : try json(traditional)]
      try output.write(contentsOf: Data((fields.joined(separator: "\t") + "\n").utf8))
      count += 1
      status = sqlite3_step(statement)
    }
    guard status == SQLITE_DONE else { throw CocoaError(.fileReadCorruptFile) }
    print("Prepared local annotations: \(count) headwords; shared production parser; offline")
  }
}
