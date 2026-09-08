import AppKit
import Foundation

@main
struct LinnetCandidatePresentationTests {
  static func testTranslationPaging() {
    typealias Owner = LinnetCandidatePresentation.TranslationCandidates
    let sources = (0..<9).map { index in
      Owner.Source(index: index, text: "source\(index)", translations: (0..<3).map { "\(index)-\($0)" })
    }
    for size in 3...9 {
      var owner = Owner()
      var page = owner.project(Array(sources.prefix(size)), pageSize: size, highlightedSource: 0)
      var seen = page.rows.map(\.text)
      require(page.rows.count == size && page.highlightedIndex == 0, "translated page ignored configured count")
      require(!owner.changePage(backward: true), "first page moved backward")
      while owner.changePage(backward: false) {
        page = owner.project(Array(sources.prefix(size)), pageSize: size, highlightedSource: 0)
        require(page.rows.count <= size, "translated page overflow")
        seen += page.rows.map(\.text)
      }
      require(seen.count == size * 3 && Set(seen).count == size * 3 && page.isLast,
        "translation pagination dropped or duplicated later source words")
      owner.reset()
      page = owner.project(Array(sources.prefix(size)), pageSize: size, highlightedSource: size - 1)
      require(page.rows[page.highlightedIndex].sourceIndex == size - 1,
        "switching translation lost the highlighted source")
      let selected = page.rows[page.highlightedIndex].id
      page = owner.project(sources, pageSize: size, highlightedSource: 0)
      require(page.rows[page.highlightedIndex].id == selected, "annotation refresh moved selection")
    }
    require(Owner.selectionIndex(digit: 2, count: 1) == nil, "hidden source selection returned")
    require(Owner.selectionIndex(digit: 1, count: 1) == 0, "visible translation is not selectable")
    var empty = Owner()
    require(empty.project([], pageSize: 5, highlightedSource: nil).rows.isEmpty &&
      !empty.changePage(backward: false), "empty translation menu manufactured a candidate")
  }

