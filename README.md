# HaiBooth — Apple Native Photobooth System

![HaiBooth Cover](https://via.placeholder.com/1200x400/1A1A24/FFFFFF?text=HAIBOOTH+SYSTEM+—+APPLE+NATIVE)

HaiBooth adalah sistem *photobooth* canggih, **Native First**, dan dirancang khusus untuk ekosistem Apple. Arsitekturnya memisahkan peran kamera (iPhone) dan peran kios tamu (iPad) yang berkomunikasi secara terenkripsi *(P2P)* tanpa membutuhkan jaringan internet aktif *(Offline Always)*.

---

## 🌟 Fitur Utama (Rekapitulasi Fase 1 - 5)

Proyek ini telah dikembangkan secara bertahap melalui 5 fase krusial:

1. **Fase 1: P2P Network & Kamera Engine**
   - Menggunakan `MultipeerConnectivity` dengan enkripsi TLS 1.2 untuk komunikasi *seamless* antara iPhone (Camera App) dan iPad (Kiosk App).
   - *Engine* kamera memanfaatkan `AVCaptureSession` dengan dukungan resolusi tinggi 12MP Apple ProRAW dan *shutter* asinkron tanpa nge-*lag*.

2. **Fase 2: Alur Kiosk Tamu & Desain UI iPad**
   - Layar sentuh *Kiosk* di iPad (dibangun menggunakan SwiftUI) yang menuntun tamu secara *step-by-step*: Pendaftaran ➔ Pemilihan Paket ➔ Sesi Foto Aktif ➔ Pemilihan Foto ➔ Pembayaran.
   - Menggunakan *macOS-inspired frosted glass UI* untuk kesan mewah dan responsif.

3. **Fase 3: Mission Control & Database Operator**
   - **Mission Control**: Dashboard rahasia bergaya *Control Center* Apple yang dapat diakses operator melalui ketukan jari 3 kali (*three-finger tap*). Operator dapat mengontrol sesi jarak jauh, memantau daya baterai iPhone, dan menambahkan durasi waktu tamu.
   - **Offline Ledger (CoreData)**: Semua transaksi, data cetak, dan analitik disimpan aman di memori lokal (*Actor-isolated*) dan akan disinkronisasi di *background* (*Cloudflare R2/Supabase*) ketika *router* menemukan jaringan internet.

4. **Fase 4: Fitur Premium & Kecerdasan Buatan (AI)**
   - **Metal LUT Filters**: Pemrosesan *Color Grading* menggunakan format standar industri (`.cube`) yang di-*render* instan oleh GPU iOS (*CoreImage + Metal*) — membuat filter sinematik mulus saat slider digeser.
   - **Apple Vision AI**: *Neural Engine (ANE)* melakukan *tracking* wajah setiap 2 detik untuk menyarankan komposisi *zoom* layar secara pintar, dilengkapi dengan **Living Pose Cards** (Video rekaman loop yang mengajari tamu berpose).
   - **Memory Book Auto-Generator**: Secara otomatis merakit foto-foto sesi menjadi kolase berformat 9:16 cantik (*Instagram Story Ready*) segera setelah sesi usai tanpa *render time* berlebih.

5. **Fase 5: Bug Fixes & Penyatuan Router Utama**
   - Sistem menavigasi setiap layar UI *Kiosk* menggunakan pola `@Observable AppState` yang disuntikkan ke `.environment`, menjaga sinkronisasi status UI dan *logic layer*.
   - Integrasi server *Bonjour HTTP Local* yang merilis QR Code untuk pengunduhan foto tamu instan — **Tanpa Kuota Internet!**

---

## 🚀 Cara Menjalankan Aplikasi di Xcode Pertama Kali

Repositori ini memuat **dua aplikasi** yang berjalan bersamaan:
- **`HaispaceBooths.xcodeproj`** (Aplikasi Kios & Dashboard Operator untuk **iPad**)
- **`HaispaceCamera.xcodeproj`** (Aplikasi Perekam & Transmitter untuk **iPhone**)

**Langkah-langkah Build:**
1. Buka `HaispaceBooths/HaispaceBooths.xcodeproj` menggunakan Xcode (Versi 15+ disarankan).
2. Di bagian pengaturan *Signing & Capabilities*, atur **Team** menjadi tim Apple Developer Anda.
3. Pilih *Target Device* iPad Anda (Pastikan iPadOS 17+ terpasang).
4. Tekan **Run (Cmd + R)** untuk mem-*build* aplikasi di iPad.
5. Ulangi langkah 1-4 untuk `HaispaceCamera/HaispaceCamera.xcodeproj` menggunakan iPhone Anda.

> **Note:** Fitur seperti `MultipeerConnectivity` tidak akan berjalan normal di Simulator. **Wajib** dijalankan menggunakan *real devices* (iPhone & iPad asli).

---

## 📡 Panduan Koneksi P2P (Menyambungkan iPhone dan iPad)

Untuk menjamin latensi serendah mungkin tanpa kabel:

1. **Persiapan Perangkat Biasa:**
   - Nyalakan **Wi-Fi** dan **Bluetooth** pada iPad dan iPhone.
   - (Opsional namun sangat direkomendasikan): Bawa *portable router* atau *Mi-Fi* ke lokasi acara. Buat jaringan Wi-Fi lokal tertutup bernama `HAISPACE_BOOTH` (tidak butuh kuota). Hubungkan iPhone dan iPad ke Wi-Fi tersebut. Apple *Multipeer Connectivity* sangat optimal jika berada pada jaringan router yang sama (akan menggunakan jalur *Infrastructure Wi-Fi* daripada *Bluetooth*).

2. **Proses Pairing (App):**
   - Buka **HaispaceBooths (iPad)**. Lakukan login operator.
   - Buka **HaispaceCamera (iPhone)**.
   - Pada Dashboard Kiosk iPad, aplikasi secara otomatis memulai layanan *Broadcasting*.
   - Di iPhone Anda, layar *Scanner* akan muncul otomatis. Pilih nama iPad Anda di radar pencarian perangkat.
   - Di iPad, sebuah pop-up *Pairing Request* (Permintaan Pemasangan) akan muncul. Tekan **Terima (Accept)**.
   - Boom! 💥 Layar iPad kini seharusnya menampilkan umpan video *live stream* dengan resolusi tinggi langsung dari iPhone Anda. 

## 🔐 Keamanan (App Secrets)
JANGAN pernah melakukan *commit* konstanta rahasia ke publik. Kunci *HMAC* bawaan di dalam `AppSecrets.swift` saat ini hanya digunakan untuk mode `#DEBUG`. Jika merilisnya ke *Production*, letakkan kredensial pada `.xcconfig` Anda.

---
*Dikembangkan dengan dedikasi penuh untuk memberikan revolusi nyata pada pengalaman fotografi acara.* 📸✨