import AppKit
import Foundation

extension NSRange {
  static let empty = NSRange(location: NSNotFound, length: 0)
}

extension NSPoint {
  static func += (lhs: inout Self, rhs: Self) {
    lhs.x += rhs.x
    lhs.y += rhs.y
  }
  static func -= (lhs: inout Self, rhs: Self) {
    lhs.x -= rhs.x
    lhs.y -= rhs.y
  }
  static func - (lhs: Self, rhs: Self) -> Self {
    Self(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
  }
  static func * (lhs: Self, rhs: CGFloat) -> Self {
    Self(x: lhs.x * rhs, y: lhs.y * rhs)
  }
  static func / (lhs: Self, rhs: CGFloat) -> Self {
    Self(x: lhs.x / rhs, y: lhs.y / rhs)
  }
  var length: CGFloat { sqrt(x * x + y * y) }
}

// This harness compiles the real candidate view without linking librime. The
// theme and candidate data are narrow boundary fixtures; layout, tracking,
// mouse hit testing, and accessibility geometry remain production code.
final class SquirrelTheme {
  static let offsetHeight: CGFloat = 5
  static let showStatusDuration: Double = 1.2
  typealias SelectionStyle = LinnetCandidatePresentation.CandidateSelectionStyle
  enum StatusMessageType { case long, short, mix }

  var available = true
  var backgroundColor = NSColor.windowBackgroundColor
  var attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 16),
    .foregroundColor: NSColor.labelColor,
  ]
  var borderColor: NSColor? = .separatorColor
  var candidateBackColor: NSColor?
  var candidateFormat = "[label] [candidate]"
  var commentAttrs: [NSAttributedString.Key: Any] = [:]
  var commentHighlightedAttrs: [NSAttributedString.Key: Any] = [:]
  var detailAttrs: [NSAttributedString.Key: Any] = [:]
  var highlightedBackColor: NSColor? = .selectedContentBackgroundColor
  var highlightedPreeditColor: NSColor?
  var preeditBackgroundColor: NSColor?
  var borderLineWidth: CGFloat = 0.5
  var borderWidth: CGFloat = 0.5
  var cornerRadius: CGFloat = 10
  var edgeInset = LinnetCandidatePresentation.candidateWindowInset
  var firstParagraphStyle: NSParagraphStyle = NSMutableParagraphStyle()
  var font = NSFont.systemFont(ofSize: 16)
  var highlightedAttrs: [NSAttributedString.Key: Any] = [:]
  var hilitedCornerRadius: CGFloat = 6
  var linear = true
  var inlineCandidate = false
  var inlinePreedit = false
  var labelAttrs: [NSAttributedString.Key: Any] = [:]
  var labelHighlightedAttrs: [NSAttributedString.Key: Any] = [:]
  var linespace = LinnetCandidatePresentation.candidateRowSpacing
  var mutualExclusive = false
  var native = false
  var paragraphStyle: NSParagraphStyle = NSMutableParagraphStyle()
  var preeditAttrs: [NSAttributedString.Key: Any] = [:]
  var preeditHighlightedAttrs: [NSAttributedString.Key: Any] = [:]
  var preeditParagraphStyle: NSParagraphStyle = NSMutableParagraphStyle()
  var preeditLinespace = LinnetCandidatePresentation.preeditSpacing
  var selectionStyle = SelectionStyle.tile
  var shadowSize: CGFloat = 0
  var surroundingExtraExpansion: CGFloat = 0
  var statusAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: LinnetPanelGeometry.statusFontPoint, weight: .medium),
    .foregroundColor: NSColor.labelColor,
  ]
  var statusMessageType = StatusMessageType.mix
  var statusParagraphStyle: NSParagraphStyle = NSMutableParagraphStyle()
  var alpha: CGFloat = 1
  var memorizeSize = false
  var showPaging = false
  var translucency = false
  var vertical = false

  var materialAppearance = LinnetClientAppearance.MaterialMode.system
  var pagingOffset: CGFloat { 15 }

  func load(config: SquirrelConfig, dark: Bool) {}
}

final class SquirrelConfig {}

final class SquirrelInputController {
  struct CandidateItem {
    let text: String
    let comment: String
    let page: Int
    let indexOnPage: Int
    let absoluteIndex: Int
    let selectionLabel: String?
    var emphasizesPrimaryText = false
  }

  struct CandidateSnapshot {
    let items: [CandidateItem]
    let pageSize: Int
    let currentPage: Int
    let isLastPage: Bool
  }

  private(set) var selectedCandidateIndices: [Int] = []
  private(set) var pageDirections: [Bool] = []
  var activeClient: Any?

  func page(up: Bool) -> Bool {
    pageDirections.append(up)
    return true
  }
  func selectCandidate(absoluteIndex: Int) -> Bool {
    selectedCandidateIndices.append(absoluteIndex)
    return true
  }

  func resetSelectedCandidates() {
    selectedCandidateIndices.removeAll()
  }

  func resetPageDirections() {
    pageDirections.removeAll()
  }
}

@main
struct LinnetCandidateWindowInteractionTests {
  private static var failures: [String] = []

  static func main() {
    _ = NSApplication.shared
    testColdCandidatePresentationLatency()
    testTrackingArea()
    testExactCandidatePathHitTesting()
    testSyntheticHoverLifecycle()
    testCandidateControlPointerFeedback()
    testCandidatePressPublicationIdentity()
    testAccessibilitySelectionKeepsElementIdentity()
    testStaleAccessibilityDoesNotRetainController()
    testAccessibilityRejectsInvalidGeometry()
    testSameControllerReactivationInvalidatesOldPublication()
    testInputControllerOwnerSwapInvalidatesCandidateInteraction()
    testPreciseWheelPagingSemantics()
    testCandidateScrollPublicationIdentity()
    testPreeditPressDoesNotInferEngineCaret()
    testInputModeStatusNotice()
    testScreenLocalPanelPlacement()
    testDefaultNineCandidateNaturalSize()
    testEveryCandidateShowsTranslation()
    testSquareAndRoundedPaths()
    testStructuredLocalGlosses()
    testOptionalFullAnnotations()
    testOnlineSourceAnnotations()
    testRegionalDefinitionsWrapWithoutSummarization()
    testChineseCommentsDoNotCreateEnglishPlaceholder()
    testThemeLayoutMatrix()
    testVerticalPanelDoesNotMemorizeWhenDisabled()
    for point in [CGFloat(12), 16, 32] {
      for linear in [true, false] {
        for style in [
          SquirrelTheme.SelectionStyle.tile,
          .underline,
          .bar,
        ] {
          testCandidateCellGeometry(fontPoint: point, linear: linear, style: style)
        }
      }
    }
    if let option = CommandLine.arguments.firstIndex(of: "--readme-theme-gallery"),
      CommandLine.arguments.indices.contains(option + 2)
    {
      makeReadmeThemeGallery(
        yamlPath: CommandLine.arguments[option + 1],
        outputPath: CommandLine.arguments[option + 2])
    }
    if let option = CommandLine.arguments.firstIndex(of: "--readme-product-gallery"),
      CommandLine.arguments.indices.contains(option + 3)
    {
      makeReadmeProductGallery(
        yamlPath: CommandLine.arguments[option + 1],
        inputModesOutputPath: CommandLine.arguments[option + 2],
        bilingualOutputPath: CommandLine.arguments[option + 3])
    }
    if let option = CommandLine.arguments.firstIndex(of: "--readme-regional-gallery"),
      CommandLine.arguments.indices.contains(option + 2) {
      makeReadmeRegionalGallery(yamlPath: CommandLine.arguments[option + 1],
        outputPath: CommandLine.arguments[option + 2])
    }
    if let option = CommandLine.arguments.firstIndex(of: "--readme-appearance-gallery"),
      CommandLine.arguments.indices.contains(option + 2) {
      makeReadmeAppearanceGallery(yamlPath: CommandLine.arguments[option + 1],
        outputPath: CommandLine.arguments[option + 2])
    }
    for option in CommandLine.arguments.indices
    where CommandLine.arguments[option] == "--verify-readme-render" {
      guard CommandLine.arguments.indices.contains(option + 3) else {
        failures.append("--verify-readme-render requires committed, generated, and label arguments")
        continue
      }
      verifyReadmeRender(
        committedPath: CommandLine.arguments[option + 1],
        generatedPath: CommandLine.arguments[option + 2],
        label: CommandLine.arguments[option + 3])
    }
    guard failures.isEmpty else {
      for failure in failures {
        FileHandle.standardError.write(Data("FAIL: \(failure)\n".utf8))
      }
      exit(EXIT_FAILURE)
    }
    print("LinnetCandidateWindowInteractionTests: PASS")
  }

  private static func testSquareAndRoundedPaths() {
    let view = SquirrelView(frame: NSRect(x: 0, y: 0, width: 220, height: 90))
    let rect = NSRect(x: 3, y: 3, width: 200, height: 70)
    for radius in [CGFloat(0), 5, 8] {
      guard let path = view.drawSmoothLines(view.rectVertex(of: rect), straightCorner: [],
        alpha: 0.3 * radius, beta: 1.4 * radius) else {
        failures.append("appearance path is missing")
        continue
      }
      var curves = 0
      path.applyWithBlock { element in
        if element.pointee.type == .addCurveToPoint { curves += 1 }
      }
      require((curves == 0) == (radius == 0), "square corners must not contain rounded path segments")
      require(path.contains(NSPoint(x: rect.midX, y: rect.midY)), "appearance path contains invalid coordinates")
      require(path.contains(NSPoint(x: rect.minX + 0.01, y: rect.minY + 0.01)) == (radius == 0),
              "window and full-row path did not adopt the chosen corner geometry")
    }
  }

  private static func testEveryCandidateShowsTranslation() {
    guard let yaml = try? String(contentsOfFile: "data/squirrel.yaml", encoding: .utf8),
      let sample = parseThemeSamples(yaml)["linnet_paper_light"] else {
      failures.append("bilingual row fixture could not read theme")
      return
    }
    let words = ["帅", "hello", "下班", "work", "你好", "computer", "学习", "book", "朋友"]
    let glosses = ["handsome; graceful", "你好", "finish work", "工作", "hello; hi", "电脑", "study", "书", "friend"]
    for point in [CGFloat(12), 16, 32] {
      for count in 3...9 {
        for explicitComment in [false, true] {
          let panel = SquirrelPanel(position: NSRect(x: 260, y: 420, width: 2, height: 20))
          let controller = SquirrelInputController()
          panel.bind(controller: controller)
          let view = panel.view
          configureThemeLayout(view.lightTheme, sample: sample, point: point, linear: false)
          if explicitComment { view.lightTheme.candidateFormat += "  [comment]" }
          let snapshot = SquirrelInputController.CandidateSnapshot(
            items: (0..<count).map { index in
              .init(text: words[index], comment: LinnetCandidatePresentation.reverseEnglishDetailPrefix + glosses[index],
                page: 0, indexOnPage: index, absoluteIndex: index,
                selectionLabel: String(index + 1), emphasizesPrimaryText: true)
            }, pageSize: count, currentPage: 0, isLastPage: true)
          var sizes: [NSSize] = []
          for selected in [0, count - 1] {
            require(panel.update(preedit: "", selRange: .empty, caretPos: 0,
              candidates: snapshot, highlighted: selected, update: true, controller: controller),
              "bilingual rows were not published")
            render(view)
            guard let text = view.textView.textContentStorage?.attributedString,
              view.candidateRanges.count == count else {
              failures.append("bilingual candidate ranges were lost")
              panel.hide()
              continue
            }
            for index in 0..<count {
              let row = text.attributedSubstring(from: view.candidateRanges[index]).string
              require(row.contains(words[index]) && row.contains(glosses[index]),
                "\(point)pt row \(index) lost its own translation: \(row)")
              require(row.components(separatedBy: glosses[index]).count == 2,
                "explicit comment format duplicated translation")
              let attributed = text.attributedSubstring(from: view.candidateRanges[index])
              let wordRange = (attributed.string as NSString).range(of: words[index])
              let font = attributed.attribute(.font, at: wordRange.location, effectiveRange: nil) as? NSFont
              require(font == view.lightTheme.font,
                "translation annotation or selection forced a different font weight")
            }
            require(view.detailTextView.isHidden && view.detailDividerView.isHidden,
              "selected-only translation surface returned")
            let frames = view.candidateAccessibilityGeometry().candidateFrames
            require(frames.count == count && frames.allSatisfy {
              !$0.isEmpty && view.bounds.insetBy(dx: -1, dy: -1).contains($0)
            }, "bilingual row hit geometry was clipped")
            sizes.append(panel.frame.size)
          }
          require(sizes.count == 2 && sizes[0] == sizes[1], "highlight changed bilingual list size")
          let children = view.accessibilityChildren() ?? []
          if let last = children.prefix(count).last as? LinnetCandidateAccessibilityElement {
            require(last.accessibilityPerformPress(), "translated row was not selectable")
            require(controller.selectedCandidateIndices == [count - 1],
              "translated row selection changed its source candidate index")
          } else { failures.append("translated row has no accessible selection action") }
          panel.hide()
        }
      }
    }
  }

  private static func testRegionalDefinitionsWrapWithoutSummarization() {
    guard let yaml = try? String(contentsOfFile: "data/squirrel.yaml", encoding: .utf8) else { return }
    let fullNote = "you (Mainland China: 妳 is not commonly used; 你 is used to address both males and females.)"
    let firstSense = "you (informal, as opposed to courteous 您[nin2])"
    let comment = "\u{001E}\(firstSense)\u{001F}\(fullNote)\u{001F}third sense for full help"
    for scheme in ["linnet_macos_light", "linnet_macos_dark"] {
      guard let sample = parseThemeSamples(yaml)[scheme] else {
        failures.append("missing macOS theme")
        return
      }
      for point in [CGFloat(12), 16, 32] {
        let panel = SquirrelPanel(position: NSRect(x: 260, y: 420, width: 2, height: 20))
        let controller = SquirrelInputController()
        panel.bind(controller: controller)
        let view = panel.view
        configureThemeLayout(view.lightTheme, sample: sample, point: point, linear: false)
        let snapshot = SquirrelInputController.CandidateSnapshot(items: (0..<9).map { index in
          .init(text: index == 0 ? "你" : "候选\(index)", comment: index == 0 ? comment : "\u{001E}candidate",
            page: 0, indexOnPage: index, absoluteIndex: index, selectionLabel: String(index + 1))
        }, pageSize: 9, currentPage: 0, isLastPage: true)
        require(panel.update(preedit: "ni", selRange: .empty, caretPos: 2,
          candidates: snapshot, highlighted: 0, update: true, controller: controller), "long definition not published")
        render(view)
        let rendered = view.textView.textContentStorage?.attributedString?.string ?? ""
        require(rendered.contains(firstSense) && rendered.contains(fullNote), "full usage note was shortened")
        require(!rendered.contains("…"), "definition text was truncated")
        let frames = view.candidateAccessibilityGeometry().candidateFrames
        require(frames.count == 9 && frames.allSatisfy { view.bounds.insetBy(dx: -1, dy: -1).contains($0) }, "wrapped row hit frames were clipped")
        require(frames.first!.height > frames.last!.height, "long definition did not wrap")
        require(view.contentRect.width <= min(480, max(300, point * 24)) + 1, "long note stretched the candidate window")
        require(view.candidateToolTipTexts.first?.description.contains("third sense for full help") == true, "full native tooltip lost an alternative")
        if let first = view.accessibilityChildren()?.first as? LinnetCandidateAccessibilityElement {
          require(first.accessibilityHelp()?.contains(fullNote) == true, "VoiceOver help lost full definition")
          require(first.accessibilityPerformPress() && controller.selectedCandidateIndices == [0], "wrapped row selected the wrong candidate")
        } else { failures.append("wrapped candidate has no AX element") }
        panel.hide()
        require(view.candidateToolTipTexts.isEmpty, "hidden panel retained old tooltips")
      }
    }
  }

