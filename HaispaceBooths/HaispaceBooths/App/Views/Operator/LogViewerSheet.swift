// LogViewerSheet.swift
// HaispaceBooths — App/Views/Operator
//
// Layar modal untuk melihat, menyalin, dan membagikan log sistem.

import SwiftUI

struct LogViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logContent = ""
    @State private var isShowingToast = false

    // Token dibaca/ditulis dari Keychain — input sekali, tidak perlu ulangi
    @State private var githubPAT = ""
    @State private var isTokenSaved = false
    @State private var isUploading = false
    @State private var lastUploadURL: String? = nil   // URL raw file setelah upload sukses
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

                    // Panel Token + Upload
                    VStack(alignment: .leading, spacing: 10) {
                        Text("KIRIM LOG OTOMATIS KE GITHUB")
                            .font(.caption.bold())
                            .foregroundStyle(.white.opacity(0.5))

                        // Input token (hanya perlu diisi sekali — disimpan di Keychain)
                        HStack(spacing: 8) {
                            SecureField("GitHub Personal Access Token (PAT)", text: $githubPAT)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                                .foregroundStyle(.white)
                                .font(.system(size: 13, design: .monospaced))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)

                            Button {
                                GitHubLogUploader.saveToken(githubPAT)
                                withAnimation { isTokenSaved = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    withAnimation { isTokenSaved = false }
                                }
                            } label: {
                                Label(isTokenSaved ? "Tersimpan" : "Simpan",
                                      systemImage: isTokenSaved ? "checkmark.circle.fill" : "key.fill")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(isTokenSaved ? Color.green : Color.blue)
                                    .foregroundStyle(.white)
                                    .cornerRadius(8)
                            }
                            .disabled(githubPAT.count < 10)
                        }

                        if isTokenSaved {
                            Text("✅ Token disimpan di Keychain — tidak perlu input ulang")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        } else if KeychainHelper.getGitHubPAT() != nil {
                            Text("🔑 Token sudah tersimpan di Keychain")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.5))
                        }

                        // Tombol Upload
                        Button {
                            uploadLog()
                        } label: {
                            if isUploading {
                                ProgressView().tint(.white).frame(maxWidth: .infinity)
                            } else {
                                Label("Unggah Log ke GitHub", systemImage: "arrow.up.circle.fill")
                                    .font(.caption.bold())
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.vertical, 10)
                        .background(GitHubLogUploader.resolvedToken() == nil ? Color.gray.opacity(0.3) : Color.indigo)
                        .foregroundStyle(.white)
                        .cornerRadius(8)
                        .disabled(GitHubLogUploader.resolvedToken() == nil || isUploading)

                        // URL hasil upload — langsung copy dan kirim ke AI
                        if let url = lastUploadURL {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("📎 URL Log (bagikan ke AI untuk dibaca langsung):")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white.opacity(0.6))
                                HStack {
                                    Text(url)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.cyan)
                                        .lineLimit(2)
                                    Spacer()
                                    Button {
                                        UIPasteboard.general.string = url
                                    } label: {
                                        Image(systemName: "doc.on.doc.fill")
                                            .foregroundStyle(.cyan)
                                    }
                                }
                                .padding(8)
                                .background(Color.cyan.opacity(0.1))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // Tombol Aksi Utama
                    HStack(spacing: 16) {
                        Button {
                            UIPasteboard.general.string = logContent
                            withAnimation(.spring) { isShowingToast = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation { isShowingToast = false }
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
                                Text("Bagikan Log")
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
                        lastUploadURL = nil
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup") { dismiss() }
                }
            }
            .onAppear {
                logContent = LocalLogWriter.readLogContent()
                // Load token dari Keychain jika sudah ada
                if let stored = KeychainHelper.getGitHubPAT() {
                    githubPAT = stored
                }
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
            .alert("Unggah Log", isPresented: $showUploadAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(uploadMessage)
            }
        }
    }

    private func uploadLog() {
        isUploading = true
        lastUploadURL = nil
        GitHubLogUploader.uploadLatestLog(eventName: "manual_upload") { url in
            isUploading = false
            if let url = url {
                lastUploadURL = url
                // Otomatis copy URL ke clipboard
                UIPasteboard.general.string = url
            } else {
                uploadMessage = "Gagal upload. Pastikan token valid dan koneksi internet tersedia."
                showUploadAlert = true
            }
        }
    }
}
