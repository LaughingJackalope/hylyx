import Foundation
import Darwin

final class PIDLock {
    private let path: URL
    private var fd: Int32 = -1

    init(path: URL) { self.path = path }
    deinit { releaseIfNeeded() }

    func acquire() throws {
        fd = open(path.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { throw HyError.lockAcquisitionFailed(path: path.path) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd); fd = -1
            throw HyError.vmRunning(path.deletingLastPathComponent().lastPathComponent)
        }
        ftruncate(fd, 0)
        "\(getpid())\n".withCString { _ = write(fd, $0, strlen($0)) }
    }

    func release() { releaseIfNeeded() }

    private func releaseIfNeeded() {
        guard fd >= 0 else { return }
        flock(fd, LOCK_UN); close(fd); fd = -1
        try? FileManager.default.removeItem(at: path)
    }

    static func isLocked(at path: URL) -> (isLocked: Bool, pid: pid_t?) {
        let fd = open(path.path, O_RDONLY)
        guard fd >= 0 else { return (false, nil) }
        defer { close(fd) }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 { flock(fd, LOCK_UN); return (false, nil) }
        var buf = [CChar](repeating: 0, count: 32)
        guard read(fd, &buf, 31) > 0 else { return (true, nil) }
        return (true, pid_t(String(cString: buf).trimmingCharacters(in: .whitespacesAndNewlines)))
    }
}
