// BonjourDownloadServer.swift
// HaispaceBooths — Services/Delivery
//
// HTTP Server lokal sederhana menggunakan Network.framework.
// Digunakan saat offline (internet mati) agar tamu tetap bisa men-download foto
// langsung dari iPad melalui jaringan WiFi lokal.
//
// Ref: docs/design/10_photo_delivery.md

import Foundation
import Network

@MainActor
final class BonjourDownloadServer {
    
    static let shared = BonjourDownloadServer()
    
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    
    // Alamat IP lokal
    private(set) var localIPAddress: String?
    let port: NWEndpoint.Port = 8080
    
    // Penyimpanan foto sementara untuk disajikan (Key: Photo ID)
    private var hostedPhotos: [String: Data] = [:]
    
    private init() {}
    
    // MARK: - Server Lifecycle
    
    func start() throws {
        guard listener == nil else { return }
        
        let parameters = NWParameters.tcp
        listener = try NWListener(using: parameters, on: port)
        
        listener?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self = self else { return }
                switch state {
                case .ready:
                    HaispaceLogger.info("BonjourDownloadServer berjalan di port \(self.port.rawValue)", category: "delivery")
                    self.localIPAddress = self.getWiFiAddress()
                case .failed(let error):
                    HaispaceLogger.error(error)
                    self.stop()
                default:
                    break
                }
            }
        }
        
        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleNewConnection(connection)
            }
        }
        
        listener?.start(queue: .global(qos: .userInitiated))
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()
        HaispaceLogger.info("BonjourDownloadServer dihentikan", category: "delivery")
    }
    
    // MARK: - Photo Hosting
    
    /// Menyajikan foto agar bisa di-download tamu
    /// Return: URL lokal untuk di-encode jadi QR Code
    func hostPhoto(id: String, data: Data) -> String {
        hostedPhotos[id] = data
        let ip = localIPAddress ?? "192.168.1.1" // Fallback dummy
        return "http://\(ip):\(port.rawValue)/photo/\(id).jpg"
    }
    
    /// Hapus foto dari memory jika sesi selesai sepenuhnya
    func unhostPhoto(id: String) {
        hostedPhotos.removeValue(forKey: id)
    }
    
    // MARK: - HTTP Handling
    
    private func handleNewConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self.receiveHTTP(on: connection)
                case .failed, .cancelled:
                    self.connections.removeAll { $0 === connection }
                default:
                    break
                }
            }
        }
        connections.append(connection)
        connection.start(queue: .global(qos: .userInitiated))
    }
    
    private func receiveHTTP(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, context, isComplete, error in
            Task { @MainActor in
                guard let self = self, let data = data, !data.isEmpty else {
                    connection.cancel()
                    return
                }
                
                // Parse HTTP Request
                if let requestString = String(data: data, encoding: .utf8) {
                    let lines = requestString.components(separatedBy: .newlines)
                    if let firstLine = lines.first {
                        let parts = firstLine.components(separatedBy: " ")
                        if parts.count >= 2, parts[0] == "GET" {
                            let path = parts[1]
                            self.handleGETRequest(path: path, on: connection)
                            return
                        }
                    }
                }
                
                // Invalid request
                self.sendHTTPResponse(status: 400, contentType: "text/plain", body: "Bad Request".data(using: .utf8)!, on: connection)
            }
        }
    }
    
    private func handleGETRequest(path: String, on connection: NWConnection) {
        // Path expected: /photo/{id}.jpg
        let components = path.split(separator: "/")
        
        if components.count == 2, components[0] == "photo", let file = components[1].split(separator: ".").first {
            let photoId = String(file)
            if let photoData = hostedPhotos[photoId] {
                // Return JPEG Image
                sendHTTPResponse(status: 200, contentType: "image/jpeg", body: photoData, on: connection)
                return
            }
        }
        
        // Not Found
        sendHTTPResponse(status: 404, contentType: "text/plain", body: "Photo Not Found".data(using: .utf8)!, on: connection)
    }
    
    private func sendHTTPResponse(status: Int, contentType: String, body: Data, on connection: NWConnection) {
        let statusString = status == 200 ? "200 OK" : "\(status) Error"
        
        var header = "HTTP/1.1 \(statusString)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n\r\n"
        
        var responseData = header.data(using: .utf8)!
        responseData.append(body)
        
        connection.send(content: responseData, completion: .contentProcessed({ error in
            connection.cancel()
        }))
    }
    
    // MARK: - IP Helper
    
    private func getWiFiAddress() -> String? {
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
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }
}
