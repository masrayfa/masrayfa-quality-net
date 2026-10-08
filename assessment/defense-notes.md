# Live defense notes (60–90 min)

**Purpose:** preparation for the live defense. Every claim below traces to an in-repo artifact (commit SHA, test file, assessment doc, or the risk register). Nothing relies on memory alone.

This is a neutral portfolio piece. No company, product, client, or source-repo names appear here.

## 1. How AI was used, and where it was corrected

The work was executed by an AI coding agent against a de-linked public copy of a Rails API plus React SPA. AI did recon, bootstrapping, the audit write-up, test authoring, fixes, CI wiring, and the release gate. It also got things wrong. The four corrections worth defending:

### 1a. Bootstrap DB-schema rename

The source code carried a product-flavored PostgreSQL schema name and index names. Scrubbing them was not cosmetic: a clean de-link required renaming the schema to `interview` and the two matching migration files to `create_interview_schema.rb` and `create_interview_users.rb`, plus the DB names used in seeds and Docker. The rename is visible in the initial-import commit on `main` and in `api/db/schema.rb` today (schema `interview`, table `interview.users`).

**Artifact:** initial import commit; `api/db/schema.rb`; `api/db/migrate/20240101000000_create_interview_schema.rb`.

### 1b. DatabaseCleaner nested-transaction gotcha (B2 fix)

The B2 defect was non-transactional portfolio skill persistence: a malformed later skill left earlier rows on a portfolio that then failed. The naive fix, `portfolio.transaction { ... }`, is wrong under the specs' DatabaseCleaner harness: the cleaner wraps examples in an outer transaction started `joinable: false`, and a plain nested `transaction` can be swallowed or miscounted under that setup. The shipped fix uses `portfolio.transaction(requires_new: true)` so the unit always gets a SAVEPOINT with an honest rollback, no matter what outer transaction exists.

The second root cause is the more interesting one, and it was found only while making the red test go green: records created through `portfolio.portfolio_skills.create!` stay cached in the association target. After a savepoint rollback, the failure path's `portfolio.update!(generation_status: "failed")` autosaves the cached record back, resurrecting the orphan row *after* a successful DB rollback. The SQL log showed `ROLLBACK TO SAVEPOINT` followed by a second `INSERT INTO portfolio_skills` inside the rescue's savepoint. The fix creates through `PortfolioSkill.create!(portfolio_id: portfolio.id, ...)` so autosave cannot replay the row.

**Artifact:** commit `b9df924` `fix(api): transactional portfolio persistence`; red test commit `2750114`; `api/app/services/portfolios/generator.rb` (transaction + `persist_skill!` validation + class-level create); `api/spec/services/portfolios/generator_spec.rb` (invalid skill deliberately second, so the red bites on the orphan).

### 1c. CI eager-load Zeitwerk boot bug (the net caught it)

The first pushed CI run failed *before any assertion ran*: `0 examples, 0 failures, 3 errors occurred outside of examples` with `NameError: uninitialized constant AudioWebsocketMiddleware`. CI sets `config.eager_load = ENV["CI"].present?`, and production eager-loads too, so this was a latent production-boot bug the net surfaced by simply booting the app the way production does. The file `audio_websocket_middleware.rb` defined `AudioWebSocketMiddleware`; Zeitwerk expects `AudioWebsocketMiddleware` from that filename. Fixed by renaming the two middleware files to Zeitwerk-compatible snake_case (`audio_web_socket_middleware.rb`, `coverage_web_socket_middleware.rb`) plus the `require_relative` lines in the initializers. No test or assertion was touched. After the rename, the same CI run executed the intended red set (B1 x2, B4, plus the web seam reds).

**Artifact:** commit `3aa639d` `fix(api): zeitwerk-compatible websocket middleware filenames`; the red baseline is CI run `37724650019` on `3aa639d`, documented in the "Red-to-green" section of `assessment/02-quality-system.md`.

### 1d. Branch-protection `enforce_admins` platform constraint

