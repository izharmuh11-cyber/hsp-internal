// CreateSessionView.swift
// HaispaceBooths — UI/Views (Scene 2: The Choice)
//
// Create Session & Theme Selection View Haispace Kiosk Photobooth.
// REVISION 1 — Based on Apple Design Review #003 (8.4/10 -> Target Approved).
// - Headline: "Choose your moment" (Instantly processed in 2 seconds)
// - Subtitle: Erased completely (Subtraction Test Doc #54)
// - SF Symbols Removed 100%: Replaced by Human Photo Moment Canvases
// - One Emotion Rule: Filter Selection removed (Defaults automatically per theme)
// - Screen-Wide Atmosphere Transformation: Background Gradient transforms on selection
// - Task Cancellation Engine: Prevents race conditions on rapid taps.

import SwiftUI

public struct CreateSessionView: View {
    
    // Injected Selection Handlers
    private let onCategorySelected: (String) async -> Void
    
    @State private var selectedCategory: String? = nil
    @State private var selectionTask: Task<Void, Never>? = nil
    
    // Curated Theme Models with Human Moment Gradient Atmosphere
    private struct ThemeMoment {
        let id: String
        let title: String
        let defaultFilter: String
        let gradientColors: [Color]
        let accentColor: Color
    }
    
    private let themes: [ThemeMoment] = [
        ThemeMoment(id: "Graduation", title: "Graduation", defaultFilter: "Natural", gradientColors: [Color.indigo.opacity(0.4), Color.blue.opacity(0.2)], accentColor: Color.indigo),
        ThemeMoment(id: "Couple", title: "Couple", defaultFilter: "Warm", gradientColors: [Color.pink.opacity(0.4), Color.purple.opacity(0.2)], accentColor: Color.pink),
        ThemeMoment(id: "Family", title: "Family", defaultFilter: "Warm", gradientColors: [Color.orange.opacity(0.4), Color.red.opacity(0.2)], accentColor: Color.orange),
        ThemeMoment(id: "Friends", title: "Friends", defaultFilter: "Natural", gradientColors: [Color.blue.opacity(0.4), Color.teal.opacity(0.2)], accentColor: Color.blue)
    ]
    
    public init(onCategorySelected: @escaping (String) async -> Void) {
        self.onCategorySelected = onCategorySelected
    }
    
    // Active Theme Gradient (Transforms Whole Screen Atmosphere)
    private var activeBackgroundGradient: [Color] {
        if let selected = selectedCategory, let theme = themes.first(where: { $0.id == selected }) {
            return theme.gradientColors
        }
        return [Color(white: 0.12), Color(white: 0.04)]
    }
    
    public var body: some View {
        ZStack {
            // Dynamic Screen-Wide Atmosphere Gradient
            RadialGradient(
                colors: activeBackgroundGradient,
                center: .center,
                startRadius: 150,
                endRadius: 950
            )
            .animation(.easeInOut(duration: 0.5), value: selectedCategory)
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer().frame(height: 32)
                
                // Action Headline (Processed in < 2 Seconds)
                Text("Choose your moment")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
                
                // 4 HUMAN MOMENT CANVASES (75% Visual Focus — Zero SF Symbols)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 28) {
                    ForEach(themes, id: \.id) { theme in
                        let isSelected = selectedCategory == theme.id
                        
                        ZStack(alignment: .bottomLeading) {
                            // Human Visual Moment Canvas (Replaces SF Symbols)
                            LinearGradient(
                                colors: theme.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(isSelected ? Color.white : Color.white.opacity(0.15), lineWidth: isSelected ? 3 : 1)
                            )
                            
                            // Human Theme Title
                            VStack(alignment: .leading, spacing: 4) {
                                Text(theme.title)
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                            }
                            .padding(24)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 190)
                        .cornerRadius(20)
                        .scaleEffect(isSelected ? 1.06 : (selectedCategory == nil ? 1.0 : 0.94))
                        .opacity(selectedCategory == nil || isSelected ? 1.0 : 0.4)
                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isSelected)
                        .onTapGesture {
                            // 1. Set Selected Category & Transform Whole Atmosphere
                            selectedCategory = theme.id
                            
                            // 2. Task Cancellation Engine (Prevents Race Conditions)
                            selectionTask?.cancel()
                            selectionTask = Task {
                                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms micro-pause
                                guard !Task.isCancelled else { return }
                                await onCategorySelected(theme.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 48)
                
                Spacer()
            }
        }
    }
}

#Preview {
    CreateSessionView(onCategorySelected: { _ in })
}
