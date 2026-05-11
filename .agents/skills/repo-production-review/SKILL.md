---
name: repo-production-review
description: Lineup Desktop wrapper for the global repo-production-review suite. Use for read-only production code-health reviews of this repo with local workflow, role, verification, and orchestration constraints.
---

# repo-production-review

Thin Lineup Desktop wrapper for the global `repo-production-review` skill suite.

## Local Required Reads

Before running the universal review, read and honor:

- `AGENTS.md`
- `docs/AGENTIC_DEV_WORKFLOW.md`
- `.codex/config.toml`
- `.agents/skills/*/SKILL.md`
- `docs/architecture/CURRENT_STATE.md`
- `docs/architecture/desktop-repo-genesis-adr.md`
- `docs/roadmap/desktop-port-roadmap.md`
- `docs/architecture/import-ledger.md`
- the tracked production-review launcher document, if present

Also open and follow the global orchestrator at:

- `/Users/tristan/.codex/skills/repo-production-review/SKILL.md`

## Local Role Constraints

- `explorer`: bounded read-only evidence discovery.
- `explorer_fallback`: only when `explorer` is unavailable.
- `reviewer`: read-only adversarial review and severity/confidence calibration.
- `docs_researcher`: read-only official API/framework/platform documentation checks.
- `planner`: remediation planning only after accepted findings.
- `monitor`: observation of safe long-running commands only.
- `monitor_fallback`: only when `monitor` is unavailable.
- `worker`: not used during the read-only review pass.

Honor local orchestration limits:

- `max_threads = 6`
- `max_depth = 1`

## Local Review Boundary

The review remains read-only:

- no product-code changes,
- no test changes,
- no dependency or lockfile changes,
- no config changes,
- no docs changes unless explicitly approved as a planning artifact,
- no patches,
- no implementation work.

## Local Invocation Behavior

Run the global `repo-production-review` orchestrator. Use global specialist skills when installed:

- `repo-review-architecture-boundaries`
- `repo-review-correctness-failure-modes`
- `repo-review-maintainability-ai-debt`
- `repo-review-tests-ci-verification`
- `repo-review-security-privacy`
- `repo-review-build-release-supply-chain`
- `repo-review-ops-observability-config`
- `repo-review-performance-concurrency-reliability`
- `repo-review-docs-dx`
- `repo-review-evidence-calibration`

The final report must separate confirmed defects, inferred risks, subjective maintainability concerns, and insufficient-data items. Every material finding must include evidence, risk mechanism, severity, confidence, suggested verification, and remediation direction.

## Verification For Wrapper Changes

For changes to this wrapper or related control-plane docs, run the repo's documented committed-doc policy verification, normally `npm run verify:docs`, before calling the work complete.
