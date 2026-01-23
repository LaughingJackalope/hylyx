import Foundation

enum Defaults {
    static let cloudURL = URL(string: "https://origon.ai/hylyx")!
    static let kernelCmdline = "root=/dev/vda rw console=hvc0"
    static let cpu = ProcessInfo.processInfo.processorCount
    static let memGB: UInt64 = 2
    static let diskGB: UInt64 = 16
}
