import Darwin
import Foundation

/// Manages terminal raw mode state in a thread-safe manner
final class TerminalMode {
    static let shared = TerminalMode()
    
    private var savedTermios = termios()
    private var isRawMode = false
    private let lock = NSLock()
    
    private init() {}
    
    /// Enable raw terminal mode (disables echo, canonical mode, and signals)
    func enableRaw() {
        lock.lock()
        defer { lock.unlock() }
        
        guard !isRawMode else { return }
        guard tcgetattr(STDIN_FILENO, &savedTermios) == 0 else { return }
        
        var raw = savedTermios
        raw.c_lflag &= ~UInt(ECHO | ICANON | ISIG)
        tcsetattr(STDIN_FILENO, TCSANOW, &raw)
        isRawMode = true
        
        atexit { TerminalMode.shared.restore() }
    }
    
    /// Restore terminal to original mode
    func restore() {
        lock.lock()
        defer { lock.unlock() }
        
        guard isRawMode else { return }
        tcsetattr(STDIN_FILENO, TCSANOW, &savedTermios)
        isRawMode = false
    }
}

// MARK: - Convenience Functions (backward compatibility)

func enableRawTerminalMode() {
    TerminalMode.shared.enableRaw()
}

func restoreTerminalMode() {
    TerminalMode.shared.restore()
}
