import Virtualization

@available(macOS 13, *)
let bridgeInterfaces = VZBridgedNetworkInterface.networkInterfaces

enum NetworkService {
    @available(macOS 13, *)
    static func createDevice(bridge name: String, mac: String?) -> VZVirtioNetworkDeviceConfiguration {
        let dev = VZVirtioNetworkDeviceConfiguration()

        if !name.isEmpty,
           let iface = bridgeInterfaces.first(where: { $0.identifier == name || $0.localizedDisplayName == name }) {
            dev.attachment = VZBridgedNetworkDeviceAttachment(interface: iface)
        } else {
            dev.attachment = VZNATNetworkDeviceAttachment()
        }

        if let mac = mac, let addr = VZMACAddress(string: mac) {
            dev.macAddress = addr
        }

        return dev
    }

    @available(macOS 13, *)
    static func listBridges() -> [(id: String, name: String?)] {
        bridgeInterfaces.map { ($0.identifier, $0.localizedDisplayName) }
    }
}
