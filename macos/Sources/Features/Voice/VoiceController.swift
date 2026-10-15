import AppKit
import AVFoundation
import Combine

/// 系统朗读与持久化历史的应用级服务。
@MainActor
final class VoiceController: ObservableObject {
    static let shared = VoiceController()
    @Published var entries: [VoiceHistoryEntry] = []
    @Published private(set) var originalRecordings: [OriginalVoiceHistoryReader.Recording] = []
    @Published private(set) var unreadableOriginalRecordings = 0
    private var selectedOriginalRoot: URL?
    @Published var settings: VoiceSettings = VoiceSettings() {
        didSet {
            if oldValue.rewriteBaseURL != settings.rewriteBaseURL,
               (try? ScriptRewriteRequest.endpoint(baseURL: oldValue.rewriteBaseURL ?? "")) !=
                (try? ScriptRewriteRequest.endpoint(baseURL: settings.rewriteBaseURL ?? "")) {
                rewriteToken = ""
                rewriteCredentialStatus = "改写地址已改变，请重新输入或读取对应令牌；已保存条目未删除。"
            }
            if oldValue.gatewayBaseURL != settings.gatewayBaseURL,
               (try? QwenTTSRequest.endpoint(baseURL: oldValue.gatewayBaseURL ?? "")) !=
                (try? QwenTTSRequest.endpoint(baseURL: settings.gatewayBaseURL ?? "")) {
                gatewayToken = ""
                gatewayCredentialStatus = "网关地址已改变，请重新输入或读取对应令牌；已保存条目未删除。"
            }
            if oldValue.isEnabled != settings.isEnabled {
                if !settings.isEnabled { stop() }
                (NSApp.delegate as? AppDelegate)?.setupRecoveredFeaturesMenu()
            }
            playback.rate = settings.rate
            var snapshot = settings
            if !settings.hasSafeGatewayAddress || !settings.hasSafeRewriteAddress {
                let previous = UserDefaults.standard.data(forKey: "recovered.voice.settings")
                    .flatMap { try? JSONDecoder().decode(VoiceSettings.self, from: $0) }
                snapshot = settings.persistenceSnapshot(previous: previous)
                if !settings.hasSafeGatewayAddress { gatewayCredentialStatus = "当前地址无效或含账号／查询参数，未保存；其他设置仍正常保存。" }
                if !settings.hasSafeRewriteAddress { rewriteCredentialStatus = "改写地址无效或含账号／查询参数，未保存；其他设置仍正常保存。" }
            }
            if let data = try? JSONEncoder().encode(snapshot) {
                UserDefaults.standard.set(data, forKey: "recovered.voice.settings")
            }
        }
    }
    let playback = SegmentedSpeechPlayer()
    @Published private(set) var transcriptSegments: [SpeechSegment] = []
    @Published private(set) var playingHistoryID: UUID?
    @Published private(set) var isPreparing = false
    @Published private(set) var isRewriting = false
    private let renderer = SystemSpeechRenderer()
    private var synthesisTask: Task<Void, Never>?
    private var synthesisGeneration = UUID()
    private let store = VoiceHistoryStore()
    private let audioHistory = VoiceAudioHistoryStore()
    @Published private(set) var savesAudioHistory = false
    @Published private(set) var historyMaxCount = VoiceHistoryRetention.defaultCount
    @Published private(set) var historyMaxMB = 300
    @Published private(set) var historyBytes: Int64 = 0
    @Published private(set) var isUpdatingHistory = false
    @Published private(set) var acceptsHistoryLimits = false
    @Published var gatewayToken = ""
    @Published var rewriteToken = ""
    @Published private(set) var rewriteCredentialStatus: String?
    @Published private(set) var rewriteNotice: String?
    @Published private(set) var gatewayCredentialStatus: String?
    @Published private(set) var isImportingGatewayToken = false
    @Published private(set) var fallbackNotice: String?
    private var replyTask: Task<Void, Never>?
    var isSpeaking: Bool { playback.isActive || isPreparing || replyTask != nil }

