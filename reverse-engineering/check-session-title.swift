import Foundation

/// 独立运行原包名称边界回归，不读取或修改真实会话。
@main
enum SessionTitleCheck {
    static func main() throws {
        let trimmed = try ClaudeSessionScanner.validatedTitle(" \n中文会话\t ")
        precondition(trimmed == "中文会话")
        let boundary = String(repeating: "👨‍👩‍👧‍👦", count: 120)
        let accepted = try ClaudeSessionScanner.validatedTitle(boundary)
        precondition(accepted == boundary)
        for invalid in [" \n\t", boundary + "字"] {
            do {
                _ = try ClaudeSessionScanner.validatedTitle(invalid)
                preconditionFailure("非法名称未被拒绝")
            } catch is ClaudeSessionScanner.TitleError { }
        }
        print("名称校验通过：去空白、空名称、120／121 个组合字符边界；无会话写入")
    }
}
