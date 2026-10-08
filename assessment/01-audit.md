# Assessment: platform audit

**Date:** 2026-10-07
**Scope:** monorepo with a Rails API (`api/`) and a React SPA (`web/`)
**Baseline:** pre-fix. Every item below is `open` at this commit.
**Machine-readable twin:** `assessment/risk-register.json` (parsed by the release gate)

## Ship / do-not-ship

**DO-NOT-SHIP as-is.** Eight P1 risks are open. Three of them are confirmed-red data-integrity defects: session end trusts the client, portfolio save is non-transactional, and the fit/gap contract drifts between API and web. The reviewed delivery stack also has no background worker, so portfolio generation never completes. Ship only after the confirmed-red set is fixed, a worker runs, and the release gate reads an all-green register.

## How this list works

Severity follows the delivery bar: P0 blocker, P1 major (any data-integrity issue is at least P1), P2 minor, P3 cosmetic. Each row carries a one-line impact (who or what is hurt), how it was found (repro steps or code citation), and a final status (`open` / `fixed` / `wont-fix`). All are `open` now. The list is ranked, not flat. The class column separates **built wrong** (spec defines it, the build does not match) from **missing/ambiguous spec** (nobody defined it) and **delivery env** (the stack around the code).

## Systemic patterns

These clusters share root causes. Fixing one row without the pattern leaves the siblings red.

1. **Client-truth trusted over server state.** The server accepts client claims without re-checking. B1 (client says "audio complete", server records `all_covered` with zero coverage). U1 (candidate page treats a 404 invite as a completed interview). U3 and U9 (failures swallowed into reloads or infinite retries).
2. **Contract drift: API payload vs web types.** The web declares shapes the API never emits. A4 (`expected_level` persisted, `required_level` read). A1 (`skill_id` typed number, stored varchar). A2 (`ai_level` string vs integer). A3 (status unions omit `failed` / `error`).
3. **Failure invisible to the user.** 4xx and 5xx responses become success screens, blank pages, or silent no-ops. U1 through U9 are this pattern on different pages.
4. **Prompt-only rules not code-enforced.** PRD confidence rules (high / medium / low from `probe_count` and state) live only in the LLM prompt; the server persists whatever comes back. ENF-1.
5. **Delivery env missing a worker.** `perform_async` jobs enqueue to Redis and never run in the compose stack, so portfolios stay `generating`. F2. A related contract lie: assessment create returns `system_prompt_generated: true` while the worker has not run (ASYNC-1).
6. **Non-deterministic fallback queries.** `SELECT scheme ... LIMIT 1` with no `ORDER BY` and no exclusion of the reserved org. B4.

## Ranked risk list

### P1 (8 open): fix before any client demo

| # | ID | Class | Impact (who or what is hurt) | How found | Status |
|---|----|-------|------------------------------|-----------|--------|
| 1 | **B1** | built wrong | A candidate, with no auth needed, can force-end any session by POSTing `audio_complete`. The session records `end_reason=all_covered` with zero coverage and portfolio generation runs on an empty interview. Hiring data lies. | Live probe: POST `/api/v1/sessions/:token/audio_complete` on a zero-coverage session returns ended + `all_covered`. Code: `sessions_controller.rb:118-129` (reason hardcoded at :127), `end_handler.rb:26-37`. PRD-02 defines `all_covered` as all configured skills covered. | open |
| 2 | **B2** | built wrong | Invalid LLM output on the 2nd skill leaves the 1st skill row persisted with the portfolio marked `failed`. Partial portfolios can be read as if they were complete. | Live probe: generator with a valid 1st skill and an invalid-confidence 2nd skill raises `RecordInvalid`, leaves 1 skill row, status `failed`. Code: `generator.rb:150-179` (no transaction around `save_skills`). | open |
| 3 | **A4** | built wrong | An assessor reviews fit/gap against a vacancy with the Required column blank for every skill, and the human-override marker can never render. The core review output is unusable. | Live payload plus browser: DB and API hold `{expected_level: 3}`, the screen shows an empty Required cell. Code: `engine.rb:58-66` emits `expected_level` and no `is_override`; `ComparisonTable.tsx:50,56` reads `required_level` / `is_override`; `types/index.ts:130-137`. A consumer replay printed `undefined` for the Required read. | open |
| 4 | **U1** | built wrong | A candidate who opens an invalid or expired invite is told the interview completed and was recorded. They believe a real interview happened; assessors see nothing. | Browser: network 404 on `candidate_info`, UI still renders the complete screen. Code: `InterviewPage.tsx:51` `.catch(() => setInterviewState("complete"))` then lines 230-241. | open |
| 5 | **B4** | built wrong | Login binds the wrong organization whenever the reserved `id=0` org row is physically first. Tokens carry the wrong tenant and tenant-scoped reads hit the wrong org. | Live probe with reserved `id=0` org first returns login scheme `default-reserved`. Code: `authentication_controller.rb:24-29` (`SELECT scheme FROM organizations LIMIT 1`, no `ORDER BY`, no `id != 0`). | open |
| 6 | **F2** | delivery env | In the reviewed compose stack there is no Sidekiq worker. Every `perform_async` job stays queued, portfolio stays `generating`, and fit/gap plus export are unreachable. The end-to-end product cannot be demoed. | `docker-compose.yml` runs api/db/redis only; `Procfile:2` declares a worker. Live queue sizes: default 2, portfolio 2. Golden path stalls at `202 {status:"generating"}`. | open |
| 7 | **C3b** | built wrong + missing spec | Tenant selection is client-controlled at login (`X-Tenant-Scheme`) with no user-to-org binding. Any authenticated admin can mint a valid token scoped to any existing org. Every tenant-scoped model is exposed the same way. | Live probe: login with `X-Tenant-Scheme: other-corp` returns a token scoped to `other-corp`. Code: `authentication_controller.rb:16,24-29`. Probe notes graded this P2; it is ranked P1 here under the delivery bar's data-integrity floor (cross-tenant access). | open |
| 8 | **ENF-1** | built wrong (unenforced rule) | Confidence labels (high / medium / low) are prompt-only. The server persists whatever the LLM returns, so a skill with `probe_count=1` can be stored as `high` confidence. Assessors read wrong confidence metadata. | Code and PRD trace: rules defined in PRD-01 section 5; `generator.rb:97-100` (prompt text), `generator.rb:150-178` (persists `confidence` verbatim). The schema enum constrains the value set, not the rule. | open |

