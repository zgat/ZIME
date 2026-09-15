import CryptoKit
import Foundation

/// Product distribution identity is separate from retained upstream pack
/// formats. ZIME has not published a compatible automatic-update catalog yet.
enum ZIMEReleasePolicy {
  static let releasesURL = URL(string: "https://github.com/zgat/ZIME/releases")!
  static func usesManualReleases(bundleIdentifier: String?) -> Bool {
    bundleIdentifier == "com.zime.inputmethod.ZIME" ||
      bundleIdentifier == "com.zime.inputmethod.ZIME.local-build"
  }
}

// The transport choice owns the verified pack to reuse or reconstruct.
extension LinnetDataChannel {
  struct Delta: Codable, Equatable, Sendable {
    let baseContentSHA256: String
    let bytes: UInt64
    let sha256: String
    let url: URL

    enum CodingKeys: String, CodingKey {
      case bytes, sha256, url
      case baseContentSHA256 = "base_content_sha256"
    }

    func assetName(for kind: LinnetPackContract.Kind) -> String {
      kind.releaseAssetName.replacingOccurrences(
        of: ".linnetpack", with: "-from-\(baseContentSHA256).linnetdelta")
    }
  }

  struct Artifact: Codable, Equatable, Sendable {
    let kind: LinnetPackContract.Kind
    let version: String
    let sequence: UInt64
    let dataABI: UInt32
    let minCore: String
    let contentSHA256: String
    let bytes: UInt64
    let containerSHA256: String
    let url: URL
    var deltas: [Delta]?

    enum CodingKeys: String, CodingKey {
      case kind, version, sequence, bytes, url, deltas
      case dataABI = "data_abi"
      case minCore = "min_core"
      case contentSHA256 = "content_sha256"
      case containerSHA256 = "container_sha256"
    }

  }
}

/// The replay-resistant selection boundary for independently published
/// language packs. A catalog fetched from the canonical HTTPS endpoint names a
/// complete compatible Standard or Full Active set. Each entry binds the exact
/// immutable release asset before the pack contract validates its contents.
enum LinnetDataChannel {
  static let format = 1
  static let maximumCatalogBytes = 64 * 1024
  /// Core 0.1.1 ships the first public online catalog contract at data-4.
  /// A mirror is an untrusted transport, so a fresh install must reject older
  /// catalogs before it creates a transaction or downloads any pack.
  static let minimumCatalogSequence: UInt64 = 4

  enum Failure: LocalizedError, Equatable {
    case invalidCatalog(String)
    case invalidArtifact(String)
    case completeRepairRequired

    var errorDescription: String? {
      switch self {
      case .invalidCatalog(let detail): "Invalid Linnet data catalog: \(detail)."
      case .invalidArtifact(let detail): "Invalid Linnet data artifact: \(detail)."
      case .completeRepairRequired: "A complete language-data repair needs your confirmation."
      }
    }
  }

  struct ActivationSet: Codable, Equatable, Sendable {
    let edition: LinnetDataRegistry.Edition
    let packs: [Artifact]

  }

  struct Core: Codable, Equatable, Sendable {
    let version: String
    let build: UInt64
    let revision: String
    let bytes: UInt64
    let sha256: String
    let packageURL: URL
    let releaseURL: URL

    enum CodingKeys: String, CodingKey {
      case version, build, revision, bytes, sha256
      case packageURL = "package_url"
      case releaseURL = "release_url"
    }

  }

  struct Catalog: Codable, Equatable, Sendable {
    let format: Int
    let sequence: UInt64
    let core: Core
    let activationSets: [ActivationSet]

    enum CodingKeys: String, CodingKey {
      case format, sequence, core
      case activationSets = "activation_sets"
    }

  }

  struct Verified: Equatable, Sendable {
    let catalog: Catalog
    let digest: String
  }

  static func verify(_ data: Data, coreVersion: String) throws -> Verified {
    let verified = try verifyPublished(data)
    guard verified.catalog.activationSets.allSatisfy({ set in
      set.packs.allSatisfy {
        LinnetPackContract.supportsCore(required: $0.minCore, actual: coreVersion)
      }
    }) else { throw Failure.invalidCatalog("Core compatibility") }
    return verified
  }

  /// Update checks must be able to authenticate a newer Core even when its
  /// accompanying data no longer supports the installed Core. Mutation paths
  /// use `verify(_:coreVersion:)` and retain the stricter compatibility gate.
  static func verifyPublished(_ data: Data) throws -> Verified {
    guard !data.isEmpty, data.count <= maximumCatalogBytes else {
      throw Failure.invalidCatalog("size")
    }
    let catalog: Catalog
    do {
      catalog = try JSONDecoder().decode(Catalog.self, from: data)
    } catch {
      throw Failure.invalidCatalog("JSON")
    }
    let canonical = try canonicalCatalogData(catalog)
    try validate(catalog, minimumSequence: minimumCatalogSequence)
    return .init(catalog: catalog, digest: sha256(canonical))
  }

