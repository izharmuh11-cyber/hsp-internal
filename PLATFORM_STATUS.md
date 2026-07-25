# 📌 PLATFORM_STATUS.md — Haispace Photobooth Platform Status

> Catatan resmi milestone proyek dan status pembekuan layer inti (*Core Layer Freeze*). 
> Berfungsi sebagai dokumen acuan orientasi untuk seluruh pengembang (Human & AI Agent).

---

## 🏆 Milestone Utama yang Telah Dicapai

- [x] **Fase 1: Konstitusi Arsitektur (#44 s/d #50)** — 17 Invariants, P2P Specification, Event Contracts, 3-Layer Capability Topology, & Golden Reference Template.
- [x] **Fase 2: Lima Business Capability Terbukti (#50 Scorecard 100/100)**:
  1. `CameraCapability` (Hardware Orchestration) — *Golden Reference*
  2. `EditingCapability` (Processing Pipeline - CoreImage/Metal)
  3. `P2PCapability` (Networking & Distributed Transfer - Dual-Transport)
  4. `PaymentCapability` (Business Payment Lifecycle - QRIS / Gateway)
  5. `DeliveryCapability` (Distribution Orchestrator - Bonjour / AirDrop)
- [x] **Fase 3: Integration & Workflow Orchestration**:
  - `WorkflowOrchestrator` Business State Machine (`Landing` ➔ `Capture` ➔ `Edit` ➔ `Payment` ➔ `Delivery` ➔ `Reset`).
  - `VerticalSlicePipelineTests.swift` — Uji integrasi pipa happy path & failure-path resiliency.
- [x] **Fase 4: End-to-End Product Acceptance Test**:
  - `ProductAcceptanceTests.swift` — High-level Given-When-Then BDD Acceptance Suite.

---

## 🔒 Status Core Layer: FROZEN (DIBEKUKAN)

Layer Inti (*Core Platform*) secara resmi **DIBEKUKAN (`FROZEN`)**:
- `CameraCapability`, `EditingCapability`, `P2PCapability`, `PaymentCapability`, `DeliveryCapability`, dan `WorkflowOrchestrator` **DILARANG DIUBAH** kecuali untuk perbaikan bug runtime yang terbukti secara empiris.
- Perubahan pada Dokumen #44 s/d #50 dilarang tanpa pembuktian kebutuhan minimal 3 capability sekaligus.

---

## 🎯 Fokus Utama Pengembangan Selanjutnya (Product Experience & Operations)

1. **SwiftUI Kiosk UI Runtime:** Layar-layar antarmuka iPad (Landing, Registration, Template, Capture, Edit, Payment, Delivery) murni sebagai *Thin Rendering Layer*.
2. **Mission Control Operator Dashboard:** Tampilan pemantauan status kesehatan visual real-time (`Camera 🟢`, `Editing 🟢`, `P2P 🟢`, `Payment 🟢`, `Delivery 🟢`, `Workflow 🟢`).
3. **Hardware Validation & Field Operations:** Pengujian durabilitas fisik (100+ capture berturut-turut, GPU thermal check, Wi-Fi recovery).

---

## 📋 Architecture Decision Records (ADR)

| ADR | Judul | Status | Tanggal |
|-----|-------|--------|---------|
| [ADR-001](design/ADR-001_workflow_ownership.md) | Workflow Ownership | ✅ ACCEPTED | 2026-07-25 |
| [ADR-002](design/ADR-002_operational_resilience.md) | Operational Resilience | ✅ ACCEPTED (Amended) | 2026-07-25 |
| [ADR-003](design/ADR-003_mission_control_boundary.md) | Mission Control Boundary | ✅ ACCEPTED | 2026-07-25 |
| [ADR-004](design/ADR-004_operational_data_ownership.md) | Operational Data Ownership | ✅ ACCEPTED | 2026-07-25 |

---

## 🔄 Workflow Migration Progress

Migrasi View layer dari `navigateTo()` → `handleIntent()` (sesuai ADR-001):

```
[x] Bridge Step 1  — WorkflowOrchestrator di-wire ke AppState ✅
[x] Landing        — handleIntent(.startGuestRegistration) ✅
[ ] Registration   — handleIntent(.guestSubmittedInfo)
[ ] Package Select — handleIntent(.selectPackage)
[ ] Camera/Capture — handleIntent(.triggerShutter)
[ ] Editing        — handleIntent(.selectFilter / .acceptPreview)
[ ] Payment        — handleIntent(.confirmPaymentSuccess)
[ ] Delivery       — handleIntent(.finishSession)
```

---

## 🔒 Sprint Foundation & Stabilization Review Checklist

**Definition of Done (100% COMPLETED):**

- [x] Zero secret/credential di source code ✅ *R2 keys dipindah ke xcconfig*
- [x] License validation nyata (bukan placeholder) — DI via `LicenseValidatorProtocol` ✅
- [x] ADR-001 diterima ✅
- [x] AppState mock bypass dibungkus `#if DEBUG` ✅
- [x] Bridge WorkflowOrchestrator → AppState selesai ✅ *via WorkflowRouteMapper*
- [x] Architecture Regression Tests selesai ✅ *WorkflowOrchestratorTests.swift expanded*
- [x] Failure Injection Tests selesai ✅ *WorkflowFailureInjectionTests.swift created*
- [x] CI Security & Architecture Guard aktif ✅ *security_guard.yml: 4 jobs*
- [x] Landing View dimigrasikan ke handleIntent() ✅ *Minimal 1-line migration*
- [x] Stabilization Review Approved ✅ *Governance, Security, Thread Safety & Failure Resilience Verified*

---

*Last Updated: 2026-07-25*  
*Status Platform: 🔒 SPRINT FOUNDATION & STABILIZATION APPROVED / SPRINT OPERATIONAL EXCELLENCE STARTED*

---

## 🚀 Sprint Operational Excellence Checklist

**Target: Booth tetap bisa menyelesaikan transaksi walaupun sebagian sistem gagal.**

### Pilar 1 — Auditability
- [x] `SessionAuditTrail` — persistent synchronous event log per-sesi ✅
- [x] Setiap transisi `WorkflowStage` tercatat di audit trail ✅
- [x] Error di camera/payment/delivery juga tercatat ✅
- [ ] Audit trail visible di Mission Control (Log Viewer)

### Pilar 2 — Recoverability  
- [x] `OrphanedSessionDetector` — deteksi sesi tidak selesai saat launch ✅
- [x] `AppState.setup()` menjalankan deteksi sebelum `isAppReady = true` ✅
- [x] `paymentConfirmed` → `resumeToDelivery` (tidak pernah di-abandon) ✅
- [ ] RootView routing untuk handle `orphanedSessionDecisions`
- [ ] UI recovery dialog untuk operator

### Customer Views (Apple HIG Refined)
- [x] `LandingView` — 1 CTA, clean typography, Apple press button, subtle idle hint ✅
- [x] `PackageSelectionView` — 2-card comparison, popular tag, high clarity ✅
- [x] `CaptureView` — floating cinematic countdown, 80x80 thumbnail pop animation, corner guides ✅
- [x] `EditingView` — fast frame/filter swipe selection, live preview strip ✅
- [x] `PaymentView` — QRIS display, clear total, instant & reassuring confirmation ✅
- [x] `DeliveryView` — WhatsApp softcopy input, warm farewell, 15s auto-reset ✅

### Mission Control Operator Views (ADR-003 & ADR-004)
- [x] `MissionControlViewModel` — thin ViewModel (refresh, acknowledge, retry, dismiss) ✅
- [x] `MissionControlView` — 4 tabs (Incidents, Diagnosis, Health, KPIs) ✅

### Pilar 4 — Operability
- [x] `OperatorAction` enum (retry, reconnect, clear queue, export, reset) ✅
- [ ] Mission Control UI tombol aksi per insiden
- [ ] Recovery Panel untuk orphaned sessions
- [ ] Export diagnostic log ke file

### Production Readiness Review (PRR)
- [ ] 8-jam soak test tanpa memory growth
- [ ] Crash injection di setiap stage → orphaned session terdeteksi
- [ ] Printer restart di tengah delivery → retry otomatis
- [ ] Storage 95% penuh → app tetap berjalan, error jelas
- [ ] Semua CI Guard hijau setelah siklus penuh