### P2 (6 open)

| # | ID | Class | Impact | How found | Status |
|---|----|-------|--------|-----------|--------|
| 9 | **B5** | ambiguous spec | Fit/gap matching is exact-case `skill_id` then exact label. Realistic lowercase ids, including the generator prompt's own example, silently degrade to `not_assessed` and hide real gaps. | Live probe: lowercase id plus label variant returns `not_assessed` instead of `exceed`. Code: `engine.rb:88-91`, `generator.rb:106`. | open |
| 10 | **A3** | built wrong | A failed session renders no status chip and no action buttons. A failed portfolio shape's `error` key is absent from the web union. Operators cannot tell what happened. | Browser and types: `types/index.ts:42`, `sessions.ts:24` versus DB enums (`session_status` includes `failed`) and the controller's failed shape. | open |
| 11 | **A1** | built wrong | `skill_id` is typed `number` but stored as varchar `sk-eng-001`; `SkillCard` prefixes again, so badges render `SK-sk-eng-001`. | Browser on the assessment edit page with live data. Code: `types/index.ts:19`, `SkillCard.tsx:57`. | open |
| 12 | **U3** | built wrong | Wrong password on login: the global 401 interceptor redirects to `/login` while the user is already there, the page reloads, and the error message is never shown. The user sees a blank form with no explanation. | Browser: wrong password leads to a reload with no error state. Code: `api.ts:29-35`, `LoginPage.tsx:29-33`. | open |
| 13 | **C2** | hardening / ambiguous spec | JWT is decoded without verification to pick the tenant. Protected routes still 401 because auth verifies later, but `Current.organization` is set from unverified claims for the rest of the request. | Live probe: forged token returns 401 on protected routes. Code: `tenant_resolver_middleware.rb:42-51`. No exploit proven today. | open |
| 14 | **EDGE-1** | built wrong | A vacancy with zero skills makes fit/gap raise `RecordInvalid` ("Skill comparisons can't be blank") and surface a 500 instead of an empty-but-valid report. | Live probe with a fake Gemini client against a zero-skill vacancy. Code: `engine.rb` report update path. | open |

### P3 (4 open)

| # | ID | Class | Impact | How found | Status |
|---|----|-------|--------|-----------|--------|
| 15 | **A2** | built wrong | The discovered-skill line renders raw `3 (confirmed)` instead of `L3`. Cosmetic; other consumers tolerate both shapes. | Browser output. Code: `FitGapReportPage.tsx:196`, `types/index.ts:93`. | open |
| 16 | **B7** | hygiene | Three indexes on `coverage_maps.session_id` (one unique composite plus two redundant single columns). Write cost, no read benefit. | `schema.rb:80-82` plus a live `pg_indexes` probe. | open |
| 17 | **B8** | dev tooling | The `.irbrc` console helper filters `discarded_at IS NULL` on a table without that column; the helper always errors and `mint` falls back to scheme `unknown`. | Live console probe raised `UndefinedColumn`. `.irbrc:16,71`. | open |
| 18 | **ASYNC-1** | built wrong | Assessment create/update returns `system_prompt_generated: true` synchronously while the generator runs async, and per F2 never runs in this stack. The flag is a constant, not a fact. | Golden-path probe: the 201 response has `system_prompt_generated: true` and `system_prompt: null`. Code: `assessments_controller.rb:34,44`. | open |

