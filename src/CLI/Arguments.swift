import Foundation

struct Arguments {
    let cmd: Command
    let vmNames: [String]
    let base: String?
    let filePath: String?
    let cpu: Int?
    let memGiB: UInt64?
    let bridge: String?
    let shared: String?
    let console: Bool  // -c for foreground mode
    let sizeGiB: UInt64?

    var vmName: String? { vmNames.first }

    static func parse() -> Arguments {
        var args = Array(CommandLine.arguments.dropFirst())

        guard let first = args.first else {
            return Arguments(cmd: .unknown, vmNames: [], base: nil, filePath: nil,
                           cpu: nil, memGiB: nil, bridge: nil, shared: nil,
                           console: false, sizeGiB: nil)
        }

        // Support -h and h as aliases for help
        let cmd: Command
        if first == "-h" || first == "h" {
            cmd = .help
        } else {
            cmd = Command(rawValue: first) ?? .unknown
        }
        args.removeFirst()

        var base: String? = nil
        if cmd == .images, let next = args.first, !next.hasPrefix("-") {
            base = next
            args.removeFirst()
        }

        var vmNames: [String] = []
        var file: String?
        var cpu: Int?
        var mem: UInt64?
        var bridge: String?
        var shared: String?
        var console = false
        var size: UInt64?

        var i = 0
        while i < args.count {
            let a = args[i]
            switch a {
            case "-t":
                i += 1; if i < args.count { file = args[i] }
            case "-c":
                console = true
            case "-p":
                i += 1; if i < args.count { cpu = Int(args[i]) }
            case "-m":
                i += 1; if i < args.count {
                    let s = args[i].replacingOccurrences(of: "[gG]", with: "", options: .regularExpression)
                    mem = UInt64(s)
                }
            case "-b":
                i += 1; if i < args.count { bridge = args[i] }
            case "-d":
                i += 1; if i < args.count { shared = args[i] }
            case "-s":
                i += 1; if i < args.count { size = parseSize(args[i]) }
            default:
                if cmd == .resize {
                    if vmNames.isEmpty {
                        vmNames.append(a)
                    } else if size == nil, let sz = parseSize(a) {
                        size = sz
                    }
                } else if cmd == .del || cmd == .stop || cmd == .restart {
                    vmNames.append(a)
                } else if vmNames.isEmpty {
                    vmNames.append(a)
                } else if base == nil {
                    base = a
                }
            }
            i += 1
        }

        return Arguments(cmd: cmd, vmNames: vmNames, base: base, filePath: file,
                        cpu: cpu, memGiB: mem, bridge: bridge, shared: shared,
                        console: console, sizeGiB: size)
    }

    private static func parseSize(_ s: String) -> UInt64? {
        let clean = s.trimmingCharacters(in: .whitespaces).lowercased()
        let digits = clean.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        guard let val = UInt64(digits), val > 0 else { return nil }
        if clean.hasSuffix("m") || clean.hasSuffix("mb") {
            return max(1, (val + 1023) / 1024)  // Round up, min 1 GiB
        }
        return val
    }
}
