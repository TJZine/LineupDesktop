# Plans

Use this directory for active Lineup Desktop plans that need fresh-session
handoff memory.

Keep routine one-session work in `update_plan`. Promote a plan here only while
it is the active durable handoff surface for work that crosses architecture
boundaries, spans sessions, changes workflow, imports upstream Lineup code, or
affects Electron IPC/security, native playback, persistence/secrets, or
packaging.

After closeout, promote durable conclusions into the roadmap, current-state,
architecture, import-ledger, workflow, or verifier docs as appropriate. Then
move the full completed plan body to the local ignored archive under
`docs/runs/archive/plans/` and remove it from git. Completed plan bodies are not
long-term GitHub authority.

Use [`../roadmap/desktop-port-roadmap.md`](../roadmap/desktop-port-roadmap.md)
to choose the next major port slice after the current active plan is reviewed
and implemented. The roadmap is sequencing authority; each serious slice still
needs an active tracked plan here while it is in flight.
