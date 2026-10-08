# Assessment index

Everything submitted for the take-home, in one place. Read this file first; each link resolves to a file or artifact that exists in this repo (verified by the scripted check in `.omo/evidence/36-index.txt`, outside the repo).

This is a neutral portfolio piece. No company, product, client, or source-repo names appear anywhere in these docs or the repo.

## Deliverables

| # | Deliverable | Path | What it is |
|---|-------------|------|------------|
| 1 | Platform audit | [`01-audit.md`](01-audit.md) | Severity-ranked risk list (P1–P3) with impact, how-found (repro or code citation), missing-spec vs built-wrong split, systemic patterns, and the ship / do-not-ship line at baseline. |
| 2 | Risk register | [`risk-register.json`](risk-register.json) | Machine-readable twin of the audit (`id`, `severity`, `status`, `owner`, `risk_accepted`). The release gate parses this file; it is the single source that decides `RELEASABLE` vs `BLOCKED`. |
| 3 | Quality system | [`02-quality-system.md`](02-quality-system.md) | What the net is, how to run and extend it, what each check protects **and** what it deliberately does not, the red→green story per fixed defect, and the explicit not-covered/not-fixed list. |
| 4 | Release decision | [`03-release-decision.md`](03-release-decision.md) | What the release gate checked, what it found, the recommendation, the named risk owner, and what would close the accepted residual risk. |
| 5 | Release notes | [`../RELEASE_NOTES.md`](../RELEASE_NOTES.md) | What `v1.0.0` claims to deliver: the net, the P1 fixes, the release gate itself, and the open risks accepted for the tag. |
| 6 | Assumptions | [`assumptions.md`](assumptions.md) | The ambiguity calls made during the work, each stated with the evidence behind it. |
| 7 | Defense notes | [`defense-notes.md`](defense-notes.md) | Live-defense prep: how AI was used and where it was corrected, key judgment calls (severity, ship/block, B3, P2/P3), red→green pointers, and anticipated CTO questions with crisp answers. Every claim traces to a repo artifact. |

## Repo artifacts (the net + the demos)

These are not documents; they are the working machinery the deliverables describe.

| Artifact | Path / link | What it is |
|----------|-------------|------------|
| Workflow gate (PR) | [`.github/workflows/policy-gate.yml`](../.github/workflows/policy-gate.yml), [`.github/pull_request_template.md`](../.github/pull_request_template.md), [`.github/scripts/policy-gate.cjs`](../.github/scripts/policy-gate.cjs) | Definition-of-Ready/Done gate. Blocks PRs missing spec/AC/design/test sections, unchecked DoR items, an empty body, or a source change with no matching test-file change. Required status check on `main` for merges. |
| CI quality net | [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) | RSpec (api, with Postgres + Redis services) + Vitest + `tsc` + Vite build (web) on every push and PR; reusable by the release gate via `workflow_call`. |
| Release gate | [`.github/workflows/release-gate.yml`](../.github/workflows/release-gate.yml), [`.github/scripts/release-gate.cjs`](../.github/scripts/release-gate.cjs) | Tag-triggered (`v*` push). Re-runs the CI net on the tagged commit and parses `assessment/risk-register.json`; emits `RELEASABLE`/`BLOCKED` as a commit status tied to the tag. Fails closed. |
| Demo PR #1 (blocked) | [#1 — "Demo: change without required inputs"](https://github.com/masrayfa/masrayfa-quality-net/pull/1) (`demo/no-inputs`) | Source change with no linked spec/AC/test. `policy-gate` fails; left open with the red check visible. |
| Demo PR #2 (passed) | [#2 — "fix(web): keep login error visible when 401 arrives on /login (U3)"](https://github.com/masrayfa/masrayfa-quality-net/pull/2) (`demo/with-inputs`) | Change with linked inputs and a matching test. `policy-gate` and the CI net both pass; left open with green checks. |
| Release tag | [`v1.0.0`](https://github.com/masrayfa/masrayfa-quality-net/releases/tag/v1.0.0) (annotated, peels to `2ab08dbc3c6941d2e72af9857f8ba6f2d78004a6`) | The gated release. Gate run: [actions/runs/37731170653](https://github.com/masrayfa/masrayfa-quality-net/actions/runs/37731170653) → `RELEASABLE v1.0.0`. |

## Submission checklist

Every item below was checked to resolve to a real file or link before this index was committed. The scripted verification lives outside the repo at `.omo/evidence/36-index.txt`.

| Brief item | Where it lives | Resolves? |
|------------|----------------|-----------|
| Audit of the platform, severity-ranked | [`01-audit.md`](01-audit.md) | exists |
| Machine-readable risk register the gate reads | [`risk-register.json`](risk-register.json) | exists |
| Quality-system write-up (what the net is, red→green, not-fixed list) | [`02-quality-system.md`](02-quality-system.md) | exists |
| Definition-of-Ready workflow gate | `.github/workflows/policy-gate.yml` + PR template + gate script | exists |
| CI net running on every change | `.github/workflows/ci.yml` | exists |
| P0/P1 fixes to green with red-before evidence | `risk-register.json` entries `fixed` + red→green section of `02-quality-system.md` | exists |
| Two demonstration PRs (one blocked, one passed) | [PR #1](https://github.com/masrayfa/masrayfa-quality-net/pull/1) `policy-gate` FAILURE; [PR #2](https://github.com/masrayfa/masrayfa-quality-net/pull/2) `policy-gate` + CI SUCCESS | verified live via `gh pr list` |
| Release notes stating what the version claims | [`../RELEASE_NOTES.md`](../RELEASE_NOTES.md) | exists |
| Tag `v1.0.0` on the released commit | `git tag v1.0.0` → [tag page](https://github.com/masrayfa/masrayfa-quality-net/releases/tag/v1.0.0) | verified live via `gh api` |
| Release gate with legible `RELEASABLE`/`BLOCKED` status tied to the tag | `.github/workflows/release-gate.yml`; run [37731170653](https://github.com/masrayfa/masrayfa-quality-net/actions/runs/37731170653) → RELEASABLE | verified live |
| Release decision doc, honest about accepted risk | [`03-release-decision.md`](03-release-decision.md) | exists |
| Assumptions recorded | [`assumptions.md`](assumptions.md) | exists |
| Index linking every deliverable | this file | exists |
| Public, de-linked repo; no forbidden names in artifacts | `gh repo view --json visibility` = PUBLIC; confidentiality grep clean (evidence outside repo, todo 38) | verified |

## How to read this submission in order

1. [`01-audit.md`](01-audit.md) — what was wrong at baseline, ranked, with a ship line of **do-not-ship**.
2. [`02-quality-system.md`](02-quality-system.md) — the net that catches those risks, its limits, and the red→green proof per fix.
3. The two demo PRs above — the gate blocking a PR with no inputs, and passing one with them, on real checks.
4. [`../RELEASE_NOTES.md`](../RELEASE_NOTES.md) + [`03-release-decision.md`](03-release-decision.md) — what `v1.0.0` claims, what the gate found, and the one P1 left open with named acceptance (C3b).
5. [`risk-register.json`](risk-register.json) + [`assumptions.md`](assumptions.md) — the machine-readable statuses and the judgment calls behind them.
