import Foundation
import Darwin

enum Machine {
    // MARK: - Create

    static func create(
        name: String,
        image: String? = nil,
        localTar: String? = nil,
        cpu: Int? = nil,
        mem: UInt64? = nil,
        bridge: String? = nil,
        shared: String? = nil,
        sizeGiB: UInt64? = nil
    ) throws {
        try Validation.vmName(name)
        try Paths.ensureRoot()

        let vm = Paths.vm(name)
        let fm = FileManager.default

        guard !fm.fileExists(atPath: vm.dir.path) else {
            throw HyError.alreadyExists("VM '\(name)'")
        }

        var success = false
        defer { if !success { try? fm.removeItem(at: vm.dir) } }

        let tmp = fm.tmpDir()
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let archive: URL
        let imageName: String
        if let tar = localTar {
            archive = try ImageService.resolve(from: .local(URL(fileURLWithPath: tar.expandingTildeInPath)), into: tmp)
            imageName = URL(fileURLWithPath: tar).deletingPathExtension().deletingPathExtension().lastPathComponent
        } else {
            let cloudImage = image ?? name
            archive = try ImageService.resolve(from: .cloud(cloudImage), into: tmp)
            imageName = cloudImage
        }

        try fm.createDirectory(at: vm.dir, withIntermediateDirectories: true)

        let size = sizeGiB ?? Defaults.diskGB
        try shell("/usr/bin/truncate", ["-s", "\(size)G", vm.disk.path])
        try shell(Toolchain.mkfs, ["-F", "-q", "-t", "ext4", "-L", name, "-d", archive.path, vm.disk.path])

        var cfg = VMConfig()
        if let c = cpu { cfg.cpu = c }
        if let m = mem { cfg.memGiB = m }
        if let b = bridge { cfg.bridge = b }
        if let s = shared { cfg.shared = s }
        cfg.image = imageName
        try JSONEncoder().encode(cfg).write(to: vm.cfg)

        Log.success("VM '\(name)' created")
        success = true
    }

    // MARK: - Start

    static func start(name: String, console: Bool) throws {
        try Validation.vmName(name)
        let vm = Paths.vm(name)
        let fm = FileManager.default
        
        guard fm.fileExists(atPath: vm.disk.path) else {
            throw HyError.notFound("VM '\(name)'")
        }
        
        // Already running?
        if PIDLock.isLocked(at: vm.pid).isLocked {
            if console {
                throw HyError.vmRunning(name)
            }
            Log.info("VM '\(name)' is already running")
            showConnectionInfo(name: name)
            return
        }
        
        try provisionKernel()

        if console {
            // Foreground with serial console
            if #available(macOS 13, *) {
                try runVM(named: name)
            } else {
                throw HyError.unsupportedOS(required: "macOS 13+")
            }
        } else {
            // Background mode (default)
            let exe = Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
            fm.createFile(atPath: vm.log.path, contents: nil)
            let logHandle = try? FileHandle(forWritingTo: vm.log)
            defer { logHandle?.closeFile() }

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: exe)
            proc.arguments = ["start", name, "-c"]
            proc.standardOutput = logHandle
            proc.standardError = logHandle
            proc.standardInput = FileHandle(forReadingAtPath: "/dev/null")
            try proc.run()

            Log.success("VM '\(name)' started")
            