  static func main() {
    require(ZIMEReleasePolicy.usesManualReleases(bundleIdentifier: "com.zime.inputmethod.ZIME") &&
      ZIMEReleasePolicy.usesManualReleases(bundleIdentifier: "com.zime.inputmethod.ZIME.local-build") &&
      !ZIMEReleasePolicy.usesManualReleases(bundleIdentifier: "org.rime.inputmethod.Squirrel"),
      "ZIME must not inherit upstream update catalogs")
    testTranslationPaging()
    testCandidateRows()
    testNavigationLayout()

    require(
      LinnetCandidatePresentation.candidateWindowInset == CGSize(width: 7, height: 6) &&
        LinnetCandidatePresentation.candidateRowSpacing == 6 &&
        LinnetCandidatePresentation.preeditSpacing == 8,
      "candidate-window typography and spacing lost their shared compact metrics"
    )
    require(
      LinnetCandidatePresentation.windowInset(verticalText: false)
        == CGSize(width: 7, height: 6) &&
        LinnetCandidatePresentation.windowInset(verticalText: true)
        == CGSize(width: 6, height: 7),
      "vertical text did not rotate the one shared candidate-window inset"
    )
    testCanonicalTypography()
    testCandidateLineTypographyOwner()
    testCanonicalInlineMetricsAndMaterial()
    testCandidateDetailGeometry()
    testInputModeTransitions()
    testIdleMenuPresentationState()
    testHighlightedCandidateBounds()
    testCandidateSelectionLabels()
    let annotation = LinnetCandidatePresentation.bilingualComment(displayText: "you",
      translations: ["you"],
      detailText: "你 [ni3]\nFull note with \"quotes\" and \u{001F} delimiter")
    require(LinnetCandidatePresentation.candidateComment(annotation).displayText == "you", "structured comment lost display text")
    require(LinnetCandidatePresentation.candidateComment(annotation).translations == ["you"], "full annotations leaked into translation commits")
    require(LinnetCandidatePresentation.fullCandidateComment(annotation) == "你 [ni3]\nFull note with \"quotes\" and \u{001F} delimiter", "structured detail was not lossless")
    let legacy = "\u{001C}" + #"{"displayText":"you","translations":["you"],"detailText":"legacy note"}"#
    require(LinnetCandidatePresentation.candidateComment(legacy).translations == ["you"]
      && LinnetCandidatePresentation.candidateComment(legacy).sourceLabel == nil,
      "adding source metadata broke older/local annotations")
    let onlineText = "  you (informal) / yourself\nsecond line  "
    let online = LinnetCandidatePresentation.bilingualComment(displayText: "腾讯:\(onlineText)",
      translations: [onlineText], detailText: "", sourceLabel: "腾讯")
    let decodedOnline = LinnetCandidatePresentation.candidateComment(online)
    require(decodedOnline.sourceLabel == "腾讯" && decodedOnline.translations == [onlineText]
      && decodedOnline.displayText == "腾讯:\(onlineText)", "online annotation lost its source or complete field")
    var onlineOwner = LinnetCandidatePresentation.TranslationCandidates()
    let onlinePage = onlineOwner.project([.init(index: 3, text: "你", translations: [onlineText], sourceLabel: "腾讯")],
      pageSize: 5, highlightedSource: 3)
    require(onlinePage.rows.count == 1 && onlinePage.rows[0].sourceIndex == 3
      && onlinePage.rows[0].sourceLabel == "腾讯" && onlinePage.rows[0].text == onlineText,
      "translation paging split an online field or mixed a source label into the commit")
    for malformed in ["\u{001C}not JSON", "\u{001C}{}", "\u{001C}" + String(repeating: "x", count: 140000)] {
      require(LinnetCandidatePresentation.candidateComment(malformed).displayText.isEmpty &&
        LinnetCandidatePresentation.fullCandidateComment(malformed).isEmpty, "malformed comment leaked internal payload into UI")
    }

    var accessibilitySurface =
      LinnetCandidatePresentation.AccessibilitySurface.candidates
    require(
      accessibilitySurface.exposesCandidateList &&
        accessibilitySurface.localizedLabelKey == "Candidate window",
      "candidate publication lost its list accessibility container"
    )
    accessibilitySurface = .inputModeStatus
    require(
      !accessibilitySurface.exposesCandidateList &&
        accessibilitySurface.localizedLabelKey == "Input mode",
      "status publication retained the candidate-list accessibility container"
    )
    accessibilitySurface = .candidates
    require(
      accessibilitySurface.exposesCandidateList &&
        accessibilitySurface.localizedLabelKey == "Candidate window",
      "candidate publication did not restore its accessibility container"
    )

    require(
      LinnetCandidatePresentation.usesInlineComments(
        candidateFormat: "[label]. [candidate] [comment]"),
      "the standard Squirrel inline-comment format was not preserved"
    )
    require(
      !LinnetCandidatePresentation.usesInlineComments(
        candidateFormat: "[label] [candidate]"),
      "a Linnet selected-detail format was mistaken for inline comments"
    )
    require(
      LinnetCandidatePresentation.selectedDetailText("  short definition  ") == "short definition",
      "short detail was not normalized"
    )
    require(
      LinnetCandidatePresentation.selectedDetailText(
        "/wɜːk/ · n. 工作；职业；v. 运行；奏效；adj. 工作的"
      ) == "/wɜːk/ · n. 工作；职业\nv. 运行；奏效\nadj. 工作的",
      "selected English detail did not start each part of speech on its own line"
    )
    require(
      LinnetCandidatePresentation.selectedDetailText(
        "n. 品牌；name. 林内特；v. 命名；adj. 专有的"
      ) == "n. 品牌\nname. 林内特\nv. 命名\nadj. 专有的",
      "name, verb, and adjective detail groups did not receive separate lines"
    )
    require(
      LinnetCandidatePresentation.selectedDetailText(
        "n. 光；lit. 字面义；fig. 比喻义"
      ) == "n. 光\nlit. 字面义\nfig. 比喻义",
      "literal and figurative definition groups did not receive separate lines"
    )
    let long = String(repeating: "释", count: 300)
    let bounded = LinnetCandidatePresentation.selectedDetailText(long)
    require(
      LinnetCandidatePresentation.maximumDetailCharacterCount == 256 &&
        bounded.count == LinnetCandidatePresentation.maximumDetailCharacterCount,
      "detail was still truncated at the former 72-character display budget"
    )
    require(bounded.last == "…", "safety-bounded detail has no ellipsis")

    require(
      LinnetCandidatePresentation.candidateComment("［shì］")
        == .init(displayText: "［shì］", belongsToSmartEnglish: false),
      "ordinary Chinese spelling comments were classified as English details"
    )
    require(
      LinnetCandidatePresentation.candidateComment("\u{001D}n. 工作")
        == .init(
          displayText: "n. 工作", belongsToSmartEnglish: true,
          translations: ["工作"]),
      "the Smart English detail marker was not removed at the presentation boundary"
    )
    require(
      LinnetCandidatePresentation.candidateComment(
        "\u{001E}work\u{001F}job\u{001F}labour\u{001F}overflow")
        == .init(
          displayText: "work / job", belongsToSmartEnglish: false,
          translations: ["work", "job", "labour"]),
      "the reverse bilingual marker did not preserve bounded English alternatives"
    )
    require(
      LinnetCandidatePresentation.candidateComment(
        "\u{001D}/wɜːk/ · n. 工作；职业；v. 运行").translations
        == ["工作", "职业", "运行"],
      "English definitions did not expose bounded Chinese commit alternatives"
    )

    require(
      LinnetCandidatePresentation.accessibilityAnnouncement(
        candidate: "interface", comment: "  n. 接口  ", page: 2, indexOnPage: 1
      ) == "Page 3, candidate 2, interface, n. 接口",
      "candidate accessibility announcement lost position or definition"
    )
    require(
      LinnetCandidatePresentation.accessibilityAnnouncement(
        candidate: "work", comment: "n. 工作；v. 运行", page: 0, indexOnPage: 0
      ) == "Page 1, candidate 1, work, n. 工作, v. 运行",
      "visual part-of-speech line breaks leaked into accessibility speech"
    )
    require(
      LinnetCandidatePresentation.accessibilityAnnouncement(
        candidate: "候选", comment: "", page: 0, indexOnPage: 0
      ) == "Page 1, candidate 1, 候选",
      "empty candidate comment produced accessibility noise"
    )
    require(
      LinnetCandidatePresentation.accessibilityAnnouncement(
        candidate: "candidate", comment: "definition", page: -1, indexOnPage: 0
      ) == nil,
      "invalid highlighted candidate was announced"
    )

    print("LinnetCandidatePresentationTests: PASS")
  }

