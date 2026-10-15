import AVFoundation
import SwiftUI

/// 语音朗读设置界面。
struct VoiceSettingsView: View {
    private static let comparisonText = """
    ## 三个刻意绕开的坑

    | 决策 | 绕开了什么 |
    |---|---|
    | 设置不写进配置文件，单独存 | 避免以后同步官方更新时反复处理冲突 |

    ```swift
    item = menu.addItem(withTitle: "朗读选中内容", action: #selector(speakSelection(_:)))
    ```

    改动点在 /Users/mac/Desktop/Vibe coding/二开软件/ghostty-main/macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift:1576。
    """

    @Binding var settings: VoiceSettings
    @ObservedObject private var controller = VoiceController.shared
    @State private var historyCount = "50"
    @State private var historyMB = "300"
    @State private var customGatewayVoice = false
    @State private var customRewriteModel = false

    var body: some View {
        Form {
            Toggle("启用语音朗读", isOn: $settings.isEnabled)
            Toggle("在终端右上角显示小喇叭", isOn: $settings.isOverlayShown)
                .disabled(!settings.isEnabled)
            Text("这颗喇叭只在当前终端正在跟 Claude 对话时出现。关掉它之后，仍然可以用右键菜单和快捷键朗读。")
                .font(.caption).foregroundColor(.secondary)
            Section("朗读引擎") {
                Picker("引擎", selection: $settings.engine) {
                    Text("系统内置音色").tag(VoiceSettings.Engine.system)
                    Text("公司语音模型").tag(VoiceSettings.Engine.remote)
                }
                if settings.engine == .system {
                    Text("用 macOS 自带的朗读能力。离线可用、不花钱，音色不如公司模型自然。")
                        .font(.caption).foregroundColor(.secondary)
                    let voices = SystemVoiceCatalog.chineseVoices()
                    if let preferred = SystemVoiceCatalog.preferredChineseVoice(voices) {
                        Picker("系统音色", selection: Binding(get: {
                            settings.voiceIdentifier.flatMap(AVSpeechSynthesisVoice.init(identifier:))?.identifier
                                ?? preferred.identifier
                        }, set: { settings.voiceIdentifier = $0 })) {
                            ForEach(voices, id: \.identifier) { voice in
                                Text("\(voice.name) · \(voice.language)").tag(voice.identifier)
                            }
                        }
                        Text("当前系统音色：\((settings.voiceIdentifier.flatMap(AVSpeechSynthesisVoice.init(identifier:)) ?? preferred).name)")
                            .font(.caption).foregroundColor(.secondary)
                    } else {
                        Text("没找到中文音色").foregroundColor(.secondary)
                    }
                }
                if settings.engine == .remote {
                    Text("走公司网关上的语音模型，音色自然。需要密钥，且该密钥要有语音接口的访问权限。")
                        .font(.caption).foregroundColor(.secondary)
                    TextField("网关基础地址", text: Binding(get: { settings.gatewayBaseURL ?? "" }, set: { settings.gatewayBaseURL = $0 }))
                    TextField("模型编号", text: Binding(get: { settings.gatewayModel ?? QwenTTSRequest.defaultModel }, set: { settings.gatewayModel = $0 }))
                    SecureField("访问令牌（仅本次运行）", text: $controller.gatewayToken)
                    HStack {
                        Button("保存到钥匙串…") { controller.saveGatewayToken() }.disabled(controller.gatewayToken.isEmpty)
                        Button("从钥匙串读取") { controller.loadGatewayToken() }
                        Button("从终端环境导入") { controller.importGatewayTokenFromLoginShell() }
                            .disabled(controller.isImportingGatewayToken)
                    }
                    if let status = controller.gatewayCredentialStatus { Text(status).font(.caption).foregroundColor(.secondary) }
                    Text("令牌不写入配置；“从终端环境导入”会启动登录 shell 读取 ANTHROPIC_AUTH_TOKEN。发送前会显示目的地址和完整文字供确认。")
                        .font(.caption).foregroundColor(.secondary)
                    Picker("音色", selection: Binding(get: {
                        customGatewayVoice || !VoiceSettings.gatewayVoices.contains(where: { $0.id == settings.gatewayVoiceName })
                            ? "__custom" : settings.gatewayVoiceName
                    }, set: { value in
                        customGatewayVoice = value == "__custom"
                        if !customGatewayVoice { settings.gatewayVoiceName = value }
                    })) {
                        ForEach(VoiceSettings.gatewayVoices) { voice in
                            Text("\(voice.name) · \(voice.trait)").tag(voice.id)
                        }
                        Text("其他（手填参数名）").tag("__custom")
                    }
                    if customGatewayVoice || !VoiceSettings.gatewayVoices.contains(where: { $0.id == settings.gatewayVoiceName }) {
                        TextField("音色参数名", text: $settings.gatewayVoiceName)
                    }
                }
                Picker("代码内容", selection: $settings.codeMode) {
                    Text("跳过，只说一句有代码").tag(VoiceSettings.CodeMode.skip)
                    Text("简化后朗读").tag(VoiceSettings.CodeMode.simplify)
                    Text("逐字朗读").tag(VoiceSettings.CodeMode.verbatim)
                }
                Button("念一句话试试") {
                    controller.speakForComparison("你好，这是一段语音朗读测试。", useRewrite: false)
                }
                .disabled(!settings.isEnabled || controller.isSpeaking)
                DisclosureGroup("选不中文字怎么办") {
                    Text("Claude Code 这类程序运行时会接管鼠标操作。按住 Shift 再拖选、按住 Shift 再右键，就能正常选择文字和打开菜单。这是终端的固有行为，不是朗读功能的问题。")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            Section("模型改写") {
                Toggle("启用模型改写", isOn: $settings.isRewriteEnabled)
                Picker("改写力度", selection: Binding(get: { ScriptRewriteRequest.Strength(rawValue: settings.rewriteStrength ?? "")?.rawValue ?? "conservative" }, set: { settings.rewriteStrength = $0 })) {
                    Text("保守").tag("conservative")
                    Text("自然").tag("natural")
                }
                TextField("最小字数", value: Binding(get: { settings.effectiveRewriteMinimumLength },
                                                     set: { settings.rewriteMinimumLength = $0 }), format: .number)
                Toggle("改写使用独立网关", isOn: $settings.usesSeparateRewriteGateway)
                if settings.usesSeparateRewriteGateway {
                    TextField("改写网关地址", text: Binding(get: { settings.rewriteBaseURL ?? "" }, set: { settings.rewriteBaseURL = $0 }))
                    SecureField("改写令牌（仅本次运行）", text: $controller.rewriteToken)
                    HStack {
                        Button("保存改写令牌…") { controller.saveGatewayToken(forRewrite: true) }.disabled(controller.rewriteToken.isEmpty)
                        Button("读取改写令牌") { controller.loadGatewayToken(forRewrite: true) }
                    }
                    if let status = controller.rewriteCredentialStatus { Text(status).font(.caption).foregroundColor(.secondary) }
                }
                Picker("模型", selection: Binding(get: {
                    let model = settings.rewriteModel ?? VoiceSettings.defaultRewriteModel
                    return customRewriteModel || !VoiceSettings.rewriteModels.contains(where: { $0.id == model }) ? "__custom" : model
                }, set: { value in
                    customRewriteModel = value == "__custom"
                    if !customRewriteModel { settings.rewriteModel = value }
                })) {
                    ForEach(VoiceSettings.rewriteModels) { model in Text(model.name).tag(model.id) }
                    Text("其他（手填模型编号）").tag("__custom")
                }
                if customRewriteModel || !VoiceSettings.rewriteModels.contains(where: { $0.id == (settings.rewriteModel ?? VoiceSettings.defaultRewriteModel) }) {
                    TextField("模型编号", text: Binding(get: { settings.rewriteModel ?? VoiceSettings.defaultRewriteModel }, set: { settings.rewriteModel = $0 }))
                }
                if let model = VoiceSettings.rewriteModels.first(where: { $0.id == (settings.rewriteModel ?? VoiceSettings.defaultRewriteModel) }) {
                    Text("原包备注：\(model.note)").font(.caption).foregroundColor(.secondary)
                }
                Text("达到最小字数且不超过 8000 字时改写。非正阈值按默认 120；发送前确认，失败使用规则清洗稿。模型可能改变细节，请核对事实。")
                    .font(.caption).foregroundColor(.secondary)
                Divider()
                Text("对比一下再决定").font(.headline)
                Text("用同一段示例文本（含表格、代码块、长路径）分别念一遍，听完你就知道值不值得开。")
                    .font(.caption).foregroundColor(.secondary)
                HStack {
                    Button("试听 规则清洗版") {
                        controller.speakForComparison(Self.comparisonText, useRewrite: false)
                    }
                    Button("试听 模型改写版") {
                        controller.speakForComparison(Self.comparisonText, useRewrite: true)
                    }
                }
                .disabled(!settings.isEnabled || controller.isSpeaking)
            }

            Section("播放") {
                HStack {
                    Text("速度")
                    Slider(value: $settings.rate, in: 0.5...2.0, step: 0.1)
                    Text(String(format: "%gx", settings.rate))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
            Section("录音历史") {
                Toggle("保存朗读录音", isOn: Binding(get: { controller.savesAudioHistory },
                                                     set: { controller.setAudioHistoryEnabled($0) }))
                Text("把念过的内容存成录音，方便回听。录音只存在这台电脑上，不上传，也不参与 Time Machine 备份。")
                    .font(.caption).foregroundColor(.secondary)
                TextField("最多保留次数", text: $historyCount).disabled(controller.isUpdatingHistory)
                TextField("容量上限（MB）", text: $historyMB).disabled(controller.isUpdatingHistory)
                Button("应用限额") { controller.applyHistoryLimits(countText: historyCount, megabytesText: historyMB) }
                    .disabled(controller.isUpdatingHistory)
                Text(controller.acceptsHistoryLimits
                     ? "已应用：\(controller.historyMaxCount) 次、\(controller.historyMaxMB) MB。超限录音移入回收站。"
                     : "自动清理未开启；应用限额后超限最旧录音会移入回收站。")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 450)
        .padding()
        .onAppear { historyCount = String(controller.historyMaxCount); historyMB = String(controller.historyMaxMB) }
    }
}
