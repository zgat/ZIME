/// The single projection from a live Rime menu/context into the typed candidate
/// snapshot consumed by the panel. The input controller owns the session; this
/// builder owns current-page bounds and labels.
enum LinnetRimeCandidateSnapshotBuilder {
  static func build(
    context: RimeContext_stdbool,
    labels: [String]
  ) -> SquirrelInputController.CandidateSnapshot? {
    guard let menuPage = LinnetCandidatePresentation.candidateMenuPage(
      currentPage: context.menu.page_no,
      pageSize: context.menu.page_size,
      candidateCount: context.menu.num_candidates,
      highlighted: context.menu.highlighted_candidate_index)
    else { return nil }
    guard menuPage.pageSize > 0 else {
      return .init(
        items: [], currentPage: 0, pageSize: 0, highlightedItemIndex: 0,
        isLastPage: true)
    }
    let currentPage = menuPage.currentPage
    let pageSize = menuPage.pageSize
    let currentCount = menuPage.candidateCount
    let highlightedOnPage = menuPage.highlighted
    let (currentPageStart, overflow) = currentPage.multipliedReportingOverflow(by: pageSize)
    guard !overflow, currentPageStart <= Int.max - currentCount else { return nil }
    var compactItems = [SquirrelInputController.CandidateItem]()
    compactItems.reserveCapacity(currentCount)
    for indexOnPage in 0..<currentCount {
      let candidate = context.menu.candidates[indexOnPage]
      let rawComment = candidate.comment.map { String(cString: $0) } ?? ""
      compactItems.append(.init(
        absoluteIndex: currentPageStart + indexOnPage,
        page: currentPage,
        indexOnPage: indexOnPage,
        text: candidate.text.map { String(cString: $0) } ?? "",
        comment: rawComment,
        selectionLabel: LinnetCandidatePresentation.candidateSelectionLabel(
          at: indexOnPage, labels: labels),
        emphasizesPrimaryText:
          !LinnetCandidatePresentation.candidateComment(rawComment).translations.isEmpty
      ))
    }
    return SquirrelInputController.CandidateSnapshot(
      items: compactItems,
      currentPage: currentPage,
      pageSize: pageSize,
      highlightedItemIndex: highlightedOnPage,
      isLastPage: context.menu.is_last_page)
  }
}