## Missing / ambiguous spec (not built-wrong)

These are risks in their own right: nobody can say whether the behavior is correct because the PRD never defined it. They sit apart from the built-wrong rows above.

| ID | Severity | What is missing | Why it matters | Where it shows up |
|----|----------|-----------------|----------------|-------------------|
| SPEC-1 | P2 | Auth and tenant scheme resolution (login, admin gate, `X-Tenant-Scheme`) has no owning PRD rule. | B4 and C3b live here because nothing pinned deterministic, membership-checked scheme selection. | `authentication_controller.rb` |
| SPEC-2 | P2 | The assessor override flow (`portfolio_skills` override plus stale fit/gap invalidation) has no PRD rule, yet the fit/gap engine consumes overrides. | Override semantics (who, what levels, when it wins) are undefined, and the UI marker tied to A4 was never spec'd. | `portfolio_skills_controller.rb`, `engine.rb#effective_portfolio_skills` |
| SPEC-3 | P3 | The taxonomy read API is cited as a data source in the PRD but has no API contract. | Borderline orphan; latent only because one consumer exists. | `skill_taxonomies_controller.rb` |
| SPEC-4 | P3 | Pacing buckets (`ahead` / `on_track` / `behind` / `critical`), auto-advance of stale partials at `probe_count>=4`, and prompt rules 6-7 are built beyond the wiki PRD. | Implementation extensions, not silent drift. Classify them as product decisions and pin them in a spec, or remove them. | `map_injector.rb`, `coverage_analyzer_worker.rb`, `system_prompt_compiler.rb` |
| SPEC-5 | P3 | The PG enum `fit_result` is defined but no column references it (`skill_comparisons` is jsonb). | The result set is enforced only in app code; the DB-level check is absent. | `schema.rb:23` |

## Verified correct / checked and rejected

So the list is not only red. These were exercised and hold.

- **B3 (coverage state machine):** the `probe_count >= 2` gate, forward-only transitions, and covered-freeze all hold. Enforced in `state_engine.rb`; a live probe passed 9/9. Regression lock, not a new defect.
- **C3 vacancy scoping:** `Vacancy` includes `TenantScoped`; cross-tenant reads return 0 rows or 404. The tenancy *binding* issue is C3b above; the scoping itself is correct.
- **C1 committed secrets:** no live secret anywhere. Every secret-shaped value is a placeholder, an empty string, or an ENV reference. Topology disclosure in the k8s manifests is a P3 hygiene note, not a secret.
- **B6 admin seed:** fixed earlier (admin user seeded, login proven live). Treat as a regression lock.
- **Golden path up to pending:** health, login, assessment create, session create, invite token, `candidate_info` without JWT, coverage and transcript reads, and the negatives (no JWT to 401, invalid invite to 404) all behave. The break is downstream at portfolio generation (F2) and in the seams above.
- **Positive error handling** (evidence the error check is meaningful because some consumers pass): override save shows "Failed to save override", end-session shows "Failed to end session", assessment create and edit surface API error messages.

## Static-only, unconfirmed

These are plausible from source but were not exercised live. They are not ranked above and carry low confidence: invite create silent failure, portfolio fetch/export unhandled 422, monitor initial load unhandled, edit blank-overwrite, fitgap 202 blank page, and infinite audio retry on 404 (U9, adjacent to U1).

## What I would gate before a client sees this

1. Fix the three confirmed-red defects (B1, B2, A4) with regression tests that fail on the old code.
2. Add the worker to the delivery stack and re-run the golden path through portfolio, fit/gap, and export.
3. Bind users to orgs at login to close C3b, and make scheme fallback deterministic for B4.
4. Make the candidate page surface invite failures honestly (U1).
5. Enforce confidence rules inside `save_skills`, not only in the prompt (ENF-1).

---

*Severity language, ranked-list discipline, and the ship line follow the delivery bar. All repros were run against a local Docker stack; code citations point at paths in this repo. Statuses are `open` at this commit; subsequent fixes update this file and `assessment/risk-register.json`.*
