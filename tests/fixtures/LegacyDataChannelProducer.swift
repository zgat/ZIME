// SPDX-License-Identifier: GPL-3.0-or-later
// Historical upstream update producers, retained ONLY to construct legacy
// transaction/receipt fixtures for runtime recovery and pack-format regression.
// Not built into ZIME, Settings, or any shipping command-line product.
// Extracted during 0.1.22 cleanup; runtime readers/recovery stay in sources/.
import CryptoKit
import Foundation

extension LinnetDataChannel {
  enum PackTransfer: Equatable, Sendable {
    case current(LinnetDataRegistry.ActivePack)
    case delta(Delta, base: LinnetDataRegistry.ActivePack)
    case complete
    case requiresCompleteRepair
  }

  enum CoreAvailability: Equatable, Sendable {
    case current
    case available
  }

  enum UpdateAvailability: Equatable, Sendable {
    case current
    case localDataAhead
    case core(Core)
    case languageData([LanguageDataUpdate])
  }

  struct LanguageDataUpdate: Equatable, Sendable {
    let kind: LinnetPackContract.Kind
    let installedVersion: String?
    let installedSequence: UInt64?
    let availableVersion: String
    let availableSequence: UInt64
  }

  /// Pack sequence owns both immutable activation sets, not the independently
  /// changing Core pointer. The full Catalog digest remains its byte identity.
  static func packSnapshotDigest(_ catalog: Catalog) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let packsOnly = catalog.activationSets.map { set in
      ActivationSet(edition: set.edition, packs: set.packs.map { pack in
        var identity = pack
        identity.deltas = nil
        return identity
      })
    }
    return try SHA256.hash(data: encoder.encode(packsOnly)).map { String(format: "%02x", $0) }.joined()
  }

  /// The canonical catalog binds the complete downloaded container before the
  /// pack contract inspects its manifest and payload.
  static func verifyDownloadedArtifact(bytes: UInt64, sha256: String, at file: URL) throws {
    guard bytes > 0,
      bytes <= LinnetPackContract.maximumContainerBytes
    else { throw Failure.invalidArtifact("size") }
    let values = try file.resourceValues(
      forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
    guard values.isRegularFile == true, values.isSymbolicLink != true,
      (attributes[.size] as? NSNumber)?.uint64Value == bytes
    else { throw Failure.invalidArtifact("size") }
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
      hasher.update(data: chunk)
    }
    let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
    guard digest == sha256 else {
      throw Failure.invalidArtifact("SHA-256")
    }
  }
}

extension LinnetDataChannel.Artifact {
  func matches(_ pack: LinnetDataRegistry.ActivePack) -> Bool {
    kind == pack.kind
      && version == pack.version
      && sequence == pack.sequence
      && dataABI == pack.dataABI
      && minCore == pack.minCore
      && contentSHA256 == pack.contentSHA256
  }

  /// Normal updates may reuse or reconstruct; only a first baseline or an
  /// explicit new repair operation can authorize a complete download.
  func transfer(
    from installed: LinnetDataRegistry.ActivePack?, allowCompleteRepair: Bool = false
  ) -> LinnetDataChannel.PackTransfer {
    guard let installed else { return .complete }
    if matches(installed) { return .current(installed) }
    if allowCompleteRepair { return .complete }
    guard installed.kind == kind, installed.dataABI == dataABI,
      let delta = deltas?.first(where: { $0.baseContentSHA256 == installed.contentSHA256 })
    else { return .requiresCompleteRepair }
    return .delta(delta, base: installed)
  }
}

extension LinnetDataChannel.ActivationSet {
  enum UpdateSelection {
    case current
    case localAhead
    case available([LinnetDataChannel.Artifact])
    case conflict(LinnetPackContract.Kind)
  }

  /// A catalog describes one atomic set, not a menu of independently mixable
  /// packs. Never advertise or download a set that regresses any local pack.
  func updateSelection(installedPacks: [LinnetDataRegistry.ActivePack]) -> UpdateSelection {
    var updates: [LinnetDataChannel.Artifact] = []
    var localAhead = false
    for artifact in packs {
      if let installed = installedPacks.first(where: { $0.kind == artifact.kind }) {
        if artifact.sequence < installed.sequence {
          localAhead = true
          continue
        }
        if artifact.sequence == installed.sequence {
          guard artifact.matches(installed) else {
            return .conflict(artifact.kind)
          }
          continue
        }
      }
      updates.append(artifact)
    }
    if localAhead { return .localAhead }
    return updates.isEmpty ? .current : .available(updates)
  }
}

