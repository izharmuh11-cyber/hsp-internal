// PoseIntelligenceService.swift
// HaispaceBooths — Services/AI
//
// Layanan yang menggunakan Apple Vision Framework untuk mendeteksi
// wajah secara periodik dan merekomendasikan pose serta zoom.
// Berjalan di Neural Engine (ANE) sehingga efisien baterai.
//
// Ref: docs/design/35_pose_guide_ai.md

import Foundation
import Vision
import CoreVideo
import OSLog

/// Kategori Pose berdasarkan jumlah orang
enum PoseCategory: String, CaseIterable {
    case solo = "Solo"
    case couple = "Couple"
    case group = "Group"
    case waiting = "Menunggu..."
}

/// Rekomendasi Zoom
enum ZoomRecommendation: Double {
    case ultrawide = 0.5
    case wide = 1.0
    case telephoto = 2.0
    
    var description: String {
        switch self {
        case .ultrawide: return "0.5x (Ultrawide)"
        case .wide: return "1.0x (Wide)"
        case .telephoto: return "2.0x (Portrait)"
        }
    }
}

final class PoseIntelligenceService: @unchecked Sendable {
    
    static let shared = PoseIntelligenceService()
    
    private let faceRequest = VNDetectFaceRectanglesRequest()
    private var isAnalyzing = false
    
    // Throttle untuk mencegah analisis setiap frame
    private var lastAnalysisTime: Date = .distantPast
    private let analysisInterval: TimeInterval = 2.0 // Analisis setiap 2 detik
    
    private init() {}
    
    /// Menganalisis CVPixelBuffer dari feed kamera (dipanggil oleh FrameCompositor atau StreamDecoder)
    func analyzeFrame(pixelBuffer: CVPixelBuffer, completion: @escaping (Int, PoseCategory, ZoomRecommendation?) -> Void) {
        let now = Date()
        guard !isAnalyzing, now.timeIntervalSince(lastAnalysisTime) > analysisInterval else {
            return
        }
        
        isAnalyzing = true
        lastAnalysisTime = now
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        Task.detached(priority: .userInitiated) {
            do {
                try handler.perform([self.faceRequest])
                let count = self.faceRequest.results?.count ?? 0
                
                let category: PoseCategory
                let zoom: ZoomRecommendation?
                
                switch count {
                case 0:
                    category = .waiting
                    zoom = .wide
                case 1:
                    category = .solo
                    zoom = .telephoto
                case 2:
                    category = .couple
                    zoom = .wide
                case 3, 4:
                    category = .group
                    zoom = .wide
                default:
                    // 5+ orang
                    category = .group
                    zoom = .ultrawide
                }
                
                await MainActor.run {
                    self.isAnalyzing = false
                    completion(count, category, zoom)
                }
            } catch {
                HaispaceLogger.error("Vision AI Error: \(error)", category: "ai")
                await MainActor.run {
                    self.isAnalyzing = false
                    completion(0, .waiting, nil)
                }
            }
        }
    }
}
