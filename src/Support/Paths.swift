import Foundation

enum Paths {
    static let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".hylyx")
    static var kernel: URL { root.appendingPathComponent(".linux") }
    
    static func ensureRoot() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    struct VM {
        let name: String
        var dir: URL  { Paths.root.appendingPathComponent(name) }
        var disk: URL { dir.appendingPathComponent("\(name).img") }
        var cfg: URL  { dir.appendingPathComponent("\(name).json") }
        var pid: URL  { dir.appendingPathComponent("\(name).pid") }
        var log: URL  { dir.appendingPathComponent("\(name).log") }
    }

    static func vm(_ name: String) -> VM { VM(name: name) }
}

enum Toolchain {
    private static let lib: String = {
        let fm = FileManager.default
        var exe = ProcessInfo.processInfo.arguments[0]
        
        // Make path absolute
        if !exe.hasPrefix("/") {
            exe = fm.currentDirectoryPath + "/" + exe
        }
        
        // Resolve symlink if any
        if let resolved = try? fm.destinationOfSymbolicLink(atPath: exe) {
            exe = resolved.hasPrefix("/") ? resolved : URL(fileURLWithPath: exe).deletingLastPathComponent().appendingPathComponent(resolved).path
        }
        
        let exeURL = URL(fileURLWithPath: exe).standardized
        let exeDir = exeURL.deletingLastPathComponent()
        
        // App bundle: /path/Hylyx.app/Contents/MacOS/hylyx → ../lib
        let bundleLib = exeDir.deletingLastPathComponent().appendingPathComponent("lib").path
        if fm.fileExists(atPath: bundleLib) { return bundleLib }
        
        // Development: /path/build/hylyx → bin
        let devBin = exeDir.appendingPathComponent("bin").path
        if fm.fileExists(atPath: devBin) { return devBin }
        
        return "/usr/local/lib/hylyx"
    }()
    
    private static func tool(_ name: String) -> String {
        let fm = FileManager.default
        // Dev binaries have -hy suffix
        let hyPath = "\(lib)/\(name)-hy"
        if fm.fileExists(atPath: hyPath) { return hyPath }
        return "\(lib)/\(name)"
    }
    
    static var mkfs: String    { tool("mkfs") }
    static var resize: String  { tool("resize") }
    static var fsck: String    { tool("fsck") }
    static var debugfs: String { tool("debugfs") }
}
