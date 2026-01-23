import Foundation
import Virtualization

@available(macOS 13, *)
final class VMDelegate: NSObject, VZVirtualMachineDelegate {
    private let lock: PIDLock

    init(lock: PIDLock) {
        self.lock = lock
        super.init()
    }

    func virtualMachine(_ vm: VZVirtualMachine, didStopWithError error: Error) {
        restoreTerminalMode()
        Log.error("VM stopped: \(error.localizedDescription)")
        lock.release()
        exit(1)
    }

    func guestDidStop(_ vm: VZVirtualMachine) {
        restoreTerminalMode()
        Log.info("VM exited")
        lock.release()
        exit(0)
    }
}
