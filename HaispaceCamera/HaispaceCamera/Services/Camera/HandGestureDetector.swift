// HandGestureDetector.swift
// HaispaceCamera — Services/Camera
//
// Detektor gesture "Hai" (5 Jari / Open Palm) berbasis iOS Vision Framework.
// Berjalan secara efisien menggunakan Neural Engine (ANE) tanpa membebani CPU/GPU.
//

import Foundation
import Vision
import CoreMedia

class HandGestureDetector {
    static let shared = HandGestureDetector()
    
    private let handPoseRequest = VNDetectHumanHandPoseRequest()
    private var lastTriggerTime: Date = .distantPast
    
    private init() {
        handPoseRequest.maximumHandCount = 1
    }
    
    /// Memproses frame video secara asinkron untuk mendeteksi telapak tangan terbuka ("Hai")
    func processFrame(_ sampleBuffer: CMSampleBuffer, onGestureDetected: @escaping () -> Void) {
        // Cooldown 5 detik untuk mencegah double-trigger selama countdown dan jepretan berlangsung
        guard Date().timeIntervalSince(lastTriggerTime) > 5 else { return }
        
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, options: [:])
        do {
            try handler.perform([handPoseRequest])
            guard let observation = handPoseRequest.results?.first else { return }
            
            // Dapatkan titik pergelangan tangan (wrist) sebagai referensi jarak
            let wrist = try observation.recognizedPoint(.wrist)
            guard wrist.confidence > 0.3 else { return }
            
            var extendedFingers = 0
            
            // Jari yang dideteksi (selain jempol)
            let fingers: [VNDetectHumanHandPoseRequest.JointsGroupName] = [
                .indexFinger, .middleFinger, .ringFinger, .littleFinger
            ]
            
            for finger in fingers {
                let mcp = try observation.recognizedPoint(try jointName(for: finger, type: .mcp))
                let tip = try observation.recognizedPoint(try jointName(for: finger, type: .tip))
                
                if mcp.confidence > 0.3 && tip.confidence > 0.3 {
                    // Hitung jarak dari pergelangan tangan (wrist) ke sendi bawah (mcp) dan ke ujung jari (tip)
                    let distWristToMCP = distance(from: wrist.location, to: mcp.location)
                    let distWristToTip = distance(from: wrist.location, to: tip.location)
                    
                    // Jika ujung jari jauh lebih panjang daripada sendi pangkal, berarti jari diluruskan
                    if distWristToTip > distWristToMCP * 1.3 {
                        extendedFingers += 1
                    }
                }
            }
            
            // Deteksi khusus jempol (thumb)
            let thumbIP = try observation.recognizedPoint(.thumbIP)
            let thumbTip = try observation.recognizedPoint(.thumbTip)
            if thumbIP.confidence > 0.3 && thumbTip.confidence > 0.3 {
                let distWristToIP = distance(from: wrist.location, to: thumbIP.location)
                let distWristToTip = distance(from: wrist.location, to: thumbTip.location)
                if distWristToTip > distWristToIP * 1.15 {
                    extendedFingers += 1
                }
            }
            
            // Jika minimal 4 dari 5 jari tegak diluruskan, kita anggap tamu sedang menyapa "Hai" (Open Palm)
            if extendedFingers >= 4 {
                lastTriggerTime = Date()
                onGestureDetected()
            }
            
        } catch {
            // Abaikan kesalahan pembacaan frame sementara
        }
    }
    
    private func jointName(for group: VNDetectHumanHandPoseRequest.JointsGroupName, type: JointType) throws -> VNDetectHumanHandPoseRequest.JointName {
        switch (group, type) {
        case (.indexFinger, .mcp): return .indexMCP
        case (.indexFinger, .tip): return .indexTip
        case (.middleFinger, .mcp): return .middleMCP
        case (.middleFinger, .tip): return .middleTip
        case (.ringFinger, .mcp): return .ringMCP
        case (.ringFinger, .tip): return .ringTip
        case (.littleFinger, .mcp): return .littleMCP
        case (.littleFinger, .tip): return .littleTip
        default:
            throw NSError(domain: "HandGestureDetector", code: 1, userInfo: nil)
        }
    }
    
    private enum JointType {
        case mcp, tip
    }
    
    private func distance(from p1: CGPoint, to p2: CGPoint) -> CGFloat {
        let dx = p1.x - p2.x
        let dy = p1.y - p2.y
        return sqrt(dx * dx + dy * dy)
    }
}