    func speakLatestReply(cwd: String?, terminalTitle: String?, isCurrentTerminal: @escaping @MainActor () -> Bool) {
        guard settings.isEnabled else { return }
        replyTask?.cancel()
        replyTask = nil
        guard let cwd, cwd.hasPrefix("/") else {
            showError("拿不到当前终端的目录，没法定位 Claude 的会话记录。")
            return
        }
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        replyTask = Task {
            do {
                let readTask = Task.detached(priority: .userInitiated) {
                    try Task.checkCancellation()
                    guard let record = try ClaudeReplyLocator.find(root: root, cwd: cwd, terminalTitle: terminalTitle) else {
                        return Optional<ClaudeAssistantReply>.none
                    }
                    return try ClaudeReplyReader.latestReply(in: record.file, sessionID: record.id)
                }
                let reply = try await withTaskCancellationHandler {
                    try await readTask.value
                } onCancel: {
                    readTask.cancel()
                }
                try Task.checkCancellation()
                guard isCurrentTerminal() else { replyTask = nil; return }
                replyTask = nil
                guard let reply else { showError("在这个目录下没找到可朗读的 Claude 助手回复。"); return }
                speak(reply.text, summary: "Claude 最新回复",
                      projectName: URL(fileURLWithPath: cwd).lastPathComponent,
                      terminalTitle: terminalTitle)
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled else { return }
                replyTask = nil
                showError("读取最新回复失败：\(error.localizedDescription)")
            }
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: "recovered.voice.settings"),
           let value = try? JSONDecoder().decode(VoiceSettings.self, from: data) { settings = value }
        do { entries = try store.load() } catch { showError(error.localizedDescription) }
        historyBytes = (try? audioHistory.totalBytes()) ?? 0
        savesAudioHistory = UserDefaults.standard.bool(forKey: "recovered.voice.audioHistoryEnabled")
        let count = UserDefaults.standard.integer(forKey: "recovered.voice.historyMaxCount")
        let megabytes = UserDefaults.standard.integer(forKey: "recovered.voice.historyMaxMB")
        historyMaxCount = count > 0 ? count : VoiceHistoryRetention.defaultCount
        historyMaxMB = megabytes >= 10 && megabytes <= Int(Int64.max >> 20) ? megabytes : 300
        acceptsHistoryLimits = UserDefaults.standard.bool(forKey: "recovered.voice.acceptsHistoryLimits")
        selectedOriginalRoot = UserDefaults.standard.string(forKey: "recovered.voice.originalHistoryRoot")
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        playback.rate = settings.rate
    }

    func speakForComparison(_ text: String, useRewrite: Bool) {
        speak(text, record: false, rewriteComparison: useRewrite)
    }

