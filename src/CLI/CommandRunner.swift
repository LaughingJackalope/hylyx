import Foundation
import Virtualization

struct CommandRunner {
    static func run() {
        let args = Arguments.parse()

        do {
            switch args.cmd {
            case .install:
                guard let name = args.vmName else { throw HyError.notFound("VM name") }
                try Machine.create(
                    name: name,
                    image: args.base,
                    localTar: args.filePath,
                    cpu: args.cpu,
                    mem: args.memGiB,
                    bridge: args.bridge,
                    shared: args.shared,
                    sizeGiB: args.sizeGiB
                )
                
                // SSH key injection (auto-detect from ~/.ssh/)
                var sshInjected = false
                if let key = Machine.findDefaultSSHKey() {
                    let vm = Paths.vm(name)
                    if Machine.injectSSHKey(key.content, into: vm.disk) {
                        Log.success("SSH key injected")
                        sshInjected = true
                    } else {
                        Log.info("SSH key injection failed")
                    }
                }
                
                if sshInjected {
                    try Machine.start(name: name, console: false)
                } else {
                    Log.info("No SSH key in ~/.ssh/ - booting to console")
                    try Machine.start(name: name, console: true)
                }

            case .start:
                guard let name = args.vmName else { throw HyError.notFound("VM name") }
                try Validation.vmName(name)
                try Machine.start(name: name, console: args.console)

            case .stop:
                guard !args.vmNames.isEmpty else { throw HyError.notFound("VM name") }
                for name in args.vmNames {
                    try Validation.vmName(name)
                    try Machine.stop(name: name)
                }

            case .restart:
                guard !args.vmNames.isEmpty else { throw HyError.notFound("VM name") }
                for name in args.vmNames {
                    try Validation.vmName(name)
                    try Machine.restart(name: name)
                }

            case .clone:
                guard let src = args.vmName, let dst = args.base else {
                    throw HyError.notFound("source and destination")
                }
                try Validation.vmName(src)
                try Validation.vmName(dst)
                try Machine.clone(src: src, dst: dst)

            case .resize:
                guard let name = args.vmName, let sz = args.sizeGiB else {
                    throw HyError.notFound("VM name and size")
                }
                try Validation.vmName(name)
                try Machine.resize(name: name, toGiB: sz)

            case .del:
                guard !args.vmNames.isEmpty else { throw HyError.notFound("VM name") }
                for name in args.vmNames {
                    try Validation.vmName(name)
                }
                confirmRemove(vms: args.vmNames)

            case .info:
                guard let name = args.vmName else { throw HyError.notFound("VM name") }
                try Validation.vmName(name)
                showInfo(name: name)

            case .autostart:
                guard let name = args.vmName else { throw HyError.notFound("VM name") }
                try Validation.vmName(name)
                if args.base == "off" {
                    try Machine.disableAutostart(name: name)
                } else {
                    try Machine.enableAutostart(name: name)
                }

            case .images:
                listImages(filter: args.base)

            case .bridges:
                listBridges()

            case .update:
                try Machine.provisionKernel(force: true)
                selfUpdate()

            case .uninstall:
                selfUninstall()

            case .help:
                printHelp()

            case .unknown:
                printWelcome()
            }
        } catch {
            Log.error(error.localizedDescription)
            exit(1)
        }
    }

    // MARK: - Info

