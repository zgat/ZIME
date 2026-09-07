//
//  LinnetSettingsDocument.swift
//  Typed, versioned settings document edited by the graphical Settings UI and
//  rendered into Rime YAML projections only at deploy time. The document is
//  the only Layer-1 surface the Settings application writes to; everything
//  else is derived by LinnetSettingsProjectionRenderer.
//

import Foundation

/// Canonical settings document (schema v17). ZIME's bilingual layout defaults
/// are projected over the bundled Rime distribution without modifying its data.
struct LinnetSettingsDocument: Codable, Equatable, Sendable {
  static let currentSchemaVersion = 17

  var schemaVersion: Int
  var appearance: Appearance
  var input: Input
  var english: English
  var shortcuts: Shortcuts
  private enum CodingKeys: String, CodingKey { case schemaVersion, appearance, input, english, shortcuts }

  init(
    schemaVersion: Int = currentSchemaVersion,
    appearance: Appearance,
    input: Input,
    english: English,
    shortcuts: Shortcuts = .default
  ) {
    self.schemaVersion = schemaVersion
    self.appearance = appearance
    self.input = input
    self.english = english
    self.shortcuts = shortcuts
  }
}

extension LinnetSettingsDocument {
  enum ThemeMode: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark
  }

  enum ThemeFamily: String, Codable, CaseIterable, Sendable {
    case paperLedger = "paper_ledger"
    case moonJade = "moon_jade"
    case sidecarSlate = "sidecar_slate"
    case clayTiles = "clay_tiles"
    case mistJade = "mist_jade"
    case nativeGlass = "native_glass"
    case inkCinnabar = "ink_cinnabar"
    case macOS = "macos"

    static let defaultValue = ThemeFamily.paperLedger

    func schemeIdentifier(isDark: Bool) -> String {
      let prefix: String
      switch self {
      case .paperLedger: prefix = "linnet_paper"
      case .moonJade: prefix = "linnet_moon_jade"
      case .sidecarSlate: prefix = "linnet_sidecar"
      case .clayTiles: prefix = "linnet_clay"
      case .mistJade: prefix = "linnet_mist_jade"
      case .nativeGlass: prefix = "linnet_glass"
      case .inkCinnabar: prefix = "linnet_ink_cinnabar"
      case .macOS: prefix = "linnet_macos"
      }
      return "\(prefix)_\(isDark ? "dark" : "light")"
    }
  }

  enum FontPreset: String, Codable, CaseIterable, Sendable {
    case system
    case humanist
    case swiss
    case editorial
    case book

    /// Canonical font cascade used by both the live candidate window and the
    /// Settings preview. The first family owns Latin glyphs; the second owns
    /// Chinese glyphs and any fallback absent from the first family.
    var fontFamilies: [String] {
      switch self {
      case .system: []
      case .humanist: ["Avenir Next", "Hiragino Sans GB"]
      case .swiss: ["Helvetica Neue", "Heiti SC"]
      case .editorial: ["Iowan Old Style", "Songti SC"]
      case .book: ["Charter", "Songti SC"]
      }
    }

    var displayPair: String {
      self == .system ? "SF Pro + PingFang SC" : fontFamilies.joined(separator: " + ")
    }

    var projectedFontFace: String? {
      fontFamilies.isEmpty ? nil : fontFamilies.joined(separator: ", ")
    }
  }

  enum CandidateLayout: String, Codable, CaseIterable, Sendable {
    case horizontal
    case vertical
  }

  enum CandidateSelectionEffect: String, Codable, CaseIterable, Sendable {
    case fullRow = "full_row"
    case underline

    var projectedStyle: String { self == .fullRow ? "tile" : "underline" }
  }

  enum CandidateCornerStyle: String, Codable, CaseIterable, Sendable {
    case rounded
    case square

    var windowRadius: Double { self == .rounded ? 8 : 0 }
    var selectionRadius: Double { self == .rounded ? 5 : 0 }
  }

  /// Physical macOS key identity; modifier bits match NSEvent's public flags.
  /// Return and keypad Enter are one action and conflict as the same shortcut.
  struct Shortcut: Codable, Equatable, Hashable, Sendable {
    static let shift: UInt = 1 << 17
    static let control: UInt = 1 << 18
    static let option: UInt = 1 << 19
    static let command: UInt = 1 << 20
    static let modifierMask = shift | control | option | command
    let keyCode: UInt16
    let modifiers: UInt

    init(keyCode: UInt16, modifiers: UInt = 0) {
      self.keyCode = keyCode == 76 ? 36 : keyCode
      self.modifiers = modifiers
    }

    static let tab = Shortcut(keyCode: 48)
    static let enter = Shortcut(keyCode: 36)
    static let optionTab = Shortcut(keyCode: 48, modifiers: option)

    private static let keyNames: [UInt16: String] = [
      0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V",
      11:"B", 12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 18:"1", 19:"2",
      20:"3", 21:"4", 22:"6", 23:"5", 24:"=", 25:"9", 26:"7", 27:"-", 28:"8",
      29:"0", 30:"]", 31:"O", 32:"U", 33:"[", 34:"I", 35:"P", 36:"↩", 37:"L",
      38:"J", 39:"'", 40:"K", 41:";", 42:"\\", 43:",", 44:"/", 45:"N", 46:"M",
      47:".", 48:"⇥", 49:"Space", 50:"`", 65:".", 67:"*", 69:"+", 75:"/",
      78:"-", 81:"=", 82:"0", 83:"1", 84:"2", 85:"3", 86:"4", 87:"5", 88:"6",
      89:"7", 91:"8", 92:"9", 96:"F5", 97:"F6", 98:"F7", 99:"F3", 100:"F8",
      101:"F9", 103:"F11", 105:"F13", 106:"F16", 107:"F14", 109:"F10", 111:"F12",
      113:"F15", 118:"F4", 120:"F2", 122:"F1", 64:"F17", 79:"F18", 80:"F19", 90:"F20"
    ]

    var isValid: Bool {
      guard modifiers & ~Self.modifierMask == 0, let name = Self.keyNames[keyCode] else { return false }
      if modifiers & (Self.control | Self.option | Self.command) == 0,
        ![36, 48, 49].contains(keyCode),
        !(name.hasPrefix("F") && Int(name.dropFirst()) != nil) { return false }
      // These system/window shortcuts cannot reliably reach an input method.
      if modifiers & Self.command != 0, [12, 13, 4, 46, 48, 49].contains(keyCode) { return false }
      if modifiers & Self.control != 0, keyCode == 49 { return false }
      return true
    }

    var displayName: String {
      var result = ""
      for (flag, label) in [(Self.control, "⌃"), (Self.option, "⌥"), (Self.shift, "⇧"), (Self.command, "⌘")] {
        if modifiers & flag != 0 { result += label }
      }
      return result + (Self.keyNames[keyCode] ?? "?")
    }

    func matches(keyCode: UInt16, modifiers: UInt) -> Bool {
      self == Shortcut(keyCode: keyCode, modifiers: modifiers & Self.modifierMask)
    }

    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      self.init(keyCode: try values.decode(UInt16.self, forKey: .keyCode),
                modifiers: try values.decode(UInt.self, forKey: .modifiers))
      guard isValid else {
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unsupported shortcut"))
      }
    }
  }

  struct Shortcuts: Codable, Equatable, Sendable {
    enum Action: String, CaseIterable, Sendable {
      case switchSourceTranslation, commitRawInput, smartComplete
    }
    var switchSourceTranslation: Shortcut = .tab
    var commitRawInput: Shortcut = .enter
    var smartComplete: Shortcut? = .optionTab
    static let `default` = Shortcuts()

    private enum CodingKeys: String, CodingKey {
      case switchSourceTranslation, commitRawInput, smartComplete, commitCandidate
    }

    init() {}

    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      switchSourceTranslation = try values.decodeIfPresent(Shortcut.self, forKey: .switchSourceTranslation) ?? .tab
      // Retain the recorded key, but retire candidate-confirmation semantics.
      commitRawInput = try values.decodeIfPresent(Shortcut.self, forKey: .commitRawInput)
        ?? values.decodeIfPresent(Shortcut.self, forKey: .commitCandidate) ?? .enter
      smartComplete = values.contains(.smartComplete)
        ? try values.decodeIfPresent(Shortcut.self, forKey: .smartComplete) : .optionTab
    }

    func encode(to encoder: Encoder) throws {
      var values = encoder.container(keyedBy: CodingKeys.self)
      try values.encode(switchSourceTranslation, forKey: .switchSourceTranslation)
      try values.encode(commitRawInput, forKey: .commitRawInput)
      try values.encode(smartComplete, forKey: .smartComplete)
    }

    subscript(action: Action) -> Shortcut? {
      get {
        switch action {
        case .switchSourceTranslation: switchSourceTranslation
        case .commitRawInput: commitRawInput
        case .smartComplete: smartComplete
        }
      }
      set {
        switch action {
        case .switchSourceTranslation: if let newValue { switchSourceTranslation = newValue }
        case .commitRawInput: if let newValue { commitRawInput = newValue }
        case .smartComplete: smartComplete = newValue
        }
      }
    }

    var isValid: Bool {
      let bindings = Action.allCases.compactMap { self[$0] }
      return bindings.allSatisfy(\.isValid) && Set(bindings).count == bindings.count
    }

    func action(keyCode: UInt16, modifiers: UInt) -> Action? {
      guard isValid else { return nil }
      return Action.allCases.first { self[$0]?.matches(keyCode: keyCode, modifiers: modifiers) == true }
    }
  }

  /// One product-level choice owns the two Rime learning switches. Keeping
  /// invalid combinations out of the document avoids a second UI-side policy.
  enum ChineseLearningPolicy: String, Codable, CaseIterable, Sendable {
    case enhanced
    case standard
    case disabled
  }

  /// One finite product choice owns both Rime projections required by the
  /// standard affix segmentor. Keeping the literal and regular expression
  /// together prevents a custom trigger from reaching the recognizer without
  /// also reaching the prefix stripper.
  enum PinyinReverseTrigger: String, Codable, CaseIterable, Sendable {
    case semicolon
    case verticalBar = "vertical_bar"

    var prefix: String {
      switch self {
      case .semicolon: ";"
      case .verticalBar: "|"
      }
    }

    var recognizerPattern: String {
      switch self {
      case .semicolon: "^;[a-z;']*$"
      case .verticalBar: "^[|][a-z;']*$"
      }
    }
  }

  struct Appearance: Codable, Equatable, Sendable {
    static let defaultFontPoint = 16.0
    static let minimumFontPoint = 12.0
    static let maximumFontPoint = 32.0
    static let fontPointStep = 1.0
    static let defaultPageSize = 9
    static let pageSizeOptions = Array(3...9)

    var fontPoint: Double
    var themeFamily: ThemeFamily
    var themeMode: ThemeMode
    var fontPreset: FontPreset
    var selectionEffect: CandidateSelectionEffect
    var cornerStyle: CandidateCornerStyle
    var chineseCandidateLayout: CandidateLayout
    var englishCandidateLayout: CandidateLayout
    var pageSize: Int

    static let `default` = Appearance(
      fontPoint: defaultFontPoint,
      themeMode: .system,
      chineseCandidateLayout: .vertical,
      englishCandidateLayout: .vertical,
      pageSize: defaultPageSize,
      themeFamily: ThemeFamily.defaultValue,
      fontPreset: .system
    )

    init(
      fontPoint: Double,
      themeMode: ThemeMode,
      chineseCandidateLayout: CandidateLayout,
      englishCandidateLayout: CandidateLayout,
      pageSize: Int,
      themeFamily: ThemeFamily = ThemeFamily.defaultValue,
      fontPreset: FontPreset = .system,
      selectionEffect: CandidateSelectionEffect = .fullRow,
      cornerStyle: CandidateCornerStyle = .rounded
    ) {
      self.fontPoint = fontPoint
      self.themeFamily = themeFamily
      self.themeMode = themeMode
      self.fontPreset = fontPreset
      self.selectionEffect = selectionEffect
      self.cornerStyle = cornerStyle
      self.chineseCandidateLayout = chineseCandidateLayout
      self.englishCandidateLayout = englishCandidateLayout
      self.pageSize = pageSize
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      fontPoint =
        Self.clampFontPoint(
          try container.decodeIfPresent(Double.self, forKey: .fontPoint) ?? Self.defaultFontPoint)
      let familyValue = try container.decodeIfPresent(String.self, forKey: .themeFamily)
      if let familyValue {
        guard let family = ThemeFamily(rawValue: familyValue) else {
          throw DecodingError.dataCorruptedError(
            forKey: .themeFamily,
            in: container,
            debugDescription: "Unknown Linnet theme family.")
        }
        themeFamily = family
      } else {
        themeFamily = ThemeFamily.defaultValue
      }
      let modeValue = try container.decodeIfPresent(String.self, forKey: .themeMode)
      themeMode = modeValue.flatMap(ThemeMode.init(rawValue:)) ?? .system
      let fontValue = try container.decodeIfPresent(String.self, forKey: .fontPreset)
      fontPreset = fontValue.flatMap(FontPreset.init(rawValue:)) ?? .system
      // Adopt the former theme treatment once for pre-v14 documents. Once
      // saved, changing the palette can never change these independent choices.
      let legacyUnderline = [.paperLedger, .moonJade, .inkCinnabar].contains(themeFamily)
      selectionEffect = try container.decodeIfPresent(
        CandidateSelectionEffect.self, forKey: .selectionEffect)
        ?? (legacyUnderline ? .underline : .fullRow)
      cornerStyle = try container.decodeIfPresent(
        CandidateCornerStyle.self, forKey: .cornerStyle) ?? .rounded
      let chineseLayoutValue = try container.decodeIfPresent(
        String.self, forKey: .chineseCandidateLayout)
      let englishLayoutValue = try container.decodeIfPresent(
        String.self, forKey: .englishCandidateLayout)
      if chineseLayoutValue == "expanded" {
        chineseCandidateLayout = .horizontal
      } else if let chineseLayoutValue {
        guard let layout = CandidateLayout(rawValue: chineseLayoutValue) else {
          throw DecodingError.dataCorruptedError(
            forKey: .chineseCandidateLayout,
            in: container,
            debugDescription: "Unknown Chinese candidate layout.")
        }
        chineseCandidateLayout = layout
      } else {
        chineseCandidateLayout = .horizontal
      }
      if englishLayoutValue == "expanded" {
        englishCandidateLayout = .horizontal
      } else if let englishLayoutValue {
        guard let layout = CandidateLayout(rawValue: englishLayoutValue) else {
          throw DecodingError.dataCorruptedError(
            forKey: .englishCandidateLayout,
            in: container,
            debugDescription: "Unknown English candidate layout.")
        }
        englishCandidateLayout = layout
      } else {
        englishCandidateLayout = .horizontal
      }

      // Read and validate the retired field only. Do not write it back or
      // expose it to presentation/runtime code after migrating an old backup.
      let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
      if let value = try legacy.decodeIfPresent(String.self, forKey: .candidateBrowsingMode),
        value != "scrolling_only" && value != "expandable" {
        throw DecodingError.dataCorruptedError(
          forKey: .candidateBrowsingMode, in: legacy,
          debugDescription: "Unknown legacy candidate browsing mode.")
      }
      let decodedPageSize =
        try container.decodeIfPresent(Int.self, forKey: .pageSize) ?? Self.defaultPageSize
      pageSize = Self.pageSizeOptions.contains(decodedPageSize) ? decodedPageSize : Self.defaultPageSize
    }

    private enum LegacyCodingKeys: String, CodingKey {
      case candidateBrowsingMode
    }

    static func clampFontPoint(_ value: Double) -> Double {
      min(maximumFontPoint, max(minimumFontPoint, value))
    }

    static func labelFontPoint(for candidateFontPoint: Double) -> Double {
      max(10, clampFontPoint(candidateFontPoint) * 0.625)
    }

    static func commentFontPoint(for candidateFontPoint: Double) -> Double {
      max(12, clampFontPoint(candidateFontPoint) * 0.75)
    }

    /// Projects an appearance request onto the subset the Host can reload
    /// without rebuilding its active Rime sessions. The Settings model uses
    /// this to avoid claiming a draft is live; the mutation coordinator uses
    /// the same owner to enforce the boundary for direct callers.
    func livePanelProjection(over baseline: Appearance) -> Appearance {
      var result = self
      result.pageSize = baseline.pageSize
      result.chineseCandidateLayout = baseline.chineseCandidateLayout
      result.englishCandidateLayout = baseline.englishCandidateLayout
      return result
    }
  }

  struct Input: Codable, Equatable, Sendable {
    var chineseProfile: LinnetSettingsContract.ChineseProfile
    var emojiEnabled: Bool
    var traditionalChinese: Bool
    var asciiPunctuationDefault: Bool
    var singleCharacterSearchDefault: Bool
    var chineseLearningPolicy: ChineseLearningPolicy
    var pinyinReverseTrigger: PinyinReverseTrigger

    static let `default` = Input(
      chineseProfile: .fullPinyin,
      emojiEnabled: true,
      traditionalChinese: false,
      asciiPunctuationDefault: false,
      singleCharacterSearchDefault: false,
      chineseLearningPolicy: .enhanced,
      pinyinReverseTrigger: .verticalBar
    )

    init(
      chineseProfile: LinnetSettingsContract.ChineseProfile = .fullPinyin,
      emojiEnabled: Bool,
      traditionalChinese: Bool,
      asciiPunctuationDefault: Bool,
      singleCharacterSearchDefault: Bool = false,
      chineseLearningPolicy: ChineseLearningPolicy = .enhanced,
      pinyinReverseTrigger: PinyinReverseTrigger
    ) {
      self.chineseProfile = chineseProfile
      self.emojiEnabled = emojiEnabled
      self.traditionalChinese = traditionalChinese
      self.asciiPunctuationDefault = asciiPunctuationDefault
      self.singleCharacterSearchDefault = singleCharacterSearchDefault
      self.chineseLearningPolicy = chineseLearningPolicy
      self.pinyinReverseTrigger = pinyinReverseTrigger
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      if container.contains(.chineseProfile) {
        chineseProfile = try container.decode(
          LinnetSettingsContract.ChineseProfile.self,
          forKey: .chineseProfile
        )
      } else {
        chineseProfile = Input.default.chineseProfile
      }
      emojiEnabled =
        try container.decodeIfPresent(Bool.self, forKey: .emojiEnabled)
        ?? Input.default.emojiEnabled
      traditionalChinese =
        try container.decodeIfPresent(Bool.self, forKey: .traditionalChinese)
        ?? Input.default.traditionalChinese
      asciiPunctuationDefault =
        try container.decodeIfPresent(Bool.self, forKey: .asciiPunctuationDefault)
        ?? Input.default.asciiPunctuationDefault
      singleCharacterSearchDefault =
        try container.decodeIfPresent(Bool.self, forKey: .singleCharacterSearchDefault)
        ?? Input.default.singleCharacterSearchDefault
      if container.contains(.chineseLearningPolicy) {
        let learningValue = try? container.decode(
          String.self, forKey: .chineseLearningPolicy)
        chineseLearningPolicy =
          learningValue.flatMap(ChineseLearningPolicy.init(rawValue:))
          ?? .disabled
      } else {
        chineseLearningPolicy = Input.default.chineseLearningPolicy
      }
      if container.contains(.pinyinReverseTrigger) {
        let triggerValue = try? container.decode(
          String.self, forKey: .pinyinReverseTrigger)
        pinyinReverseTrigger =
          triggerValue.flatMap(PinyinReverseTrigger.init(rawValue:))
          ?? Input.default.pinyinReverseTrigger
      } else {
        pinyinReverseTrigger = Input.default.pinyinReverseTrigger
      }
    }
  }

  struct English: Codable, Equatable, Sendable {
    var sentenceCapitalization: Bool
    var showIPA: Bool
    var showTranslation: Bool
    var predictionEnabled: Bool
    var learnFromSelections: Bool
    var spaceAddsTrailingSpace: Bool

    static let `default` = English(
      sentenceCapitalization: false,
      showIPA: true,
      showTranslation: true,
      predictionEnabled: true,
      learnFromSelections: true,
      spaceAddsTrailingSpace: true
    )

    init(
      sentenceCapitalization: Bool,
      showIPA: Bool = true,
      showTranslation: Bool = true,
      predictionEnabled: Bool = true,
      learnFromSelections: Bool = true,
      spaceAddsTrailingSpace: Bool = true
    ) {
      self.sentenceCapitalization = sentenceCapitalization
      self.showIPA = showIPA
      self.showTranslation = showTranslation
      self.predictionEnabled = predictionEnabled
      self.learnFromSelections = learnFromSelections
      self.spaceAddsTrailingSpace = spaceAddsTrailingSpace
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      sentenceCapitalization =
        try container.decodeIfPresent(Bool.self, forKey: .sentenceCapitalization)
        ?? English.default.sentenceCapitalization
      showIPA = try container.decodeIfPresent(Bool.self, forKey: .showIPA) ?? true
      showTranslation = try container.decodeIfPresent(Bool.self, forKey: .showTranslation) ?? true
      predictionEnabled =
        try container.decodeIfPresent(Bool.self, forKey: .predictionEnabled) ?? true
      learnFromSelections =
        try container.decodeIfPresent(Bool.self, forKey: .learnFromSelections) ?? true
      spaceAddsTrailingSpace =
        try container.decodeIfPresent(Bool.self, forKey: .spaceAddsTrailingSpace) ?? true
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let storedSchemaVersion =
      try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
    schemaVersion = storedSchemaVersion
    appearance = try container.decodeIfPresent(Appearance.self, forKey: .appearance) ?? .default
    input = try container.decodeIfPresent(Input.self, forKey: .input) ?? .default
    english = try container.decodeIfPresent(English.self, forKey: .english) ?? .default
    shortcuts = container.contains(.shortcuts)
      ? try container.decode(Shortcuts.self, forKey: .shortcuts) : .default
    if !container.contains(.shortcuts), container.contains(.english) {
      let legacy = try container.decode(LegacyShortcuts.self, forKey: .english)
      guard legacy.translationToggleKey == nil || ["tab", "option_return"].contains(legacy.translationToggleKey!),
        legacy.translationCommitKey == nil || ["enter", "space"].contains(legacy.translationCommitKey!)
      else {
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unsupported legacy shortcut"))
      }
      if legacy.translationToggleKey == "option_return" {
        shortcuts.switchSourceTranslation = .init(keyCode: 36, modifiers: Shortcut.option)
      }
      if legacy.translationCommitKey == "space" { shortcuts.commitRawInput = .init(keyCode: 49) }
      if ["pass", "navigate"].contains(legacy.tabBehavior ?? "") { shortcuts.smartComplete = nil }
    }
    guard shortcuts.isValid else {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Conflicting shortcuts"))
    }
    // v4 changes two shipped defaults. Older documents necessarily stored the
    // previous values without recording whether they were explicit, so adopt
    // the new product defaults once; users can still opt back into either value.
    if storedSchemaVersion < 4 {
      if appearance.englishCandidateLayout == .vertical {
        appearance.englishCandidateLayout = .horizontal
      }
      if appearance.pageSize == 5 {
        appearance.pageSize = Appearance.defaultPageSize
      }
    }
    if storedSchemaVersion < 13 {
      // One-time ZIME bilingual layout migration; later explicit choices stay.
      appearance.chineseCandidateLayout = .vertical
      appearance.englishCandidateLayout = .vertical
    }
    if storedSchemaVersion < Self.currentSchemaVersion {
      schemaVersion = Self.currentSchemaVersion
    }
  }

  static let `default` = LinnetSettingsDocument(
    appearance: .default,
    input: .default,
    english: .default
  )

  private struct LegacyShortcuts: Decodable {
    var tabBehavior: String?
    var translationToggleKey: String?
    var translationCommitKey: String?
  }

  func encode(to encoder: Encoder) throws {
    guard shortcuts.isValid else {
      throw EncodingError.invalidValue(shortcuts, .init(codingPath: encoder.codingPath, debugDescription: "Invalid or conflicting shortcuts"))
    }
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(appearance, forKey: .appearance)
    try container.encode(input, forKey: .input)
    try container.encode(english, forKey: .english)
    try container.encode(shortcuts, forKey: .shortcuts)
  }

  /// Clamps values into their bounded contract ranges and pins the schema
  /// version, so nothing the renderer emits can produce invalid Rime.
  func normalized() -> LinnetSettingsDocument {
    var result = self
    result.schemaVersion = Self.currentSchemaVersion
    result.input.chineseProfile = .fullPinyin
    result.appearance.fontPoint = Self.Appearance.clampFontPoint(appearance.fontPoint)
    if !Self.Appearance.pageSizeOptions.contains(result.appearance.pageSize) {
      result.appearance.pageSize = Self.Appearance.defaultPageSize
    }
    return result
  }
}
