import Foundation

enum SpeechFallbackPolicy {
    static func reason(for error: Error) -> (message: String, permission: Bool)? {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return nil }
        if (error as? URLError)?.code == .noPermissionsToReadFile { return ("未授权音频下载地址", true) }
        switch error {
        case QwenTTSResponse.ResponseError.unauthorized:
            return ("网关不认这个密钥", true)
        case QwenTTSResponse.ResponseError.routeNotAllowed:
            return ("网关未开通语音接口权限", true)
        case QwenTTSResponse.ResponseError.httpStatus(let code):
            return ("网关返回 HTTP \(code)", false)
        case is CocoaError:
            return ("网关未返回可用音频", false)
        default:
            return ("连不上语音网关", false)
        }
    }
}