extension LinnetDataChannel.Catalog {
  func activationSet(for edition: LinnetDataRegistry.Edition) -> LinnetDataChannel.ActivationSet? {
    activationSets.first { $0.edition == edition }
  }

  func updateAvailability(
    currentVersion: String,
    currentBuild: UInt64,
    currentRevision: String,
    edition: LinnetDataRegistry.Edition?,
    installedPacks: [LinnetDataRegistry.ActivePack]
  ) throws -> LinnetDataChannel.UpdateAvailability {
    if core.availability(
      currentVersion: currentVersion,
      currentBuild: currentBuild,
      currentRevision: currentRevision)
      == .available {
      return .core(core)
    }
    guard let edition, let selected = activationSet(for: edition) else { return .current }
    let artifacts: [LinnetDataChannel.Artifact]
    switch selected.updateSelection(installedPacks: installedPacks) {
    case .current: return .current
    case .localAhead: return .localDataAhead
    case .available(let updates): artifacts = updates
    case .conflict(let kind): throw LinnetDataChannel.Failure.invalidCatalog("conflicting pack sequence: \(kind.rawValue)")
    }
    let updates = artifacts.map { artifact -> LinnetDataChannel.LanguageDataUpdate in
      let installed = installedPacks.first {
        $0.kind == artifact.kind
      }
      return .init(
        kind: artifact.kind,
        installedVersion: installed?.version,
        installedSequence: installed?.sequence,
        availableVersion: artifact.version,
        availableSequence: artifact.sequence)
    }
    return .languageData(updates)
  }
}

extension LinnetDataChannel.Core {
  func availability(
    currentVersion: String,
    currentBuild: UInt64,
    currentRevision: String
  ) -> LinnetDataChannel.CoreAvailability {
    if version == currentVersion {
      return build > currentBuild || (build == currentBuild && revision != currentRevision)
        ? .available : .current
    }
    return LinnetPackContract.supportsCore(required: currentVersion, actual: version)
      && !LinnetPackContract.supportsCore(required: version, actual: currentVersion)
      ? .available : .current
  }
}

extension LinnetDataRegistry {
  func receiptForCatalog(
    _ catalog: LinnetDataChannel.Verified
  ) throws -> DataChannelReceipt {
    guard catalog.catalog.sequence > 0, Self.isSHA256(catalog.digest) else {
      throw Failure.invalidActiveState
    }
    return .init(format: "io.github.ares-x.linnet.data-channel-receipt.v1",
      sequence: catalog.catalog.sequence, digest: catalog.digest,
      packSnapshotDigest: try LinnetDataChannel.packSnapshotDigest(catalog.catalog))
  }

  func validateDataChannelReceipt(
    _ candidate: DataChannelReceipt, artifacts: [LinnetDataChannel.Artifact]
  ) throws {
    guard validDataChannelReceipt(candidate) else { throw Failure.invalidActiveState }
    let committed = try committedActiveState()
    guard let previous = committed.acceptedCatalog else { return }
    guard candidate.sequence >= previous.sequence else { throw Failure.staleDataChannel }
    switch (previous.packSnapshotDigest, candidate.packSnapshotDigest) {
    case (.some(let accepted), .some(let proposed)):
      guard candidate.sequence > previous.sequence || accepted == proposed else {
        throw Failure.staleDataChannel
      }
    case (.some, .none):
      throw Failure.staleDataChannel
    case (.none, .none):
      // An already-downloading old transaction retains the shipped contract.
      guard candidate.sequence > previous.sequence || candidate.digest == previous.digest else {
        throw Failure.staleDataChannel
      }
    case (.none, .some):
      // Old receipts bound the entire Catalog. Only exact committed pack
      // identities authorize same-sequence migration. Historical uninstalled
      // editions are unknown; the current Catalog authenticates their artifacts.
      if candidate.sequence == previous.sequence {
        guard committed.packs.allSatisfy({ installed in
          artifacts.contains { $0.matches(installed) }
        }) else { throw Failure.staleDataChannel }
      }
    }
  }

