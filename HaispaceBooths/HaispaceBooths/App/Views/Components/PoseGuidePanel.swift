// PoseGuidePanel.swift
// HaispaceBooths — App/Views/Components
//
// Panel pintar di sisi layar yang menampilkan rekomendasi pose ("Living Pose Cards").
// Berupa video pendek yang berulang tanpa henti (loop) menggunakan AVPlayerLooper.
// Kategori video otomatis berubah berdasarkan AI Face Detection.
//
// Ref: docs/design/35_pose_guide_ai.md

import SwiftUI
import AVKit

struct PoseGuidePanel: View {
    let category: PoseCategory
    let faceCount: Int
    
    // Mock Data Video Poses
    private var videoNames: [String] {
        switch category {
        case .solo: return ["pose_solo_1", "pose_solo_2"]
        case .couple: return ["pose_couple_1", "pose_couple_2"]
        case .group: return ["pose_group_1", "pose_group_2"]
        case .waiting: return []
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header Info
            HStack {
                Image(systemName: "face.dashed")
                    .foregroundStyle(Color(hex: "#F5A623"))
                Text("\(faceCount) Wajah (\(category.rawValue))")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.5))
            .cornerRadius(12)
            
            // Living Pose Cards
            if category == .waiting {
                VStack {
                    Image(systemName: "person.crop.rectangle.badge.plus")
                        .font(.largeTitle)
                        .foregroundStyle(.gray)
                    Text("Masuk ke dalam frame...")
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .padding(.top, 8)
                }
                .frame(width: 200, height: 300)
                .background(Color.white.opacity(0.05))
                .cornerRadius(16)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        ForEach(videoNames, id: \.self) { videoName in
                            LivingPoseCard(videoName: videoName)
                        }
                    }
                }
                .frame(width: 200)
            }
        }
        .padding()
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .colorScheme(.dark)
                .overlay(
                    HStack {
                        Rectangle()
                            .fill(LinearGradient(colors: [.white.opacity(0.15), .clear], startPoint: .top, endPoint: .bottom))
                            .frame(width: 1)
                        Spacer()
                    }
                )
                .ignoresSafeArea()
        )
    }
}

// MARK: - Living Pose Card (Video Looper)

struct LivingPoseCard: View {
    let videoName: String
    
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    
    var body: some View {
        ZStack {
            Color.black
            
            if let player = player {
                VideoPlayer(player: player)
                    .disabled(true) // Disable controls
            } else {
                ProgressView()
            }
        }
        .frame(width: 200, height: 300)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
        }
    }
    
    private func setupPlayer() {
        // Mock: Jika video .mov tidak ada di bundle, kita pakai fallback
        // Di prod, ini akan load dari Documents/poses/
        guard let url = Bundle.main.url(forResource: videoName, withExtension: "mov") else {
            return
        }
        
        let item = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer(items: [item])
        queuePlayer.isMuted = true
        
        self.looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        self.player = queuePlayer
        
        queuePlayer.play()
    }
}

#Preview {
    HStack {
        Spacer()
        PoseGuidePanel(category: .group, faceCount: 3)
    }
    .background(Color.gray)
}
