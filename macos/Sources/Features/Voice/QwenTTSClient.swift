import Foundation

/// 调用者必须先取得目的地址、文字及凭据的发送许可；不读取账户或保存录音。
final class QwenTTSClient {
    private let configuration: URLSessionConfiguration

    init(configuration: URLSessionConfiguration = .ephemeral) {
        self.configuration = configuration.copy() as! URLSessionConfiguration
        self.configuration.urlCache = nil
        self.configuration.httpCookieStorage = nil
        self.configuration.httpShouldSetCookies = false
        self.configuration.urlCredentialStorage = nil
        self.configuration.httpAdditionalHeaders = nil
    }

    func synthesize(endpoint: URL, text: String, voice: String, model: String = QwenTTSRequest.defaultModel,
                    token: String, permittedAudioHosts: Set<String> = []) async throws -> (data: Data, duration: TimeInterval) {
        try Task.checkCancellation()
        let request = try QwenTTSRequest.make(endpoint: endpoint, text: text, voice: voice, model: model, token: token)
        let session = URLSession(configuration: configuration, delegate: RedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let response = try await receive(request, session: session)
        let data: Data
        switch try QwenTTSResponse.decode(response.data, statusCode: response.status) {
        case .bytes(_, let bytes): data = bytes
        case .url(_, let url):
            let hosts = Set(permittedAudioHosts.map { $0.lowercased() }).union([endpoint.host!.lowercased()])
            guard let host = url.host?.lowercased(), hosts.contains(host) else { throw URLError(.noPermissionsToReadFile) }
            // 音频下载独立构造 GET，不携带网关 Authorization 或 Cookie。
            let download = URLRequest(url: url, timeoutInterval: request.timeoutInterval)
            let audio = try await receive(download, session: session)
            guard audio.status == 200 else { throw QwenTTSResponse.ResponseError.httpStatus(audio.status) }
            data = audio.data
        }
        try Task.checkCancellation()
        return (data, try SpeechPlayer.validatedDuration(of: data))
    }

    func fetch(_ request: URLRequest, maximumBytes: Int) async throws -> (data: Data, status: Int) {
        try Task.checkCancellation()
        let session = URLSession(configuration: configuration, delegate: RedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await receive(request, session: session, maximumBytes: maximumBytes)
    }

    private func receive(_ request: URLRequest, session: URLSession, maximumBytes: Int = 64 * 1024 * 1024) async throws -> (data: Data, status: Int) {
        guard maximumBytes > 0, maximumBytes <= 64 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        let limit = maximumBytes
        guard response.expectedContentLength <= Int64(limit) else { throw CocoaError(.fileReadTooLarge) }
        var data = Data()
        if response.expectedContentLength > 0 { data.reserveCapacity(Int(response.expectedContentLength)) }
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else { throw CocoaError(.fileReadTooLarge) }
            data.append(byte)
        }
        try Task.checkCancellation()
        return (data, http.statusCode)
    }

    // 未确认额外目的地址时禁止自动重定向，包括同主机其他路由。
    private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