  private static func testOptionalFullAnnotations() {
    guard let yaml = try? String(contentsOfFile: "data/squirrel.yaml", encoding: .utf8),
      let sample = parseThemeSamples(yaml)["linnet_macos_light"] else {
      failures.append("missing theme for annotation toggle test")
      return
    }
    let lexicon = ZIMELocalLexicon(url: URL(fileURLWithPath: "resources/zime-cedict.sqlite3"))
    let annotation = lexicon.annotation(for: "你", region: .mainland)
    let panel = SquirrelPanel(position: NSRect(x: 260, y: 420, width: 2, height: 20))
    let controller = SquirrelInputController()
    panel.bind(controller: controller)
    configureThemeLayout(panel.view.lightTheme, sample: sample, point: 16, linear: false)
    for fullNotes in [false, true, false] {
      let item = SquirrelInputController.CandidateItem(text: "你",
        comment: LinnetCandidatePresentation.bilingualComment(displayText: annotation.displayText,
          translations: annotation.translations, detailText: fullNotes ? annotation.detailText : ""),
        page: 0, indexOnPage: 0, absoluteIndex: 0, selectionLabel: "1")
      require(panel.update(preedit: "ni", selRange: .empty, caretPos: 2,
        candidates: .init(items: [item], pageSize: 5, currentPage: 0, isLastPage: true),
        highlighted: 0, update: true, controller: controller), "annotation toggle lost the candidate panel")
      render(panel.view)
      require(panel.view.candidateToolTipTexts.first?.description == (fullNotes ? annotation.detailText : ""),
        "disabled full annotations left a stale native tooltip")
      if let element = panel.view.accessibilityChildren()?.first as? LinnetCandidateAccessibilityElement {
        require((element.accessibilityHelp()?.contains("您[nin2]") == true) == fullNotes,
          "optional full annotations leaked into accessibility help")
      } else { failures.append("annotation toggle lost candidate accessibility") }
      require(panel.view.textView.textContentStorage?.attributedString?.string.contains("informal") == false,
        "hover toggle exposed full notes in the candidate row")
    }
    panel.hide()
  }

  private static func testOnlineSourceAnnotations() {
    guard let yaml = try? String(contentsOfFile: "data/squirrel.yaml", encoding: .utf8),
      let sample = parseThemeSamples(yaml)["linnet_macos_light"] else { return }
    let panel = SquirrelPanel(position: NSRect(x: 260, y: 420, width: 2, height: 20))
    let controller = SquirrelInputController()
    panel.bind(controller: controller)
    configureThemeLayout(panel.view.lightTheme, sample: sample, point: 16, linear: false)
    let labels = ["腾讯", "百度", "DeepL", "ai"]
    let raw = "you (informal) / yourself\nsecond line"
    let items = labels.enumerated().map { index, label in
      SquirrelInputController.CandidateItem(text: "你",
        comment: LinnetCandidatePresentation.bilingualComment(displayText: "\(label):\(raw)",
          translations: [raw], detailText: "", sourceLabel: label),
        page: 0, indexOnPage: index, absoluteIndex: index, selectionLabel: String(index + 1))
    }
    require(panel.update(preedit: "ni", selRange: .empty, caretPos: 2,
      candidates: .init(items: items, pageSize: 5, currentPage: 0, isLastPage: true),
      highlighted: 0, update: true, controller: controller), "online source panel not published")
    render(panel.view)
    if let text = panel.view.textView.textContentStorage?.attributedString {
      for (index, label) in labels.enumerated() {
        let row = text.attributedSubstring(from: panel.view.candidateRanges[index]).string
        require(row.contains("\(label):\(raw)"), "online row lost its provider or original punctuation/newline")
      }
    } else { failures.append("online source text missing") }
    let frames = panel.view.candidateAccessibilityGeometry().candidateFrames
    require(frames.count == labels.count && frames.allSatisfy { panel.view.bounds.insetBy(dx: -1, dy: -1).contains($0) },
      "online source rows lost hit geometry")
    panel.hide()
  }

  private static func testStructuredLocalGlosses() {
    guard let yaml = try? String(contentsOfFile: "data/squirrel.yaml", encoding: .utf8),
      let sample = parseThemeSamples(yaml)["linnet_macos_light"] else { return }
    let lexicon = ZIMELocalLexicon(url: URL(fileURLWithPath: "resources/zime-cedict.sqlite3"))
    for region in [ZIMELocalLexicon.RegionProfile.mainland, .traditionalRegions] {
      let words = region == .mainland
        ? ["你", "发", "帅", "朋友", "工作", "学习", "你好", "天气", "下班"]
        : ["你", "妳", "發", "髮", "帥", "朋友", "工作", "學習", "你好"]
      let annotations = words.map { lexicon.annotation(for: $0, region: region) }
      for point in [CGFloat(12), 16, 32] {
        for count in 3...9 {
          let panel = SquirrelPanel(position: NSRect(x: 260, y: 420, width: 2, height: 20))
          let controller = SquirrelInputController()
          panel.bind(controller: controller)
          let view = panel.view
          configureThemeLayout(view.lightTheme, sample: sample, point: point, linear: false)
          let items = (0..<count).map { index in
            let annotation = annotations[index]
            return SquirrelInputController.CandidateItem(text: words[index],
              comment: LinnetCandidatePresentation.bilingualComment(displayText: annotation.displayText,
                translations: annotation.translations, detailText: annotation.detailText),
              page: 0, indexOnPage: index, absoluteIndex: index, selectionLabel: String(index + 1))
          }
          _ = panel.update(preedit: "ni", selRange: .empty, caretPos: 2,
            candidates: .init(items: items, pageSize: count, currentPage: 0, isLastPage: true),
            highlighted: 0, update: true, controller: controller)
          render(view)
          if let text = view.textView.textContentStorage?.attributedString {
            let ni = text.attributedSubstring(from: view.candidateRanges[0]).string
            require(ni.contains("you") && !ni.contains("informal") && !ni.contains("nin2") && !ni.contains("Mainland") && !ni.contains(" / you"),
              "structured 你 retained redundant / explanatory suffixes")
            for index in 0..<count {
              let row = text.attributedSubstring(from: view.candidateRanges[index]).string
              require(row.contains(annotations[index].displayText), "candidate lost its own structured gloss")
            }
          } else { failures.append("structured candidate text missing") }
          require(view.candidateToolTipTexts.first?.description == annotations[0].detailText,
            "structured full definitions were not delivered to native tooltip")
          if let first = view.accessibilityChildren()?.first as? LinnetCandidateAccessibilityElement {
            require(first.accessibilityHelp()?.contains("您[nin2]") == true, "AX lost original comparison note")
            require(first.accessibilityPerformPress() && controller.selectedCandidateIndices == [0], "structured annotation changed commit selection")
          } else { failures.append("structured candidate has no AX element") }
          panel.hide()
          require(view.candidateToolTipTexts.isEmpty, "stale structured tooltip survived hiding")
        }
      }
    }
  }

  private static func testColdCandidatePresentationLatency() {
    let panel = SquirrelPanel(position: NSRect(x: 320, y: 420, width: 2, height: 20))
    let controller = SquirrelInputController()
    panel.bind(controller: controller)
    let candidates = SquirrelInputController.CandidateSnapshot(
      items: ["测试", "侧室", "测速", "策士", "测式"].enumerated().map { index, value in
        .init(
          text: value, comment: "", page: 0, indexOnPage: index,
          absoluteIndex: index, selectionLabel: String(index + 1))
      },
      pageSize: 5,
      currentPage: 0,
      isLastPage: true)
    let coldStarted = ProcessInfo.processInfo.systemUptime
    let published = panel.update(
      preedit: "ceshi", selRange: .empty, caretPos: 5,
      candidates: candidates, highlighted: 0, update: true,
      controller: controller)
    let coldMilliseconds =
      (ProcessInfo.processInfo.systemUptime - coldStarted) * 1_000
    require(published, "cold candidate presentation did not publish")

    var steadySamples: [Double] = []
    for _ in 0..<20 {
      let started = ProcessInfo.processInfo.systemUptime
      let republished = panel.update(
        preedit: "ceshi", selRange: .empty, caretPos: 5,
        candidates: candidates, highlighted: 0, update: true,
        controller: controller)
      steadySamples.append(
        (ProcessInfo.processInfo.systemUptime - started) * 1_000)
      require(republished, "steady candidate presentation did not publish")
    }
    let sortedSteadySamples = steadySamples.sorted()
    let p95Index = min(
      sortedSteadySamples.count - 1,
      Int(ceil(Double(sortedSteadySamples.count) * 0.95)) - 1)
    let steadyP95 = sortedSteadySamples[p95Index]
    let steadyMaximum = sortedSteadySamples.last ?? .infinity
    require(
      steadyP95 < 50,
      "steady candidate presentation p95 took \(steadyP95)ms")
    require(
      steadyMaximum < 100,
      "steady candidate presentation maximum took \(steadyMaximum)ms")
    print(
      "candidate_interaction: cold_presentation_ms="
        + String(format: "%.2f", coldMilliseconds)
        + " steady_p95_ms=" + String(format: "%.2f", steadyP95)
        + " steady_max_ms=" + String(format: "%.2f", steadyMaximum))
    panel.hide()
  }

  private static func testInputModeStatusNotice() {
    let panel = SquirrelPanel(position: NSRect(x: 120, y: 120, width: 2, height: 20))
    let controller = SquirrelInputController()
    panel.bind(controller: controller)
    panel.updateStatus(
      long: "Smart English", short: "En",
      controller: controller)
    _ = panel.update(
      preedit: "", selRange: .empty, caretPos: 0,
      candidates: .init(
        items: [], pageSize: 0, currentPage: 0, isLastPage: true),
      highlighted: 0, update: true,
      controller: controller)
    let text = panel.contentView?.subviews.compactMap { $0 as? NSTextView }.first?
      .textContentStorage?.attributedString?.string
    require(panel.isVisible, "input-mode status was not presented beside the caret")
    require(
      text == "En",
      "input-mode status did not render the compact language label: \(text ?? "<missing>")")
    panel.handlePassiveEmptyUpdate(controller: controller)
    require(
      panel.isVisible && panel.statusTimer != nil,
      "a passive empty Rime update dismissed the timed input-mode status")
    guard let candidateView = panel.contentView?.subviews.compactMap({
      $0 as? SquirrelView
    }).first else {
      failures.append("input-mode status lost its production presentation surface")
      panel.hide()
      return
    }
    require(
      candidateView.accessibilityRole() == .group &&
        candidateView.accessibilityLabel() == "Input mode",
      "input-mode status was exposed as a candidate list"
    )
    let children = candidateView.accessibilityChildren() ?? []
    require(
      children.count == 1 &&
        (children[0] as? NSAccessibilityElement)?.accessibilityLabel() == "En",
      "input-mode status lost its accessible language announcement"
    )
    panel.hide()
  }

  private static func testVerticalPanelDoesNotMemorizeWhenDisabled() {
    guard let screen = NSScreen.main?.visibleFrame else { return }
    let caret = NSRect(
      x: screen.maxX - 2,
      y: screen.midY,
      width: 1,
      height: 18)
    let panel = SquirrelPanel(position: caret)
    let controller = SquirrelInputController()
    panel.bind(controller: controller)
    guard let candidateView = panel.contentView?.subviews.compactMap({
      $0 as? SquirrelView
    }).first else {
      failures.append("vertical resize fixture lost its candidate view")
      return
    }
    candidateView.lightTheme.vertical = true
    candidateView.lightTheme.linear = false
    candidateView.lightTheme.memorizeSize = false
    panel.updatePosition(caret)
    let longText = String(repeating: "候选词", count: 18)
    _ = panel.update(
      preedit: "", selRange: .empty, caretPos: 0,
      candidates: candidatePublication([(text: longText, absoluteIndex: 1)]),
      highlighted: 0, update: true,
      controller: controller)
    let longHeight = panel.frame.height
    _ = panel.update(
      preedit: "", selRange: .empty, caretPos: 0,
      candidates: candidatePublication([(text: "词", absoluteIndex: 2)]),
      highlighted: 0, update: true,
      controller: controller)
    let shortHeight = panel.frame.height
    require(
      shortHeight + 1 < longHeight,
      "vertical candidates retained a prior long size with memorize-size disabled")
    require(
      panel.frame.width <= screen.width * 0.95 + 0.5 &&
        panel.frame.height <= screen.height * 0.95 + 0.5,
      "candidate frame plus paging strip exceeded the 95% screen cap")
    panel.hide()
  }

  private static func testTrackingArea() {
    let view = SquirrelView(frame: NSRect(x: 0, y: 0, width: 220, height: 60))
    view.updateTrackingAreas()
    let owned = view.trackingAreas.filter { $0.owner === view }
    require(owned.count == 1, "candidate view must own exactly one pointer tracking area")
    guard let options = owned.first?.options else { return }
    for option: NSTrackingArea.Options in [
      .inVisibleRect, .mouseEnteredAndExited, .mouseMoved, .activeAlways,
    ] {
      require(options.contains(option), "candidate tracking area lost option \(option.rawValue)")
    }
  }

  private static func testExactCandidatePathHitTesting() {
    let splitCandidate = CGMutablePath()
    splitCandidate.addRect(NSRect(x: 0, y: 0, width: 10, height: 10))
    splitCandidate.addRect(NSRect(x: 30, y: 0, width: 10, height: 10))
    let middleCandidate = CGPath(
      rect: NSRect(x: 15, y: 0, width: 10, height: 10),
      transform: nil)
    let paths: [CGPath?] = [splitCandidate, middleCandidate]

    require(
      SquirrelView.candidateIndex(
        at: NSPoint(x: 20, y: 5),
        paths: paths) == 1,
      "a split candidate's bounding box stole another candidate's hit")
    require(
      SquirrelView.candidateIndex(
        at: NSPoint(x: 12, y: 5),
        paths: paths) == nil,
      "empty space inside a multi-line bounding box selected a candidate")
  }

  private static func testSyntheticHoverLifecycle() {
    let panel = SquirrelPanel(position: NSRect(x: 120, y: 120, width: 2, height: 20))
    let controller = SquirrelInputController()
    panel.bind(controller: controller)
    let candidates = SquirrelInputController.CandidateSnapshot(
      items: [
        .init(text: "输入", comment: "", page: 0, indexOnPage: 0,
              absoluteIndex: 0, selectionLabel: "1"),
        .init(text: "输入法", comment: "", page: 0, indexOnPage: 1,
              absoluteIndex: 1, selectionLabel: "2"),
      ],
      pageSize: 2,
      currentPage: 0,
      isLastPage: true)
    _ = panel.update(
      preedit: "", selRange: .empty, caretPos: 0,
      candidates: candidates, highlighted: 0, update: true,
      controller: controller)
    guard let candidateView = panel.contentView?.subviews.compactMap({
      $0 as? SquirrelView
    }).first else {
      failures.append("candidate panel did not retain its production SquirrelView")
      return
    }
    let frames = candidateView.candidateAccessibilityGeometry().candidateFrames
    guard frames.count == 2 else {
      failures.append("synthetic hover fixture did not publish two candidate cells")
      panel.hide()
      return
    }
    candidateView.updateTrackingAreas()
    guard candidateView.trackingAreas.contains(where: { $0.owner === candidateView }) else {
      failures.append("synthetic hover has no production tracking area")
      panel.hide()
      return
    }
    let secondPoint = candidateView.convert(frames[1].center, to: nil)
    if let entered = NSEvent.enterExitEvent(
      with: .mouseEntered,
      location: secondPoint,
      modifierFlags: [],
      timestamp: 1,
      windowNumber: panel.windowNumber,
      context: nil,
      eventNumber: 1,
      trackingNumber: 1,
      userData: nil)
    {
      panel.sendEvent(entered)
    }
    if let moved = NSEvent.mouseEvent(
      with: .mouseMoved,
      location: secondPoint,
      modifierFlags: [],
      timestamp: 2,
      windowNumber: panel.windowNumber,
      context: nil,
      eventNumber: 2,
      clickCount: 0,
      pressure: 0)
    {
      panel.sendEvent(moved)
    }
    requireEngineHighlight(
      0, in: candidateView,
      "mouse move replaced the Rime-owned visual or accessibility selection")
    require(
      candidateView.shape.candidateIndex == 1 &&
        !candidateView.shape.isPressed,
      "mouse move did not publish hover feedback for the second candidate")
    requirePointerFeedback(
      in: candidateView, candidateIndex: 1, expectedAlpha: 0.08,
      context: "second-candidate hover")
    if let exited = NSEvent.enterExitEvent(
      with: .mouseExited,
      location: secondPoint,
      modifierFlags: [],
      timestamp: 3,
      windowNumber: panel.windowNumber,
      context: nil,
      eventNumber: 3,
      trackingNumber: 1,
      userData: nil)
    {
      panel.sendEvent(exited)
    }
    requireEngineHighlight(
      0, in: candidateView,
      "mouse exit replaced the Rime-owned visual or accessibility selection")
    require(
      candidateView.shape.candidateIndex == nil &&
        !candidateView.shape.isPressed,
      "mouse exit did not clear candidate pointer feedback")
    requireNoPointerFeedback(in: candidateView, context: "mouse exit")
    panel.hide()
  }

