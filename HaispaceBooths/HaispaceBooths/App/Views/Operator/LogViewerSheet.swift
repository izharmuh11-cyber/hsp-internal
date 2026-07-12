// LogViewerSheet.swift
// HaispaceBooths — App/Views/Operator
//
// Layar modal untuk melihat, menyalin, dan membagikan log sistem.

import SwiftUI

struct LogViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logContent = ""
    @State private var isShowingToast = false
    
    // Konfigurasi Auto-Upload GitHub
    @AppStorage("github_pat") private var githubPAT = ""
    @State private var isUploading = false
    @State private var uploadMessage = ""
    @State private var showUploadAlert = false
    
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
                    
                    // Panel Unggah ke GitHub (Sangat Praktis & Aman via Token Lokal)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("KIRIM LOG OTOMATIS KE GITHUB")
                            .font(.caption.bold())
                            .foregroundStyle(.white.opacity(0.5))
                        
                        HStack(spacing: 8) {
                            SecureField("Masukkan GitHub Personal Access Token (PAT)", text: $githubPAT)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                                .foregroundStyle(.white)
                                .font(.system(size: 13, design: .monospaced))
                            
                            Button {
                                uploadLogToGitHub()
                            } label: {
                                if isUploading {
                                    ProgressView()
                                        .tint(.white)
                                        .frame(width: 90)
                                } else {
                                    Text("Unggah Log")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(githubPAT.isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                                        .foregroundStyle(.white)
                                        .cornerRadius(8)
                                }
                            }
                            .disabled(githubPAT.isEmpty || isUploading)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Tombol Aksi Utama yang Sangat Jelas di Bagian Bawah
                    HStack(spacing: 16) {
                        Button {
                            UIPasteboard.general.string = logContent
                            withAnimation(.spring) {
                                isShowingToast = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation {
                                    isShowingToast = false
                                }
                            }
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
            .overlay {
                if isShowingToast {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.green)
                        
                        Text("Log Berhasil Disalin")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .shadow(color: .black.opacity(0.3), radius: 10)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .alert("Unggah Log ke GitHub", isPresented: $showUploadAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(uploadMessage)
            }
        }
    }
    
    private func uploadLogToGitHub() {
        guard !githubPAT.isEmpty else { return }
        isUploading = true
        uploadMessage = ""
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let filename = "ipad-log-\(timestamp).txt"
        
        let url = URL(string: "https://api.github.com/repos/izharmuh11-cyber/hsp-internal/contents/logs/\(filename)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(githubPAT)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let base64Content = Data(logContent.utf8).base64EncodedString()
        let body: [String: Any] = [
            "message": "Upload log from iPad at \(timestamp)",
            "content": base64Content,
            "branch": "main"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isUploading = false
                if let error = error {
                    uploadMessage = "Gagal mengunggah: \(error.localizedDescription)"
                    showUploadAlert = true
                    return
                }
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                        uploadMessage = "Log sukses diunggah ke GitHub di folder logs/\(filename). Klik sync/pull pada workspace kamu untuk membacanya langsung!"
                    } else {
                        let responseString = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Tidak ada respons"
                        uploadMessage = "Gagal (HTTP \(httpResponse.statusCode)):\n\(responseString)"
                    }
                } else {
                    uploadMessage = "Respons server tidak dikenal."
                }
                showUploadAlert = true
            }
        }.resume()
    }
}
