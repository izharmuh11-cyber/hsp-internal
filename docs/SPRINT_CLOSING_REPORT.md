# Sprint Closing Report
# Haispace Booths — Foundation → Operational Platform

> Dokumen ini merangkum seluruh perubahan yang terjadi dalam satu sesi kolaborasi antara:
> - **Principal Engineer / Apple Dev Reviewer** — arah, prinsip, koreksi boundary
> - **IDE Agent (Architect)** — implementasi, dokumentasi, enforcement

---

## Gambaran Perubahan Terbesar

**Sebelum sprint:**
```
Photobooth App → Camera → Payment → Print
```

**Sesudah sprint:**
```
                 Product
                    │
             Workflow Engine
                    │
        ┌───────────┼───────────┐
        │           │           │
   Capability     Audit      Health
        │           │           │
        └───────────┼───────────┘
                    │
          Diagnosis Engine
                    │
           Incident Engine
                    │
      MissionControlViewModel
                    │
          MissionControlView
                    │
             Operator UI
```

---

## 10 Area Perubahan

### 1. Fondasi Arsitektur
- `WorkflowOrchestrator` sebagai single source of truth (ADR-001)
- View hanya mengirim intent — tidak pernah menentukan route sendiri
- `AppState` hanya sebagai projection layer
- `LandingView` sudah dimigrasikan ke `send(.startGuestRegistration)`

### 2. Security
- Secret R2 dipindahkan dari source ke `xcconfig`
- `LicenseValidatorProtocol` dengan Dependency Injection
- `AppState` mock bypass dibungkus `#if DEBUG`
- Tidak ada credential tersisa di Git history yang aktif

### 3. Governance — 4 ADR
| ADR | Keputusan |
|-----|-----------|
| ADR-001 | WorkflowOrchestrator adalah source of truth |
| ADR-002 | Operational Resilience — 4 pilar (Audit, Recovery, Observability, Operability) |
| ADR-003 | Mission Control tidak menghitung apapun — hanya memvisualisasikan |
| ADR-004 | Data Ownership — siapa yang memiliki data apa |

### 4. Audit Trail — Append-Only JSONL
```
{sessionId}.jsonl:
  Line 1:  { header }      ← sessionId, startedAt, schemaVersion
  Line 2:  { event #1 }    ← sequence, stage, eventType, correlationId, actor
  Line 3:  { event #2 }
  ...
  Line N:  { footer }      ← ada footer = selesai normal, tidak ada = crash
```
- Write primitive: `FileHandle.seekToEnd()` — tidak pernah rewrite
- Setiap event punya `sequence` (monotonic) — urutan deterministik
- Setiap event punya `correlationId` — bisa ditelusuri lintas domain

### 5. Recovery — OrphanedSessionDetector
```
App Launch
    ↓
OrphanedSessionDetector.detect()   ← pure function, tidak ada side effect
    ↓
[OrphanedSessionDecision]
    ├── .resumeToDelivery    ← payment confirmed → WAJIB resume
    ├── .awaitOperatorVerification ← payment pending → operator putuskan
    └── .safeToAbandon       ← belum ada transaksi → aman dihapus
```

### 6–7. Observability & Incident Pipeline
```
HealthAggregator.collect()     → PlatformHealthSnapshot
    ↓
DiagnosisEngine.analyze()      → DiagnosisReport         (pure fn)
    ↓
IncidentEngine.evaluate()      → IncidentReport           (pure fn)
    ↓
MissionControlViewModel        → MissionControlSnapshot
    ↓
MissionControlView             → render only
```

**6 Incident Rules:**
| Rule | Severity |
|------|----------|
| Payment confirmed + delivery gagal berulang | Critical |
| Orphaned session dengan payment | Critical |
| Kamera mati saat sesi aktif | High |
| P2P putus saat capturing | High |
| Delivery queue stuck ≥ 3 | High |
| Sesi tidak bergerak > 10 menit | Medium |