  static func canonicalCatalogData(_ catalog: Catalog) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(catalog)
  }

  private static func validate(
    _ catalog: Catalog, minimumSequence: UInt64
  ) throws {
    guard catalog.format == format, catalog.sequence >= minimumSequence,
      catalog.activationSets.count == 2, validate(catalog.core)
    else { throw Failure.invalidCatalog("identity") }
    let expectedEditions: Set<LinnetDataRegistry.Edition> = [.standard, .full]
    guard Set(catalog.activationSets.map(\.edition)) == expectedEditions else {
      throw Failure.invalidCatalog("edition set")
    }
    for set in catalog.activationSets {
      let required: Set<LinnetPackContract.Kind> = set.edition == .full
        ? [.chinese, .english, .lts, .extended]
        : [.chinese, .english, .lts]
      guard Set(set.packs.map(\.kind)) == required else {
        throw Failure.invalidCatalog("pack set")
      }
      guard let chinese = set.packs.first(where: { $0.kind == .chinese }) else {
        throw Failure.invalidCatalog("Chinese")
      }
      for pack in set.packs {
        guard isSafeIdentifier(pack.version), pack.sequence > 0, pack.dataABI > 0,
          isSHA256(pack.contentSHA256), isSHA256(pack.containerSHA256), pack.bytes > 0,
          pack.bytes <= LinnetPackContract.maximumContainerBytes,
          LinnetPackContract.supportsCore(
            required: pack.minCore, actual: catalog.core.version),
          isImmutableReleaseURL(
            pack.url, kind: pack.kind, catalogSequence: catalog.sequence)
        else { throw Failure.invalidCatalog("pack \(pack.kind.rawValue)") }
        try validateDeltas(pack, catalogSequence: catalog.sequence)
        if pack.kind == .lts || pack.kind == .extended {
          guard pack.dataABI == chinese.dataABI else {
            throw Failure.invalidCatalog("Chinese ABI")
          }
        }
      }
    }
  }

  private static func validateDeltas(_ pack: Artifact, catalogSequence: UInt64) throws {
    guard let deltas = pack.deltas else { return }
    guard !deltas.isEmpty, deltas.count <= 16,
      Set(deltas.map(\.baseContentSHA256)).count == deltas.count else {
      throw Failure.invalidCatalog("delta base set")
    }
    for delta in deltas {
      guard isSHA256(delta.baseContentSHA256), isSHA256(delta.sha256),
        delta.baseContentSHA256 != pack.contentSHA256,
        delta.bytes > 0, delta.bytes <= LinnetPackContract.maximumContainerBytes,
        delta.url.scheme == "https", delta.url.host?.lowercased() == "github.com",
        delta.url.query == nil, delta.url.fragment == nil,
        delta.url.path == "/Ares-X/Linnet/releases/download/data-\(catalogSequence)/" + delta.assetName(for: pack.kind)
      else { throw Failure.invalidCatalog("delta \(pack.kind.rawValue)") }
    }
  }

  private static func validate(_ core: Core) -> Bool {
    guard LinnetPackContract.supportsCore(required: core.version, actual: core.version),
      core.build > 0, isRevision(core.revision),
      core.bytes > 0, core.bytes <= LinnetPackContract.maximumContainerBytes,
      isSHA256(core.sha256), core.packageURL.query == nil,
      core.packageURL.fragment == nil, core.releaseURL.query == nil,
      core.releaseURL.fragment == nil
    else { return false }
    let releaseTag = "core-v\(core.version)"
    return core.packageURL.scheme == "https"
      && core.packageURL.host?.lowercased() == "github.com"
      && core.packageURL.path
        == "/Ares-X/Linnet/releases/download/\(releaseTag)/Linnet-\(core.version)-arm64-Core-community-beta.pkg"
      && core.releaseURL.scheme == "https"
      && core.releaseURL.host?.lowercased() == "github.com"
      && core.releaseURL.path == "/Ares-X/Linnet/releases/tag/\(releaseTag)"
  }

  private static func isImmutableReleaseURL(
    _ url: URL,
    kind: LinnetPackContract.Kind,
    catalogSequence: UInt64
  ) -> Bool {
    guard url.scheme == "https", url.host?.lowercased() == "github.com",
      url.query == nil, url.fragment == nil, url.pathExtension == "linnetpack"
    else { return false }
    let prefix = "/Ares-X/Linnet/releases/download/data-\(catalogSequence)/"
    return url.path == prefix + kind.releaseAssetName
  }

  private static func isSafeIdentifier(_ value: String) -> Bool {
    guard !value.isEmpty, value.count <= 128 else { return false }
    return value.unicodeScalars.allSatisfy {
      CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        .contains($0)
    }
  }

  private static func isSHA256(_ value: String) -> Bool {
    value.count == 64 && value.unicodeScalars.allSatisfy {
      CharacterSet(charactersIn: "0123456789abcdef").contains($0)
    }
  }

  private static func isRevision(_ value: String) -> Bool {
    value.count == 40 && value.unicodeScalars.allSatisfy {
      CharacterSet(charactersIn: "0123456789abcdef").contains($0)
    }
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
// Registry admission owns receipt migration at begin/prepare; storage reads
// never rewrite an older receipt or infer an unrecorded pack snapshot.
extension LinnetDataRegistry {
  private static let dataChannelReceiptFormat = "io.github.ares-x.linnet.data-channel-receipt.v1"

  func validDataChannelReceipt(_ receipt: DataChannelReceipt?) -> Bool {
    guard let receipt else { return true }
    return receipt.format == Self.dataChannelReceiptFormat
      && receipt.sequence > 0 && Self.isSHA256(receipt.digest)
      && receipt.packSnapshotDigest.map(Self.isSHA256) != false
  }

}
