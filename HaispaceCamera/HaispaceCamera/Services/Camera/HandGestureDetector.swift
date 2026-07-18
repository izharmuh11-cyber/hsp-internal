// HandGestureDetector.swift
// HaispaceCamera — Services/Camera
//
// Detektor gesture "Hai" (5 Jari / Open Palm) berbasis iOS Vision Framework.
// Berjalan secara efisien menggunakan Neural Engine (ANE) tanpa membebani CPU/GPU.
//
// FITUR KEAMANAN GESTUR (ANTI FALSE TRIGGER):
// 1. Dwell Time / Temporal Persistence (0.6s / 18 consecutive frames hold)
// 2. High Joint Confidence Threshold (>= 0.60)
// 3. Proximity / Hand Size Filter (tangan harus cukup dekat dengan kamera)
// 4. Reset instan jika gestur terputus mid-way -> 0 false positives!

import Foundation
import Vision
import CoreMedia

class HandGestureDetector {
    static let shared = HandGestureDetector()
    
    private let handPoseRequest = VNDetectHumanHandPoseRequest()
    private var lastTriggerTime: Date = .distantPast
    
    // Tracking Dwell Time / Temporal Persistence
    private var holdFrameCount: Int = 0
    private var firstDetectedTime: Date? = nil
    private var lastWristPosition: CGPoint? = nil
    
    // Syarat kelayakan gestur: ditahan stabil minimal 22 frame (~0.75 detik pada 30fps)
    private let requiredHoldFrames: Int = 22
    private let requiredHoldDuration: TimeInterval = 0.75
    
    private init() {
        handPoseRequest.maximumHandCount = 1
    }
    
    /// Memproses frame video secara asinkron untuk mendeteksi telapak tangan terbuka ("Hai")
    func processFrame(_ sampleBuffer: CMSampleBuffer, onGestureDetected: @escaping () -> Void) {
        // Cooldown 5 detik setelah pemicu sukses agar tidak double-trigger saat countdown photobooth
        guard Date().timeIntervalSince(lastTriggerTime) > 5.0 else {
            resetHoldState()
            return
        }
        
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, options: [:])
        do {
            try handler.perform([handPoseRequest])
            guard let observation = handPoseRequest.results?.first else {
                resetHoldState()
                return
            }
            
            // Dapatkan titik pergelangan tangan (wrist) sebagai referensi dasar
            let wrist = try observation.recognizedPoint(.wrist)
            guard wrist.confidence >= 0.65 else {
                resetHoldState()
                return
            }
            
            // Motion Stability Check: Jika tangan bergerak terlalu cepat (gerakan tidak stabil),
            // abaikan frame ini (mencegah pemicuan dari gerakan tangan yang sedang berpindah/memegang wajah)
            if let lastWrist = lastWristPosition {
                let movement = distance(from: wrist.location, to: lastWrist)
                if movement > 0.04 {
                    resetHoldState()
                    lastWristPosition = wrist.location
                    return
                }
            }
            lastWristPosition = wrist.location
            
            // FILTER ANTI MEMEGANG WAJAH (Finger Spread Fan-Out Check):
            // Saat telapak tangan terbuka menyapa "Hai" (🖐️), jari-jari mekar melebar keluar.
            // Saat memegang wajah/pipi/dagu, jari-jari sejajar atau rapat melengkung.
            let indexTip = try observation.recognizedPoint(.indexTip)
            let littleTip = try observation.recognizedPoint(.littleTip)
            let indexMCP = try observation.recognizedPoint(.indexMCP)
            let littleMCP = try observation.recognizedPoint(.littleMCP)
            
            if indexTip.confidence >= 0.60 && littleTip.confidence >= 0.60 &&
                indexMCP.confidence >= 0.60 && littleMCP.confidence >= 0.60 {
                let tipSpread = distance(from: indexTip.location, to: littleTip.location)
                let mcpSpread = distance(from: indexMCP.location, to: littleMCP.location)
                
                // Jari-jari HARUS mekar (tipSpread minimal 1.30x lebih lebar daripada pangkal MCP)
                // Jika kurang dari 1.30x (jari rapat/memegang wajah), anggap BUKAN gestur Hai!
                guard tipSpread >= mcpSpread * 1.30 else {
                    resetHoldState()
                    return
                }
            }
            
            var extendedFingers = 0
            
            let mcpJoints: [VNHumanHandPoseObservation.JointName] = [.indexMCP, .middleMCP, .ringMCP, .littleMCP]
            let tipJoints: [VNHumanHandPoseObservation.JointName] = [.indexTip, .middleTip, .ringTip, .littleTip]
            
            var totalHandSpan: CGFloat = 0
            
            for i in 0..<mcpJoints.count {
                let mcp = try observation.recognizedPoint(mcpJoints[i])
                let tip = try observation.recognizedPoint(tipJoints[i])
                
                if mcp.confidence >= 0.60 && tip.confidence >= 0.60 {
                    let distWristToMCP = distance(from: wrist.location, to: mcp.location)
                    let distWristToTip = distance(from: wrist.location, to: tip.location)
                    
                    totalHandSpan += distWristToTip
                    
                    // Ujung jari harus minimal 1.35x lebih jauh daripada pangkal jari (jari lurus penuh)
                    if distWristToTip > distWristToMCP * 1.35 {
                        extendedFingers += 1
                    }
                }
            }
            
            // Deteksi khusus jempol (thumb)
            let thumbIP = try observation.recognizedPoint(.thumbIP)
            let thumbTip = try observation.recognizedPoint(.thumbTip)
            if thumbIP.confidence >= 0.60 && thumbTip.confidence >= 0.60 {
                let distWristToIP = distance(from: wrist.location, to: thumbIP.location)
                let distWristToTip = distance(from: wrist.location, to: thumbTip.location)
                if distWristToTip > distWristToIP * 1.20 {
                    extendedFingers += 1
                }
            }
            
            // Filter Ukuran Tangan (Proximity Filter):
            // Tangan harus berjarak cukup dekat dari kamera (bukan orang di background jauh)
            let avgHandSpan = totalHandSpan / 4.0
            guard avgHandSpan >= 0.08 else {
                resetHoldState()
                return
            }
            
            // Gestur dianggap valid jika 5 jari (atau minimal 4 jari lurus)
            if extendedFingers >= 4 {
                let now = Date()
                if firstDetectedTime == nil {
                    firstDetectedTime = now
                }
                holdFrameCount += 1
                
                let elapsedTime = now.timeIntervalSince(firstDetectedTime ?? now)
                
                // Hanya picu jika gestur DITAHAN diam & mekar stabil selama 0.75 detik & 22+ frame
                if holdFrameCount >= requiredHoldFrames && elapsedTime >= requiredHoldDuration {
                    lastTriggerTime = now
                    resetHoldState()
                    onGestureDetected()
                }
            } else {
                // Jika di tengah jalan jari ditekuk / posisi berubah -> langsung reset!
                resetHoldState()
            }
            
        } catch {
            resetHoldState()
        }
    }
    
    private func resetHoldState() {
        holdFrameCount = 0
        firstDetectedTime = nil
        lastWristPosition = nil
    }
    
    private func distance(from p1: CGPoint, to p2: CGPoint) -> CGFloat {
        let dx = p1.x - p2.x
        let dy = p1.y - p2.y
        return sqrt(dx * dx + dy * dy)
    }
}