  private static func testCandidateSelectionLabels() {
    for (index, expected) in ["1", "2", "3", "4", "5", "6", "7", "8", "9"].enumerated() {
      require(
        LinnetCandidatePresentation.candidateSelectionLabel(
          at: index, labels: ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
        ) == expected,
        "Rime's 1-9 candidate labels were not preserved"
      )
    }
    require(
      LinnetCandidatePresentation.candidateSelectionLabel(at: 1, labels: ["asdf"]) == "s",
      "single-string custom selection labels were not preserved"
    )
    require(
      LinnetCandidatePresentation.candidateSelectionLabel(at: 2, labels: []) == "3",
      "missing custom labels did not use the visible one-based candidate index"
    )
  }

  private static func testInputModeTransitions() {
    typealias Identity = LinnetCandidatePresentation.InputModeIdentity
    let pinyin = Identity(schemaID: "linnet_zh_pinyin", asciiMode: false)
    let flypy = Identity(schemaID: "linnet_zh_flypy", asciiMode: false)
    let english = Identity(schemaID: "linnet_en", asciiMode: false)
    let pinyinASCII = Identity(schemaID: "linnet_zh_pinyin", asciiMode: true)
    let flypyASCII = Identity(schemaID: "linnet_zh_flypy", asciiMode: true)
    let englishASCII = Identity(schemaID: "linnet_en", asciiMode: true)

    require(
      LinnetCandidatePresentation.inputModeTransitionLabel(
        previous: nil, current: pinyin) == nil,
      "initial activation was mistaken for a user mode switch"
    )
    require(
      LinnetCandidatePresentation.inputModeTransitionLabel(
        previous: nil, current: pinyinASCII) == nil,
      "initial ASCII-mode sampling emitted a false switch notice"
    )

    for transition in [
      (pinyin, pinyinASCII),
      (english, englishASCII),
      (english, pinyinASCII),
      (pinyinASCII, flypyASCII),
    ] {
      require(
        LinnetCandidatePresentation.inputModeTransitionLabel(
          previous: transition.0, current: transition.1) == "A",
        "a transition into ASCII mode lost its compact caret label"
      )
    }

    require(
      LinnetCandidatePresentation.inputModeTransitionLabel(
        previous: pinyin, current: english) == "En",
      "Chinese to Smart English lost its compact caret label"
    )
    require(
      LinnetCandidatePresentation.inputModeTransitionLabel(
        previous: english, current: flypy) == "中",
      "Smart English to Chinese lost its compact caret label"
    )
    require(
      LinnetCandidatePresentation.inputModeTransitionLabel(
        previous: pinyinASCII, current: english) == "En",
      "leaving ASCII mode for Smart English lost its compact caret label"
    )
    require(
      LinnetCandidatePresentation.inputModeTransitionLabel(
        previous: englishASCII, current: english) == "En",
      "leaving same-schema ASCII mode for Smart English lost its compact caret label"
    )
    require(
      LinnetCandidatePresentation.inputModeTransitionLabel(
        previous: englishASCII, current: flypy) == "中",
      "leaving ASCII mode for Chinese lost its compact caret label"
    )
    require(
      LinnetCandidatePresentation.inputModeTransitionLabel(
        previous: pinyinASCII, current: pinyin) == "中",
      "leaving same-schema ASCII mode for Chinese lost its compact caret label"
    )
    require(
      LinnetCandidatePresentation.inputModeTransitionLabel(
        previous: pinyin, current: flypy) == nil,
      "changing Chinese profiles was mistaken for a Shift language switch"
    )
    require(
      LinnetCandidatePresentation.inputModeTransitionLabel(
        previous: english, current: english) == nil,
      "an unchanged Smart English schema emitted duplicate feedback"
    )
    require(
      LinnetCandidatePresentation.inputModeTransitionLabel(
        previous: pinyinASCII, current: pinyinASCII) == nil,
      "an unchanged ASCII identity emitted duplicate feedback"
    )
  }