The plan asked for `required_status_checks=["policy-gate"]` plus `enforce_admins=true`. Applied as specified, classic GitHub branch protection rejected direct-to-main pushes with `GH006: Required status check "policy-gate" is expected` — chicken-and-egg: a new commit cannot carry a passing status before it is accepted. That conflicts with the brief's allowance for bulk direct commits to `main` during the build. The adaptation is one field: `enforce_admins` set to `false`, everything else unchanged. The required context stays `policy-gate` for PR merges; `ci` is deliberately not a required `main` check. The tradeoff is stated, not hidden: the repo admin bypasses the check for both direct pushes and PR merges; non-admin collaborators still require a green `policy-gate` before merging. Direct push was verified live on `main` (`ca6da4b`).

**Artifact:** `assessment/assumptions.md` §3; branch-protection JSON is recorded in the work ledger at `.omo/evidence/20-protection.txt` (outside the repo, by design).

## 2. Key judgment calls

### Severity ranking: data-integrity floor is P1

The delivery bar is: P0 blocker, P1 major, P2 minor, P3 cosmetic. The extra rule that drives the whole list: **any data-integrity issue is at least P1**, regardless of how exploitable it looks today. That rule is why C3b (client-controlled tenant scheme at login) sits at P1 even though some notes graded it P2 (hardening, no proven bypass of a protected route). Cross-tenant token minting is data integrity; the floor wins.

No P0s were found in the confirmed set. The baseline ship line was driven by eight open P1s, not by a missing P0.

**Artifacts:** `assessment/01-audit.md` (severity language + C3b row note); `assessment/risk-register.json`; `assessment/assumptions.md` §8.

### Ship / block: RELEASABLE with C3b risk-accepted + named owner

At baseline the honest line was **do-not-ship** (eight open P1s, three confirmed-red data-integrity defects, no worker in the delivery stack). At `v1.0.0` the gate and the register agree on **RELEASABLE**:

- No P0 in the register at tag time.
- Seven confirmed P1s fixed with regression locks or live verification (B1, B2, A4, B4, U1, F2, ENF-1).
- Exactly one P1 open: C3b, `risk_accepted: true`, owner `engineering`, residual risk spelled out in the register entry.

The gate policy is mechanical: RELEASABLE iff the CI net is green on the tag *and* the register has no open P0/P1 without `risk_accepted: true`. Malformed register or failed net → BLOCKED (fail closed). So RELEASABLE here means "known residual risk, explicitly accepted and owned", not "risk eliminated". Each later release must re-state the acceptance.

**Artifacts:** `assessment/03-release-decision.md`; `assessment/risk-register.json`; `.github/workflows/release-gate.yml` + `.github/scripts/release-gate.cjs`; tag `v1.0.0` peels to `2ab08db`.

### Why B3 is a regression lock, not a fix

B3 was a *candidate* defect during planning: the coverage state machine's hard rules (`probe_count >= 2` gate, forward-only transitions, `covered` terminal). During defect verification all 9 probes against the live engine passed. The rule was already enforced in `api/app/services/coverage/state_engine.rb`. The specs in `api/spec/services/coverage/state_engine_spec.rb` are therefore a regression lock: they pin already-correct behavior so a later refactor cannot silently loosen the gate, the chain, or the terminal state. No product code was changed for B3. Saying "fixed B3" would have been a lie; the red→green table keeps it in its own lane.

**Artifacts:** `assessment/02-quality-system.md` §"B3 — coverage rule verified correct"; `assessment/assumptions.md` §9; decision commit `680671a`; probe evidence `.omo/evidence/08-defects/index.md` (9/9) and `.omo/evidence/26-b3.txt`.

### Why P2/P3 are left open, risk-accepted

The plan scoped fixes to confirmed P0/P1. Ten P2/P3 items remain open (B5, A3, A1, U3, C2, EDGE-1, A2, B7, B8, ASYNC-1). Each is in `assessment/risk-register.json` with `status: "open"`, `risk_accepted: true`, a named owner, and a one-line rationale. They are named in the release decision and release notes anyway, so a reader sees them without digging. Where an item degrades behavior, the degradation is an explicit state (fit/gap → `not_assessed`, never a wrong level), not a silent wrong result.

**Artifacts:** `assessment/risk-register.json`; "Not covered / not fixed" in `assessment/02-quality-system.md`; `assessment/assumptions.md` §5.

## 3. The red→green story

Full write-up: [`02-quality-system.md`](02-quality-system.md) §"Red-to-green". The short version for the defense:

