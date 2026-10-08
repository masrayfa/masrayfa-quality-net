# Assessment: quality net

**Date:** 2026-10-08
**Scope:** the CI net built for this repo (`api/` + `web/`) and what it does and does not guard
**Part:** 1 of 2. Part 2, the red-to-green story, is the "Red-to-green" section below, written after the P0/P1 fixes landed.

This is a neutral portfolio piece. No client, product, or source-repo names appear here.

## What the net is

The quality net is the set of automated checks that must pass before this codebase can ship. It has three layers, from cheapest and bluntest to most specific:

1. **Process gate (pull requests).** A PR cannot merge unless it carries a filled Definition-of-Ready/Done body and pairs every source change with a test change.
2. **Test gate (every push and PR).** The API suite (RSpec against Postgres + Redis) and the web suite (Vitest + a production build) run on every push and pull request. The same jobs are reusable by the release gate via `workflow_call`.
3. **Release gate (tags, later).** A tag-triggered workflow reuses the test jobs and additionally reads the in-repo `assessment/risk-register.json`. See "How the pieces fit" below.

Each layer covers a different failure mode. The process gate catches *undisciplined changes* (no test, no rationale). The test gate catches *broken behavior on the paths we pinned*. The release gate catches *known unfixed risk shipping anyway*.

## How to run it

Everything runs the same way locally as it does in CI. No mocking of the test databases; the specs hit real Postgres and Redis.

```bash
# API: RSpec suite (coverage state machine + auth/tenant/session request specs)
docker compose run --rm -e RAILS_ENV=test api bundle exec rspec

# Web: Vitest in watch-off mode (what CI runs) + production build
cd web
npm run test -- --run
npm run build

# After changing anything under api/spec/ or api/app|config|db:
docker compose build api
```

The `docker compose build api` step is required after spec or schema changes because the test container must see the new code and migrations. The CI api job runs `bundle exec rails db:create db:migrate` (not `db:prepare`) before RSpec; migrations create the schema the app lives in and `schema.rb` alone does not carry it.

The policy gate can be exercised locally without opening a PR:

```bash
node .github/scripts/policy-gate.cjs <case.json>   # {"body": "...", "files": [...]}
```

Exit 0 means the Definition of Ready/Done is satisfied. Exit 1 means blocked; the reasons are printed to stderr.

## How to extend it

| You changed | Add the check here | Then |
|---|---|---|
| `api/app/**`, `api/config/**`, `api/db/**` | a request or service spec under `api/spec/` | `docker compose build api` and re-run RSpec |
| `web/src/**` | a Vitest test under `web/src/*.test.*` or `web/src/*.spec.*` | `npm run test -- --run` in `web/` |
| Anything that a seam consumer reads | a contract assertion in `web/src/test/seam.test.tsx` (API payload shape vs web consumer) | re-run web tests |
| The release risk list | an entry in `assessment/risk-register.json` | the release gate parses this file (below) |

The PR policy gate enforces the first two rows mechanically: any change under `api/app|api/config|api/db|web/src` without a concurrent change under `api/spec/` or a matching web test path is blocked.

## What each check protects, and what it does not

### 1. Policy gate (`.github/pull_request_template.md` + `.github/workflows/policy-gate.yml` + `.github/scripts/policy-gate.cjs`)

**Protects.** Every PR body must contain four non-empty sections: Spec/PRD, Acceptance criteria, Design plan, Test evidence. Every checklist item must be checked. Source changes without test changes are blocked. A missing or empty PR body fails closed. The workflow checks out the base commit, so a PR cannot rewrite the gate that judges it.

**Deliberately does not cover.** This is a *presence-only* test check. The gate sees that a file under `api/spec/` or `web/src/*.test.*` changed in the same PR. It does not open the file. It cannot tell whether the "test" is a real assertion, an empty describe block, or a `skip`. A PR can satisfy the gate by adding a one-line smoke test next to a risky change. The honest fix is review and the test gate below; the gate itself only enforces *discipline of pairing*, not *quality of the test*. That limitation is by design: parsing test bodies in CI would be a second test framework to maintain and would still be gameable.

Also outside its scope: anything under `api/lib`, `api/scripts`, or other trees not in its source regex. Those changes pass the gate untouched.

### 2. Test gate (`ci.yml`)

Two jobs, both on `ubuntu-latest`, both on `push`, `pull_request`, and `workflow_call`.