    private static func showInfo(name: String) {
        let vm = Paths.vm(name)
        let fm = FileManager.default
        let m = Style.muted
        let r = Style.reset
        let g = Style.green
        let c = Style.cyan

        guard fm.fileExists(atPath: vm.disk.path) else {
            Log.error("VM '\(name)' not found")
            return
        }

        let isRunning = PIDLock.isLocked(at: vm.pid).isLocked
        var cfg = VMConfig()
        if fm.fileExists(atPath: vm.cfg.path) {
            do {
                cfg = try JSONDecoder().decode(VMConfig.self, from: Data(contentsOf: vm.cfg))
            } catch {
                Log.info("Warning: could not read config, using defaults")
            }
        }

        let attrs = try? fm.attributesOfItem(atPath: vm.disk.path)
        let diskBytes = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
        let diskGB = diskBytes / 1024 / 1024 / 1024

        let status = isRunning ? "\(g)● running\(r)" : "\(m)● stopped\(r)"
        let osName = !cfg.image.isEmpty ? cfg.image : name

        print()
        print("  \(m)OS\(r)          \(osName)")
        print("  \(m)Status\(r)      \(status)")
        print("  \(m)CPU\(r)         \(cfg.cpu) cores")
        print("  \(m)Memory\(r)      \(cfg.memGiB) GB")
        print("  \(m)Disk\(r)        \(diskGB) GB")
        if !cfg.mac.isEmpty {
            print("  \(m)MAC\(r)         \(cfg.mac)")
        }
        
        // Show SSH command if running
        if isRunning, !cfg.mac.isEmpty {
            if let ip = IPDiscovery.findIP(mac: cfg.mac, bridge: cfg.bridge.isEmpty ? nil : cfg.bridge) {
                print("  \(m)SSH\(r)         \(c)ssh root@\(ip)\(r)")
            }
        }

        if !cfg.bridge.isEmpty {
            print("  \(m)Bridge\(r)      \(cfg.bridge)")
        }
        if !cfg.shared.isEmpty {
            print("  \(m)Shared\(r)      \(cfg.shared)")
        }
        
        // Show autostart status
        let daemonPath = "/Library/LaunchDaemons/dev.ss.hylyx.\(name).plist"
        if fm.fileExists(atPath: daemonPath) {
            print("  \(m)Autostart\(r)   \(g)enabled\(r)")
        }
        
        if cfg.bridge.isEmpty {
            print("  \(m)Note\(r)        \(m)VM-to-VM networking requires bridge mode (-b <iface>).\(r)")
        }

        print()
        print("  \(m)Location\(r)    \(vm.dir.path)")
        print()
    }

    // MARK: - Images

    private static func listImages(filter: String?) {
        let m = Style.muted
        let r = Style.reset
        let b = Style.bold
        let p = Style.magenta
        let c = Style.cyan

        do {
            Log.step("Fetching images...")
            let html = try ImageService.fetchIndex()
            let regex = try NSRegularExpression(pattern: #"<span class="name">([^"]+)</span>"#)
            let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

            let names = matches.compactMap { match -> String? in
                guard let range = Range(match.range(at: 1), in: html) else { return nil }
                return String(html[range])
            }

            let list = filter.map { f in names.filter { $0.lowercased().contains(f.lowercased()) } } ?? names
            
            guard !list.isEmpty else {
                print()
                print("  \(m)No images\(filter.map { " matching '\($0)'" } ?? "").\(r)")
                print()
                return
            }

            print()
            print("  \(p)\(b)Available Images\(r)")
            if let f = filter {
                print("  \(m)Filtered by: \(f)\(r)")
            }
            print()

            // Group by distro
            var grouped: [String: [String]] = [:]
            for name in list.sorted() {
                let distro = name.split(separator: "-").first.map(String.init) ?? "other"
                grouped[distro, default: []].append(name)
            }

            for distro in grouped.keys.sorted() {
                let images = grouped[distro]!
                print("  \(c)\(distro)\(r)")
                for img in images {
                    print("    \(m)›\(r) \(img)")
                }
                print()
            }

            print("  \(m)\(list.count) image\(list.count == 1 ? "" : "s") available\(r)")
            print()
        } catch {
            Log.error("Failed to fetch images: \(error.localizedDescription)")
        }
    }

    // MARK: - Bridges

    private static func listBridges() {
        let m = Style.muted
        let r = Style.reset
        let b = Style.bold
        let p = Style.magenta

        guard #available(macOS 13, *) else {
            Log.error("Requires macOS 13+")
            return
        }

        let bridges = NetworkService.listBridges()
        
        print()
        print("  \(p)\(b)Network Interfaces\(r)")
        print()

        guard !bridges.isEmpty else {
            print("  \(m)No bridge interfaces available.\(r)")
            print()
            return
        }

        for bridge in bridges {
            let displayName = bridge.name ?? "Unknown"
            print("  \(m)›\(r) \(b)\(bridge.id)\(r)")
            print("    \(m)\(displayName)\(r)")
            print()
        }

        print("  \(m)Use -b <id> when creating a VM\(r)")
        print()
    }

