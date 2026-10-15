import Foundation

/// 音频载荷提取，不下载地址或将解码字节直接当作有效音频。
enum QwenTTSResponse {
    enum ResponseError: LocalizedError {
        case httpStatus(Int)
        case unauthorized
        case routeNotAllowed(String)
        var errorDescription: String? {
            switch self {
            case .httpStatus(let status): return "语音服务返回 HTTP \(status)，未尝试播放响应内容。"
            case .unauthorized: return "语音服务鉴权失败，请检查访问令牌。"
            case .routeNotAllowed(let route): return "语音网关不允许访问路由 \(route)，请检查网关权限。"
            }
        }
    }

    static func decode(_ data: Data, statusCode: Int) throws -> Payload {
        if statusCode == 401 { throw ResponseError.unauthorized }
        if statusCode == 403 { throw ResponseError.routeNotAllowed("/bailian/audio/tts") }
        guard statusCode == 200 else { throw ResponseError.httpStatus(statusCode) }
        return try decode(data)
    }

    enum Payload {
        case url(path: String, URL)
        case bytes(path: String, Data)
    }

    static func decode(_ data: Data) throws -> Payload {
        guard data.count <= 64 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        let object = try JSONSerialization.jsonObject(with: data)
        if let preferred = preferredAudioURL(in: object) { return .url(path: preferred.path, preferred.url) }
        var budget = 100_000
        if let found = try firstString(in: object, budget: &budget, matching: { path, value in
            let lower = value.lowercased()
            return value.hasPrefix("http") &&
                ([".mp3", ".wav", ".m4a", ".pcm"].contains(where: { lower.contains($0) }) || path.lowercased().contains("audio")) &&
                secureURL(value) != nil
        }), let url = secureURL(found.value) {
            return .url(path: found.path, url)
        }
        budget = 100_000
        guard let found = try firstString(in: object, budget: &budget, matching: { isBase64Candidate($1, atPath: $0) }),
              let bytes = Data(base64Encoded: found.value), !bytes.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        return .bytes(path: found.path, bytes)
    }

    private static func firstString(in object: Any, prefix: String = "", depth: Int = 0,
                                    budget: inout Int, matching: (String, String) -> Bool) throws -> (path: String, value: String)? {
        guard depth <= 64, budget > 0 else { throw CocoaError(.fileReadTooLarge) }
        budget -= 1
        if let string = object as? String, matching(prefix, string) { return (prefix, string) }
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                let path = prefix.isEmpty ? key : prefix + "." + key
                if let found = try firstString(in: value, prefix: path, depth: depth + 1, budget: &budget, matching: matching) { return found }
            }
        } else if let array = object as? [Any] {
            for (index, value) in array.enumerated() {
                if let found = try firstString(in: value, prefix: "\(prefix)[\(index)]", depth: depth + 1,
                                                budget: &budget, matching: matching) { return found }
            }
        }
        return nil
    }

    private static func secureURL(_ string: String) -> URL? {
        guard var components = URLComponents(string: string),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              components.host?.isEmpty == false,
              components.user == nil, components.password == nil, components.fragment == nil else { return nil }
        components.scheme = "https"
        return components.url
    }
    /// 原包仅用前 64 字符筛选候选；实际解码仍须单独验证完整内容。
    static func isBase64Candidate(_ text: String, atPath path: String) -> Bool {
        guard text.count > 512 else { return false }
        let path = path.lowercased()
        guard ["audio", "data", "content"].contains(where: { path.contains($0) }) else { return false }
        return text.prefix(64).allSatisfy { $0.isLetter || $0.isNumber || "+/=".contains($0) }
    }

    static let preferredURLPaths = [
        ["output", "audio", "url"], ["output", "audio_url"], ["output", "url"],
        ["data", "audio", "url"], ["data", "url"], ["audio", "url"],
        ["url"], ["result", "audio_url"]
    ]

    static func preferredAudioURL(in object: Any) -> (path: String, url: URL)? {
        for path in preferredURLPaths {
            var value: Any? = object
            for key in path { value = (value as? [String: Any])?[key] }
            guard let string = value as? String, let url = secureURL(string) else { continue }
            return (path.joined(separator: "."), url)
        }
        return nil
    }
}
