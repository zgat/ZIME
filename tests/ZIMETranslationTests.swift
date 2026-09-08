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
    require(mainlandNi.displayText == "you" && mainlandNi.translations == ["you"],
      "你 must display and commit only its deduplicated core meaning")
    require(mainlandNi.detailText.contains("both males and females") && mainlandNi.detailText.contains("您[nin2]")
      && mainlandNi.detailText.contains("Taiwan"), "full original notes must remain available without regional rewriting")
    require(traditionalNi.displayText == "you" && traditionalNi.translations == ["you"],
      "traditional mode must use the same core-meaning contract")
    require(traditionalFemaleNi.displayText == "you" && traditionalFemaleNi.detailText.contains("Taiwan"),
      "妳 must keep the full use restriction in optional details only")
    for region in [ZIMELocalLexicon.RegionProfile.mainland, .traditionalRegions, .all] {
      for word in ["你", "妳", "帅", "帥", "发", "發", "髮", "德士", "拟", "擬", "腻", "膩"] {
        require(!lexicon.annotation(for: word, region: region).translations.isEmpty,
          "visible candidate blocked by script/region: \(word), \(region)")
      }
      require(lexicon.annotation(for: "髮", region: region).translations == ["hair"], "髮 inherited 發 meanings")
      require(!lexicon.annotation(for: "發", region: region).translations.contains("hair"), "發 inherited 髮 meanings")
      require(lexicon.annotation(for: "德士", region: region).translations == ["taxi"], "regional fallback did not translate taxi")
    }
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
    for (definition, core) in [
      ("you (informal, as opposed to courteous 您[nin2])", "you"),
      ("(Singapore, Malaysia) taxi (loanword)", "taxi"),
      ("(bound form) other; another", "other; another"),
      ("work (noun) / job (informal)", "work / job"),
      ("/aɪ/ · n. 译文（注释）", "/aɪ/ · n. 译文"),
      ("工作（名词，示例（嵌套）） / 上班（动词）", "工作 / 上班"),
      ("test (Note: example (nested) / another example)", "test"),
      ("capital (city)", "capital (city)"),
      ("not (positive)", "not (positive)"),
      ("(a grammatical definition)", "a grammatical definition"),
      ("(possessive particle, literary equivalent of 的[de5])", "possessive particle"),
      ("also written as", "also written as"),
      ("also known as", "also known as"),
      ("see you tomorrow", "see you tomorrow"),
      ("abbr. for 世界博覽會|世界博览会[Shi4 jie4 Bo2 lan3 hui4], World Expo", "World Expo"),
      ("Shanghai Stock Exchange (SSE), abbr. for 上海證券交易所|上海证券交易所", "Shanghai Stock Exchange (SSE)"),
      ("unofficial variant of 瞭[liao4]", ""),
      ("old variant of 壯|壮, Zhuang ethnic group of Guangxi", "Zhuang ethnic group of Guangxi"),
      ("to obtain (old variant of 得[de2])", "to obtain"),
      ("a river (from the mountains)", "a river (from the mountains)"),
      ("(Note: no standalone gloss)", ""),
      ("Taiwan pr. [fa3]", ""),
      ("see you (informal)", "see you"),
      ("see a doctor", "see a doctor"),
      ("see 你[ni3]", ""),
      ("variant of 你[ni3]", ""),
      ("reference 您[nin2] [x] [1]", "reference 您 [x] [1]"),
      ("colo(u)r", "colo(u)r"), ("teacher(s)", "teacher(s)"),
      ("vitamin B(12)", "vitamin B(12)"), ("(CH3)2CO", "(CH3)2CO"),
      ("you (unclosed note", "you (unclosed note")
    ] {
      require(ZIMELocalLexicon.coreDefinition(definition) == core, "core projection failed: \(definition)")
      require(ZIMELocalLexicon.coreDefinition(core) == core, "core projection is not idempotent: \(definition)")
    }
    require(ZIMELocalLexicon.coreTranslations(["you (informal)", "you (Note: example)", "yourself", "Taiwan pr. [ni3]"])
      == ["you", "yourself"], "core alternatives were duplicated or distinct meanings lost")
    require(ZIMELocalLexicon.parseSense("CL:個|个[ge4]").kind == .annotation, "classifier is metadata")
    let reference = ZIMELocalLexicon.parseSense("variant of 費城|费城[Fei4 cheng2]")
    require(reference.kind == .reference && reference.reference?.traditional == "費城"
      && reference.reference?.simplified == "费城" && reference.reference?.pinyin == "Fei4 cheng2",
      "reference target identity or reading lost")
    let runtimeLexicon = ZIMELocalLexicon(url: URL(fileURLWithPath: "resources/zime-cedict.sqlite3"), usePreparedAnnotations: false)
    for word in ["你", "妳", "费城", "費城", "世博", "上汽", "瞭解", "了解", "明天见", "下次见", "看穿", "亦作", "之", "了", "发", "髮", "德士"] {
      for region in [ZIMELocalLexicon.RegionProfile.all, .mainland, .traditionalRegions] {
        let prepared = lexicon.annotation(for: word, region: region, includeDetails: false)
        require(prepared == runtimeLexicon.annotation(for: word, region: region, includeDetails: false),
          "build/runtime parser drift: \(word), \(region)")
        require(!prepared.translations.isEmpty && prepared.detailText.isEmpty, "missing prepared meaning: \(word)")
      }
    }
    require(lexicon.annotation(for: "费城", region: .mainland).translations == ["Philadelphia, Pennsylvania"], "abbreviation reference leaked into commit")
    require(lexicon.annotation(for: "世博", region: .mainland).translations.first == "World Expo", "mixed abbreviation lost real gloss")
    require(lexicon.annotation(for: "明天见", region: .mainland).translations.first == "see you tomorrow", "ordinary see meaning was dropped")
    let originalNi = lexicon.translations(for: "你").first!
    require(lexicon.translations(for: "你", region: .mainland).first == originalNi
      && originalNi.contains("informal") && mainlandNi.translations == ["you"],
      "core projection must not rewrite the source dictionary")
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
    let providerLabels: [(ZIMETranslationConfiguration.Provider, String)] = [(.compatible, "ai"), (.deepl, "DeepL"), (.baidu, "百度"), (.tencent, "腾讯")]
    for (provider, label) in providerLabels {
      require(provider.candidateSourceLabel == label, "wrong source label")
      func response(_ text: String) throws -> Data {
        let object: [String: Any]
        switch provider {
        case .compatible: object = ["choices": [["message": ["content": text]]]]
        case .deepl: object = ["translations": [["text": text]]]
        case .baidu: object = ["trans_result": [["dst": text]]]
        case .tencent: object = ["Response": ["TargetText": text]]
        }
        return try JSONSerialization.data(withJSONObject: object)
      }
      for raw in ["  you (informal) / yourself; yours\nsecond line\t尾行  ", String(repeating: "译", count: 1000)] {
        let parsed = try ZIMETranslationHTTP.parse(response(raw), provider: provider)
        require(parsed == raw, "online translation was trimmed, split or classified: \(provider)")
      }
      for invalid in [" \n\t", "invalid\0tail", String(repeating: "译", count: 1400)] {
        do {
          _ = try ZIMETranslationHTTP.parse(response(invalid), provider: provider)
          fatalError("invalid or oversized translation accepted: \(provider)")
        } catch {}
      }
    }
    print("ZIMETranslationTests: PASS (offline; no credentials accessed and no API requests sent)")
  }
}
