import Foundation

/// 语音朗读设置。枚举值根据安装包中保留的 Swift 类型名建立，服务字段待确认。
struct VoiceSettings: Codable, Equatable {
    struct RewriteModel: Identifiable, Equatable {
        let id: String
        let name: String
        let note: String
    }
    static let defaultRewriteModel = "claude-haiku-4-5"
    static let rewriteModels = [
        RewriteModel(id: "claude-haiku-4-5", name: "Haiku 4.5", note: "最快最省，推荐"),
        RewriteModel(id: "claude-sonnet-5", name: "Sonnet 5", note: "质量更好，慢一些"),
        RewriteModel(id: "claude-opus-5", name: "Opus 5", note: "最好，但慢且贵")
    ]
    var rewriteModel: String?
    var rewriteStrength: String?
    var rewriteBaseURL: String?
    private var rewriteUseSeparateGateway: Bool?
    var usesSeparateRewriteGateway: Bool {
        get { rewriteUseSeparateGateway ?? false }
        set { rewriteUseSeparateGateway = newValue }
    }
    private var rewriteEnabled: Bool?
    var isRewriteEnabled: Bool {
        get { rewriteEnabled ?? false }
        set { rewriteEnabled = newValue }
    }
    var rewriteMinimumLength: Int?
    var effectiveRewriteMinimumLength: Int {
        let value = rewriteMinimumLength ?? 120
        return value > 0 ? value : 120
    }

    struct GatewayVoice: Identifiable, Equatable {
        let id: String
        let name: String
        let trait: String
    }

    static let gatewayVoices = [
        GatewayVoice(id: "longanlufeng", name: "龙安鲁风", trait: "明亮开朗"),
        GatewayVoice(id: "longanlingxin", name: "龙安灵心", trait: "知心温暖"),
        GatewayVoice(id: "longanlingxi", name: "龙安灵希", trait: "可爱甜美"),
        GatewayVoice(id: "longanhuan_v3.6", name: "龙安欢", trait: "自然平实")
    ]
    private static let obsoleteVoices: Set<String> = [
        "Cherry", "Serena", "Ethan", "Chelsie", "longxiaochun", "longxiaochun_v2",
        "longwan", "longcheng", "longhua", "longxiaoxia"
    ]
    private var gatewayVoice: String?
    var gatewayBaseURL: String?
    var gatewayModel: String?
    var hasSafeGatewayAddress: Bool {
        Self.isSafeGatewayAddress(gatewayBaseURL)
    }
    var hasSafeRewriteAddress: Bool { Self.isSafeGatewayAddress(rewriteBaseURL) }
    private static func isSafeGatewayAddress(_ value: String?) -> Bool {
        guard let raw = value, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return true }
        guard raw.rangeOfCharacter(from: .controlCharacters) == nil,
              let url = URLComponents(string: raw.trimmingCharacters(in: .whitespaces)) else { return false }
        return url.scheme?.lowercased() == "https" && url.host?.isEmpty == false &&
            url.user == nil && url.password == nil && url.query == nil && url.fragment == nil
    }

    func persistenceSnapshot(previous: VoiceSettings?) -> VoiceSettings {
        var snapshot = self
        if !hasSafeGatewayAddress {
            snapshot.gatewayBaseURL = previous?.hasSafeGatewayAddress == true ? previous?.gatewayBaseURL : nil
        }
        if !hasSafeRewriteAddress {
            snapshot.rewriteBaseURL = previous?.hasSafeRewriteAddress == true ? previous?.rewriteBaseURL : nil
        }
        return snapshot
    }
    var gatewayVoiceName: String {
        get {
            let value = gatewayVoice ?? "longanlufeng"
            return Self.obsoleteVoices.contains(value) ? "longanlufeng" : value
        }
        set { gatewayVoice = newValue }
    }

    enum Engine: String, Codable, CaseIterable, Identifiable {
        case system
        case remote

        var id: String { rawValue }
    }

    enum CodeMode: String, Codable, CaseIterable, Identifiable {
        case skip, simplify, verbatim

        var id: String { rawValue }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if raw == "read" { self = .verbatim; return }
            guard let value = Self(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "未知代码朗读模式")
            }
            self = value
        }
    }

    var engine: Engine = .system
    var codeMode: CodeMode = .skip
    var rate: Double = 1.0
    var voiceIdentifier: String?
    // 旧版设置没有此字段，保持原有可朗读状态。
    private var enabled: Bool?
    var isEnabled: Bool {
        get { enabled ?? true }
        set { enabled = newValue }
    }
    private var showOverlay: Bool?
    var isOverlayShown: Bool {
        get { showOverlay ?? true }
        set { showOverlay = newValue }
    }
}
