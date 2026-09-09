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
| surface-02 | Mini-marathons · corrected | Unreviewed | User skipped separate review; adaptive/Windows checks pending | September 9: proceed to surface-03; no separate state lock |
| surface-03 | Channel sources · corrected | Approved at 1080p | Behavior checks passed; adaptive/Windows checks pending | September 9: one and two libraries, grouping separate; `8e972785` |
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


## September 9, 2026 — surface-03 correction brief

The user moved past surface-02 and confirmed two-column Channel sources with
“the same general fixes as last page”. They also requested shared Ember & Steel
palette alignment if Playback order had used local color overrides.

- Root verified that the theme already uses the exact approved mock palette;
  Playback order introduced no local color constants. Keep shared theme roles,
  correcting their presentation and hierarchy rather than changing matching hues.
- The frozen packet's `channel-source-comparison.html` is a 960px single-column
  rich-row component. The manifest's “two-column” description overstates that
  artifact. The active specification explicitly requires two columns and visible
  source-local details; that later decision governs this correction.
- Root inspected the rendered HTML and fresh real Flutter surface at base
  `cfa779fa24d8aeef031e9b28fdde720895595413`. Baseline PNG SHA-256:
  `39b49d22acce424935b15e3f3e0c39679790e3c420539bc0b296d792527ba5e7`.
  Capture: 1920×1080, DPR1, text100%, pinned Roboto body and Arial wordmark;
  one synthetic movie library, two actual generated channels, grouping hidden.
- Preserve the approved configuration frame. For Channel sources only, use
  “Choose the channels you want from your libraries.” below “Shape your lineup”.
- Retain two columns with more separation, readable wrapping and spacious source
  rows. Prioritize names over quieter qualifying/included counts; restore clear
  supporting-description hierarchy. Keep native source checkboxes, visible
  source-local grouping where applicable, truthful counts and current ordering.
- Existing `worker_luna` task `setup_frame_correction` owns only the source-grid,
  source-row and source-subtitle changes in `channel_setup_view.dart`. Root owns
  integration, behavior checks, captures and visual inspection. No theme edit,
  new layout test, independent reviewer or worker commit is assigned.

Candidate approval, final evidence and implementation commit remain pending.
Adaptive and physical Windows checks remain outstanding; the fresh two-library
state was visually inspected by root as recorded below.


### Surface-03 candidate presented for approval

- Source: base `cfa779fa24d8aeef031e9b28fdde720895595413` plus working-tree
  `lib/app/channel_setup_view.dart`, SHA-256
  `20f6f2035d8b6ca9c20211de381e85fcb948866fc4a6324532f22dd8476d7165`.
- Single-library candidate: `build/desktop-ui/surface-03/candidate-02.png`, SHA-256
  `d345558f73a8001d1dfd6610d1535b79e2b5d0b7e1bb701293ba4ba9de396387`.
- Two-library candidate: `build/desktop-ui/surface-03/candidate-02-multi.png`, SHA-256
  `52a64b9d595ca92a655f9974366791cefd730bc1153039988256fd553b5b5748`.
- Both are real 1920×1080/DPR1/text100% captures, without resize or retouching,
  using synthetic inventory, pinned Roboto body and Arial wordmark. Sources are
  selected; cross-library grouping is off in the two-library capture.
- Root reviewed the worker diff, retained useful description examples/eligibility
  wording, reduced excessive combined row spacing exposed by the two-library
  capture, aligned counts to column edges/baselines, and visually inspected both
  final captures. All eight source families and applicable grouping controls are
  visible in the two-library fixture at the recorded settings.
- Final source passed all 75 existing tests across `desktop_setup_test.dart`,
  `ui_review_regression_test.dart` and `lineup_app_test.dart`, full
  `flutter analyze --no-pub`, formatting and `git diff --check`. No new layout
  tests or golden-baseline updates. No shared palette or Playback order changes.
- Await explicit user visual approval for each shown state before locking or
  committing. Grouped adaptive/accessibility checks and physical Windows
  typography/input evidence remain outstanding. Independent review is not
  specifically recommended for this bounded presentation change; none launched.


### Surface-03 multi-library revision brief

The user said the one-library candidate “looks great” but rejected the added
multi-library grouping layout. Surface-03 remains in review. They approved the
following revision: compact “Library grouping” dropdowns with “Separate by
library” and source-specific “Combine matching …” choices; align controls with
source descriptions; show one shared explanation above the grid only for
multiple libraries; preserve disabled-source behavior and saved grouping choices.
The one-library candidate-02 appearance is to remain unchanged. Root reuses the
same exclusive production-file Luna worker and owns the behavior regression,
capture and visual review. No shared palette or other surface changes.


### Surface-03 revised candidate presented for approval

- Current candidate-04 source SHA-256 for `lib/app/channel_setup_view.dart`:
  `ff14dc37be97bcf4a1a12c4dee278fe1dedf0366eec68c36461acae5425e7704`,
  still based on `cfa779fa24d8aeef031e9b28fdde720895595413` plus working-tree edits.
