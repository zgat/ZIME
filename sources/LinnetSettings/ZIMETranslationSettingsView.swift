// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct ZIMETranslationSettingsView: View {
  @ObservedObject var model: ZIMETranslationSettingsModel
  @State private var confirmsDeletion = false

  var body: some View {
    LinnetSettingsPage("翻译", summary: "每个候选词显示独立译文；本地优先，云端按需补全。", systemImage: "character.bubble") {
      GroupBox("译文显示") {
        VStack(alignment: .leading, spacing: 8) {
          Toggle("翻译显示完整注释", isOn: $model.configuration.showFullAnnotations)
            .accessibilityIdentifier("settings.translation.fullAnnotations")
          Text("仅在悬停详情中显示本地词典的完整注释。本地译文使用核心释义，多义仍用 / 分隔；此选项不会启用云翻译。")
            .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
      }
      GroupBox("离线词库") {
        VStack(alignment: .leading, spacing: 8) {
          Text("CC-CEDICT 中英词典 · 支持简体和繁体；英文释义沿用本地英汉词库。")
          Text("拼音词库负责候选和组句，翻译词库负责释义。没有可用释义时统一显示“无译文”，不会用拼音代替。")
            .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
      }
      GroupBox("翻译 API") {
        VStack(alignment: .leading, spacing: 12) {
          Toggle("启用云翻译，补全缺少本地译文的候选词", isOn: $model.configuration.enabled)
            .disabled(model.deletesCredentials)
            .accessibilityIdentifier("settings.translation.enabled")
          Text("开启并应用后，缺少本地译文的当前页候选词会发送给下方服务，可能产生费用。不会发送前后文、剪贴板、应用名称或已输入的文档。关闭时不发请求。")
            .font(.caption).foregroundStyle(.secondary)
          Text("本地有可用译义时不请求在线服务。在线候选显示来源，例如“腾讯:you”或“ai:you”；切换到译文后用数字选中，会完整提交服务返回的译文字段，来源标签不上屏。过长或无效响应整体拒收，不截断译文。")
            .font(.caption).foregroundStyle(.secondary)
          Picker("服务商", selection: $model.configuration.provider) {
            ForEach(ZIMETranslationConfiguration.Provider.allCases, id: \.self) { provider in
              Text(provider.title).tag(provider)
            }
          }.pickerStyle(.menu).accessibilityIdentifier("settings.translation.provider")
          if model.configuration.provider == .compatible {
            TextField("服务地址，例如 https://api.example.com/v1", text: $model.configuration.baseURL)
              .accessibilityIdentifier("settings.translation.endpoint")
            TextField("模型名称（使用服务商提供的标识）", text: $model.configuration.model)
              .accessibilityIdentifier("settings.translation.model")
          }
          if model.configuration.provider == .deepl {
            Picker("DeepL 账户", selection: $model.configuration.deeplFree) {
              Text("API Free").tag(true)
              Text("API Pro").tag(false)
            }.pickerStyle(.menu)
          }
          if model.configuration.provider == .tencent {
            TextField("地区，例如 ap-guangzhou", text: $model.configuration.region)
          }
          SecureField(credentialLabel + "（留空保留已存密钥）", text: $model.identifier)
            .disabled(model.deletesCredentials)
            .accessibilityIdentifier("settings.translation.key")
          if model.configuration.provider == .baidu || model.configuration.provider == .tencent {
            SecureField(model.configuration.provider == .baidu ? "密钥 Secret" : "SecretKey", text: $model.secret)
              .disabled(model.deletesCredentials)
          }
          Text("密钥仅保存在本机 macOS 钥匙串，不进入设置 JSON、项目或词库备份。更换服务地址需要为新地址保存密钥。")
            .font(.caption).foregroundStyle(.secondary)
          HStack {
            Button(model.testing ? "测试中…" : "测试连接（发送 hello）") { model.testConnection() }
              .disabled(model.testing || model.deletesCredentials)
            Spacer()
            Button("删除此服务密钥", role: .destructive) { confirmsDeletion = true }
              .disabled(model.deletesCredentials)
          }
          Text("使用窗口下方的“应用更改”保存本页；关闭窗口前会提醒未保存的修改。测试只发送 hello，不保存配置，也不自动启用云翻译。")
            .font(.caption).foregroundStyle(.secondary)
          if model.pendingChanges {
            Label("尚未应用", systemImage: "pencil.circle")
              .font(.caption).foregroundStyle(.secondary)
          }
          if !model.status.isEmpty { Text(model.status).font(.callout).textSelection(.enabled) }
        }.padding(8)
      }
    }
    .confirmationDialog("删除此服务密钥？", isPresented: $confirmsDeletion, titleVisibility: .visible) {
      Button("应用时删除密钥", role: .destructive) { model.stageCredentialDeletion() }
      Button("取消", role: .cancel) {}
    } message: {
      Text("应用更改后会关闭云翻译并删除当前服务的钥匙串密钥。应用前可以撤销。")
    }
  }

  private var credentialLabel: String {
    switch model.configuration.provider {
    case .compatible, .deepl: "API Key"
    case .baidu: "APP ID"
    case .tencent: "SecretId"
    }
  }
}
