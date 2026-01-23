import Foundation
import Darwin

// MARK: - Terminal Launch

private func escapeForAppleScript(_ s: String) -> String {
    let appleEscaped = s
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\t", with: "\\t")
    return appleEscaped.replacingOccurrences(of: "'", with: "'\\''")
}

func launchInTerminalIfNeeded() {
    guard CommandLine.arguments.count == 1, isatty(STDOUT_FILENO) == 0 else { return }

    let exe = Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
    let escaped = escapeForAppleScript(exe)

    let script = """
        tell application "Terminal"
            activate
            do script "clear && '\(escaped)' help"
        end tell
        """

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    proc.arguments = ["-e", script]
    try? proc.run()
    exit(0)
}

// MARK: - Entry Point

launchInTerminalIfNeeded()
CommandRunner.run()
