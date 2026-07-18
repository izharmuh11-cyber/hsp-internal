# Haispace Booths & Camera — AI Agent Rules

## 🔄 Interaction & Deployment Workflow

All AI agents working on this project must strictly adhere to the following workflow when interacting with the operator:

1. **Problem Analysis (Analisis Masalah):**
   * Before writing code or making modifications, explain the issue or target feature to the operator.
   * Clarify where the problem lies in the codebase and its impact.

2. **Recommendations & Solutions (Saran & Solusi):**
   * Provide a clear recommendation or alternative options to solve the issue.
   * Discuss technical tradeoffs if any (e.g., performance, security, complexity).

3. **Strict Git Push Authorization:**
   * **Automatic Push for Bug/Compile Fixes:** The agent is authorized to automatically push commits for the purpose of fixing compilation issues, resolving bugs, or CI/CD troubleshooting to ensure build success.
   * **Explicit Authorization for Features:** For new features, architectural changes, or strategic proposals or asking, `git push` is **strictly prohibited** until the operator explicitly requests or authorizes it (e.g., *"silahkan push"*, *"oke push"*).

4. **Confidentiality of Design Docs:**
   * Do not remove `docs/design/` from `.gitignore`. Internal design strategy documents must remain local-only.

## 📌 Status Pengembangan Terakhir & Log Build (Per 18 Juli 2026)

Semua agen AI selanjutnya wajib membaca riwayat build ini sebelum melanjutkan pekerjaan perbaikan kamera Portrait pada iPhone 14:

### 1. Riwayat Eksperimen Build & Penyebab Crash
* **Build #170 - #173 (Gagal Compile):** Error sintaksis pada Swift try-catch wrapper dan ketiadaan properti `supportedPhotoQualityPrioritizations` pada `AVCapturePhotoOutput`.
* **Build #174 (Crash Watchdog - 16 detik):** Terjadi circular wait deadlock (Swift Concurrency) antara `MainActor` dan `PhotoTransferService` actor, memicu pembekuan main thread selama 16 detik hingga Watchdog iOS mematikan paksa aplikasi.
* **Build #175 (Crash Instan saat Capture):** Deadlock selesai dengan memindahkan transfer foto ke `Task.detached`. Namun terjadi crash instan baru karena inisialisasi default `AVCapturePhotoSettings()` menghasilkan format uncompressed (TIFF/RAW) yang tidak mendukung embedding depth data metadata.
* **Build #176 (Crash Instan saat Capture):** Memaksa inisialisasi settings dengan format terkompresi `.hevc` atau `.jpeg`. Tetap crash karena bentrokan bandwidth hardware dual-camera iPhone 14 akibat streaming depth via `AVCaptureDepthDataOutput` (dengan synchronizer) berjalan bersamaan dengan capture depth pada `AVCapturePhotoOutput`.
* **Build #177 - #178 (Gagal Compile):** Percobaan mematikan synchronizer sementara saat capture, namun gagal compile karena salah argumen `queue:` (seharusnya `callbackQueue:` pada setDelegate depthOutput).
* **Build #179 (Crash Instan saat Capture):** Error compile teratasi, namun masih crash karena walaupun synchronizer dilepas, `depthOutput` tetap aktif mengalirkan frame depth di latar belakang.
* **Build #180 (Migrasi Penuh ke Asynchronous Caching):** 
  * Membuang `AVCaptureDataOutputSynchronizer` secara total.
  * `depthOutput` dan `videoOutput` berjalan asinkron. Data depth disimpan ke cache memori `lastDepthImage` secara berkala, lalu video delegate mengambil cache tersebut untuk merender bokeh secara independen.
  * **Pencegahan Crash:** Sesaat sebelum jepret (`capturePhoto`), kita menonaktifkan seluruh koneksi `depthOutput` (`connection.isEnabled = false`) untuk membebaskan 100% bandwidth sensor. Koneksi dihidupkan kembali (`connection.isEnabled = true`) di dalam callback delegate `didFinishProcessingPhoto`.

### 2. Langkah Pengujian Berikutnya untuk Agen Baru:
1. Tanyakan kepada operator apakah **Build #180** yang baru saja di-push dapat berjalan dengan sukses dan berhasil mengambil foto Portrait tanpa crash.
2. Jika sukses, masalah crash mode portrait telah terselesaikan 100% melalui arsitektur Asynchronous Caching baru ini.