  private static func testAccessibilitySelectionKeepsElementIdentity() {
    let panel = SquirrelPanel(position: NSRect(x: 120, y: 120, width: 2, height: 20))
    let controller = SquirrelInputController()
    panel.bind(controller: controller)
    guard let candidateView = panel.contentView?.subviews.compactMap({
      $0 as? SquirrelView
    }).first else {
      failures.append("accessibility identity fixture lost its candidate view")
      return
    }
    candidateView.lightTheme.highlightedAttrs = candidateView.lightTheme.attrs
    candidateView.lightTheme.labelHighlightedAttrs = candidateView.lightTheme.labelAttrs
    candidateView.lightTheme.commentHighlightedAttrs = candidateView.lightTheme.commentAttrs
    let candidates = candidatePublication([
      (text: "甲", absoluteIndex: 101),
      (text: "乙", absoluteIndex: 102),
    ])
    _ = panel.update(
      preedit: "", selRange: .empty, caretPos: 0,
      candidates: candidates, highlighted: 0, update: true,
      controller: controller)
    guard let firstChildren = candidateView.accessibilityChildren(),
      firstChildren.count >= 2
    else {
      failures.append("accessibility identity fixture did not publish candidates")
      panel.hide()
      return
    }

    _ = panel.update(
      preedit: "", selRange: .empty, caretPos: 0,
      candidates: candidates, highlighted: 1, update: true,
      controller: controller)
    let secondChildren = candidateView.accessibilityChildren() ?? []
    let selected = candidateView.accessibilitySelectedChildren() ?? []
    let firstElements = firstChildren.compactMap { $0 as? NSAccessibilityElement }
    let secondElements = secondChildren.compactMap { $0 as? NSAccessibilityElement }
    let selectedElements = selected.compactMap { $0 as? NSAccessibilityElement }
    require(
      firstElements.count >= 2 && secondElements.count >= 2 &&
        firstElements[0] === secondElements[0] &&
        firstElements[1] === secondElements[1],
      "a selection-only update replaced VoiceOver candidate identities")
    require(
      selectedElements.count == 1 && selectedElements[0] === secondElements[1],
      "a selection-only update did not publish the new VoiceOver selection")
    panel.hide()
  }

  private static func testStaleAccessibilityDoesNotRetainController() {
    let panel = SquirrelPanel(position: NSRect(x: 120, y: 120, width: 2, height: 20))
    weak var releasedController: SquirrelInputController?
    var staleElement: LinnetCandidateAccessibilityElement?
    do {
      let controller = SquirrelInputController()
      releasedController = controller
      panel.bind(controller: controller)
      _ = panel.update(
        preedit: "", selRange: .empty, caretPos: 0,
        candidates: candidatePublication([(text: "甲", absoluteIndex: 101)]),
        highlighted: 0, update: true,
        controller: controller)
      let candidateView = panel.contentView?.subviews.compactMap({
        $0 as? SquirrelView
      }).first
      staleElement = candidateView?.accessibilityChildren()?.first
        as? LinnetCandidateAccessibilityElement
      panel.unbind(controller: controller)
    }
    require(
      releasedController == nil,
      "a stale accessibility action retained its retired input controller")
    require(
      staleElement?.accessibilityPerformPress() == false,
      "a stale accessibility action remained authoritative after unbind")
  }

  private static func testAccessibilityRejectsInvalidGeometry() {
    let view = SquirrelView(frame: NSRect(x: 0, y: 0, width: 180, height: 40))
    let accessibility = LinnetCandidateAccessibility()
    accessibility.install(parent: view, rawTextView: view.textView)
    accessibility.publish(
      parent: view,
      publication: .init(
        geometry: .init(
          candidateFrames: [],
          previousPageFrame: nil,
          nextPageFrame: nil),
        candidates: [
          .init(
            text: "甲", comment: "", page: 0, indexOnPage: 0,
            absoluteIndex: 101, selectionLabel: "1"),
        ],
        highlightedIndex: 0,
        controlMode: .paging(canPageUp: false, canPageDown: false),
        shouldAnnounce: false),
      selectCandidate: { _ in true },
      performControl: { _ in true })
    require(
      (view.accessibilityChildren() ?? []).isEmpty,
      "invalid candidate geometry was exposed as a whole-window AX button")

    let validCandidateFrame = NSRect(x: 4, y: 4, width: 40, height: 20)
    let validControlFrame = NSRect(x: 52, y: 4, width: 20, height: 20)
    let invalidControlCases: [(
      label: String,
      mode: LinnetCandidatePresentation.CandidateControlMode,
      previous: NSRect?,
      next: NSRect?,
      expectedActions: [LinnetCandidatePresentation.CandidateControlAction]
    )] = [
      (
        label: "empty previous-page frame",
        mode: .paging(canPageUp: true, canPageDown: true),
        previous: .zero,
        next: validControlFrame,
        expectedActions: [.pageDown]
      ),
      (
        label: "zero-width next-page frame",
        mode: .paging(canPageUp: true, canPageDown: true),
        previous: validControlFrame,
        next: NSRect(x: 76, y: 4, width: 0, height: 20),
        expectedActions: [.pageUp]
      ),
      (
        label: "non-finite next-page frame",
        mode: .paging(canPageUp: false, canPageDown: true),
        previous: nil,
        next: NSRect(x: CGFloat.nan, y: 4, width: 20, height: 20),
        expectedActions: []
      ),
      (
        label: "non-finite previous-page frame",
        mode: .paging(canPageUp: true, canPageDown: false),
        previous: NSRect(x: 52, y: 4, width: 20, height: CGFloat.infinity),
        next: nil,
        expectedActions: []
      ),
    ]
    for invalidCase in invalidControlCases {
      var performedActions: [LinnetCandidatePresentation.CandidateControlAction] = []
      accessibility.publish(
        parent: view,
        publication: .init(
          geometry: .init(
            candidateFrames: [validCandidateFrame],
            previousPageFrame: invalidCase.previous,
            nextPageFrame: invalidCase.next),
          candidates: [
            .init(
              text: "甲", comment: "", page: 0, indexOnPage: 0,
              absoluteIndex: 101, selectionLabel: "1"),
          ],
          highlightedIndex: 0,
          controlMode: invalidCase.mode,
          shouldAnnounce: false),
        selectCandidate: { _ in true },
        performControl: { action in
          performedActions.append(action)
          return true
        })
      let children = view.accessibilityChildren() ?? []
      for control in children.dropFirst() {
        _ = (control as? LinnetCandidateAccessibilityElement)?
          .accessibilityPerformPress()
      }
      require(
        children.count == invalidCase.expectedActions.count + 1 &&
          performedActions == invalidCase.expectedActions,
        "\(invalidCase.label) published an invalid AX control frame")
    }
  }

  private static func testPreciseWheelPagingSemantics() {
    let start = Date(timeIntervalSinceReferenceDate: 100)
    func sample(
      deltaY: CGFloat,
      phase: NSEvent.Phase = [],
      momentumPhase: NSEvent.Phase = [],
      at timestamp: Date
    ) -> LinnetCandidateInteractionState<Int>.ScrollSample {
      return .init(
        delta: CGVector(dx: 0, dy: deltaY),
        hasPreciseScrollingDeltas: true,
        phase: phase,
        momentumPhase: momentumPhase,
        timestamp: timestamp)
    }

    var accumulated = LinnetCandidateInteractionState<Int>()
    let firstHalf = accumulated.processScroll(
      sample(deltaY: 6, at: start), vertical: false)
    let secondHalf = accumulated.processScroll(
      sample(deltaY: 6, at: start.addingTimeInterval(0.1)),
      vertical: false)
    require(
      firstHalf == nil && secondHalf == .previousPage,
      "two precise 6-point wheel deltas did not page exactly once")

    var reversed = LinnetCandidateInteractionState<Int>()
    let forwardHalf = reversed.processScroll(
      sample(deltaY: 6, at: start), vertical: false)
    let firstReverseHalf = reversed.processScroll(
      sample(deltaY: -6, at: start.addingTimeInterval(0.1)),
      vertical: false)
    let secondReverseHalf = reversed.processScroll(
      sample(deltaY: -6, at: start.addingTimeInterval(0.2)),
      vertical: false)
    require(
      forwardHalf == nil && firstReverseHalf == nil &&
        secondReverseHalf == .nextPage,
      "a precise direction change discarded its first reverse delta")

    var momentum = LinnetCandidateInteractionState<Int>()
    _ = momentum.processScroll(
      sample(deltaY: 6, at: start), vertical: false)
    let momentumIntent = momentum.processScroll(
      sample(
        deltaY: 12,
        momentumPhase: .changed,
        at: start.addingTimeInterval(0.1)),
      vertical: false)
    let afterMomentum = momentum.processScroll(
      sample(deltaY: 6, at: start.addingTimeInterval(0.2)),
      vertical: false)
    require(
      momentumIntent == nil && afterMomentum == nil,
      "momentum paged or retained a precise wheel remainder")

    var cancelled = LinnetCandidateInteractionState<Int>()
    _ = cancelled.processScroll(
      sample(deltaY: 0, phase: .began, at: start), vertical: false)
    _ = cancelled.processScroll(
      sample(
        deltaY: 12,
        phase: .changed,
        at: start.addingTimeInterval(0.1)),
      vertical: false)
    let cancelledIntent = cancelled.processScroll(
      sample(
        deltaY: 0,
        phase: .cancelled,
        at: start.addingTimeInterval(0.2)),
      vertical: false)
    let staleEndIntent = cancelled.processScroll(
      sample(
        deltaY: 0,
        phase: .ended,
        at: start.addingTimeInterval(0.3)),
      vertical: false)
    require(
      cancelledIntent == nil && staleEndIntent == nil,
      "a cancelled precise gesture still paged")
  }

  private static func testCandidatePressPublicationIdentity() {
    let panel = SquirrelPanel(position: NSRect(x: 120, y: 120, width: 2, height: 20))
    let controller = SquirrelInputController()
    panel.bind(controller: controller)
    let firstPublication = candidatePublication([
      (text: "甲", absoluteIndex: 101),
      (text: "乙", absoluteIndex: 102),
    ])
    let secondPublication = candidatePublication([
      (text: "丙", absoluteIndex: 201),
      (text: "丁", absoluteIndex: 202),
    ])

    _ = panel.update(
      preedit: "", selRange: .empty, caretPos: 0,
      candidates: firstPublication, highlighted: 0, update: true,
      controller: controller)
    guard let candidateView = panel.contentView?.subviews.compactMap({
      $0 as? SquirrelView
    }).first,
      candidateView.candidateAccessibilityGeometry().candidateFrames.count == 2
    else {
      failures.append("candidate press fixture did not publish two candidate cells")
      panel.hide()
      return
    }
    let candidateFrames = candidateView.candidateAccessibilityGeometry().candidateFrames
    let secondCandidatePoint = candidateView.convert(candidateFrames[1].center, to: nil)
    let outsidePoint = candidateView.convert(
      NSPoint(x: candidateView.bounds.minX - 10, y: candidateView.bounds.minY - 10),
      to: nil)

    sendCandidateMouse(.mouseMoved, at: secondCandidatePoint, to: panel, eventNumber: 20)
    requireEngineHighlight(
      0, in: candidateView,
      "mouse move changed the engine-selected first candidate")
    require(
      candidateView.shape.candidateIndex == 1 &&
        !candidateView.shape.isPressed,
      "hovering the second candidate did not change the visual pointer index")
    _ = panel.update(
      preedit: "", selRange: .empty, caretPos: 0,
      candidates: firstPublication, highlighted: 0, update: true,
      controller: controller)
    require(
      candidateView.shape.candidateIndex == nil &&
        !candidateView.shape.isPressed,
      "a replacement publication retained stale hover feedback")
    sendCandidateMouse(.leftMouseDown, at: secondCandidatePoint, to: panel, eventNumber: 21)
    requireEngineHighlight(
      0, in: candidateView,
      "mouse press changed the engine-selected first candidate")
    require(
      candidateView.shape.candidateIndex == 1 &&
        candidateView.shape.isPressed,
      "mouse-down did not immediately publish pressed feedback")
    requirePointerFeedback(
      in: candidateView, candidateIndex: 1, expectedAlpha: 0.16,
      context: "second-candidate press")
    sendCandidateMouse(.leftMouseUp, at: secondCandidatePoint, to: panel, eventNumber: 22)
    require(
      controller.selectedCandidateIndices == [102],
      "clicking the second candidate did not commit that candidate exactly once")
    requireEngineHighlight(
      0, in: candidateView,
      "committing a clicked candidate replaced the engine-owned selection")
    require(
      candidateView.shape.candidateIndex == 1 &&
        !candidateView.shape.isPressed,
      "mouse-up did not return pressed feedback to hover feedback")

    controller.resetSelectedCandidates()
    _ = panel.update(
      preedit: "", selRange: .empty, caretPos: 0,
      candidates: firstPublication, highlighted: 0, update: true,
      controller: controller)
    sendCandidateMouse(.leftMouseDown, at: secondCandidatePoint, to: panel, eventNumber: 23)
    sendCandidateMouse(.mouseExited, at: outsidePoint, to: panel, eventNumber: 24)
    sendCandidateMouse(.leftMouseUp, at: outsidePoint, to: panel, eventNumber: 25)
    require(
      controller.selectedCandidateIndices.isEmpty,
      "dragging out of the second candidate committed it")
    requireEngineHighlight(
      0, in: candidateView,
      "dragging out of a candidate replaced the engine-owned selection")

    controller.resetSelectedCandidates()
    _ = panel.update(
      preedit: "", selRange: .empty, caretPos: 0,
      candidates: firstPublication, highlighted: 0, update: true,
      controller: controller)
    sendCandidateMouse(.leftMouseDown, at: secondCandidatePoint, to: panel, eventNumber: 26)
    sendCandidateMouse(.mouseExited, at: outsidePoint, to: panel, eventNumber: 27)
    sendCandidateMouse(.leftMouseDragged, at: secondCandidatePoint, to: panel, eventNumber: 28)
    require(
      candidateView.shape.candidateIndex == 1 &&
        candidateView.shape.isPressed,
      "dragging back to the pressed candidate did not restore pressed feedback")
    sendCandidateMouse(.leftMouseUp, at: secondCandidatePoint, to: panel, eventNumber: 29)
    require(
      controller.selectedCandidateIndices == [102],
      "dragging away and back did not preserve the original click target")

    controller.resetSelectedCandidates()
    _ = panel.update(
      preedit: "", selRange: .empty, caretPos: 0,
      candidates: firstPublication, highlighted: 0, update: true,
      controller: controller)
    sendCandidateMouse(.leftMouseDown, at: secondCandidatePoint, to: panel, eventNumber: 30)
    _ = panel.update(
      preedit: "", selRange: .empty, caretPos: 0,
      candidates: secondPublication, highlighted: 0, update: true,
      controller: controller)
    require(
      candidateView.shape.candidateIndex == nil &&
        !candidateView.shape.isPressed,
      "a new publication retained the previous candidate's pressed feedback")
    requireNoPointerFeedback(in: candidateView, context: "new publication")
    sendCandidateMouse(.leftMouseUp, at: secondCandidatePoint, to: panel, eventNumber: 31)
    require(
      controller.selectedCandidateIndices.isEmpty,
      "a candidate press crossed publications and committed replacement candidate 202")
    requireEngineHighlight(
      0, in: candidateView,
      "a replacement publication did not restore its engine-owned selection")

    controller.resetSelectedCandidates()
    _ = panel.update(
      preedit: "", selRange: .empty, caretPos: 0,
      candidates: firstPublication, highlighted: 0, update: true,
      controller: controller)
    sendCandidateMouse(.leftMouseDown, at: secondCandidatePoint, to: panel, eventNumber: 32)
    _ = panel.update(
      preedit: "", selRange: .empty, caretPos: 0,
      candidates: firstPublication, highlighted: 0, update: false,
      controller: controller)
    sendCandidateMouse(.leftMouseUp, at: secondCandidatePoint, to: panel, eventNumber: 33)
    require(
      controller.selectedCandidateIndices == [102],
      "a hover-only redraw cancelled a press within the same publication")
    requireEngineHighlight(
      0, in: candidateView,
      "a hover-only redraw replaced the engine-owned selection")
    sendCandidateMouse(.mouseMoved, at: secondCandidatePoint, to: panel, eventNumber: 34)
    panel.hide()
    require(
      candidateView.shape.candidateIndex == nil &&
        !candidateView.shape.isPressed,
      "hiding the panel retained candidate pointer feedback")
    requireNoPointerFeedback(in: candidateView, context: "panel hide")
  }