    func speak(_ text: String, summary: String? = nil, record: Bool = true, prepared: Bool = false, rewriteComparison: Bool? = nil,
               projectName: String? = nil, terminalTitle: String? = nil) {
        guard settings.isEnabled else { return }
        replyTask?.cancel()
        replyTask = nil
        let cleaned = prepared ? [text].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            : SpeechTextCleaner(codeMode: settings.codeMode).cleanIntoSegments(text)
        guard !cleaned.isEmpty else {
            showError("这段内容清洗之后没有可念的文字（可能整段都是代码或符号）。")
            return
        }
        let remote = settings.engine == .remote
        var endpoint: URL?
        var initialFallback: (message: String, permission: Bool)?
        if remote {
            if gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                initialFallback = ("没读到网关密钥", true)
            } else {
                do { endpoint = try QwenTTSRequest.endpoint(baseURL: settings.gatewayBaseURL ?? "") }
                catch { initialFallback = ("网关基础地址无效", true) }
            }
        }
        let remoteEndpoint = endpoint
        let remoteToken = gatewayToken
        let remoteVoice = settings.gatewayVoiceName
        let remoteModel = settings.gatewayModel ?? QwenTTSRequest.defaultModel
        let shouldRewrite = !prepared && ScriptRewriter.shouldRewrite(text,
            enabled: settings.isRewriteEnabled,
            minimumLength: settings.effectiveRewriteMinimumLength,
            comparison: rewriteComparison)
        let rewriteBase = settings.usesSeparateRewriteGateway ? settings.rewriteBaseURL ?? "" : settings.gatewayBaseURL ?? ""
        let rewriteSecret = settings.usesSeparateRewriteGateway ? rewriteToken : gatewayToken
        let rewriteModel = settings.rewriteModel ?? VoiceSettings.defaultRewriteModel
        let rewriteStrength = ScriptRewriteRequest.Strength(rawValue: settings.rewriteStrength ?? "") ?? .conservative
        let codeMode = settings.codeMode
        if record && !UserDefaults.standard.bool(forKey: "recovered.voice.didExplainAudioHistory") {
            setAudioHistoryEnabled(true)
            UserDefaults.standard.set(true, forKey: "recovered.voice.didExplainAudioHistory")
        }
        if record && savesAudioHistory && !acceptsHistoryLimits &&
            !UserDefaults.standard.bool(forKey: "recovered.voice.didExplainHistoryLimits") {
            acceptsHistoryLimits = confirmHistoryLimits(count: historyMaxCount, megabytes: historyMaxMB)
            UserDefaults.standard.set(acceptsHistoryLimits, forKey: "recovered.voice.acceptsHistoryLimits")
            UserDefaults.standard.set(true, forKey: "recovered.voice.didExplainHistoryLimits")
        }
        stop()
        transcriptSegments = cleaned.map { SpeechSegment(text: $0) }
        if let initialFallback { reportFallback(initialFallback) }
        let token = UUID()
        synthesisGeneration = token
        let voice = settings.voiceIdentifier
        isPreparing = true
        synthesisTask = Task {
            defer {
                if synthesisGeneration == token { isPreparing = false; isRewriting = false; synthesisTask = nil }
            }
            do {
                var pieces = cleaned
                var usedRewrite = false
                if shouldRewrite {
                    if !rewriteSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       let rewriteEndpoint = try? ScriptRewriteRequest.endpoint(baseURL: rewriteBase) {
                        guard confirmRemoteSpeech(endpoint: rewriteEndpoint, pieces: [text], purpose: "模型改写（\(rewriteModel)）", isRewrite: true) else { return }
                        isRewriting = true
                        do {
                            let rewritten = try await ScriptRewriter.rewrite(baseURL: rewriteBase, token: rewriteSecret,
                                model: rewriteModel, text: text, strength: rewriteStrength)
                            try Task.checkCancellation()
                            guard synthesisGeneration == token else { return }
                            if let rewritten {
                                let result = SpeechTextCleaner(codeMode: codeMode).cleanIntoSegments(rewritten)
                                if !result.isEmpty { pieces = result; usedRewrite = true; rewriteNotice = "本次使用模型改写稿，请核对事实与数字。" }
                                else { rewriteNotice = "改写无可朗读内容，使用规则清洗稿。" }
                            } else { rewriteNotice = "改写未成功，使用规则清洗稿。" }
                        } catch {
                            try Task.checkCancellation()
                            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
                            guard synthesisGeneration == token else { return }
                            rewriteNotice = "改写失败，使用规则清洗稿。"
                        }
                        isRewriting = false
                    } else { rewriteNotice = "改写网关未配置，使用规则清洗稿。" }
                }
                try Task.checkCancellation()
                guard synthesisGeneration == token else { return }
                if let remoteEndpoint,
                   !confirmRemoteSpeech(endpoint: remoteEndpoint, pieces: pieces) { return }
                try Task.checkCancellation()
                var clips: [SpeechAudioSegment] = []
                for piece in pieces {
                    try Task.checkCancellation()
                    let audio: RenderedSpeechClip
                    if let remoteEndpoint {
                        do {
                            let result = try await QwenTTSClient().synthesize(endpoint: remoteEndpoint, text: piece,
                                voice: remoteVoice, model: remoteModel, token: remoteToken)
                            // 未读取真实帧数时用 0 标记；播放和分段使用原生解码时长，不推算帧数。
                            audio = RenderedSpeechClip(data: result.data, duration: result.duration, frameCount: 0)
                        } catch {
                            try Task.checkCancellation()
                            guard synthesisGeneration == token else { return }
                            guard let reason = SpeechFallbackPolicy.reason(for: error) else { throw CancellationError() }
                            reportFallback(reason)
                            try Task.checkCancellation()
                            audio = try await renderer.render(piece, voiceIdentifier: voice)
                        }
                    } else {
                        audio = try await renderer.render(piece, voiceIdentifier: voice)
                    }
                    try Task.checkCancellation()
                    guard synthesisGeneration == token else { return }
                    clips.append(SpeechAudioSegment(text: piece, audio: audio))
                }
                playback.rate = settings.rate
                try playback.play(clips)
                transcriptSegments = try SpeechSegment.timed(clips)
                if record && savesAudioHistory {
                    entries = try audioHistory.save(clips, summary: summary, wasRewritten: usedRewrite,
                                                    projectName: projectName, terminalTitle: terminalTitle)
                    if acceptsHistoryLimits {
                        entries = try audioHistory.enforceLimits(maxCount: historyMaxCount,
                            maxBytes: Int64(historyMaxMB) << 20).entries
                    }
                    historyBytes = try audioHistory.totalBytes()
                }
            } catch is CancellationError { }
            catch {
                guard synthesisGeneration == token else { return }
                showError(error.localizedDescription)
            }
        }
    }

    func saveGatewayToken(forRewrite: Bool = false) {
        do {
            let endpoint = try forRewrite ? ScriptRewriteRequest.endpoint(baseURL: settings.rewriteBaseURL ?? "") : QwenTTSRequest.endpoint(baseURL: settings.gatewayBaseURL ?? "")
            let token = forRewrite ? rewriteToken : gatewayToken
            let alert = NSAlert()
            alert.messageText = "保存访问令牌到钥匙串？"
            alert.informativeText = "按当前网关地址保存：\(endpoint.absoluteString)\n不会写入配置文件，也不会读取或覆盖原版软件的密钥。已有本恢复版同地址令牌会被替换；此操作不发送网络请求。"
            alert.addButton(withTitle: "保存")
            alert.addButton(withTitle: "取消")
            alert.buttons.first?.keyEquivalent = ""
            alert.buttons.last?.keyEquivalent = "\r"
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            try VoiceGatewayCredentials.save(token, endpoint: endpoint,
                service: forRewrite ? "com.mitchellh.ghostty.recovered.voice.rewrite" : "com.mitchellh.ghostty.recovered.voice.gateway")
            setCredentialStatus("当前网关令牌已保存到钥匙串。", forRewrite: forRewrite)
        } catch { setCredentialStatus(error.localizedDescription, forRewrite: forRewrite) }
    }

    func loadGatewayToken(forRewrite: Bool = false) {
        do {
            let endpoint = try forRewrite ? ScriptRewriteRequest.endpoint(baseURL: settings.rewriteBaseURL ?? "") : QwenTTSRequest.endpoint(baseURL: settings.gatewayBaseURL ?? "")
            guard let token = try VoiceGatewayCredentials.read(endpoint: endpoint,
                service: forRewrite ? "com.mitchellh.ghostty.recovered.voice.rewrite" : "com.mitchellh.ghostty.recovered.voice.gateway") else {
                setCredentialStatus("本恢复版钥匙串未找到当前地址的令牌；内存令牌未改变。", forRewrite: forRewrite)
                return
            }
            if forRewrite { rewriteToken = token } else { gatewayToken = token }
            setCredentialStatus("已读取当前网关令牌；尚未发送任何请求。", forRewrite: forRewrite)
        } catch { setCredentialStatus(error.localizedDescription, forRewrite: forRewrite) }
    }

    func importGatewayTokenFromLoginShell() {
        guard !isImportingGatewayToken else { return }
        do {
            let endpoint = try QwenTTSRequest.endpoint(baseURL: settings.gatewayBaseURL ?? "")
            let alert = NSAlert()
            alert.messageText = "从终端环境导入访问令牌？"
            alert.informativeText = "将启动你的登录 Shell，仅读取 ANTHROPIC_AUTH_TOKEN，并按当前地址保存到本恢复版钥匙串：\n\(endpoint.absoluteString)\n不会发送网络请求，也不会读取原版软件的钥匙串。"
            alert.addButton(withTitle: "读取并保存")
            alert.addButton(withTitle: "取消")
            alert.buttons.first?.keyEquivalent = ""
            alert.buttons.last?.keyEquivalent = "\r"
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            isImportingGatewayToken = true
            gatewayCredentialStatus = "正在读取终端环境…（要等 shell 加载配置，约一两秒）"
            Task {
                defer { isImportingGatewayToken = false }
                do {
                    guard let token = try await Task.detached(priority: .userInitiated, operation: {
                        try LoginShellTokenImporter.read()
                    }).value else {
                        gatewayCredentialStatus = "在终端环境里没找到 ANTHROPIC_AUTH_TOKEN。"
                        return
                    }
                    try VoiceGatewayCredentials.save(token, endpoint: endpoint)
                    gatewayToken = token
                    gatewayCredentialStatus = "已从终端环境导入，并保存到系统钥匙串。"
                } catch {
                    gatewayCredentialStatus = "导入失败：\(error.localizedDescription)"
                }
            }
        } catch { gatewayCredentialStatus = error.localizedDescription }
    }

    private func setCredentialStatus(_ message: String, forRewrite: Bool) {
        if forRewrite { rewriteCredentialStatus = message } else { gatewayCredentialStatus = message }
    }

    private func reportFallback(_ reason: (message: String, permission: Bool)) {
        fallbackNotice = "本次含系统音色：\(reason.message)"
        let key = reason.permission ? "recovered.voice.didWarnPermission" : "recovered.voice.didWarnBackend"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let alert = NSAlert()
        alert.messageText = "本次改用系统音色"
        alert.informativeText = "\(reason.message)。本段会在本机合成，音源设置没有改变，下次仍会尝试网关。此类提示不再重复，原因会保留在朗读控件上。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    private func confirmRemoteSpeech(endpoint: URL, pieces: [String], purpose: String = "语音合成", isRewrite: Bool = false) -> Bool {
        let alert = NSAlert()
        alert.messageText = "确认发送文字用于\(purpose)"
        let cancellation = isRewrite ? "取消不发送改写请求，也不继续朗读。" : "取消不发送语音请求；此前已经确认发送的改写请求无法撤回。"
        alert.informativeText = "目的地址：\(endpoint.absoluteString)\n将发送下面的完整文字和对应网关令牌，可能产生服务费用。模型改写以一条用户消息提交，语音按段提交；音频 GET 不传令牌。\n\(cancellation)"
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        scroll.hasVerticalScroller = true
        let preview = NSTextView(frame: scroll.bounds)
        preview.isEditable = false
        preview.font = .systemFont(ofSize: 12)
        preview.isVerticallyResizable = true
        preview.textContainer?.widthTracksTextView = true
        preview.string = pieces.joined(separator: "\n\n")
        scroll.documentView = preview
        alert.accessoryView = scroll
        alert.addButton(withTitle: "确认发送")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.keyEquivalent = ""
        alert.buttons.last?.keyEquivalent = "\r"
        return alert.runModal() == .alertFirstButtonReturn
    }

    func setAudioHistoryEnabled(_ enabled: Bool) {
        if enabled && !savesAudioHistory {
            let alert = NSAlert()
            alert.messageText = "允许保存朗读录音？"
            alert.informativeText = "录音内容与你的对话一样敏感。开启后会在本机保存音频和稿件，不上传，也不参与 Time Machine 备份。默认最多保留 \(historyMaxCount) 次、\(historyMaxMB) MB；超限最旧录音会移入回收站，可以找回。关闭后不再保存新录音，不会删除已有录音。"
            alert.addButton(withTitle: "开启保存")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            acceptsHistoryLimits = true
            UserDefaults.standard.set(true, forKey: "recovered.voice.acceptsHistoryLimits")
            UserDefaults.standard.set(true, forKey: "recovered.voice.didExplainHistoryLimits")
        }
        savesAudioHistory = enabled
        if enabled { UserDefaults.standard.set(true, forKey: "recovered.voice.didExplainAudioHistory") }
        UserDefaults.standard.set(enabled, forKey: "recovered.voice.audioHistoryEnabled")
    }

    private func confirmHistoryLimits(count: Int, megabytes: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = "应用朗读历史限额？"
        alert.informativeText = "恢复版录音将最多保留 \(count) 次、\(megabytes) MB。超过任一限额时，最旧录音及稿件会移入回收站，可找回；不处理原版应用的数据。"
        alert.addButton(withTitle: "应用限额")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func applyHistoryLimits(count: Int, megabytes: Int) {
        guard !isUpdatingHistory else { return }
        guard count >= 1, megabytes >= 10, megabytes <= Int(Int64.max >> 20) else {
            showError("历史条数至少为 1，容量至少为 10 MB，且不能超出可表示范围。")
            return
        }
        guard confirmHistoryLimits(count: count, megabytes: megabytes) else { return }
        isUpdatingHistory = true
        Task {
            defer { isUpdatingHistory = false }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try VoiceAudioHistoryStore().enforceLimits(maxCount: count, maxBytes: Int64(megabytes) << 20)
                }.value
                entries = result.entries
                historyBytes = try VoiceAudioHistoryStore().totalBytes()
                historyMaxCount = count
                historyMaxMB = megabytes
                acceptsHistoryLimits = true
                UserDefaults.standard.set(count, forKey: "recovered.voice.historyMaxCount")
                UserDefaults.standard.set(megabytes, forKey: "recovered.voice.historyMaxMB")
                UserDefaults.standard.set(true, forKey: "recovered.voice.acceptsHistoryLimits")
                UserDefaults.standard.set(true, forKey: "recovered.voice.didExplainHistoryLimits")
            } catch { showError("限额未应用：\(error.localizedDescription)") }
        }
    }

    func applyHistoryLimits(countText: String, megabytesText: String) {
        guard let count = Int(countText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let megabytes = Int(megabytesText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            showError("历史条数与容量请输入有效整数，原限额没有改变。")
            return
        }
        applyHistoryLimits(count: count, megabytes: megabytes)
    }

    func playHistory(_ entry: VoiceHistoryEntry, startingAt index: Int? = nil) {
        guard settings.isEnabled else { return }
        if let index, playingHistoryID == entry.id, playback.duration > 0 {
            jumpToTranscriptSegment(index)
            return
        }
        if !entry.hasRecordedAudio { speak(entry.text, record: false, prepared: true); return }
        stop()
        if entry.wasRewritten == true { rewriteNotice = "重播已保存的模型改写稿，不重新调用模型。" }
        do {
            playback.rate = settings.rate
            try playback.play(audioHistory.load(entry))
            transcriptSegments = entry.segments
            playingHistoryID = entry.id
            if let index { try playback.jump(to: index) }
        } catch { showError("录音读取失败：\(error.localizedDescription)") }
    }

    func revealHistory(_ entry: VoiceHistoryEntry) {
        guard let directory = audioHistory.recordingURL(for: entry) else {
            showError("找不到这条录音的本地目录，原索引未修改。")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    func deleteHistory(_ entry: VoiceHistoryEntry) {
        guard entry.hasRecordedAudio, confirmTrash(count: 1) else { return }
        trashHistory(ids: [entry.id])
    }

    func clearHistory() {
        let ids = Set(entries.filter(\.hasRecordedAudio).map(\.id))
        guard !ids.isEmpty, confirmTrash(count: ids.count) else { return }
        trashHistory(ids: ids)
    }

    private func confirmTrash(count: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = count == 1 ? "将这条朗读录音移到废纸篓？" : "将全部朗读录音移到废纸篓？"
        alert.informativeText = "将处理本恢复版的 \(count) 条录音和稿件，不会处理原版录音；之后可以从废纸篓找回。"
        alert.addButton(withTitle: "移到废纸篓")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func trashHistory(ids: Set<UUID>) {
        guard !isUpdatingHistory else { return }
        isUpdatingHistory = true
        Task {
            defer { isUpdatingHistory = false }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try VoiceAudioHistoryStore().trash(ids)
                }.value
                if let playingHistoryID, ids.contains(playingHistoryID) { stop() }
                entries = result.entries
                historyBytes = try VoiceAudioHistoryStore().totalBytes()
            } catch { showError("录音未移入废纸篓：\(error.localizedDescription)") }
        }
    }

    func jumpToTranscriptSegment(_ index: Int) {
        do { try playback.jump(to: index) }
        catch { showError("片段定位失败：\(error.localizedDescription)") }
    }

    func reloadHistory(restoreRecoveredIndex: Bool = true) {
        guard !isUpdatingHistory else { return }
        isUpdatingHistory = true
        let originalRoot = selectedOriginalRoot ?? OriginalVoiceHistoryReader.originalRoot
        Task {
            defer { isUpdatingHistory = false }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let current = restoreRecoveredIndex ? try VoiceAudioHistoryStore().restoreIndex() : try VoiceHistoryStore().load()
                    let original = try originalRoot.map { try OriginalVoiceHistoryReader.scan(root: $0) }
                    return (current, original, try VoiceAudioHistoryStore().totalBytes())
                }.value
                entries = result.0
                originalRecordings = result.1?.recordings ?? []
                unreadableOriginalRecordings = result.1?.unreadableCount ?? 0
                historyBytes = result.2
            } catch { showError("历史刷新失败，原索引保留：\(error.localizedDescription)") }
        }
    }

    func chooseOriginalHistoryRoot() {
        let panel = NSOpenPanel()
        panel.title = "选择原版录音目录（只读）"
        panel.message = "请选择包含各条录音子目录的 VoiceHistory 根目录。只读取，不迁移或清理原文件。"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let root = panel.url else { return }
        selectedOriginalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        UserDefaults.standard.set(selectedOriginalRoot?.path, forKey: "recovered.voice.originalHistoryRoot")
        reloadHistory(restoreRecoveredIndex: false)
    }

    func playOriginalHistory(_ recording: OriginalVoiceHistoryReader.Recording) {
        guard settings.isEnabled else { return }
        stop()
        if recording.record.wasRewritten == true { rewriteNotice = "重播原版模型改写录音，不重新调用模型。" }
        do {
            let clips = try OriginalVoiceHistoryReader.audio(recording)
            playback.rate = settings.rate
            try playback.play(clips)
            transcriptSegments = try SpeechSegment.timed(clips)
        } catch { showError("原版录音读取失败，未修改原文件：\(error.localizedDescription)") }
    }

    func importOriginalHistory(_ recording: OriginalVoiceHistoryReader.Recording) {
        guard !isUpdatingHistory else { return }
        let alert = NSAlert()
        alert.messageText = "导入这条原版录音？"
        alert.informativeText = "会把音频和稿件复制到恢复版目录；原版文件保持不变。重复导入同一记录不会产生副本。"
        alert.addButton(withTitle: "导入副本")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        isUpdatingHistory = true
        Task {
            defer { isUpdatingHistory = false }
            do {
                entries = try await Task.detached(priority: .userInitiated) {
                    try VoiceAudioHistoryStore().importOriginal(recording)
                }.value
                historyBytes = try VoiceAudioHistoryStore().totalBytes()
            } catch { showError("原版录音导入失败，原文件未修改：\(error.localizedDescription)") }
        }
    }

    func togglePause() {
        guard settings.isEnabled else { return }
        playback.togglePause()
    }

    func stop() {
        replyTask?.cancel()
        replyTask = nil
        synthesisGeneration = UUID()
        synthesisTask?.cancel()
        synthesisTask = nil
        renderer.cancel()
        isPreparing = false
        isRewriting = false
        playback.stop()
        playingHistoryID = nil
        fallbackNotice = nil
        rewriteNotice = nil
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "语音朗读"
        alert.informativeText = message
        alert.runModal()
    }
}
