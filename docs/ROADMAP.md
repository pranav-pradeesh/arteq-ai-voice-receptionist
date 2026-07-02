# Arteq — Production Readiness Audit & Implementation Roadmap

_Audited: 2026-07-02 · branch `development` @ 04fbee4 · ~21.6k lines Python + Next.js frontend_

## 1. Architecture map (current)

```
Caller (PSTN) ─ Vobiz SIP trunk ─ livekit-sip ─ LiveKit (self-host) ─ agent worker (livekit_agent.py)
                                                          │                 ├─ STT  Sarvam saarika (ml-IN pinned)
Browser /talk ─ /api/v1/livekit/token ────────────────────┘                 ├─ LLM  gemini-2.5-flash (openrouter/groq fallbacks in _build_llm)
                                                                            ├─ TTS  Sarvam bulbul v3 (chunked WS + REST, cache, prewarm)
                                                                            └─ tools (livekit_tools.py, 15 @function_tool)
FastAPI app (src/main.py)
  ├─ /admin/*        dashboard/routes/admin_api.py  (3,571 lines — monolith)
  ├─ /api/v1/auth/*  dashboard/routes/auth.py       (legacy single-password JWT)
  ├─ additions/*     analytics, QA, users/RBAC, live WS, monitoring (parallel universe)
  ├─ scheduler       reminder / confirmation / doctor-availability / outbound-queue /
  │                  callback / follow-up / CDR-reconcile loops (leader-elected)
  └─ migrations      41 .sql files, ALL re-executed at every startup (no version table)
DB: Postgres (compose) / Supabase (tunnel) — multi-tenant by hospital_id (app-level filtering; RLS enabled but app connects as owner → bypassed)
Frontend: Next.js + next-auth, proxies /admin/api/* → backend /admin/*
Deploy: docker-compose.selfhost.yml (10 services), nginx :80 only, prometheus. No TLS, no CI/CD, no backups.
```

## 2. Findings (prioritized)

### P0 — patient safety / security (fix first)
| # | Finding | Evidence |
|---|---------|----------|
| P0-1 | **LLM hallucinates doctors & slots.** Prompt forbids it (line ~172) but gemini-flash violated it live: call `d24a6c67` invented "Dr. Priya / Dr. Anand" + fake Neurology slot times and proceeded toward booking. No post-generation guard; grounding is prompt-only. | call_logs transcript 2026-07-02 15:38 IST |
| P0-2 | **Dead-air calls on provider failure.** Sarvam 402 (out of credits) closed AgentSession mid-call → patients heard silence, no fallback, no transfer, no alert. `FallbackAdapter` exists in deps but is not wired; no `session.on("error")` recovery (LiveKit docs pattern: mark recoverable + `update_agent`). | 2026-06-30 incident |
| P0-3 | **Legacy shared-password auth = super_admin everywhere.** `DASHBOARD_ADMIN_PASSWORD` (default `admin`), JWT secret default `insecure-dev-secret`, non-constant-time compare, token grants all-tenant access. RBAC (users/user_tenants, 006a) exists and is enforced in `_require_auth`, but the legacy path bypasses it by design. | auth.py, admin_api.py:58-125 |
| P0-4 | **No TLS.** All dashboard traffic (PII, JWTs) + browser mic client over plain HTTP on a raw IP. Also blocks WhatsApp webhooks. | nginx :80 only |

### P1 — production blockers
| # | Finding |
|---|---------|
| P1-1 | **No safe human-handoff policy.** `connect_to_human` fires only on explicit ask. No auto-escalation on repeated tool failure, STT garble streak, or low confidence; no context/transcript summary handed to reception. |
| P1-2 | **Migrations un-tracked.** 41 files re-run every boot; one non-idempotent statement bricks startup (`_MigrationError`). Need `schema_migrations` table + apply-once. |
| P1-3 | **No DB backups**, no restore drill. Single Postgres container / remote Supabase via socat tunnel (single point). |
| P1-4 | **No CI/CD.** Tests exist (1 pytest smoke + 3 Playwright e2e) but never run automatically; deploys are manual SSH. |
| P1-5 | **In-memory rate limits** (token + login) — evaporate on restart, break on >1 replica. Move to Redis (already in stack). |
| P1-6 | **Tenant isolation is app-code-only.** RLS enabled (022) but app connects as table owner → every query must remember `hospital_id`. One missed filter = cross-tenant leak. Add automated query audit + (later) per-tenant DB roles. |
| P1-7 | **Monoliths.** `admin_api.py` 3,571 / `livekit_agent.py` 2,536 / `livekit_tools.py` 1,468 lines. `additions/` duplicates dashboard concerns (two auth styles, two user models). Merge & split. |
| P1-8 | **Observability gaps.** Prometheus scrape exists; no alert rules (call failure rate, provider 4xx/5xx, credit exhaustion!), no error tracker (Sentry), agent logs only in docker. Sarvam credit exhaustion was discovered by a patient hearing silence. |

