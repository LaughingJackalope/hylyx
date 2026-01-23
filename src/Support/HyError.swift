import Foundation

enum HyError: Error, LocalizedError {
    case notFound(String)
    case alreadyExists(String)
    case vmRunning(String)
    case vmNotRunning(String)
    case vmStopTimeout(String)
    case invalidName(String)
    case insufficientDiskSpace(required: UInt64, available: UInt64)
    case extractionFailed(String)
    case executionFailed(command: String, exitCode: Int32)
    case lockAcquisitionFailed(path: String)
    case incompatibleConfigVersion(found: Int, supported: Int)
    case unsupportedOS(required: String)
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let item):           "Not found: \(item)"
        case .alreadyExists(let item):      "Already exists: \(item)"
        case .vmRunning(let name):          "VM '\(name)' is running"
        case .vmNotRunning(let name):       "VM '\(name)' is not running"
        case .vmStopTimeout(let name):      "VM '\(name)' did not stop in time"
        case .invalidName(let reason):      "Invalid name: \(reason)"
        case .insufficientDiskSpace(let r, let a): "Insufficient disk space: need \(r) GiB, have \(a) GiB"
        case .extractionFailed(let reason): "Extraction failed: \(reason)"
        case .executionFailed(let cmd, let code): "\(cmd) failed (exit \(code))"
        case .lockAcquisitionFailed(let p): "Could not acquire lock: \(p)"
        case .incompatibleConfigVersion(let f, let s): "Config version \(f) unsupported (max \(s))"
        case .unsupportedOS(let req):       "Requires \(req)"
        case .custom(let msg):              msg
        }
    }
}