  private static func testIdleMenuPresentationState() {
    require(
      LinnetCandidatePresentation.candidateMenuPage(
        currentPage: 0, pageSize: 0, candidateCount: 0, highlighted: 0
      ) == .init(currentPage: 0, pageSize: 0, candidateCount: 0, highlighted: 0),
      "an idle schema switch was rejected because it has no candidate menu"
    )
    require(
      LinnetCandidatePresentation.candidateMenuPage(
        currentPage: 0, pageSize: 9, candidateCount: 0, highlighted: 0
      ) == .init(currentPage: 0, pageSize: 9, candidateCount: 0, highlighted: 0),
      "a valid empty candidate page was rejected"
    )
    require(
      LinnetCandidatePresentation.candidateMenuPage(
        currentPage: 1, pageSize: 0, candidateCount: 0, highlighted: 0
      ) == nil,
      "an inconsistent zero-sized candidate page was accepted"
    )
  }

  private static func testHighlightedCandidateBounds() {
    require(
      LinnetCandidatePresentation.candidateMenuPage(
        currentPage: 0, pageSize: 9, candidateCount: 2, highlighted: 1
      ) == .init(currentPage: 0, pageSize: 9, candidateCount: 2, highlighted: 1),
      "the last valid highlighted candidate was rejected"
    )
    require(
      LinnetCandidatePresentation.candidateMenuPage(
        currentPage: 0, pageSize: 9, candidateCount: 2, highlighted: 2
      ) == nil,
      "a nonempty candidate page accepted an out-of-bounds highlight"
    )
    require(
      LinnetCandidatePresentation.candidateMenuPage(
        currentPage: 0, pageSize: 9, candidateCount: 0, highlighted: 1
      ) == nil,
      "an empty candidate page accepted a nonzero highlight"
    )
  }

  private static func testCanonicalTypography() {
    for point in [CGFloat(12), 16, 32] {
      let system = LinnetCandidatePresentation.platformFont(fontNames: [], size: point)
      require(
        system.fontName == NSFont.systemFont(ofSize: point).fontName &&
          system.pointSize == point,
        "the default candidate font is not the macOS system font")
      let cascade = LinnetCandidatePresentation.platformFont(
        fontNames: ["Avenir Next", "Hiragino Sans GB"], size: point)
      require(cascade.pointSize == point, "candidate font scaling changed")
      let descriptors = cascade.fontDescriptor.fontAttributes[.cascadeList]
        as? [NSFontDescriptor]
      require(
        cascade.familyName == "Avenir Next" &&
          descriptors?.first?.object(forKey: .family) as? String == "Hiragino Sans GB",
        "the bilingual candidate font cascade changed")
    }
    require(
      LinnetCandidatePresentation.platformFont(
        fontNames: ["Avenir Next-Demi Bold"], size: 16).familyName == "Avenir Next",
      "legacy family-face candidate font names stopped resolving")
  }

