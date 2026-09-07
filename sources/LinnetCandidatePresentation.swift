//
//  LinnetCandidatePresentation.swift
//  Linnet
//
//  Candidate-window presentation rules shared by AppKit, Settings, and tests.
//

import AppKit
import Foundation

/// Offline provider retained for embedders. The optional remote implementation
/// lives in ZIMETranslationHTTP and is gated by explicit user configuration.
protocol ZIMECloudTranslationProvider: Sendable {
  func translations(for text: String, sourceLanguage: String) async -> [String]
}

struct ZIMENullCloudTranslationProvider: ZIMECloudTranslationProvider {
  func translations(for _: String, sourceLanguage _: String) async -> [String] { [] }
}

enum LinnetCandidatePresentation {
  private struct BilingualAnnotation: Codable {
    let displayText: String
    let translations: [String]
    let detailText: String
  }
  struct CandidateComment: Equatable {
    let displayText: String
    let belongsToSmartEnglish: Bool
    let translations: [String]

    init(
      displayText: String,
      belongsToSmartEnglish: Bool,
      translations: [String] = []
    ) {
      self.displayText = displayText
      self.belongsToSmartEnglish = belongsToSmartEnglish
      self.translations = translations
    }
  }

  private struct FormatReplacement {
    let token: String
    let value: String
    let attributes: [NSAttributedString.Key: Any]
    let isCandidate: Bool
  }

  private struct FormatMatch {
    let range: Range<String.Index>
    let replacement: FormatReplacement
  }

  // TextKit owns visible line truncation. This higher bound is only a safety
  // limit for malformed dictionary metadata, not a display budget.
  static let maximumDetailCharacterCount = 256
  static let maximumFooterDetailLineCount = 3
  static let smartEnglishDetailPrefix = "\u{001D}"
  static let structuredBilingualPrefix = "\u{001C}"
  static let reverseEnglishDetailPrefix = "\u{001E}"
  static let translationAlternativeSeparator = "\u{001F}"

  // One compact typographic skeleton serves every bundled theme. Color,
  // material, corner treatment, and selection shape remain theme-owned.
  static let candidateWindowInset = CGSize(width: 7, height: 6)
  static let candidateRowSpacing: CGFloat = 6
  static let preeditSpacing: CGFloat = 8
  static let inlineCandidateSeparator = "  "
  static let candidateMaterial = NSVisualEffectView.Material.popover

  private static let detailPartOfSpeechBoundary =
    #/[；;]\s*(name|n|vt|vi|v|adj|adv|abbr|int|interj|prep|pref|conj|pron|suf|vbl|num|aux|art|det|fig|lit)[.]\s*/#

  /// Smart English owns whether a Rime comment is an English detail surface.
  /// The presentation boundary removes its one-byte marker before any text is
  /// drawn or announced; ordinary Chinese spelling comments remain unmarked.
  static func candidateComment(_ rawComment: String) -> CandidateComment {
    if rawComment.hasPrefix(structuredBilingualPrefix) {
      guard let annotation = decodeBilingualAnnotation(rawComment) else {
        return .init(displayText: "", belongsToSmartEnglish: false)
      }
      return .init(displayText: annotation.displayText, belongsToSmartEnglish: false,
        translations: Array(annotation.translations.prefix(3)))
    }
    if rawComment.hasPrefix(reverseEnglishDetailPrefix) {
      let alternatives = String(rawComment.dropFirst())
        .components(separatedBy: translationAlternativeSeparator)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      return CandidateComment(
        displayText: alternatives.prefix(2).joined(separator: " / "),
        belongsToSmartEnglish: false,
        translations: Array(alternatives.prefix(3)))
    }
    guard rawComment.hasPrefix(smartEnglishDetailPrefix) else {
      return CandidateComment(
        displayText: rawComment, belongsToSmartEnglish: false, translations: [])
    }
    let displayText = String(rawComment.dropFirst())
    return CandidateComment(
      displayText: displayText,
      belongsToSmartEnglish: true,
      translations: chineseTranslationAlternatives(in: displayText))
  }

  /// Full regional definitions for native tooltips/AX help; independent of
  /// line wrapping and the existing three explicit translation alternatives.
  static func fullCandidateComment(_ rawComment: String) -> String {
    if rawComment.hasPrefix(structuredBilingualPrefix) {
      return decodeBilingualAnnotation(rawComment)?.detailText ?? ""
    }
    if rawComment.hasPrefix(reverseEnglishDetailPrefix) {
      return String(rawComment.dropFirst())
        .components(separatedBy: translationAlternativeSeparator)
        .filter { !$0.isEmpty }.joined(separator: "\n")
    }
    return candidateComment(rawComment).displayText
  }

