import Foundation

enum Validation {
    private static let pattern = try! NSRegularExpression(pattern: "^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$")
    private static let reserved: Set<String> = ["linux"]  // kernel directory name

    static func vmName(_ name: String) throws {
        guard !name.isEmpty else { throw HyError.invalidName("cannot be empty") }
        guard !reserved.contains(name.lowercased()) else { throw HyError.invalidName("'\(name)' is reserved") }
        let range = NSRange(name.startIndex..., in: name)
        guard pattern.firstMatch(in: name, range: range) != nil else {
            throw HyError.invalidName("alphanumeric, hyphens, underscores only (max 64)")
        }
    }

    static func imageName(_ name: String) throws {
        guard !name.isEmpty else { throw HyError.invalidName("image name cannot be empty") }
        guard !name.contains("..") else { throw HyError.invalidName("image name cannot contain '..'") }
        guard !name.contains("/") else { throw HyError.invalidName("image name cannot contain '/'") }
    }
}
