import Foundation

@main
struct CheckVoiceSettings {
    static func main() throws {
        let legacy = Data(#"{"engine":"system","codeMode":"read","rate":1}"#.utf8)
        var settings = try JSONDecoder().decode(VoiceSettings.self, from: legacy)
        precondition(settings.isEnabled && settings.isOverlayShown && settings.codeMode == .verbatim)
        precondition(settings.gatewayVoiceName == "longanlufeng")
        let chineseVoices = SystemVoiceCatalog.chineseVoices()
        precondition(chineseVoices.allSatisfy { $0.language.lowercased().hasPrefix("zh") })
        if let preferred = SystemVoiceCatalog.preferredChineseVoice(chineseVoices) {
            precondition(chineseVoices.contains { $0.identifier == preferred.identifier })
        } else {
            precondition(chineseVoices.isEmpty)
        }
        precondition(settings.effectiveRewriteMinimumLength == 120)
        precondition(!settings.isRewriteEnabled)
        precondition(VoiceSettings.rewriteModels.map(\.id) == ["claude-haiku-4-5", "claude-sonnet-5", "claude-opus-5"])
        settings.rewriteMinimumLength = -1
        precondition(settings.effectiveRewriteMinimumLength == 120)
        settings.rewriteMinimumLength = 240
        settings.rewriteModel = "custom-rewrite-test"
        settings.isRewriteEnabled = true
        let rewrite = try JSONDecoder().decode(VoiceSettings.self, from: JSONEncoder().encode(settings))
        precondition(rewrite.effectiveRewriteMinimumLength == 240 && rewrite.rewriteModel == "custom-rewrite-test")
        precondition(rewrite.isRewriteEnabled)
        precondition(VoiceSettings.gatewayVoices.map(\.id) == ["longanlufeng", "longanlingxin", "longanlingxi", "longanhuan_v3.6"])
        for obsolete in ["Cherry", "Serena", "Ethan", "Chelsie", "longxiaochun", "longxiaochun_v2",
                         "longwan", "longcheng", "longhua", "longxiaoxia"] {
            settings.gatewayVoiceName = obsolete
            precondition(settings.gatewayVoiceName == "longanlufeng")
        }
        settings.gatewayVoiceName = "custom-test"
        settings.gatewayBaseURL = "https://example.invalid"
        let safe = settings
        for address in ["https://user:synthetic-secret@example.invalid", "https://example.invalid?token=synthetic-secret",
                        "https://example.invalid#synthetic-secret", "https://", "http://example.invalid"] {
            settings.gatewayBaseURL = address
            settings.rate = 1.5
            let snapshot = settings.persistenceSnapshot(previous: safe)
            precondition(snapshot.gatewayBaseURL == safe.gatewayBaseURL && snapshot.rate == 1.5)
            let encoded = try JSONEncoder().encode(snapshot)
            precondition(!String(decoding: encoded, as: UTF8.self).contains("synthetic-secret"))
        }
        let noPrevious = settings.persistenceSnapshot(previous: nil)
        precondition(noPrevious.gatewayBaseURL == nil)
        let unsafePrevious = settings.persistenceSnapshot(previous: settings)
        precondition(unsafePrevious.gatewayBaseURL == nil)
        settings.gatewayBaseURL = ""
        precondition(settings.persistenceSnapshot(previous: safe).gatewayBaseURL == "")
        settings.gatewayBaseURL = safe.gatewayBaseURL
        settings.rewriteBaseURL = "https://example.invalid?token=synthetic-rewrite-secret"
        let rewriteSafeSnapshot = settings.persistenceSnapshot(previous: safe)
        precondition(rewriteSafeSnapshot.rewriteBaseURL == nil && rewriteSafeSnapshot.gatewayBaseURL == safe.gatewayBaseURL)
        let rewriteSafeData = try JSONEncoder().encode(rewriteSafeSnapshot)
        precondition(!String(decoding: rewriteSafeData, as: UTF8.self).contains("synthetic-rewrite-secret"))
        settings.rewriteBaseURL = "https://rewrite.invalid"
        settings.usesSeparateRewriteGateway = true
        settings.rewriteStrength = "natural"
        let separate = try JSONDecoder().decode(VoiceSettings.self, from: JSONEncoder().encode(settings))
        precondition(separate.usesSeparateRewriteGateway && separate.rewriteStrength == "natural" && separate.rewriteBaseURL == "https://rewrite.invalid")
        settings.gatewayModel = "synthetic-model"
        let custom = try JSONDecoder().decode(VoiceSettings.self, from: JSONEncoder().encode(settings))
        precondition(custom.gatewayVoiceName == "custom-test")
        precondition(custom.gatewayBaseURL == "https://example.invalid" && custom.gatewayModel == "synthetic-model")
        let settingsData = try JSONEncoder().encode(settings)
        let object = try JSONSerialization.jsonObject(with: settingsData) as! [String: Any]
        precondition(!object.keys.contains(where: { $0.lowercased().contains("token") }))
        settings.isEnabled = false
        let disabled = try JSONDecoder().decode(VoiceSettings.self, from: JSONEncoder().encode(settings))
        precondition(!disabled.isEnabled)
        settings.isEnabled = true
        settings.isOverlayShown = false
        settings.voiceIdentifier = chineseVoices.first?.identifier
        let enabled = try JSONDecoder().decode(VoiceSettings.self, from: JSONEncoder().encode(settings))
        precondition(enabled.isEnabled && !enabled.isOverlayShown)
        precondition(enabled.voiceIdentifier == chineseVoices.first?.identifier)
        print("朗读开关、叠加控件和系统音色旧设置兼容及往返检查通过")
    }
}
