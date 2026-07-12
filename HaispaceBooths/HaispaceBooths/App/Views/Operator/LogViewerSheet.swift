// LogViewerSheet.swift
// HaispaceBooths — App/Views/Operator
//
// Layar modal untuk melihat, menyalin, dan membagikan log sistem.

import SwiftUI

struct LogViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logContent = ""
    
    var body: some View {
        NavigationStack {
            VStack {
                if logContent.isEmpty {
                    Text("Log kosong atau tidak dapat dimuat.")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        Text(logContent)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }
            }
            .navigationTitle("Log Sistem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Hapus Log", role: .destructive) {
                        LocalLogWriter.clearLog()
                        logContent = ""
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            UIPasteboard.general.string = logContent
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        
                        ShareLink(item: logContent) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                logContent = LocalLogWriter.readLogContent()
            }
        }
    }
}