  private static func testCandidateLineTypographyOwner() {
    let primaryFont = NSFont.systemFont(ofSize: 16)
    let secondaryFont = NSFont.systemFont(ofSize: 10)
    let baseline = LinnetCandidatePresentation.secondaryBaselineOffset(
      primaryFont: primaryFont,
      secondaryFont: secondaryFont,
      baseOffset: 1,
      verticalText: false,
      placement: .inline)
    require(abs(baseline - 3.4) < 0.0001,
            "secondary candidate typography lost the live baseline formula")
    require(
      LinnetCandidatePresentation.secondaryBaselineOffset(
        primaryFont: primaryFont,
        secondaryFont: secondaryFont,
        baseOffset: 1,
        verticalText: true,
        placement: .inline) == 1,
      "vertical candidate typography retained a horizontal baseline correction")
    require(
      LinnetCandidatePresentation.secondaryBaselineOffset(
        primaryFont: primaryFont,
        secondaryFont: secondaryFont,
        baseOffset: 1,
        verticalText: false,
        placement: .standaloneDetail) == 1,
      "standalone candidate detail inherited the inline optical baseline correction")

    let candidateAttributes: [NSAttributedString.Key: Any] = [
      .font: primaryFont,
      .foregroundColor: NSColor.labelColor,
      .baselineOffset: 1,
    ]
    let labelAttributes: [NSAttributedString.Key: Any] = [
      .font: secondaryFont,
      .foregroundColor: NSColor.secondaryLabelColor,
      .baselineOffset: baseline,
    ]
    let commentAttributes: [NSAttributedString.Key: Any] = [
      .font: secondaryFont,
      .foregroundColor: NSColor.tertiaryLabelColor,
      .baselineOffset: baseline,
    ]
    let line = LinnetCandidatePresentation.candidateLine(
      candidateFormat: "‹[label]› [candidate] / [comment]",
      label: "1",
      candidate: "输入",
      comment: "名词",
      candidateAttributes: candidateAttributes,
      labelAttributes: labelAttributes,
      commentAttributes: commentAttributes)
    require(line.attributedString.string == "‹1› 输入 / 名词",
            "candidate placeholders no longer preserve arbitrary surrounding format")
    require(line.labelPrefix.string == "‹1› ",
            "stacked candidates lost their attributed label-prefix measurement")

    let rendered = line.attributedString.string as NSString
    let labelIndex = rendered.range(of: "1").location
    let candidateRange = rendered.range(of: "输入")
    let commentIndex = rendered.range(of: "名词").location
    require(
      (line.attributedString.attribute(.font, at: labelIndex, effectiveRange: nil)
        as? NSFont)?.pointSize == 10,
      "candidate label replacement lost its secondary font attributes")
    require(
      (line.attributedString.attribute(.font, at: candidateRange.location, effectiveRange: nil)
        as? NSFont)?.pointSize == 16,
      "candidate replacement lost its primary font attributes")
    require(
      (line.attributedString.attribute(.font, at: commentIndex, effectiveRange: nil)
        as? NSFont)?.pointSize == 10,
      "candidate comment replacement lost its secondary font attributes")
    require(
      line.attributedString.attribute(
        NSAttributedString.Key("noBreak"),
        at: candidateRange.location + 1,
        effectiveRange: nil) as? Bool == true,
      "short candidate replacement lost the live no-break contract")

    let detailFont = NSFont.systemFont(ofSize: 12)
    let detailBaseline = LinnetCandidatePresentation.secondaryBaselineOffset(
      primaryFont: primaryFont,
      secondaryFont: detailFont,
      baseOffset: 1,
      verticalText: false,
      placement: .standaloneDetail)
    let detail = LinnetCandidatePresentation.candidateLine(
      candidateFormat: "[comment]",
      label: "",
      candidate: "",
      comment: "/ef/ · n. 字母 F",
      candidateAttributes: candidateAttributes,
      labelAttributes: labelAttributes,
      commentAttributes: [
        .font: detailFont,
        .foregroundColor: NSColor.secondaryLabelColor,
        .baselineOffset: detailBaseline,
      ])
    require(detail.attributedString.string == "/ef/ · n. 字母 F",
            "standalone candidate detail split the runtime metadata wire shape")
    require(
      (detail.attributedString.attribute(.font, at: 0, effectiveRange: nil)
        as? NSFont)?.pointSize == 12 &&
        (detail.attributedString.attribute(.baselineOffset, at: 0, effectiveRange: nil)
          as? NSNumber)?.doubleValue == 1,
      "standalone candidate detail lost its canonical font or baseline")

    for point in [CGFloat(12), 16, 32] {
      let font = NSFont.systemFont(ofSize: point)
      let separatorWidth = LinnetCandidatePresentation.inlineCandidateSeparatorWidth(
        font: font)
      let tile = LinnetCandidatePresentation.candidateSelectionInsets(
        style: .tile, candidateFont: font)
      require(
        tile.left == separatorWidth / 2 && tile.right == separatorWidth / 2 &&
          tile.top == LinnetCandidatePresentation.candidateRowSpacing / 2 &&
          tile.bottom == LinnetCandidatePresentation.candidateRowSpacing / 2,
        "\(point)pt tile selection lost the live separator or row expansion")
      let underline = LinnetCandidatePresentation.candidateSelectionInsets(
        style: .underline, candidateFont: font)
      require(
        underline.top == 0 && underline.left == 0 &&
          underline.bottom == 0 && underline.right == 0,
        "\(point)pt underline selection incorrectly changed glyph geometry")
      let bar = LinnetCandidatePresentation.candidateSelectionInsets(
        style: .bar, candidateFont: font)
      require(
        bar.left == 8 && bar.right == 0 &&
          bar.top == LinnetCandidatePresentation.candidateRowSpacing / 2 &&
          bar.bottom == LinnetCandidatePresentation.candidateRowSpacing / 2,
        "\(point)pt bar selection lost its shared leading gutter or row expansion")
    }
  }