    // MARK: - Remove Confirmation

    private static func confirmRemove(vms: [String]) {
        let m = Style.muted
        let r = Style.reset
        let b = Style.bold
        let y = Style.yellow

        print()
        print("  \(y)\(b)Remove VMs\(r)")
        print()
        for vm in vms {
            print("  \(m)›\(r) \(vm)")
        }
        print()
        print("  \(m)This will permanently delete all VM data.\(r)")
        print()
        print("  \(y)Continue?\(r) [y/N] ", terminator: "")

        guard readLine()?.lowercased() == "y" else {
            print("  \(m)Cancelled.\(r)")
            print()
            return
        }

        print()
        for name in vms {
            do {
                try Machine.delete(name: name)
            } catch {
                Log.error(error.localizedDescription)
            }
        }
    }

    // MARK: - Self Update/Uninstall

    private static func selfUpdate() {
        let url = Defaults.cloudURL.appendingPathComponent("install.sh").absoluteString
        Log.step("Updating binary...")
        execCurl(url)
    }

    private static func selfUninstall() {
        let url = Defaults.cloudURL.appendingPathComponent("uninstall.sh").absoluteString
        execCurl(url)
    }

    private static func execCurl(_ url: String) {
        var argv: [UnsafeMutablePointer<CChar>?] = [
            strdup("/bin/bash"),
            strdup("-c"),
            strdup("curl -fsSL '\(url)' | bash"),
            nil
        ]
        execv("/bin/bash", &argv)
    }

    // MARK: - Welcome

    private static func printWelcome() {
        let c = Style.cyan
        let m = Style.muted
        let r = Style.reset
        let b = Style.bold
        let p = Style.magenta
        let g = Style.green

        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(atPath: Paths.root.path)) ?? []
        let vms = items.filter { fm.fileExists(atPath: Paths.vm($0).disk.path) }.sorted()
        let running = vms.filter { PIDLock.isLocked(at: Paths.vm($0).pid).isLocked }

        print()
        print("  \(m)╭──────────────────────────────────────────────────────╮\(r)")
        print("  \(m)│\(r)                                                      \(m)│\(r)")
        print("  \(m)│\(r)  \(p)■ ■\(r)  \(p)\(b)hylyx\(r) \(m)v1.0\(r)                                     \(m)│\(r)")
        print("  \(m)│\(r)  \(p)───\(r)  \(m)Linux — Built for Apple Silicon.\(r)               \(m)│\(r)")
        print("  \(m)│\(r)                                                      \(m)│\(r)")
        print("  \(m)╰──────────────────────────────────────────────────────╯\(r)")
        print()

        print("  \(p)\(b)Your VMs\(r)")
        if vms.isEmpty {
            print("  \(m)No VMs yet. Run \(r)\(c)hylyx install ubuntu\(r)\(m) to get started.\(r)")
        } else {
            print()
            for name in vms {
                let isRunning = running.contains(name)
                let dot = isRunning ? "\(g)●\(r)" : "\(m)●\(r)"
                let status = isRunning ? "\(g)running\(r)" : "\(m)stopped\(r)"
                print("  \(dot) \(b)\(name)\(r)  \(status)")
            }
            print()
            let runningCount = running.count
            let stoppedCount = vms.count - runningCount
            var summary = "  \(m)\(vms.count) VM\(vms.count == 1 ? "" : "s")"
            if runningCount > 0 { summary += " · \(r)\(g)\(runningCount) running\(r)\(m)" }
            if stoppedCount > 0 && runningCount > 0 { summary += " · \(stoppedCount) stopped" }
            summary += "\(r)"
            print(summary)
        }
        print()

