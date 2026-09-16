import Foundation

@main
struct ZIMEInstallTransactionTests {
  static let fm = FileManager.default
  static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw ZIMEInstallTransaction.Failure.invalid("TEST: " + message) }
  }
  static func make(_ url: URL, _ name: String, _ value: String) throws {
    try fm.createDirectory(at: url, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    try Data(value.utf8).write(to: url.appendingPathComponent(name))
  }
  static func main() {
    do { try verify() } catch {
      fputs(error.localizedDescription + "\n", stderr)
      exit(1)
    }
  }

  static func verify() throws {
    let root = URL(fileURLWithPath: "/private/tmp/zime-install-tests-" + UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: root) }
    try verifyRestartBoundaries(root)
    for fresh in [false, true] {
      for fault in [nil, ZIMEInstallTransaction.Step.data, .runtime, .app, .verified] {
        let work = root.appendingPathComponent(UUID().uuidString)
        let methods = work.appendingPathComponent("Input Methods")
        let support = work.appendingPathComponent("Application Support")
        try fm.createDirectory(at: methods, withIntermediateDirectories: true)
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        let txn = ZIMEInstallTransaction(inputMethods: methods, support: support)
        let app = work.appendingPathComponent("source.app")
        let data = work.appendingPathComponent("source-data")
        try make(app.appendingPathComponent("Contents"), "payload", "new")
        for name in ["Data", "Runtime"] {
          try make(data.appendingPathComponent(name), "payload", "new")
          if !fresh { try make(txn.dataRoot.appendingPathComponent(name), "payload", "old") }
        }
        if !fresh { try make(txn.installed.appendingPathComponent("Contents"), "payload", "old") }
        try make(txn.dataRoot.appendingPathComponent("UserData"), "learning", "key=可以,4;key=key,7;emoji=3")
        let userBefore = try LinnetDirectoryDelta.digest(txn.dataRoot.appendingPathComponent("UserData"))
        let inode = try? fm.attributesOfItem(atPath: txn.installed.path)[.systemFileNumber] as? NSNumber
        var stopped = false
        var failed = false
        do {
          let result = try txn.run(sourceApp: app, sourceData: data,
            validateApp: { try require(fm.fileExists(atPath: $0.appendingPathComponent("Contents/payload").path), "app validation") },
            validateData: { value in
              for name in ["Data", "Runtime"] {
                try require(fm.fileExists(atPath: value.appendingPathComponent(name + "/payload").path), "data validation")
              }
            }, quiesce: { stopped = true }, assertQuiescent: { try require(stopped, "publish before stop") },
            after: { if $0 == fault { throw ZIMEInstallTransaction.Failure.invalid("injected " + $0.rawValue) } })
          try require(result.firstInstall == fresh, "first install flag")
          try require(fm.fileExists(atPath: result.backup.appendingPathComponent("UserData-before/learning").path), "learning backup")
        } catch {
          if fault == nil { throw error }
          failed = true
        }
        try require(failed == (fault != nil), "fault injection")
        try require(try LinnetDirectoryDelta.digest(txn.dataRoot.appendingPathComponent("UserData")) == userBefore, "learning changed")
        if fresh && failed {
          try require(!fm.fileExists(atPath: txn.installed.path), "fresh rollback app")
          for name in ["Data", "Runtime"] { try require(!fm.fileExists(atPath: txn.dataRoot.appendingPathComponent(name).path), "fresh rollback data") }
        } else {
          let expected = failed ? "old" : "new"
          try require(try String(contentsOf: txn.installed.appendingPathComponent("Contents/payload"), encoding: .utf8) == expected, "app bytes")
          for name in ["Data", "Runtime"] {
            try require(try String(contentsOf: txn.dataRoot.appendingPathComponent(name + "/payload"), encoding: .utf8) == expected, "data bytes")
          }
          if !fresh { try require(try fm.attributesOfItem(atPath: txn.installed.path)[.systemFileNumber] as? NSNumber == inode, "registered App inode changed") }
        }
      }
    }
    // Core-only preserves the existing Data/Runtime and does not publish when
    // the host refuses to quit or a validator rejects the package.
    let core = root.appendingPathComponent("core")
    let methods = core.appendingPathComponent("Input Methods")
    let support = core.appendingPathComponent("Application Support")
    try fm.createDirectory(at: methods, withIntermediateDirectories: true)
    try fm.createDirectory(at: support, withIntermediateDirectories: true)
    let txn = ZIMEInstallTransaction(inputMethods: methods, support: support)
    let app = core.appendingPathComponent("new.app")
    try make(app.appendingPathComponent("Contents"), "payload", "new")
    try make(txn.installed.appendingPathComponent("Contents"), "payload", "old")
    for name in ["Data", "Runtime", "UserData"] {
      try make(txn.dataRoot.appendingPathComponent(name), "payload", "retained")
    }
    let retained = try LinnetDirectoryDelta.digest(txn.dataRoot)
    for reject in ["app", "data", "quiesce", "running"] {
      var rejected = false
      do {
        _ = try txn.run(sourceApp: app, sourceData: nil,
          validateApp: { _ in if reject == "app" { throw ZIMEInstallTransaction.Failure.invalid("bad app") } },
          validateData: { _ in if reject == "data" { throw ZIMEInstallTransaction.Failure.invalid("bad data") } },
          quiesce: { if reject == "quiesce" { throw ZIMEInstallTransaction.Failure.invalid("quit refused") } },
          assertQuiescent: { if reject == "running" { throw ZIMEInstallTransaction.Failure.invalid("still running") } })
      } catch { rejected = true }
      try require(rejected, "rejected preflight was published")
      try require(try String(contentsOf: txn.installed.appendingPathComponent("Contents/payload"), encoding: .utf8) == "old", "preflight changed app")
      try require(try LinnetDirectoryDelta.digest(txn.dataRoot) == retained, "preflight changed data")
    }
    _ = try txn.run(sourceApp: app, sourceData: nil, validateApp: { _ in }, validateData: { _ in },
      quiesce: {}, assertQuiescent: {})
    try require(try LinnetDirectoryDelta.digest(txn.dataRoot) == retained, "core changed retained data")
    try require(try String(contentsOf: txn.installed.appendingPathComponent("Contents/payload"), encoding: .utf8) == "new", "core app not updated")
    // Path aliases must never weaken RENAME_NOFOLLOW_ANY.
    let unsafe = root.appendingPathComponent("symlink")
    try fm.createSymbolicLink(at: unsafe, withDestinationURL: root)
    do { try ZIMEInstallTransaction.directory(unsafe); fatalError("symlink accepted") } catch {}
    print("ZIME install transaction: PASS (fresh/full/core, 8 rollback boundaries, 4 preflight refusals, 14 restart boundaries, recovery refusal, App inode and learning preserved, symlink rejection)")
  }

  static func verifyRestartBoundaries(_ root: URL) throws {
    let steps: [ZIMEInstallTransaction.Step] = [.data, .runtime, .app, .verified]
    for fresh in [false, true] {
      for forcedFailure in [false, true] {
        for boundary in steps where forcedFailure || boundary != .verified {
          let work = root.appendingPathComponent(UUID().uuidString)
          let methods = work.appendingPathComponent("Input Methods")
          let support = work.appendingPathComponent("Support")
          try fm.createDirectory(at: methods, withIntermediateDirectories: true)
          try fm.createDirectory(at: support, withIntermediateDirectories: true)
          let txn = ZIMEInstallTransaction(inputMethods: methods, support: support)
          let app = work.appendingPathComponent("source.app")
          let data = work.appendingPathComponent("data")
          try make(app.appendingPathComponent("Contents"), "payload", "new")
          for name in ["Data", "Runtime"] {
            try make(data.appendingPathComponent(name), "payload", "new")
            if !fresh { try make(txn.dataRoot.appendingPathComponent(name), "payload", "old") }
          }
          if !fresh { try make(txn.installed.appendingPathComponent("Contents"), "payload", "old") }
          try make(txn.dataRoot.appendingPathComponent("UserData"), "learning", "retained")
          let userDigest = try LinnetDirectoryDelta.digest(txn.dataRoot.appendingPathComponent("UserData"))
          var running = false
          var published: [ZIMEInstallTransaction.Step] = []
          var rejected = false
          do {
            _ = try txn.run(sourceApp: app, sourceData: data, validateApp: { _ in }, validateData: { _ in },
              quiesce: {}, assertQuiescent: { try require(!running, "host restarted") }, after: { step in
                published.append(step)
                if step == boundary {
                  running = true
                  if forcedFailure { throw ZIMEInstallTransaction.Failure.invalid("injected publication failure") }
                }
              })
          } catch {
            rejected = error.localizedDescription.contains("暂不回滚正在使用的文件")
          }
          let index = steps.firstIndex(of: boundary)!
          try require(rejected && published == Array(steps.prefix(index + 1)), "restart allowed later publication or unsafe rollback")
          for (offset, name) in ["Data", "Runtime", "App"].enumerated() {
            let payload = name == "App" ? txn.installed.appendingPathComponent("Contents/payload")
              : txn.dataRoot.appendingPathComponent(name + "/payload")
            if fresh && offset > index {
              try require(!fm.fileExists(atPath: payload.path), "restart created an unpublished component")
            } else {
              try require(try String(contentsOf: payload, encoding: .utf8) == (offset <= index ? "new" : "old"),
                "restart changed a published or untouched component")
            }
          }
          let backups = try fm.contentsOfDirectory(at: methods, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".zime-install-") }
          try require(backups.count == 1 && fm.fileExists(atPath: backups[0].appendingPathComponent("in-progress").path),
            "restart discarded recovery marker")
          try require(try LinnetDirectoryDelta.digest(txn.dataRoot.appendingPathComponent("UserData")) == userDigest,
            "restart changed learning")
          let partialDigest = try LinnetDirectoryDelta.digest(txn.dataRoot)
          var retried = false
          var retryRejected = false
          do {
            _ = try txn.run(sourceApp: app, sourceData: data, validateApp: { _ in }, validateData: { _ in },
              quiesce: { retried = true }, assertQuiescent: {})
          } catch {
            try require(error.localizedDescription.contains("发现中断的安装"), "wrong recovery refusal")
            retryRejected = true
          }
          try require(!retried && retryRejected && (try LinnetDirectoryDelta.digest(txn.dataRoot)) == partialDigest,
            "incomplete transaction allowed another install")
        }
      }
    }
  }
}
