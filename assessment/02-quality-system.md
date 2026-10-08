# Assessment: quality net

**Date:** 2026-10-08
**Scope:** the CI net built for this repo (`api/` + `web/`) and what it does and does not guard
**Part:** 1 of 2. This document describes the net as built. The red-to-green story is in the next section placeholder below and is written once the fixes land.

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
- Several confirmed defects (notably the generator's non-transactional save, B2) have no committed red test yet at this baseline. They are in the risk register; their red arrives with their fix.
- The release gate does not exist in this document's commit; it is specified in Task 4 and depends on `assessment/risk-register.json` remaining in-repo and up to date.

## Red-to-green

<!-- Placeholder. Part 2 of this write-up, written after the confirmed defects are fixed:
     each defect id, the red test that pins it, the fix, the green run, and the
     evidence path under .omo/evidence/. -->
