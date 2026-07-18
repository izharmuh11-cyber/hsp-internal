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

## 📁 How to View and Analyze logs (Cara Melihat & Menganalisis Log)

AI agents must use the following procedure to inspect logs when debugging issues or verifying test results:

1. **Download logs from cloud storage (R2):**
   Run the Python script in the repository root to fetch logs:
   ```bash
   python scratch/fetch_r2_logs.py
   ```
   *This downloads the latest logs to the local `scratch/logs/` directory.*

2. **Locate Target Log Files:**
   * **iPhone logs (HaiCamera):** Inspect `scratch/logs/iphone-latest.txt` (or timestamped `iphone-*.txt` matching the test timestamp).
   * **iPad logs (HaiBooth):** Inspect `scratch/logs/ipad-latest.txt` (or timestamped `ipad-*.txt` matching the test timestamp).

3. **Log Markers to search for:**
   * `Memicu jepretan foto` – Marks the start of a still capture event.
   * `[PortraitMode]` – Traces zoom adjustment, depth delivery activation, and synchronizer changes.
   * `Koneksi TCP gagal` or `Connection reset` – Indicates a network drop, usually caused by an instant app crash on the other device.
   * `launched` or `setupSession` – Traces app launches/restarts.
