---
name: debugging-remediation
description: Use when Lineup Desktop has a bug, regression, failing test, unclear runtime symptom, Electron IPC issue, playback symptom, or user-reported behavior where the cause is unknown.
---

# Debugging Remediation

Use this only from the Lineup Desktop repo.

Read:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/architecture/CURRENT_STATE.md`
4. task-specific architecture docs for the suspected layer

Do not patch from intuition. First establish:

- exact symptom, expected behavior, and observed behavior
- affected layer: renderer, preload, main, helper, Plex, scheduler, packaging,
  persistence, tests, or workflow harness
- smallest reproduction, failing command, source audit, or manual proof
- likely owner boundary and at least one rejected alternative cause
- verification that will prove the fix

Stop and replan if the fix would change Electron privilege boundaries, secret
flow, native playback architecture, packaging gates, or copied upstream scope
beyond the approved plan.
