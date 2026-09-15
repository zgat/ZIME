import Foundation
import SwiftParser
import SwiftSyntax

// Select declarations by syntax, not whitespace, comments or function order.
// The complete Bilingual extension is compiled unchanged alongside these four
// declarations. Only unrelated IMK lifetime methods are excluded from the fixture.
private enum ExtractionError: Error { case invalidSource, missingOrDuplicateDeclaration }

private func extract(_ source: String) throws -> String {
  let tree = Parser.parse(source: source)
  guard !tree.hasError else { throw ExtractionError.invalidSource }
  let names = Set(["CandidateItem", "CandidateSnapshot", "selectCandidate", "page"])
  var found: [String: String] = [:]
  for statement in tree.statements {
    guard let block = statement.item.as(ExtensionDeclSyntax.self),
      block.extendedType.trimmedDescription == "SquirrelInputController" else { continue }
    for member in block.memberBlock.members {
      let name = member.decl.as(StructDeclSyntax.self)?.name.text
        ?? member.decl.as(FunctionDeclSyntax.self)?.name.text
      guard let name, names.contains(name) else { continue }
      guard found[name] == nil else { throw ExtractionError.missingOrDuplicateDeclaration }
      found[name] = member.decl.description
    }
  }
  guard Set(found.keys) == names else { throw ExtractionError.missingOrDuplicateDeclaration }
  return "import AppKit\nextension SquirrelInputController {\n"
    + names.sorted().compactMap { found[$0] }.joined(separator: "\n") + "\n}\n"
}

private func selfTest() throws {
  let fixture = """
  extension SquirrelInputController {
    func page(up: Bool) -> Bool { return true } // reorder is harmless
    struct CandidateSnapshot { let text = "}" }
    /* nested braces { } must not delimit a method */
    func selectCandidate(
      absoluteIndex: Int
    ) -> Bool { if absoluteIndex > 0 { return true }; return false }
    struct CandidateItem { }
  }
  """
  let extracted = try extract(fixture)
  precondition(extracted.contains("if absoluteIndex > 0 { return true }"))
  precondition(!Parser.parse(source: extracted).hasError)
  for invalid in [fixture.replacingOccurrences(of: "func page", with: "func other"),
                  fixture + "\nextension SquirrelInputController { struct CandidateItem {} }",
                  fixture.replacingOccurrences(of: "SquirrelInputController", with: "Unrelated"),
                  fixture + "\nfunc {"] {
    do {
      _ = try extract(invalid)
      preconditionFailure("invalid declaration input accepted")
    } catch ExtractionError.invalidSource {
      continue
    } catch ExtractionError.missingOrDuplicateDeclaration {
      continue
    }
  }
}

do {
  try selfTest()
  guard CommandLine.arguments.count == 2 else {
    throw ExtractionError.invalidSource
  }
  print(try extract(String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)))
} catch {
  fputs("Host declaration extraction failed: \(error)\n", stderr)
  exit(1)
}
