import Foundation

enum Log {
    static func info(_ msg: String) {
        print("\(Style.accent)\(Style.dot)\(Style.reset) \(msg)")
    }
    
    static func success(_ msg: String) {
        print("\(Style.success)\(Style.check)\(Style.reset) \(msg)")
    }
    
    static func error(_ msg: String) {
        fputs("\(Style.error)\(Style.cross)\(Style.reset) \(msg)\n", stderr)
    }
    
    static func step(_ msg: String) {
        print("\(Style.muted)\(Style.chevron)\(Style.reset) \(msg)")
    }
}
