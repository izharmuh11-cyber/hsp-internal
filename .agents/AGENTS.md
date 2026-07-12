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
   * **NEVER** run `git push` automatically.
   * All changes must remain purely local in the working directory until the operator explicitly requests a push with commands like *"silahkan push"* or *"oke push"*.

4. **Confidentiality of Design Docs:**
   * Do not remove `docs/design/` from `.gitignore`. Internal design strategy documents must remain local-only.