  private static func testCandidateControlPointerFeedback() {
    let panel = SquirrelPanel(position: NSRect(x: 120, y: 120, width: 2, height: 20))
    let controller = SquirrelInputController()
    panel.bind(controller: controller)
    guard let candidateView = panel.contentView?.subviews.compactMap({
      $0 as? SquirrelView
    }).first else {
      failures.append("candidate control feedback fixture lost its view")
      return
    }
    candidateView.lightTheme.showPaging = true
    let candidates = SquirrelInputController.CandidateSnapshot(
      items: candidatePublication([
        (text: "甲", absoluteIndex: 101),
        (text: "乙", absoluteIndex: 102),
      ]).items,
      pageSize: 2,
      currentPage: 1,
      isLastPage: false)
    _ = panel.update(
      preedit: "", selRange: .empty, caretPos: 0,
      candidates: candidates, highlighted: 0, update: true,
      controller: controller)
    panel.displayIfNeeded()
    guard let nextPage = candidateView.pagingLayout.nextPage else {
      failures.append("candidate control feedback fixture lost next-page geometry")
      panel.hide()
      return
    }
    let point = candidateView.convert(nextPage.visualCenter, to: nil)
    sendCandidateMouse(.mouseMoved, at: point, to: panel, eventNumber: 60)
    require(
      candidateView.pointerControlAction == .pageDown &&
        !candidateView.pointerControlIsPressed,
      "paging hover did not publish control feedback")
    requireControlFeedback(
      in: candidateView,
      expectedAlpha: 0.08,
      context: "next-page hover")
    sendCandidateMouse(.leftMouseDown, at: point, to: panel, eventNumber: 61)
    require(
      candidateView.pointerControlAction == .pageDown &&
        candidateView.pointerControlIsPressed,
      "paging press did not publish pressed feedback")
    requireControlFeedback(
      in: candidateView,
      expectedAlpha: 0.16,
      context: "next-page press")
    sendCandidateMouse(.mouseExited, at: point, to: panel, eventNumber: 62)
    require(
      candidateView.pointerControlAction == nil &&
        !candidateView.pointerControlIsPressed,
      "paging pointer exit retained control feedback")
    panel.hide()
  }

  private static func testPreeditPressDoesNotInferEngineCaret() {
    let panel = SquirrelPanel(position: NSRect(x: 120, y: 120, width: 2, height: 20))
    let controller = SquirrelInputController()
    panel.bind(controller: controller)
    let candidates = candidatePublication([(text: "测试", absoluteIndex: 0)])
    _ = panel.update(
      preedit: "ceshi", selRange: NSRange(location: 0, length: 5), caretPos: 5,
      candidates: candidates, highlighted: 0, update: true,
      controller: controller)
    guard let candidateView = panel.contentView?.subviews.compactMap({
      $0 as? SquirrelView
    }).first,
      let preeditTextRange = candidateView.convert(range: NSRange(location: 0, length: 1))
    else {
      failures.append("preedit press fixture did not publish text geometry")
      panel.hide()
      return
    }
    candidateView.layoutSubtreeIfNeeded()
    var preeditPoint = candidateView.contentRect(range: preeditTextRange).center
    preeditPoint.x += candidateView.textView.frame.minX
      + candidateView.textView.textContainerInset.width
    preeditPoint.y += candidateView.textView.frame.minY
      + candidateView.textView.textContainerInset.height
    let windowPreeditPoint = candidateView.convert(preeditPoint, to: nil)
    let candidateFrame = candidateView.candidateAccessibilityGeometry().candidateFrames.first
    guard let candidateFrame else {
      failures.append("preedit press fixture did not publish candidate geometry")
      panel.hide()
      return
    }
    let windowCandidatePoint = candidateView.convert(candidateFrame.center, to: nil)

    sendCandidateMouse(.leftMouseDown, at: windowCandidatePoint, to: panel, eventNumber: 30)
    sendCandidateMouse(.leftMouseUp, at: windowPreeditPoint, to: panel, eventNumber: 31)
    require(
      controller.selectedCandidateIndices.isEmpty &&
        controller.pageDirections.isEmpty,
      "dragging from a candidate onto preedit text mutated the engine")

    sendCandidateMouse(.leftMouseDown, at: windowPreeditPoint, to: panel, eventNumber: 32)
    sendCandidateMouse(.leftMouseUp, at: windowPreeditPoint, to: panel, eventNumber: 33)
    require(
      controller.selectedCandidateIndices.isEmpty &&
        controller.pageDirections.isEmpty,
      "displayed preedit coordinates were incorrectly applied to raw Rime input")
    panel.hide()
  }

  private static func testSameControllerReactivationInvalidatesOldPublication() {
    let panel = SquirrelPanel(position: NSRect(x: 120, y: 120, width: 2, height: 20))
    let controller = SquirrelInputController()
    panel.bind(controller: controller)
    let candidates = candidatePublication([
      (text: "甲", absoluteIndex: 101),
      (text: "乙", absoluteIndex: 102),
    ])
    _ = panel.update(
      preedit: "", selRange: .empty, caretPos: 0,
      candidates: candidates, highlighted: 0, update: true,
      controller: controller)
    guard let candidateView = panel.contentView?.subviews.compactMap({
      $0 as? SquirrelView
    }).first,
      let staleAccessibilityAction = candidateView.accessibilityChildren()?.first
        as? LinnetCandidateAccessibilityElement,
      candidateView.candidateAccessibilityGeometry().candidateFrames.count == 2
    else {
      failures.append("same-controller reactivation fixture did not publish actions")
      panel.hide()
      return
    }
    let secondPoint = candidateView.convert(
      candidateView.candidateAccessibilityGeometry().candidateFrames[1].center,
      to: nil)
    sendCandidateMouse(.leftMouseDown, at: secondPoint, to: panel, eventNumber: 34)

    panel.unbind(controller: controller)
    panel.bind(controller: controller)
    require(
      panel.publication == nil && panel.inputController === controller,
      "same-controller reactivation retained the previous publication")
    require(
      !staleAccessibilityAction.accessibilityPerformPress(),
      "an accessibility action crossed same-controller activation generations")
    sendCandidateMouse(.leftMouseUp, at: secondPoint, to: panel, eventNumber: 35)
    require(
      controller.selectedCandidateIndices.isEmpty,
      "a mouse press crossed same-controller activation generations")

    _ = panel.update(
      preedit: "", selRange: .empty, caretPos: 0,
      candidates: candidates, highlighted: 0, update: true,
      controller: controller)
    guard let currentAccessibilityAction = candidateView.accessibilityChildren()?.first
      as? LinnetCandidateAccessibilityElement
    else {
      failures.append("replacement activation did not publish accessibility actions")
      panel.hide()
      return
    }
    require(
      currentAccessibilityAction.accessibilityPerformPress() &&
        controller.selectedCandidateIndices == [101],
      "the replacement activation did not accept its own exact action")
    panel.hide()
  }

  private static func testInputControllerOwnerSwapInvalidatesCandidateInteraction() {
    let panel = SquirrelPanel(position: NSRect(x: 120, y: 120, width: 2, height: 20))
    let oldController = SquirrelInputController()
    let newController = SquirrelInputController()
    let finalController = SquirrelInputController()
    let candidates = candidatePublication([
      (text: "甲", absoluteIndex: 101),
      (text: "乙", absoluteIndex: 102),
    ])
    panel.bind(controller: oldController)
    _ = panel.update(
      preedit: "", selRange: .empty, caretPos: 0,
      candidates: candidates, highlighted: 0, update: true,
      controller: oldController)
    guard let candidateView = panel.contentView?.subviews.compactMap({
      $0 as? SquirrelView
    }).first,
      candidateView.candidateAccessibilityGeometry().candidateFrames.count == 2
    else {
      failures.append("controller-swap fixture did not publish candidate geometry")
      panel.hide()
      return
    }
    let secondPoint = candidateView.convert(
      candidateView.candidateAccessibilityGeometry().candidateFrames[1].center,
      to: nil)
    guard let staleAccessibilityAction = candidateView.accessibilityChildren()?.first
      as? LinnetCandidateAccessibilityElement
    else {
      failures.append("controller-swap fixture did not publish accessibility actions")
      panel.hide()
      return
    }
    sendCandidateMouse(.leftMouseDown, at: secondPoint, to: panel, eventNumber: 35)
    panel.bind(controller: newController)
    require(!panel.isVisible, "controller swap retained the previous candidate panel")
    require(
      candidateView.shape.candidateIndex == nil &&
        !candidateView.shape.isPressed,
      "controller swap retained the previous pointer interaction")
    require(
      candidateView.accessibilityChildren()?.isEmpty == true,
      "controller swap retained the previous accessibility candidates")
    sendCandidateMouse(.leftMouseUp, at: secondPoint, to: panel, eventNumber: 36)
    require(
      !staleAccessibilityAction.accessibilityPerformPress() &&
        oldController.selectedCandidateIndices.isEmpty &&
        newController.selectedCandidateIndices.isEmpty,
      "an old mouse or accessibility action crossed controller ownership")

    _ = panel.update(
      preedit: "", selRange: .empty, caretPos: 0,
      candidates: candidates, highlighted: 0, update: true,
      controller: newController)
    sendCandidateScroll(deltaY: 6, phase: 0, to: panel)
    panel.bind(controller: finalController)
    sendCandidateScroll(deltaY: 6, phase: 0, to: panel)
    require(
      finalController.pageDirections.isEmpty,
      "a wheel remainder crossed input-controller ownership")
    panel.hide()
  }

  private static func testCandidateScrollPublicationIdentity() {
    let panel = SquirrelPanel(position: NSRect(x: 120, y: 120, width: 2, height: 20))
    let controller = SquirrelInputController()
    panel.bind(controller: controller)
    let firstPublication = candidatePublication([
      (text: "甲", absoluteIndex: 101),
      (text: "乙", absoluteIndex: 102),
    ])
    let secondPublication = candidatePublication([
      (text: "丙", absoluteIndex: 201),
      (text: "丁", absoluteIndex: 202),
    ])
    _ = panel.update(
      preedit: "", selRange: .empty, caretPos: 0,
      candidates: firstPublication, highlighted: 0, update: true,
      controller: controller)
    guard let candidateView = panel.contentView?.subviews.compactMap({
      $0 as? SquirrelView
    }).first,
      candidateView.candidateAccessibilityGeometry().candidateFrames.count == 2
    else {
      failures.append("candidate scroll fixture did not publish two candidate cells")
      panel.hide()
      return
    }
    let secondPoint = candidateView.convert(
      candidateView.candidateAccessibilityGeometry().candidateFrames[1].center,
      to: nil)

    sendCandidateMouse(.leftMouseDown, at: secondPoint, to: panel, eventNumber: 40)
    sendCandidateScroll(deltaY: 2, phase: 0, to: panel)
    sendCandidateMouse(.leftMouseUp, at: secondPoint, to: panel, eventNumber: 41)
    require(
      controller.selectedCandidateIndices.isEmpty,
      "a candidate press survived an intervening scroll gesture")

    controller.resetPageDirections()
    sendCandidateScroll(deltaY: 0, phase: 1, to: panel)
    sendCandidateScroll(deltaY: 8, phase: 2, to: panel)
    _ = panel.update(
      preedit: "", selRange: .empty, caretPos: 0,
      candidates: secondPublication, highlighted: 0, update: true,
      controller: controller)
    sendCandidateScroll(deltaY: 8, phase: 2, to: panel)
    sendCandidateScroll(deltaY: 0, phase: 4, to: panel)
    require(
      controller.pageDirections.isEmpty,
      "a phased scroll gesture crossed candidate publications")

    sendCandidateScroll(deltaY: 0, phase: 1, to: panel)
    sendCandidateScroll(deltaY: 12, phase: 2, to: panel)
    sendCandidateScroll(deltaY: 0, phase: 4, to: panel)
    require(
      controller.pageDirections == [true],
      "a same-publication trackpad gesture did not page exactly once")

    controller.resetPageDirections()
    sendCandidateScroll(deltaY: 1, phase: 0, units: .line, to: panel)
    sendCandidateScroll(deltaY: -1, phase: 0, units: .line, to: panel)
    require(
      controller.pageDirections == [true, false],
      "ordinary wheel ticks did not page once in each direction")

    controller.resetPageDirections()
    sendCandidateScroll(deltaY: 6, phase: 0, to: panel)
    panel.hide()
    _ = panel.update(
      preedit: "", selRange: .empty, caretPos: 0,
      candidates: firstPublication, highlighted: 0, update: true,
      controller: controller)
    sendCandidateScroll(deltaY: 6, phase: 0, to: panel)
    require(
      controller.pageDirections.isEmpty,
      "a mouse-wheel remainder survived hide and a new publication")
    panel.hide()
  }

  private static func candidatePublication(
    _ candidates: [(text: String, absoluteIndex: Int)]
  ) -> SquirrelInputController.CandidateSnapshot {
    .init(
      items: candidates.enumerated().map { index, candidate in
        .init(
          text: candidate.text, comment: "", page: 0, indexOnPage: index,
          absoluteIndex: candidate.absoluteIndex, selectionLabel: String(index + 1))
      },
      pageSize: candidates.count,
      currentPage: 0,
      isLastPage: true)
  }

  private static func sendCandidateMouse(
    _ type: NSEvent.EventType,
    at point: NSPoint,
    to panel: SquirrelPanel,
    eventNumber: Int
  ) {
    let event: NSEvent?
    if type == .mouseEntered || type == .mouseExited {
      event = NSEvent.enterExitEvent(
        with: type,
        location: point,
        modifierFlags: [],
        timestamp: TimeInterval(eventNumber),
        windowNumber: panel.windowNumber,
        context: nil,
        eventNumber: eventNumber,
        trackingNumber: 1,
        userData: nil)
    } else {
      event = NSEvent.mouseEvent(
        with: type,
        location: point,
        modifierFlags: [],
        timestamp: TimeInterval(eventNumber),
        windowNumber: panel.windowNumber,
        context: nil,
        eventNumber: eventNumber,
        clickCount: 1,
        pressure: type == .leftMouseDown ? 1 : 0)
    }
    guard let event
    else {
      failures.append("candidate press fixture could not create mouse event \(eventNumber)")
      return
    }
    panel.sendEvent(event)
  }