  /// The local dictionary owns parsing and deduplication. JSON preserves all
  /// punctuation, quotes and legacy delimiter characters in source notes.
  static func bilingualComment(displayText: String, translations: [String], detailText: String) -> String {
    let value = BilingualAnnotation(displayText: displayText,
      translations: Array(translations.prefix(3)), detailText: detailText)
    guard let data = try? JSONEncoder().encode(value) else { return "" }
    return structuredBilingualPrefix + String(decoding: data, as: UTF8.self)
  }

  private static func decodeBilingualAnnotation(_ rawComment: String) -> BilingualAnnotation? {
    guard rawComment.utf8.count <= 131_072 else { return nil }
    return try? JSONDecoder().decode(BilingualAnnotation.self, from: Data(rawComment.dropFirst().utf8))
  }

  private static func chineseTranslationAlternatives(in detail: String) -> [String] {
    let translatedDetail = detail.components(separatedBy: " · ").last ?? detail
    let parts = translatedDetail.components(
      separatedBy: CharacterSet(charactersIn: "；;"))
    var result: [String] = []
    var seen = Set<String>()
    for rawPart in parts {
      var part = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
      if let boundary = part.range(
        of: #"^(name|n|vt|vi|v|adj|adv|abbr|int|interj|prep|pref|conj|pron|suf|vbl|num|aux|art|det)[.]\s*"#,
        options: [.regularExpression, .caseInsensitive]) {
        part.removeSubrange(boundary)
      }
      let containsHan = part.unicodeScalars.contains { scalar in
        (0x3400...0x9FFF).contains(scalar.value) ||
          (0xF900...0xFAFF).contains(scalar.value) ||
          (0x20000...0x2FA1F).contains(scalar.value)
      }
      guard containsHan, !part.isEmpty, part.count <= maximumDetailCharacterCount,
        seen.insert(part).inserted
      else { continue }
      result.append(part)
      if result.count == 3 { break }
    }
    return result
  }

  struct InputModeIdentity: Equatable {
    let schemaID: String
    let asciiMode: Bool
  }

  /// A transient notice is only a live input-mode transition projection.
  /// Initial sampling, Settings reloads, and switches between Chinese profiles
  /// stay quiet. Rime's schema and ascii_mode remain the state owners; this
  /// function only chooses the compact caret label.
  static func inputModeTransitionLabel(
    previous: InputModeIdentity?,
    current: InputModeIdentity
  ) -> String? {
    guard let previous, previous != current else {
      return nil
    }
    if current.asciiMode {
      return "A"
    }

    let previousIsChinese =
      LinnetSettingsContract.ChineseProfile(schemaID: previous.schemaID) != nil
    let currentIsChinese =
      LinnetSettingsContract.ChineseProfile(schemaID: current.schemaID) != nil
    let previousIsEnglish = previous.schemaID == LinnetSettingsContract.englishSchemaID
    let currentIsEnglish = current.schemaID == LinnetSettingsContract.englishSchemaID
    if previous.asciiMode {
      if currentIsEnglish { return "En" }
      if currentIsChinese { return "中" }
      return nil
    }
    if previousIsChinese && currentIsEnglish {
      return "En"
    }
    if previousIsEnglish && currentIsChinese {
      return "中"
    }
    return nil
  }

  struct CandidateMenuPage: Equatable {
    let currentPage: Int
    let pageSize: Int
    let candidateCount: Int
    let highlighted: Int
  }

  /// Rime's selection keys are the single label owner for every selectable
  /// current-page candidate, including zero-input Smart English predictions.
  /// A missing custom label falls back to the same one-based page index used
  /// by direct numeric selection.
  static func candidateSelectionLabel(at index: Int, labels: [String]) -> String {
    if labels.count > 1, labels.indices.contains(index) {
      return labels[index]
    }
    if let customLabels = labels.first, labels.count == 1,
      index >= 0, index < customLabels.count {
      return String(customLabels[customLabels.index(customLabels.startIndex, offsetBy: index)])
    }
    return String(index + 1)
  }

