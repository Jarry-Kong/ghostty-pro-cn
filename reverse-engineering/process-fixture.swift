import Foundation

/// 仅用于验证 PID／参数探测，编译到临时目录的 claude 文件，不使用真实客户端。
@main
struct ProcessFixture {
    static func main() { Thread.sleep(forTimeInterval: 30) }
}