- Two-library closed-controls PNG: `build/desktop-ui/surface-03/candidate-04-multi.png`,
  SHA-256 `bca7a88bdd434aed663ce878470a666e52bc82986d7bbed9e5dad43bffa25e36`.
- One-library PNG: `build/desktop-ui/surface-03/candidate-04.png`; SHA-256 remains
  `d345558f73a8001d1dfd6610d1535b79e2b5d0b7e1bb701293ba4ba9de396387`,
  byte-identical to the candidate-02 appearance the user liked.
- Root additionally inspected the Genres dropdown open in
  `build/desktop-ui/surface-03/candidate-04-multi-open.png`, SHA-256
  `97c57132e20a2e526a8670b065e27d9c8f0f0b81c947c927e5984635057dc872`.
  All captures use the same real 1920×1080/DPR1/text100% conditions and font
  limitations as above. No resizing or retouching.
- Root corrected dropdown font inheritance and added a restrained field surface
  using existing theme roles after reviewing the Luna result. The source-local
  controls use compact 16px text at 1080p with one shared grouping explanation.
- Existing configure/defaults test now exercises choosing combined genres,
  disabling/re-enabling the source with its choice retained, and returning to
  separate libraries. All 75 existing focused tests and full analysis passed
  on the final source, as did formatting and `git diff --check`. No layout tests.
- Await renewed user visual approval. No implementation commit or visual lock
  yet; adaptive/accessibility and physical Windows checks remain outstanding.


### Surface-03 paired-row revision brief

The user approved pairing sources by their grouping controls after finding
candidate-04's columns insufficiently aligned: Playlists / Collections,
Recently added / Decades, Genres / Studios, Actors / Directors. Each pair shares
row height and aligned grouping controls/separators, growing with wrapped text.
Narrow layouts stack naturally in that display order. This changes visual order
only; allocation priority remains owned by Lineup rules. No new grouping behavior
is added. Both one- and multi-library appearances require fresh visual review.
The existing Luna worker owns the bounded source-row composition; root retains
integration, behavior checks and personal visual inspection. Approval to make
these changes is not the final visual lock.


### Surface-03 paired candidate presented for approval

- Candidate-05 source SHA-256 for `lib/app/channel_setup_view.dart`:
  `379d6cfbb8f953d00d35958ca370d4194c22fb819090db8a088fcb7dab26c5b7`,
  based on `cfa779fa24d8aeef031e9b28fdde720895595413` plus working-tree edits.
- One-library PNG: `build/desktop-ui/surface-03/candidate-05.png`, SHA-256
  `6824eb3c290212bc1798e1184f23312482dd3cf3939317b2b198ea5977e3e1d8`.
- Two-library PNG: `build/desktop-ui/surface-03/candidate-05-multi.png`, SHA-256
  `4cd39fcccb7fe7c5229bb28cf3c8fbe7c9951f593e86c404c72590b3bda1d78d`.
- Root personally inspected both real, unscaled 1920×1080/DPR1/text100% captures.
  The paired rows align descriptions, grouping controls and bottom separators;
  all eight sources remain visible in the two-library fixture. The existing
  pinned Roboto/Arial evidence and physical Windows typography limitations apply.
- The existing Luna worker completed source pairing with native table layout and
  reused selection/grouping helpers; root reviewed integration and confirmed that
  `_sourceOrder` and allocation priority are unchanged. No new layout tests.
- Final source passed all 75 existing focused behavior tests, full analysis,
  formatting and `git diff --check`. Both reordered states await explicit visual
  approval before locking/committing. Grouped adaptive/accessibility and physical
  Windows checks remain outstanding. Independent review is not specifically
  recommended for this bounded change; none was launched.


### Surface-03 explicit approval — September 9, 2026

The user approved both candidate-05 states: “yes locked. time to move to 04 lineup
rules”. Surface-03 is visually locked at 1920×1080/DPR1/text100% for one library
and two libraries, all sources selected, grouping set to Separate by library.
Implementation commit: `8e972785d8297cb347489efec9d67fa59e9c5e16`
(`fix(ui): align channel source configuration rows`), matching the candidate-05
source SHA-256 recorded above. The approved captures are preserved unchanged:

- [One library](design/desktop-ui/approved/2026-09-09-surface-03/channel-sources-one-library.png)
- [Two libraries](design/desktop-ui/approved/2026-09-09-surface-03/channel-sources-two-libraries.png)

Their SHA-256 values are the candidate-05 hashes above. Approval does not extend
to open dropdowns, other grouping selections, enlarged text or physical Windows
rendering. Grouped adaptive/accessibility and Windows checks remain outstanding.
No independent review is specifically recommended; none was launched. The frozen
comparison packet remains unchanged. Next user-selected surface is 04 Lineup rules.
