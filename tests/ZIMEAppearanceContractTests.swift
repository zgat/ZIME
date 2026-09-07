import AppKit

// Only the Rime config reader is stubbed. This gate loads the production
// SquirrelTheme and compares it with the production Settings presentation.
final class SquirrelConfig {
  var fields: [String: String] = [:]

  init(source: String) {
    var parents: [String] = []
    for raw in source.split(separator: "\n") {
      let line = String(raw.prefix { $0 != "#" })
      let indent = line.prefix { $0 == " " }.count
      let value = line.trimmingCharacters(in: .whitespaces)
      guard !value.isEmpty, let colon = value.firstIndex(of: ":") else { continue }
      let level = indent / 2
      parents = Array(parents.prefix(level))
      let key = String(value[..<colon])
      let scalar = String(value[value.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
      if scalar.isEmpty { parents.append(key) }
      else { fields[(parents + [key]).joined(separator: "/")] = scalar.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
    }
  }

  func getString(_ option: String) -> String? { fields[option] }
  func getBool(_ option: String) -> Bool? { fields[option].flatMap(Bool.init) }
  func getDouble(_ option: String) -> CGFloat? { fields[option].flatMap(Double.init).map { CGFloat($0) } }
  func getColor(_ option: String, inSpace: SquirrelTheme.RimeColorSpace) -> NSColor? {
    guard let raw = fields[option], let value = UInt32(raw.replacingOccurrences(of: "0x", with: ""), radix: 16) else { return nil }
    return LinnetSettingsAppearancePreview.ColorComponents(value).nsColor
  }
}

infix operator ?= : AssignmentPrecedence
func ?=<T>(left: inout T, right: T?) { if let right { left = right } }
func ?=<T>(left: inout T?, right: T?) { if let right { left = right } }

enum ZIMEAppearanceContractTests {
  static func run() {
    let source = try! String(contentsOfFile: "data/squirrel.yaml", encoding: .utf8)
    let catalog = try! LinnetSettingsAppearancePreview.Catalog(contents: source)
    let config = SquirrelConfig(source: source)
    for key in config.fields.keys where key.hasPrefix("preset_color_schemes/linnet_") {
      let field = key.split(separator: "/").last!
      precondition(field.hasSuffix("_color") || ["color_space", "name", "author"].contains(String(field)),
                   "Built-in palette owns a non-color property: \(key)")
    }
    precondition(config.getDouble("style/corner_radius") == 8 && config.getDouble("style/hilited_corner_radius") == 5)
    precondition(config.getString("style/linnet_selection_style") == "tile")
    for family in LinnetSettingsDocument.ThemeFamily.allCases {
      for dark in [false, true] {
        for effect in LinnetSettingsDocument.CandidateSelectionEffect.allCases {
          for corners in LinnetSettingsDocument.CandidateCornerStyle.allCases {
            for point in [12.0, 16, 32] {
              var appearance = LinnetSettingsDocument.Appearance.default
              appearance.themeFamily = family
              appearance.themeMode = dark ? .dark : .light
              appearance.selectionEffect = effect
              appearance.cornerStyle = corners
              appearance.fontPoint = point
              let prefix = "preset_color_schemes/\(family.schemeIdentifier(isDark: dark))"
              config.fields["style/color_scheme"] = family.schemeIdentifier(isDark: dark)
              config.fields["style/color_scheme_dark"] = family.schemeIdentifier(isDark: dark)
              config.fields["style/linnet_selection_style"] = effect.projectedStyle
              config.fields["style/corner_radius"] = String(corners.windowRadius)
              config.fields["style/hilited_corner_radius"] = String(corners.selectionRadius)
              config.fields["style/font_point"] = String(point)
              config.fields["style/label_font_point"] = String(LinnetSettingsDocument.Appearance.labelFontPoint(for: point))
              config.fields["style/comment_font_point"] = String(LinnetSettingsDocument.Appearance.commentFontPoint(for: point))
              // Stale v13 palette overrides must not undo the controls.
              for (key, value) in ["corner_radius": "99", "hilited_corner_radius": "88",
                "linnet_selection_style": "bar", "translucency": "true", "mutual_exclusive": "true",
                "font_point": "30", "candidate_list_layout": "stacked"] {
                config.fields["\(prefix)/\(key)"] = value
              }
              let theme = SquirrelTheme()
              theme.load(config: config, dark: dark)
              guard case .success(let preview) = LinnetSettingsAppearancePreview.presentation(
                for: appearance, systemIsDark: dark, catalog: catalog) else { fatalError("missing preview") }
              precondition(theme.selectionStyle == preview.selectionStyle
                && theme.cornerRadius == preview.cornerRadius && theme.hilitedCornerRadius == preview.highlightedCornerRadius,
                "Live and Settings appearance treatments differ")
              precondition(!theme.translucency && !theme.mutualExclusive && theme.linear,
                "Palette changed material or layout")
              precondition(theme.font.pointSize == point && theme.font == LinnetCandidatePresentation.platformFont(fontNames: [], size: point),
                "Palette or annotation changed the regular font")
              let selected = effect == .fullRow ? preview.palette.selectedPrimary : preview.palette.primary
              let secondary = effect == .fullRow ? preview.palette.selectedPrimary : preview.palette.secondary
              precondition(theme.highlightedAttrs[.foregroundColor] as? NSColor == selected.nsColor)
              precondition(theme.labelHighlightedAttrs[.foregroundColor] as? NSColor == secondary.nsColor)
              precondition(theme.commentHighlightedAttrs[.foregroundColor] as? NSColor == secondary.nsColor)
              precondition(theme.backgroundColor == preview.palette.background.nsColor)
              precondition(theme.highlightedBackColor == (effect == .fullRow
                ? preview.palette.selectedBackground : preview.palette.selectionIndicator).nsColor)
            }
          }
        }
      }
    }
    print("ZIMEAppearanceContractTests: PASS (192 live/preview combinations)")
  }
}