**`api` job.** Postgres 16 and Redis 7 as services with health checks. Ruby 3.3.2 with bundler cache. `db:create db:migrate`, then `bundle exec rspec`. This is the harness that proves the Rails app boots against a real database and runs the suites below.

**`web` job.** Node 20 with npm cache, `npm ci`, `npm run test -- --run` (Vitest + React Testing Library in jsdom), then `npm run build`. The build step catches type and bundling breakage that tests alone miss.

**Protects.** Regressions on the paths the specs actually exercise (next section). Contract drift between the API payload and the web consumer, when pinned. Broken CI assumptions (missing services, bad env) because the jobs run against real dependencies, not mocks.

**Deliberately does not cover.** End-to-end browser flows against a running stack. The web tests mock the service layer; they prove component behavior given a payload shape, not that the deployed API emits that shape. That is why the seam specs pin the *real* persisted shapes (copied from the engine/controller code) rather than idealized types. Also uncovered: performance, load, and security probing beyond the auth/tenant specs, and any path not named in the specs below.

### 3. The specs themselves (`api/spec/**`, `web/src/test/**`)

**`api/spec/services/coverage/state_engine_spec.rb`** — the coverage state machine. Pins the PRD rule that `probe_count < 2` blocks any transition past `initiated`, that the chain is forward-only (`not_yet → initiated → partial → covered`), that skip-ahead and backward proposals are rejected, that `covered` is terminal, and that `resolve_state` walks one step at a time rather than jumping. This suite is expected green; it locks behavior that was already correct so a later refactor cannot silently loosen it.

**Does not cover.** Who calls the state machine, or what happens when an LLM response arrives with inconsistent data. That lives in the generator path (see the risk register), not here.

**`api/spec/requests/auth_and_session_scoping_spec.rb`** — auth, tenant scoping, candidate routes, session end. Includes two **expected-red** suites that document known defects as failing tests rather than leaving them undocumented:

- **B1** — `POST /api/v1/sessions/:token/audio_complete` must not record `end_reason=all_covered` when the session has zero or partial coverage. The server currently trusts the client claim.
- **B4** — login tenant fallback must never bind the reserved `id=0` org and must be deterministic with multiple orgs present. The current fallback is `SELECT scheme FROM organizations LIMIT 1` with no `ORDER BY` and no id guard.

The same file also pins green behavior: assessor-only routes reject non-assessor roles with 403, candidate routes work on invite tokens without JWT and 404 on bad tokens, and cross-tenant session reads 404 while the owning tenant gets a 200.

**Does not cover.** The full JWT verification path (C2: unverified token used for tenant selection was found by live probe, not by this suite). Tenant binding at login beyond the fallback (C3b). Background job behavior.

**`web/src/test/harness.test.tsx`** — proves Vitest, jsdom, RTL, and jest-dom matchers are wired. A boot smoke, not a product assertion.

**`web/src/test/seam.test.tsx`** — contract checks between API payloads and web consumers. Three pinned checks, all **expected-red** on current code:

- **A4** — fit/gap comparison: the API engine persists `expected_level` and never emits `is_override`; the web `ComparisonTable` reads `required_level` / `is_override`, so the Required column is blank.
- **A2** — portfolio skill levels: the API serializes `ai_level` as an integer; the page renders it raw instead of an L-label.
- **U7** — portfolio generating state: the API returns `{status:"generating"}` when the portfolio is not ready; the page only handles `{portfolio}` and goes blank.

**Does not cover.** Visual regression, accessibility, or any page whose consumer behavior is not named here. The seam tests assert on mocked service responses whose *shapes* were copied from the real controllers; they do not run the Rails stack.

### 4. Release gate (design; implemented later in this project's Task 4)

The release gate reuses `ci.yml` via `workflow_call` and adds one more condition: it parses the in-repo **`assessment/risk-register.json`** (written during the audit phase) and blocks the release if any P0/P1 entry is still `status: open` without `risk_accepted: true`.

**Protects.** Shipping code while known high-severity defects are still open, even if the tests happen to pass (for example, a risk that has no committed test yet). The register is the machine-readable twin of the audit write-up; the gate reads the file, never any out-of-repo evidence.

**Deliberately does not cover.** Anything not in the register. A new defect that nobody filed does not block the tag. The test net may still catch it; the register only tracks what has been found and triaged.

## Why coverage targets risk paths, not a percentage

