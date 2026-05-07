---
name: persistence-boundaries
description: Use when Lineup Desktop work reads or writes persisted settings, app paths, secure storage, selected server state, credentials, local files, or browser storage.
---

# Persistence Boundaries

Use this only from the Lineup Desktop repo.

Read:

1. `AGENTS.md`
2. `docs/AGENTIC_DEV_WORKFLOW.md`
3. `docs/architecture/security-and-secret-flow.md`
4. `docs/architecture/CURRENT_STATE.md`

Keep persistence owned by the correct privileged layer:

- renderer may hold ephemeral renderer-safe UI state only
- preload may validate and translate calls but must not store secrets
- main/helper owns app paths, secure storage, credential access, and
  filesystem-backed state
- contracts must not expose tokens, auth headers, tokenized URLs, native handles,
  or raw persisted secret values

If persistence changes also touch Plex, renderer UI, or Electron process
ownership, load `plex-integration-boundaries`, `ui-composition-patterns`, or
`architecture-boundaries`.

Before implementation, define storage owner, key/schema shape, redaction rules,
migration or no-migration policy, and verification. Stop if the renderer needs
direct secret, filesystem, process, or raw browser-storage ownership.
