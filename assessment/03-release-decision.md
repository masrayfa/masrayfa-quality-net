# Assessment: release decision for v1.0.0

**Date:** 2026-10-08
**Tag:** `v1.0.0` (annotated; peels to commit `2ab08dbc3c6941d2e72af9857f8ba6f2d78004a6`)
**Decision:** **RELEASABLE** — shipped with one explicitly accepted open P1 (C3b), named owner, and a documented path to close it.

This is a neutral portfolio piece. No client, product, or source-repo names appear here.

## What the gate checked

The release gate is tag-triggered (`.github/workflows/release-gate.yml`, script `.github/scripts/release-gate.cjs`). It ran two checks and combined them with an AND:

1. **The CI net on the tag.** The workflow reuses `ci.yml` via `workflow_call`, so the full quality net ran on the tagged commit: the API suite (RSpec against real Postgres + Redis services) and the web suite (Vitest + a production build). Anything other than a green net fails the gate.
2. **The risk register P0/P1 rule.** The gate parses `assessment/risk-register.json` and blocks if any P0 or P1 entry is `status: "open"` without `risk_accepted: true`. Unknown statuses, an unreadable register, or a non-array register also block.

The gate fails closed in both directions: a crashed script, a failed net, or a malformed register all produce BLOCKED, never a silent pass. The verdict is posted as a commit status (`release-gate`) on the tagged commit, so the decision is visible on the commit that shipped, not just in a log.

## What it found

**The net is green on the tag.** All three jobs succeeded in run 37731170653: `quality_net / api` (RSpec green), `quality_net / web` (npm ci + Vitest + build green), and the `release-gate` job itself (verdict computed and published). The register at tag time parsed clean: 18 items, no unaccepted open P0/P1.

**P1s fixed before the tag.** Seven confirmed P1s are `status: "fixed"` in the register, each with a regression lock or a verified fix in evidence 29-fixes.txt:

| ID | What changed |
| --- | --- |
| B1 | `audio_complete` no longer trusts the client for `end_reason=all_covered` |
| B2 | Portfolio skill save is transactional (savepoint + pre-write validation) |
| A4 | Fit/gap contract aligned: engine emits `expected_level` / `is_override`, web reads them |
| B4 | Login tenant fallback is ordered and excludes the reserved `id=0` organization |
| U1 | Invalid or expired invite renders an error/expired state, never "Interview Complete" |
| F2 | Compose stack now runs a Sidekiq worker; queues drain (verified live) |
| ENF-1 | Confidence is enforced server-side against coverage maps, not just the prompt |

**The one open P1 is accepted, not ignored.** C3b (tenant selection is client-controlled at login) stays `status: "open"` with `risk_accepted: true` and a named owner (`engineering`). The fix batch added the minimal guard: the requested `X-Tenant-Scheme` must name an existing, non-reserved organization, or login returns 400. The residual risk is explicit in the register: the schema has no user-to-organization membership model (`users` has no `organization_id`), so an authenticated admin can still mint a token for any existing organization. That binding is a product/data-model decision, not something this fix batch invents.

**P2/P3 items are also accepted, per item.** B5, A3, A1, U3, C2, EDGE-1, A2, B7, B8, and ASYNC-1 remain open, each with `risk_accepted: true` and a one-line rationale in the register. None of them are P0/P1, so none of them gate the release on their own.

## The recommendation: RELEASABLE

The brief's rule is the standard: if any P0/P1 is open, the honest status is BLOCKED, or RELEASABLE only with explicit, documented risk acceptance and a named owner. Here that rule was applied literally:

- No P0 exists in the register at tag time.
- All seven confirmed P1 defects found in the audit are fixed, with regression locks.
- Exactly one P1 (C3b) is open. It is `risk_accepted: true`, the residual risk is spelled out in the register entry, and the owner is named: **engineering**.
- The gate's own machine check agrees: no unaccepted open P0/P1 → RELEASABLE.

So the honest call is RELEASABLE, with the caveat that RELEASABLE here means "known residual risk, explicitly accepted and owned", not "risk eliminated". Nothing was weakened to get the green verdict; the accepted risks are recorded, not hidden.

## Who owns the residual risk, and what closes it

**Owner:** engineering (C3b, and every other open register item).

**Residual risk, restated:** any authenticated user who is an admin for one organization can mint a token that resolves any existing organization's tenant scheme, because membership is not modeled in the schema.

**What a next release needs to close it:** a real user-to-organization membership model. Concretely, that means deciding and building a membership association (for example, an `organization_id` on users or a membership table with roles) so tenant resolution can be derived from the authenticated user's org membership instead of a client-supplied scheme header. That is a product and data-model decision, with migrations, auth-flow changes, and tests. Until it lands, C3b stays open with `risk_accepted: true`, and each subsequent release must re-state the acceptance rather than treating it as inherited silence.

C2 (JWT decoded without verification as a tenant hint) is recorded as deferred work that should ship alongside the same membership-model change.

## Run URL and commit status

- **Release-gate run:** https://github.com/masrayfa/masrayfa-quality-net/actions/runs/37731170653
  - Workflow `release-gate`, event: push of tag `v1.0.0`, head SHA `2ab08dbc3c6941d2e72af9857f8ba6f2d78004a6`, conclusion: success.
- **Commit status on the tagged commit:** context `release-gate`, state `success`, description `RELEASABLE v1.0.0: quality net green, no unaccepted open P0/P1`, target URL = the run above.
  - Verified via `gh api` on `commits/2ab08dbc3c6941d2e72af9857f8ba6f2d78004a6/status` after the run completed.
- **Local pre-flight (same policy, same verdict):** `node .github/scripts/release-gate.cjs --register assessment/risk-register.json --net success --tag v1.0.0` → RELEASABLE, exit 0.

## Evidence

- `.omo/evidence/33-tag.txt` — release notes, annotated tag, gate run, commit status.
- `.omo/evidence/29-fixes.txt` — red-first fix runs for F2, U1, ENF-1, C3b and the register diff.
- `assessment/risk-register.json` — the register the gate parses (18 items at tag time).
- `assessment/02-quality-system.md` — what each layer of the net checks and what it deliberately does not.
