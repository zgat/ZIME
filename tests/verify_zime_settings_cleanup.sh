#!/usr/bin/env bash
# Source contract for the removed multi-page candidate feature, not UI testing.
set -euo pipefail
cd "$(dirname "$0")/.."

if rg -n 'candidateExpansion|CandidateBrowsingMode|isExpanded|canExpand|usesGridLayout|expandedCandidateRange|candidateGridColumns|reservesExpandedDetail|candidate_expansion|case disclosure|case .*expand, collapse' \
    sources/SquirrelPanel.swift sources/SquirrelPanel+CandidatePresentation.swift \
    sources/SquirrelView.swift sources/SquirrelView+CandidateDrawing.swift \
    sources/SquirrelTheme.swift sources/LinnetCandidatePresentation.swift \
    sources/LinnetCandidateAccessibility.swift sources/LinnetRimeCandidateSnapshotBuilder.swift \
    sources/SquirrelInputController.swift sources/SquirrelInputController+RimeSession.swift \
    sources/ZIMECandidateTranslator.swift sources/LinnetSettings/LinnetSettingsAppearancePreview.swift \
    sources/LinnetSettings/LinnetSettingsProjectionRenderer.swift plugins/smart_english data/squirrel.yaml; then
  echo 'FAIL: retired candidate expansion code returned' >&2
  exit 1
fi
if rg -n 'Candidate browsing|Scrolling only|Expandable|Show more candidates|Show fewer candidates|settings.appearance.browsing' \
    sources/LinnetSettings/SettingsViews.swift resources/Localizable.xcstrings; then
  echo 'FAIL: retired candidate browsing control returned' >&2
  exit 1
fi
rg -Fq '.disclosureGroupStyle(LinnetSettingsDisclosureStyle())' sources/LinnetSettings/SettingsViews.swift
rg -Fq '.contentShape(Rectangle())' sources/LinnetSettings/LinnetSettingsPage.swift
rg -Fq '.buttonStyle(.plain)' sources/LinnetSettings/LinnetSettingsPage.swift
rg -Fq 'LegacyCodingKeys' sources/LinnetSettings/LinnetSettingsDocument.swift
echo 'ZIME settings cleanup: PASS'
