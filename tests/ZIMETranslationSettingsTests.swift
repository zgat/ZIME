import Foundation

@main
struct ZIMETranslationSettingsTests {
  @MainActor static func main() async throws {
    // Migrate the actual old JSON shape without silently losing a provider,
    // endpoint or credential revision when the optional display key is added.
    let legacy = Data(#"{"enabled":true,"provider":"compatible","baseURL":"https://example.com/v1","model":"fixture-model","deeplFree":false,"region":"ap-shanghai","revision":"saved-key-revision"}"#.utf8)
    let migrated = try JSONDecoder().decode(ZIMETranslationConfiguration.self, from: legacy)
    precondition(!migrated.showFullAnnotations && migrated.enabled && migrated.model == "fixture-model"
      && migrated.baseURL == "https://example.com/v1" && migrated.region == "ap-shanghai"
      && migrated.revision == "saved-key-revision" && !migrated.deeplFree)
    var displaySaved: ZIMETranslationConfiguration?
    let displayModel = ZIMETranslationSettingsModel(configuration: migrated,
      saveConfiguration: { displaySaved = $0 },
      loadCredentials: { _ in preconditionFailure("display toggle accessed Keychain") },
      saveCredentials: { _, _ in preconditionFailure("display toggle wrote Keychain") },
      deleteCredentials: { _ in preconditionFailure("display toggle deleted credentials") },
      translate: { _, _ in preconditionFailure("display toggle sent an API request") })
    displayModel.configuration.showFullAnnotations = true
    precondition(displayModel.pendingChanges && displaySaved == nil)
    displayModel.discard()
    precondition(!displayModel.pendingChanges && !displayModel.configuration.showFullAnnotations)
    displayModel.configuration.showFullAnnotations = true
    try displayModel.apply()
    precondition(displaySaved?.showFullAnnotations == true && !displayModel.pendingChanges)
    precondition(displaySaved!.hasSameService(as: migrated)
      && displaySaved!.credentialAccount == migrated.credentialAccount,
      "display-only Apply invalidated translations or changed credentials")
    let roundTrip = try JSONDecoder().decode(ZIMETranslationConfiguration.self,
      from: JSONEncoder().encode(displaySaved!))
    precondition(roundTrip == displaySaved!, "annotation preference did not survive saving")
    var saved: [ZIMETranslationConfiguration] = []
    var credentials: [String: ZIMETranslationCredentials] = [:]
    var deletions: [String] = []
    var failsSave = false
    let model = ZIMETranslationSettingsModel(configuration: .init(),
      saveConfiguration: { if failsSave { throw ZIMETranslationError.configuration }; saved.append($0) },
      loadCredentials: { credentials[$0] ?? .init() },
      saveCredentials: { credentials[$1] = $0 },
      deleteCredentials: { deletions.append($0); credentials.removeValue(forKey: $0) },
      translate: { _, _ in
        try? await Task.sleep(nanoseconds: 80_000_000)
        return "fixture"
      })
    precondition(!model.pendingChanges)
    model.configuration.provider = .deepl
    model.identifier = "fixture-key"
    model.configuration.enabled = true
    precondition(model.pendingChanges && saved.isEmpty && credentials.isEmpty)
    model.discard()
    precondition(!model.pendingChanges && model.identifier.isEmpty && saved.isEmpty)
    model.configuration.provider = .deepl
    model.identifier = "fixture-key"
    model.configuration.enabled = true
    try model.apply()
    precondition(!model.pendingChanges && saved.count == 1 && credentials.count == 1)
    model.configuration.deeplFree = false
    model.identifier = "second-key"
    model.testConnection()
    precondition(model.testing)
    model.configuration.deeplFree = true
    try await Task.sleep(nanoseconds: 140_000_000)
    precondition(!model.testing && model.status.isEmpty && model.identifier.isEmpty,
      "old endpoint test repainted the new draft or carried its credentials")
    model.stageCredentialDeletion()
    precondition(model.pendingChanges && deletions.isEmpty && !model.configuration.enabled)
    model.discard()
    precondition(!model.pendingChanges && deletions.isEmpty && model.configuration.enabled)
    model.stageCredentialDeletion()
    try model.apply()
    precondition(!model.pendingChanges && deletions.count == 1 && credentials.isEmpty)
    model.configuration.model = "unsaved"
    failsSave = true
    do { try model.apply(); preconditionFailure("failed save reported success") }
    catch { precondition(model.pendingChanges && !model.status.isEmpty) }
    precondition(ZIMETranslationConfiguration() == ZIMETranslationConfiguration(),
      "default configuration invalidates caches on every keystroke")
    print("ZIME translation Settings: shared draft, save/discard, staged deletion, stale test and failed save: PASS")
  }
}
