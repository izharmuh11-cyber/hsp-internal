// SessionFeedbackService.swift
// HaispaceBooths — Services/Utility
//
// Layanan modular untuk feedback audio & haptic selama sesi foto.
// Menghindari bentrokan namespace UI dan dependensi C-APIs di file view SwiftUI.
//

import UIKit
import AudioToolbox

class SessionFeedbackService {
    static let shared = SessionFeedbackService()
    
    private init() {}
    
    /// Memutar suara beep pendek untuk hitung mundur (System Sound 1057)
    func playCountdownTick() {
        AudioServicesPlaySystemSound(SystemSoundID(1057))
    }
    
    /// Memutar suara shutter click klasik (System Sound 1108)
    func playShutterClick() {
        AudioServicesPlaySystemSound(SystemSoundID(1108))
    }
    
    /// Memicu feedback getaran haptic sesuai tingkatan
    func triggerHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        // Jalankan di MainActor karena UIImpactFeedbackGenerator membutuhkan thread utama
        DispatchQueue.main.async {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            generator.impactOccurred()
        }
    }
}
