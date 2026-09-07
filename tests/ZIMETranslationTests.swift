import Foundation

@main
struct ZIMETranslationTests {
  static func require(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
  }
  static func main() throws {
    let lexicon = ZIMELocalLexicon(url: URL(fileURLWithPath: "resources/zime-cedict.sqlite3"))
    for word in ["帅", "帥"] {
      let definitions = lexicon.translations(for: word)
      require(definitions.first?.contains("handsome") == true, "\(word) must mean handsome, not pinyin")
      require(definitions.first != "shuai", "romanization is not a definition")
    }
    for word in ["你好", "下班", "输入法", "人工智能", "常见", "漂亮", "学习", "朋友", "天气", "工作"] {
      require(!lexicon.translations(for: word).isEmpty, "missing common word \(word)")
    }
    require(lexicon.translations(for: "ZIME测试未收录的虚构长词").isEmpty, "unknown words must not fabricate definitions")
    require(!lexicon.translations(for: "handsome").isEmpty, "English reverse headword")
    require(ZIMELocalLexicon(url: nil).translations(for: "帅").isEmpty, "missing data fails safely")
    let start = Date()
    for _ in 0..<10000 { _ = lexicon.translations(for: "帅") }
    print("10,000 cached lookups: \(Date().timeIntervalSince(start)) s")

    var config = ZIMETranslationConfiguration()
    require(!config.enabled, "cloud must default off")
    config.baseURL = "https://example.com/v1"
    config.model = "user-selected-model"
    require(config.endpoint?.absoluteString == "https://example.com/v1/chat/completions", "compatible base URL")
    let credential = ZIMETranslationCredentials(identifier: "test-key", secret: "test-secret")
    let req = try ZIMETranslationHTTP.request(configuration: config, credentials: credential, text: "你好", chinese: true)
    require(req.value(forHTTPHeaderField: "Authorization") == "Bearer test-key", "bearer authorization")
    let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
    require(body["model"] as? String == "user-selected-model", "model must remain user selected")
    let messages = body["messages"] as! [[String: String]]
    require(messages.last?["content"] == "你好", "candidate-only payload")
    require(body["tools"] == nil && body["metadata"] == nil, "no auxiliary context")
    let account = config.credentialAccount
    config.baseURL = "https://different.example/v1"
    require(account != config.credentialAccount, "endpoint changes must not reuse credentials")
    for url in ["http://example.com/v1", "https://user:password@example.com/v1", "https://example.com/v1?token=x", "https://example.com/v1#fragment"] {
      config.baseURL = url
      require(config.endpoint == nil, "unsafe endpoint \(url)")
    }

    config.provider = .deepl
    let deepl = try ZIMETranslationHTTP.request(configuration: config, credentials: credential, text: "hello", chinese: false)
    require(deepl.url?.host == "api-free.deepl.com", "DeepL Free endpoint")
    require(deepl.value(forHTTPHeaderField: "Authorization") == "DeepL-Auth-Key test-key", "DeepL header auth")

    config.provider = .baidu
    let baidu = try ZIMETranslationHTTP.request(configuration: config,
      credentials: .init(identifier: "2015063000000001", secret: "1234567890"),
      text: "apple", chinese: false, salt: "65478")
    let form = String(data: baidu.httpBody!, encoding: .utf8)!
    require(form.contains("sign=a1a7461d92e5194c5cae3182b5b24de1"), "Baidu official signature vector")
    require(baidu.url?.query == nil && baidu.httpMethod == "POST", "text never in URL query")

    config.provider = .tencent
    let tencent = try ZIMETranslationHTTP.request(configuration: config, credentials: credential,
      text: "hello", chinese: false, timestamp: 1551113065)
    require(tencent.value(forHTTPHeaderField: "X-TC-Action") == "TextTranslate", "Tencent action")
    require(tencent.value(forHTTPHeaderField: "X-TC-Version") == "2018-03-21", "Tencent version")
    require(tencent.value(forHTTPHeaderField: "Authorization")?.contains("2019-02-25/tmt/tc3_request") == true, "UTC signing scope")
    require(tencent.value(forHTTPHeaderField: "Authorization")?.hasSuffix("d30a3d3a8bf8aef78395b3a754cf2cfd70c7fa34e5eb6f84d21cf05ff286f2d4") == true, "Tencent signature independently verified with Ruby/OpenSSL")
    require(tencent.value(forHTTPHeaderField: "Authorization")?.hasSuffix("test-secret") == false, "secret must never be sent")

    for (provider, json) in [
      (ZIMETranslationConfiguration.Provider.compatible, #"{"choices":[{"message":{"content":"你好"}}]}"#),
      (.deepl, #"{"translations":[{"text":"你好"}]}"#),
      (.baidu, #"{"trans_result":[{"dst":"你好"}]}"#),
      (.tencent, #"{"Response":{"TargetText":"你好"}}"#)
    ] {
      let parsed = try ZIMETranslationHTTP.parse(Data(json.utf8), provider: provider)
      require(parsed == "你好", "response parser \(provider)")
      do {
        _ = try ZIMETranslationHTTP.parse(Data("{}".utf8), provider: provider)
        fatalError("malformed response accepted")
      } catch {}
    }
    print("ZIMETranslationTests: PASS (offline; no credentials accessed and no API requests sent)")
  }
}