  /// Rime legitimately exposes an all-zero menu while the input session is
  /// idle. Keep that state presentable so schema-transition feedback can use
  /// the normal caret-anchored panel without treating missing menu data as an
  /// input-session failure.
  static func candidateMenuPage(
    currentPage: Int32,
    pageSize: Int32,
    candidateCount: Int32,
    highlighted: Int32
  ) -> CandidateMenuPage? {
    guard let currentPage = Int(exactly: currentPage),
      let pageSize = Int(exactly: pageSize),
      let candidateCount = Int(exactly: candidateCount),
      let highlighted = Int(exactly: highlighted),
      currentPage >= 0,
      pageSize >= 0,
      candidateCount >= 0,
      highlighted >= 0
    else { return nil }
    guard pageSize > 0 else {
      return currentPage == 0 && candidateCount == 0 && highlighted == 0
        ? CandidateMenuPage(
          currentPage: 0, pageSize: 0, candidateCount: 0, highlighted: 0)
        : nil
    }
    guard candidateCount == 0 ? highlighted == 0 : highlighted < candidateCount else {
      return nil
    }
    return CandidateMenuPage(
      currentPage: currentPage,
      pageSize: pageSize,
      candidateCount: candidateCount,
      highlighted: highlighted)
  }

  enum CandidateSelectionStyle: String, Equatable {
    case tile, underline, bar
  }

  struct CandidateLine {
    let attributedString: NSAttributedString
    let labelPrefix: NSAttributedString
  }

  enum SecondaryTextPlacement {
    case inline
    case standaloneDetail
  }

  static func inlineCandidateSeparatorWidth(font: NSFont) -> CGFloat {
    (inlineCandidateSeparator as NSString).size(withAttributes: [.font: font]).width
  }

  /// TextKit and SwiftUI both consume the same selection expansion without
  /// changing the candidate line's intrinsic size. Tiles borrow half of the
  /// inter-candidate gap on each side; bars extend through the shared row gap;
  /// underlines remain attached to the glyph line.
  static func candidateSelectionInsets(
    style: CandidateSelectionStyle,
    candidateFont: NSFont
  ) -> NSEdgeInsets {
    switch style {
    case .tile:
      let horizontal = inlineCandidateSeparatorWidth(font: candidateFont) / 2
      let vertical = candidateRowSpacing / 2
      return NSEdgeInsets(
        top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    case .underline:
      return NSEdgeInsetsZero
    case .bar:
      let vertical = candidateRowSpacing / 2
      return NSEdgeInsets(top: vertical, left: 8, bottom: vertical, right: 0)
    }
  }

  /// Secondary candidate text uses the same optical baseline in the live
  /// panel and Settings preview. Vertical glyph flow already supplies its own
  /// alignment and therefore receives only the configured base offset.
  static func secondaryBaselineOffset(
    primaryFont: NSFont,
    secondaryFont: NSFont,
    baseOffset: CGFloat,
    verticalText: Bool,
    placement: SecondaryTextPlacement
  ) -> CGFloat {
    guard !verticalText, placement == .inline else { return baseOffset }
    return baseOffset + (primaryFont.pointSize - secondaryFont.pointSize) / 2.5
  }

  /// Canonical candidate-line composition. Attribute placeholders before
  /// replacement so arbitrary candidate formats retain label/candidate/comment
  /// typography, and preserve the existing TextKit no-break behavior.
  static func candidateLine(
    candidateFormat: String,
    label: String,
    candidate: String,
    comment: String,
    candidateAttributes: [NSAttributedString.Key: Any],
    labelAttributes: [NSAttributedString.Key: Any],
    commentAttributes: [NSAttributedString.Key: Any]
  ) -> CandidateLine {
    let normalizedCandidate = candidate.precomposedStringWithCanonicalMapping
    let normalizedComment = comment.precomposedStringWithCanonicalMapping
    let line = NSMutableAttributedString()
    var labelPrefix: NSAttributedString?
    var remainingFormat = candidateFormat
    while !remainingFormat.isEmpty {
      let replacements: [FormatReplacement] = [
        .init(token: "[label]", value: label, attributes: labelAttributes, isCandidate: false),
        .init(
          token: "[candidate]", value: normalizedCandidate,
          attributes: candidateAttributes, isCandidate: true),
        .init(
          token: "[comment]", value: normalizedComment,
          attributes: commentAttributes, isCandidate: false)
      ]
      let next = replacements.compactMap { replacement -> FormatMatch? in
        guard let range = remainingFormat.range(of: replacement.token) else { return nil }
        return .init(range: range, replacement: replacement)
      }.min { $0.range.lowerBound < $1.range.lowerBound }
      guard let next else {
        line.append(NSAttributedString(
          string: remainingFormat,
          attributes: labelAttributes))
        break
      }

      let literal = String(remainingFormat[..<next.range.lowerBound])
      line.append(NSAttributedString(string: literal, attributes: labelAttributes))
      let token = String(remainingFormat[next.range])
      if labelPrefix == nil, token == "[candidate]" || token == "[comment]" {
        labelPrefix = NSAttributedString(attributedString: line)
      }
      let replacementStart = line.length
      line.append(NSAttributedString(
        string: next.replacement.value,
        attributes: next.replacement.attributes))
      if next.replacement.isCandidate,
        normalizedCandidate.count <= 5, normalizedCandidate.count > 1 {
        let firstCharacterEnd = normalizedCandidate.index(after: normalizedCandidate.startIndex)
          .utf16Offset(in: normalizedCandidate)
        line.addAttribute(
          NSAttributedString.Key("noBreak"),
          value: true,
          range: NSRange(
            location: replacementStart + firstCharacterEnd,
            length: normalizedCandidate.utf16.count - firstCharacterEnd))
      }
      remainingFormat = String(remainingFormat[next.range.upperBound...])
    }

    if line.length > 1, line.length <= 10 {
      line.addAttribute(
        NSAttributedString.Key("noBreak"),
        value: true,
        range: NSRange(location: 1, length: line.length - 1))
    }
    return CandidateLine(
      attributedString: NSAttributedString(attributedString: line),
      labelPrefix: labelPrefix ?? NSAttributedString())
  }

  /// The only candidate-font resolver used by the live AppKit surface and the
  /// Settings preview. Font names remain ordered: the first available family
  /// owns the primary face and later families form its CoreText cascade.
  static func platformFont(
    fontNames: [String],
    size: CGFloat,
    fallback: NSFont? = nil
  ) -> NSFont {
    var seenFamilies = Set<String>()
    let fonts = fontNames.compactMap { rawName -> NSFont? in
      let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty else { return nil }
      let familyFaceFont: NSFont? = if let separator = name.lastIndex(of: "-"),
        separator != name.startIndex,
        name.index(after: separator) != name.endIndex {
        NSFont(
          descriptor: NSFontDescriptor(fontAttributes: [
            .family: String(name[..<separator]),
            .face: String(name[name.index(after: separator)...])
          ]),
          size: size)
      } else {
        nil
      }
      let font = NSFont(name: name, size: size)
        ?? familyFaceFont
        ?? NSFont(
          descriptor: NSFontDescriptor(fontAttributes: [.family: name]),
          size: size)
      guard let font else { return nil }
      let identity = font.familyName ?? font.fontName
      return seenFamilies.insert(identity).inserted ? font : nil
    }
    guard let primary = fonts.first else {
      return (fallback ?? NSFont.systemFont(ofSize: size)).withSize(size)
    }
    let cascades = fonts.dropFirst().map(\.fontDescriptor)
    guard !cascades.isEmpty else { return primary.withSize(size) }
    let descriptor = primary.fontDescriptor.addingAttributes([.cascadeList: cascades])
    return NSFont(descriptor: descriptor, size: size) ?? primary.withSize(size)
  }

}

extension LinnetCandidatePresentation {
  static func windowInset(verticalText: Bool) -> CGSize {
    guard verticalText else { return candidateWindowInset }
    return CGSize(
      width: candidateWindowInset.height,
      height: candidateWindowInset.width)
  }

