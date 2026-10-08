# Release notes — v1.0.0

**Tag:** annotated `v1.0.0`
**Gate:** `.github/workflows/release-gate.yml` — triggered by this tag push; reuses the CI quality net (`.github/workflows/ci.yml` via `workflow_call`) and additionally parses the in-repo `assessment/risk-register.json`. Posts `RELEASABLE` / `BLOCKED` as a commit status on the tagged commit. Fails closed (crashed or unreadable register = `BLOCKED`).

## What v1.0.0 claims to deliver

A **hardened baseline**, not a zero-risk product. This release delivers:

1. **The quality net** — Definition-of-Ready/Done workflow gate + CI test net, built around the assessment findings, demonstrated RED on the seeded defects and GREEN after root-cause fixes.
2. **P0/P1 fixes for the confirmed data-integrity defects** — session end no longer trusts the client; portfolio save is transactional; tenant fallback is deterministic; the fit/gap contract is aligned; invite failures are surfaced honestly; confidence rules are code-enforced; the compose stack runs the background worker.
3. **The release gate itself** — a tag-triggered, legible `RELEASABLE`/`BLOCKED` verdict tied to the tag, driven by the CI net + the risk register (no open, unaccepted P0/P1).

Evidence and design: [`assessment/01-audit.md`](assessment/01-audit.md), [`assessment/risk-register.json`](assessment/risk-register.json), [`assessment/02-quality-system.md`](assessment/02-quality-system.md).

### The net (what protects this repo)

| Check | What it protects | Where |
|-------|------------------|-------|
| Definition-of-Ready/Done policy gate | PRs missing spec/AC/design/test evidence, or shipping source changes (`api/app|config|db`, `web/src`) without a matching test file, cannot merge. Required status check on `main`. | `.github/workflows/policy-gate.yml`, `.github/scripts/policy-gate.cjs`, `.github/pull_request_template.md` |
| CI quality net | Every push/PR: RSpec (api, with Postgres + Redis services) + Vitest + `tsc` + Vite build (web). | `.github/workflows/ci.yml` |
| Release gate | On `v*` tag push: CI net re-run on the tagged commit **and** risk register parsed; `RELEASABLE` only if net green AND no P0/P1 `open` without `risk_accepted: true`. Verdict posted as commit status on the tag. | `.github/workflows/release-gate.yml`, `.github/scripts/release-gate.cjs` |

What each check deliberately does **not** do (and how to run/extend the net) is documented in [`assessment/02-quality-system.md`](assessment/02-quality-system.md), including the red→green history per fixed defect and the explicit not-covered/not-fixed list.

### Fixed in this release (P1 confirmed defects)

Each fix landed with a regression test; each has a captured red→green story in `assessment/02-quality-system.md`. Machine-readable statuses live in `assessment/risk-register.json`.

| ID | Severity | What was fixed |
|----|----------|----------------|
| **B1** | P1 | `audio_complete` no longer trusts the client's `all_covered` claim. A session cannot be force-ended as fully covered on zero coverage; the server records a truthful end reason when coverage is unverified. |
| **B2** | P1 | Portfolio skill save is transactional (savepoint) with pre-write validation of `level`/`confidence`. A bad skill in the response cannot leave a partial row set behind. |
| **B4** | P1 | Login tenant-scheme fallback is deterministic: ordered selection that excludes the reserved `id=0` org; explicit `X-Tenant-Scheme` still wins. |
| **A4** | P1 | Fit/gap contract drift closed: web types/read path now match what the API persists (`expected_level`) and emits (`is_override`). The Required column and override marker render correctly. |
| **U1** | P1 | Invalid/expired candidate invite renders an explicit invalid-link state — never a false "Interview Complete" success screen. |
| **ENF-1** | P1 | Confidence rules (high/medium/low from `probe_count` + coverage state) enforced server-side in `save_skills` against the session's coverage maps; no longer prompt-only. Never upgrades. |
| **F2** | P1 | Compose stack runs the Sidekiq worker (same api image/env). Background jobs drain; portfolio generation, fit/gap, and export are reachable — the end-to-end path completes. |

Also recorded, for completeness:

- **B3** (coverage state machine) — verified **correct**, not a defect. Regression-lock tests only (`state_engine.rb` probe-count gate, forward-only transitions, `covered` freeze).
- **B6** (no admin user in seeds) — fixed earlier (seeded admin, login proven); regression-locked.

### Open risks — read this before shipping

The gate emits `RELEASABLE` for `v1.0.0` because the quality net is green **and** every remaining P0/P1 carries an explicit `risk_accepted: true` with a named owner in the risk register. That is a **documented acceptance with residual risk**, not a claim the risk is gone.

- **C3b — P1, `open`, `risk_accepted: true` (owner: engineering).** Tenant selection remains client-controlled at login (`X-Tenant-Scheme`). A minimal guard now rejects unknown and reserved schemes (login 400s otherwise), but the schema has no user↔org membership model — the `users` table has no `organization_id` — so an authenticated admin can still mint a token for any *existing* org. Binding users to orgs needs a product/data-model decision (membership table), deliberately outside this fix batch. **Residual risk accepted for v1.0.0 and named for the release decision.**
- **P2/P3 items** (B5, A3, A1, U3, C2, EDGE-1, A2, B7, B8, ASYNC-1) are all recorded `open` + `risk_accepted: true`, each with impact and rationale in the risk register. None were fixed; none hide behind a green build. Summary: fit/gap degrades to explicit `not_assessed` on fuzzy skill ids (never a wrong level); missing `failed` status chips; cosmetic type drift; lost login error message; unverified JWT decode as a tenant hint (no bypass proven); fit/gap 500 on a zero-skill vacancy (fails loudly); one cosmetic render; storage hygiene; a broken dev-console helper; a mislabeled `system_prompt_generated` flag.

No known check was weakened or deleted to make this release green. Full detail: `assessment/02-quality-system.md` → "Not covered / not fixed" and `assessment/risk-register.json`.

## The release decision

The formal release decision — what the gate checked, what it found, the recommendation, and the risk owner — is recorded in [`assessment/03-release-decision.md`](assessment/03-release-decision.md). That document lands with the gate run for this tag and must agree with the actual workflow status and the register state above. If any P0/P1 were open *without* `risk_accepted: true`, the honest status would be `blocked`; for this tag the register's accepted C3b is the named residual risk.

## Audit trail

| Artifact | Contents |
|----------|----------|
| [`assessment/01-audit.md`](assessment/01-audit.md) | Baseline audit: ranked P1–P3 list with impact, how-found (repro/code citation), missing-spec vs built-wrong split, systemic patterns, and the ship / do-not-ship line (do-not-ship as-is, at baseline). |
| [`assessment/risk-register.json`](assessment/risk-register.json) | Machine-readable twin (`id`, `severity`, `status`, `owner`, `risk_accepted`) — the single source the release gate parses. |
| [`assessment/02-quality-system.md`](assessment/02-quality-system.md) | The net: design, run/extend instructions, per-check protections **and** non-protections, red→green per fixed defect, known limits, not-covered/not-fixed list. |
| [`assessment/03-release-decision.md`](assessment/03-release-decision.md) | Release decision for `v1.0.0` (gate output + register state + recommendation + risk owner). |

## Verification

```bash
git tag -v v1.0.0                                        # annotated tag verification
gh api repos/masrayfa/masrayfa-quality-net/git/refs/tags/v1.0.0
gh run list --workflow=release-gate.yml                  # the tag-triggered gate run
gh run view <run-id>                                     # RELEASABLE/BLOCKED verdict + status on the tag commit
```