1. **The net went RED on its own.** CI run `37724650019` on `3aa639d` (after the Zeitwerk boot fix): api job `33 examples, 3 failures` (B1 x2, B4); web job `3 failed | 1 passed` (A4, A2, U7). Every failure was an assertion failure inside an example, not a boot or collection error. Baseline evidence: `.omo/evidence/21-net-red.txt`.
2. **Each fix has a red before and a green after.** Per-defect map (red test → fix commit → green evidence):

| Defect | Red test | Fix commit | Green evidence |
|---|---|---|---|
| B1 | `api/spec/requests/auth_and_session_scoping_spec.rb` x2 (zero + partial coverage) | `f778043` | `.omo/evidence/24-fix-b1.txt` |
| B2 | `api/spec/services/portfolios/generator_spec.rb` x2 (invalid 2nd skill) | `2750114` (red test), `b9df924` (fix) | `.omo/evidence/25-fix-b2.txt` |
| B4 | `auth_and_session_scoping_spec.rb` (reserved id=0) | `5f015cd` | `.omo/evidence/27-fix-b4.txt` |
| A4 | `web/src/test/seam.test.tsx` (Required column blank) | `a5ea4ba` | `.omo/evidence/28-fix-seam.txt` |
| A2 | `seam.test.tsx` (raw integer level) | `a5ea4ba` | `.omo/evidence/28-fix-seam.txt` |
| U1 | `web/src/test/interview-invite.test.tsx` x2 (false success) | `aca738e` | `.omo/evidence/29-fixes.txt` |
| ENF-1 | `generator_spec.rb` x4 (confidence caps) | `0a97048` | `.omo/evidence/29-fixes.txt` |
| C3b | auth specs x2 (scheme rejection) | `574e5ec` | `.omo/evidence/29-fixes.txt` |
| F2 | none (live probe, delivery env) | `86721ec` | `.omo/evidence/29-fixes.txt` (worker boot + drain) |
| B3 | n/a (verified correct) | `680671a` (decision doc) | `.omo/evidence/26-b3.txt` |

3. **No check was weakened to get green.** The B4 spec asserts the same expectation before and after its fix. Suites grew (api 33 → 46 examples, web 4 → 6) because fix commits added regression locks, not because failures were deleted. Final suites at HEAD: api `46 examples, 0 failures`, web `6 passed` + `tsc && vite build` exit 0.
4. **The gate proved causal, not decorative.** Demo PR #1 (`demo/no-inputs`, PR #1) is blocked by `policy-gate` (no linked spec/AC/test). Demo PR #2 (`demo/with-inputs`, PR #2) passes `policy-gate` *and* the CI net, on an all-green run. Both PRs are left open and visible.

## 4. Anticipated questions, crisp answers

**"How much of this was written by you vs generated by the AI?"**
AI wrote the code and docs under a plan I controlled; human owns the live defense and the final submit. The correction log above is the honest answer to "where the AI got it wrong": four places, each with a repo artifact (schema rename, `requires_new: true`, Zeitwerk rename, `enforce_admins=false`).

**"Why should I trust the red→green claim?"**
Every red is a captured failing run on a named commit and a named assertion; every green is a captured passing run on the fix commit. The map is in `assessment/02-quality-system.md`. Nothing claims green without a captured run. Where no red existed (A1, F2, B3), the docs say so explicitly.

**"The PR gate's test check is just a presence check. Isn't that gameable?"**
Yes, and it is documented as a deliberate limitation in `02-quality-system.md`. The gate enforces discipline of pairing (source change ⇒ test change). The real regression block is the CI test suite the PR must pass. The honest fix for quality is review plus the suite, not parsing test bodies in CI.

**"You shipped RELEASABLE with an open P1. Isn't that hiding risk?"**
No. C3b is `open` with `risk_accepted: true` in the machine-readable register the gate itself parses, owner named (engineering), residual risk spelled out in the entry, and called out in `03-release-decision.md`. The gate's own check is "no unaccepted open P0/P1". RELEASABLE means known accepted residual risk, not risk gone. A hidden risk would have been an open P0/P1 with `risk_accepted: false` and a green verdict, or a weakened test.

