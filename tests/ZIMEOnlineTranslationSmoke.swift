// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

@main
struct ZIMEOnlineTranslationSmoke {
  static func main() async {
    // Consent is checked before reading preferences or looking up any credential.
    guard Array(CommandLine.arguments.dropFirst()) == ["--allow-network"] else {
      print("NOT_EXERCISED: explicit --allow-network consent is required.")
      exit(64)
    }
    do {
      let configuration = ZIMETranslationConfiguration.load()
      guard configuration.enabled else {
        print("NOT_EXERCISED: the configured translation service is disabled.")
        exit(2)
      }
      try configuration.validate()
      let credentials = try ZIMETranslationCredentials.load(account: configuration.credentialAccount)
      for (text, chinese) in [("你好", true), ("hello", false)] {
        let result = try await ZIMETranslationHTTP.translate(
          configuration: configuration, credentials: credentials, text: text, chinese: chinese)
        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          throw ZIMETranslationError.response
        }
      }
      // Never print credentials, endpoint, response text or request bodies.
      print("PASS: \(configuration.provider.rawValue); two fixed requests decoded; semantic quality not certified.")
    } catch {
      print("FAIL: live translation request or configuration failed; inspect service settings privately.")
      exit(1)
    }
  }
}