### 8. Mission Control (ADR-003)
- `MissionControlSnapshot` — satu objek agregat, bukan 20 publisher
- `MissionControlViewModel` — hanya 4 method: `refresh()`, `acknowledgeIncident()`, `retryIncident()`, `dismissDiagnosis()`
- `MissionControlView` — 4 tab: Insiden, Diagnosis, Kesehatan, KPI

### 9. Incident Lifecycle
```
Detected → Acknowledged → Mitigating → Resolved → Archived
```
Severity: `critical / high / medium / low / info`

### 10. CI Guard — 4 Jobs Otomatis
```
secret-scan          → tidak ada credential di source code
todo-critical-scan   → tidak ada TODO di jalur payment/delivery/license
mock-release-guard   → MockLicenseValidator hanya di #if DEBUG
architecture-guard   → View tidak bypass workflow (ADR-001 enforcement)
```

---

## Invariant yang Ditambahkan

| # | Invariant |
|---|-----------|
| 19 | Setiap transisi WorkflowStage wajib ditulis ke AuditTrail sebelum operasi lanjut |
| 20 | Sesi dengan paymentConfirmed WAJIB di-resume, tidak pernah di-abandon |
| 21 | MissionControlView hanya membaca dari MissionControlViewModel |
| 22 | Setiap kejadian bisnis wajib tercatat di AuditTrail |
| 23 | DiagnosisReport dan IncidentReport tidak boleh disimpan permanen (selalu di-generate ulang) |

---

## File Baru yang Dibuat

### Core/Audit
- `SessionAuditTrail.swift` — append-only JSONL event log
- `OrphanedSessionDetector.swift` — pure detect + recommend

### Core/Observability
- `DiagnosisEngine.swift` — pure function, interface-agnostic
- `HealthAggregator.swift` — collect-only actor
- `IncidentEngine.swift` — 6 rules dengan lifecycle
- `MissionControlSnapshot.swift` — aggregate + OperationalKPIs

### Core/Capabilities
- `NoOpCapabilities.swift` — null object pattern untuk DI

### Core/Workflow
- `WorkflowRouteMapper.swift` — exhaustive stage → route mapping

### App/ViewModels/Operator
- `MissionControlViewModel.swift` — thin, 4 method

### App/Views/Operator
- `MissionControlView.swift` — render only, 4 tab

### Docs
- `ADR-001_workflow_ownership.md`
- `ADR-002_operational_resilience.md` (amended)
- `ADR-003_mission_control_boundary.md`
- `ADR-004_operational_data_ownership.md`

### Tests
- `WorkflowOrchestratorTests.swift` — 12+ regression tests
- `WorkflowFailureInjectionTests.swift` — 5 failure scenarios

### CI
- `.github/workflows/security_guard.yml` — 4 jobs

---

## Yang Belum Selesai (Sprint Berikutnya)

### PRR — Production Readiness Review
- [ ] 8-jam soak test tanpa memory leak
- [ ] Crash injection di setiap stage → orphan terdeteksi
- [ ] Internet offline → queue retry otomatis
- [ ] Storage 95% penuh → app tetap berjalan
- [ ] Thermal throttling → kamera graceful degradation

### View Migration (7 dari 8 belum)
- [x] LandingView
- [ ] GuestRegistrationView, PackageSelectionView, TemplateSelectionView
- [ ] CaptureView, EditingView, PaymentView, DeliveryView

### KPI Collector
- [ ] Implementasi nyata `KPICollector.collect()` dari audit trail

### Recovery Panel UI
- [ ] UI dialog untuk operator saat ada orphaned session

---

## Penutup

> Perubahan terbesar bukan jumlah file atau kelas baru.
> Perubahan terbesar adalah **cara berpikir tentang produk**.
>
> Dari *aplikasi photobooth* → menjadi *platform operasional photobooth*.
> Sistem yang tidak hanya mengambil foto, tetapi mampu mengelola workflow,
> memulihkan kegagalan, memberikan observabilitas, dan membantu operator
> menjalankan banyak booth dengan andal.

---

*Sprint selesai: 2026-07-25*  
*Status: ✅ FOUNDATION + OPERATIONAL EXCELLENCE (Pilar 1–4) SELESAI*  
*Merge target: develop (pending integration soak test sebelum main)*
