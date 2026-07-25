// Tokens.swift
// HaispaceBooths — App/DesignSystem
//
// Single Source of Truth untuk Token Visual, Tipografi, Spacing, dan Animasi.
// Ref: Lead Apple UI/UX Review (Target 9.9 - 10 / Apple Store Demo Grade)

import SwiftUI

// MARK: - Color Tokens (Surfaces & Brand)

public enum AppTheme {
    public enum Surface {
        /// Dark background utama platform #161616
        public static let background = Color(hex: "#161616")
        /// Kartu level 1 (card, container) #222222
        public static let primary = Color(hex: "#222222")
        /// Kartu level 2 (unselected state, input background) #1C1C1C
        public static let secondary = Color(hex: "#1C1C1C")
        /// Kartu level 3 (highlighted card) #2A2A2A
        public static let tertiary = Color(hex: "#2A2A2A")
    }

    public enum Brand {
        /// Warna aksen emas utama Haispace #F5A623
        public static let gold = Color(hex: "#F5A623")
        /// Teks utama murni putih
        public static let textPrimary = Color.white
        /// Teks sekunder dengan opacity 60%
        public static let textSecondary = Color.white.opacity(0.6)
        /// Teks tersier dengan opacity 35%
        public static let textMuted = Color.white.opacity(0.35)
        /// Dark text untuk kontras tinggi di atas tombol putih #111111
        public static let textDark = Color(hex: "#111111")
    }
}

// MARK: - Spacing Tokens (Apple Standard Scale)

public enum Spacing {
    /// 4pt
    public static let xs: CGFloat = 4
    /// 8pt
    public static let sm: CGFloat = 8
    /// 12pt
    public static let md: CGFloat = 12
    /// 16pt
    public static let lg: CGFloat = 16
    /// 24pt
    public static let xl: CGFloat = 24
    /// 32pt
    public static let xxl: CGFloat = 32
    /// 48pt (Standard Section Inset)
    public static let section: CGFloat = 48
}

// MARK: - Typography Scale (Apple HIG 6-Tier Hierarchy)

public enum AppFont {
    /// Large Display Title (26pt Bold Rounded)
    public static let largeTitle = Font.system(size: 26, weight: .bold, design: .rounded)
    /// Title Header (22pt Bold Rounded)
    public static let title = Font.system(size: 22, weight: .bold, design: .rounded)
    /// Section Headline (18pt Bold Rounded)
    public static let headline = Font.system(size: 18, weight: .bold, design: .rounded)
    /// Standard Body (15pt Medium)
    public static let body = Font.system(size: 15, weight: .medium, design: .default)
    /// Footnote & Helper (13pt Regular)
    public static let footnote = Font.system(size: 13, weight: .regular, design: .default)
    /// Micro Caption & Tracking (11pt Bold Rounded)
    public static let caption = Font.system(size: 11, weight: .bold, design: .rounded)
}

// MARK: - Motion System (Unified Apple Spring Animations)

public enum Motion {
    /// Animasi perpindahan antar layar (Spring Response 0.35s, Damping 0.82)
    public static let screen = Animation.spring(response: 0.35, dampingFraction: 0.82)
    /// Animasi interaksi tombol (EaseInOut 0.15s)
    public static let button = Animation.easeInOut(duration: 0.15)
    /// Animasi thumbnail pop (Spring Response 0.28s, Damping 0.72)
    public static let thumbnail = Animation.spring(response: 0.28, dampingFraction: 0.72)
}

// MARK: - Color Hex Initializer Helper

extension Color {
    public init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
