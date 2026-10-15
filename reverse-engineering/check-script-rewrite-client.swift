import Foundation

private final class RewriteResponse: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        precondition(request.httpMethod == "POST" && request.timeoutInterval == 20)
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-rewrite")
        precondition(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let failed = request.url!.host == "failure.invalid"
        let body = Data(#"{"content":[{"type":"thinking","text":"不可朗读"},{"type":"text","text":" 离线口播稿 123 "}]}"#.utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: failed ? 500 : 200,
                                                            httpVersion: "HTTP/1.1", headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

@main
enum CheckScriptRewriteClient {
    static func main() async throws {
        precondition(!ScriptRewriter.isWorthRewriting(String(repeating: "字", count: 119)))
        precondition(ScriptRewriter.isWorthRewriting(String(repeating: "字", count: 120)))
        precondition(ScriptRewriter.isWorthRewriting(String(repeating: "字", count: 8000)))
        precondition(!ScriptRewriter.isWorthRewriting(String(repeating: "字", count: 8001)))
        precondition(ScriptRewriter.isWorthRewriting(String(repeating: "👨‍👩‍👧‍👦", count: 120), minimumLength: -1))
        precondition(!ScriptRewriter.isWorthRewriting(String(repeating: "字", count: 120), minimumLength: 121))
        precondition(!ScriptRewriter.shouldRewrite(String(repeating: "字", count: 120), enabled: false, minimumLength: 120))
        precondition(ScriptRewriter.shouldRewrite("短试听", enabled: false, minimumLength: 120, comparison: true))
        precondition(!ScriptRewriter.shouldRewrite(String(repeating: "字", count: 120), enabled: true, minimumLength: 120, comparison: false))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RewriteResponse.self]
        let result = try await ScriptRewriter.rewrite(baseURL: "https://example.invalid/v1", token: "synthetic-rewrite",
                                                      model: "test-model", text: "离线原文 123", strength: .conservative, configuration: configuration)
        precondition(result == "离线口播稿 123")
        let failed = try await ScriptRewriter.rewrite(baseURL: "https://failure.invalid", token: "synthetic-rewrite",
                                                      model: "test-model", text: "离线原文 123", strength: .natural, configuration: configuration)
        precondition(failed == nil)
        let cancelled = Task {
            while !Task.isCancelled { await Task.yield() }
            return try await ScriptRewriter.rewrite(baseURL: "https://example.invalid", token: "synthetic-rewrite",
                                                    model: "test-model", text: "离线原文 123", strength: .natural, configuration: configuration)
        }
        cancelled.cancel()
        do { _ = try await cancelled.value; preconditionFailure("取消后不得发送") }
        catch is CancellationError { }
        print("改写客户端离线检查通过：请求头、文本提取、错误返回 nil、取消保护；响应由 URLProtocol 提供，未联网")
    }
}