There is no line-coverage number in this net, and that is intentional. A percentage tells you how much code was *executed*, not which decisions were *checked*. This codebase's failure modes are concentrated in a few places: the coverage state machine's hard rules, session-end authority, tenant fallback determinism, and the fit/gap contract between the API engine and the web consumer. Those are the paths the specs pin, each with an explicit assertion that fails if the rule is loosened.

A 90% coverage number could be reached by covering the happy path of every controller and still miss the fact that `audio_complete` trusts the client, that `LIMIT 1` binds the reserved org, or that `expected_level` and `required_level` are different keys. The net's job is to make those specific mistakes impossible to land silently, not to maximize executed lines.

If a new risk is found (the risk register is the list), the response is a new spec on that path, not a coverage hunt.

## How the pieces fit

```
PR opened
  └─ policy-gate  ── checks PR body sections + test/source pairing  (presence only)
Push / PR / workflow_call
  └─ ci.yml
       ├─ api:  Postgres + Redis + db:migrate + RSpec
       └─ web:  npm ci + Vitest + npm run build
Tag v*
  └─ release-gate (later)
       ├─ reuses ci.yml via workflow_call
       └─ parses assessment/risk-register.json; BLOCKED if P0/P1 open and not risk-accepted
```

The policy gate is the outermost, cheapest layer. The test gate is where behavior is actually asserted. The release gate is the last stop, and it only knows what the register says.

## Known limits of the net

Summarized, because a net that oversells itself is worse than no net:

- The PR gate's test check is presence-only. It cannot judge test quality.
- The web seam tests mock the API. They catch shape drift when someone updates the consumer or the mocked shape, not when the API silently changes at runtime.
- The release gate does not exist in this document's commit; it is specified in Task 4 and depends on `assessment/risk-register.json` remaining in-repo and up to date.

## Red-to-green

The net was built to fail on known defects before any fix landed. The red baseline is CI run `37724650019` on commit `3aa639d` (push to main): the api job failed with `33 examples, 3 failures` and the web job failed with `3 failed | 1 passed`. Every failure was an assertion failure inside an example, not a boot or collection error (proof and per-test defect map in `.omo/evidence/21-net-red.txt`).

The baseline red set, by defect id:

- **Red in the baseline run:** B1, B4, A4, A2, U7
- **Red via its own test+fix pair (not in the baseline run):** B2 (the plan put its red test with its fix)
- **Found by live probe, red test written with the fix:** U1, ENF-1, C3b
- **Delivery-stack defect, no test-net red:** F2
- **Verified correct, regression lock only:** B3 (see the section below this one)

What follows is each defect: what was red (test name), what changed (commit), what is green now. All evidence lives under `.omo/evidence/`.

### Fixed defects

#### B1, P1: `audio_complete` trusted the client's `all_covered` claim

**Red.** `api/spec/requests/auth_and_session_scoping_spec.rb`, two examples in CI run `37724650019` (lines 85 and 98 at that commit):

- "B1: POST /api/v1/sessions/:token/audio_complete (expected RED) does not record all_covered for a session with zero coverage maps"
- "B1: ... does not record all_covered for a session with incomplete (partial) coverage"

Both asserted `end_reason` must not be `all_covered`; the server recorded `all_covered` anyway (zero and partial coverage maps). Cause: `sessions_controller.rb` passed the reason straight through with no coverage read.

**Changed.** Commit `f778043` `fix(api): never assert all_covered without verification`. `audio_complete` now reconciles the client claim against the server coverage map (`Coverage::MapInjector#all_covered?`) before asserting `all_covered`. When coverage does not verify, the session still ends (no stall, the failure mode the old source comment warned about) but records the truthful reason `client_audio_complete`, added to the PG enum and `Session::END_REASONS`. The red specs were rewritten as strict regression locks plus a positive control.

**Green now.** B1 examples: `3 examples, 0 failures` (zero coverage and partial coverage both record `client_audio_complete`; fully covered records `all_covered`). Evidence: `.omo/evidence/24-fix-b1.txt`.

#### B2, P1: portfolio skill save was non-transactional

**Red.** No B2 example existed in the baseline CI run; the plan landed its red test with the fix (base `f778043`, red commit `2750114` `test(api): B2 portfolio persistence rollback (expected red)`). Failing examples in `api/spec/services/portfolios/generator_spec.rb`:

