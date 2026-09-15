import Carbon
import InputMethodKit

extension SquirrelInputController {
  /// Custom shortcuts take precedence; ordinary modified keys pass through.
  func handleBilingualKeyDown(
    _ event: NSEvent,
    modifiers: NSEvent.ModifierFlags
  ) -> Bool? {
    let shortcutModifiers = modifiers.intersection([.command, .control, .option, .shift])
    let bindings = NSApp.squirrelAppDelegate.activeSettingsDocument?.shortcuts ?? .default
    let action = bindings.action(keyCode: event.keyCode, modifiers: shortcutModifiers.rawValue)
    if event.isARepeat, action == .switchSourceTranslation,
      hasPendingRimeInput || bilingualTranslationMode { return true }
    switch action {
    case .switchSourceTranslation: return toggleTranslationCandidates()
    case .commitRawInput: return submitBilingualRawInput()
    case .smartComplete: return completeBilingualInput()
    case nil: break
    }
    guard bilingualTranslationMode, shortcutModifiers.isEmpty else { return nil }
    return handleTranslationSelection(event)
  }

  private func toggleTranslationCandidates() -> Bool? {
    if bilingualTranslationMode {
      bilingualTranslationMode = false
      bilingualCandidates.reset()
      rimeUpdate()
      return true
    }
    guard hasPendingRimeInput, let source = bilingualSourceSnapshot else { return nil }
    guard source.items.contains(where: {
      !LinnetCandidatePresentation.candidateComment($0.comment).translations.isEmpty
    }) else {
      NSApp.squirrelAppDelegate.panel?.updateStatus(long: "无译文", short: "无译文", controller: self)
      return true
    }
    bilingualTranslationMode = true
    bilingualCandidates.reset()
    rimeUpdate()
    return true
  }

  private func submitBilingualRawInput() -> Bool? {
    guard hasPendingRimeInput, let targetClient = activeClient else { return nil }
    candidateTranslator.cancel()
    bilingualTranslationMode = false
    bilingualSourceSnapshot = nil
    bilingualCandidates.reset()
    commitActiveComposition(to: targetClient)
    return true
  }

  private func completeBilingualInput() -> Bool? {
    if bilingualTranslationMode { return true }
    guard hasPendingRimeInput, inputModeIdentity?.schemaID == "linnet_en",
      inputModeIdentity?.asciiMode == false,
      let source = bilingualSourceSnapshot else { return nil }
    guard let input = rimeAPI.get_input(session).map({ String(cString: $0) }),
      let completed = LinnetCandidatePresentation.smartCompletionText(
        input: input, candidates: source.items.map(\.text), highlighted: source.highlightedItemIndex)
    else { return true }
    // Completion edits marked input only; it neither commits nor learns.
    _ = completed.withCString { rimeAPI.set_input(session, $0) }
    rimeUpdate()
    return true
  }

  private func handleTranslationSelection(_ event: NSEvent) -> Bool? {
    let presented = NSApp.squirrelAppDelegate.panel?.candidateSnapshot
    if event.keyCode == UInt16(kVK_Space) {
      guard hasPendingRimeInput else {
        bilingualTranslationMode = false
        bilingualCandidates.reset()
        return nil
      }
      guard let presented, presented.items.indices.contains(presented.highlightedItemIndex) else { return true }
      _ = selectCandidate(absoluteIndex: presented.items[presented.highlightedItemIndex].absoluteIndex)
      return true
    }
    if let digit = event.charactersIgnoringModifiers?.first?.wholeNumberValue, (1...9).contains(digit) {
      guard let presented,
        let index = LinnetCandidatePresentation.TranslationCandidates.selectionIndex(
          digit: digit, count: presented.items.count) else { return true }
      _ = selectCandidate(absoluteIndex: presented.items[index].absoluteIndex)
      return true
    }
    return navigateTranslationCandidates(event.keyCode, presented: presented)
  }

  private func navigateTranslationCandidates(_ keyCode: UInt16, presented: CandidateSnapshot?) -> Bool? {
    switch keyCode {
    case UInt16(kVK_Escape):
      bilingualTranslationMode = false
      bilingualCandidates.reset()
      rimeUpdate()
      return true
    case UInt16(kVK_PageUp), UInt16(kVK_ANSI_Minus): return page(up: true)
    case UInt16(kVK_PageDown), UInt16(kVK_ANSI_Equal): return page(up: false)
    case UInt16(kVK_LeftArrow), UInt16(kVK_UpArrow), UInt16(kVK_RightArrow), UInt16(kVK_DownArrow):
      guard let presented, !presented.items.isEmpty else { return true }
      let backward = [UInt16(kVK_LeftArrow), UInt16(kVK_UpArrow)].contains(keyCode)
      bilingualCandidates.move(by: backward ? -1 : 1)
      rimeUpdate()
      return true
    default:
      // Includes an unbound Return: restore the unchanged source state before
      // the native raw-input owner processes this key.
      bilingualTranslationMode = false
      bilingualCandidates.reset()
      return nil
    }
  }

  func projectTranslationCandidates(
    from source: CandidateSnapshot
  ) -> CandidateSnapshot {
    let highlightedSource = source.items.indices.contains(source.highlightedItemIndex)
      ? source.items[source.highlightedItemIndex].absoluteIndex : nil
    let page = bilingualCandidates.project(source.items.map {
      let annotation = LinnetCandidatePresentation.candidateComment($0.comment)
      return .init(index: $0.absoluteIndex, text: $0.text,
        translations: annotation.translations, sourceLabel: annotation.sourceLabel)
    }, pageSize: source.pageSize, highlightedSource: highlightedSource)
    let items = page.rows.enumerated().map { index, row in
      CandidateItem(absoluteIndex: row.id, page: page.index, indexOnPage: index,
        text: row.text, comment: row.sourceLabel.map { "\($0):\(row.sourceText)" } ?? row.sourceText,
        selectionLabel: String(index + 1),
        sourceAbsoluteIndex: row.sourceIndex, commitOverride: row.text)
    }
    return .init(
      items: items,
      currentPage: source.currentPage + page.index,
      pageSize: page.size,
      highlightedItemIndex: page.highlightedIndex,
      isLastPage: page.isLast && source.isLastPage)
  }

}