  private static func testCanonicalInlineMetricsAndMaterial() {
    let font = NSFont.systemFont(ofSize: 16)
    let expected = (LinnetCandidatePresentation.inlineCandidateSeparator as NSString)
      .size(withAttributes: [.font: font]).width
    require(
      LinnetCandidatePresentation.inlineCandidateSeparator == "  " &&
        LinnetCandidatePresentation.inlineCandidateSeparatorWidth(font: font) == expected,
      "inline candidate spacing gained a second pixel owner")
    require(
      LinnetCandidatePresentation.candidateMaterial == .popover,
      "candidate material stopped matching the native popover surface")
  }

  private static func testCandidateDetailGeometry() {
    let footer = LinnetCandidatePresentation.candidateDetailGeometry(
      forLinearLayout: true)
    let footerFrames = footer.frames(
      candidateSize: CGSize(width: 100, height: 20),
      detailSize: CGSize(width: 40, height: 10),
      dividerSize: CGSize(width: 1, height: 20))
    require(
      footer.placement == .footer &&
        footer.spacing == LinnetCandidatePresentation.candidateRowSpacing &&
        footer.detailColumnMaximumWidth == 256,
      "horizontal candidate detail lost its compact footer policy")
    require(
      footerFrames.candidate == CGRect(x: 0, y: 0, width: 100, height: 20) &&
        footerFrames.divider == nil &&
        footerFrames.detail == CGRect(x: 0, y: 26, width: 40, height: 10) &&
        footerFrames.size == CGSize(width: 100, height: 36),
      "footer candidate and detail no longer share one spatial geometry")

    let longFooterFrames = footer.frames(
      candidateSize: CGSize(width: 72, height: 24),
      detailSize: CGSize(width: 900, height: 54),
      dividerSize: CGSize(width: 1, height: 24))
    require(
      longFooterFrames.detail.width == 72 &&
        longFooterFrames.size.width == 72,
      "a horizontal definition can still widen its candidate row")

    let sidecar = LinnetCandidatePresentation.candidateDetailGeometry(
      forLinearLayout: false)
    let sidecarFrames = sidecar.frames(
      candidateSize: CGSize(width: 40, height: 60),
      detailSize: CGSize(width: 30, height: 12),
      dividerSize: CGSize(width: 1, height: 60))
    require(
      sidecar.placement == .sidecar &&
        sidecar.detailColumnMaximumWidth == 104,
      "vertical candidate detail lost its shared sidecar policy")
    require(
      sidecarFrames.candidate == CGRect(x: 0, y: 0, width: 40, height: 60) &&
        sidecarFrames.divider == CGRect(x: 46, y: 0, width: 1, height: 60) &&
        sidecarFrames.detail == CGRect(x: 53, y: 0, width: 30, height: 12) &&
        sidecarFrames.size == CGSize(width: 83, height: 60),
      "sidecar candidate, divider, and detail no longer share one spatial geometry")
    let tallSidecarFrames = sidecar.frames(
      candidateSize: CGSize(width: 40, height: 60),
      detailSize: CGSize(width: 104, height: 240),
      dividerSize: CGSize(width: 1, height: 240))
    let nextPageSidecarFrames = sidecar.frames(
      candidateSize: CGSize(width: 40, height: 60),
      detailSize: CGSize(width: 80, height: 20),
      dividerSize: CGSize(width: 1, height: 20))
    require(
      tallSidecarFrames.detail.height == 60 &&
        tallSidecarFrames.divider?.height == 60 &&
        tallSidecarFrames.size.height == 60 &&
        nextPageSidecarFrames.size.height == tallSidecarFrames.size.height,
      "sidecar detail can still grow or destabilize candidate-owned page height")

    let longDefinitionFrames = sidecar.frames(
      candidateSize: CGSize(width: 112, height: 156),
      detailSize: CGSize(width: 680, height: 18),
      dividerSize: CGSize(width: 1, height: 156))
    require(
      longDefinitionFrames.detail.width <= 120 &&
        longDefinitionFrames.size.width <= 245,
      "a long English definition can still stretch the vertical candidate panel")

    for (fontPoint, expectedDetailWidth) in [
      (CGFloat(12), CGFloat(104)),
      (CGFloat(15), CGFloat(104)),
      (CGFloat(16), CGFloat(104)),
      (CGFloat(32), CGFloat(136))
    ] {
      let geometry = LinnetCandidatePresentation.candidateDetailGeometry(
        forLinearLayout: false,
        candidateFontPoint: fontPoint)
      let frames = geometry.frames(
        candidateSize: CGSize(width: 500, height: 180),
        detailSize: CGSize(width: 500, height: 180),
        dividerSize: CGSize(width: 1, height: 180))
      require(
        geometry.detailColumnMaximumWidth == expectedDetailWidth &&
          frames.detail.width == expectedDetailWidth,
        "\(fontPoint)pt canonical sidecar detail escaped its exact width owner")
    }
  }

