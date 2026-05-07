# Import Ledger

Every copied or adapted upstream Lineup slice must be recorded here before or in
the same change that imports it.

## Required Fields

| Field | Meaning |
| --- | --- |
| Source path | Upstream repo path or source document |
| Source commit/date | Upstream commit, branch, or exact source date |
| Imported files/symbols | Files or symbols copied/adapted into this repo |
| Desktop owner | Owning module or document in this repo |
| Adaptation summary | What changed and why |
| Retained tests | Tests copied or preserved from upstream |
| New tests needed | Desktop-specific proof still required |
| Platform assumptions | WebOS/browser assumptions removed, isolated, or pending |
| Divergence rationale | Why copy/adapt is better than exact sharing for now |
| Provenance notes | License or binary/source provenance notes |
| Follow-up trigger | When to revisit, extract, or replan |

## Entries

| Source path | Source commit/date | Imported files/symbols | Desktop owner | Adaptation summary | Retained tests | New tests needed | Platform assumptions | Divergence rationale | Provenance notes | Follow-up trigger |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `docs/architecture/desktop-repo-genesis-adr.md` from upstream Lineup workspace | 2026-05-07, upstream base `08c4e0fe` plus reviewed local ADR | `docs/architecture/desktop-repo-genesis-adr.md` | Architecture docs | Adapted links and wording for this separate repo; removed upstream cleanup-control references as active authority | Current repo `npm run verify:docs` passed before scaffold | Keep this repo `verify:docs` passing | Upstream webOS/current cleanup state is evidence only | Separate repo needs local authority without importing upstream control-plane baggage | Apache-2.0 project source | Revisit if repo shape, playback hypothesis, or secret ownership changes |
| Upstream Lineup workflow conventions | 2026-05-07, upstream base `08c4e0fe` | `AGENTS.md`, `docs/AGENTIC_DEV_WORKFLOW.md`, `docs/agentic/*` | Workflow/control plane | Ported steady-state feature workflow and review discipline; omitted historical cleanup program mechanics | Current repo docs verifier informed structure | This repo docs verifier and harness tests | Upstream webOS verification routing adapted to desktop scaffold | Desktop needs workflow from day one, but not exact upstream cleanup history | Apache-2.0 project source | Revisit after first workflow-harness review |
| Upstream Lineup Codex role convention | 2026-05-07, upstream base `08c4e0fe` | `.codex/config.toml`, `.codex/agents/*.toml` | Codex role config | Adapted conservative role set for Desktop; omitted dedicated maintenance-worker role until this repo has its own need | None | `npm run verify:docs`; role configs reviewed as control-plane surface | Upstream role text had web app history; Desktop role text is product-neutral and anti-overengineering | Codex roles are repo-local config, not shared package code | Apache-2.0 project source | Revisit after first Tier 3 Desktop plan and implementation |
| Upstream Lineup Codanna convention | 2026-05-07, upstream base `08c4e0fe` | `.codannaignore`, `docs/agentic/codanna-playbook.md` | Discovery workflow | Adapted to path-agnostic Desktop guidance; did not copy generated `.codanna/` index or absolute settings | None | `npm run verify:docs` | Old index paths were tied to the upstream checkout | Desktop needs discovery rules, not old generated state | Apache-2.0 project source | Revisit when a fresh Desktop Codanna index is initialized |
| Upstream Lineup review and repo-hosting conventions | 2026-05-07, upstream base `08c4e0fe` | `.coderabbit.yaml`, `.github/**`, `SECURITY.md`, `LICENSE`, `.editorconfig` | Repo hosting and review config | Rewritten for Desktop Electron boundaries, Windows CI, pre-release security policy, and current verification scripts | None | `npm run verify`; future GitHub CI runs `npm run verify` on Linux and Windows | Old webOS jobs and path instructions were not copied | Desktop needs own review/CI surface before product code | Apache-2.0 project source | Revisit after Electron dependencies and runtime smoke tests exist |
| Upstream Lineup architecture-lint pattern | 2026-05-07, upstream base `08c4e0fe` | `eslint.config.js`, `tools/architecture-rules/*`, `tools/__tests__/build-eslint-architecture-rules.test.mjs` | Architecture verification | Rebuilt as first-pass Electron boundary linting instead of copying web app module rules | Harness tests for rule builder | `npm run verify:architecture`; `npm run test:harness-docs` | Old webOS module roots are not Desktop roots | Desktop needs boundary linting shaped around renderer/preload/main/native-helper | Apache-2.0 project source | Revisit when source directories are created and real Electron imports land |
