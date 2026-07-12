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
            VStack(spacing: 16) {
                if logContent.isEmpty {
                    Spacer()
                    Text("Log kosong atau tidak dapat dimuat.")
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ScrollView {
                        Text(logContent)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Tombol Aksi Utama yang Sangat Jelas di Bagian Bawah
                    HStack(spacing: 16) {
                        Button {
                            UIPasteboard.general.string = logContent
                        } label: {
                            HStack {
                                Image(systemName: "doc.on.doc.fill")
                                Text("Salin Log")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.blue.opacity(0.2))
                            .foregroundStyle(.blue)
                            .cornerRadius(12)
                        }
                        
                        ShareLink(item: logContent) {
                            HStack {
                                Image(systemName: "square.and.arrow.up.fill")
                                Text("Bagikan Log (Teks)")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.green.opacity(0.2))
                            .foregroundStyle(.green)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)
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