            // Wait for VM to boot and discover IP
            showConnectionInfo(name: name, waitForIP: true)
        }
    }
    
    /// Show connection info (IP address) for a running VM
    static func showConnectionInfo(name: String, waitForIP: Bool = false) {
        let vm = Paths.vm(name)
        let m = Style.muted
        let r = Style.reset
        let c = Style.cyan
        
        if waitForIP {
            print("  \(m)Looking for IP address...\(r)", terminator: "")
            fflush(stdout)
        }
        
        // Wait for MAC to be written by subprocess (up to 5 seconds)
        var mac = ""
        var bridge = ""
        var waited = 0
        for _ in 1...5 {
            if let cfg = try? JSONDecoder().decode(VMConfig.self, from: Data(contentsOf: vm.cfg)),
               !cfg.mac.isEmpty {
                mac = cfg.mac.lowercased()
                bridge = cfg.bridge
                break
            }
            usleep(1_000_000)
            waited += 1
        }
        guard !mac.isEmpty else {
            if waitForIP { print("\r\u{1b}[K", terminator: "") }
            return
        }
        
        // Ensure minimum 5s wait for VM to boot before IP discovery
        if waitForIP && waited < 5 {
            usleep(UInt32((5 - waited) * 1_000_000))
        }
        
        // Try to find IP (retry every 5s for 30s)
        let maxAttempts = waitForIP ? 6 : 1
        for attempt in 1...maxAttempts {
            if let ip = IPDiscovery.findIP(mac: mac, bridge: bridge.isEmpty ? nil : bridge) {
                if waitForIP { print("\r\u{1b}[K", terminator: "") }
                print()
                print("  \(m)Connect:\(r)")
                print("  \(c)ssh root@\(ip)\(r)")
                if bridge.isEmpty {
                    print("  \(m)Note: VM-to-VM networking requires bridge mode (-b <iface>).\(r)")
                }
                print()
                return
            }
            if waitForIP && attempt < maxAttempts {
                print(".", terminator: "")
                fflush(stdout)
                usleep(5_000_000)
            }
        }
        
        if waitForIP { print("\r\u{1b}[K", terminator: "") }
        print()
        print("  \(m)IP not detected. Check with:\(r) \(c)hylyx info \(name)\(r)")
        print()
    }
    
    // MARK: - Stop

    static func stop(name: String) throws {
        try Validation.vmName(name)
        let vm = Paths.vm(name)
        let (locked, pid) = PIDLock.isLocked(at: vm.pid)
        guard locked, let p = pid else {
            throw HyError.vmNotRunning(name)
        }
        kill(p, SIGTERM)
        Log.success("VM '\(name)' stopped")
    }

    // MARK: - Restart

    static func restart(name: String) throws {
        try stop(name: name)

        // Wait for lock to be released (up to 10 seconds)
        let vm = Paths.vm(name)
        var stopped = false
        for _ in 1...20 {
            if !PIDLock.isLocked(at: vm.pid).isLocked {
                stopped = true
                break
            }
            usleep(500_000)
        }

        guard stopped else {
            throw HyError.vmStopTimeout(name)
        }

        try start(name: name, console: false)
    }

    // MARK: - Autostart

    static func enableAutostart(name: String) throws {
        try Validation.vmName(name)
        guard getuid() == 0 else {
            throw HyError.custom("Run with sudo: sudo hylyx autostart \(name)")
        }
        
        // Get the actual user (not root) when running with sudo
        guard let username = ProcessInfo.processInfo.environment["SUDO_USER"], !username.isEmpty else {
            throw HyError.custom("Could not determine user. Run with: sudo hylyx autostart \(name)")
        }
        
        // Check VM exists in user's home (not root's)
        let userHome = "/Users/\(username)"
        let vmDisk = "\(userHome)/.hylyx/\(name)/\(name).img"
        guard FileManager.default.fileExists(atPath: vmDisk) else {
            throw HyError.notFound("VM '\(name)'")
        }
        
        let plistPath = launchDaemonPath(for: name)
        
        // Run as the original user so ~/.hylyx paths work correctly
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>dev.ss.hylyx.\(name)</string>
            <key>UserName</key>
            <string>\(username)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/local/bin/hylyx</string>
                <string>start</string>
                <string>\(name)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
        </dict>
        </plist>
        """
        
        try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
        
        // Load the daemon
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["load", plistPath]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        
        Log.success("Autostart enabled for '\(name)' (starts at boot)")
    }
    
    static func disableAutostart(name: String) throws {
        try Validation.vmName(name)
        let plistPath = launchDaemonPath(for: name)
        let fm = FileManager.default
        
        guard fm.fileExists(atPath: plistPath) else {
            Log.info("Autostart not enabled for '\(name)'")
            return
        }
        
        guard getuid() == 0 else {
            throw HyError.custom("Run with sudo: sudo hylyx autostart \(name) off")
        }
        
        // Unload the daemon
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["unload", plistPath]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        
        try fm.removeItem(atPath: plistPath)
        Log.success("Autostart disabled for '\(name)'")
    }
    
    private static func launchDaemonPath(for name: String) -> String {
        "/Library/LaunchDaemons/dev.ss.hylyx.\(name).plist"
    }

    // MARK: - Clone

    static func clone(src: String, dst: String) throws {
        try Validation.vmName(src)
        try Validation.vmName(dst)

        let fm = FileManager.default
        let srcVM = Paths.vm(src)
        let dstVM = Paths.vm(dst)

        guard fm.fileExists(atPath: srcVM.disk.path) else {
            throw HyError.notFound("VM '\(src)'")
        }
        guard !fm.fileExists(atPath: dstVM.disk.path) else {
            throw HyError.alreadyExists("VM '\(dst)'")
        }
        guard !PIDLock.isLocked(at: srcVM.pid).isLocked else {
            throw HyError.vmRunning(src)
        }

        var success = false
        defer { if !success { try? fm.removeItem(at: dstVM.dir) } }

        try fm.createDirectory(at: dstVM.dir, withIntermediateDirectories: true)
        try fm.copyItem(at: srcVM.disk, to: dstVM.disk)
        if fm.fileExists(atPath: srcVM.cfg.path) {
            var cfg = try JSONDecoder().decode(VMConfig.self, from: Data(contentsOf: srcVM.cfg))
            cfg.mac = ""  // Reset MAC so clone gets new address on first start
            try JSONEncoder().encode(cfg).write(to: dstVM.cfg)
        }

        success = true
        Log.success("Cloned '\(src)' → '\(dst)'")
    }

    // MARK: - Resize

    static func resize(name: String, toGiB newSize: UInt64) throws {
        try Validation.vmName(name)
        let vm = Paths.vm(name)
        let fm = FileManager.default

        guard fm.fileExists(atPath: vm.disk.path) else {
            throw HyError.notFound("VM '\(name)'")
        }
        guard !PIDLock.isLocked(at: vm.pid).isLocked else {
            throw HyError.vmRunning(name)
        }

        // Filesystem check
        let fsck = Process()
        fsck.executableURL = URL(fileURLWithPath: Toolchain.fsck)
        fsck.arguments = ["-pf", vm.disk.path]
        try fsck.run(); fsck.waitUntilExit()
        guard fsck.terminationStatus <= 1 else {
            throw HyError.executionFailed(command: Toolchain.fsck, exitCode: fsck.terminationStatus)
        }

        // Current size
        let attrs = try fm.attributesOfItem(atPath: vm.disk.path)
        let curBytes = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let curGiB = curBytes / 1024 / 1024 / 1024

        if newSize >= curGiB {
            // Grow
            try verifyDiskSpace(forGrowingTo: newSize, at: vm.disk)
            try shell("/usr/bin/truncate", ["-s", "\(newSize)G", vm.disk.path])
            try shell(Toolchain.resize, ["-p", vm.disk.path])
        } else {
            // Shrink
            try shell(Toolchain.resize, ["-p", vm.disk.path, "\(newSize)G"])
            try shell("/usr/bin/truncate", ["-s", "\(newSize)G", vm.disk.path])
        }

        Log.success("Resized '\(name)' to \(newSize) GiB")
    }

    // MARK: - Delete

    static func delete(name: String) throws {
        try Validation.vmName(name)
        let vm = Paths.vm(name)
        let fm = FileManager.default

        guard fm.fileExists(atPath: vm.dir.path) else {
            throw HyError.notFound("VM '\(name)'")
        }
        guard !PIDLock.isLocked(at: vm.pid).isLocked else {
            throw HyError.vmRunning(name)
        }

        try fm.removeItem(at: vm.dir)
        Log.success("VM '\(name)' deleted")
    }

    // MARK: - Kernel

    static func provisionKernel(force: Bool = false) throws {
        try Paths.ensureRoot()
        let kernel = Paths.kernel
        if !force && FileManager.default.fileExists(atPath: kernel.path) { return }

        Log.step("Fetching kernel...")
        let tmp = FileManager.default.tmpDir()
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let archive = try ImageService.resolve(from: .cloud("linux"), into: tmp)
        let extDir = tmp.appendingPathComponent("kernel")
        try FileManager.default.createDirectory(at: extDir, withIntermediateDirectories: true)

        try ImageService.extract(archive: archive, to: extDir)

        guard let candidate = ImageService.firstFile(in: extDir) else {
            throw HyError.notFound("kernel in archive")
        }

        if FileManager.default.fileExists(atPath: kernel.path) {
            try FileManager.default.removeItem(at: kernel)
        }
        try FileManager.default.moveItem(at: candidate, to: kernel)
        Log.success("Kernel updated")
    }

    // MARK: - Helpers

    private static func verifyDiskSpace(forGrowingTo newSizeGiB: UInt64, at path: URL) throws {
        var fs = Darwin.statfs()
        let dirPath = path.deletingLastPathComponent().path
        guard statfs(dirPath, &fs) == 0 else {
            Log.info("Warning: could not check available disk space")
            return
        }

        let available = UInt64(fs.f_bavail) * UInt64(fs.f_bsize)

        var st = Darwin.stat()
        // If lstat fails, assume worst case (no existing data to account for)
        let used: UInt64 = lstat(path.path, &st) == 0 ? UInt64(st.st_blocks) * 512 : 0

        let needed = newSizeGiB.gibibytes
        let additional = needed > used ? needed - used : 0

        guard available >= additional else {
            throw HyError.insufficientDiskSpace(
                required: additional / 1024 / 1024 / 1024,
                available: available / 1024 / 1024 / 1024
            )
        }
    }

    // MARK: - SSH Key Injection

    /// Find or create default SSH public key from ~/.ssh/
    static func findDefaultSSHKey() -> (path: String, content: String)? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let sshDir = home.appendingPathComponent(".ssh")
        let candidates = ["id_ed25519.pub", "id_ecdsa.pub", "id_rsa.pub"]
        
        for name in candidates {
            let keyPath = sshDir.appendingPathComponent(name)
            if let content = try? String(contentsOf: keyPath, encoding: .utf8) {
                return (keyPath.path, content.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        
        // Generate ECDSA key if none found
        let keyPath = sshDir.appendingPathComponent("id_ecdsa")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        proc.arguments = ["-t", "ecdsa", "-b", "521", "-N", "", "-f", keyPath.path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let pubPath = sshDir.appendingPathComponent("id_ecdsa.pub")
            if let content = try? String(contentsOf: pubPath, encoding: .utf8) {
                Log.success("SSH key generated: \(pubPath.path)")
                return (pubPath.path, content.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } catch {}
        return nil
    }

    /// Inject SSH key into disk image using debugfs
    static func injectSSHKey(_ key: String, into diskPath: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: Toolchain.debugfs) else { return false }
        
        let tmp = fm.tmpDir(prefix: "hylyx-ssh")
        let keyFile = tmp.appendingPathComponent("key.pub")
        let cmdFile = tmp.appendingPathComponent("cmd")
        
        let keyContent = key.hasSuffix("\n") ? key : key + "\n"
        let cmds = "mkdir /root/.ssh\nrm /root/.ssh/authorized_keys\nwrite \(keyFile.path) /root/.ssh/authorized_keys\n"
        
        do {
            try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
            try keyContent.write(to: keyFile, atomically: true, encoding: .utf8)
            try cmds.write(to: cmdFile, atomically: true, encoding: .utf8)
        } catch { return false }
        defer { try? fm.removeItem(at: tmp) }
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: Toolchain.debugfs)
        proc.arguments = ["-w", "-f", cmdFile.path, diskPath.path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch { return false }
    }
}