- "rolls back and leaves the portfolio failed when the 2nd skill confidence is invalid" (expected zero skill rows, found 1 orphan row)
- "rolls back and leaves the portfolio failed when the 2nd skill level is out of range" (generator must raise)

The invalid skill was deliberately second in the payload so the pre-fix code inserted the first row before raising. Cause: `portfolios/generator.rb#save_skills` wrote each skill with an independent `create!`, and silently clamped out-of-range levels into wrong-but-valid values.

**Changed.** Commit `b9df924` `fix(api): transactional portfolio persistence`. All skill writes run in `portfolio.transaction(requires_new: true)`. `persist_skill!` validates before writing (level must be an integer in 1..5, confidence must be in `high|medium|low`) and raises otherwise. A second root cause surfaced while making the spec green: records created through `portfolio.portfolio_skills.create!` stay in the association target and get autosaved back after a savepoint rollback; the fix creates through `PortfolioSkill.create!` so the rollback cannot replay.

**Green now.** `generator_spec.rb`: `3 examples, 0 failures` (invalid second confidence and out-of-range second level both raise, portfolio `failed`, zero rows; valid payload persists 3 rows). Evidence: `.omo/evidence/25-fix-b2.txt`.

#### B4, P1-conditional: login tenant fallback bound the reserved org

**Red.** `api/spec/requests/auth_and_session_scoping_spec.rb`, CI run `37724650019` (line 115 at that commit):

- "B4: POST /api/v1/auth/login tenant fallback (expected RED) never binds the reserved id=0 org and is deterministic with >= 2 orgs present"

With the reserved id=0 org inserted first, fallback bound scheme `default-reserved`. Cause: `authentication_controller.rb#resolve_scheme` ran `SELECT scheme FROM organizations LIMIT 1` with no `ORDER BY` and no id guard.

**Changed.** Commit `5f015cd` `fix(api): deterministic tenant scheme resolution`. Fallback is now `SELECT scheme FROM organizations WHERE id != 0 ORDER BY id LIMIT 1`. An explicit `X-Tenant-Scheme` header still wins; with only the reserved org present, login fails cleanly to a fallback scheme.

**Green now.** B4 examples: `2 examples, 0 failures` (deterministic with >= 2 orgs, never binds id=0; explicit header still wins). The test was not weakened. Full api suite after this fix: `37 examples, 0 failures`. Evidence: `.omo/evidence/27-fix-b4.txt`.

#### A4, P1: fit/gap contract drift (`expected_level` vs `required_level`)

**Red.** `web/src/test/seam.test.tsx`, CI run `37724650019` (line 70):

- "A4 — fit/gap comparison contract (API shape vs web consumer) > renders the Required column from the API's expected_level key"

Expected `L3`, received `""`. The API engine persisted `expected_level` and never emitted `is_override`; the web `ComparisonTable` read `required_level` / `is_override`, so `LEVEL_LABELS[undefined]` rendered blank.

**Changed.** Commit `a5ea4ba` `fix(web): align api contract types and consumers`. `ComparisonTable` reads `expected_level`; `web/src/types/index.ts` updated to the real persisted shape; `fit_gap/engine.rb` now emits an `is_override` marker alongside one key, with a comment pinning the contract.

**Green now.** Seam suite green in the same commit (`web/src/test/seam.test.tsx`, Required cell renders `L3`). Evidence: `.omo/evidence/28-fix-seam.txt`.

#### A2, P3 confirmed: discovered-skill line rendered a raw integer

**Red.** `web/src/test/seam.test.tsx`, CI run `37724650019` (line 117):

- "Portfolio/fit-gap consumer — portfolio skill levels from the real API > renders a discovered skill's integer ai_level as an L-label"

Expected `/L3/`, received raw `"3 (confirmed)"`. The API serializes `ai_level` as an integer; `FitGapReportPage` rendered it raw.

**Changed.** Same commit `a5ea4ba`. The page now renders through `parseLevel` / `LEVEL_LABELS`, and `ai_level` is typed `number | string` so both shapes compile and render as an L-label.

**Green now.** The pinned seam test passes (`L3` found). Note: `assessment/risk-register.json` still lists A2 as `open` with `risk_accepted: true` (P3, cosmetic). The test path is fixed; the register entry was left open in the todo-29 catch-up. Both facts are recorded, neither is hidden.

#### A1, P2: `skill_id` type drift (no red available)

