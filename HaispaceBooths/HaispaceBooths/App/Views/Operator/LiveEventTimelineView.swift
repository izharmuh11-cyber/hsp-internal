// LiveEventTimelineView.swift
// HaispaceBooths — App/Views/Operator
//
// Debug overlay untuk menampilkan workflow event timeline secara live.
// Sesuai dengan "Phase 1: State Machine & Health Contract" untuk memudahkan
// observabilitas tanpa harus membaca log file mentah.

import SwiftUI

struct LiveEventTimelineView: View {
    @Environment(AppState.self) private var appState
    
    // Auto-scroll to bottom
    @Namespace private var bottomID

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Live Session Timeline")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                
                Spacer()
                
                if let sessionId = appState.currentSession?.sessionId {
                    Text(sessionId.prefix(8))
                        .font(.caption2.monospaced())
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.8))
            
            // Content
            ScrollView {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 6) {
                        let events = activeEvents()
                        
                        if events.isEmpty {
                            Text("Waiting for events...")
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .padding()
                        } else {
                            ForEach(events, id: \.id) { event in
                                EventRowView(event: event)
                            }
                        }
                        
                        // Anchor for auto-scroll
                        Color.clear
                            .frame(height: 1)
                            .id(bottomID)
                    }
                    .padding(12)
                    .onChange(of: activeEvents().count) { _, _ in
                        withAnimation {
                            proxy.scrollTo(bottomID, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color.black.opacity(0.6))
        }
        .frame(width: 320, height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func activeEvents() -> [AuditEvent] {
        guard let sessionId = appState.currentSession?.sessionId,
              let record = SessionAuditTrail.read(sessionId: sessionId) else {
            return []
        }
        return record.events
    }
}

// MARK: - EventRowView

private struct EventRowView: View {
    let event: AuditEvent
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(timeString(event.timestamp))
                .font(.caption2.monospacedDigit())
                .foregroundColor(.gray)
            
            statusIcon(for: event.type)
                .font(.caption2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.description)
                    .font(.caption)
                    .foregroundColor(.white)
                
                if let details = event.metadata?["details"] as? String {
                    Text(details)
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
        }
    }
    
    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    
    @ViewBuilder
    private func statusIcon(for type: AuditEventType) -> some View {
        switch type {
        case .stageChanged:
            Image(systemName: "arrow.right.circle.fill").foregroundColor(.blue)
        case .actionTriggered:
            Image(systemName: "bolt.fill").foregroundColor(.yellow)
        case .errorOccurred:
            Image(systemName: "xmark.circle.fill").foregroundColor(.red)
        case .capabilityResult:
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        default:
            Image(systemName: "circle.fill").foregroundColor(.gray)
        }
    }
}
