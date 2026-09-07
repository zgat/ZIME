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
    for spelling in ["handsome", "Handsome", "HANDSOME", "hAnDsOmE", " Handsome "] {
      require(lexicon.translations(for: spelling) == lexicon.translations(for: "handsome"),
        "local English case variants or cache lookup lost the definition: \(spelling)")
    }
    require(ZIMELocalLexicon(url: nil).translations(for: "帅").isEmpty, "missing data fails safely")
    // The same glyphs must follow the selected source, not a script heuristic.
    for _ in 0..<3 {
      require(lexicon.translations(for: "土豆", region: .mainland) == ["potato"], "Mainland potato must exclude Taiwan peanut")
      require(lexicon.translations(for: "土豆", region: .traditionalRegions).contains { $0.contains("peanut") }, "Traditional-region senses missing after cache switch")
      require(lexicon.translations(for: "德士", region: .mainland).isEmpty, "Singapore/Malaysia sense leaked into Mainland group")
      require(lexicon.translations(for: "德士", region: .traditionalRegions).first?.contains("taxi") == true, "Singapore/Malaysia group missing")
    }
    let mainlandNi = lexicon.annotation(for: "你", region: .mainland)
    let traditionalNi = lexicon.annotation(for: "你", region: .traditionalRegions)
    let traditionalFemaleNi = lexicon.annotation(for: "妳", region: .traditionalRegions)
    require(mainlandNi.displayText == "you (informal)" && mainlandNi.translations.count == 1,
      "Mainland 你 must coalesce explanatory you without dropping the informal qualifier")
    require(mainlandNi.detailText.contains("both males and females") && mainlandNi.detailText.contains("您[nin2]")
      && !mainlandNi.detailText.contains("Taiwan"), "Mainland full regional notes lost")
    require(traditionalNi.displayText == "you (informal)" && !traditionalNi.detailText.contains("妳"),
      "Traditional 你 must not inherit the 妳 headword's female-address notes")
    require(traditionalFemaleNi.displayText == "you (female)" && traditionalFemaleNi.detailText.contains("Taiwan"),
      "妳 must retain its distinguishing female-address sense")
    require(lexicon.translations(for: "妳", region: .mainland).isEmpty, "strict simplified lookup must not guess a traditional spelling")
    require(lexicon.sourceEntries(for: "你").map(\.traditional) == ["你", "妳"], "original headword identity lost")
    require(lexicon.sourceEntries(for: "你", region: .traditionalRegions).map(\.traditional) == ["你"], "traditional lookup reused simplified alias")
    let simplifiedFa = lexicon.annotation(for: "发", region: .mainland)
    require(simplifiedFa.displayText.contains("hair") && simplifiedFa.displayText.contains("to send out"),
      "simplified 發/髮 must expose both distinct meanings, not discard one as a duplicate")
    require(lexicon.annotation(for: "髮", region: .traditionalRegions).displayText == "hair", "髮 inherited 發 meanings or pronunciation-only candidate")
    require(lexicon.annotation(for: "髮", region: .traditionalRegions).detailText.contains("Taiwan pr."), "moved pronunciation note lost from detail")
    require(!lexicon.annotation(for: "發", region: .traditionalRegions).detailText.contains("hair"), "發 inherited 髮")
    for term in ["你", "妳", "发", "髮", "土豆"] {
      let first = lexicon.annotation(for: term, region: .mainland)
      _ = lexicon.annotation(for: term, region: .traditionalRegions)
      require(lexicon.annotation(for: term, region: .mainland) == first, "annotation cache crossed a region boundary")
    }
    for definition in ["capital (city)", "capital (finance)", "(bound form) other; another",
      "(used after an attribute when it modifies a noun)", "not (positive)",
      "a (nested (essential) condition)", "you (unclosed note"] {
      require(ZIMELocalLexicon.inlineDefinition(definition, headword: "fixture").text == definition,
        "necessary or unclassified qualification was removed: \(definition)")
    }
    require(ZIMELocalLexicon.inlineDefinition("you (informal, as opposed to courteous 您[nin2])", headword: "你").text == "you (informal)", "comparison not moved to detail")
    require(ZIMELocalLexicon.inlineDefinition("test (Note: example (nested))", headword: "fixture").text == "test", "balanced explanatory note not separated")
    require(ZIMELocalLexicon.inlineDefinition("(Note: no standalone gloss)", headword: "fixture").text == "(Note: no standalone gloss)", "note-only entry became blank")
    require(ZIMELocalLexicon.inlineDefinition("reference 您[nin2] [x] [1]", headword: "fixture").text == "reference 您 [x] [1]", "pinyin removal changed other bracket content")
    let originalNi = lexicon.translations(for: "你").first!
    require(lexicon.translations(for: "你", region: .mainland).first == originalNi && mainlandNi.translations.first == originalNi,
      "general informal/polite distinction must not be summarized away")
    let regionalFixture = ["(HK) regional sense", "(Macau) local usage", "(PRC) mainland usage",
      "(Singapore, Malaysia) taxi", "a company in Taiwan and mainland China",
      "China Airlines (Taiwan)", "(dialect) to take a shower", "not (positive)",
      "(PRC, Tw) shared regional usage", "AA battery (Tw) (PRC equivalent: 五號電池[wu3 hao4 dian4 chi2])"]
    let mainland = ZIMELocalLexicon.regionalTranslations(regionalFixture, for: "fixture", region: .mainland)
    let traditional = ZIMELocalLexicon.regionalTranslations(regionalFixture, for: "fixture", region: .traditionalRegions)
    require(!mainland.contains(regionalFixture[0]) && traditional.contains(regionalFixture[0]), "HK usage filtering")
    require(!mainland.contains(regionalFixture[1]) && traditional.contains(regionalFixture[1]), "Macau usage filtering")
    require(mainland.contains(regionalFixture[2]) && !traditional.contains(regionalFixture[2]), "PRC usage filtering")
    for unchanged in regionalFixture[4...8] {
      require(mainland.contains(unchanged) && traditional.contains(unchanged), "unclassified/common sense was altered: \(unchanged)")
    }
    require(traditional.last == "AA battery (Tw)", "cross-region equivalence note was not filtered independently")
    require(lexicon.translations(for: "他", region: .mainland) == lexicon.translations(for: "他"), "grammar/usage notes must remain intact")
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
