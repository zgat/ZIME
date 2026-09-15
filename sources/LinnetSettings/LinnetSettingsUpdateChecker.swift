import Foundation

/// Read-only installation identity for Settings. Updates are installed through
/// verified ZIME packages, never through the retired upstream catalog service.
@MainActor
final class LinnetSettingsUpdateChecker: ObservableObject {
  @Published private(set) var installedIdentity: LinnetSettingsContract.ProductIdentity?
  private let identityBundle: Bundle

  init(bundle: Bundle = .main) {
    identityBundle = bundle
    refreshInstalledIdentity()
  }

  var usesManualReleases: Bool {
    let host = LinnetSettingsContract.hostBundle(startingAt: identityBundle)
    return ZIMEReleasePolicy.usesManualReleases(bundleIdentifier: host?.bundleIdentifier)
  }

  func refreshInstalledIdentity() {
    installedIdentity = LinnetSettingsContract.productIdentity(startingAt: identityBundle)
  }
}
