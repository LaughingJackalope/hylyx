import Foundation

struct VMConfig: Codable {
    static let currentVersion = 1

    var version: Int
    var cpu: Int
    var memGiB: UInt64
    var bridge: String
    var shared: String
    var mac: String
    var image: String

    init(cpu: Int = Defaults.cpu, memGiB: UInt64 = Defaults.memGB,
         bridge: String = "", shared: String = "", mac: String = "", image: String = "") {
        self.version = Self.currentVersion
        self.cpu = cpu
        self.memGiB = memGiB
        self.bridge = bridge
        self.shared = shared
        self.mac = mac
        self.image = image
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let v = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        guard v <= Self.currentVersion else {
            throw HyError.incompatibleConfigVersion(found: v, supported: Self.currentVersion)
        }
        version = Self.currentVersion
        cpu = try c.decodeIfPresent(Int.self, forKey: .cpu) ?? Defaults.cpu
        memGiB = try c.decodeIfPresent(UInt64.self, forKey: .memGiB) ?? Defaults.memGB
        bridge = try c.decodeIfPresent(String.self, forKey: .bridge) ?? ""
        shared = try c.decodeIfPresent(String.self, forKey: .shared) ?? ""
        mac = try c.decodeIfPresent(String.self, forKey: .mac) ?? ""
        image = try c.decodeIfPresent(String.self, forKey: .image) ?? ""
    }
}