  private static func testNavigationLayout() {
    let compactHorizontal = LinnetCandidatePresentation.rimeNavigationLayout(
      flow: .horizontal, verticalText: false)
    require(
      compactHorizontal.linear && !compactHorizontal.vertical,
      "compact horizontal candidates lost their stock Left/Right navigation")

    let compactVertical = LinnetCandidatePresentation.rimeNavigationLayout(
      flow: .vertical, verticalText: false)
    require(
      !compactVertical.linear && !compactVertical.vertical,
      "compact vertical candidates lost their stock Up/Down navigation")


  }

  private static func testCandidateRows() {
    for count in 3...9 {
      require(
        LinnetCandidatePresentation.visualRows(candidateCount: count, flow: .horizontal)
          == [Array(0..<count)],
        "horizontal candidates must use exactly the current page")
      require(
        LinnetCandidatePresentation.visualRows(candidateCount: count, flow: .vertical)
          == (0..<count).map { [$0] },
        "vertical candidates must show one translated candidate per row")
    }
    require(
      LinnetCandidatePresentation.visualRows(candidateCount: 0, flow: .horizontal).isEmpty,
      "an empty candidate list created a visual row")
  }

  private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fail(message) }
  }

  private static func fail(_ message: String) -> Never {
    FileHandle.standardError.write(
      Data("LinnetCandidatePresentationTests: FAIL: \(message)\n".utf8))
    exit(EXIT_FAILURE)
  }
}
