// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Carbon
import Foundation

#if !ZIME_INSTALL_TEST
@main
#endif
struct ZIMEInstallHelper {
  static let bundleID = "com.zime.inputmethod.ZIME"
  typealias Failure = ZIMEInstallTransaction.Failure

  static func command(_ executable: String, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let bytes = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw Failure.invalid("校验命令失败：\(executable)")
    }
    return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func info(_ app: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
    guard let value = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
      throw Failure.invalid("无效的 App 信息")
    }
    return value
  }

  static func validateApp(_ app: URL) throws {
    try ZIMEInstallTransaction.directory(app)
    try ZIMEInstallTransaction.directory(app.appendingPathComponent("Contents"))
    guard try FileManager.default.contentsOfDirectory(atPath: app.path) == ["Contents"] else {
      throw Failure.invalid("App 顶层结构错误")
    }
    let value = try info(app)
    guard value["CFBundleIdentifier"] as? String == bundleID,
      value["CFBundleExecutable"] as? String == "ZIME",
      let version = value["CFBundleShortVersionString"] as? String,
      version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil,
      let build = value["CFBundleVersion"] as? String, Int(build) != nil,
      try command("/usr/bin/lipo", ["-archs", app.appendingPathComponent("Contents/MacOS/ZIME").path]) == "arm64",
      try info(app.appendingPathComponent("Contents/Applications/Settings.app"))["CFBundleIdentifier"] as? String == bundleID + ".settings" else {
      throw Failure.invalid("App 身份、版本或架构不符合 ZIME 要求")
    }
    _ = try command("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
  }

  static func sourceID(_ source: TISInputSource) -> String? {
    guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
  }

  static func validateData(_ root: URL, version: String) throws {
    guard try LinnetDataRegistry.inspectInstalledRuntime(productName: root.lastPathComponent,
      coreVersion: version, applicationSupportDirectory: root.deletingLastPathComponent()) == .healthy else {
      throw Failure.invalid("离线词库或运行数据不完整，请使用完整安装包")
    }
  }

  static func run() throws {
    var args = Array(CommandLine.arguments.dropFirst())
    // Package verification uses the real validators with no home-directory,
    // process, input-source, Keychain or network side effects.
    if args.count == 3 && args[0] == "check" {
      let app = URL(fileURLWithPath: args[1]).standardizedFileURL
      try validateApp(app)
      let version = try info(app)["CFBundleShortVersionString"] as! String
      try Self.validateData(URL(fileURLWithPath: args[2]).standardizedFileURL, version: version)
      print("ZIME installer payload: PASS (App signature, identity, architecture and complete offline runtime)")
      return
    }
    guard (args.count == 3 && args[0] == "install") ||
      (args.count == 2 && ["update", "install-staged"].contains(args[0])) else {
      throw Failure.invalid("用法：zime-install-helper install APP DATA，或 update APP")
    }
    guard getuid() != 0, let passwd = getpwuid(getuid()), let homePath = passwd.pointee.pw_dir else {
      throw Failure.invalid("请在当前登录用户的终端运行，不要使用 sudo")
    }
    let home = URL(fileURLWithPath: String(cString: homePath)).standardizedFileURL
    try ZIMEInstallTransaction.directory(home)
    if args[0] == "install-staged" {
      guard args[1].range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil else {
        throw Failure.invalid("安装包版本错误")
      }
      let payload = home.appendingPathComponent("Library/Application Support/ZIME Installer/" + args[1])
      args = ["install", payload.appendingPathComponent("ZIME.app").path,
        payload.appendingPathComponent("ZIME-Data").path]
    }
    let library = home.appendingPathComponent("Library")
    try ZIMEInstallTransaction.directory(library)
    let inputMethods = library.appendingPathComponent("Input Methods")
    let support = library.appendingPathComponent("Application Support")
    for directory in [inputMethods, support] {
      if !FileManager.default.fileExists(atPath: directory.path) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
          attributes: [.posixPermissions: 0o700])
      }
      try ZIMEInstallTransaction.directory(directory)
    }
    let transaction = ZIMEInstallTransaction(inputMethods: inputMethods, support: support)
    let sourceApp = URL(fileURLWithPath: args[1]).standardizedFileURL
    let sourceData = args[0] == "install" ? URL(fileURLWithPath: args[2]).standardizedFileURL : nil
    try validateApp(sourceApp)
    let version = try info(sourceApp)["CFBundleShortVersionString"] as! String
    let build = Int(try info(sourceApp)["CFBundleVersion"] as! String)!
    if FileManager.default.fileExists(atPath: transaction.installed.path) {
      let installedInfo = try info(transaction.installed)
      guard let oldVersion = installedInfo["CFBundleShortVersionString"] as? String,
        let oldBuild = installedInfo["CFBundleVersion"] as? String,
        let oldBuildNumber = Int(oldBuild),
        version.compare(oldVersion, options: .numeric) != .orderedAscending,
        build >= oldBuildNumber else { throw Failure.invalid("不允许用旧版本覆盖当前安装") }
    }
    let previous = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    let wasSelected = sourceID(previous)?.hasPrefix(bundleID + ".") == true
    var stopped = false
    func running() throws -> [NSRunningApplication] {
      let apps = [bundleID, bundleID + ".settings"].flatMap {
        NSRunningApplication.runningApplications(withBundleIdentifier: $0)
      }.filter { !$0.isTerminated }
      for app in apps {
        guard let path = app.bundleURL?.standardizedFileURL.path,
          path == transaction.installed.path || path == transaction.installed.appendingPathComponent("Contents/Applications/Settings.app").path else {
          throw Failure.invalid("另一路径的 ZIME 正在运行，请先退出它")
        }
      }
      return apps
    }
    func assertQuiescent() throws {
      guard try running().isEmpty else {
        throw Failure.invalid("ZIME 或设置仍在运行，请切换到其他输入法并关闭 ZIME 设置后重试")
      }
    }
    func quiesce() throws {
      _ = try running()
      if wasSelected {
        let ascii = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
        guard TISSelectInputSource(ascii) == noErr else {
          throw Failure.invalid("请先手动切换到 ABC 等其他输入法")
        }
      }
      stopped = true
      // No force termination: settings may need the user's save/discard choice.
      for app in try running() { _ = app.terminate() }
      let deadline = Date().addingTimeInterval(12)
      while !(try running()).isEmpty && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
      }
      try assertQuiescent()
    }
    func validateData(_ root: URL) throws {
      try Self.validateData(root, version: version)
    }
    let result: ZIMEInstallTransaction.Result
    do {
      result = try transaction.run(sourceApp: sourceApp, sourceData: sourceData,
        validateApp: validateApp, validateData: validateData,
        quiesce: quiesce, assertQuiescent: assertQuiescent)
    } catch {
      // Restore selection only after a complete rollback. An interrupted
      // publication must stay stopped until its retained backup is reviewed.
      let entries = (try? FileManager.default.contentsOfDirectory(at: inputMethods,
        includingPropertiesForKeys: nil)) ?? []
      let interrupted = entries.contains {
        $0.lastPathComponent.hasPrefix(".zime-install-") &&
          FileManager.default.fileExists(atPath: $0.appendingPathComponent("in-progress").path)
      }
      if stopped && !interrupted && wasSelected { _ = TISSelectInputSource(previous) }
      throw error
    }
    print("ZIME \(version) 已安装；用户词频和设置保持不变。")
    print("回退备份：\(result.backup.path)")
    if result.firstInstall {
      _ = try command(transaction.installed.appendingPathComponent("Contents/MacOS/ZIME").path,
        ["--request-first-install-authorization"])
      print("请在系统设置 → 键盘 → 输入源中添加 ZIME 简体中文或 ZIME 繁體中文。")
    } else {
      // -j hides the input-method host and can suppress all candidate windows.
      _ = try command("/usr/bin/open", ["-g", transaction.installed.path])
      if wasSelected { _ = TISSelectInputSource(previous) }
    }
  }

  static func main() {
    do { try run() }
    catch {
      FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
      exit(1)
    }
  }
}