        print("  \(p)\(b)Commands\(r)")
        print("  \(m)Run\(r) hylyx help \(m)for all commands, or:\(r)")
        print()
        print("    \(c)hylyx install\(r) <name>    \(m)Install & boot VM\(r)")
        print("    \(c)hylyx stop\(r) <name>       \(m)Shutdown VM\(r)")
        print()
    }

    // MARK: - Help

    private static func printHelp() {
        let c = Style.cyan
        let m = Style.muted
        let r = Style.reset
        let b = Style.bold
        let p = Style.magenta

        // Header
        print()
        print("  \(m)╭──────────────────────────────────────────────────────╮\(r)")
        print("  \(m)│\(r)                                                      \(m)│\(r)")
        print("  \(m)│\(r)  \(p)■ ■\(r)  \(p)\(b)hylyx\(r) \(m)v1.0\(r)                                     \(m)│\(r)")
        print("  \(m)│\(r)  \(p)───\(r)  \(m)Linux — Built for Apple Silicon.\(r)               \(m)│\(r)")
        print("  \(m)│\(r)                                                      \(m)│\(r)")
        print("  \(m)╰──────────────────────────────────────────────────────╯\(r)")
        print()

        // VM Lifecycle
        print("  \(p)\(b)VM Lifecycle\(r)")
        print()
        print("    \(c)install\(r) <name> [distro]    Create VM, copy SSH, start")
        print("    \(c)start\(r) <name>               Start VM in background")
        print("    \(c)start\(r) <name> \(c)-c\(r)            Start with serial console")
        print("    \(c)stop\(r) <name> ...            Stop VM(s)")
        print("    \(c)restart\(r) <name> ...         Restart VM(s)")
        print("    \(c)del\(r) <name> ...             Delete VM(s)")
        print()

        // VM Management
        print("  \(p)\(b)VM Management\(r)")
        print()
        print("    \(c)info\(r) <name>                Show details, discover IP")
        print("    \(c)clone\(r) <src> <dst>          Clone stopped VM")
        print("    \(c)resize\(r) <name> <GB>         Grow or shrink disk")
        print("    \(c)autostart\(r) <name>           Enable boot startup (sudo)")
        print("    \(c)autostart\(r) <name> \(c)off\(r)       Disable boot startup (sudo)")
        print()

        // Discovery
        print("  \(p)\(b)Discovery\(r)")
        print()
        print("    \(c)images\(r) [filter]            List available images")
        print("    \(c)bridges\(r)                    List network interfaces")
        print()

        // System
        print("  \(p)\(b)System\(r)")
        print()
        print("    \(c)update\(r)                     Update Hylyx")
        print("    \(c)uninstall\(r)                  Remove Hylyx")
        print("    \(c)help\(r)                       Show this help")
        print()

        // Create Options
        print("  \(p)\(b)Create Options\(r)")
        print()
        print("    \(m)-p\(r) <n>       \(m)CPU cores      (default: all)\(r)")
        print("    \(m)-m\(r) <GB>      \(m)Memory         (default: 2)\(r)")
        print("    \(m)-s\(r) <GB>      \(m)Disk size      (default: 16)\(r)")
        print("    \(m)-b\(r) <iface>   \(m)Bridge network (default: NAT)\(r)")
        print("    \(m)-d\(r) <path>    \(m)Mount host directory in guest\(r)")
        print("    \(m)-t\(r) <file>    \(m)Use local rootfs archive\(r)")
        print()

        // Get Started
        print("  \(p)\(b)Get Started\(r)")
        print()
        print("    \(m)$\(r) \(c)hylyx install ubuntu\(r)   \(m)# or alpine, fedora\(r)")
        print()
    }
}
