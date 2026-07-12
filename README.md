# 📸 HaiBooth — Apple Native Photobooth System

![HaiBooth Cover](https://via.placeholder.com/1200x400/1A1A24/FFFFFF?text=HAIBOOTH+SYSTEM+—+APPLE+NATIVE)

HaiBooth adalah sistem *photobooth* profesional yang dirancang khusus dengan pendekatan **Native-First** untuk ekosistem Apple. Arsitektur mutakhirnya memisahkan peran **Kamera Perekam (iPhone)** dan **Kiosk Interaktif Tamu (iPad)** yang berkomunikasi secara terenkripsi *(Peer-to-Peer)* tanpa membutuhkan jaringan internet aktif *(Offline Always)*.

---

## 🌟 Rekapitulasi Fitur (Fase 1 - 5)

Proyek ini telah dikembangkan secara bertahap melalui 5 fase krusial hingga mencapai bentuk sempurnanya:

### Fase 1: P2P Network & Kamera Engine 📡
- **Offline P2P TLS 1.2:** Menggunakan `MultipeerConnectivity` dan Network.framework untuk komunikasi nirkabel tanpa batas antara iPhone dan iPad dengan latensi ultra-rendah.
- **ProRAW 12MP Capture Engine:** Mesin kamera di iPhone memanfaatkan `AVCaptureSession` dengan dukungan resolusi tinggi dan pengambilan gambar asinkron tanpa *shutter-lag*.

### Fase 2: Alur Kiosk Tamu & Desain UI iPad 🎨
- **Kiosk Interaktif SwiftUI:** Menuntun tamu melalui proses yang *seamless*: Pendaftaran Tamu ➔ Pemilihan Paket ➔ Sesi Foto ➔ Pemilihan Cetak ➔ Pembayaran.
- **Frosted Glass UI:** Desain antarmuka terinspirasi dari macOS (material *ThinMaterial*) yang memberikan kesan elegan, responsif, dan premium.

### Fase 3: Mission Control & Database Operator ⚙️
- **Mission Control (Secret Dashboard):** Panel kontrol operator tersembunyi yang dapat dipanggil menggunakan ketukan 3 jari (*three-finger tap*). Memungkinkan reset sesi, tambah waktu, dan pantau baterai iPhone secara *remote*.
- **Offline Ledger (CoreData):** Semua transaksi pembayaran, antrian cetak, dan data tamu disimpan di penyimpanan lokal, dan akan disinkronisasikan perlahan ke *Cloud* saat internet tersedia.

### Fase 4: Fitur Premium & Kecerdasan Buatan (AI) 🧠
- **Real-Time Metal LUT Filters:** Filter *Color Grading* (Hitam Putih, Vintage, Cinematic) berformat `.cube` yang di-render 60 FPS oleh GPU menggunakan **Metal & CoreImage**.
- **Apple Vision AI Tracking:** Deteksi wajah dan tubuh otomatis berbasis *Neural Engine*. Layar iPad akan memberikan instruksi cerdas untuk memandu tamu berpose.
- **Memory Book Auto-Generator:** Generator kolase otomatis (rasio 9:16) untuk langsung dibagikan tamu ke Instagram Story/TikTok.

### Fase 5: Bug Fixes, Finalisasi & Sinkronisasi Xcode 🛠️
- **Robust Architecture:** Memperbaiki aliran Data Flow SwiftUI menggunakan `@Observable AppState`, menjaga agar UI tidak patah saat transisi.
- **Bonjour Local HTTP Server:** iPad otomatis menjadi server jaringan lokal sehingga tamu dapat mengunduh foto mereka langsung via pemindaian **QR Code** tanpa kuota seluler.

---

## 🚀 Cara Menjalankan di Xcode Pertama Kali

Repositori ini memuat **dua aplikasi** yang berjalan saling berdampingan:
1. **`HaispaceBooths.xcodeproj`** (Aplikasi Kios & Dashboard Operator untuk **iPad**)
2. **`HaispaceCamera.xcodeproj`** (Aplikasi Perekam & Transmitter untuk **iPhone**)

**Langkah-langkah Kompilasi (Build):**
1. Buka folder `HaispaceBooths` dan buka `HaispaceBooths.xcodeproj` menggunakan Xcode (Versi 16+ disarankan).
2. Pergi ke tab **Signing & Capabilities**, atur **Team** menjadi tim Apple Developer (Personal/Company) Anda.
3. Hubungkan **iPad asli** menggunakan kabel ke Mac Anda, dan pilih iPad tersebut sebagai *Target Device*.
4. Tekan **Run (Cmd + R)** untuk mem-*build* aplikasi di iPad.
5. Setelah berhasil, tutup Xcode (opsional) dan buka `HaispaceCamera/HaispaceCamera.xcodeproj`.
6. Lakukan hal yang sama untuk **iPhone asli** Anda.

> **Peringatan Keras (Simulator):** Fitur kamera perangkat keras, Vision AI ANE, dan `MultipeerConnectivity` **tidak dapat** berjalan di iOS Simulator. **Wajib** menjalankannya menggunakan *real devices*.

---

## 📡 Panduan Koneksi P2P (Menyambungkan iPhone & iPad)

Untuk menjamin latensi serendah mungkin tanpa kabel (di tengah keramaian acara/sinyal *crowded*):

1. **Persiapan Sinyal Jaringan (Rekomendasi Praktik Terbaik):**
   - Bawa *portable router* biasa (tanpa perlu kartu SIM/paket data) ke lokasi acara. 
   - Buat jaringan Wi-Fi lokal tertutup (Misal: `HAISPACE_BOOTH_5G`).
   - Hubungkan iPhone dan iPad ke Wi-Fi tersebut. Apple *Multipeer Connectivity* sangat cerdas; jika perangkat berada dalam satu jaringan router, ia akan menggunakan jalur *Infrastructure Wi-Fi* yang jauh lebih kuat dan cepat dibandingkan *Bluetooth* atau *Ad-hoc Wi-Fi*.

2. **Proses Pemasangan (Pairing):**
   - Buka aplikasi **HaispaceBooths** di iPad. Setelah login, aplikasi akan membuka jalur komunikasi P2P sebagai *Broadcaster*.
   - Buka aplikasi **HaispaceCamera** di iPhone.
   - Layar iPhone akan masuk ke mode *Radar Scanner*. Ketuk nama iPad Anda saat muncul di daftar perangkat terdekat.
   - Layar iPad akan menampilkan pop-up konfirmasi *Pairing*. Tekan **Terima (Accept)**.
   - Selesai! Layar iPad sekarang akan menayangkan siaran langsung (Live View) HD dari kamera iPhone Anda.

---

## 🔐 Keamanan & Lingkungan (App Secrets)

Jangan pernah menyimpan kredensial produksi (API Key, kunci enkripsi JWT, sandi) di dalam *source code* Git. 
Buka file `Core/Security/AppSecrets.swift`. Kunci *HMAC* dan konfigurasi di sana sudah diamankan, namun jika Anda bersiap meluncurkan ke publik (App Store), sangat direkomendasikan memindahkannya ke `.xcconfig` yang di-*gitignore*.

---
*Dikembangkan dengan penuh ketelitian untuk revolusi industri Photobooth.* 🚀🍏