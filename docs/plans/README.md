# Plans

Use this directory for durable Lineup Desktop plans that need fresh-session
handoff memory.

Keep routine one-session work in `update_plan`. Promote a plan here when the
work crosses architecture boundaries, spans sessions, changes workflow, imports
upstream Lineup code, or affects Electron IPC/security, native playback,
persistence/secrets, or packaging.

Use [`../roadmap/desktop-port-roadmap.md`](../roadmap/desktop-port-roadmap.md)
to choose the next major port slice after the current active plan is reviewed
and implemented. The roadmap is sequencing authority; each serious slice still
needs its own tracked plan here.