**Red.** No red test. A1 was a static finding (API `skill_id` is varchar like `sk-eng-001`; the web type claimed number and `SkillCard` prefixed `SK-` again, so badges rendered `SK-sk-eng-001`). It never produced an assertion failure in the baseline.

**Changed.** Types and `SkillCard` were aligned in `a5ea4ba` (varchar `skill_id`, no double prefix). There is no red-to-green story here because no red test ever existed; the change is cosmetic and unguarded by the net.

**Green now.** No test pins A1. The register keeps A1 `open` + `risk_accepted: true` (P2, cosmetic label prefix, no data corruption).

#### A3, P2: status/portfolio union drift (not fixed)

No red test, no fix. The web status union omits `failed` and the portfolio union omits the failed-shape `error` key, so a failed session renders no chip and no action. Register: `open` + `risk_accepted: true` (cosmetic missing state; the row still renders and no false success is shown). Listed again under "Not covered / not fixed".

#### U1, P1: invalid invite shown as "Interview Complete"

**Red.** `web/src/test/interview-invite.test.tsx`, red-first run captured in `.omo/evidence/29-fixes.txt` before the fix commit:

- "shows an expired-link state on a 404 candidate_info, not the success screen" (rendered DOM was `✅ Interview Complete / Thank you. The interview has been recorded.`)
- "shows an error state (not success) when candidate_info fails for another reason" (same success screen)

**Changed.** Commit `aca738e` `fix(web): show expired state for invalid interview invites`. `InterviewPage` keeps a `loadError` state: 404 renders "Link invalid or expired", any other failure renders "We couldn't load this interview", and the success screen only appears for a real `session_status === "ended"`. The Vitest harness also shims a broken global `localStorage` in this shell (CI unaffected).

**Green now.** `interview-invite.test.tsx`: `2 passed`. Full web suite after all fixes: `6 passed`. Register: U1 `fixed`. Evidence: `.omo/evidence/29-fixes.txt`.

#### ENF-1, P1: confidence rules were prompt-only

**Red.** `api/spec/services/portfolios/generator_spec.rb`, red-first run in `.omo/evidence/29-fixes.txt`:

- "caps a claimed high to low when the skill has no coverage map" (expected `low`, got `high`)
- "caps a claimed high to low at probe_count 1 / initiated" (expected `low`, got `high`)
- "caps a claimed high to medium at probe_count 2 / partial" (expected `medium`, got `high`)
- "matches discovered skills by label and applies the same cap" (expected `medium`, got `high`)

The LLM confidence claim was persisted verbatim, so `probe_count=1` could store `confidence=high`.

**Changed.** Commit `0a97048` `fix(api): enforce confidence against coverage evidence`. `Portfolios::Generator#save_skills` caps the claim against the session's coverage maps: `high` needs `probe_count >= 3` AND `covered`; `medium` needs `probe_count == 2` OR `partial`; anything else (including no coverage map) is `low`; the cap never upgrades a conservative claim. Matching is by `skill_id` then label for configured skills and by label (case-insensitive) for discovered skills.

**Green now.** Targeted files `22 examples, 0 failures`. Full api suite: `46 examples, 0 failures`. Register: ENF-1 `fixed`. Evidence: `.omo/evidence/29-fixes.txt`.

#### C3b, P1: client-controlled tenant scheme (partial fix, residual accepted)

**Red.** Same generator/auth spec batch in `.omo/evidence/29-fixes.txt`:

- "rejects a scheme that no organization owns, without minting a token" (expected `400`, got `200`)
- "rejects the reserved id=0 organization scheme even though it exists" (expected `400`, got `200`)

An attacker-controlled `X-Tenant-Scheme` minted a token for any scheme string, including the reserved org's.

**Changed.** Commit `574e5ec` `fix(api): validate login tenant scheme`. An explicit `X-Tenant-Scheme` must name an existing, non-reserved org (`Organization.where.not(id: 0).where(scheme:)`), otherwise login is `400 Unknown tenant scheme`. The deterministic B4 fallback is unchanged.

**Green now.** Both rejection examples pass; targeted files `22 examples, 0 failures`. **Residual risk accepted:** the schema has no user-to-org membership model (`users` has no `organization_id`), so an authenticated admin can still mint a token for any *existing* org. Binding users to orgs needs a product/data-model decision and was not invented here. Register: C3b stays `open` with `risk_accepted: true` and the rationale in `summary`. Evidence: `.omo/evidence/29-fixes.txt`.

