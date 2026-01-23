import Foundation

/// ANSI terminal styling
enum Style {
    // Core
    static let reset   = "\u{001B}[0m"
    static let bold    = "\u{001B}[1m"
    
    // Colors
    static let red     = "\u{001B}[31m"
    static let green   = "\u{001B}[32m"
    static let yellow  = "\u{001B}[33m"
    static let magenta = "\u{001B}[35m"
    static let cyan    = "\u{001B}[36m"
    static let muted   = "\u{001B}[90m"  // bright black
    
    // Semantic
    static var accent: String { cyan }
    static var success: String { green }
    static var error: String { red }
    
    // Symbols
    static let dot     = "●"
    static let check   = "✓"
    static let cross   = "✗"
    static let chevron = "›"
}
