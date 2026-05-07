# Feature Review Launcher

Use this launcher for read-only adversarial review of Lineup Desktop plans or
implementations.

## Review Inputs

Accept either:

- a pasted `NEXT_SESSION_HANDOFF` block naming `TASK`, `PLAN`, `ARTIFACT`,
  `FILES`, and `MESSAGE`
- one short follow-up naming the plan, diff, commit, or run bundle to review

## Prioritize Findings

- security and secret-flow leaks
- renderer privilege or raw IPC exposure
- native playback/process lifecycle risks
- import ledger omissions
- feature quality guardrail regressions
- workflow/control-plane drift
- insufficient verification
- product implementation that landed before an approved plan
- scope widening beyond the approved execution unit

## Plan Review Criteria

Require clear goal, non-goals, architecture seam, files in/out of scope,
evidence, applicable feature quality guardrails, verification classification,
acceptance criteria, rollback notes, and replan triggers.

Treat a plan as not implementation-ready when a fresh implementer would need to
invent Electron, IPC, security, playback, persistence, packaging, import, or
verification policy.

## Implementation Review Criteria

Check the implementation against the approved plan and the desktop feature
quality guardrails. Push findings back to planning, not implementation, when the
defect is a missing decision, wrong owner, or boundary violation that cannot be
safely patched inside the approved plan.

## Output Contract

Lead with findings ordered by severity. Cite files and lines where possible.
Separate blockers from optional improvements. Say explicitly when no blockers
remain.

If another session is needed, end with one `NEXT_SESSION_HANDOFF`:

- plan findings route to `lineup-desktop-feature-plan`
- clean plan review routes to `lineup-desktop-feature-implement`
- fixable implementation findings route to `lineup-desktop-feature-implement`
- plan/decision implementation findings route to `lineup-desktop-feature-plan`
