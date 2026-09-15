import Darwin
import Foundation

@main
struct LinnetSettingsUpdateCheckerStateTests {
  @MainActor static func main() throws {
    let installed = LinnetSettingsContract.ProductIdentity(
      version: "0.1.22", build: 23, revision: String(repeating: "a", count: 40))
    for identifier in ["com.zime.inputmethod.ZIME", "com.zime.inputmethod.ZIME.local-build"] {
      let fixture = try makeBundleFixture(identity: installed, identifier: identifier)
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let checker = LinnetSettingsUpdateChecker(bundle: fixture.settings)
      require(checker.installedIdentity == installed, "Settings did not read the Host identity")
      require(checker.usesManualReleases, "ZIME did not use its manual release policy")
      checker.refreshInstalledIdentity()
      require(checker.installedIdentity == installed, "read-only refresh changed installation identity")

      let hostURL = fixture.settings.bundleURL.deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
      let versionURL = hostURL.appending(path: "Contents/Resources/LinnetRelease/VERSION.json")
      let original = try Data(contentsOf: versionURL)
      try Data("{}".utf8).write(to: versionURL)
      checker.refreshInstalledIdentity()
      require(checker.installedIdentity == nil, "malformed release metadata retained a stale identity")
      try original.write(to: versionURL)
      checker.refreshInstalledIdentity()
      require(checker.installedIdentity == installed, "repaired metadata did not recover")
      try FileManager.default.removeItem(at: versionURL)
      checker.refreshInstalledIdentity()
      require(checker.installedIdentity == nil, "missing release metadata fell back to an unverified version")
    }
    require(ZIMEReleasePolicy.releasesURL.absoluteString == "https://github.com/zgat/ZIME/releases",
      "manual update link belongs to another product")
    print("LinnetSettingsUpdateCheckerStateTests: PASS (read-only identity, repair, manual releases)")
  }

  private struct BundleFixture {
    let root: URL
    let settings: Bundle
  }

  private static func makeBundleFixture(
    identity: LinnetSettingsContract.ProductIdentity,
    identifier: String = "com.zime.inputmethod.ZIME"
  ) throws -> BundleFixture {
    let root = LinnetTestScratch.directory.appending(
      path: "LinnetSettingsUpdateCheckerTests-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    let hostURL = root.appending(path: "Linnet.app", directoryHint: .isDirectory)
    let settingsURL = hostURL.appending(
      path: "Contents/Applications/Settings.app", directoryHint: .isDirectory)
    try writeInfoPlist(
      to: hostURL,
      values: [
        "CFBundleDisplayName": "Linnet",
        "CFBundleExecutable": "Linnet",
        "CFBundleIdentifier": identifier,
        "CFBundleName": "Linnet",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": identity.version,
        "CFBundleVersion": String(identity.build),
        "InputMethodConnectionName": "Linnet_Test_Connection",
      ]
    )
    try writeInfoPlist(
      to: settingsURL,
      values: [
        "CFBundleDisplayName": "Linnet Settings",
        "CFBundleExecutable": "Settings",
        "CFBundleIdentifier": identifier + ".settings",
        "CFBundleName": "Settings",
        "CFBundlePackageType": "APPL",
      ]
    )
    let releaseDirectory = hostURL.appending(
      path: "Contents/Resources/LinnetRelease", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: releaseDirectory, withIntermediateDirectories: true)
    let versionData = try JSONSerialization.data(withJSONObject: [
      "version": identity.version,
      "build": String(identity.build),
      "source": ["candidate_revision": identity.revision],
    ])
    try versionData.write(to: releaseDirectory.appending(path: "VERSION.json"))
    guard let settings = Bundle(url: settingsURL) else { throw FixtureFailure.invalidBundle }
    return .init(root: root, settings: settings)
  }

  private static func writeInfoPlist(
    to bundleURL: URL,
    values: [String: Any]
  ) throws {
    let contents = bundleURL.appending(path: "Contents", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let data = try PropertyListSerialization.data(
      fromPropertyList: values, format: .xml, options: 0)
    try data.write(to: contents.appending(path: "Info.plist"))
  }

  private static func require(
    _ condition: @autoclosure () -> Bool,
    _ message: String
  ) {
    guard condition() else {
      fputs("LinnetSettingsUpdateCheckerStateTests: FAIL: \(message)\n", stderr)
      exit(1)
    }
  }

  private static func fail(_ message: String) -> Never {
    fputs("LinnetSettingsUpdateCheckerStateTests: FAIL: \(message)\n", stderr)
    exit(1)
  }

  private enum FixtureFailure: Error { case invalidBundle }
}
