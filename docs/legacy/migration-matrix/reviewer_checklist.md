# 🧪 Objective Reviewer Checklist & Review Verdict Specification

> **Daftar Periksa & Keputusan Reviewer Objektif (Reviewer Quality Gate & Verdicts)** Haispace Kiosk Photobooth Platform.
> Digunakan oleh reviewer independen untuk memverifikasi setiap Forensic Investigation Report (`DIG-XXX`) secara netral dan objektif.

---

## 🚦 1. Minimum Acceptance Criteria (Syarat Masuk Audit)

Sebelum pengujian 5 tahap dilakukan, Laporan DIG WAJIB lolos 4 syarat minimum:
1. *Canonical Evidence* mengarah ke lokasi kode yang eksplisit dan dapat ditemukan.
2. *Supporting Evidence* relevan dengan keputusan yang dibahas.
3. *Product Question* dijawab langsung oleh bukti yang dikumpulkan.
4. *Decision Statement* dapat ditelusuri kembali ke bukti tanpa lompatan asumsi.
*(Jika syarat minimum ini belum terpenuhi, laporan langsung dikembalikan untuk dilengkapi).*

---

## 🔍 2. 5-Point Reviewer Quality Gate

1. **Evidence Check:** Apakah *Canonical Evidence* dan *Supporting Evidence* benar-benar mendukung kesimpulan tanpa manipulasi?
2. **Inference Check:** Apakah *Decision Statement* murni diturunkan dari bukti, atau terdapat lompatan logika (*logic jumps*)?
3. **Scope Check:** Apakah fokus laporan murni 1 *Decision Family*, atau terdapat keputusan lain yang tercampur?
4. **Migration Check:** Apakah rekomendasi (*Adopt / Adapt / Archive / Reject*) konsisten dengan bukti dan ROI?
5. **Confidence Check:** Apakah rating bintang (*Code, Behavior, Origin, Reusability*) mencerminkan kualitas bukti secara jujur?

---

## ⚖️ 2. Review Verdict Classification

Setiap audit laporan DIG wajib diakhiri dengan salah satu dari 3 status keputusan (*Review Verdict*):

- **PASS:** Laporan terbukti kuat, evidence valid, dan inferensi logis. Siap dipromosikan ke *Product DNA Atlas*.
- **PASS WITH REVISIONS:** Laporan memiliki nilai, tetapi membutuhkan bukti pendukung tambahan atau perbaikan inferensi sebelum dipromosikan.
- **REJECT:** Evidence tidak terbukti di kode, terdapat lompatan logika fatal, atau merupakan spekulasi tanpa bukti.

---

## 📊 3. DIG Review Audit & Atlas Promotion Table

| DIG ID | Decision Family | Verdict | Confidence | Ready for DNA Atlas |
| :--- | :--- | :---: | :---: | :---: |
| **DIG-001** | Photo Manipulation Family | `PENDING REVIEW` | — | ❌ |

---

## 📈 4. Internal Investigation Performance Metrics

- **Average Review Time:** Durasi rata-rata audit per Laporan DIG.
- **PASS Rate:** persentase Laporan DIG yang langsung lolos tanpa revisi.
- **Revision Rate:** persentase Laporan DIG yang membutuhkan perbaikan bukti.
- **Evidence Reuse:** Frekuensi penggunaan ulang *Canonical Evidence* yang sama.
- **Atlas Promotion Rate:** Persentase Laporan DIG yang dipromosikan ke *Product DNA Atlas* Phase 5.

---

## 🚦 5. Phase Gate Decision & Operational Rules

- **Gate Status:** `APPROVED TO ENTER INVESTIGATION`
- **Rule — One Investigation at a Time:** DILARANG memulai DIG-002 sebelum DIG-001 selesai diaudit dan mendapatkan *Review Verdict*. Ini mencegah merambatnya pola kesalahan investigasi.

---

## 🔒 6. Independent Reproducibility Rule
Laporan DIG HANYA lolos `PASS` jika reviewer kedua yang membaca *Canonical Evidence* sampai pada kesimpulan yang identik secara independen tanpa lompatan asumsi.

---

*Last Updated: 2026-07-25*  
*Status: 🔒 FROZEN REVIEWER CHECKLIST*
