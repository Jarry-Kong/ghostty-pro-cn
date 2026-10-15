import XCTest
@testable import Ghostty

final class LoginShellTokenImporterTests: XCTestCase {
    func testExtractsLastMarkedTokenAndRejectsUnsafeValues() throws {
        let output = Data("配置输出\n__GHOSTTY_ANTHROPIC_AUTH_TOKEN__旧值\n其他输出\n__GHOSTTY_ANTHROPIC_AUTH_TOKEN__虚构令牌-123\n".utf8)
        XCTAssertEqual(try LoginShellTokenImporter.extractToken(from: output), "虚构令牌-123")
        XCTAssertNil(try LoginShellTokenImporter.extractToken(from: Data("普通输出".utf8)))
        XCTAssertNil(try LoginShellTokenImporter.extractToken(from: Data("\n__GHOSTTY_ANTHROPIC_AUTH_TOKEN__\n".utf8)))
        XCTAssertThrowsError(try LoginShellTokenImporter.extractToken(
            from: Data("\n__GHOSTTY_ANTHROPIC_AUTH_TOKEN__含\u{0}控制符\n".utf8)))
    }
}
