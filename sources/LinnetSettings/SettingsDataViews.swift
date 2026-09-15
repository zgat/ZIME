//
//  SettingsDataViews.swift
//  Local installation identity, backup history, and diagnostics.
//

import AppKit
import SwiftUI

extension DataTabView {

  var versionSection: some View {
    GroupBox("Version") {
      VStack(alignment: .leading, spacing: 8) {
        LabeledContent("Application") { Text(verbatim: model.productName) }
        LabeledContent("Version") {
          if let installed = updateChecker.installedIdentity {
            Text(verbatim: productIdentityDescription(installed))
          } else {
            Text("Unavailable").foregroundStyle(.secondary)
          }
        }
        if updateChecker.installedIdentity == nil {
          LabeledContent("Core status") { Text("Installation needs repair") }
          Text("Run the Complete installer to restore the installed Core identity.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        LabeledContent("Language data") { Text(languageDataEditionLabel) }
        if updateChecker.usesManualReleases {
          Divider()
          Link("查看 ZIME 的 GitHub 发布版本", destination: ZIMEReleasePolicy.releasesURL)
            .accessibilityIdentifier("settings.data.zimeReleases")
          Text("当前通过 ZIME 发布页手动更新；独立自动更新渠道尚未启用。不会查询或下载上游 Linnet 的更新。")
            .font(.caption).foregroundStyle(.secondary)
        }
        if model.installedPacks.isEmpty {
          LabeledContent("Data status") { Text("Installation needs repair") }
          Text("Reinstall ZIME to restore the required local language data.")
            .font(.caption).foregroundStyle(.secondary)
        } else {
          ForEach(orderedInstalledPacks, id: \.kind.rawValue) { pack in
            LabeledContent(packLabel(pack.kind)) {
              Text(verbatim: packReleaseDescription(
                version: pack.version,
                sequence: pack.sequence))
            }
          }
          Text(
            "Data release is the pack's increasing content sequence, not a Git revision. The version identifies the corresponding published content."
          )
          .font(.caption2)
          .foregroundStyle(.secondary)
        }
      }
      .padding(8)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  func productIdentityDescription(
    _ identity: LinnetSettingsContract.ProductIdentity
  ) -> String {
    "\(identity.version) (\(identity.build))"
  }

  var languageDataEditionLabel: LocalizedStringKey {
    switch model.dataEdition {
    case .some(.full): "Complete offline"
    case .some(.standard): "Recommended"
    case nil: "Unavailable"
    }
  }

  var orderedInstalledPacks: [LinnetDataRegistry.ActivePack] {
    let order: [LinnetPackContract.Kind] = [.chinese, .english, .lts, .extended]
    return model.installedPacks.sorted {
      (order.firstIndex(of: $0.kind) ?? order.count)
        < (order.firstIndex(of: $1.kind) ?? order.count)
    }
  }

  func packLabel(_ kind: LinnetPackContract.Kind) -> LocalizedStringKey {
    switch kind {
    case .chinese: "Chinese data"
    case .english: "English data"
    case .lts: "Chinese grammar model"
    case .extended: "Long-tail data"
    }
  }
  func packReleaseDescription(version: String, sequence: UInt64) -> String {
    "\(version) · \(String(localized: "Data release")) \(sequence)"
  }

}

extension DataTabView {

  var legacyDataDescription: LocalizedStringKey {
    switch model.legacyImportState {
    case .unavailable: "Data services are unavailable."
    case .checking: "Checking detected legacy data…"
    case .none: "No compatible legacy data was found."
    case .compatible: "Compatible legacy data was verified."
    case .failed: "Detected legacy data could not be verified."
    }
  }

  var backupSection: some View {
    GroupBox("Recovery history") {
      VStack(alignment: .leading, spacing: 8) {
        Text("These recovery points are created before data-changing transactions; they are not automatic full backups.")
          .font(.caption).foregroundStyle(.secondary)
        Text("Full backup archives are created only when you choose a backup or export button.")
          .font(.caption2).foregroundStyle(.secondary)
        Picker("Retention", selection: $model.backupRetentionPolicy) {
          ForEach(LinnetSettingsContract.BackupRetentionPolicy.allCases, id: \.self) {
            Text(backupRetentionName($0)).tag($0)
          }
        }
        .accessibilityIdentifier("settings.data.retention")
        .disabled(model.operationActive)
        .onChange(of: model.backupRetentionPolicy) { _ in
          model.saveBackupRetentionPolicy()
        }
        Text(
          "Retention limits apply to verified backups. Existing incomplete or invalid records are not removed automatically."
        )
        .font(.caption).foregroundStyle(.secondary)
        Divider()
        switch model.backupHistory {
        case .unavailable:
          Label(
            SettingsPresentationStatus.backupsUnavailable.text(locale: locale),
            systemImage: "exclamationmark.triangle.fill"
          )
            .foregroundStyle(.red)
            .accessibilityLabel(
              SettingsPresentationStatus.backupsUnavailable.text(locale: locale))
        case .loading:
          Label("Loading backups…", systemImage: "hourglass")
            .foregroundStyle(.secondary)
        case .failed:
          Label(
            SettingsPresentationStatus.backupsUnavailable.text(locale: locale),
            systemImage: "exclamationmark.triangle.fill"
          )
          .foregroundStyle(.red)
        case .loaded(let records) where records.isEmpty:
          Text("No data-operation backups yet.")
            .foregroundStyle(.secondary)
        case .loaded:
          EmptyView()
        }
        ForEach(backupRecords, id: \.transactionDirectory.path) { record in
          HStack {
            Image(systemName: backupSymbol(record.state))
              .foregroundStyle(backupColor(record.state))
              .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
              Text(backupTitle(record.state).text(locale: locale))
                .font(.callout.weight(.medium))
              if let createdAt = record.createdAt {
                Text(verbatim: createdAt.formatted(date: .abbreviated, time: .standard))
                  .font(.caption).foregroundStyle(.secondary)
              } else {
                Text("No completion timestamp")
                  .font(.caption).foregroundStyle(.secondary)
              }
            }
            Spacer()
            Button("Reveal") { model.reveal(record) }
            if case .verified = record.state {
              Button("Restore") { pendingRestore = record }
                .disabled(!model.canRestoreBackup || model.operationActive)
            } else if record.transactionID != nil {
              Button {
                pendingBackupRemoval = record
              } label: {
                Text(verbatim: SettingsBackupRemovalCopy.rowAction(locale: locale))
              }
              .disabled(model.operationActive)
            }
          }
          Divider()
        }
      }.padding(8)
    }
  }

  var backupRecords: [LinnetBackupStore.BackupRecord] {
    switch model.backupHistory {
    case .unavailable: []
    case .loading(let records), .loaded(let records), .failed(let records): records
    }
  }

  var diagnosticsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let diagnostics = model.diagnostics {
        Text(SettingsPresentationStatus.runtime(diagnostics.reachability).text(locale: locale))
          .font(.callout.weight(.medium))
        Text(diagnostics.redactedReport)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
      } else {
        Text("Diagnostics have not been collected.").foregroundStyle(.secondary)
      }
      HStack {
        Button("Refresh") { model.refreshDiagnostics() }
          .disabled(model.operationActive)
        Button("Copy Report") { model.copyDiagnostics() }
          .disabled(model.diagnostics == nil)
        Button("Save…") { model.saveDiagnostics(locale: locale) }
          .disabled(model.diagnostics == nil)
        Spacer()
        Text(
          "Reports contain counts and versions, never words, learning rows, identity, or paths."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
    }
  }

}

private func backupTitle(_ state: LinnetBackupStore.BackupState) -> SettingsPresentationStatus {
  switch state {
  case .verified(let manifest): .backupVerified(backupOperation(manifest.operation))
  case .incomplete: .backupIncomplete
  case .corrupt: .backupInvalid
  }
}

private func backupOperation(_ operation: LinnetBackupStore.BackupOperation) -> SettingsOperationKind {
  switch operation {
  case .applyPersonalData: .apply
  case .importLegacy: .legacy
  case .importPortable: .portableImport
  case .restore: .restore
  case .clearLearning: .clearLearning
  }
}

private func backupRetentionName(_ policy: LinnetSettingsContract.BackupRetentionPolicy) -> LocalizedStringKey {
  switch policy {
  case .keepLatest10: "Keep latest 10 verified backups"
  case .keepLatest30: "Keep latest 30 verified backups"
  case .keepLatest100: "Keep latest 100 verified backups"
  }
}

private func backupSymbol(_ state: LinnetBackupStore.BackupState) -> String {
  switch state {
  case .verified: "checkmark.shield"
  case .incomplete: "clock.badge.exclamationmark"
  case .corrupt: "xmark.shield"
  }
}

private func backupColor(_ state: LinnetBackupStore.BackupState) -> Color {
  switch state {
  case .verified: .green
  case .incomplete: .orange
  case .corrupt: .red
  }
}
