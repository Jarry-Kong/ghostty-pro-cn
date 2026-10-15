import Foundation

@main
enum CheckVoiceOverlayProcess {
    static func main() {
        if CommandLine.arguments.count == 2 {
            print(ClaudeSessionProcesses.snapshot().isActive(directory: CommandLine.arguments[1]) ? "active" : "inactive")
            return
        }
        var snapshot = ClaudeSessionProcesses.Snapshot()
        let canonical = URL(fileURLWithPath: "/tmp").resolvingSymlinksInPath().standardizedFileURL.path
        snapshot.activeDirectories.insert(canonical)
        precondition(snapshot.isActive(directory: "/tmp/../tmp"))
        precondition(!snapshot.isActive(directory: "/var"))
        print("语音叠加进程目录检查通过：规范化目录精确匹配，不按父目录或字符串包含误判")
    }
}
