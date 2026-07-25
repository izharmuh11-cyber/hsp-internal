# 🏛️ Haispace Product Archaeology Contract & Evidence Rating System

```text
===================================================================
ARCHAEOLOGY CONTRACT METADATA
Status: LOCKED FOR CURRENT INVESTIGATION CYCLE
Version: v1.0
Effective Date: 2026-07-25
Unlock Condition: Evidence from completed DIG requiring methodological revision
===================================================================
```

> **Kontrak Kerja Arkeologi Produk (Product Archaeology Contract v1.0)** Haispace Kiosk Photobooth Platform.
> Mengatur tata cara penggalian artefak kode legacy SnapBooth (`photobooth_clean.zip`), penelusuran *Product Fossils*, dan Sistem Penilaian Bukti.

---

## 🔒 1. Independent Reproducibility Rule

> **"Sebuah Laporan DIG dinyatakan selesai HANYA jika reviewer independen dapat mereproduksi ulang kesimpulannya secara identik dari bukti kanonis (Canonical Evidence) yang dicantumkan."**

---

## 📜 2. Strict Archaeological Sequence & 7 Archaeology Missions

```text
Discovery  ➔  Forensic Investigation Report  ➔  Repository Verification  ➔  Knowledge Card  ➔  Migration
```

### 🎯 The 7 Archaeology Missions
1. **Mission 1 — 100% Evidence Driven:** Stop producing new design documents (Doc #60+ forbidden). Focus 100% on forensic code investigation.
2. **Mission 2 — Decisions Over Features:** Extract product decisions & rationale, not raw syntax/features.
3. **Mission 3 — Forensic Investigation Report Format:** Every finding must be formatted as a formal `DIG-XXX` Forensic Investigation Report.
4. **Mission 4 — Strict Order:** Investigation Report comes FIRST before any Knowledge Card.
5. **Mission 5 — Domain DNA Extraction:** Extract DNA across Editing, Camera, Session, Printing, Asset, & UX.
6. **Mission 6 — Decision Chains:** Map interconnected decisions into overarching product philosophies.
7. **Mission 7 — Product DNA Atlas:** Produce an indexed atlas of verified product decisions mapped to Native implementation candidates.

---

## 🔍 2. Forensic Investigation Report Structure & Templates

- **Forensic Report Template:** [dig_template.md](dig_template.md)
- **Objective Reviewer Quality Gate & Verdicts:** [reviewer_checklist.md](reviewer_checklist.md) (`PASS` | `PASS WITH REVISIONS` | `REJECT`)

---

## 🔒 3. Contract Lock Rule
`archaeology_contract.md` kini **DIBEKUKAN MUTLAK**. Perubahan pada kontrak ini **DILARANG HARUS** kecuali jika minimal satu Laporan DIG yang selesai membuktikan adanya kekurangan nyata pada metodologi.

---

## ⚡ 4. Haispace Difference Registry (Di Mana Haispace Melampaui Legacy)

| Legacy Decision (SnapBooth) | Haispace Decision | Rationale Keunggulan Native |
| :--- | :--- | :--- |
| Popup Error Technical Alert | Silent Self-Healing Recovery | Mengurangi kecemasan tamu |
| Manual Crop Adjustment | Smart Auto Composition | Mengurangi friksi interaksi |
| Blocking Export Render | Background Async Pipeline | Respons visual instan (<50ms) |
| Waiting Spinner Screen | Progressive Curtain Reveal | Meningkatkan antisipasi emosional |

---

## 🎯 4. Product DNA Review Summit (Bridging Phase 4 to Phase 5)

Pertemuan puncak peninjauan DNA produk sebelum penyusunan Atlas Phase 5:
- **20 Keputusan Terbaik** yang wajib dipertahankan.
- **10 Keputusan Legacy** yang sengaja tidak dibawa.
- **10 Inovasi Murni Haispace Native**.
- **5 Eksperimen Utama** untuk diuji pada prototipe fisik.

---

## 🎯 5. The 80/20 Archaeology Rule & Investigation Guidelines

### 🔒 80/20 Focus Matrix
- **Top Priority (5★):** Photo Editor, Canvas Engine, Composition, Gesture, Session Flow.
- **Medium Priority (4★):** Asset Pipeline, Print Queue, Operator Mission Control.
- **Low Priority (2★):** Admin CRUD, Authentication, User Settings.
- **Skip (1★):** Boilerplate, Vendor Libraries, Config files.

### 📐 Investigation Rules
1. **Decision Family:** Group micro-decisions into unified Decision Families (e.g. `DIG-001: Photo Manipulation Decision Family`).
2. **Evidence Saturation:** One DIG per core decision; avoid duplicate DIGs for repeated function calls.
3. **Canonical Evidence:** Specify 1 primary source file/line range as `Canonical Evidence` and others as `Supporting Evidence`.
4. **Tombstone Rule:** Mark dead/abandoned code as `STATUS: OBSOLETE` (documenting why features were abandoned).
5. **Product Timeline:** Trace decision evolution historically from legacy up to Haispace Native (e.g. *Manual ➔ Auto Fit ➔ Smart Alignment ➔ Adaptive Composition*).

---

## 💰 4. Innovation ROI Matrix & Legacy Doesn't Win Automatically Rule

### Innovation ROI Score Formula
Each verified DIG Report is evaluated against 4 ROI factors:
- **User Impact** (1–5 Stars)
- **Engineering Cost** (1–5 Stars)
- **Maintenance Cost** (1–5 Stars)
- **Differentiation** (1–5 Stars)
➔ Yields: **HIGH ROI**, **MEDIUM ROI**, or **LOW ROI**.

### 🔒 Legacy Doesn't Win Automatically Rule
Every legacy artifact must answer 4 validation questions:
1. Does it really provide value for guests/operators?
2. Is it still relevant to Haispace today?
3. Is there a simpler native way to achieve the same result?
4. If building from scratch today, would we still choose this decision?
*(If No ➔ `Archive` or `Reject`!).*

---

## ⭐ 2. Dual-Dimension Evidence Rating System

Setiap artefak dievaluasi berdasarkan dua dimensi rating:

1. **Code Evidence (1–5 Bintang):** Apakah perilaku ini secara empiris ada dan dapat dibuktikan di dalam kode SnapBooth Web?
2. **Behavior Evidence (1–5 Bintang):** Apakah perilaku ini sengaja diciptakan untuk menyelesaikan masalah nyata tamu/operator?

---

## ⛏️ 3. Urutan Prioritas Penggalian (6 Dig Priorities)

1. **Dig 1: Composition & Editing Engine** (Transform matrix, snap thresholds, auto-fit, frame hole mask, gesture smoothing).
2. **Dig 2: Session Lifecycle** (Recovery, idle timeout, session restore, state persistence).
3. **Dig 3: Asset Pipeline** (Caching, thumbnail generation, lazy loading, anticipatory loading).
4. **Dig 4: Operator Layer** (Hidden shortcuts, maintenance flow, diagnostics, recovery paths).
5. **Dig 5: Print & Delivery** (Queue management, idempotent retry, completion flow).
6. **Dig 6: Experience Layer** (Countdown timing, animation easing curves, reveal choreography).

---

*Last Updated: 2026-07-25*  
*Status: 🔒 FROZEN PRODUCT ARCHAEOLOGY CONTRACT*
