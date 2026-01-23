import Foundation
import Virtualization

@available(macOS 13, *)
func runVM(named name: String) throws {
    let vm = Paths.vm(name)
    let fm = FileManager.default

    guard fm.fileExists(atPath: vm.disk.path) else {
        throw HyError.notFound("VM '\(name)'")
    }

    let lock = PIDLock(path: vm.pid)
    try lock.acquire()

    var cfg = try JSONDecoder().decode(VMConfig.self, from: Data(contentsOf: vm.cfg))
    let expectedMAC = MACAddress.fromName(name)
    if cfg.mac != expectedMAC {
        cfg.mac = expectedMAC
        try JSONEncoder().encode(cfg).write(to: vm.cfg)
    }

    if isatty(STDIN_FILENO) != 0 { enableRawTerminalMode() }

    let vzCfg = VZVirtualMachineConfiguration()
    vzCfg.cpuCount = cfg.cpu
    vzCfg.memorySize = cfg.memGiB.gibibytes

    let serial = VZVirtioConsoleDeviceSerialPortConfiguration()
    serial.attachment = VZFileHandleSerialPortAttachment(
        fileHandleForReading: .standardInput,
        fileHandleForWriting: .standardOutput
    )
    vzCfg.serialPorts = [serial]

    let boot = VZLinuxBootLoader(kernelURL: Paths.kernel)
    boot.commandLine = Defaults.kernelCmdline
    vzCfg.bootLoader = boot

    vzCfg.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
    vzCfg.memoryBalloonDevices = [VZVirtioTraditionalMemoryBalloonDeviceConfiguration()]

    let disk = try VZDiskImageStorageDeviceAttachment(url: vm.disk, readOnly: false)
    vzCfg.storageDevices = [VZVirtioBlockDeviceConfiguration(attachment: disk)]
    vzCfg.networkDevices = [NetworkService.createDevice(bridge: cfg.bridge, mac: cfg.mac)]

    if !cfg.shared.isEmpty {
        let shareURL = URL(fileURLWithPath: cfg.shared.expandingTildeInPath)
        let share = VZSharedDirectory(url: shareURL, readOnly: false)
        let fs = VZVirtioFileSystemDeviceConfiguration(tag: "host")
        fs.share = VZSingleDirectoryShare(directory: share)
        vzCfg.directorySharingDevices = [fs]
    }

    try vzCfg.validate()

    let machine = VZVirtualMachine(configuration: vzCfg)
    let delegate = VMDelegate(lock: lock)
    machine.delegate = delegate

    machine.start { result in
        if case .failure(let error) = result {
            Log.error(error.localizedDescription)
            lock.release()
            exit(1)
        }
    }

    RunLoop.main.run()
}
