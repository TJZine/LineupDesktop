# Desktop surface visual approvals

Starting comparison: `cbf3dbd5`, September 9, 2026. The user accepted the comparison
as useful; **no application surface is visually approved by that statement**.
Follow the [collaborative handoff](desktop-ui-collaborative-handoff.md).

Use `Unreviewed`, `In review`, `Changes requested`, or `Approved at 1080p` for the
visual column. The adaptation column separately records other resolutions,
DPI/text scale and interaction checks. Never infer approval or reuse an approval
for a changed appearance. Add a dated entry beneath the table for each explicit
user approval: message/quote, surface/state scope, commit/source hashes, capture
hashes, remaining limitations and any later invalidation. A shared correction
may cover multiple listed states only when that scope is clear to the user.

| ID | Surface | 1080p visual status | Adaptation/interaction status | Approval record |
| --- | --- | --- | --- | --- |
| surface-01 | Playback order · corrected | Approved at 1080p | Behavior checks passed; adaptive/Windows checks pending | September 9: Shuffle selected, additional versions off; `8e1f1bc0` |
| surface-02 | Mini-marathons · corrected | Unreviewed | Not assessed in this pass | — |
| surface-03 | Channel sources · corrected | Unreviewed | Not assessed in this pass | — |
| surface-04 | Lineup rules · corrected | Unreviewed | Not assessed in this pass | — |
| surface-05 | Review lineup · corrected labels | Unreviewed | Not assessed in this pass | — |
| surface-06 | Review removals · corrected labels | Unreviewed | Not assessed in this pass | — |
| surface-07 | Linking · corrected | Unreviewed | Not assessed in this pass | — |
| surface-08 | Linking expired · corrected | Unreviewed | Not assessed in this pass | — |
| surface-09 | Terminal linking failure | Unreviewed | Not assessed in this pass | — |
| surface-10 | Profile selection | Unreviewed | Not assessed in this pass | — |
| surface-11 | Profile PIN | Unreviewed | Not assessed in this pass | — |
| surface-12 | Server selection | Unreviewed | Not assessed in this pass | — |
| surface-13 | Library scan outcomes | Unreviewed | Not assessed in this pass | — |
| surface-14 | Setup progress | Unreviewed | Not assessed in this pass | — |
| surface-15 | Setup complete | Unreviewed | Not assessed in this pass | — |
| surface-16 | Channel directory | Unreviewed | Not assessed in this pass | — |
| surface-17 | Channel selection | Unreviewed | Not assessed in this pass | — |
| surface-18 | Channel reorder | Unreviewed | Not assessed in this pass | — |
| surface-19 | Delete confirmation | Unreviewed | Not assessed in this pass | — |
| surface-20 | Studio · hand-picked | Unreviewed | Not assessed in this pass | — |
| surface-21 | Studio · full authoring | Unreviewed | Not assessed in this pass | — |
| surface-22 | Studio · browse sources | Unreviewed | Not assessed in this pass | — |
| surface-23 | Studio · library programming | Unreviewed | Not assessed in this pass | — |
| surface-24 | Studio · filter picker | Unreviewed | Not assessed in this pass | — |
| surface-25 | Guide · no playback | Unreviewed | Not assessed in this pass | — |
| surface-26 | Guide · PiP | Unreviewed | Not assessed in this pass | — |
| surface-27 | Mini Guide | Unreviewed | Not assessed in this pass | — |
| surface-28 | Player OSD · protected | Unreviewed | Not assessed in this pass | — |
| surface-29 | Now Playing · protected | Unreviewed | Not assessed in this pass | — |
| surface-30 | Audio tracks | Unreviewed | Not assessed in this pass | — |
| surface-31 | Subtitles · long names | Unreviewed | Not assessed in this pass | — |
| surface-32 | Sleep timer | Unreviewed | Not assessed in this pass | — |
| surface-33 | Settings · Appearance | Unreviewed | Not assessed in this pass | — |
| surface-34 | Settings · Guide | Unreviewed | Not assessed in this pass | — |
| surface-35 | Settings · Playback | Unreviewed | Not assessed in this pass | — |
| surface-36 | Settings · Accessibility | Unreviewed | Not assessed in this pass | — |
| surface-37 | Settings · Account | Unreviewed | Not assessed in this pass | — |
| surface-38 | Settings · Support | Unreviewed | Not assessed in this pass | — |
| surface-39 | Settings over playback | Unreviewed | Not assessed in this pass | — |
| surface-40 | Alternate theme · current only | Unreviewed | Not assessed in this pass | — |
| surface-41 | Lineup menu | Unreviewed | Not assessed in this pass | — |
| surface-42 | Diagnostics · recording off | Unreviewed | Not assessed in this pass | — |
| surface-43 | Diagnostics · synthetic events | Unreviewed | Not assessed in this pass | — |
| surface-44 | Diagnostics · technical details | Unreviewed | Not assessed in this pass | — |
| surface-45 | Diagnostics · events and details | Unreviewed | Not assessed in this pass | — |

