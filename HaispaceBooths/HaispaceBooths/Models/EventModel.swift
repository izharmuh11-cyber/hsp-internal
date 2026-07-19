// EventModel.swift
// HaispaceBooths — Models
//
// Model data untuk mengelola Event/Job lokasi photobooth.
// Mengatur nama event, lokasi, tarif, bingkai khusus, tone filter, dan tracking statistik.

import Foundation

struct EventModel: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var location: String
    var pricePerSession: Double
    var isPayPerSession: Bool
    var totalSessions: Int
    var totalRevenue: Double
    var iconName: String
    var themeColorHex: String
    var selectedFrameName: String
    var selectedFilterName: String
    
    init(
        id: String = UUID().uuidString,
        name: String,
        location: String,
        pricePerSession: Double = 25000,
        isPayPerSession: Bool = true,
        totalSessions: Int = 0,
        totalRevenue: Double = 0,
        iconName: String = "mappin.circle.fill",
        themeColorHex: String = "#7C5CFC",
        selectedFrameName: String = "Strip 3-Pose Standard",
        selectedFilterName: String = "Cinematic Warm"
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.pricePerSession = pricePerSession
        self.isPayPerSession = isPayPerSession
        self.totalSessions = totalSessions
        self.totalRevenue = totalRevenue
        self.iconName = iconName
        self.themeColorHex = themeColorHex
        self.selectedFrameName = selectedFrameName
        self.selectedFilterName = selectedFilterName
    }
    
    // Preset sampel event untuk dev & testing
    static let samples: [EventModel] = [
        EventModel(
            id: "evt-ung",
            name: "Wisuda UNG 2026",
            location: "Auditorium UNG",
            pricePerSession: 25000,
            isPayPerSession: true,
            totalSessions: 48,
            totalRevenue: 1200000,
            iconName: "academiccap.fill",
            themeColorHex: "#3B82F6",
            selectedFrameName: "Graduation Strip 3-Pose",
            selectedFilterName: "Cinematic Warm"
        ),
        EventModel(
            id: "evt-pantai",
            name: "Pop-Up Pantai Indah",
            location: "Kawasan Pantai",
            pricePerSession: 30000,
            isPayPerSession: true,
            totalSessions: 85,
            totalRevenue: 2550000,
            iconName: "sun.max.fill",
            themeColorHex: "#F59E0B",
            selectedFrameName: "Summer Grid 4-Pose",
            selectedFilterName: "Vibrant Summer"
        ),
        EventModel(
            id: "evt-city",
            name: "Night Market Bundaran",
            location: "Bundaran Kota",
            pricePerSession: 20000,
            isPayPerSession: true,
            totalSessions: 110,
            totalRevenue: 2200000,
            iconName: "building.2.fill",
            themeColorHex: "#10B981",
            selectedFrameName: "Modern Minimalist 4-Pose",
            selectedFilterName: "Moody Black & White"
        ),
        EventModel(
            id: "evt-ultah",
            name: "Ultah Sarah 17th",
            location: "House of Sarah",
            pricePerSession: 0,
            isPayPerSession: false,
            totalSessions: 32,
            totalRevenue: 0,
            iconName: "gift.fill",
            themeColorHex: "#EC4899",
            selectedFrameName: "Birthday Party Card 2-Pose",
            selectedFilterName: "Soft Pastel Pink"
        )
    ]
}
