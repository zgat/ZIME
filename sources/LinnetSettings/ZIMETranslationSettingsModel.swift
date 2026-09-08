// SPDX-License-Identifier: GPL-3.0-or-later
import Combine
import Foundation

/// Translation drafts participate in the same Apply/Discard/close contract as
/// other settings. Credentials remain memory-only until an explicit Apply.
@MainActor
final class ZIMETranslationSettingsModel: ObservableObject {
  @Published var configuration: ZIMETranslationConfiguration {
    didSet {
      if !oldValue.hasSameService(as: configuration) { invalidateTest() }
      if oldValue.credentialAccount != configuration.credentialAccount {
        identifier = ""
        secret = ""
        deletesCredentials = false
      }
    }
  }
  @Published var identifier = "" { didSet { invalidateTest() } }
  @Published var secret = "" { didSet { invalidateTest() } }
  @Published private(set) var status = ""
  @Published private(set) var testing = false
  @Published private(set) var deletesCredentials = false
  private var baseline: ZIMETranslationConfiguration
  private var testTask: Task<Void, Never>?
  private var generation = UUID()
  private let saveConfiguration: (ZIMETranslationConfiguration) throws -> Void
  private let loadCredentials: (String) throws -> ZIMETranslationCredentials
  private let saveCredentials: (ZIMETranslationCredentials, String) throws -> Void
  private let deleteCredentials: (String) throws -> Void
  private let translate: (ZIMETranslationConfiguration, ZIMETranslationCredentials) async throws -> String

  init(configuration: ZIMETranslationConfiguration = .load(),
    saveConfiguration: @escaping (ZIMETranslationConfiguration) throws -> Void = { try $0.save() },
    loadCredentials: @escaping (String) throws -> ZIMETranslationCredentials = { try .load(account: $0) },
    saveCredentials: @escaping (ZIMETranslationCredentials, String) throws -> Void = { try $0.save(account: $1) },
    deleteCredentials: @escaping (String) throws -> Void = { try ZIMETranslationCredentials.delete(account: $0) },
    translate: @escaping (ZIMETranslationConfiguration, ZIMETranslationCredentials) async throws -> String = {
      try await ZIMETranslationHTTP.translate(configuration: $0, credentials: $1, text: "hello", chinese: false)
    }
  ) {
    self.configuration = configuration
    baseline = configuration
    self.saveConfiguration = saveConfiguration
    self.loadCredentials = loadCredentials
    self.saveCredentials = saveCredentials
    self.deleteCredentials = deleteCredentials
    self.translate = translate
  }

  var pendingChanges: Bool {
    configuration != baseline || !identifier.isEmpty || !secret.isEmpty || deletesCredentials
  }

  private func credentials() throws -> ZIMETranslationCredentials {
    let value = identifier.isEmpty && secret.isEmpty
      ? try loadCredentials(configuration.credentialAccount)
      : ZIMETranslationCredentials(identifier: identifier.trimmingCharacters(in: .whitespacesAndNewlines),
          secret: secret.trimmingCharacters(in: .whitespacesAndNewlines))
    _ = try ZIMETranslationHTTP.request(configuration: configuration, credentials: value, text: "hello", chinese: false)
    return value
  }

  func validate() throws {
    guard pendingChanges else { return }
    do {
      let serviceChanged = !configuration.hasSameService(as: baseline)
      let credentialsChanged = !identifier.isEmpty || !secret.isEmpty
      if !deletesCredentials && (credentialsChanged || (configuration.enabled && serviceChanged)) {
        _ = try credentials()
      }
    } catch { status = error.localizedDescription; throw error }
  }

  func apply() throws {
    guard pendingChanges else { return }
    do {
      try validate()
      if deletesCredentials {
        try deleteCredentials(configuration.credentialAccount)
      } else if !identifier.isEmpty || !secret.isEmpty {
        try saveCredentials(credentials(), configuration.credentialAccount)
      }
      var submitted = configuration
      if !configuration.hasSameService(as: baseline) || deletesCredentials || !identifier.isEmpty || !secret.isEmpty {
        submitted.revision = UUID().uuidString
      }
      try saveConfiguration(submitted)
      configuration = submitted
      baseline = submitted
      identifier = ""
      secret = ""
      deletesCredentials = false
      status = "翻译设置已保存。"
    } catch {
      status = error.localizedDescription
      throw error
    }
  }

  func discard() {
    configuration = baseline
    identifier = ""
    secret = ""
    deletesCredentials = false
    invalidateTest()
  }

  func stageCredentialDeletion() {
    configuration.enabled = false
    identifier = ""
    secret = ""
    deletesCredentials = true
    status = "应用更改后删除此服务密钥；撤销可取消。"
  }

  private func invalidateTest() {
    generation = UUID()
    testTask?.cancel()
    testTask = nil
    testing = false
    status = ""
  }

  func testConnection() {
    invalidateTest()
    do {
      let credential = try credentials()
      let selected = configuration
      let token = generation
      testing = true
      testTask = Task { [weak self, translate] in
        do {
          let result = try await translate(selected, credential)
          guard let self, generation == token, !Task.isCancelled else { return }
          status = "\(selected.provider.title)：hello → \(result)"
          testing = false
          testTask = nil
        } catch {
          guard let self, generation == token else { return }
          status = error.localizedDescription
          testing = false
          testTask = nil
        }
      }
    } catch { status = error.localizedDescription }
  }
}
