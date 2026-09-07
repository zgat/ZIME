// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct ZIMETranslationSettingsView: View {
  @State private var configuration = ZIMETranslationConfiguration.load()
  @State private var identifier = ""
  @State private var secret = ""
  @State private var status = ""
  @State private var testing = false

  var body: some View {
    LinnetSettingsPage("翻译", summary: "每个候选词显示独立译文；本地优先，云端按需补全。", systemImage: "character.bubble") {
      GroupBox("离线词库") {
        VStack(alignment: .leading, spacing: 8) {
          Text("CC-CEDICT 中英词典 · 支持简体和繁体；英文释义沿用本地英汉词库。")
          Text("拼音词库负责候选和组句，翻译词库负责释义。未收录的整句、新词会显示“暂无本地译文”，不会用拼音代替。")
            .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
      }
      GroupBox("翻译 API") {
        VStack(alignment: .leading, spacing: 12) {
          Toggle("启用云翻译，补全缺少本地译文的候选词", isOn: $configuration.enabled)
            .accessibilityIdentifier("settings.translation.enabled")
          Text("开启并保存后，缺少本地译文的当前页候选词会发送给下方服务，可能产生费用。不会发送前后文、剪贴板、应用名称或已输入的文档。关闭时不发请求。")
            .font(.caption).foregroundStyle(.secondary)
          Picker("服务商", selection: $configuration.provider) {
            ForEach(ZIMETranslationConfiguration.Provider.allCases, id: \.self) { provider in
              Text(provider.title).tag(provider)
            }
          }.pickerStyle(.menu).accessibilityIdentifier("settings.translation.provider")
          if configuration.provider == .compatible {
            TextField("服务地址，例如 https://api.example.com/v1", text: $configuration.baseURL)
              .accessibilityIdentifier("settings.translation.endpoint")
            TextField("模型名称（使用服务商提供的标识）", text: $configuration.model)
              .accessibilityIdentifier("settings.translation.model")
          }
          if configuration.provider == .deepl {
            Picker("DeepL 账户", selection: $configuration.deeplFree) {
              Text("API Free").tag(true)
              Text("API Pro").tag(false)
            }.pickerStyle(.menu)
          }
          if configuration.provider == .tencent {
            TextField("地区，例如 ap-guangzhou", text: $configuration.region)
          }
          SecureField(credentialLabel + "（留空保留已存密钥）", text: $identifier)
            .accessibilityIdentifier("settings.translation.key")
          if configuration.provider == .baidu || configuration.provider == .tencent {
            SecureField(configuration.provider == .baidu ? "密钥 Secret" : "SecretKey", text: $secret)
          }
          Text("密钥仅保存在本机 macOS 钥匙串，不进入设置 JSON、项目或词库备份。更换服务地址需要为新地址保存密钥。")
            .font(.caption).foregroundStyle(.secondary)
          HStack {
            Button("保存翻译设置") { save() }
              .accessibilityIdentifier("settings.translation.save")
            Button(testing ? "测试中…" : "测试连接（发送 hello）") { test() }
              .disabled(testing)
            Button("删除此服务密钥", role: .destructive) { deleteCredentials() }
          }
          Text("本页单独保存，保存后下一次输入生效。测试按钮只发送固定单词 hello，不会自动启用云翻译。")
            .font(.caption).foregroundStyle(.secondary)
          if !status.isEmpty { Text(status).font(.callout).textSelection(.enabled) }
        }.padding(8)
      }
    }
    .onChange(of: configuration.provider) { _ in clearDraftCredentials() }
    .onChange(of: configuration.baseURL) { _ in clearDraftCredentials() }
    .onChange(of: configuration.deeplFree) { _ in clearDraftCredentials() }
  }

  private var credentialLabel: String {
    switch configuration.provider {
    case .compatible, .deepl: "API Key"
    case .baidu: "APP ID"
    case .tencent: "SecretId"
    }
  }
  private func clearDraftCredentials() { identifier = ""; secret = ""; status = "" }
  private func credentials() throws -> ZIMETranslationCredentials {
    let value = identifier.isEmpty && secret.isEmpty
      ? try ZIMETranslationCredentials.load(account: configuration.credentialAccount)
      : ZIMETranslationCredentials(identifier: identifier.trimmingCharacters(in: .whitespacesAndNewlines), secret: secret.trimmingCharacters(in: .whitespacesAndNewlines))
    _ = try ZIMETranslationHTTP.request(configuration: configuration, credentials: value, text: "hello", chinese: false)
    return value
  }
  private func save() {
    do {
      if configuration.enabled || !identifier.isEmpty || !secret.isEmpty {
        try credentials().save(account: configuration.credentialAccount)
      }
      configuration.revision = UUID().uuidString
      try configuration.save()
      clearDraftCredentials()
      status = configuration.enabled ? "已保存：本地优先，云翻译补全已启用。" : "已保存：仅使用离线词库。"
    } catch { status = error.localizedDescription }
  }
  private func test() {
    do {
      let credentials = try credentials()
      let selected = configuration
      testing = true
      Task { @MainActor in
        defer { testing = false }
        do {
          let translation = try await ZIMETranslationHTTP.translate(configuration: selected, credentials: credentials, text: "hello", chinese: false)
          status = "\(selected.provider.title) 连接成功：hello → \(translation)"
        } catch { status = error.localizedDescription }
      }
    } catch { status = error.localizedDescription }
  }
  private func deleteCredentials() {
    do {
      try ZIMETranslationCredentials.delete(account: configuration.credentialAccount)
      configuration.enabled = false
      configuration.revision = UUID().uuidString
      try configuration.save()
      clearDraftCredentials()
      status = "已删除此服务密钥，并关闭云翻译。"
    } catch { status = error.localizedDescription }
  }
}