### P2 — scale & quality
| # | Finding |
|---|---------|
| P2-1 | **Latency**: llm_ttft ≈ 1.3–1.5 s dominates (~2.1 s turn). System prompt is ~4k+ words rebuilt per call and resent per turn → direct TTFT + cost hit. Slim to <1.5k words; move rules into guards/code. |
| P2-2 | **"RAG" = prompt stuffing.** Whole `knowledge_base` text is inlined; `embeddings` table + `match_documents()` exist but unused. Chunk + retrieve top-k only when KB is large. |
| P2-3 | **Malayalam STT robustness**: transcripts show garbles ("മെറുഗോളജി" for Neurology). No domain keyword biasing (doctor/department names), no confidence-driven re-ask policy in code (prompt-only). |
| P2-4 | **Dead code / legacy providers**: exotel_bridge, exotel_stream, plivo_provisioning, groq_brain (partially), `scripts/build_founder_pdf.py` in prod image. |
| P2-5 | **No per-doctor working hours** in `doctors` (only availability_status); `schedules` table exists but unclear coverage — booking uses hospital-wide hours. |
| P2-6 | **Frontend**: role-aware UI incomplete (super-admin vs tenant views), duplicated pages under additions-era routes. |

### P3 — hygiene
Naming consistency, docstrings, `README` drift, test coverage (<5%), `.env.example` completeness, remove `Windows.old`-style leftovers in repo (founder PDF, sample assets).

## 3. Roadmap (phased, in execution order)

### Phase 1 — AI voice pipeline (task #9) ⟵ NEXT
1. **Grounding guard (P0-1)** — deterministic post-LLM validator in the agent's reply path (`tts_node`):
   - Per-call roster (doctor names + departments from `hospital_ctx`) and per-turn tool-result cache.
   - Reply mentions a doctor name not in roster ∪ tool results → block that reply, substitute safe Malayalam re-ask, log `hallucination_blocked`.
   - Tools already fail closed with apologetic strings — keep; add metrics.
2. **Provider failover + never-dead-air (P0-2)** — per LiveKit docs (Context7-verified):
   - `stt.FallbackAdapter([sarvam, openai_stt])`, same for TTS; `session.on("error")` → mark recoverable, `session.update_agent()` for STT resets.
   - Terminal failure (all providers down) → speak canned local WAV apology (pre-generated, no TTS needed) → SIP-transfer to `reception_phone`.
   - Prometheus counter + alert on provider errors (catches credit exhaustion in minutes, not via patients).
3. **Safe human fallback (P1-1)** — auto `connect_to_human` triggers: 2+ consecutive tool failures, 3+ unclear-turn streak, emergency keywords, provider outage. Handoff = live transfer + summary row (`call_handoffs` table) surfaced on dashboard live view.
4. **Malayalam (P2-3)** — inject hospital roster (doctor + dept names, Malayalam + Latin) as STT keyword bias if Sarvam API supports; expand `tts_normalize`; verify number/date speech rules.
5. **Latency (P2-1)** — slim prompt to <1.5k words (guards now enforce what prose used to beg for); measure ttft before/after; keep gemini-flash primary, groq llama fallback.

### Phase 2 — Dashboards + RBAC (task #10)
1. Role matrix: `super_admin` (platform: tenants, billing, usage, health), `tenant_admin` (their hospital: doctors, schedules, patients, calls, settings), `receptionist` (new role: today's appointments, live calls, callbacks, handoffs — no settings/billing), `viewer` (read-only). Doctor portal deferred unless required.
2. Retire legacy shared password behind `LEGACY_ADMIN_ENABLED=false` (default off in prod); constant-time compares; required strong `DASHBOARD_JWT_SECRET` (fail startup on default).
3. Merge `additions/` into `dashboard/` (one auth dependency, one users API); split `admin_api.py` by resource.
4. Frontend: role-gated nav, remove dead pages, add missing enterprise pages (audit log, usage & cost, provider health, handoff queue).

### Phase 3 — Platform hardening
TLS (domain + certbot/caddy or Cloudflare tunnel), `schema_migrations` tracking, nightly `pg_dump` backups + restore doc, Redis rate limits, Sentry, Prometheus alert rules, CI (GitHub Actions: pytest + playwright + compose build), staged deploys (staging branch → prod).

### Phase 4 — Quality
Delete exotel/plivo dead code, tests for tools & auth & scheduler (target: critical-path coverage), README refresh, `.env.example`, load test (k6) on booking path.

## 4. Definition of done per phase
Each phase lands on `development`, tested on VPS (compose build + real test call for agent changes), then merged to `main` after user sign-off.
