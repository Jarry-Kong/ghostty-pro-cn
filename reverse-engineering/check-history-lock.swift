import Foundation

@main
enum HistoryLockCheck {
    static func main() throws {
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "hold" {
            let store = VoiceHistoryStore(fileURL: URL(fileURLWithPath: CommandLine.arguments[2]))
            try store.withExclusiveAccess {
                FileHandle.standardOutput.write(Data("ready\n".utf8))
                Thread.sleep(forTimeInterval: 10)
            }
            return
        }
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("Ghostty-Lock-Test-" + UUID().uuidString)
            .resolvingSymlinksInPath()
        defer { try? manager.removeItem(at: directory) }
        let file = directory.appendingPathComponent("index.json")
        let store = VoiceHistoryStore(fileURL: file)
        let entry = VoiceHistoryEntry(text: "临时锁检查")
        try store.save([entry])
        let child = Process()
        let output = Pipe()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["hold", file.path]
        child.standardOutput = output
        try child.run()
        defer { if child.isRunning { child.terminate(); child.waitUntilExit() } }
        let ready = output.fileHandleForReading.readData(ofLength: 6)
        precondition(ready == Data("ready\n".utf8))
        do { try store.save([]); preconditionFailure("跨进程写锁未拒绝冲突") } catch { }
        let preserved = try store.load()
        precondition(preserved.count == 1 && preserved[0].id == entry.id)
        child.terminate()
        child.waitUntilExit()
        try store.save([])
        let unlocked = try store.load()
        precondition(unlocked.isEmpty)
        let outside = directory.appendingPathComponent("outside")
        try manager.createDirectory(at: outside, withIntermediateDirectories: false)
        let link = directory.appendingPathComponent("link")
        try manager.createSymbolicLink(at: link, withDestinationURL: outside)
        let unsafe = VoiceHistoryStore(fileURL: link.appendingPathComponent("new-child/index.json"))
        do { try unsafe.save([]); preconditionFailure("软链接父目录未拒绝") } catch { }
        precondition(!manager.fileExists(atPath: outside.appendingPathComponent("new-child/index.json").path))
        print("跨进程锁检查通过：真实子进程持锁、冲突拒绝且索引不变、子进程退出后释放；仅临时数据")
    }
}