## Approval records

Surface-01 was explicitly approved on September 9, 2026, as recorded below.
Physical Windows acceptance remains a separate evidence track.

## September 9, 2026 — surface-01 correction brief

The user approved proceeding with corrections: “okay then we are locked and ready
for the corrections”. This locks the **correction brief**, not the resulting
surface appearance. The subsequent candidate approval is recorded below.

- Reference: `playback-order-fluid.html`, 1920×1080 variant, Shuffle selected,
  Additional channel versions off. Root inspected the rendered reference through
  the visualization skill's sandboxed preview and the real current Flutter PNG.
- Baseline source: `070ab1d69054a094951bc8a1670bffb91c961a0f`, clean working tree.
  Fresh 1920×1080/DPR1/text100% capture is byte-identical to the frozen packet's
  surface-01 PNG: SHA-256
  `9998d87b7f8ba28096c2364aa3511a60b95519d9cc3c11f62bc8ae3b977faf6e`.
- Restore the mock's full-window proportions, larger choice cards, inline section
  description, episode-strip explanation, spacing, and restrained surface roles.
- Configuration header: amber LINEUP to the left of the logo, then “Shape your
  lineup” and “Choose how your generated channels will play.” Match the mock's
  hierarchy. Header composition and exact applicable wording are explicit review
  criteria on each later surface.
- Font clarification: match the mock's Arial Regular/uppercase/letter-spaced
  LINEUP treatment only. Preserve the existing application font family elsewhere;
  approved size and hierarchy corrections still apply. Windows uses Segoe UI;
  the existing capture harness pins Roboto. Do not represent these captures as
  exact Windows typography evidence.
- Footer: prominent actual generated count at the left, supporting information
  below; Back to libraries next to Review channels at the right, vertically
  centered. Preserve actual allocation/exclusion information rather than copying
  the mock's illustrative estimated count.
- Whole-card radio selection without visible circles; preserve radio semantics,
  focus and keyboard operation. Keep the additional-versions switch and move it
  beside its label, with the explanatory text below.
- Keep later chronology, specials, eligibility, invalid-selection and allocation
  contracts when original mock prose is outdated. No scheduling/persistence edits.
- Shared configuration frame also affects surfaces 02–04; these remain unreviewed
  until reached in the agreed order. No global theme or other setup-stage redesign.
- Root owns integration and visual review; bounded `worker_luna` units receive
  exclusive production-file leases. No independent reviewers or new layout tests.

### Approved candidate — September 9, 2026

- User approval: “approved and locked”. Scope: surface-01 Playback order,
  Shuffle selected, Additional channel versions off, at 1920×1080/DPR1/text100%.
  Other states and surfaces are not locked by this approval.
- Approved [Flutter capture](design/desktop-ui/approved/2026-09-09-surface-01/playback-order.png),
  preserved byte-for-byte from `candidate-03.png`, with no resize or retouching.
- Implementation commit: `8e1f1bc00b6d42b9100774eeaa0906622aeb3635`
  (`fix(ui): restore playback setup composition`). Its production source matches
  the approved candidate hash below; source git blob
  `1e3fdcc0ca5bc3c239c7b733116c71b08a13f232`.
- Source base: `070ab1d69054a094951bc8a1670bffb91c961a0f` plus working-tree
  `lib/app/channel_setup_view.dart`, SHA-256
  `1e8a8523dab5c0e2556107b566d4cb52562ff7401850fc4a80a4c2589c8e52b9`.
- PNG SHA-256:
  `894d61ed8a2a0c810b0c5027dcd48c57ea156e21f65b0522fefffa96c914e74f`.
- Capture fonts: existing pinned Roboto body; Arial Regular loaded for the
  wordmark. This does not establish exact Segoe UI rendering on Windows.
- `worker_luna` (`gpt-5.6-luna`/`xhigh`), task `setup_frame_correction`, completed
  two sequential exclusive-file units: configuration frame, then playback
  spacing/copy/episode strip/switch presentation. Root reviewed both, corrected
  integration issues, and owns the native RawRadio/focus-node implementation,
  regression adaptation, captures and final visual inspection.
- Verification: 75 tests passed across `desktop_setup_test.dart`,
  `ui_review_regression_test.dart`, and `lineup_app_test.dart`; full
  `flutter analyze --no-pub` passed. Existing defaults coverage now exercises
  radio semantics and arrow-key selection; affected selectors and scrolling
  interactions were adapted. No new layout tests or golden-baseline updates.
- Root visually inspected the final candidate against the approved reference.
  Real generated counts, the approved native switch, retained application body
  font, and synthetic episode-order differences remain intentional distinctions.

**Surface-01 is visually approved and locked at the recorded state and settings.**
The original comparison packet remains a frozen baseline. Grouped adaptive checks,
remaining affected configuration-state review, and physical Windows typography,
input and accessibility evidence remain outstanding. Independent review is not
specifically recommended for this bounded visual correction; none was launched.
