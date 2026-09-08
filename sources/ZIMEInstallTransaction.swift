import Darwin
import Foundation

/// Shared by the ZIP and PKG entrypoints. Only this transaction publishes an
/// App or language data; the registered App directory never moves on upgrade.
struct ZIMEInstallTransaction {
  enum Failure: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
      switch self { case .invalid(let reason): "ZIME 安装未完成：\(reason)" }
    }
  }
  enum Step: String { case data, runtime, app, verified }
  struct Result {
    let backup: URL
    let firstInstall: Bool
  }
  let inputMethods: URL
  let support: URL
  var installed: URL { inputMethods.appendingPathComponent("ZIME.app") }
  var dataRoot: URL { support.appendingPathComponent("ZIME") }
  private let fm = FileManager.default

  static func directory(_ url: URL) throws {
    var info = stat()
    guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
      info.st_uid == getuid(),
      url.standardizedFileURL.path == url.resolvingSymlinksInPath().standardizedFileURL.path else {
      throw Failure.invalid("目录不存在、含符号链接或不属于当前用户：\(url.path)")
    }
  }

  private static func exists(_ url: URL) -> Bool {
    var info = stat()
    return lstat(url.path, &info) == 0
  }

  private func createDirectory(_ url: URL) throws {
    if !Self.exists(url) {
      try fm.createDirectory(at: url, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
    }
    try Self.directory(url)
  }

  private static func swap(_ first: URL, _ second: URL) throws {
    try directory(first); try directory(second)
    guard renameatx_np(AT_FDCWD, first.path, AT_FDCWD, second.path,
      UInt32(RENAME_SWAP | RENAME_NOFOLLOW_ANY)) == 0 else {
      throw Failure.invalid("无法原子交换目录（errno \(errno)）")
    }
  }

  /// Validators and the quiescence boundary are shared with the real CLI;
  /// tests inject failures here, never redirect the production install home.
  func run(sourceApp: URL, sourceData: URL?,
           validateApp: (URL) throws -> Void,
           validateData: (URL) throws -> Void,
           quiesce: () throws -> Void,
           assertQuiescent: () throws -> Void,
           after: (Step) throws -> Void = { _ in }) throws -> Result {
    try Self.directory(inputMethods)
    try Self.directory(support)
    try Self.directory(sourceApp)
    try validateApp(sourceApp)
    guard sourceApp.standardizedFileURL != installed.standardizedFileURL,
      sourceApp.pathExtension == "app" else { throw Failure.invalid("安装来源不能是正在使用的 App") }
    if let sourceData {
      try Self.directory(sourceData)
      guard Set(try fm.contentsOfDirectory(atPath: sourceData.path)) == ["Data", "Runtime"],
        sourceData.standardizedFileURL != dataRoot.standardizedFileURL else {
        throw Failure.invalid("离线数据包结构错误")
      }
      try validateData(sourceData)
    }
    try createDirectory(dataRoot)
    let descriptor = open(inputMethods.appendingPathComponent(".zime-install.lock").path,
      O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw Failure.invalid("无法取得安装锁") }
    defer { _ = flock(descriptor, LOCK_UN); _ = close(descriptor) }
    var lockInfo = stat()
    guard fstat(descriptor, &lockInfo) == 0, lockInfo.st_uid == getuid(),
      lockInfo.st_mode & S_IFMT == S_IFREG, flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      throw Failure.invalid("已有安装任务正在运行")
    }
    let existed = Self.exists(installed)
    if existed { try Self.directory(installed); try validateApp(installed) }
    guard existed || sourceData != nil else { throw Failure.invalid("首次安装需要完整离线数据包") }
    // Interrupted transactions retain their complete signed App and data.
    // Do not stack another installation on an unknown partial publication.
    for name in try fm.contentsOfDirectory(atPath: inputMethods.path)
      where name.hasPrefix(".zime-install-") {
      let marker = inputMethods.appendingPathComponent(name).appendingPathComponent("in-progress")
      if Self.exists(marker) { throw Failure.invalid("发现中断的安装，请先检查备份：\(marker.deletingLastPathComponent().path)") }
    }
    let backup = inputMethods.appendingPathComponent(".zime-install-" + UUID().uuidString)
    try createDirectory(backup)
    let stagedApp = backup.appendingPathComponent("previous.app")
    try fm.copyItem(at: sourceApp, to: stagedApp)
    try validateApp(stagedApp)
    let targetDigest = try LinnetDirectoryDelta.digest(stagedApp)
    if let sourceData {
      for name in ["Data", "Runtime"] {
        let source = sourceData.appendingPathComponent(name)
        try Self.directory(source)
        try fm.copyItem(at: source, to: backup.appendingPathComponent(name))
      }
      try validateData(backup)
    } else {
      // A Core-only update must continue to work with the retained data ABI.
      try validateData(dataRoot)
    }
    try quiesce()
    try assertQuiescent()
    let userData = dataRoot.appendingPathComponent("UserData")
    let userDigest: String?
    if Self.exists(userData) {
      try Self.directory(userData)
      let snapshot = backup.appendingPathComponent("UserData-before")
      try fm.copyItem(at: userData, to: snapshot)
      userDigest = try LinnetDirectoryDelta.digest(userData)
      guard try LinnetDirectoryDelta.digest(snapshot) == userDigest else {
        throw Failure.invalid("用户词频备份校验失败")
      }
    } else { userDigest = nil }
    let oldDigest = existed ? try LinnetDirectoryDelta.digest(installed) : nil
    let oldInode = existed ? try fm.attributesOfItem(atPath: installed.path)[.systemFileNumber] as? NSNumber : nil
    let marker = backup.appendingPathComponent("in-progress")
    try Data("ZIME installation in progress; retain this directory for recovery.\n".utf8)
      .write(to: marker, options: .atomic)
    var undo: [() throws -> Void] = []
    do {
      if sourceData != nil {
        for (name, step) in [("Data", Step.data), ("Runtime", Step.runtime)] {
          try assertQuiescent()
          let current = dataRoot.appendingPathComponent(name)
          let staged = backup.appendingPathComponent(name)
          if Self.exists(current) {
            try Self.swap(current, staged)
            undo.append { try Self.swap(current, staged) }
          } else {
            try fm.moveItem(at: staged, to: current)
            undo.append { try fm.moveItem(at: current, to: staged) }
          }
          try after(step)
        }
      }
      try assertQuiescent()
      if let oldDigest {
        try LinnetDirectoryDelta.exchangeApp(installed: installed, staged: stagedApp,
          baseSHA256: oldDigest, targetSHA256: targetDigest)
        undo.append {
          try LinnetDirectoryDelta.exchangeApp(installed: installed, staged: stagedApp,
            baseSHA256: oldDigest, targetSHA256: targetDigest)
        }
      } else {
        try fm.moveItem(at: stagedApp, to: installed)
        undo.append { try fm.moveItem(at: installed, to: stagedApp) }
      }
      try after(.app)
      try validateApp(installed)
      try validateData(dataRoot)
      guard try LinnetDirectoryDelta.digest(installed) == targetDigest else {
        throw Failure.invalid("已安装 App 与已验证来源不一致")
      }
      if let oldInode {
        guard try fm.attributesOfItem(atPath: installed.path)[.systemFileNumber] as? NSNumber == oldInode else {
          throw Failure.invalid("输入源注册目录被意外替换")
        }
      }
      if let userDigest {
        guard try LinnetDirectoryDelta.digest(userData) == userDigest else {
          throw Failure.invalid("安装期间用户词频或设置发生变化")
        }
      } else if Self.exists(userData) { throw Failure.invalid("安装期间出现外部用户数据写入") }
      try assertQuiescent()
      try after(.verified)
      try fm.removeItem(at: marker)
      return Result(backup: backup, firstInstall: !existed)
    } catch {
      let original = error
      var rollbackErrors: [String] = []
      do { try assertQuiescent() } catch {
        throw Failure.invalid("输入法意外重新启动，暂不回滚正在使用的文件。请保留备份并退出 ZIME：\(backup.path)")
      }
      for reverse in undo.reversed() {
        do { try reverse() } catch { rollbackErrors.append(error.localizedDescription) }
      }
      if rollbackErrors.isEmpty {
        try fm.removeItem(at: marker)
        throw Failure.invalid("已恢复安装前版本；\(original.localizedDescription)。备份：\(backup.path)")
      }
      throw Failure.invalid("回滚未完成，请保留 \(backup.path)。\(rollbackErrors.joined(separator: "; "))")
    }
  }
}