  enum CandidateFlow: Equatable {
    case horizontal, vertical
  }

  struct RimeNavigationLayout: Equatable {
    let linear: Bool
    let vertical: Bool
  }

  /// Projects the current page's geometry into librime Selector options.
  static func rimeNavigationLayout(
    flow: CandidateFlow,
    verticalText: Bool
  ) -> RimeNavigationLayout {
    .init(linear: flow == .horizontal, vertical: verticalText)
  }

  enum CandidateControlMode: Equatable {
    case paging(canPageUp: Bool, canPageDown: Bool)
  }

  enum CandidateControlAction: Equatable, Hashable {
    case pageUp, pageDown
  }

  /// Maps current-page offsets to horizontal or vertical visual rows.
  /// Click and accessibility indices remain independent of layout direction.
  static func visualRows(
    candidateCount: Int,
    flow: CandidateFlow
  ) -> [[Int]] {
    guard candidateCount > 0 else { return [] }
    let indices = Array(0..<candidateCount)
    switch flow {
    case .horizontal: return [indices]
    case .vertical: return indices.map { [$0] }
    }
  }

  enum AccessibilitySurface: Equatable {
    case candidates, inputModeStatus

    var exposesCandidateList: Bool { self == .candidates }

    var localizedLabelKey: String {
      switch self {
      case .candidates: "Candidate window"
      case .inputModeStatus: "Input mode"
      }
    }
  }

  enum DetailPlacement: Equatable {
    case footer, sidecar
  }

  struct CandidateDetailFrames: Equatable {
    let candidate: CGRect
    let divider: CGRect?
    let detail: CGRect
    let size: CGSize
  }