  private static func sendCandidateScroll(
    deltaY: Int32,
    phase: Int64,
    units: CGScrollEventUnit = .pixel,
    to panel: SquirrelPanel
  ) {
    guard let cgEvent = CGEvent(
      scrollWheelEvent2Source: nil,
      units: units,
      wheelCount: 2,
      wheel1: deltaY,
      wheel2: 0,
      wheel3: 0)
    else {
      failures.append("candidate scroll fixture could not create a CGEvent")
      return
    }
    cgEvent.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
    guard let event = NSEvent(cgEvent: cgEvent) else {
      failures.append("candidate scroll fixture could not bridge an NSEvent")
      return
    }
    panel.sendEvent(event)
  }

  private static func requireEngineHighlight(
    _ expectedIndex: Int,
    in candidateView: SquirrelView,
    _ context: String
  ) {
    let candidateElements = (candidateView.accessibilityChildren() ?? []).compactMap {
      $0 as? NSAccessibilityElement
    }
    let selectedElements = (candidateView.accessibilitySelectedChildren() ?? []).compactMap {
      $0 as? NSAccessibilityElement
    }
    require(
      candidateView.hilightedIndex == expectedIndex,
      "\(context): visual index was \(candidateView.hilightedIndex)")
    require(
      candidateElements.indices.contains(expectedIndex) &&
        selectedElements.count == 1 &&
        selectedElements[0] === candidateElements[expectedIndex],
      "\(context): accessibility selection diverged from candidate \(expectedIndex)")
  }

  private static func requirePointerFeedback(
    in candidateView: SquirrelView,
    candidateIndex: Int,
    expectedAlpha: CGFloat,
    context: String
  ) {
    guard candidateView.candidateInteractionFrames.indices.contains(candidateIndex),
      let panelLayer = candidateView.layer?.sublayers?.first as? CAShapeLayer,
      let feedbackLayer = panelLayer.sublayers?.first(where: {
        $0.name == LinnetCandidatePointerPresentation.feedbackLayerName
      }) as? CAShapeLayer,
      let path = feedbackLayer.path,
      let alpha = feedbackLayer.fillColor?.alpha
    else {
      failures.append("\(context) did not render its visual feedback layer")
      return
    }
    var transform = panelLayer.affineTransform()
    let visualFrame = path.copy(using: &transform)?.boundingBox ?? .zero
    require(
      approximatelyEqual(
        visualFrame,
        candidateView.candidateInteractionFrames[candidateIndex],
        tolerance: 0.5),
      "\(context) feedback did not cover candidate \(candidateIndex)")
    require(
      abs(alpha - expectedAlpha) < 0.001,
      "\(context) feedback alpha was \(alpha), expected \(expectedAlpha)")
  }

  private static func requireControlFeedback(
    in candidateView: SquirrelView,
    expectedAlpha: CGFloat,
    context: String
  ) {
    guard let feedbackLayer = candidateView.layer?.sublayers?.first(where: {
      $0.name == SquirrelView.controlPointerFeedbackLayerName
    }) as? CAShapeLayer,
      let alpha = feedbackLayer.fillColor?.alpha
    else {
      failures.append("\(context): missing control feedback layer")
      return
    }
    require(
      abs(alpha - expectedAlpha) <= 0.01,
      "\(context): control feedback alpha was \(alpha)")
  }

  private static func requireNoPointerFeedback(
    in candidateView: SquirrelView,
    context: String
  ) {
    let feedbackLayer = (candidateView.layer?.sublayers?.first as? CAShapeLayer)?
      .sublayers?.first(where: {
        $0.name == LinnetCandidatePointerPresentation.feedbackLayerName
      })
    require(feedbackLayer == nil, "\(context) retained a visual feedback layer")
  }

  private static func testScreenLocalPanelPlacement() {
    let screens = [
      NSRect(x: 0, y: 0, width: 1_440, height: 900),
      NSRect(x: -1_280, y: 0, width: 1_280, height: 800),
      NSRect(x: 1_440, y: 200, width: 1_024, height: 768),
      NSRect(x: 0, y: -900, width: 1_440, height: 900),
    ]
    for screen in screens {
      let carets = [
        ("left", NSRect(x: screen.minX + 1, y: screen.midY, width: 2, height: 20)),
        ("right", NSRect(x: screen.maxX - 3, y: screen.midY, width: 2, height: 20)),
        ("bottom", NSRect(x: screen.midX, y: screen.minY + 1, width: 2, height: 20)),
        ("top", NSRect(x: screen.midX, y: screen.maxY - 21, width: 2, height: 20)),
      ]
      for point in [CGFloat(12), 16, 32] {
        for vertical in [false, true] {
          let metrics = LinnetPanelGeometry.presentationMetrics(
            role: .candidate,
            candidateFontPoint: point,
            candidateEdgeInset: LinnetCandidatePresentation.candidateWindowInset,
            candidatePaging: LinnetPanelGeometry.pagingConfiguration(
              showPaging: true,
              themeOffset: 15,
              canPageUp: true,
              canPageDown: true),
            candidateVertical: vertical,
            candidateCornerRadius: 10)
          let contentSize = vertical
            ? NSSize(width: point * 9, height: 220)
            : NSSize(width: min(680, screen.width * 0.72), height: point * 3)
          for (edge, caret) in carets {
            guard let frame = LinnetPanelGeometry.panelFrame(
              contentSize: contentSize,
              caret: caret,
              screen: screen,
              metrics: metrics,
              offsetHeight: SquirrelTheme.offsetHeight,
              verticalPreeditExtent: vertical ? point : 0)
            else {
              failures.append(
                "\(point)pt \(vertical ? "vertical" : "horizontal") \(edge) placement "
                  + "returned no frame on screen \(screen)")
              continue
            }
            let tolerance: CGFloat = 0.01
            require(
              frame.width > 0 && frame.height > 0 &&
                frame.minX >= screen.minX - tolerance &&
                frame.maxX <= screen.maxX + tolerance &&
                frame.minY >= screen.minY - tolerance &&
                frame.maxY <= screen.maxY + tolerance &&
                frame.width <= screen.width * 0.95 + tolerance &&
                frame.height <= screen.height * 0.95 + tolerance,
              "\(point)pt \(vertical ? "vertical" : "horizontal") \(edge) placement "
                + "escaped screen \(screen): \(frame)")
            if !vertical && edge == "bottom" {
              require(
                frame.minY >= caret.maxY,
                "\(point)pt bottom-edge panel did not flip above the caret")
            } else if !vertical && edge == "top" {
              require(
                frame.maxY <= caret.minY,
                "\(point)pt top-edge panel did not remain below the caret")
            }
          }
        }
      }
    }
  }

  private static func testDefaultNineCandidateNaturalSize() {
    guard let yaml = try? String(contentsOfFile: "data/squirrel.yaml", encoding: .utf8),
      let sample = parseThemeSamples(yaml)["linnet_paper_light"]
    else {
      failures.append("default natural-size fixture could not resolve Paper Light")
      return
    }

    let panel = SquirrelPanel(position: NSRect(x: 320, y: 420, width: 2, height: 20))
    let controller = SquirrelInputController()
    panel.bind(controller: controller)
    guard let candidateView = panel.contentView?.subviews.compactMap({
      $0 as? SquirrelView
    }).first else {
      failures.append("default natural-size fixture could not locate SquirrelView")
      return
    }

    let theme = candidateView.lightTheme
    let candidateFont = LinnetCandidatePresentation.platformFont(fontNames: [], size: 16)
    let labelFont = LinnetCandidatePresentation.platformFont(
      fontNames: [], size: 10, fallback: candidateFont)
    let labelBaseline = (candidateFont.pointSize - labelFont.pointSize) / 2.5
    theme.font = candidateFont
    theme.backgroundColor = sample.background
    theme.borderColor = sample.border
    theme.highlightedBackColor = sample.selectedBackground
    theme.cornerRadius = sample.cornerRadius
    theme.hilitedCornerRadius = sample.highlightedCornerRadius
    theme.selectionStyle = sample.selectionStyle
    theme.linear = true
    theme.showPaging = true
    theme.linespace = LinnetCandidatePresentation.candidateRowSpacing
    theme.candidateFormat = "[label] [candidate]"
    theme.attrs = [.font: candidateFont, .foregroundColor: sample.primary]
    theme.highlightedAttrs = [.font: candidateFont, .foregroundColor: sample.selectedPrimary]
    theme.labelAttrs = [
      .font: labelFont,
      .foregroundColor: sample.label,
      .baselineOffset: labelBaseline,
    ]
    theme.labelHighlightedAttrs = [
      .font: labelFont,
      .foregroundColor: sample.selectedLabel,
      .baselineOffset: labelBaseline,
    ]
    let firstParagraph = NSMutableParagraphStyle()
    firstParagraph.paragraphSpacing = theme.linespace / 2
    firstParagraph.paragraphSpacingBefore =
      LinnetCandidatePresentation.preeditSpacing / 2 + theme.linespace / 2
    theme.firstParagraphStyle = firstParagraph
    let paragraph = NSMutableParagraphStyle()
    paragraph.paragraphSpacing = theme.linespace / 2
    paragraph.paragraphSpacingBefore = theme.linespace / 2
    theme.paragraphStyle = paragraph

    let values = ["截图", "解", "接", "结", "姐", "节", "界", "届", "洁"]
    let candidates = SquirrelInputController.CandidateSnapshot(
      items: values.enumerated().map { index, value in
        .init(
          text: value, comment: "", page: 0, indexOnPage: index,
          absoluteIndex: index, selectionLabel: String(index + 1))
      },
      pageSize: values.count,
      currentPage: 0,
      isLastPage: false)
    _ = panel.update(
      preedit: "", selRange: .empty, caretPos: 0,
      candidates: candidates, highlighted: 0, update: true,
      controller: controller)
    panel.displayIfNeeded()
    render(candidateView)

    let contentRect = candidateView.contentRect
    let inset = LinnetCandidatePresentation.candidateWindowInset
    let paging = candidateView.pagingLayout
    let expectedSize = NSSize(
      width: contentRect.width + inset.width * 2 + paging.stripFrame.width,
      height: contentRect.height + inset.height * 2)
    let actualSize = panel.frame.size
    require(
      abs(actualSize.width - ceil(expectedSize.width)) <= 0.5,
      "default 16pt nine-candidate panel width \(actualSize.width) is not natural content width \(expectedSize.width)")
    require(
      abs(actualSize.height - ceil(expectedSize.height)) <= 0.5,
      "default 16pt nine-candidate panel height \(actualSize.height) is not compact content height \(expectedSize.height)")
    require(
      candidateView.textView.frame.width + 0.5 >= contentRect.width + inset.width * 2,
      "default 16pt nine-candidate text view clipped its natural content width")
    require(
      paging.previousPage == nil && paging.nextPage != nil,
      "first candidate page lost its next-page control")
    require(
      abs(paging.stripFrame.maxX - candidateView.bounds.maxX) <= 0.5,
      "first-page paging strip left the horizontal trailing edge")
    if let nextPage = paging.nextPage {
      require(
        candidateView.click(at: nextPage.visualCenter) == .control(.pageDown),
        "first-page paging control lost its paging hit target")
    }
    let stripBackgroundPoint = NSPoint(
      x: paging.stripFrame.midX,
      y: paging.stripFrame.minY + min(3, paging.stripFrame.height / 4))
    require(
      candidateView.shape.path?.contains(stripBackgroundPoint) == true,
      "first-page paging strip was left outside the panel background")
    let pagingGlyph = candidateView.layer?.sublayers?.last?.sublayers?.first
      as? CAShapeLayer
    require(
      pagingGlyph?.fillColor != theme.backgroundColor.cgColor,
      "first-page paging glyph disappeared into the panel background")

    let frames = candidateView.candidateAccessibilityGeometry().candidateFrames
    require(frames.count == values.count, "default 16pt row did not expose all nine candidate cells")
    if let last = frames.last {
      require(
        last.maxX <= candidateView.bounds.maxX + 0.5,
        "default 16pt ninth candidate was clipped at the trailing edge")
      require(
        candidateView.click(at: NSPoint(x: last.midX, y: last.midY)) == .candidate(8),
        "default 16pt ninth candidate lost its natural-width hit target")
    }

    let middlePage = SquirrelInputController.CandidateSnapshot(
      items: values.enumerated().map { index, value in
        .init(
          text: value, comment: "", page: 1, indexOnPage: index,
          absoluteIndex: values.count + index, selectionLabel: String(index + 1))
      },
      pageSize: values.count,
      currentPage: 1,
      isLastPage: false)
    _ = panel.update(
      preedit: "", selRange: .empty, caretPos: 0,
      candidates: middlePage, highlighted: 0, update: true,
      controller: controller)
    panel.displayIfNeeded()
    render(candidateView)

    let middlePaging = candidateView.pagingLayout
    let middleContentRect = candidateView.contentRect
    let middleNaturalHeight = ceil(middleContentRect.height + inset.height * 2)
    require(
      middlePaging.previousPage != nil && middlePaging.nextPage != nil,
      "middle-page fixture did not expose both paging controls")
    require(
      abs(panel.frame.height - middleNaturalHeight) <= 0.5,
      "switching to a middle page inflated the horizontal panel from natural height "
        + "\(middleNaturalHeight) to \(panel.frame.height)")
    let lastPage = SquirrelInputController.CandidateSnapshot(
      items: values.prefix(3).enumerated().map { index, value in
        .init(
          text: value, comment: "", page: 2, indexOnPage: index,
          absoluteIndex: values.count * 2 + index, selectionLabel: String(index + 1))
      },
      pageSize: values.count,
      currentPage: 2,
      isLastPage: true)
    _ = panel.update(
      preedit: "", selRange: .empty, caretPos: 0,
      candidates: lastPage, highlighted: 0, update: true,
      controller: controller)
    panel.displayIfNeeded()
    render(candidateView)
    let lastPaging = candidateView.pagingLayout
    let lastNaturalHeight = ceil(candidateView.contentRect.height + inset.height * 2)
    require(
      lastPaging.previousPage != nil && lastPaging.nextPage == nil,
      "last-page fixture did not retain only the previous-page control")
    require(
      abs(panel.frame.height - lastNaturalHeight) <= 0.5,
      "a partial last page retained stale paging height")
    require(
      candidateView.candidateAccessibilityGeometry().candidateFrames.count == 3,
      "a partial last page retained stale candidate geometry")

    _ = panel.update(
      preedit: "", selRange: .empty, caretPos: 0,
      candidates: candidates, highlighted: 0, update: true,
      controller: controller)
    panel.displayIfNeeded()
    render(candidateView)
    require(
      abs(panel.frame.height - actualSize.height) <= 0.5,
      "returning to the first page did not restore its natural height")
    print(
      "Default 16pt nine-candidate natural panel: "
        + "\(actualSize.width)×\(actualSize.height), content "
        + "\(contentRect.width)×\(contentRect.height)")
    panel.hide()
  }


  private static func testChineseCommentsDoNotCreateEnglishPlaceholder() {
    let panel = SquirrelPanel(position: NSRect(x: 260, y: 420, width: 2, height: 20))
    let controller = SquirrelInputController()
    panel.bind(controller: controller)
    let candidateView = panel.view
    let theme = candidateView.lightTheme
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.labelColor,
    ]
    theme.font = NSFont.systemFont(ofSize: 16)
    theme.linear = true
    theme.candidateFormat = "[label] [candidate]"
    theme.attrs = attributes
    theme.highlightedAttrs = attributes
    theme.labelAttrs = attributes
    theme.labelHighlightedAttrs = attributes
    theme.detailAttrs = attributes
    theme.firstParagraphStyle = NSMutableParagraphStyle()
    theme.paragraphStyle = NSMutableParagraphStyle()