  func committedActiveState() throws -> ActiveState {
    let active = try loadActiveStateDocument().state
    if active.publication == .committed { return active }
    guard let transactionID = active.transactionID else { throw Failure.invalidActiveState }
    let previous = transactionsDirectory.appending(
      path: transactionID.uuidString, directoryHint: .isDirectory).appending(
      path: "language-active", directoryHint: .isDirectory)
    let previousState = try loadActiveStateDocument(at: previous).state
    guard previousState.publication == .committed else { throw Failure.invalidActiveState }
    return previousState
  }

  func validatedPreparationRecord(
    update: DataChannelUpdateTransaction,
    transaction: URL,
    snapshot: RuntimeSnapshot,
    packs: [ActivePack],
    edition: Edition
  ) throws -> LanguageTransactionRecord {
    guard update.downloadDirectory.standardizedFileURL
      == downloadsDirectory.appending(
        path: update.transactionID.uuidString, directoryHint: .isDirectory).standardizedFileURL,
      let record = validatedLanguageTransaction(at: transaction, now: Date()),
      record.phase == .downloading,
      record.baseRevision == snapshot.activeRevision,
      record.edition == edition,
      record.artifacts.count == packs.count,
      record.artifacts.allSatisfy({ artifact in
        packs.contains(where: { artifact.matches($0) })
      })
    else { throw Failure.invalidActiveState }
    try validateDataChannelReceipt(record.catalog, artifacts: record.artifacts)
    return record
  }

  struct ActivationCandidate: Equatable, Sendable {
    let transactionID: UUID
    let directory: URL
    let expectedActiveRevision: ActiveRevision
  }

  struct DataChannelUpdateTransaction: Equatable, Sendable {
    let transactionID: UUID
    let downloadDirectory: URL
  }

  /// The Registry owns catalog validation so it can fail closed against
  /// the Core version that is actually running, rather than a Settings label.
  func verifyDataChannel(_ data: Data) throws -> LinnetDataChannel.Verified {
    try LinnetDataChannel.verify(data, coreVersion: coreVersion)
  }

  func verifiedInstalledPack(at directory: URL) throws -> ActivePack {
    let installed = try verifiedInstalledManifest(at: directory)
    let manifestSHA256 = Self.sha256(installed.manifestData)
    let expectedPack = Self.activePack(
      from: installed.manifest, manifestSHA256: manifestSHA256)
    guard directory.standardizedFileURL == rootDirectory.appending(
      path: expectedPack.relativePath, directoryHint: .isDirectory).standardizedFileURL
    else { throw Failure.invalidActiveState }
    return expectedPack
  }

  func makeImmutable(_ directory: URL) throws {
    let contents = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    for entry in contents {
      let values = try entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      guard values.isSymbolicLink != true else { throw Failure.unsafePath(entry.path) }
      if values.isDirectory == true {
        try makeImmutable(entry)
      } else {
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: entry.path)
      }
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
  }

  /// Manifest encodings differ between the initial PKG and signed transport.
  /// Stable payload identity and compatibility metadata, not the envelope
  /// digest, own same-sequence idempotence.
  static func sameImmutablePack(_ lhs: ActivePack, _ rhs: ActivePack) -> Bool {
    lhs.packID == rhs.packID
      && lhs.kind == rhs.kind
      && lhs.version == rhs.version
      && lhs.sequence == rhs.sequence
      && lhs.dataABI == rhs.dataABI
      && lhs.contentSHA256 == rhs.contentSHA256
      && lhs.minCore == rhs.minCore
      && lhs.requirements == rhs.requirements
      && lhs.relativePath == rhs.relativePath
  }