**"Why B4's fix but not C3b's full fix?"**
B4 is a one-line determinism fix (ordered fallback excluding reserved `id=0`). C3b's real fix needs a user-to-org membership model — a product/data-model decision (membership table or equivalent) with migrations, auth-flow changes, and tests. Inventing that mid-take-home without product input would be worse than shipping the minimal guard (scheme must name an existing, non-reserved org, else 400) and naming the residual. C2 (unverified JWT decode as tenant hint) is deferred with the same work.

**"Why is B3 in the red→green table at all?"**
It is not fixed; it is verified correct and locked. Keeping it in its own lane is the point: a table that implies a fix that never happened is a credibility problem. The regression lock exists so a refactor cannot silently loosen the coverage gate.

**"Why did CI go red on boot instead of on the tests you expected?"**
Because CI eager-loads the app, same as production. A filename/constant mismatch that local test runs (lazy-load) never hit blew up in CI. The net earning its keep. Fixed at `3aa639d`; no assertion was touched.

**"Why is Playwright missing?"**
Time-boxed omission, first MVP cut, recorded deliberately in `assumptions.md` §7 and `02-quality-system.md` (not-in-net list). The manual-equivalent is the agent-driven golden-path smoke against the Docker stack; web tests mock the service layer and prove component behavior given a payload shape, not that a deployed API emits it.

**"What would make you flip the release to BLOCKED?"**
Two things, both mechanical: (i) the CI net red on the tag, or (ii) a P0/P1 in the register `open` without `risk_accepted: true`. Both fail closed — a crashed gate script or unreadable register also yields BLOCKED.

**"What is the single worst residual risk after v1.0.0?"**
C3b: any authenticated admin can mint a token for any *existing* org, because membership is not modeled. It is accepted, owned, and named. The closure path is a membership model so tenant resolution derives from the authenticated user, not a client-supplied scheme header. Ship that together with C2.

**"Where would you start if you had one more day?"**
Close C3b with a real membership model (migration + auth flow + the existing C3b red tests extended to assert membership binding), then re-run the release gate so the register closes that item rather than re-accepting it. Second: add the Playwright seam smoke as the one net gap with the highest demo value.

## 5. One-page traceability (claim → artifact)

| Claim | Artifact |
|---|---|
| Audit ranked P1–P3 with ship line | `assessment/01-audit.md` |
| Machine-readable register the gate parses | `assessment/risk-register.json` |
| Net description + red→green + not-fixed list | `assessment/02-quality-system.md` |
| RELEASABLE decision + named owner | `assessment/03-release-decision.md` |
| Gate policy (AND of net green + register rule) | `.github/workflows/release-gate.yml`, `.github/scripts/release-gate.cjs` |
| Policy gate files + presence-only limitation | `.github/workflows/policy-gate.yml`, `.github/scripts/policy-gate.cjs`, `.github/pull_request_template.md` |
| CI net (api RSpec + web Vitest/build, workflow_call) | `.github/workflows/ci.yml` |
| Red baseline | CI run `37724650019` @ `3aa639d` |
| B1 fix | `f778043`, `api/spec/requests/auth_and_session_scoping_spec.rb` |
| B2 fix + requires_new + autosave root cause | `b9df924`, `api/app/services/portfolios/generator.rb`, `api/spec/services/portfolios/generator_spec.rb` |
| B4 fix | `5f015cd`, same request spec |
| A-seam fix | `a5ea4ba`, `web/src/test/seam.test.tsx`, `api/app/services/fit_gap/engine.rb` |
| U1 / ENF-1 / C3b / F2 fixes | `aca738e`, `0a97048`, `574e5ec`, `86721ec`; specs under `web/src/test/` and `api/spec/` |
| B3 regression lock | `api/spec/services/coverage/state_engine_spec.rb`, `api/app/services/coverage/state_engine.rb`, commit `680671a` |
| Severity floor + B3/P2/P3 judgments | `assessment/assumptions.md` |
| Demo PRs (blocked / passed) | PR #1 `demo/no-inputs`, PR #2 `demo/with-inputs` (left open) |
| Tag + gate run | `v1.0.0` → `2ab08db`; gate run `37731170653` → RELEASABLE |

Work-ledger evidence for each todo lives outside the repo under `.omo/evidence/` (by design, per the plan); the repo itself carries the commits, tests, and assessment docs the defense needs.
