import Foundation

// Shared snapshot boundary for normal and mutation executables. No production
// implementation is copied; both compile the actual candidate translator.
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

extension ZIMECandidateTranslatorTests {
  // Expected mutation failures are ordinary test failures, not application
  // crashes. Keep diagnostics without filling macOS DiagnosticReports.
  @MainActor static func check(_ condition: @autoclosure () -> Bool,
    _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    guard condition() else {
      FileHandle.standardError.write(Data("ZIME test assertion failed: \(message()) [\(file):\(line)]\n".utf8))
      exit(1)
    }
  }

  @MainActor static func waitUntil(_ condition: () -> Bool) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(5))
    var yields = 0
    while !condition() {
      check(clock.now < deadline, "candidate translator fixture event deadline exceeded")
      if yields < 16 {
        yields += 1
        await Task.yield()
      } else {
        try await Task.sleep(nanoseconds: 1_000_000)
      }
    }
  }
}