  /// Canonical spatial relationship between the candidate body and selected
  /// metadata. TextKit and SwiftUI measure their own glyphs, then consume these
  /// frames instead of independently choosing axes, gaps, or detail widths.
  struct CandidateDetailGeometry: Equatable {
    let placement: DetailPlacement
    let spacing: CGFloat
    let dividerText: String
    let candidateColumnMaximumWidth: CGFloat?
    let detailColumnMaximumWidth: CGFloat?

    func fittedDetailWidth(candidateWidth: CGFloat, detailWidth: CGFloat) -> CGFloat {
      let boundedDetailWidth = min(
        detailWidth,
        detailColumnMaximumWidth ?? detailWidth)
      return placement == .footer
        ? min(max(0, candidateWidth), boundedDetailWidth)
        : boundedDetailWidth
    }

    func frames(
      candidateSize: CGSize,
      detailSize: CGSize,
      dividerSize: CGSize
    ) -> CandidateDetailFrames {
      let fittedCandidateSize = CGSize(
        width: min(candidateSize.width, candidateColumnMaximumWidth ?? candidateSize.width),
        height: candidateSize.height)
      let fittedDetailSize = CGSize(
        width: fittedDetailWidth(
          candidateWidth: fittedCandidateSize.width,
          detailWidth: detailSize.width),
        height: placement == .sidecar
          ? min(detailSize.height, max(0, fittedCandidateSize.height))
          : detailSize.height)
      let candidate = CGRect(origin: .zero, size: fittedCandidateSize)
      switch placement {
      case .footer:
        let detail = CGRect(
          origin: CGPoint(x: 0, y: fittedCandidateSize.height + spacing),
          size: fittedDetailSize)
        return CandidateDetailFrames(
          candidate: candidate,
          divider: nil,
          detail: detail,
          size: CGSize(
            width: max(fittedCandidateSize.width, fittedDetailSize.width),
            height: fittedCandidateSize.height + spacing + fittedDetailSize.height))
      case .sidecar:
        let divider = CGRect(
          origin: CGPoint(x: fittedCandidateSize.width + spacing, y: 0),
          size: CGSize(width: dividerSize.width, height: fittedCandidateSize.height))
        let detail = CGRect(
          origin: CGPoint(x: divider.maxX + spacing, y: 0),
          size: fittedDetailSize)
        return CandidateDetailFrames(
          candidate: candidate,
          divider: divider,
          detail: detail,
          size: CGSize(
            width: detail.maxX,
            height: fittedCandidateSize.height))
      }
    }
  }

  static func candidateDetailGeometry(
    forLinearLayout linear: Bool,
    candidateFontPoint: CGFloat = 16
  ) -> CandidateDetailGeometry {
    let candidateColumnMaximumWidth = min(240, max(150, candidateFontPoint * 10))
    let detailColumnMaximumWidth = linear
      ? min(360, max(240, candidateFontPoint * 16))
      : min(136, max(104, candidateFontPoint * 4.25))
    return CandidateDetailGeometry(
      placement: linear ? .footer : .sidecar,
      spacing: candidateRowSpacing,
      dividerText: "│",
      candidateColumnMaximumWidth: linear ? nil : candidateColumnMaximumWidth,
      detailColumnMaximumWidth: detailColumnMaximumWidth)
  }

  static func usesInlineComments(candidateFormat: String) -> Bool {
    candidateFormat.contains("[comment]")
  }

  static func selectedDetailText(_ rawComment: String) -> String {
    let normalized = rawComment.trimmingCharacters(in: .whitespacesAndNewlines)
    let bounded = normalized.count > maximumDetailCharacterCount
      ? String(normalized.prefix(maximumDetailCharacterCount - 1)) + "…"
      : normalized
    return bounded.replacing(detailPartOfSpeechBoundary) { match in
      "\n\(match.1). "
    }
  }

  static func accessibilityAnnouncement(
    candidate: String,
    comment: String,
    page: Int,
    indexOnPage: Int
  ) -> String? {
    guard page >= 0, indexOnPage >= 0, !candidate.isEmpty else { return nil }
    let position = String(
      format: NSLocalizedString(
        "Page %1$ld, candidate %2$ld",
        comment: "Candidate accessibility position"
      ),
      locale: Locale.current,
      page + 1,
      indexOnPage + 1
    )
    var parts = [position, candidate]
    let detail = selectedDetailText(comment)
    if !detail.isEmpty {
      parts.append(detail.replacingOccurrences(of: "\n", with: ", "))
    }
    return parts.joined(separator: ", ")
  }

}
