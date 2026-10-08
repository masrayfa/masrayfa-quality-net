# Assumptions and ambiguity calls

The brief said assumptions are signal, so here are the calls that shaped the work. Each one names the ambiguity, the call made, and the evidence behind it. Nothing here was hidden behind a green build; the register and the release decision carry the residual risk.

This is a neutral portfolio piece. No company, product, client, or source-repo names appear anywhere in these docs or the repo.

## 1. No Gemini key in CI → tests inject a fake client

**Ambiguity:** automated tests need the LLM-backed paths (portfolio generation, fit/gap) exercised, but CI has no API key and live calls are forbidden in tests.

**Call:** every automated test injects a fake client (the generators already accept an injected `gemini_client:`). No test makes a live call. A real key remains optional for manual smoke only; the local worker stack runs without one, and a missing key surfaces as a handled error, not a hang.

**Evidence:** `.omo/evidence/07-golden-path.txt`; decision restated in `02-quality-system.md` (F2 green verification notes the expected `KeyError: GEMINI_API_KEY` in a key-less environment).

## 2. Web dev server port 5173 is taken on this machine → run on 5174

**Ambiguity:** the web README and `.env.example` assume the Vite default of 5173. On the machine this work ran on, that port is occupied by another process, so boot probes cannot bind it.

**Call:** local dev/probe runs use `vite --port 5174 --strictPort`. This is a local-runtime fact, not a product change: nothing in the repo was patched for it, CI is unaffected (the web job builds and tests, it never serves 5173), and the submitted deliverables never depend on the port number.

**Evidence:** `.omo/evidence/08-defects/vite-5174.log` (vite ready on `http://localhost:5174/`).

## 3. Branch protection: `enforce_admins=false` instead of the suggested `true`

**Ambiguity:** the plan suggested `enforce_admins=true` to harden the gate, while also requiring bulk direct commits to land on `main` during the build (the brief allows direct-to-main).

**Call:** those two goals conflict under classic branch protection. With `required_status_checks` on `main`, `enforce_admins=true` rejects direct pushes from everyone, including the build commits (`GH006: Required status check "policy-gate" is expected`). Final config: `required_status_checks={strict:false, contexts:["policy-gate"]}`, `enforce_admins:false`, no PR requirement for `main`. The gate still blocks **merges** through a PR that fails `policy-gate`; direct commits land, as the brief allows. `ci` is deliberately not a required `main` context.

**Evidence:** plan todo 20 adaptation note; `.omo/evidence/20-protection.txt` (protection JSON) and a live direct-push verification (`ca6da4b`).

## 4. B2's red test is colocated with its fix

**Ambiguity:** the red→green story asks for a failing run *before* each fix. Most fixes rode the bulk red baseline; B2 did not, because the baseline specs did not include the mid-write rollback case, and the plan wanted the invalid skill placed second so the red would actually bite.

**Call:** B2's red test was written as its own commit immediately before the fix, in the same spec file the fix validates (`api/spec/services/portfolios/generator_spec.rb`). That keeps the red-first history honest for B2 without rewriting the bulk baseline: commit `2750114` `test(api): B2 portfolio persistence rollback (expected red)` (2 of 3 examples fail, orphan row found) followed by `b9df924` `fix(api): transactional portfolio persistence` (3 of 3 green). The payload deliberately puts the invalid skill second, so pre-fix code persists the first row before raising, and the red assertion bites on the orphan.

**Evidence:** `.omo/evidence/25-fix-b2.txt` (before/after runs, fix diff, SQL-level savepoint rollback note).

## 5. P2 and P3 left open, each explicitly risk-accepted

**Ambiguity:** the plan scoped fixes to confirmed P0/P1 and said P2/P3 would be documented, not fixed, unless time remained. Ten such items exist (B5, A3, A1, U3, C2, EDGE-1, A2, B7, B8, ASYNC-1).

**Call:** none were fixed. Each is recorded in `assessment/risk-register.json` with `status: "open"`, `risk_accepted: true`, a named owner, and a one-line rationale. The release gate only *blocks* on open, unaccepted P0/P1, so these items do not flip the verdict; they are named in `RELEASE_NOTES.md` and `03-release-decision.md` anyway, so a reader sees them without digging. Where an item degraded somewhere, the degradation is an explicit state (e.g. fit/gap → `not_assessed`, never a wrong level), not a silent wrong result.

**Evidence:** `assessment/risk-register.json` (every P2/P3 entry); "Not covered / not fixed" section of `02-quality-system.md`.

## 6. C3b tenant-binding deferred, residual risk accepted

**Ambiguity:** the audit ranked cross-tenant token minting as P1: login takes a client-supplied `X-Tenant-Scheme`, and the schema has no user-to-organization membership model (`users` has no `organization_id`), so any authenticated admin can mint a token for any existing org. Fixing it properly is a product/data-model decision (membership table or equivalent), not a code patch.

**Call:** the fix batch shipped the minimal guard only — the requested scheme must name an existing, non-reserved org (reserved `id=0` rejected), otherwise login 400s. Real binding is deferred. The register keeps C3b `status: "open"` with `risk_accepted: true` and owner `engineering`, the residual risk is spelled out in the register entry, and the release decision names it as the one open P1 behind the `RELEASABLE` verdict. RELEASABLE here means "known residual risk, explicitly accepted and owned", not "risk eliminated". Each later release must re-state the acceptance.

**Evidence:** `risk-register.json` entry C3b; `03-release-decision.md` ("The one open P1 is accepted, not ignored" and "Who owns the residual risk").

## 7. Playwright e2e smoke omitted (time-boxed)

**Ambiguity:** the plan allowed one browser seam smoke, and also allowed dropping it as the first MVP cut if time ran short.

**Call:** omitted. Documented as a deliberate decision, not a gap discovered late: the web tests mock the service layer and prove component behavior given a payload shape, they do not prove a deployed API emits that shape. The manual-equivalent path is the golden-path smoke run against the Docker stack, which was executed agent-side rather than encoded as a Playwright spec. Recorded in `02-quality-system.md` under "Not in the net at all".

## 8. Severity floor: any data-integrity issue ranked ≥ P1

**Ambiguity:** the delivery bar defines P0 as blocker and P1 as major, but the probed severity of C3b was argued down in some notes to P2 (hardening, no proven bypass today).

**Call:** applied the delivery bar's data-integrity floor literally. C3b is ranked P1 in the audit and register because cross-tenant token minting is data integrity, even though no live bypass of a protected route was proven. No P0s were found in the confirmed set; the ship line at baseline was driven by the eight open P1s, not by a missing P0 category.

**Evidence:** `01-audit.md` ("P0 blocker, P1 major (any data-integrity issue is at least P1)") and the C3b row note.

## 9. B3 coverage state machine: verified correct, tests are a regression lock

**Ambiguity:** the coverage transition rules (`probe_count >= 2` gate, forward-only chain, `covered` terminal) were listed as a candidate defect (B3) before they were exercised.

**Call:** verified empirically correct against the live engine (9/9 probes passed). The specs that pin the rule are a **regression lock**, not a bug fix, and no product code was changed for B3. Recorded as "verified correct" in the audit, the quality-system doc, and the risk register story, so the red→green table does not imply a fix that never happened.

**Evidence:** `.omo/evidence/08-defects/index.md` (9/9), `.omo/evidence/26-b3.txt`, decision commit `680671a`.

---

*Each call above is visible somewhere in the submission: in the register, the quality-system doc, the release decision, or the demo PR checks. If a call looks wrong to you, the register entry or the evidence path is the place to argue it, not the absence of a record.*
