// Historical upstream IPC sender / recovery reader for compatibility tests only.
// Not linked into ZIME or Settings. No production UI starts these operations.
import Foundation

extension SettingsDataCoordinator {
  func activateLanguage(
    _ activation: LinnetDataRegistry.ActivationCandidate,
    progress: @escaping @Sendable (Phase) -> Void = { _ in }
  ) async throws {
    let registry = registryOverride ?? LinnetSettingsContract.dataRegistry(startingAt: bundle)
    guard let registry else { throw Failure.unavailable }
    let transaction = registry.transactionsDirectory.appending(
      path: activation.transactionID.uuidString, directoryHint: .isDirectory)
    guard activation.directory.standardizedFileURL
      == transaction.appending(path: "language-active", directoryHint: .isDirectory)
        .standardizedFileURL
    else {
      throw Failure.unsafePath(activation.directory.path)
    }
    try requireDirectory(transaction)
    try requireDirectory(activation.directory)

    let deadline = Date().addingTimeInterval(Self.transactionRequestTimeout)
    var paused = false
    do {
      progress(.pausing)
      let pause = try await request(
        makeRequest(
          transactionID: activation.transactionID,
          command: .pause,
          candidate: nil,
          deadline: deadline,
          expectedActiveRevision: activation.expectedActiveRevision
        ),
        replyTimeout: try remainingTransactionTime(until: deadline),
        progress: progress
      )
      guard pause.status == .paused else { throw Failure.requestFailed(pause.code) }
      paused = true
      try Task.checkCancellation()
      progress(.activating)
      let reply = try await request(
        makeRequest(
          transactionID: activation.transactionID,
          command: .activateLanguage,
          candidate: activation.directory,
          deadline: deadline,
          expectedActiveRevision: activation.expectedActiveRevision
        ),
        replyTimeout: try remainingTransactionTime(until: deadline),
        progress: progress
      )
      switch reply.status {
      case .activated:
        paused = false
        progress(.completed)
      case .rolledBack:
        paused = false
        throw Failure.requestFailed(reply.code)
      case .failed:
        paused = false
        throw Failure.requestFailed(reply.code)
      default:
        throw Failure.requestFailed(reply.code)
      }
    } catch {
      let operationError = error
      var resumeError: Error?
      if paused {
        progress(.cancelling)
        do {
          let resume = try await request(
            makeRequest(
              transactionID: activation.transactionID,
              command: .cancel,
              candidate: nil,
              deadline: deadline
            ),
            replyTimeout: try remainingTransactionTime(until: deadline),
            progress: progress
          )
          if resume.status != .cancelled {
            resumeError = Failure.requestFailed(resume.code)
          }
        } catch {
          resumeError = error
        }
      }
      if let resumeError { throw resumeError }
      throw operationError
    }
  }

  /// Cloud recovery reconstruction can invoke rsync and read a full archive;
  /// it stays on this coordinator actor rather than the Settings main actor.
  func inspectCloudRecovery(
    in cloudFolder: URL
  ) throws -> PortableImportCandidate? {
    guard !Task.isCancelled else { throw Failure.cancelled }
    let scratch = LinnetTestScratch.directory.appending(
      path: "CloudRecoveryInspect-\(UUID().uuidString)", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: scratch, withIntermediateDirectories: false)
    defer { try? fileManager.removeItem(at: scratch) }
    guard let materialized = try LinnetCloudRecoveryArchive.materializeLatest(
      in: cloudFolder, workspace: scratch)
    else { return nil }
    return try inspectPortable(materialized)
  }
}
