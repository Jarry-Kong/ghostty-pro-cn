import Foundation

@main
enum CheckSpeechFallback {
    static func main() {
        precondition(SpeechFallbackPolicy.reason(for: CancellationError()) == nil)
        precondition(SpeechFallbackPolicy.reason(for: URLError(.cancelled)) == nil)
        precondition(SpeechFallbackPolicy.reason(for: QwenTTSResponse.ResponseError.unauthorized)?.permission == true)
        precondition(SpeechFallbackPolicy.reason(for: QwenTTSResponse.ResponseError.routeNotAllowed("test"))?.permission == true)
        precondition(SpeechFallbackPolicy.reason(for: QwenTTSResponse.ResponseError.httpStatus(500))?.permission == false)
        precondition(SpeechFallbackPolicy.reason(for: URLError(.timedOut))?.permission == false)
        precondition(SpeechFallbackPolicy.reason(for: URLError(.noPermissionsToReadFile))?.permission == true)
        precondition(SpeechFallbackPolicy.reason(for: CocoaError(.fileReadCorruptFile))?.message == "网关未返回可用音频")
        print("回退分类检查通过：取消禁止回退、权限／后端分组、音频损坏；未朗读或写入偏好")
    }
}
