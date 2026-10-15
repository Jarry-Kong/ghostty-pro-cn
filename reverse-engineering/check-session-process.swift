import Darwin
import Foundation

@main
enum SessionProcessCheck {
    static func main() throws {
        if CommandLine.arguments.contains("--worker") {
            for _ in 0..<300 { usleep(100_000) }
            return
        }

        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("ghostty-session-process-" + UUID().uuidString)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }
        let id = UUID().uuidString.lowercased()

        let identified = try start(arguments: ["--resume", id, "--worker"], directory: directory)
        defer { identified.terminate(); identified.waitUntilExit() }
        guard wait(until: {
            let snapshot = ClaudeSessionProcesses.snapshot()
            return snapshot.sessions[id] == identified.processIdentifier &&
                snapshot.ownedSessions.contains(id) && snapshot.isActive(directory: directory.path)
        }) else { preconditionFailure("未识别带编号的独立 Claude 进程") }

        identified.terminate()
        identified.waitUntilExit()
        guard wait(until: { ClaudeSessionProcesses.snapshot().sessions[id] == nil }) else {
            preconditionFailure("退出进程仍被识别为运行中")
        }

        let unidentified = try start(arguments: ["--worker"], directory: directory)
        defer { if unidentified.isRunning { unidentified.terminate(); unidentified.waitUntilExit() } }
        guard wait(until: { ClaudeSessionProcesses.snapshot().isUncertain(directory: directory.path) }) else {
            preconditionFailure("无编号 Claude 进程未进入安全的不确定状态")
        }
        unidentified.terminate()
        unidentified.waitUntilExit()
        guard wait(until: { !ClaudeSessionProcesses.snapshot().isUncertain(directory: directory.path) }) else {
            preconditionFailure("无编号进程退出后仍保留不确定状态")
        }

        print("会话进程检查通过：随机编号、精确 PID、目录活跃、无编号安全阻止及退出清除；仅临时进程")
    }

    private static func start(arguments: [String], directory: URL) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = arguments
        process.currentDirectoryURL = directory
        try process.run()
        return process
    }

    private static func wait(until condition: () -> Bool) -> Bool {
        for _ in 0..<40 {
            if condition() { return true }
            usleep(50_000)
        }
        return false
    }
}
