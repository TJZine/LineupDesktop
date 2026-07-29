# Package 1F Local Visual And Windows Evidence Checklist Template

This tracked file is a safe, reusable template, not evidence or authority. On a
Windows Codex checkout, copy it to the ignored sibling `windows-checklist.md`
for each new evidence session. Record session-specific observations only in
that ignored copy. Never add secrets, raw evidence, account or machine
identifiers, or local paths to this template.

Audited upstream commit:
`0258dbe15b04d2d141d0a4a44575fecb5bb72d41`

## Fresh Capture Procedure

1. Confirm the upstream checkout is at the audited commit and Desktop is at the
   intended `HEAD`.
2. Confirm every mapped upstream and reviewed Desktop closure source is tracked,
   byte-identical to its recorded revision, and scoped clean.
3. Start the bounded collector from the Desktop repository root:
   `node docs/runs/2026-07-22-tier3-parity-correction/channel-builder/capture.mjs --wait-ms=3600000`.
   The explicit wait is required and bounded to at most one hour.
4. While that collector remains running, generate every approved upstream and
   Desktop state. Every PNG must be written after collector launch;
   pre-existing or prior-session PNGs are rejected.
5. Use the frozen capture IDs and physical dimensions: CSS viewport multiplied
   by DPR. The zoomed 640×360 CSS viewport at DPR 2 is a 1280×720 bitmap.
6. Let the running collector finish. It rechecks source snapshots and `HEAD`,
   validates PNGs and hashes, and atomically publishes both
   comparison-incomplete manifests through same-directory transient files.
7. Compare typography, color, spacing, artwork/icon treatment,
   clipping/overflow, focus visibility/order/restoration, reduced motion,
   state communication, and interaction disposition for every row.
8. Change a row from blocked only for a recorded safe decision: match, approved
   Electron adaptation, or approved product divergence.
9. Run the contract test and full verifier. Any failure invalidates the whole
   session before authority updates.

## Manual UI Matrix — No Passes Claimed

Record measured viewport, DPR, zoom, focus owner, and outcome only in the
ignored session copy.

- [ ] `CB-UI-01-WIDE-CONFIG` — 1920×1080 DIPs, Windows 100%, DPR 1, zoom
  100%. Exercise every strategy, scope, priority, min/max, Expand, alternate,
  sequential/block, and mode control; verify columns, values, focus, and no
  horizontal scroll, overlap, truncation, or dead control.
- [ ] `CB-UI-02-BASELINE-REVIEW` — 1280×720 DIPs, Windows 100%, DPR 1, zoom
  100%. Exercise ready, blocked, slow, warnings/caps, append/merge, and replace
  open/cancel/confirm; verify counts/status, modal trap/restoration, Escape
  safety, and unclipped content/actions.
- [ ] `CB-UI-03-ORDINARY-WIDTH` — 1024×720 DIPs, Windows 125%, DPR 1.25,
  zoom 100%. Exercise config through review above 900px; verify usable columns,
  keyboard/pointer access, focused-control visibility, and no occlusion.
- [ ] `CB-UI-04-STACK-BREAKPOINT` — 900×700 DIPs, Windows 150%, DPR 1.5,
  zoom 100%. Exercise config, review, and progress; verify the 900px
  single-column breakpoint, DOM/focus order, and reachable content/status.
- [ ] `CB-UI-05-NARROW-BREAKPOINT` — 600×700 DIPs, Windows 125%, DPR 1.25,
  zoom 100%. Exercise library, config, and replace modal; verify the 600px
  one-column layout, internally scrolling dialog, and reachable actions.
- [ ] `CB-UI-06-INPUT-FOCUS` — 1280×720 DIPs, Windows 100%, DPR 1, zoom
  100%. Complete review/cancel/review/apply with keyboard, D-pad, mouse,
  gamepad mapping, and typed inputs; verify one focus owner, pending/disabled
  skipping, single activation, shortcut suppression, and exact restoration.
- [ ] `CB-UI-07-REDUCED-MOTION-ZOOM` — 1280×720 DIPs at DPR 1/zoom 100%,
  then 640×360 CSS at effective DPR 2/zoom 200%. Exercise every progress phase,
  canceled, result, and recovery with reduced motion; verify no focus theft,
  overlap, clipping, or unreachable action.
- [ ] `CB-UI-08-FORCED-COLORS` — 900×700 DIPs, Windows 150%, DPR 1.5, zoom
  100%, forced colors/high contrast. Exercise config, focused review, modal,
  progress, failure, and result; verify visible focus/boundaries, non-color-only
  states, accessible names/states, and announcements without focus movement.

Fail a scenario for horizontal document scroll, overlapping interactive
targets, clipped required content, invisible focus, focus outside an open
modal, unreachable primary/back/cancel action, color-only state, duplicate
activation, or focused content outside its visible scrollport.

## Automated Responsive Assertions — No Passes Claimed

- [ ] 901 CSS px: above the stack breakpoint.
- [ ] 900 CSS px: stack breakpoint matches.
- [ ] 601 CSS px: above the narrow breakpoint.
- [ ] 600 CSS px: narrow breakpoint matches.

## Performance Follow-Up

- [ ] `WS1-PERF-01` remains open. Safe historical observation: workflow run
  `30074270895`, job `89421508431`, 50,000-candidate duration `2690.61ms`,
  threshold `2000ms`, above threshold.
- [ ] Repeat on the authoritative Windows runner and retain only safe run, job,
  threshold, duration, and status conclusions in tracked authority.

## Live Multi-Library Plex Proof — No Passes Claimed

- [ ] Prove safe facet discovery and the complete supported filter surface with
  multiple eligible libraries.
- [ ] Prove review and apply for append, merge, and replace.
- [ ] Cancel before persistence and prove no change; cancel after the barrier
  and prove commit-started rejection without a second activation.
- [ ] Restart and prove restored channel/configuration state.
- [ ] Prove guide refresh occurs only after commit.

Keep account, server, library, media, and credential material out of manifests
and tracked notes.

## Packaged WS9 Smoke And Persistence — No Passes Claimed

- [ ] Record only a safe package identity.
- [ ] Run the packaged executable once with validated smoke data and once with
  production persistence data.
- [ ] Through the packaged app, create/read/replace both the smoke sentinel and
  canonical channel file.
- [ ] Repeat the ACL gate below; unpackaged results cannot substitute.

## Windows ACL Gate — No Passes Claimed

Inspect the canonical persistence parent, channel file, smoke root, and smoke
sentinel after packaged operations and before cleanup. For each target:

- [ ] Capture `Get-Acl` and `icacls` output only in ignored local evidence.
- [ ] Resolve effective current-user create/replace/read control.
- [ ] Confirm no broad-principal Allow grants Write, Modify, or FullControl.
- [ ] Confirm inheritance matches the validated-parent assumption.
- [ ] Confirm the packaged app can open and replace the tested file.

The safe manifest contains only the 12 booleans for the four targets under
`currentUserControl`, `broadWriteAbsent`, and
`inheritsFromValidatedParent`. Keep raw ACL output, commands containing actual
paths, principals, names, SIDs, inheritance detail, and diagnostics only in the
ignored session checklist. Any missing, ambiguous, or false packaged result
keeps proof blocked.