    let snapshot = SquirrelInputController.CandidateSnapshot(
      items: ["是", "时", "事"].enumerated().map { index, value in
        .init(
          text: value, comment: index == 0 ? "［shì］" : "",
          page: index / 3, indexOnPage: index % 3, absoluteIndex: index,
          selectionLabel: index < 3 ? String(index + 1) : nil)
      },
      pageSize: 3, currentPage: 0, isLastPage: false)
    _ = panel.update(
      preedit: "ui", selRange: .empty, caretPos: 2,
      candidates: snapshot, highlighted: 1, update: true,
      controller: controller)
    panel.displayIfNeeded()
    candidateView.displayIfNeeded()
    require(
      candidateView.detailTextView.isHidden,
      "Chinese spelling comments gave another Chinese candidate the English placeholder")
    panel.hide()
  }


  private static func testThemeLayoutMatrix() {
    guard let yaml = try? String(contentsOfFile: "data/squirrel.yaml", encoding: .utf8)
    else {
      failures.append("theme layout matrix could not read canonical squirrel.yaml")
      return
    }
    let samples = parseThemeSamples(yaml)
    guard samples.count == 16 else {
      failures.append("theme layout matrix resolved \(samples.count) palettes instead of 16")
      return
    }
    let rawDetail = "/w/ · n. 工作；v. 运作；adj. 有效；fig. 起作用"
    let detail = LinnetCandidatePresentation.candidateComment(rawDetail).displayText
    let values = ["work", "works", "woke", "week", "wiki", "weak", "worse", "wise", "working"]

    let variants = samples.values.sorted(by: { $0.identifier < $1.identifier }).flatMap { sample in
      [SquirrelTheme.SelectionStyle.tile, .underline].flatMap { style in
        [true, false].map { rounded in appearanceSample(sample, style: style, rounded: rounded) }
      }
    }
    for sample in variants {
      let dark = sample.identifier.hasSuffix("_dark")
      for point in [CGFloat(12), 16, 32] {
        for linear in [true, false] {
          let context = "\(sample.identifier) \(sample.selectionStyle) radius=\(sample.cornerRadius) \(point)pt \(linear ? "horizontal" : "vertical")"
          let panel = SquirrelPanel(
            position: NSRect(x: 320, y: 420, width: 2, height: 20))
          let controller = SquirrelInputController()
          panel.bind(controller: controller)
          guard let candidateView = panel.contentView?.subviews.compactMap({
            $0 as? SquirrelView
          }).first else {
            failures.append("\(context) could not locate SquirrelView")
            panel.hide()
            continue
          }
          let theme = dark ? candidateView.darkTheme : candidateView.lightTheme
          configureThemeLayout(
            theme,
            sample: sample,
            point: point,
            linear: linear)
          panel.resolvedAppearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
          candidateView.applyClientAppearance(isDark: dark)
          require(
            candidateView.currentTheme === theme,
            "\(context) did not select the configured \(dark ? "dark" : "light") theme")

          let published = panel.update(
            preedit: "", selRange: .empty, caretPos: 0,
            candidates: SquirrelInputController.CandidateSnapshot(
              items: values.enumerated().map { index, value in
                .init(
                  text: value, comment: index == 0 ? rawDetail : "",
                  page: 0, indexOnPage: index, absoluteIndex: index,
                  selectionLabel: String(index + 1))
              },
              pageSize: values.count,
              currentPage: 0,
              isLastPage: true),
            highlighted: 0,
            update: true,
            controller: controller)
          panel.displayIfNeeded()
          render(candidateView)
          require(published, "\(context) did not publish")
          let tolerance: CGFloat = 1.01
          let candidateBounds = candidateView.bounds.insetBy(dx: -tolerance, dy: -tolerance)
          let candidateFrames = candidateView.candidateAccessibilityGeometry().candidateFrames
          require(
            candidateFrames.count == values.count && candidateFrames.allSatisfy {
              !$0.isEmpty && candidateBounds.contains($0)
            },
            "\(context) clipped candidate interaction geometry")
          require(candidateView.detailTextView.isHidden && candidateView.detailDividerView.isHidden,
            "\(context) reintroduced a selected-only detail surface")
          let text = candidateView.textView.textContentStorage?.attributedString
          require(text?.string.contains(detail) == true,
            "\(context) lost its inline bilingual annotation")
          if linear {
            let expectedWidth = ceil(
              candidateView.contentRect.width + theme.edgeInset.width * 2)
            require(
              abs(panel.frame.width - expectedWidth) <= tolerance,
              "\(context) unexpected candidate-owned panel width: "
                + "\(panel.frame.width) versus \(expectedWidth)")
          } else {
            let expectedHeight = ceil(
              candidateView.contentRect.height + theme.edgeInset.height * 2)
            require(
              abs(panel.frame.height - expectedHeight) <= tolerance,
              "\(context) unexpected candidate-owned panel height: "
                + "\(panel.frame.height) versus \(expectedHeight)")
          }
          panel.hide()
        }
      }
    }
  }

  private static func configureThemeLayout(
    _ theme: SquirrelTheme,
    sample: ThemeSample,
    point: CGFloat,
    linear: Bool
  ) {
    let candidateFont = LinnetCandidatePresentation.platformFont(fontNames: [], size: point)
    let labelFont = LinnetCandidatePresentation.platformFont(
      fontNames: [], size: max(10, point - 6), fallback: candidateFont)
    let detailFont = LinnetCandidatePresentation.platformFont(
      fontNames: [], size: max(10, point - 4), fallback: candidateFont)
    theme.available = true
    theme.font = candidateFont
    theme.backgroundColor = sample.background
    theme.borderColor = sample.border
    theme.highlightedBackColor = sample.selectedBackground
    theme.cornerRadius = sample.cornerRadius
    theme.hilitedCornerRadius = sample.highlightedCornerRadius
    theme.mutualExclusive = sample.mutuallyExclusive
    theme.translucency = sample.isTranslucent
    theme.selectionStyle = sample.selectionStyle
    theme.linear = linear
    theme.vertical = false
    theme.showPaging = false
    theme.linespace = LinnetCandidatePresentation.candidateRowSpacing
    theme.edgeInset = LinnetCandidatePresentation.candidateWindowInset
    theme.candidateFormat = "[label] [candidate]"
    theme.attrs = [.font: candidateFont, .foregroundColor: sample.primary]
    theme.highlightedAttrs = [
      .font: candidateFont, .foregroundColor: sample.selectedPrimary,
    ]
    theme.labelAttrs = [.font: labelFont, .foregroundColor: sample.label]
    theme.labelHighlightedAttrs = [
      .font: labelFont, .foregroundColor: sample.selectedLabel,
    ]
    theme.commentAttrs = [.font: detailFont, .foregroundColor: sample.primary]
    theme.commentHighlightedAttrs = [
      .font: detailFont, .foregroundColor: sample.selectedPrimary,
    ]
    theme.detailAttrs = [.font: detailFont, .foregroundColor: sample.primary]
    let firstParagraph = NSMutableParagraphStyle()
    firstParagraph.paragraphSpacing = theme.linespace / 2
    firstParagraph.paragraphSpacingBefore =
      LinnetCandidatePresentation.preeditSpacing / 2 + theme.linespace / 2
    theme.firstParagraphStyle = firstParagraph
    let paragraph = NSMutableParagraphStyle()
    paragraph.paragraphSpacing = theme.linespace / 2
    paragraph.paragraphSpacingBefore = theme.linespace / 2
    theme.paragraphStyle = paragraph
  }

  private static func testCandidateCellGeometry(
    fontPoint: CGFloat,
    linear: Bool,
    style: SquirrelTheme.SelectionStyle
  ) {
    let bounds = NSRect(
      x: 0, y: 0, width: 360,
      height: linear ? fontPoint + 32 : (fontPoint + 20) * 2)
    let view = SquirrelView(frame: bounds)
    view.lightTheme.linear = linear
    view.lightTheme.selectionStyle = style
    view.lightTheme.linespace = LinnetCandidatePresentation.candidateRowSpacing
    view.separatorWidth = linear
      ? LinnetCandidatePresentation.inlineCandidateSeparatorWidth(
        font: NSFont.systemFont(ofSize: fontPoint))
      : 0
    let value = linear ? "1 输入  2 输入法" : "1 输入\n2 输入法"
    let paragraph = NSMutableParagraphStyle()
    if linear {
      paragraph.lineSpacing = LinnetCandidatePresentation.candidateRowSpacing
    } else {
      paragraph.paragraphSpacing = LinnetCandidatePresentation.candidateRowSpacing / 2
      paragraph.paragraphSpacingBefore = LinnetCandidatePresentation.candidateRowSpacing / 2
    }
    let text = NSMutableAttributedString(
      string: value,
      attributes: [
        .font: NSFont.systemFont(ofSize: fontPoint),
        .paragraphStyle: paragraph,
      ])
    let source = text.string as NSString
    let ranges = [source.range(of: "1 输入"), source.range(of: "2 输入法")]
    view.textView.textContentStorage?.attributedString = text
    view.textView.frame = bounds
    view.textView.textContainerInset = LinnetCandidatePresentation.candidateWindowInset
    view.textView.textContainer?.size = bounds.size
    view.textView.textLayoutManager?.ensureLayout(
      for: view.textView.textLayoutManager!.documentRange)
    view.applyPresentationMetrics(LinnetPanelGeometry.presentationMetrics(
      role: .candidate,
      candidateFontPoint: fontPoint,
      candidateEdgeInset: LinnetCandidatePresentation.candidateWindowInset,
      candidatePaging: .none,
      candidateVertical: false,
      candidateCornerRadius: 10))
    view.drawView(
      candidateRanges: ranges, detailRange: .empty,
      hilightedIndex: 0,
      preeditRange: .empty,
      highlightedPreeditRange: .empty,
      controlMode: .paging(canPageUp: false, canPageDown: false))
    render(view)

    guard let textRange = view.convert(range: ranges[0]) else {
      failures.append("\(fontPoint)pt \(style.rawValue) selection lost its TextKit range")
      return
    }
    var glyphRect = view.contentRect(range: textRange)
    glyphRect.origin.x += LinnetCandidatePresentation.candidateWindowInset.width
    glyphRect.origin.y += LinnetCandidatePresentation.candidateWindowInset.height
    guard let selectionBox = highlightedSelectionBox(in: view) else {
      failures.append("\(fontPoint)pt \(style.rawValue) selection path is missing")
      return
    }
    switch style {
    case .tile:
      let cellBox = view.candidateAccessibilityGeometry().candidateFrames.first
      require(
        cellBox.map { approximatelyEqual(selectionBox, $0) } == true,
        "\(fontPoint)pt tile selection diverged from the candidate cell path")
    case .underline:
      let expected = NSRect(
        x: glyphRect.minX,
        y: glyphRect.maxY + 1,
        width: glyphRect.width,
        height: 2)
      require(
        approximatelyEqual(selectionBox, expected),
        "\(fontPoint)pt underline selection geometry drifted: \(selectionBox) / \(expected)")
    case .bar:
      let insets = LinnetCandidatePresentation.candidateSelectionInsets(
        style: .bar,
        candidateFont: NSFont.systemFont(ofSize: fontPoint))
      let expected = NSRect(
        x: max(1, glyphRect.minX - insets.left),
        y: glyphRect.minY - insets.top,
        width: 3,
        height: glyphRect.height + insets.top + insets.bottom)
      require(
        approximatelyEqual(selectionBox, expected),
        "\(fontPoint)pt bar selection bypassed shared insets: \(selectionBox) / \(expected)")
    }

    let frames = view.candidateAccessibilityGeometry().candidateFrames
    require(frames.count == ranges.count, "AX candidate frame count changed at \(fontPoint)pt")
    guard frames.count == ranges.count else { return }
    let font = NSFont.systemFont(ofSize: fontPoint)
    let minimumRowHeight = NSLayoutManager().defaultLineHeight(for: font)
      + LinnetCandidatePresentation.candidateRowSpacing
    for (index, frame) in frames.enumerated() {
      require(
        frame.height + 0.5 >= minimumRowHeight,
        "\(fontPoint)pt \(linear ? "row" : "column") AX frame \(frame.height) is smaller than visible row \(minimumRowHeight)")
      for point in interiorSamples(frame) {
        require(
          view.click(at: point) == .candidate(index),
          "candidate \(index) frame \(frame) contains wrong hit at \(point), \(fontPoint)pt")
      }
    }
    require(
      !frames[0].intersects(frames[1]),
      "candidate interaction cells overlap: \(frames[0]) / \(frames[1])")
    require(frames.allSatisfy(bounds.contains), "candidate interaction cell escaped the panel")
  }

  private static func render(_ view: SquirrelView) {
    // NSTextViews are siblings of SquirrelView, not its children. Rendering
    // only SquirrelView tests the highlight but misses AppKit text auto-sizing.
    let panel = view.window as? SquirrelPanel
    let surface = panel?.contentView ?? view
    guard let representation = surface.bitmapImageRepForCachingDisplay(in: surface.bounds) else {
      failures.append("candidate view did not create a bitmap render target")
      return
    }
    surface.cacheDisplay(in: surface.bounds, to: representation)
    guard panel != nil else { return }
    let cells = view.candidateAccessibilityGeometry().candidateFrames
    let origin = view.textView.textContainerOrigin
    let detailFrame = view.convert(view.detailTextView.bounds, from: view.detailTextView)
    for (candidate, cell) in zip(view.candidateRanges, cells) {
      guard let range = view.convert(range: candidate) else {
        failures.append("rendered candidate has no text range")
        continue
      }
      let glyph = view.convert(
        view.contentRect(range: range).offsetBy(dx: origin.x, dy: origin.y),
        from: view.textView)
      require(cell.insetBy(dx: -0.5, dy: -0.5).contains(glyph.center),
        "rendered glyph escaped its candidate cell: glyph \(glyph), cell \(cell)")
      require(view.detailTextView.isHidden || !glyph.intersects(detailFrame),
        "rendered candidate overlaps its definition: glyph \(glyph), detail \(detailFrame)")
    }
  }

  private struct ThemeSample {
    let identifier: String
    let background: NSColor
    let border: NSColor
    let primary: NSColor
    let label: NSColor
    var selectedBackground: NSColor
    let selectionIndicator: NSColor
    var selectedPrimary: NSColor
    var selectedLabel: NSColor
    var cornerRadius: CGFloat
    var highlightedCornerRadius: CGFloat
    let mutuallyExclusive: Bool
    let isTranslucent: Bool
    var selectionStyle: SquirrelTheme.SelectionStyle
  }

  private static func appearanceSample(
    _ palette: ThemeSample, style: SquirrelTheme.SelectionStyle, rounded: Bool
  ) -> ThemeSample {
    var result = palette
    result.selectionStyle = style
    result.cornerRadius = rounded ? 8 : 0
    result.highlightedCornerRadius = rounded ? 5 : 0
    if style != .tile {
      result.selectedBackground = palette.selectionIndicator
      result.selectedPrimary = palette.primary
      result.selectedLabel = palette.label
    }
    return result
  }

  private static func makeReadmeProductGallery(
    yamlPath: String,
    inputModesOutputPath: String,
    bilingualOutputPath: String
  ) {
    guard let source = try? String(contentsOfFile: yamlPath, encoding: .utf8),
      let paper = parseThemeSamples(source)["linnet_paper_light"]
    else {
      failures.append("README product gallery could not resolve Paper Light")
      return
    }
    guard let chineseStatus = renderStatusNotice("中"),
      let englishStatus = renderStatusNotice("En"),
      let asciiStatus = renderStatusNotice("A")
    else {
      failures.append("README product gallery could not render input-mode notices")
      return
    }

    let modeSize = NSSize(width: 1360, height: 500)
    guard let (modeBitmap, modeContext) = bitmapSurface(
      size: modeSize, failure: "README input-mode image")
    else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = modeContext
    let ink = NSColor(srgbRed: 0.09, green: 0.10, blue: 0.10, alpha: 1)
    let secondary = NSColor(srgbRed: 0.36, green: 0.41, blue: 0.40, alpha: 1)
    let accent = NSColor(srgbRed: 0.27, green: 0.58, blue: 0.55, alpha: 1)
    NSColor(srgbRed: 0.985, green: 0.989, blue: 0.989, alpha: 1).setFill()
    NSRect(origin: .zero, size: modeSize).fill()
    ("Shift 切换后，状态在光标旁立即出现" as NSString).draw(
      at: NSPoint(x: 64, y: 422),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: 40, weight: .semibold),
        .foregroundColor: ink,
      ])
    ("以下三枚提示均由当前 SquirrelPanel / SquirrelView 真实渲染" as NSString).draw(
      at: NSPoint(x: 66, y: 382),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: 22),
        .foregroundColor: secondary,
      ])
    let columns: [(String, String, NSBitmapImageRep)] = [
      ("中文", "全拼 · 中文候选与英文译文", chineseStatus),
      ("Smart English", "补全 · 纠错 · IPA · 中文释义", englishStatus),
      ("原始 ASCII", "代码 · 密码 · 终端 · 原样输入", asciiStatus),
    ]
    for (index, column) in columns.enumerated() {
      let originX = CGFloat(66 + index * 430)
      let width = CGFloat(360)
      (column.0 as NSString).draw(
        at: NSPoint(x: originX, y: 285),
        withAttributes: [
          .font: NSFont.systemFont(ofSize: 30, weight: .semibold),
          .foregroundColor: ink,
        ])
      let noticeWidth = CGFloat(column.2.pixelsWide) * 2
      let noticeHeight = CGFloat(column.2.pixelsHigh) * 2
      drawBitmap(
        column.2,
        in: NSRect(
          x: originX + (width - noticeWidth) / 2,
          y: 178, width: noticeWidth, height: noticeHeight))
      (column.1 as NSString).draw(
        at: NSPoint(x: originX, y: 135),
        withAttributes: [
          .font: NSFont.systemFont(ofSize: 20),
          .foregroundColor: secondary,
        ])
      if index < columns.count - 1 {
        accent.withAlphaComponent(0.22).setFill()
        NSRect(x: originX + 394, y: 125, width: 2, height: 190).fill()
      }
    }
    ("轻按 Shift：中文 ↔ Smart English　·　Caps Lock：进入或退出 A" as NSString).draw(
      at: NSPoint(x: 64, y: 48),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: 22, weight: .medium),
        .foregroundColor: accent,
      ])
    NSGraphicsContext.restoreGraphicsState()
    writeReadmeBitmap(
      modeBitmap, outputPath: inputModesOutputPath, label: "README input-mode image")

    let reverseItems = [
      ("帅", "handsome; graceful"),
      ("摔", "fall; throw down"),
      ("甩", "fling; throw"),
    ]
    let englishItems = [
      ("cloud", "/klaʊd/ · n. 云；云端；云状物"),
      ("cloudy", "多云的；阴天的"),
      ("cloudless", "无云的；晴朗的"),
      ("cloudburst", "暴雨"),
    ]
    let reverseInput = "shuai"
    guard let reverse = renderProductCandidatePanel(
      sample: paper, preedit: reverseInput, items: reverseItems),
      let english = renderProductCandidatePanel(
        sample: paper, preedit: "cloud", items: englishItems)
    else {
      failures.append("README product gallery could not render bilingual candidates")
      return
    }
    let bilingualSize = NSSize(width: 1360, height: 660)
    guard let (bilingualBitmap, bilingualContext) = bitmapSurface(
      size: bilingualSize, failure: "README bilingual image")
    else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = bilingualContext
    NSColor(srgbRed: 0.985, green: 0.989, blue: 0.989, alpha: 1).setFill()
    NSRect(origin: .zero, size: bilingualSize).fill()
    ("双语能力，直接看真实候选窗" as NSString).draw(
      at: NSPoint(x: 64, y: 582),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: 40, weight: .semibold),
        .foregroundColor: ink,
      ])
    ("候选、选中态、释义和输入串均由当前产品渲染链生成" as NSString).draw(
      at: NSPoint(x: 66, y: 542),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: 22),
        .foregroundColor: secondary,
      ])
    let panels: [(String, String, NSBitmapImageRep)] = [
      ("01 · 每个中文候选都有英文释义", "输入 \(reverseInput)，译文默认不上屏", reverse),
      ("02 · Smart English", "补全、IPA、中文释义与原始输入", english),
    ]
    for (index, panel) in panels.enumerated() {
      let originX = CGFloat(64 + index * 660)
      (panel.0 as NSString).draw(
        at: NSPoint(x: originX, y: 468),
        withAttributes: [
          .font: NSFont.systemFont(ofSize: 25, weight: .semibold),
          .foregroundColor: accent,
        ])
      (panel.1 as NSString).draw(
        at: NSPoint(x: originX, y: 432),
        withAttributes: [
          .font: NSFont.systemFont(ofSize: 20),
          .foregroundColor: secondary,
        ])
      let availableWidth = CGFloat(590)
      let scale = min(1.55, availableWidth / CGFloat(panel.2.pixelsWide))
      let panelWidth = CGFloat(panel.2.pixelsWide) * scale
      let panelHeight = CGFloat(panel.2.pixelsHigh) * scale
      drawBitmap(
        panel.2,
        in: NSRect(
          x: originX + (availableWidth - panelWidth) / 2,
          y: 190, width: panelWidth, height: panelHeight))
    }
    ("真实产品渲染 · Paper Light · 20 pt" as NSString).draw(
      at: NSPoint(x: 64, y: 46),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: 20),
        .foregroundColor: secondary,
      ])
    NSGraphicsContext.restoreGraphicsState()
    writeReadmeBitmap(
      bilingualBitmap, outputPath: bilingualOutputPath, label: "README bilingual image")
  }

  private static func renderStatusNotice(_ label: String) -> NSBitmapImageRep? {
    let panel = SquirrelPanel(position: NSRect(x: 120, y: 120, width: 2, height: 20))
    let controller = SquirrelInputController()
    panel.bind(controller: controller)
    panel.updateStatus(
      long: label, short: label,
      controller: controller)
    _ = panel.update(
      preedit: "", selRange: .empty, caretPos: 0,
      candidates: .init(
        items: [], pageSize: 9, currentPage: 0, isLastPage: true),
      highlighted: 0, update: true,
      controller: controller)
    panel.displayIfNeeded()
    defer { panel.hide() }
    return bitmapSnapshot(of: panel.contentView)
  }

  private static func makeReadmeAppearanceGallery(yamlPath: String, outputPath: String) {
    guard let yaml = try? String(contentsOfFile: yamlPath, encoding: .utf8) else { return }
    let samples = parseThemeSamples(yaml)
    let size = NSSize(width: 1120, height: 900)
    guard let (bitmap, context) = bitmapSurface(size: size, failure: "appearance gallery") else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor(srgbRed: 0.96, green: 0.97, blue: 0.98, alpha: 1).setFill()
    NSRect(origin: .zero, size: size).fill()
    let ink = NSColor(srgbRed: 0.15, green: 0.18, blue: 0.22, alpha: 1)
    ("颜色、选中效果与窗口角形，分开设置" as NSString).draw(at: NSPoint(x: 48, y: 818),
      withAttributes: [.font: NSFont.systemFont(ofSize: 32, weight: .medium), .foregroundColor: ink])
    ("雾灰（原“原生玻璃”）· 常规字重 · 真实候选窗渲染" as NSString).draw(at: NSPoint(x: 49, y: 778),
      withAttributes: [.font: NSFont.systemFont(ofSize: 21), .foregroundColor: NSColor.darkGray])
    let variants: [(SquirrelTheme.SelectionStyle, Bool, String)] = [
      (.tile, true, "整行变色 · 圆角"), (.tile, false, "整行变色 · 直角"),
      (.underline, true, "下划线 · 圆角"), (.underline, false, "下划线 · 直角")
    ]
    for (index, variant) in variants.enumerated() {
      let x = CGFloat(50 + (index % 2) * 550)
      let top = CGFloat(700 - (index / 2) * 330)
      (variant.2 as NSString).draw(at: NSPoint(x: x, y: top),
        withAttributes: [.font: NSFont.systemFont(ofSize: 23, weight: .medium), .foregroundColor: ink])
      for (modeIndex, mode) in ["light", "dark"].enumerated() {
        guard let palette = samples["linnet_glass_\(mode)"],
          let panel = renderProductCandidatePanel(
            sample: appearanceSample(palette, style: variant.0, rounded: variant.1),
            preedit: "", items: [("你", "you (informal)"), ("你好", "hello; hi"), ("工作", "work; job")]) else {
          failures.append("appearance gallery failed to render")
          continue
        }
        let scale = min(1, 475 / CGFloat(panel.pixelsWide))
        let height = CGFloat(panel.pixelsHigh) * scale
        drawBitmap(panel, in: NSRect(x: x, y: top - 24 - CGFloat(modeIndex) * 135 - height,
          width: CGFloat(panel.pixelsWide) * scale, height: height))
      }
    }
    NSGraphicsContext.restoreGraphicsState()
    writeReadmeBitmap(bitmap, outputPath: outputPath, label: "README appearance gallery")
  }

  private static func makeReadmeRegionalGallery(yamlPath: String, outputPath: String) {
    guard let yaml = try? String(contentsOfFile: yamlPath, encoding: .utf8) else { return }
    let samples = parseThemeSamples(yaml)
    let size = NSSize(width: 1360, height: 760)
    guard let (bitmap, context) = bitmapSurface(size: size, failure: "regional glossary gallery") else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1).setFill()
    NSRect(origin: .zero, size: size).fill()
    let ink = NSColor(srgbRed: 0.12, green: 0.12, blue: 0.13, alpha: 1)
    ("词义与注释分层，保留简繁词条的归属" as NSString).draw(at: NSPoint(x: 52, y: 675),
      withAttributes: [.font: NSFont.systemFont(ofSize: 36, weight: .semibold), .foregroundColor: ink])
    ("澄蓝浅色 / 深色 · 当前候选窗渲染 · 20 pt" as NSString).draw(at: NSPoint(x: 54, y: 632),
      withAttributes: [.font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.darkGray])
    let lexicon = ZIMELocalLexicon(url: URL(fileURLWithPath: "resources/zime-cedict.sqlite3"))
    let variants = [
      ("linnet_macos_light", "简体：通用 + 大陆", ZIMELocalLexicon.RegionProfile.mainland),
      ("linnet_macos_dark", "繁体：通用 + 港澳台 / 新马", .traditionalRegions)
    ]
    for (index, variant) in variants.enumerated() {
      let x = CGFloat(54 + index * 660)
      let words = index == 0 ? ["你", "发", "帅"] : ["你", "妳", "髮"]
      let items = words.map { word in
        let annotation = lexicon.annotation(for: word, region: variant.2)
        return (word, LinnetCandidatePresentation.bilingualComment(displayText: annotation.displayText,
          translations: annotation.translations, detailText: annotation.detailText))
      }
      guard let sample = samples[variant.0], let panel = renderProductCandidatePanel(sample: sample,
        preedit: "", items: items) else {
        failures.append("regional gallery could not render \(variant.0)")
        continue
      }
      (variant.1 as NSString).draw(at: NSPoint(x: x, y: 560),
        withAttributes: [.font: NSFont.systemFont(ofSize: 25, weight: .medium), .foregroundColor: ink])
      let scale = min(1.2, 580 / CGFloat(panel.pixelsWide))
      let width = CGFloat(panel.pixelsWide) * scale
      let height = CGFloat(panel.pixelsHigh) * scale
      drawBitmap(panel, in: NSRect(x: x, y: 510 - height, width: width, height: height))
    }
    ("词条展示样例 · 相同译义合并 · 辨义限定保留 · 拼音引用和长说明在悬停详情中" as NSString)
      .draw(at: NSPoint(x: 54, y: 80), withAttributes: [.font: NSFont.systemFont(ofSize: 23), .foregroundColor: ink])
    NSGraphicsContext.restoreGraphicsState()
    writeReadmeBitmap(bitmap, outputPath: outputPath, label: "README regional glossary gallery")
  }

  private static func renderProductCandidatePanel(
    sample: ThemeSample,
    preedit: String,
    items: [(String, String)]
  ) -> NSBitmapImageRep? {
    let panel = SquirrelPanel(position: NSRect(x: 120, y: 120, width: 2, height: 20))
    let controller = SquirrelInputController()
    panel.bind(controller: controller)
    guard let candidateView = panel.contentView?.subviews.compactMap({
      $0 as? SquirrelView
    }).first else { return nil }
    let theme = candidateView.lightTheme
    let candidateFont = LinnetCandidatePresentation.platformFont(fontNames: [], size: 20)
    let labelFont = LinnetCandidatePresentation.platformFont(
      fontNames: [], size: 13, fallback: candidateFont)
    let detailFont = LinnetCandidatePresentation.platformFont(
      fontNames: [], size: 15, fallback: candidateFont)
    theme.font = candidateFont
    theme.backgroundColor = sample.background
    theme.borderColor = sample.border
    theme.highlightedBackColor = sample.selectedBackground
    theme.cornerRadius = sample.cornerRadius
    theme.hilitedCornerRadius = sample.highlightedCornerRadius
    theme.selectionStyle = sample.selectionStyle
    theme.linear = false
    theme.showPaging = false
    theme.linespace = LinnetCandidatePresentation.candidateRowSpacing
    theme.candidateFormat = "[label] [candidate]"
    theme.attrs = [.font: candidateFont, .foregroundColor: sample.primary]
    theme.highlightedAttrs = [
      .font: candidateFont, .foregroundColor: sample.selectedPrimary,
    ]
    theme.labelAttrs = [.font: labelFont, .foregroundColor: sample.label]
    theme.labelHighlightedAttrs = [
      .font: labelFont, .foregroundColor: sample.selectedLabel,
    ]
    theme.commentAttrs = [.font: detailFont, .foregroundColor: sample.primary]
    theme.commentHighlightedAttrs = [
      .font: detailFont, .foregroundColor: sample.selectedPrimary,
    ]
    theme.detailAttrs = [.font: detailFont, .foregroundColor: sample.primary]
    theme.preeditAttrs = [.font: candidateFont, .foregroundColor: sample.primary]
    theme.preeditHighlightedAttrs = theme.preeditAttrs
    let firstParagraph = NSMutableParagraphStyle()
    firstParagraph.paragraphSpacing = theme.linespace / 2
    firstParagraph.paragraphSpacingBefore =
      LinnetCandidatePresentation.preeditSpacing / 2 + theme.linespace / 2
    theme.firstParagraphStyle = firstParagraph
    let paragraph = NSMutableParagraphStyle()
    paragraph.paragraphSpacing = theme.linespace / 2
    paragraph.paragraphSpacingBefore = theme.linespace / 2
    theme.paragraphStyle = paragraph
    theme.preeditParagraphStyle = paragraph

    let snapshot = SquirrelInputController.CandidateSnapshot(
      items: items.enumerated().map { index, item in
        .init(
          text: item.0, comment: item.1, page: 0, indexOnPage: index,
          absoluteIndex: index, selectionLabel: String(index + 1))
      },
      pageSize: items.count,
      currentPage: 0,
      isLastPage: true)
    _ = panel.update(
      preedit: preedit,
      selRange: NSRange(location: 0, length: preedit.utf16.count),
      caretPos: preedit.utf16.count,
      candidates: snapshot,
      highlighted: 0,
      update: true,
      controller: controller)
    panel.displayIfNeeded()
    defer { panel.hide() }
    return bitmapSnapshot(of: panel.contentView)
  }

  private static func bitmapSurface(
    size: NSSize,
    failure: String
  ) -> (NSBitmapImageRep, NSGraphicsContext)? {
    guard let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: Int(size.width),
      pixelsHigh: Int(size.height),
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else {
      failures.append("\(failure) could not allocate a bitmap surface")
      return nil
    }
    return (bitmap, context)
  }

  private static func verifyReadmeRender(
    committedPath: String,
    generatedPath: String,
    label: String
  ) {
    guard let committedData = try? Data(contentsOf: URL(fileURLWithPath: committedPath)),
      let generatedData = try? Data(contentsOf: URL(fileURLWithPath: generatedPath)),
      let committed = NSBitmapImageRep(data: committedData),
      let generated = NSBitmapImageRep(data: generatedData)
    else {
      failures.append("\(label) could not be decoded for visual verification")
      return
    }
    guard committed.pixelsWide == generated.pixelsWide,
      committed.pixelsHigh == generated.pixelsHigh
    else {
      failures.append(
        "\(label) dimensions changed from \(committed.pixelsWide)x\(committed.pixelsHigh) "
          + "to \(generated.pixelsWide)x\(generated.pixelsHigh)")
      return
    }
    guard let committedSample = normalizedReadmeSample(committed),
      let generatedSample = normalizedReadmeSample(generated),
      let committedBytes = committedSample.bitmapData,
      let generatedBytes = generatedSample.bitmapData
    else {
      failures.append("\(label) could not allocate its normalized visual sample")
      return
    }
    let byteCount = committedSample.bytesPerRow * committedSample.pixelsHigh
    guard byteCount == generatedSample.bytesPerRow * generatedSample.pixelsHigh else {
      failures.append("\(label) normalized visual samples had different storage")
      return
    }
    var difference = 0
    for index in 0..<byteCount {
      difference += abs(Int(committedBytes[index]) - Int(generatedBytes[index]))
    }
    let normalizedDifference = Double(difference) / Double(byteCount * 255)
    print(String(format: "%@ visual distance: %.4f", label, normalizedDifference))
    require(
      normalizedDifference <= 0.015,
      String(
        format: "%@ visually diverged from the current product render (distance %.4f)",
        label, normalizedDifference))
  }

  private static func normalizedReadmeSample(
    _ source: NSBitmapImageRep
  ) -> NSBitmapImageRep? {
    let width = 170
    let height = max(1, Int((Double(source.pixelsHigh) / Double(source.pixelsWide) * 170).rounded()))
    guard let sample = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: width,
      pixelsHigh: height,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: width * 4,
      bitsPerPixel: 32),
      let context = NSGraphicsContext(bitmapImageRep: sample)
    else { return nil }
    let image = NSImage(size: NSSize(width: source.pixelsWide, height: source.pixelsHigh))
    image.addRepresentation(source)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    image.draw(
      in: NSRect(x: 0, y: 0, width: width, height: height),
      from: .zero,
      operation: .copy,
      fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return sample
  }

  private static func bitmapSnapshot(of view: NSView?) -> NSBitmapImageRep? {
    guard let view,
      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
    else { return nil }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    return bitmap
  }

  private static func drawBitmap(_ bitmap: NSBitmapImageRep, in rect: NSRect) {
    let image = NSImage(size: bitmap.size)
    image.addRepresentation(bitmap)
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
  }

  private static func writeReadmeBitmap(
    _ bitmap: NSBitmapImageRep,
    outputPath: String,
    label: String
  ) {
    guard let data = bitmap.representation(using: .png, properties: [:]),
      data.count > 10_000
    else {
      failures.append("\(label) render was empty")
      return
    }
    do {
      try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
      print("\(label): \(outputPath)")
    } catch {
      failures.append("\(label) could not be written: \(error)")
    }
  }

  private static func makeReadmeThemeGallery(yamlPath: String, outputPath: String) {
    guard let source = try? String(contentsOfFile: yamlPath, encoding: .utf8) else {
      failures.append("README theme gallery could not read canonical squirrel.yaml")
      return
    }
    let samples = parseThemeSamples(source)
    let families = [
      ("linnet_paper", "宣纸青黛", "Paper Ledger"),
      ("linnet_moon_jade", "月华玉青", "Moon Jade"),
      ("linnet_sidecar", "青岩", "Sidecar Slate"),
      ("linnet_clay", "陶印", "Clay Tiles"),
      ("linnet_mist_jade", "月白雾青", "Mist Jade"),
      ("linnet_glass", "雾灰", "Soft Gray"),
      ("linnet_ink_cinnabar", "夜墨朱砂", "Ink Cinnabar"),
      ("linnet_macos", "澄蓝", "Clear Blue"),
    ]
    guard samples.count == 16,
      families.allSatisfy({
        samples["\($0.0)_light"] != nil && samples["\($0.0)_dark"] != nil
      })
    else {
      failures.append("README theme gallery did not resolve all sixteen canonical palettes")
      return
    }

    let sheetSize = NSSize(width: 1360, height: 1100)
    guard let (sheet, context) = bitmapSurface(
      size: sheetSize, failure: "README theme gallery")
    else { return }

    let titleFont = NSFont.systemFont(ofSize: 40, weight: .semibold)
    let subtitleFont = NSFont.systemFont(ofSize: 22, weight: .regular)
    let headingFont = NSFont.systemFont(ofSize: 18, weight: .semibold)
    let familyFont = NSFont.systemFont(ofSize: 28, weight: .semibold)
    let detailFont = NSFont.systemFont(ofSize: 18, weight: .regular)
    let ink = NSColor(srgbRed: 0.09, green: 0.10, blue: 0.10, alpha: 1)
    let secondary = NSColor(srgbRed: 0.39, green: 0.44, blue: 0.43, alpha: 1)
    let accent = NSColor(srgbRed: 0.31, green: 0.61, blue: 0.58, alpha: 1)
    let separator = NSColor(srgbRed: 0.88, green: 0.91, blue: 0.90, alpha: 1)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor(srgbRed: 0.985, green: 0.989, blue: 0.989, alpha: 1).setFill()
    NSRect(origin: .zero, size: sheetSize).fill()
    ("八套候选窗主题 · 当前产品真实渲染" as NSString).draw(
      at: NSPoint(x: 50, y: 1020),
      withAttributes: [.font: titleFont, .foregroundColor: ink])
    ("由 data/squirrel.yaml 通过当前 SquirrelView 生成 · 20 pt · Light / Dark" as NSString)
      .draw(
        at: NSPoint(x: 52, y: 980),
        withAttributes: [.font: subtitleFont, .foregroundColor: secondary])

    for (index, family) in families.enumerated() {
      let column = index % 2
      let row = index / 2
      let cardX = CGFloat(50 + column * 655)
      let cardY = CGFloat(745 - row * 230)
      let card = NSRect(x: cardX, y: cardY, width: 630, height: 210)
      let cardPath = NSBezierPath(roundedRect: card, xRadius: 22, yRadius: 22)
      NSColor.white.withAlphaComponent(0.72).setFill()
      cardPath.fill()
      separator.setStroke()
      cardPath.lineWidth = 1
      cardPath.stroke()
      guard let light = samples["\(family.0)_light"],
        let dark = samples["\(family.0)_dark"],
        let lightCandidate = renderCandidate(sample: light, fontPoint: 20),
        let darkCandidate = renderCandidate(sample: dark, fontPoint: 20)
      else {
        failures.append("README theme gallery could not render \(family.0)")
        continue
      }

      (family.1 as NSString).draw(
        at: NSPoint(x: cardX + 24, y: cardY + 164),
        withAttributes: [.font: familyFont, .foregroundColor: ink])
      let treatment = switch light.selectionStyle {
      case .underline: "下划线"
      case .bar: "竖线"
      case .tile: "色块"
      }
      let material = light.isTranslucent ? " · 材质" : ""
      ("\(family.2) · \(treatment)\(material)" as NSString).draw(
        at: NSPoint(x: cardX + 24, y: cardY + 138),
        withAttributes: [.font: detailFont, .foregroundColor: secondary])
      let candidateScale = CGFloat(1.18)
      let candidateWidth = lightCandidate.size.width * candidateScale
      let candidateHeight = lightCandidate.size.height * candidateScale
      ("LIGHT" as NSString).draw(
        at: NSPoint(x: cardX + 24, y: cardY + 70),
        withAttributes: [.font: headingFont, .foregroundColor: accent])
      drawBitmap(
        lightCandidate,
        in: NSRect(
          x: cardX + 130, y: cardY + 58,
          width: candidateWidth, height: candidateHeight))
      ("DARK" as NSString).draw(
        at: NSPoint(x: cardX + 24, y: cardY + 14),
        withAttributes: [.font: headingFont, .foregroundColor: accent])
      drawBitmap(
        darkCandidate,
        in: NSRect(
          x: cardX + 130, y: cardY + 2,
          width: candidateWidth, height: candidateHeight))
    }

    ("主题只改变颜色；选中效果与窗口角形在设置中独立选择。" as NSString).draw(
      at: NSPoint(x: 52, y: 18),
      withAttributes: [.font: detailFont, .foregroundColor: secondary])
    NSGraphicsContext.restoreGraphicsState()
    writeReadmeBitmap(sheet, outputPath: outputPath, label: "README theme gallery")
  }

  private static func renderCandidate(
    sample: ThemeSample,
    fontPoint: CGFloat
  ) -> NSBitmapImageRep? {
    let frame = NSRect(x: 0, y: 0, width: 376, height: fontPoint + 26)
    let host = NSView(frame: frame)
    host.wantsLayer = true
    host.layer?.backgroundColor = (sample.identifier.hasSuffix("_dark")
      ? NSColor(calibratedWhite: 0.12, alpha: 1)
      : NSColor(calibratedWhite: 0.94, alpha: 1)).cgColor
    let material = NSVisualEffectView(frame: frame)
    if sample.isTranslucent {
      material.blendingMode = .behindWindow
      material.state = .active
      material.material = LinnetCandidatePresentation.candidateMaterial
      material.appearance = NSAppearance(
        named: sample.identifier.hasSuffix("_dark") ? .darkAqua : .aqua)
      material.wantsLayer = true
      host.addSubview(material)
    }
    let view = SquirrelView(frame: frame)
    let theme = view.lightTheme
    theme.backgroundColor = sample.background
    theme.borderColor = sample.border
    theme.cornerRadius = sample.cornerRadius
    theme.hilitedCornerRadius = sample.highlightedCornerRadius
    theme.highlightedBackColor = sample.selectedBackground
    theme.mutualExclusive = sample.mutuallyExclusive
    theme.translucency = sample.isTranslucent
    theme.selectionStyle = sample.selectionStyle
    theme.linear = true
    theme.linespace = LinnetCandidatePresentation.candidateRowSpacing
    let font = LinnetCandidatePresentation.platformFont(fontNames: [], size: fontPoint)
    let text = NSMutableAttributedString(
      string: "1 输入  2 interface",
      attributes: [.font: font, .foregroundColor: sample.primary])
    let source = text.string as NSString
    let ranges = [source.range(of: "1 输入"), source.range(of: "2 interface")]
    text.addAttribute(.foregroundColor, value: sample.selectedPrimary, range: ranges[0])
    view.textView.textContentStorage?.attributedString = text
    view.textView.frame = frame
    view.textView.textContainerInset = LinnetCandidatePresentation.candidateWindowInset
    view.textView.textContainer?.size = frame.size
    view.textView.textLayoutManager?.ensureLayout(
      for: view.textView.textLayoutManager!.documentRange)
    view.separatorWidth = LinnetCandidatePresentation.inlineCandidateSeparatorWidth(font: font)
    view.applyPresentationMetrics(LinnetPanelGeometry.presentationMetrics(
      role: .candidate,
      candidateFontPoint: fontPoint,
      candidateEdgeInset: LinnetCandidatePresentation.candidateWindowInset,
      candidatePaging: .none,
      candidateVertical: false,
      candidateCornerRadius: sample.cornerRadius))
    view.drawView(
      candidateRanges: ranges, detailRange: .empty,
      hilightedIndex: 0,
      preeditRange: .empty,
      highlightedPreeditRange: .empty,
      controlMode: .paging(canPageUp: false, canPageDown: false))
    if sample.isTranslucent {
      material.layer?.mask = view.shape
    }
    host.addSubview(view)
    host.addSubview(view.textView)
    guard let representation = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
      return nil
    }
    host.cacheDisplay(in: host.bounds, to: representation)
    return representation
  }

  private static func parseThemeSamples(_ source: String) -> [String: ThemeSample] {
    var result: [String: ThemeSample] = [:]
    var identifier: String?
    var fields: [String: String] = [:]
    func flush() {
      guard let identifier,
        let background = rimeColor(fields["back_color"]),
        let border = rimeColor(fields["border_color"]),
      let primary = rimeColor(fields["candidate_text_color"]),
        let label = rimeColor(fields["label_color"]),
        let selectedBackground = rimeColor(fields["hilited_candidate_back_color"]),
        let selectedPrimary = rimeColor(fields["hilited_candidate_text_color"]),
        let selectedLabel = rimeColor(fields["hilited_candidate_label_color"])
      else { return }
      result[identifier] = ThemeSample(
        identifier: identifier,
        background: background,
        border: border,
        primary: primary,
        label: label,
        selectedBackground: selectedBackground,
        selectionIndicator: rimeColor(fields["linnet_selection_indicator_color"]) ?? selectedBackground,
        selectedPrimary: selectedPrimary,
        selectedLabel: selectedLabel,
        cornerRadius: 8,
        highlightedCornerRadius: 5,
        mutuallyExclusive: false,
        isTranslucent: false,
        selectionStyle: .tile)
    }
    for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = String(rawLine.prefix { $0 != "#" })
      let indentation = line.prefix { $0 == " " }.count
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if indentation == 2, trimmed.hasSuffix(":"), !trimmed.contains(": ") {
        flush()
        let candidate = String(trimmed.dropLast())
        identifier = candidate.hasPrefix("linnet_") ? candidate : nil
        fields = [:]
      } else if identifier != nil, indentation == 4,
        let separator = trimmed.firstIndex(of: ":")
      {
        fields[String(trimmed[..<separator])] = String(
          trimmed[trimmed.index(after: separator)...])
          .trimmingCharacters(in: .whitespaces)
      }
    }
    flush()
    return result
  }

  private static func rimeColor(_ source: String?) -> NSColor? {
    guard let source,
      let value = UInt32(source.lowercased().replacingOccurrences(of: "0x", with: ""), radix: 16)
    else { return nil }
    let alpha = value > 0xFF_FF_FF ? CGFloat((value >> 24) & 0xFF) / 255 : 1
    let red = CGFloat(value & 0xFF) / 255
    let green = CGFloat((value >> 8) & 0xFF) / 255
    let blue = CGFloat((value >> 16) & 0xFF) / 255
    return NSColor(
      srgbRed: red, green: green, blue: blue, alpha: alpha)
  }

  private static func interiorSamples(_ frame: NSRect) -> [NSPoint] {
    let inset = frame.insetBy(dx: min(1, frame.width / 4), dy: min(1, frame.height / 4))
    return [
      NSPoint(x: inset.midX, y: inset.minY),
      NSPoint(x: inset.midX, y: inset.midY),
      NSPoint(x: inset.midX, y: inset.maxY),
    ]
  }

  private static func approximatelyEqual(
    _ lhs: NSRect,
    _ rhs: NSRect,
    tolerance: CGFloat = 0.01
  ) -> Bool {
    abs(lhs.minX - rhs.minX) <= tolerance &&
      abs(lhs.minY - rhs.minY) <= tolerance &&
      abs(lhs.width - rhs.width) <= tolerance &&
      abs(lhs.height - rhs.height) <= tolerance
  }

  private static func highlightedSelectionBox(in view: SquirrelView) -> NSRect? {
    guard let selectedColor = view.currentTheme.highlightedBackColor?.cgColor,
      let panelLayer = view.layer?.sublayers?.first as? CAShapeLayer,
      let selectionLayer = panelLayer.sublayers?.compactMap({ $0 as? CAShapeLayer })
        .last(where: { layer in
          layer.fillColor.map { CFEqual($0, selectedColor) } == true
        }),
      let path = selectionLayer.path
    else { return nil }
    return path.boundingBox
  }

  private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { failures.append(message) }
  }
}

private extension NSRect {
  var center: NSPoint { NSPoint(x: midX, y: midY) }
}
