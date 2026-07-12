// NetworkUtility.swift
// HaispaceCamera — Core/Network
//
// Utilitas untuk mendapatkan konfigurasi jaringan lokal (IP Address WiFi).

import Foundation

struct NetworkUtility {
    
    /// Mendapatkan alamat IPv4 WiFi (en0) dari perangkat
    static func getWiFiAddress() -> String? {
        var address: String?
        
        // Dapatkan semua network interfaces
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }
        
        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            
            if addrFamily == UInt8(AF_INET) { // IPv4
                let name = String(cString: interface.ifa_name)
                if name == "en0" { // Biasanya en0 adalah WiFi di iOS/iPadOS
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        socklen_t(0),
                        NI_NUMERICHOST
                    )
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }
}
