import Foundation
import Darwin

/// 只检查本用户的 Claude 进程；只保留编号、PID 和目录，不记录参数或环境变量。
enum ClaudeSessionProcesses {
    struct Snapshot: Sendable {
        var sessions: [String: Int32] = [:]
        var ownedSessions: Set<String> = []
        var activeDirectories: Set<String> = []
        var unidentifiedDirectories: Set<String> = []
        var inspectionFailed = false
        func isActive(directory: String) -> Bool {
            activeDirectories.contains(Self.canonical(directory))
        }
        func isUncertain(directory: String) -> Bool {
            inspectionFailed || unidentifiedDirectories.contains(Self.canonical(directory))
        }
        private static func canonical(_ directory: String) -> String {
            URL(fileURLWithPath: directory).resolvingSymlinksInPath().standardizedFileURL.path
        }
    }

    static func sessionID(arguments: [String]) -> String? {
        for (index, argument) in arguments.enumerated() {
            if argument == "--" { break }
            if ["--resume", "-r", "--session-id"].contains(argument), index + 1 < arguments.count {
                let id = arguments[index + 1]
                if UUID(uuidString: id) != nil { return id.lowercased() }
            }
            for prefix in ["--resume=", "--session-id="] where argument.hasPrefix(prefix) {
                let id = String(argument.dropFirst(prefix.count))
                if UUID(uuidString: id) != nil { return id.lowercased() }
            }
        }
        return nil
    }

    static func snapshot() -> Snapshot {
        var result = Snapshot()
        let capacity = Int(proc_listallpids(nil, 0)) + 128
        guard capacity > 128 else { result.inspectionFailed = true; return result }
        var pids = [Int32](repeating: 0, count: capacity)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count >= 0 else { result.inspectionFailed = true; return result }
        for pid in pids.prefix(Int(count)) where pid > 0 {
            var info = proc_bsdinfo()
            let infoSize = MemoryLayout<proc_bsdinfo>.size
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(infoSize)) == infoSize else {
                // 部分系统进程禁止读取 BSD 信息，不能因此禁用所有用户会话。
                // 只有还能明确识别为候选客户端时，才保留安全的不确定状态。
                var candidatePath = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
                if proc_pidpath(pid, &candidatePath, UInt32(candidatePath.count)) > 0 {
                    let executable = candidatePath.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                    if (isNativeClaude(executable) || URL(fileURLWithPath: executable).lastPathComponent == "node"),
                       kill(pid, 0) == 0 { result.inspectionFailed = true }
                }
                continue
            }
            guard info.pbi_uid == getuid() else { continue }
            guard info.pbi_status != SZOMB && info.pbi_flags & UInt32(PROC_FLAG_INEXIT) == 0 else { continue }
            var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else {
                let name = withUnsafeBytes(of: &info.pbi_comm) {
                    String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
                }
                if ["claude", "claude.exe", "node"].contains(name), kill(pid, 0) == 0 {
                    result.inspectionFailed = true
                }
                continue
            }
            let executable = path.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            let basename = URL(fileURLWithPath: executable).lastPathComponent
            let nativeClaude = isNativeClaude(executable)
            guard nativeClaude || basename == "node" else { continue }
            guard let args = arguments(pid: pid) else {
                if kill(pid, 0) == 0 { result.inspectionFailed = true }
                continue
            }
            guard nativeClaude || args.contains(where: {
                $0.contains("/@anthropic-ai/claude-code/") && $0.hasSuffix(".js")
            }) else { continue }
            let cwd = workingDirectory(pid: pid)
            if let cwd { result.activeDirectories.insert(cwd) }
            if let id = sessionID(arguments: args) {
                let owned = isDescendant(pid: pid, ancestor: getpid())
                if owned || !result.ownedSessions.contains(id) { result.sessions[id] = pid }
                if owned { result.ownedSessions.insert(id) }
            } else {
                if let cwd { result.unidentifiedDirectories.insert(cwd) }
                else { result.inspectionFailed = true }
            }
        }
        return result
    }

    static func isNativeClaude(_ path: String) -> Bool {
        let basename = URL(fileURLWithPath: path).lastPathComponent
        return basename == "claude" || (basename == "claude.exe" && path.contains("/@anthropic-ai/claude-code/"))
    }

    private static func isDescendant(pid: Int32, ancestor: Int32) -> Bool {
        var current = pid
        var visited: Set<Int32> = []
        for _ in 0..<32 {
            if current == ancestor { return true }
            guard current > 1 && visited.insert(current).inserted else { return false }
            var info = proc_bsdinfo()
            let size = MemoryLayout<proc_bsdinfo>.size
            guard proc_pidinfo(current, PROC_PIDTBSDINFO, 0, &info, Int32(size)) == size else { return false }
            current = Int32(bitPattern: info.pbi_ppid)
        }
        return false
    }

    private static func arguments(pid: Int32) -> [String]? {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0,
              size > MemoryLayout<Int32>.size, size <= 4 * 1024 * 1024 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &bytes, &size, nil, 0) == 0 else { return nil }
        let argc = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc > 0 && argc < 65536 else { return nil }
        var cursor = MemoryLayout<Int32>.size
        // 跳过可执行路径及填充；只读取 argc 个参数，绝不解析后面的环境变量。
        while cursor < size && bytes[cursor] != 0 { cursor += 1 }
        while cursor < size && bytes[cursor] == 0 { cursor += 1 }
        var args: [String] = []
        for _ in 0..<Int(argc) {
            let start = cursor
            while cursor < size && bytes[cursor] != 0 { cursor += 1 }
            guard cursor < size else { return nil }
            args.append(String(decoding: bytes[start..<cursor], as: UTF8.self))
            cursor += 1
        }
        return args
    }

    private static func workingDirectory(pid: Int32) -> String? {
        var vnode = proc_vnodepathinfo()
        let size = MemoryLayout<proc_vnodepathinfo>.size
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnode, Int32(size)) == size else { return nil }
        let path = withUnsafeBytes(of: &vnode.pvi_cdir.vip_path) {
            String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
        }
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}