  func beginDataChannelUpdate(
    accepting catalog: LinnetDataChannel.Verified,
    edition: Edition
  ) throws -> DataChannelUpdateTransaction {
    try prepareMutableDirectories()
    let receipt = try receiptForCatalog(catalog)
    guard let set = catalog.catalog.activationSet(for: edition) else {
      throw Failure.invalidActiveState
    }
    try validateDataChannelReceipt(receipt, artifacts: set.packs)
    let snapshot = try runtimeSnapshot(reconcilingStorage: false)
    switch set.updateSelection(installedPacks: snapshot.state.packs) {
    case .localAhead: throw Failure.staleDataChannel
    case .conflict: throw Failure.invalidActiveState
    case .current, .available: break
    }
    let transactionID = UUID()
    let directory = transactionsDirectory.appending(path: transactionID.uuidString, directoryHint: .isDirectory)
    let download = downloadsDirectory.appending(path: transactionID.uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    do {
      try writeJSON(
        LanguageTransactionRecord(
          format: Self.transactionFormat,
          transactionID: transactionID,
          createdAt: Date().timeIntervalSince1970,
          catalog: receipt,
          edition: edition,
          artifacts: set.packs,
          baseRevision: snapshot.activeRevision,
          phase: .downloading,
          candidateRevision: nil),
        to: directory.appending(path: Self.languageTransactionMarkerName))
      try FileManager.default.createDirectory(at: download, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    } catch {
      try? FileManager.default.removeItem(at: download)
      try? FileManager.default.removeItem(at: directory)
      throw error
    }
    return .init(transactionID: transactionID, downloadDirectory: download)
  }

  /// The only explicit cancellation owner for both downloading and prepared
  /// language transactions. Live prepared candidates remain recovery-owned.
  func cancelDataChannelUpdate(transactionID: UUID) throws {
    let directory = transactionsDirectory.appending(
      path: transactionID.uuidString, directoryHint: .isDirectory)
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    guard validatedLanguageTransaction(at: directory, now: Date()) != nil else {
      throw Failure.invalidActiveState
    }
    let active = try loadActiveStateDocument().state
    if active.transactionID == transactionID, active.publication == .prepared { return }
    try removeOwnedDownloadDirectory(transactionID: transactionID)
    try FileManager.default.removeItem(at: directory)
    try? reconcileLanguageStorage(activeState: active)
  }

  /// Catalog-selected download authentication and immutable pack staging.
  /// Full or differential transport must reconstruct the same manifest/files.
  func verifyAndStagePack(
    package: URL, artifact: LinnetDataChannel.Artifact,
    transfer: LinnetDataChannel.PackTransfer
  ) throws -> ActivePack {
    try prepareMutableDirectories()
    let resolvedPackage = package.resolvingSymlinksInPath().standardizedFileURL
    let resolvedDownloads = downloadsDirectory.resolvingSymlinksInPath().standardizedFileURL
    let downloadOwner = resolvedPackage.deletingLastPathComponent()
    guard downloadOwner == resolvedDownloads
      || downloadOwner.deletingLastPathComponent() == resolvedDownloads,
      Self.isSecureOwnedDirectory(downloadOwner) else {
      throw Failure.unsafePath(package.path)
    }
    let values = try resolvedPackage.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure.unsafePath(package.path) }
    switch transfer {
    case .complete:
      try LinnetDataChannel.verifyDownloadedArtifact(
        bytes: artifact.bytes, sha256: artifact.containerSHA256, at: resolvedPackage)
    case .delta(let delta, let base):
      guard artifact.deltas?.contains(delta) == true, Self.validPackIdentity(base),
        base.kind == artifact.kind, base.contentSHA256 == delta.baseContentSHA256 else {
        throw Failure.invalidActiveState
      }
      try LinnetDataChannel.verifyDownloadedArtifact(
        bytes: delta.bytes, sha256: delta.sha256, at: resolvedPackage)
    case .current, .requiresCompleteRepair:
      throw Failure.invalidActiveState
    }
    let kindRoot = packsDirectory.appending(path: artifact.kind.rawValue, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: kindRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    guard Self.isSecureOwnedDirectory(kindRoot) else { throw Failure.unsafePath(kindRoot.path) }
    let identity = Self.packIdentity(sequence: artifact.sequence, version: artifact.version)
    let final = kindRoot.appending(path: identity, directoryHint: .isDirectory)
    if FileManager.default.fileExists(atPath: final.path) {
      let installed = try verifiedInstalledPack(at: final)
      guard artifact.matches(installed) else { throw Failure.invalidActiveState }
      return installed
    }

    let partial = kindRoot.appending(path: ".\(identity).partial-\(UUID().uuidString)", directoryHint: .isDirectory)
    do {
      let manifest: LinnetPackContract.Manifest, manifestData: Data
      switch transfer {
      case .delta(_, let base):
        let baseRoot = rootDirectory.appending(path: base.relativePath, directoryHint: .isDirectory)
        let baseManifest = try readOwnedFile(baseRoot.appending(path: "manifest.json"))
        guard Self.sha256(baseManifest) == base.manifestSHA256 else { throw Failure.invalidActiveState }
        try LinnetDirectoryDelta.apply(base: baseRoot, delta: resolvedPackage, output: partial)
        let staged = try verifiedInstalledManifest(at: partial)
        (manifest, manifestData) = (staged.manifest, staged.manifestData)
      case .complete:
        try FileManager.default.createDirectory(
          at: partial, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let staged = try LinnetPackContract.verify(
          package: resolvedPackage, coreVersion: self.coreVersion, extractingTo: partial)
        (manifest, manifestData) = (staged.manifest, staged.manifestData)
        try manifestData.write(to: partial.appending(path: "manifest.json"), options: .withoutOverwriting)
      case .current, .requiresCompleteRepair:
        throw Failure.invalidActiveState
      }
      let active = Self.activePack(from: manifest, manifestSHA256: Self.sha256(manifestData))
      guard artifact.matches(active) else {
        throw LinnetPackContract.Failure.invalidManifest("catalog artifact identity")
      }
      try makeImmutable(partial)
      try FileManager.default.moveItem(at: partial, to: final)
      return active
    } catch {
      try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: partial.path)
      try? FileManager.default.removeItem(at: partial)
      throw error
    }
  }

  /// Rebuilds the complete Active projection from one compatible target
  /// set. No pack can override another pack's file; collisions fail before
  /// the Host receives an activation request. This is deliberately the only
  /// activation constructor: ABI-coupled Chinese/LTS/Extended updates must
  /// travel in the same candidate, not as a sequence of partial activations.
  func prepareDataChannelUpdate(
    _ update: DataChannelUpdateTransaction,
    target: [ActivePack]
  ) throws -> ActivationCandidate {
    let snapshot = try runtimeSnapshot(reconcilingStorage: false)
    let targetState = try validatedTargetPacks(target, current: snapshot.state)

    let transactionID = update.transactionID
    let transaction = transactionsDirectory.appending(
      path: transactionID.uuidString, directoryHint: .isDirectory)
    let candidate = transaction.appending(path: "language-active", directoryHint: .isDirectory)
    var record = try validatedPreparationRecord(
      update: update,
      transaction: transaction,
      snapshot: snapshot,
      packs: targetState.packs,
      edition: targetState.edition
    )
    try FileManager.default.createDirectory(
      at: candidate,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700]
    )
    do {
      return try materializeActivationCandidate(
        candidate: candidate,
        transaction: transaction,
        snapshot: snapshot,
        packs: targetState.packs,
        edition: targetState.edition,
        record: &record
      )
    } catch {
      // The downloading record remains the single cleanup owner until the
      // prepared record is atomically published.
      try? FileManager.default.removeItem(at: candidate)
      throw error
    }
  }

  func validatedTargetPacks(
    _ target: [ActivePack],
    current state: ActiveState
  ) throws -> (packs: [ActivePack], edition: Edition) {
    guard Set(target.map(\.kind)).count == target.count else {
      throw Failure.invalidActiveState
    }
    let current = Dictionary(uniqueKeysWithValues: state.packs.map { ($0.kind, $0) })
    let requested = Dictionary(uniqueKeysWithValues: target.map { ($0.kind, $0) })
    for pack in target {
      if let previous = current[pack.kind] {
        guard pack.sequence > previous.sequence
          || (pack.sequence == previous.sequence && Self.sameImmutablePack(previous, pack))
        else { throw Failure.invalidActiveState }
      } else {
        guard pack.kind == .extended else { throw Failure.invalidActiveState }
      }
    }
    for previous in state.packs where requested[previous.kind] == nil {
      guard previous.kind == .extended else { throw Failure.invalidActiveState }
    }
    let order: [LinnetPackContract.Kind: Int] = [
      .chinese: 0, .english: 1, .lts: 2, .extended: 3
    ]
    let packs = target.sorted { order[$0.kind, default: 99] < order[$1.kind, default: 99] }
    let edition: Edition = packs.contains(where: { $0.kind == .extended }) ? .full : .standard
    guard packsAreCompatible(packs, edition: edition) else {
      throw Failure.invalidActiveState
    }
    return (packs, edition)
  }

  func materializeActivationCandidate(
    candidate: URL,
    transaction: URL,
    snapshot: RuntimeSnapshot,
    packs: [ActivePack],
    edition: Edition,
    record: inout LanguageTransactionRecord
  ) throws -> ActivationCandidate {
    try FileManager.default.createDirectory(
      at: candidate.appending(path: "build", directoryHint: .isDirectory),
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    let excluded = Set(["linnet_zh.dict.yaml", "linnet_zh_full.dict.yaml"])
    for pack in packs {
      let packRoot = rootDirectory.appending(path: pack.relativePath, directoryHint: .isDirectory)
      let manifest = try verifiedInstalledManifest(for: pack).manifest
      for entry in manifest.files {
        let relative = entry.path
        if excluded.contains(relative) { continue }
        _ = try verifiedManifestFile(entry, in: packRoot)
        let projected = candidate.appending(path: relative)
        try FileManager.default.createDirectory(
          at: projected.deletingLastPathComponent(), withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o700])
        var projectedInfo = stat()
        guard lstat(projected.path, &projectedInfo) != 0, errno == ENOENT else {
          throw Failure.invalidActiveState
        }
        let parentDepth = max(0, relative.split(separator: "/").count - 1)
        let upward = String(repeating: "../", count: 2 + parentDepth)
        try FileManager.default.createSymbolicLink(
          atPath: projected.path,
          withDestinationPath: upward + pack.relativePath + "/" + relative)
      }
    }

    let generation = snapshot.state.generation + 1
    let grammar = candidate.appending(path: "linnet_grammar_active.yaml")
    try Data("grammar:\n  language: wanxiang-lts-zh-hans\n".utf8)
      .write(to: grammar, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: grammar.path)
    guard let chinese = packs.first(where: { $0.kind == .chinese }) else {
      throw Failure.invalidActiveState
    }
    let selectorPack = edition == .full
      ? packs.first(where: { $0.kind == .extended }) : chinese
    guard let selectorPack else { throw Failure.invalidActiveState }
    let selectorName = edition == .full
      ? "linnet_zh_full.dict.yaml" : "linnet_zh.dict.yaml"
    try FileManager.default.createSymbolicLink(
      atPath: candidate.appending(path: "linnet_zh.dict.yaml").path,
      withDestinationPath: "../../\(selectorPack.relativePath)/\(selectorName)"
    )
    let state = ActiveState(
      format: Self.stateFormat,
      edition: edition,
      generation: generation,
      activeView: "Runtime/Active",
      packs: packs,
      publication: .prepared,
      transactionID: record.transactionID,
      acceptedCatalog: record.catalog,
      rollbackPacks: rollbackPacksAfterPublication(previous: snapshot.state, candidate: packs)
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let stateData = try encoder.encode(state) + Data("\n".utf8)
    try stateData.write(to: candidate.appending(path: "activation.json"), options: .atomic)
    record.phase = .prepared
    record.candidateRevision = .init(
      generation: generation, stateSHA256: Self.sha256(stateData))
    try writeJSON(record, to: transaction.appending(path: Self.languageTransactionMarkerName))
    return ActivationCandidate(
      transactionID: record.transactionID,
      directory: candidate,
      expectedActiveRevision: snapshot.activeRevision)
  }

  func rollbackPacksAfterPublication(
    previous: ActiveState,
    candidate: [ActivePack]
  ) -> [ActivePack] {
    var result = Dictionary(uniqueKeysWithValues: previous.rollbackPacks.map { ($0.kind, $0) })
    for current in candidate {
      guard let prior = previous.packs.first(where: { $0.kind == current.kind }) else { continue }
      if !Self.sameImmutablePack(prior, current) { result[current.kind] = prior }
    }
    for prior in previous.packs where !candidate.contains(where: { $0.kind == prior.kind }) {
      result[prior.kind] = prior
    }
    for current in candidate where
      result[current.kind].map({ Self.sameImmutablePack($0, current) }) == true {
      result.removeValue(forKey: current.kind)
    }
    let order: [LinnetPackContract.Kind: Int] = [
      .chinese: 0, .english: 1, .lts: 2, .extended: 3
    ]
    return result.values.sorted { order[$0.kind, default: 99] < order[$1.kind, default: 99] }
  }
}
