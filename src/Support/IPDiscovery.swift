import Foundation

enum IPDiscovery {
    /// Find IP address for a VM by MAC - pings subnet to populate ARP, then resolves MAC
    /// Note: Assumes /24 subnet (standard for VM bridges on macOS)
    static func findIP(mac: String, bridge: String? = nil) -> String? {
        let (ifaces, wide) = bridge.flatMap { $0.isEmpty ? nil : ([$0], true) } ?? (vmnetInterfaces(), false)
        guard !ifaces.isEmpty else { return nil }
        for iface in ifaces { pingSubnet(iface, range: wide ? 2...254 : 2...100) }
        return findMACInARP(mac, interfaces: ifaces)
    }
    
    /// List vmnet bridge interfaces (bridge100, bridge101, etc.)
    private static func vmnetInterfaces() -> [String] {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        proc.arguments = ["-l"]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        
        guard let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else {
            return []
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").compactMap { name in
            let s = String(name)
            return s.hasPrefix("bridge1") ? s : nil
        }
    }
    
    /// Ping IPs in range on interface (throttled to 32 concurrent)
    private static func pingSubnet(_ iface: String, range: ClosedRange<Int>) {
        guard let subnet = getSubnet(for: iface) else { return }
        let sem = DispatchSemaphore(value: 32)
        let group = DispatchGroup()
        for i in range {
            sem.wait()
            group.enter()
            DispatchQueue.global().async {
                defer { sem.signal(); group.leave() }
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/sbin/ping")
                proc.arguments = ["-c", "1", "-W", "100", "-q", "\(subnet).\(i)"]
                proc.standardOutput = FileHandle.nullDevice
                proc.standardError = FileHandle.nullDevice
                try? proc.run()
                proc.waitUntilExit()
            }
        }
        group.wait()
    }
    
    /// Get subnet (first 3 octets) from interface
    private static func getSubnet(for iface: String) -> String? {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        proc.arguments = [iface]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        
        guard let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else {
            return nil
        }
        for line in output.components(separatedBy: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ")
            if parts.first == "inet", parts.count >= 2 {
                let octets = String(parts[1]).split(separator: ".")
                if octets.count == 4 {
                    return "\(octets[0]).\(octets[1]).\(octets[2])"
                }
            }
        }
        return nil
    }
    
    /// Find IP for MAC in ARP table - returns last matching entry (most recent)
    private static func findMACInARP(_ mac: String, interfaces: [String]) -> String? {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        proc.arguments = ["-a", "-n"]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        
        guard let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else {
            return nil
        }
        
        let normalizedMAC = normalizeMAC(mac)
        var result: String? = nil
        
        for line in output.components(separatedBy: "\n") {
            // Parse: "? (192.168.66.2) at 52:54:0:68:3:fa on bridge100 ifscope [bridge]"
            let parts = line.components(separatedBy: " at ")
            guard parts.count >= 2 else { continue }
            
            let onParts = parts[1].components(separatedBy: " on ")
            guard onParts.count >= 2 else { continue }
            
            let ifacePart = onParts[1].components(separatedBy: " ").first ?? ""
            guard interfaces.contains(ifacePart) else { continue }
            
            let lineMAC = normalizeMAC(onParts[0].components(separatedBy: " ").first ?? "")
            guard lineMAC == normalizedMAC else { continue }
            
            if let start = line.firstIndex(of: "("), let end = line.firstIndex(of: ")") {
                let ip = String(line[line.index(after: start)..<end])
                if isReachable(ip) { result = ip }  // Keep last reachable match
            }
        }
        return result
    }
    
    /// Quick ping check to verify IP is actually reachable
    private static func isReachable(_ ip: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/sbin/ping")
        proc.arguments = ["-c", "1", "-W", "200", "-q", ip]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        return proc.terminationStatus == 0
    }
    
    /// Normalize MAC to lowercase with leading zeros (handles : or - separators)
    private static func normalizeMAC(_ mac: String) -> String {
        mac.replacingOccurrences(of: "-", with: ":").split(separator: ":").map { part in
            let s = String(part).lowercased()
            return s.count == 1 ? "0\(s)" : s
        }.joined(separator: ":")
    }
}
