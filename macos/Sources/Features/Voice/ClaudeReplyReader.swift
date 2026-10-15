import Foundation

struct ClaudeAssistantReply: Equatable, Sendable {
    let sessionID: String
    let text: String
    let timestamp: Date?
}

/// 只读取指定会话；不会用其他会话的“最近回复”替代当前会话。
enum ClaudeReplyReader {
    static func latestReply(in file: URL, sessionID: String) throws -> ClaudeAssistantReply? {
        try Task.checkCancellation()
        guard UUID(uuidString: sessionID) != nil,
              file.deletingPathExtension().lastPathComponent.lowercased() == sessionID.lowercased(),
              file.pathExtension == "jsonl" else { throw CocoaError(.fileReadInvalidFileName) }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var pending = Data()
        var latest: ClaudeAssistantReply?
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        func consume(_ line: Data) {
            guard let value = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  value["type"] as? String == "assistant",
                  value["isSidechain"] as? Bool != true,
                  value["isApiErrorMessage"] as? Bool != true,
                  let id = value["sessionId"] as? String,
                  id.lowercased() == sessionID.lowercased(),
                  let message = value["message"] as? [String: Any] else { return }
            let text: String
            if let content = message["content"] as? String { text = content }
            else if let blocks = message["content"] as? [[String: Any]] {
                text = blocks.filter { $0["type"] as? String == "text" }
                    .compactMap { $0["text"] as? String }.joined(separator: "\n")
            } else { return }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let date = (value["timestamp"] as? String).flatMap { fractional.date(from: $0) ?? plain.date(from: $0) }
            latest = ClaudeAssistantReply(sessionID: id, text: text, timestamp: date)
        }
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 10) {
                try Task.checkCancellation()
                consume(Data(pending[..<newline]))
                pending.removeSubrange(...newline)
            }
            guard pending.count <= 32 * 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
        }
        if !pending.isEmpty { consume(pending) }
        return latest
    }
}