#### F2, P1: no Sidekiq worker in the delivery stack (delivery fix)

**Red.** None in the test net. F2 was found by live probe (`.omo/evidence/08-defects`): `docker-compose.yml` had only api, db, and redis, so every `perform_async` job stayed queued (`default:2` / `portfolio:2`), portfolios sat `generating` forever, and fit/gap and export were unreachable. No RSpec or Vitest example could catch a missing process; this was an environment defect, not a code-path defect.

**Changed.** Commit `86721ec` `fix: add sidekiq worker service to compose`. `docker-compose.yml` adds a `worker` service using the same api image and env (`bundle exec sidekiq -C config/sidekiq.yml`), with shared YAML anchors (`x-api-build`, `x-api-env`) so api and worker cannot drift.

**Green now.** Verified live, not by unit test: worker boots (`Sidekiq 7.3.10 connecting to Redis`), enqueued `PortfolioGeneratorWorker` jobs execute (`INFO: start` ... `INFO: done`), and the pre-existing stale queue drains on startup (sessions not-found are skipped; one session ran and failed with `KeyError: GEMINI_API_KEY`, which is expected in an environment with no Gemini key). Real portfolio generation still needs a `GEMINI_API_KEY`; automated tests inject a fake client (decision unchanged since todo 7). Register: F2 `fixed`. Evidence: `.omo/evidence/29-fixes.txt`.

#### C2, P2: unverified JWT decode as tenant hint (not fixed)

No red test. C2 was a live-probe finding: `JsonWebToken.decode_without_verification` feeds the tenant resolver. Protected routes still 401 without a valid token and candidate routes are unaffected, so no auth bypass was proven; only request-scoped `Current.organization` can be set from unverified claims. Register: `open` + `risk_accepted: true` as hardening, deferred with C3b's tenant-model work. Listed again under "Not covered / not fixed".

#### B3, candidate defect: coverage rule verified correct (not a defect)

Not red, not fixed, because there was nothing to fix. All 9 probes of `coverage/state_engine.rb` passed against the live engine during defect verification (`.omo/evidence/08-defects/index.md`, 9/9). The specs in `api/spec/services/coverage/state_engine_spec.rb` are a regression lock on already-correct behavior: probe-count gate, forward-only chain, `covered` terminal, one-step walk. Decision commit `680671a` `docs(assessment): B3 coverage rule verified correct`; evidence `.omo/evidence/26-b3.txt`. The full write-up is the section below.

### Not covered / not fixed

Everything below is in `assessment/risk-register.json` with `status: open` and `risk_accepted: true`, or is outside the net entirely. The release gate reads that register, so none of this is hidden behind a green build.

**P2, risk-accepted (not fixed):**

| Id | What | Why accepted |
|---|---|---|
| B5 | Fit/gap matching is exact-case `skill_id` then exact label; lowercase ids degrade to `not_assessed` | Degrades to an explicit `not_assessed`, never a wrong level |
| A3 | Web status union omits `failed`; portfolio union omits the failed-shape `error` key | Cosmetic missing state; no false success shown |
| A1 | `skill_id` type drift (types aligned in `a5ea4ba`, but no red test pins it) | Cosmetic label prefix; no data corruption |
| U3 | Wrong password on `/login` hits the global 401 interceptor and reloads the page, swallowing the error message | Login still fails closed; only the message is lost |
| C2 | JWT decoded without verification as a tenant hint | No bypass proven; hardening deferred with C3b |
| EDGE-1 | Vacancy with zero skills makes fit/gap raise and surfaces a 500 | Requires an empty vacancy; fails loudly, never a silent wrong result |

**P3, risk-accepted (not fixed):**

| Id | What | Why accepted |
|---|---|---|
| A2 | Register keeps A2 open even though the seam test path was fixed in `a5ea4ba` | Cosmetic; test green, register entry conservative |
| B7 | Three indexes on `coverage_maps.session_id` | Storage/write hygiene only |
| B8 | `.irbrc` filters a nonexistent `discarded_at` column | Developer-console helper only; no runtime impact |
| ASYNC-1 | `system_prompt_generated:true` returned synchronously while the generator runs async | F2 now guarantees the job runs; the flag still mislabels timing |

**P1, residual accepted (partial fix):**

| Id | What | Why accepted |
|---|---|---|
| C3b | No user-to-org membership model; an admin can still mint a token for any existing org | Needs a product/data-model decision; minimal 400 guard shipped; named for the release decision |

