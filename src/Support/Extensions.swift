import Foundation

extension UInt64 {
    var gibibytes: UInt64 { self &* 1024 &* 1024 &* 1024 }
}

extension String {
    var expandingTildeInPath: String { (self as NSString).expandingTildeInPath }
}

extension FileManager {
    func tmpDir(prefix: String = "hylyx") -> URL {
        temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)")
    }
}

enum MACAddress {
    /// Generate a deterministic MAC from VM name (same name = same MAC = stable DHCP IP)
    static func fromName(_ name: String) -> String {
        var hash: UInt64 = 5381
        for byte in name.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)  // djb2
        }
        return String(format: "52:54:00:%02x:%02x:%02x",
                      UInt8(truncatingIfNeeded: hash),
                      UInt8(truncatingIfNeeded: hash >> 8),
                      UInt8(truncatingIfNeeded: hash >> 16))
    }
}

@discardableResult
func shell(_ cmd: String, _ args: [String]) throws -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: cmd)
    p.arguments = args
    try p.run(); p.waitUntilExit()
    guard p.terminationStatus == 0 else {
        throw HyError.executionFailed(command: cmd, exitCode: p.terminationStatus)
    }
    return p.terminationStatus
}
