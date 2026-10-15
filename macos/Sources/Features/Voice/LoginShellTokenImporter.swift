import Darwin
import Foundation

enum LoginShellTokenImporter {
    private static let marker = Data("\n__GHOSTTY_ANTHROPIC_AUTH_TOKEN__".utf8)

    static func read() throws -> String? {
        guard let password = getpwuid(getuid()), let rawShell = password.pointee.pw_shell else {
            throw CocoaError(.fileNoSuchFile)
        }
        let shell = String(cString: rawShell)
        guard shell.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: shell) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostty-login-shell-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: output.path, contents: nil,
                                       attributes: [.posixPermissions: 0o600])
        defer { try? FileManager.default.removeItem(at: output) }
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "printf '\\n__GHOSTTY_ANTHROPIC_AUTH_TOKEN__%s\\n' \"$ANTHROPIC_AUTH_TOKEN\""]
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        guard finished.wait(timeout: .now() + 10) == .success else {
            process.terminate()
            throw URLError(.timedOut)
        }
        guard process.terminationStatus == 0 else { throw CocoaError(.executableRuntimeMismatch) }
        let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        return try extractToken(from: Data(contentsOf: output))
    }

    static func extractToken(from output: Data) throws -> String? {
        guard let range = output.range(of: marker, options: .backwards) else { return nil }
        var token = output[range.upperBound...]
        while token.last == 10 || token.last == 13 { token.removeLast() }
        guard !token.isEmpty else { return nil }
        guard token.count <= 16 * 1024, !token.contains(where: { $0 < 32 || $0 == 127 }),
              let value = String(data: token, encoding: .utf8) else {
            throw URLError(.userAuthenticationRequired)
        }
        return value
    }
}