**Not in the net at all:**

- Browser end-to-end smoke (Playwright) was deliberately omitted (time-boxed decision, todo 17). The web tests mock the service layer; they prove component behavior given a payload shape, not that a deployed API emits it. A manual-equivalent path is the golden-path smoke (todo 7 / final wave F3), not an automated browser test.
- Performance, load, and security probing beyond the auth/tenant specs.
- Any path not named in the specs above. A new risk does not block a release unless it is added to `assessment/risk-register.json`.

### Final full-suite results (red to green)

Same commands, same databases, red baseline versus current HEAD:

| | Red baseline (run `37724650019`, `3aa639d`) | Current (HEAD `1c135aa`, 2026-10-08) |
|---|---|---|
| api, `docker compose run --rm -e RAILS_ENV=test api bundle exec rspec` | `33 examples, 3 failures` (B1 x2, B4) | `46 examples, 0 failures`, exit 0 |
| web, `npm run test -- --run` | `3 failed \| 1 passed` (A4, A2, U7) | `Test Files 3 passed (3)`, `Tests 6 passed (6)`, exit 0 |
| web, `npm run build` | skipped (test job short-circuits on red) | `tsc && vite build` exit 0, 1842 modules |

The api suite grew from 33 to 46 examples because the fix batch added regression locks (B1 strict reasons, B2 rollback, B4 deterministic fallback, ENF-1 confidence caps, C3b scheme validation). The web suite grew from 4 to 6 examples (U1 invite error states). No check was deleted or weakened to reach green; the B4 spec in particular asserts the same thing before and after its fix (`.omo/evidence/27-fix-b4.txt`: "Test unchanged (not weakened)").

Traceability, red test to fix commit to green evidence:

| Defect | Red test | Fix commit | Green evidence |
|---|---|---|---|
| B1 | `auth_and_session_scoping_spec.rb` x2 (zero + partial coverage) | `f778043` | `.omo/evidence/24-fix-b1.txt` |
| B2 | `generator_spec.rb` x2 (invalid 2nd skill) | `2750114` (red test), `b9df924` (fix) | `.omo/evidence/25-fix-b2.txt` |
| B4 | `auth_and_session_scoping_spec.rb` (reserved id=0) | `5f015cd` | `.omo/evidence/27-fix-b4.txt` |
| A4 | `seam.test.tsx` (Required column blank) | `a5ea4ba` | `.omo/evidence/28-fix-seam.txt` |
| A2 | `seam.test.tsx` (raw integer level) | `a5ea4ba` | `.omo/evidence/28-fix-seam.txt` |
| U1 | `interview-invite.test.tsx` x2 (false success) | `aca738e` | `.omo/evidence/29-fixes.txt` |
| ENF-1 | `generator_spec.rb` x4 (confidence caps) | `0a97048` | `.omo/evidence/29-fixes.txt` |
| C3b | auth specs x2 (scheme rejection) | `574e5ec` | `.omo/evidence/29-fixes.txt` |
| F2 | none (live probe) | `86721ec` | `.omo/evidence/29-fixes.txt` (worker boot + drain) |
| B3 | n/a (verified correct) | `680671a` (decision doc) | `.omo/evidence/26-b3.txt` |

Red baseline evidence: `.omo/evidence/21-net-red.txt`. This section's own evidence: `.omo/evidence/30-red-to-green.txt`.

## B3 — coverage rule verified correct

The coverage transition rules are enforced in `api/app/services/coverage/state_engine.rb`:
- no advance past `initiated` unless `probe_count ≥ 2` (the hard gate);
- transitions are forward-only (`not_yet → initiated → partial → covered`);
- `covered` is terminal (no outgoing transition);
- skip-ahead proposals walk one step at a time rather than jumping.

B3 was treated as a candidate defect during planning and then empirically verified
**correct** during defect verification (todo 8): all 9 probes passed against the live
engine (`.omo/evidence/08-defects/index.md`, 9/9 pass; source `state_engine.rb`).

The tests in `api/spec/services/coverage/state_engine_spec.rb` are therefore a
**regression lock, not a bug fix**. They pin already-correct behavior so a later
refactor cannot silently loosen the probe-count gate, the forward-only chain, or the
`covered` terminal state. No product-code change was made for B3.

Decision + green re-run evidence: `.omo/evidence/26-b3.txt`.
