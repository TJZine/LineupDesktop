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
| surface-01 | Playback order · corrected | Approved at 1080p | Behavior checks passed; adaptive/Windows checks pending | Logo-first approved `d4126b59`; previous September 9: Shuffle selected, additional versions off; `8e1f1bc0` |
| surface-02 | Mini-marathons · corrected | Unreviewed | User skipped separate review; adaptive/Windows checks pending | September 9: proceed to surface-03; no separate state lock |
| surface-03 | Channel sources · corrected | Approved at 1080p | Behavior checks passed; adaptive/Windows checks pending | Logo-first approved `d4126b59`; previous September 9: one and two libraries, grouping separate; `8e972785` |
| surface-04 | Lineup rules · corrected | Approved at 1080p | Behavior checks passed; adaptive/Windows pending | Feedback refinement approved `2924057b`; logo-first `d4126b59`; previous September 9: all-fit and limit-reached/Off states; `f535a365` |
| surface-05 | Review lineup · corrected labels | Approved at 1080p | Behavior checks passed; adaptive/Windows pending | First-time candidate05; `25467fe3` |
| surface-06 | Review removals · corrected labels | Approved at 1080p | Behavior checks passed; adaptive/Windows pending | Removal, populated and expanded-update candidate05; `25467fe3` |
| surface-07 | Linking · corrected | Approved at 1080p | Behavior checks passed; adaptive/Windows pending | Candidate01; `3a9d6b7e` |
| surface-08 | Linking expired · corrected | Approved at 1080p | Behavior checks passed; adaptive/Windows pending | Candidate01; `3a9d6b7e` |
| surface-09 | Terminal linking failure | Approved at 1080p | Behavior checks passed; adaptive/Windows pending | Candidate01; `3a9d6b7e` |
| surface-10 | Profile selection | Approved at 1080p | Behavior checks passed; adaptive/Windows pending | Candidate02; `019f4b0c` |
| surface-11 | Profile PIN | Unreviewed | Deferred by user; no visual capture | Explicitly skipped; unchanged |
| surface-12 | Server selection | Approved at 1080p | Behavior checks passed; adaptive/Windows pending | Candidate02; `019f4b0c` |
| surface-13 | Library scan outcomes · corrected | Approved at 1080p | Behavior checks passed; adaptive/Windows pending | Candidate03 state family; `692083fc` |
| surface-14 | Setup progress | Approved at 1080p | Behavior checks passed; adaptive/Windows pending | Candidate02 family; `22743fd6` |
| surface-15 | Setup complete | Approved at 1080p | Behavior checks passed; adaptive/Windows pending | Candidate02 family; `22743fd6` |
| surface-16 | Channel directory | Approved at 1080p | Behavior checks passed; adaptive/Windows pending | Candidate05/06; `d98e9761` |
| surface-17 | Channel selection | Approved at 1080p | Behavior checks passed; adaptive/Windows pending | Candidate05/06; `d98e9761` |
| surface-18 | Channel reorder | Approved at 1080p | Behavior checks passed; adaptive/Windows pending | Candidate05/06; `d98e9761` |
| surface-19 | Delete confirmation | Approved at 1080p | Behavior checks passed; adaptive/Windows pending | Text-only final amendment; recapture waived; `aa25168f` |
| surface-20 | Studio · hand-picked | Approved at 1080p | Behavior checks passed; adaptive/Windows pending | Candidate07; `8c0617c7` |
| surface-21 | Studio · full authoring | Approved at 1080p | Behavior checks passed; adaptive/Windows pending | Candidate07; `8c0617c7` |
| surface-22 | Studio · browse sources | Approved at 1080p | Behavior checks passed; adaptive/Windows pending | Candidate07; `8c0617c7` |
| surface-23 | Studio · library programming | Approved at 1080p | Behavior checks passed; adaptive/Windows pending | Candidate07; `8c0617c7` |
| surface-24 | Studio · filter picker | Approved at 1080p | Behavior checks passed; adaptive/Windows pending | Candidate07; `8c0617c7` |
| surface-25 | Guide · no playback | Approved at 1080p | Behavior checks passed; adaptive/accessibility/motion/Windows pending | September 12 candidate04; `e0834448` |
| surface-26 | Guide · PiP | Approved at 1080p | Behavior checks passed; adaptive/accessibility/motion/Windows pending | September 12 candidate04; `e0834448` |
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


## September 9, 2026 — surface-04 initial comparison

User selected Lineup rules after locking surface-03. Root inspected the original
`lineup-rules-design.html` with its 1920×1080 option, the current source owners,
and a fresh real Flutter capture at commit
`884ce5c96009fe266d729b6e74c54ecc5b004f45`:
`build/desktop-ui/surface-04/current-884ce5c9.png`, SHA-256
`ae0db94571fc74ccedb61511f915d70f31ef3d357f2911241ea1b7d9fe1d387e`.
Capture is 1920×1080/DPR1/text100%, pinned Roboto body and Arial wordmark,
synthetic one-library fixture with two generated channels, maximum200/minimum5.
The frozen comparison remains historical.

Initial proposed corrections for discussion: exact rules-specific header subtitle;
Channel limits and Source order as the two main headings; compact numeric controls
beside full labels with separate descriptions; more spacious source-order rows,
rank numbers and right-edge arrows; true allocation-derived fit/limit feedback.
Preserve actual source priority, focus transfer, disabled-source positions and
existing allocation contracts. No worker dispatched or production changes made
for surface-04 pending user feedback on this comparison.


### Surface-04 agreed correction brief

The user accepted the initial correction list and subsequent neutral all-fit /
amber excluded-by-limit feedback, with Off beside disabled source names, then
said “sounds good” to implementation. Preserve the existing frame, theme and
body font; use the exact rules subtitle, two main headings, compact labeled
numeric selectors, separate explanations, spacious numbered source-order rows,
right-edge arrows and aligned two-column composition. Actual allocation and
focus-transfer behavior remain authoritative; mock order/counts are illustrative.
The existing `worker_luna` (`gpt-5.6-luna`/`xhigh`) owns bounded presentation edits
in `channel_setup_view.dart`; root owns allocation feedback, behavior checks,
integration and visual evidence. Existing ledger edits are preserved. No new
layout tests, independent reviewers or additional tasks are authorized.


### Surface-04 candidate presented for approval

- Candidate-02 source SHA-256 for `lib/app/channel_setup_view.dart`:
  `943815a68055a62271bb776c9f154d1aabdbf2231abd5ce8b45e1287242baaeb`,
  based on `884ce5c96009fe266d729b6e74c54ecc5b004f45` plus working-tree edits.
- Default all-fit state: `build/desktop-ui/surface-04/candidate-02.png`, SHA-256
  `a36c016c14994b5f765630662f287a0465773732b9f0ccc08f641984a90095dd`.
  One synthetic movie library, all sources selected, maximum200/minimum5,
  no extras, two generated channels.
- Limit-reached/Off state: `build/desktop-ui/surface-04/candidate-02-limited.png`,
  SHA-256 `fe31e7f1a19a6ac9361d6a9493223fab2c0d55cc7c52a03474078afe9827a75c`.
  Synthetic expanded genre fixture, Playlists off, maximum50/minimum5,
  no extras, 50 included and 11 originals excluded by the generated cap.
- Both captures are real 1920×1080/DPR1/text100%, unscaled/unretouched, using
  pinned Roboto body and Arial wordmark. Root personally inspected the final
  captures against the selected mock. Windows Segoe UI evidence is outstanding.
- Luna completed the bounded presentation unit. Root reviewed and corrected
  focus-state ownership, added allocation-derived all-fit/empty/excluded feedback
  including channel-number exhaustion handling, and aligned Off with its name.
  Existing focus nodes, source priority and allocation algorithms are preserved.
- Final source passed all 75 existing focused tests, full analysis, formatting and
  `git diff --check`. The existing configure/defaults check now exercises minimum
  changes, true qualifying counts and disabled Review when nothing qualifies;
  existing source-reordering focus coverage passed. No new layout tests.
- Both candidate states await explicit user approval. No implementation commit
  or visual lock yet. Adaptive/accessibility checks are grouped at the setup
  family checkpoint; physical Windows typography/input checks remain outstanding.
  Independent review is not specifically recommended; none launched.


### Surface-04 explicit approval — September 9, 2026

Asked whether both candidate-02 states were acceptable to lock, the user replied
“yes they are.” Both are visually approved at 1920×1080/DPR1/text100% with the
state scope recorded above. Implementation commit:
`f535a365fce7a9583d45287c70e7a899d3ef2c62`
(`fix(ui): refine lineup rules configuration`), matching the recorded candidate
source SHA-256. Approved captures are preserved byte-for-byte:

- [All channels fit](design/desktop-ui/approved/2026-09-09-surface-04/lineup-rules-all-fit.png)
- [Limit reached, Playlists off](design/desktop-ui/approved/2026-09-09-surface-04/lineup-rules-limit-reached.png)

PNG hashes remain those recorded for candidate-02 above. Other states, grouped
adaptive/accessibility checks and physical Windows typography/input validation
remain outstanding. Independent review is not specifically recommended; none
launched. The user's subsequent question about logo/wordmark order is a design
discussion, not authorization to alter these approved captures or shared branding.


## September 9, 2026 — shared logo-first branding refinement

User explicitly requested logo → LINEUP ordering wherever that actual horizontal
combination appears. Root audited all production logo-asset uses and LINEUP text:
only `_configurationHeader` combines the logo asset with the LINEUP wordmark.
It is shared by configuration surfaces01–04. Guide/Channels hamburger buttons,
Settings/Diagnostics dropdown buttons, standalone branding and stage-title/logo
arrangements have different roles and were preserved.

The existing Luna worker changed only the order of the three existing header
children in `channel_setup_view.dart`; Arial style, image size, gap, semantics and
all other geometry remain unchanged. Root inspected the diff and all six fresh
1920×1080/DPR1/text100% captures. Each capture compiled and rendered real Flutter
widgets without exceptions. Formatting and diff checks passed; no new layout
tests. Prior behavior results remain relevant to the unchanged behavior.

Source base: `ba5acd4e527cb31f6e2a6bf278ed5bf315ad600a`; working-tree source SHA-256:
`39592675086af58350fcd3d91e748a9c958c8c680918418dd5e586a766978ee8`.
Fresh candidate evidence (same pinned Roboto body / Arial wordmark limitations):

- `build/desktop-ui/surface-01/branding-01.png`: SHA-256
  `1028f7ef0037f64c9fe96addfa03d40df3f9ebe8c6c8cd4048d76fd920c1931a`.
- `build/desktop-ui/branding/branding-02.png`: SHA-256
  `5d999c80f83a1c71780bb6f409b71e17247b467ae9864499bff0e72679713e04`.
- `build/desktop-ui/surface-03/branding-03.png`: SHA-256
  `a7ba2ce0adae63aee1e7dc4c9621a6585f6770a6b5879f035e85a15c5b36f084`.
- `build/desktop-ui/surface-03/branding-03-multi.png`: SHA-256
  `ba56d012c4fa781511c1ea72ae0f18d7d4aa34390dbf1f28268aeb608c77abef`.
- `build/desktop-ui/surface-04/branding-04.png`: SHA-256
  `2db0393828075ef14a234a1eaa3c6766911c672569b662a87e09551551c1e4ca`.
- `build/desktop-ui/surface-04/branding-04-limited.png`: SHA-256
  `c526271fe6bb9ed237fb7ad9fd8e97d073d60c2c534da046dadd6acac5c738e2`.

The previous surface01/03/04 approvals remain historical evidence at their
recorded commits; the changed branding awaits renewed visual approval across
those states. Surface02 remains without a separate whole-surface visual lock.
Grouped adaptive/accessibility and physical Windows checks remain outstanding.
No independent review is specifically recommended; none launched. Frozen packets
and approved original PNGs were preserved. No commit or push yet for this revision.


### Logo-first branding explicit approval — September 9, 2026

Asked whether the branding order was right to lock across affected screens, the
user replied “yes.” Commit `d4126b59187af726446e92c2ba118f0ddac413d3`
(`fix(ui): place logo before lineup wordmark`) matches the source hash above.
The same six PNGs, with the same hashes, are preserved in
[the logo-first evidence directory](design/desktop-ui/approved/2026-09-09-logo-first/).
This renews the existing surface01/03/04 state approvals with the logo-first
header. Surface02's branding is approved; its separate whole-surface review
remains skipped. Adaptive/accessibility and physical Windows evidence remain
outstanding. Independent review is not specifically recommended; none launched.

The subsequent question about repeated generated-count information in Lineup
rules is a discussion of possible refinement, not approval of another visual
change. No count information was removed at this checkpoint.


## September 9, 2026 — Lineup rules count-summary refinement

The user approved removing redundant left-column counts: “yes those changes sound
good we can lock after those refinements”. The footer remains the authoritative
count/breakdown summary. Hide the left feedback entirely when channels fit;
otherwise show concise actionable guidance without repeating counts. Preserve
appropriate guidance for empty selections and exhausted channel numbers. This is
approval to implement; the changed surface04 states await fresh visual approval.
The existing Luna worker owns only `_rulesAllocationFeedback`; root owns test
adaptation, capture and personal review. Other approved surfaces stay unchanged.


### Surface-04 simplified feedback candidate

Source base `f1266bdb90117301bd0d1f0d2100ef8de5eeac41`, working-tree production
SHA-256 `253baf5b21bf13c5809d4d885b17b9c22e6f0b0f0ebbe680d0dd23721b46c954`.
Root inspected the diff and these real 1920×1080/DPR1/text100% captures, with the
same pinned fonts and Windows limitations as the previous evidence:

- `build/desktop-ui/surface-04/candidate-03.png`: SHA-256
  `5f5a639a06f9e5b6fb700c883c248c04e2cc1a6050bd9b4bad7134c32bfd7bd8`.
- `build/desktop-ui/surface-04/candidate-03-limited.png`: SHA-256
  `5a27cee1b4c474a7dbca70c8e8795a2837cd1c0995cf1a9877febbb6981884c7`.
- `build/desktop-ui/surface-04/candidate-03-empty.png`: SHA-256
  `7ce59521c07ffad22137472710860e62fda8eb7f11a374cc40006ba5d171a5f1`.

The all-fit state has no left feedback block; limit-reached shows guidance without
counts; minimum50 on the original synthetic fixture produces zero channels and
source/minimum guidance with Review disabled. Footer counts remain unchanged.
Final source passed all 75 focused existing tests, full analysis, formatting and
`git diff --check`. Existing defaults coverage now checks authoritative footer
counts and conditional empty guidance. No new layout tests. Candidate visual
approval and commit remain pending; adaptive/accessibility/Windows checks remain
outstanding. Independent review is not specifically recommended; none launched.


### Surface-04 simplified feedback explicit approval — September 9, 2026

The user approved the two presented candidate-03 normal and limit-reached states:
“yes locked. time for 05/06 which are the same surface with diff states”.
Implementation commit `2924057bd33a9708fe7c996bf81ac9e290a10f7d`
(`fix(ui): simplify lineup rules feedback`) matches the candidate source hash.
The unchanged approved PNGs are preserved in
[the feedback refinement evidence directory](design/desktop-ui/approved/2026-09-09-surface-04-feedback/),
with their candidate-03 hashes recorded above. Empty-state capture remains root
verification, not a separate user visual lock. Adaptive/accessibility/Windows
checks remain outstanding; no independent review specifically recommended or
launched. The user selected surfaces05/06 for joint review next.

### Surfaces 05/06 first correction pass — September 9, 2026

User approved the proposed starting corrections and requested to see the first
pass before further feedback. Both states remain in review; no visual lock.
Root personally inspected the original polished first-time and edge-case
one-removal fragments in the browser, and fresh real Flutter captures at source
`404c14bfc3823095dadd95292818690d645d5287` (production file SHA-256
`253baf5b21bf13c5809d4d885b17b9c22e6f0b0f0ebbe680d0dd23721b46c954`).
The frozen packet's surface05 reference defaults to existing lineup while its
actual fixture is first-time; root selected the matching first-time mock state.

- First-time baseline: `build/desktop-ui/surface-05/current-404c14bf.png`, SHA-256
  `7d33049fcad7cfda73021ae8119b87513dee31c6eb0c04d5ff5ece3267fa0595`.
- One-removal baseline: `build/desktop-ui/surface-06/current-404c14bf.png`, SHA-256
  `9b2f04713aa8fa0ca7c83495bd56596b5e641611abb9d3b909666518008e0b66`.

Both are 1920×1080/DPR1/text100%, pinned Roboto body and Arial wordmark.
The fixture has two new channels and one removal, unlike the mock's hundreds.
Windows Segoe UI validation remains outstanding.

Agreed brief: carry forward approved branding/header hierarchy and spacing;
contained overview with prominent final total and quiet source counts; readable
full-width roster favoring channel names; restrained selectable change counts;
method and explanation left with Back/primary right; leading removal checkbox
beside warning; omit duplicate first-time footer count. Preserve build methods,
allocation, custom protection, stale-review safeguards, search/filter, lazy
roster and expanded changed-field behavior. Root also inspects a populated roster.
Actual assignment: existing `worker_luna` (GPT-5.6 Luna/xhigh), exclusive
`lib/app/channel_setup_view.dart` presentation lease; root owns tests, capture,
contracts and personal review. No new layout tests or independent reviewers.

### Surfaces 05/06 candidate and explicit approval — September 9, 2026

Root integrated the Luna presentation unit and personally reviewed fresh real
Flutter candidates. Root completed the Review-only page margins/text sizing,
entry-count spacing, primary-button font inheritance, native total arrow,
expanded-row arrow font fallback and reserved disclosure column alignment.
The existing 720p method-switch check exposed a transient overflow from inserting
“Updating review…” above the roster. That status now temporarily replaces the
method explanation in the footer and disables Apply while shown, preserving the
roster position and the existing synchronous calculation/reset-confirmation flow.
No allocation, persistence, channel-composition or result-screen changes.

The user requested larger Back text and more vertical spacing around the entry
count; both are included in the final candidate. The user also asked about the
selected Unchanged count. Root explained that its background indicates the active
roster filter and Show all restores the full list. The user accepted this meaning.

Final production source SHA-256:
`4a899426d1b42906b597eb91eac47aee553edd249041ae67c46089466ddb5c9f`.
Implementation commit: `25467fe37bbdfd1bbdbf3238a71694cee55f1e5a`
(`fix(ui): refine lineup review presentation`). Final candidate captures below
match that source and are preserved without resizing or retouching:

- [First-time, two channels](design/desktop-ui/approved/2026-09-09-surface-05/candidate-05.png):
  `56c8e6e66dc2780f9cd2a312577fbb38d131a999c305f0da4c2a9bd6f7c54e63`.
- [Replacement, two new and one removed](design/desktop-ui/approved/2026-09-09-surface-06/candidate-05.png):
  `3934f0605c34dba86d0c6cf54ab88f99ebef476a35fd27a19a57436fadba5b7e`.
- [Populated replacement, 19 new, eight custom kept and one removed](design/desktop-ui/approved/2026-09-09-surface-06/candidate-05-populated.png):
  `74ed4d2a0d293b98cb13ad7a707c127cbbcc7fd79975a2a5bb136bfe016d0f43`.
- [Update and add, expanded playback change](design/desktop-ui/approved/2026-09-09-surface-06/candidate-05-updated.png):
  `7469ee5588a6a2b1c774a361f2f021774e541ffb37531caff2ed59632ee64b25`.

All captures are 1920×1080/DPR1/text100%, pinned Roboto body and Arial wordmark.
Root additionally inspected the filtered custom-channel long-name state and
exercised Unchanged/Removed filters and Show all in the temporary capture harness.
All 75 existing focused behavior tests passed on the final production source;
full Flutter analysis, formatting and diff checks passed. No new layout tests or
permanent capture tests were added. The original golden harness was restored.

The user explicitly approved: “okay that makes sense and sounds good. i think we
are ready to lock then if you dont have any more critiques or refinements”. Root
had no remaining critique blocking this pass. This locks the presented 1080p
first-time, replacement (small/populated) and expanded-update states. It does not
claim separate visual approval for unpresented no-change, stale/error, Add as new,
or enlarged-text states. The frozen comparison archive remains unchanged.

Grouped adaptive/resolution/accessibility checks and physical Windows Segoe UI,
input/focus validation remain outstanding at the eventual tested commit. No
independent review is specifically recommended for this bounded pass; none was
launched. No push, deployment or publication.

### Surface13 initial comparison — September 9, 2026

User selected Library scan outcomes. Clean HEAD
`e8ad09b1cdd36b039968c29cf46490b854fd4393`. Root inspected original
`library-scan-states.html`, mixed state, in the browser. It is a natural-width
736px component, not an authored 1080p page. Root also inspected fresh actual
`build/desktop-ui/surface-13/current-e8ad09b1.png`, 1920×1080/DPR1/text100%,
SHA-256 `962d8c8c8d511fbf32ee578eb55728a5a18d952cf41b6e72ec29f632e1204e2a`.
Production source SHA-256
`4a899426d1b42906b597eb91eac47aee553edd249041ae67c46089466ddb5c9f`.
This actual render still matches the frozen packet image exactly. Synthetic
fixture has one ready, one unsupported, one empty and one failed library; the
mock has two ready, one empty and one failed. Pinned fonts/Windows limitations
remain as recorded for earlier surfaces.

Observed: old header typography and missing wordmark, library type labels far
from names, technical page/item scan details, generic global failure dominating
row outcomes, and terse footer labels. Proposed direction: approved setup frame,
bounded readable library rows, clear outcome summary and row-local statuses,
exclusion explanation above actions, explicit Retry/Continue labels and correct
none-ready/scanning actions. Brief awaits user feedback; no implementation or
worker assignment yet. Counts/reasons must use real available scan facts; the
mock's usable-media counts and specific timeout reason are not automatically
available from LibraryScanFact.

### Surface13 first-pass direction

User approved the starting corrections, emphasized closer scrutiny and asked
root to judge compactness. Root chose the shared full-width setup header with a
centered, unframed outcome/list area capped at 1040px at 1080p, with recovery and
Continue actions immediately beneath the rows. The body can grow/scroll for more
libraries; four rows should remain a readable group. Selection remains editable
in the rows rather than introducing another screen solely to change selection.

Actual assignment: existing worker_luna (GPT-5.6 Luna/xhigh), exclusive
`channel_setup_view.dart` visual lease for library body/header/rows. Root retains
state-derived summaries, action availability, honest scan wording, errors and
behavior verification, to integrate after lease release. Controller scan,
retention, cancellation and commit owners remain unchanged. Existing meaningful
selection/cancellation tests will also cover deselecting the only ready library
and cancellation with a completed row, not layout geometry.

The first candidate exposed a disconnected full-width header above the compact
body. The user explicitly requested that the heading follow the compact content
and that the group be vertically centered. This supersedes the first-pass
full-width-header placement for surface13 only. The same worker_luna received a
small exclusive presentation follow-up: move the existing header into the bounded
library column and center the complete group when it fits; preserve scrolling
for long lists, short windows and enlarged text. Other setup surfaces retain
their approved layout.

### Surface13 candidate03 — awaiting visual approval

The header, rows and actions now form one centered, bounded group. Long lists
scroll within the available height; short windows or enlarged text use a
whole-group scroll fallback. Root personally inspected fresh mixed, none-ready,
scanning, initial-selection and long-list captures, including the scrolled end.
Checkboxes and whole-row activation remain; root recommends retaining explicit
multi-selection controls rather than persistent selected-row backgrounds.

Base HEAD remains `e8ad09b1cdd36b039968c29cf46490b854fd4393`; working-tree
`channel_setup_view.dart` SHA-256 is
`ebccc1132a0e68b36df5d66133bef2e720b129fdaf44775f097d5a44fcc51edb`.
Local ignored evidence in `build/desktop-ui/surface-13/`, all actual
1920×1080/DPR1/text100%, pinned Roboto body and Arial wordmark:

- `candidate-03.png`: `b0867e4b774df72f8be0bbcdbe5a5a11777c9e02d9700cd5b7b76883ee903a09`.
- `candidate-03-failed.png`: `e3c5b588048a05bd82d997fb3502d73924a8b170921fa2e74f73d497ac3fbd04`.
- `candidate-03-scanning.png`: `ef628d63308c60d80cfb19ab1e95b53baa4eeb0e2488669531759282828bf9f5`.
- `candidate-03-selection.png`: `138da31daf21f394b2e177df481720a83bbacc47ed0464fc05066ce1846c9ba6`.
- `candidate-03-long.png`: `92109347aa70ccba958b0206db15b710172e353c9d6e02a9f6d602ad60210620`.
- `candidate-03-long.png-scrolled.png`: `db86d468353df985b0f2a751d0a351baeaef8a00bc49810216f014d0b5cff4dc`.

Root retained controller contracts, made outcome wording reflect available facts,
prevented Continue after cancellation, and disabled Select all while scanning.
Existing selection/cancellation behavior tests were strengthened without adding
layout tests. All 75 focused setup/review/app tests and full Flutter analysis
passed on this source. Two existing real-controller mixed-scan/cancellation
checks also passed before the final presentation-only follow-up. Formatting and
diff checks passed. Temporary capture harness was restored; golden baselines
and the frozen packet remain unchanged.

No surface13 approval or lock yet. Grouped adaptive/resolution/accessibility and
physical Windows font/input/focus checks remain outstanding. No independent
review is specifically recommended for this bounded pass; none was launched.


### Surface13 approval and state completion

The user explicitly authorized the lock subject to checking all page states:
“we can lock it if our all states of this page are properly adjusted”. Root
completed the remaining 1080p state inspection without production changes:
cancelled scan with a retained ready row, zero selected libraries, no available
libraries, empty/unsupported results without failures, global scan failure before
row facts, and entry from an existing lineup with Cancel. These join the mixed,
none-ready retry, scanning, selection and long-list states inspected above. All
use the corrected compact layout. Successful all-ready scans advance through the
existing `_scan`/`_commitLibraries` flow rather than requiring a new success page.
The zero-selection capture waits for the checkbox animation to finish.

This records the user's conditional approval after root's state checks, not a
claim that the user individually inspected every supplemental image. Surface13
is locked at 1080p under that authorization.

Implementation commit: `692083fcc3bf23204f87e44f43c36621717db0ae`
(`fix(ui): refine library scan states and compact layout`). Production source
hash remains the candidate03 hash above. Durable captures, copied byte-for-byte:

- [candidate-03-cancelled.png](design/desktop-ui/approved/2026-09-09-surface-13/candidate-03-cancelled.png): `35b0bc16d9af8608df592f180ea43d04496b740c3e91e6a0488aacafac12728b`.
- [candidate-03-existing-lineup.png](design/desktop-ui/approved/2026-09-09-surface-13/candidate-03-existing-lineup.png): `8b6c9ff28fd225f89d3807e1b5cecf1bce9f40c2f35bc31a58062d5f6b40f297`.
- [candidate-03-failed.png](design/desktop-ui/approved/2026-09-09-surface-13/candidate-03-failed.png): `e3c5b588048a05bd82d997fb3502d73924a8b170921fa2e74f73d497ac3fbd04`.
- [candidate-03-long.png](design/desktop-ui/approved/2026-09-09-surface-13/candidate-03-long.png): `92109347aa70ccba958b0206db15b710172e353c9d6e02a9f6d602ad60210620`.
- [candidate-03-long.png-scrolled.png](design/desktop-ui/approved/2026-09-09-surface-13/candidate-03-long.png-scrolled.png): `db86d468353df985b0f2a751d0a351baeaef8a00bc49810216f014d0b5cff4dc`.
- [candidate-03-no-libraries.png](design/desktop-ui/approved/2026-09-09-surface-13/candidate-03-no-libraries.png): `abb53c50a1abc86782c88b4c9aa351981d475649f507ee74e35fcc7c381f23c8`.
- [candidate-03-no-playable.png](design/desktop-ui/approved/2026-09-09-surface-13/candidate-03-no-playable.png): `25c872b448f16175d0ce3c8dbdf927587bdb83f1100de5e393aca8c7c9c8f37a`.
- [candidate-03-retry-global.png](design/desktop-ui/approved/2026-09-09-surface-13/candidate-03-retry-global.png): `45cd7d71566325500c963d3baed10aff60fcbf68d1d226ab6c86b07d9838c7d1`.
- [candidate-03-scanning.png](design/desktop-ui/approved/2026-09-09-surface-13/candidate-03-scanning.png): `ef628d63308c60d80cfb19ab1e95b53baa4eeb0e2488669531759282828bf9f5`.
- [candidate-03-selection.png](design/desktop-ui/approved/2026-09-09-surface-13/candidate-03-selection.png): `138da31daf21f394b2e177df481720a83bbacc47ed0464fc05066ce1846c9ba6`.
- [candidate-03-unselected.png](design/desktop-ui/approved/2026-09-09-surface-13/candidate-03-unselected.png): `1856e909af64ab0fc5cb47f6bf4abb5f0bd035a41d1a15b64c85a011d32dbdd7`.
- [candidate-03.png](design/desktop-ui/approved/2026-09-09-surface-13/candidate-03.png): `b0867e4b774df72f8be0bbcdbe5a5a11777c9e02d9700cd5b7b76883ee903a09`.

The existing 1280×720 library-outcomes golden alone was refreshed and its test
passed. It was personally inspected for composition, but its existing harness
loads Roboto only and renders the Arial wordmark as test-font blocks; it is not
font-acceptance evidence. The durable 1080p evidence loads the actual Arial font.
No new layout tests were added. The prior 75 behavior checks, two controller scan
checks and full analysis remain applicable; no production changes followed them.

Grouped adaptive/resolution/DPI/enlarged-text/accessibility checks remain open;
this limited 720p golden is not completion of that matrix. Physical Windows
Segoe UI and input/focus validation remain outstanding at the tested commit.
The frozen comparison packet is unchanged. No independent review is specifically
recommended for this bounded correction; none was launched. No push, deployment
or publication.


### Surfaces14/15 — new motion direction under discussion

User requested a significant enhancement beyond the minimal original mock:
fluid moving gradients using more screen area, with continuity from creation to
completion. Root inspected both original `setup-result-states.html` states in
browser and fresh actual renders at HEAD `52229edc9046ae3ca1dc6d4975177a8b0808c66d`.
Current progress SHA-256 `7407e45bdae1f5d4f68cb9d6f037958bcf6c9db7d0c826ae552317dfb82c18a5`;
completion `e39a99b152ec53619b423df13fd3ce1bfb697ee9ed9b36cdea3de17b1a71a1bc`.
Both still match the immutable packet. Local captures are in
`build/desktop-ui/surface-14-15/`, actual 1920×1080/DPR1/text100%.

Root prepared an exploratory conversation motion concept: broad warm light
moving across the film-gate background while saving, settling into a static
horizontal glow on completion; larger centered headline and nearby result
actions. The concept uses synthetic counts and offers intensity/state choices.
This is a proposed material departure from the minimal composition, not an
approved replacement or a Flutter implementation. Preserve real save completion,
no invented percentages or artificial delay, immediate access to result actions,
reduced-motion handling, failure recovery and held-Enter protection. No worker
assigned until the correction brief is settled. Surfaces remain unlocked.

User's next refinement: remove the loading circle/spinner and make the light
richer with more visible movement so the background conveys activity. Root
updated the exploratory concept accordingly: no spinner markup, stronger bronze
and pale-gold layers, wider travel and 8–12 second alternating sweeps, settling
into the existing calm completion glow. Reduced-motion remains static. This is
still a concept revision awaiting feedback, not a Flutter change or visual lock.

User accepted the concept brightness and requested a slight upward shift and
another small speed increase. Root raised both moving light and settled glow by
5% of the preview height and shortened the three sweep durations to 7.5, 10 and
6.7 seconds (about 20% faster), preserving color/opacity and text geometry.
The revised concept remains pending final direction approval.

User agreed to curved ribbons, removal of the success checkmark, concise result
information and a tighter grouping, with a final request for a natural, fluid
transition. Root revised the concept to keep the same light layers through the
transition: native animation playback decelerates to zero over 1.3 seconds while
light intensity eases to 38%; no separate replacement backdrop. Result text and
actions appear promptly, without waiting for the atmosphere to stop. The success
mark is removed; the failure mark remains. Root inspected creation and settled
completion in browser. This establishes the implementation direction, but no
Flutter implementation or production-state lock has occurred yet.


### Surfaces14/15 — Flutter candidate02 awaiting visual approval

User accepted the revised HTML direction: “this looks great and im ready to
lock,” then agreed to implementation with “sounds good.” Root clarified that the
concept omitted the shared logo-first LINEUP header and production would restore
it. This approval covers the design direction; the actual Flutter candidate still
requires explicit visual approval before production lock or implementation commit.
The durable concept is `docs/design/desktop-ui/setup-result-fluid-light.html`
(SHA-256 `3ca74b94c53834d6b396a9c387a65a062aa47121043251c8010ce4c186f3dfbf`).

Actual assignment: existing `setup_frame_correction` worker, exposed
`worker_luna` / GPT-5.6 Luna / xhigh, exclusively owned
`lib/app/channel_setup_view.dart` for header, centered result hierarchy and
nearby actions. Root retained motion/lifecycle ownership in
`lib/app/setup_result_atmosphere.dart`, behavior checks and integration. Worker
released its file lease; root personally reviewed the diff and final renders.
No independent reviewer or additional user-facing task was launched.

Candidate02 preserves the same curved light layers through the 1.3-second coast,
with immediate completion actions and a 420ms content reveal. Reduced motion is
static; failures retain their meaningful error mark and recovery action. Spinner
and success checkmark are removed. Existing-lineup changes omit zero counts.
No persistence, save timing or held-Enter contract changes.

Evidence remains local in `build/desktop-ui/surface-14-15/` pending approval.
All PNGs are actual 1920×1080 Flutter renders, DPR1/text100%, with synthetic data,
Roboto body and actual Arial wordmark; no upscaling. Root inspected progress,
completion, existing-lineup completion, failure, reduced-motion completion and
transition frames. Source HEAD is `52229edc9046ae3ca1dc6d4975177a8b0808c66d` plus:

- `lib/app/channel_setup_view.dart`: `787379dff4853c95e866efb656b0e28ff0bcebe06e10978e9373290622ce0d19`
- `lib/app/setup_result_atmosphere.dart`: `744405b113085be021bb99b29dca6802a2aa97a91c2991edfced381200e3fcbc`

Candidate PNG SHA-256 values:

- `candidate-02-progress.png`: `a9ab2cb6fec9d17807c9bf3367208feee571e2f4d01f0dee015867c116ffb3de`
- `candidate-02-complete.png`: `fbdafd08d257a22e255ece55c241fc840151d1ee094fe67e6fc1d0b1127e2430`
- `candidate-02-existing-complete.png`: `61cf48a41d661d0be847eb130f0d9e0d957b6a7db398b0c6b6b4364a3827d35b`
- `candidate-02-failed.png`: `925e984d3b147c96eff514c63b9167a0925ab6e0790f1f2a6707244731dd4143`
- `candidate-02-reduced-complete.png`: `b5262ab1e747e3efe7906836b7cc8af696a975bd99a66c1ad024faf35832c378`

`candidate-02-transition.mp4`: `cad2f74de71b61b8d367563d37ea4916c3e7b0600c4afccf77dc8d49859d4f34`.
The six-second recording encodes 120 original Flutter frames at 20fps, with
completion at frame70; no resizing. Its JSON records all frame hashes and source
identity. This demonstrates appearance and simulated transition timing, not
physical Windows frame pacing or GPU performance.

Final 75 existing setup/review/app behavior checks passed, including immediate
completion actions, held-Enter protection and stopping/restarting animation for
reduced motion. No new UI layout tests were added. Grouped adaptive dimensions,
DPI, enlarged text, accessibility and physical Windows Segoe UI/input/focus/motion
performance checks remain open. Frozen comparison packet unchanged. Independent
review is not specifically recommended for this bounded visual correction.

Full pinned Flutter analysis passed with no issues; formatting and diff checks
passed. No source changes followed the candidate02 captures.

### Surfaces14/15 — approved and committed

User: “yes looks great. locked. ready for 7,8,and 9 the linking surface.”
Candidate02 is visually locked at 1920×1080/DPR1/text100%, including the
progress-to-completion transition and associated state family reviewed above.
Implementation commit: `22743fd6262773bf96e6295c06504a2923ba1de4`. The source hashes match
the reviewed captures; no production changes followed those checks.
Durable [approved evidence](design/desktop-ui/approved/2026-09-09-surface-14-15/evidence.json)
binds the original PNGs and 20fps transition recording to this commit.
Grouped adaptive/accessibility and physical Windows checks remain outstanding as
listed above. Frozen comparison packet unchanged. No push, deploy or publication.

### Surfaces07–09 — focused linking audit started

User requested one subagent review of the mock versus implementation across all
linking states before agreeing refinements, with a compact first review and final
lock confirmation to conserve usage. Assigned `linking_visual_audit`, exposed
worker_luna / GPT-5.6 Luna / xhigh, read-only except ignored local evidence.
Root reviews its evidence and proposed brief; no implementation is approved yet.


Surfaces07–09 audit completed read-only by worker_luna; root personally inspected
rendered plex-linking-hybrid HTML and fresh normal, expired, browser-launch failure
and terminal-failure Flutter images. Evidence is local under
`build/desktop-ui/surface-07-09/fresh/`, 1920×1080/DPR1/text100%. The reference is a
736px natural-size component, not an authored full-screen 1080p mock. Initial
capture logo decode and standalone DEBUG-banner artifacts were identified as
harness issues, not production defects. Secure-cancellation and pending-request
states were considered from contracts/source but not separately visually captured.

Worker recommends compact wrapper correction while retaining existing inner
geometry. Root agrees with compactness and preserved state behavior, but proposes
modest desktop readability enlargement: approximately900px maximum centered group,
36px heading,18px instructions/actions,40px code and200px QR at1080p. Use logo-first
LINEUP branding aligned above the group, remove the nearly full-width panel border,
and constrain errors/status to the local group. Keep a shorter no-code recovery
composition for terminal failure, expired placeholder only for expired codes,
quiet Cancel, existing theme, responsive stacking/scroll fallback. These are
proposals awaiting user agreement, not approved implementation or visual lock.
No tracked implementation files were changed during the audit. Existing onboarding
and controller behavior checks will be reused; no new UI layout tests proposed.

User approved the compact linking brief: “yes approved, lets make the changes
and do one quick visual check after”. Root assigned the existing worker_luna
exclusive `lib/app/onboarding_view.dart` presentation changes, preserving shared
onboarding surfaces and all linking contracts. Root owns the reused ignored
capture harness and existing onboarding checks. No extra visual refinement loop
is planned before presenting candidate01 for explicit approval.

### Surfaces07–09 — candidate01 awaiting approval

Luna implemented linking-only presentation in `lib/app/onboarding_view.dart`.
Root made bounded integration fixes for group alignment, quiet Cancel/status and
inheritance of the existing text font. No shared onboarding surface was changed.
The actual inner group is736px wide within a900px cap, increased from the previous
560px body, with aligned branding above and a200px QR. No border surrounds it.
Root briefly inspected all four final captures under
`build/desktop-ui/surface-07-09/candidate-01/`; 1920×1080/DPR1/text100%.
Source base `e9d4411982a052ce5283b2a17e81b0a787fbaf0e`, source SHA-256
`3b40cb913f5761ced6d8f6a8d555151cf433df4574b1ebf5ad7bf22b317e1f60`. Capture hashes:

- `surface-07-linking-browser-failure.png`: `904f861fd20ace2d9000a9261f2f134d537b2256595ec95d52680bdfe6cef1d6`
- `surface-07-linking-normal.png`: `68d1d7897c661d9e3da320b22bd2c63728cb06d07a67f2a5d2283701fa81b945`
- `surface-08-linking-expired.png`: `465eff4c81c4c50b81d72467c0ea06c6522eddf4d2a453fd5d47ddf9fac70094`
- `surface-09-linking-terminal-failure.png`: `e0e18ca408545bc0ddc4dfb9df8038f4859eaaa5d28ed6e2887cbdb3f6fa9b7a`

All9 existing desktop onboarding behavior checks and the temporary four-state
capture run passed (10 total). No new layout tests. Candidate remains unlocked
until explicit user visual approval. Adaptive/enlarged-text/accessibility and
physical Windows checks remain grouped and outstanding. No additional independent
review recommended for this bounded presentation change.

### Linking approved; profiles and servers next

User explicitly locked linking: “locked. time for profile selection, profile pin,
and server selection.” Implementation `3a9d6b7e860172d9426dc1d278ed6a48f2f073af`;
[durable evidence](design/desktop-ui/approved/2026-09-09-surface-07-09/evidence.json)
retains the reviewed four-state candidate01 PNGs and source hashes. Final file
analysis passed. Adaptive/accessibility and physical Windows checks remain open.

User authorizes the same compact styling for profile and server selection, with
more horizontal room for two profile rows and sensible refinements at root
discretion. PIN is explicitly deferred, untouched and not visually locked. The
ledger IDs are10 profiles,11 PIN,12 servers (user used11/12/13; names govern scope).


Root inspected the original profile/server HTML fragments in standalone browser
wrappers and their actual1080p baseline Flutter captures, then read current owners.
The oversized bordered wrapper and standalone centered logo are the main mismatch;
profile layout currently stretches nine fixture users across one row. User permits
root discretion and requests wider profile composition retaining two rows.
Assigned existing worker_luna/GPT-5.6 Luna/xhigh exclusive
`lib/app/onboarding_view.dart`: reuse compact brand frame with unchanged linking
defaults; profile group max1080, two desktop rows with wrapping names and modestly
larger avatars/type; server group max880 with open rows, larger heading/type and
local status/errors/actions. All callbacks, semantics, focus, currentness and
verified connection facts preserved. User reiterated skipping PIN visual review;
no PIN implementation or capture is authorized in this pass. Root owns the reused
ignored two-screen capture harness and existing behavior checks. No extra reviewer.

### Profile/server candidate01 — awaiting visual approval

Luna implemented the assigned presentation in the sole leased file; root reviewed
the diff and made bounded fixes for configured action fonts, content-driven row
heights/avatar alignment, and the existing sub-pixel-width regression. All9
existing onboarding behavior checks plus the two-screen capture harness pass
(10 total). No new layout tests. PIN dialog source is byte-identical to HEAD and
was neither modified nor visually captured. Root inspected profiles and servers
with synthetic fixtures at1920×1080/DPR1/text100%; these remain unlocked.
Local evidence: `build/desktop-ui/profiles-servers/candidate-01/`.
Base `f9f8c93afa8d8cd3615381d8315144759921ea09`; onboarding source SHA-256
`6d9348e3d78340e454e9159c6b7aa6f94afaa2a183bfce98fa80343f4eede4f5`.

- `servers.png`: `384bbe3ec3a0568fde1e811dec3d427c2cb2e1870b66c19167b5483d5ad4ca51`
- `profiles.png`: `4094852a3a5fd5775f1156ae3d7086f6761d200e86b88cef75a5b9605681a962`

Grouped adaptive/accessibility and physical Windows checks remain outstanding.
No additional independent review specifically recommended for these bounded
presentation changes; none launched. No push/deploy/publication.

User requests candidate01 refinements: independently center incomplete profile
rows under the full row, and move Current away from the server row top-right.
Root assigned Luna the same exclusive file for independent row centering and
a quiet inline amber Current badge beside the name, with lighter supporting
connection text. Preserve state behavior, PIN and other approved surfaces.

### Profile/server candidate02 — awaiting approval

Luna applied only independently centered profile rows and the inline amber Current
badge with lighter supporting connection text. Root inspected both final actual
1920×1080/DPR1/text100% captures. All9 onboarding behavior tests plus capture run
passed; worker formatter/file analysis/diff checks passed. No PIN edits/capture.
Local evidence `build/desktop-ui/profiles-servers/candidate-02/evidence.json`.
Working-tree source SHA-256 `f48e7dfe6ebcd783c308d00ea196b17565d8809e6e1930936ca59aa838d5fd5a`.

- `servers.png`: `a817665965ecee6fe8890e46a91190406af6a5b687657b82e691a272991b990b`
- `profiles.png`: `20d693ca5d54b0c948a00e224d58244830b7edb19d987be136b8ec020839e028`

Approval remains pending. Existing adaptive/accessibility/physical Windows
limitations remain open; no additional independent review recommended.

### Profile/server selection — approved and committed

User explicitly approved candidate02: “locked”. Profile selection (surface10) and
server selection (surface12) are visually locked at1920×1080/DPR1/text100%.
Implementation commit `019f4b0c8c3a9ec93abed57b31e38c714113b4c1` matches the approved source hash.
[Durable evidence](design/desktop-ui/approved/2026-09-09-profiles-servers/evidence.json)
records the approved PNG hashes, implementation commit and verification.
PIN (surface11) remains untouched and unreviewed, explicitly excluded by user.
Grouped adaptive/accessibility and physical Windows checks remain outstanding;
no additional independent review specifically recommended. No push/deploy/publication.


## September 9, 2026 — surfaces 16/17/18 correction brief

The user approved the proposed first pass: “yes lets do that”. This approves
implementation, not a visual lock. Root personally inspected the three rendered
states of `channels-management-refined.html` at its authored 1920 variant and the
frozen Flutter packet; a fresh affected-state baseline was also captured from
`bc124be413ae928ed02c4109f8be335a476c0059` before edits.

- Add the thin LINEUP/Channels header divider. Use a 36px heading and adjacent
  baseline-aligned 28px quieter count, with no dot; identify reorder in the heading.
- Remove the search magnifier and use 48px minimum toolbar controls, 18px labels,
  borderless filters/actions and a subtle selected fill, preserving keyboard focus.
- Target 80px minimum rows with 22px names and 18px supporting values. Preserve
  wrapping and content growth, quiet separators and consistent column alignment.
- Put selection checkboxes near channel identity at the left; separate selection
  tools from Cancel/Delete at the right and give deletion a destructive treatment.
- Give reorder the directory's number/name/source/playback structure, drag handles
  and existing move controls, with Cancel/Save at the right. Preserve number gaps,
  old-to-new previews, identity, draft persistence boundaries and stale validation.
- Keep all existing search/filter, selection, focus, health and mutation behavior.
  No UI layout tests, independent reviewers or unrelated surfaces are included.

Local iteration captures use real Flutter widgets at 1920×1080/DPR1/text100%,
with 12 synthetic channels to judge density. The original packet remains frozen.
Adaptive resolutions, DPI/enlarged text, grouped accessibility and physical
Windows validation remain outstanding; pinned-font captures are not Windows
font-rendering evidence.

### Candidate05 — awaiting visual approval

Luna implemented the presentation changes in `lib/app/channels_view.dart`; root
reviewed and corrected selection-mode action visibility, compact spacing, toolbar
height/focus styling and reorder glyph fallback. Existing Channels/Studio checks
passed (73 tests); final expanded-only filter sizing was captured with real widgets.
Targeted analysis and formatting passed. No new UI layout tests or independent
review were added. Independent review is not specifically recommended for this
presentation change.

Source SHA-256: `aed854332dab44933a3bfc2ec6637221d6132e890a4765e4478dfe017decafdb`. Local affected-state evidence:
`build/desktop-ui/surface-16-18/candidate-05/`, 1920×1080/DPR1/text100%.

- `directory.png`: `64d213023ce0c21c67dcdc37578d8dd2e5f40cda4087f166d1286da3aac00bf9`
- `reorder.png`: `81c41786431de87d67007660fd6fa6040bc37012ccaf6df0e06e34d447e92c60`
- `selection.png`: `7bf927c3405af7e0dd72efbb417698d8c54a25310b2e2de6d5c0fff94852e53c`

States: directory with twelve synthetic channels; selection with two checked;
reorder with the first two channels swapped and number gaps retained. Captures use
pinned Roboto with Arial fallback for the arrow glyph, not physical Windows fonts.
No visual lock or implementation commit yet; adaptive and Windows checks remain
outstanding as described above.


### Candidate06 — Cancel alignment refinement

User accepted the general candidate05 treatment and requested one correction:
“in 17 and 18 the cancel text next to the delete button in 17 and save order
button in 18 looks wonky and off not being aligned with the button.”

Only the two action groups changed: center the Wrap cross-axis and give Cancel
matching vertical padding while retaining its quiet text styling. Luna made the
bounded edit; root reviewed both fresh affected-state captures. Six existing
Channels behavior checks, formatting and diff checks passed. No directory
recapture or new tests were needed. Final visual confirmation remains pending.

Source SHA-256: `e140c51bca21f87928685368227e07a969dc9413a42969989cdb84e6ed018bb2`. Evidence:
`build/desktop-ui/surface-16-18/candidate-06/`, 1920×1080/DPR1/text100%.

- `reorder.png`: `b5c50857560492029c70822f0534b72294837653c41f351f723312ddf3bb3b2c`
- `selection.png`: `4cc873992879db56dadbef8f15307befbfc2a7ef73423d54e5c2cd91da6c6285`

Adaptive, grouped accessibility and physical Windows checks remain outstanding.
No independent review is specifically recommended for this alignment adjustment.

### September 9 — surfaces16/17/18 locked

User explicitly approved: “locked. now for 19”. Directory candidate05 and
selection/reorder candidate06 are approved at1080p. Implementation `d98e97617fc01b1c947d96326af931d022d07e86`;
source and capture hashes are bound in
[durable evidence](design/desktop-ui/approved/2026-09-09-channels/evidence.json).
Adaptive, grouped accessibility and physical Windows validation remain pending.
Independent review is not specifically recommended.


## September 9 — surface19 delegated correction brief

User: “we dont have a mock, id just like you to consider its purpose and create
 youre recommended ground up panel for this function ... ill defer to your recs
totally on this panel.” This authorizes the proposed implementation direction;
visual approval of the result remains pending.

Root inspected current real 1080p one-channel and twelve-channel mixed deletion
confirmations. Use the accepted Ember & Steel language for a compact opaque
centered panel, approximately680px wide: clear deletion count, readable
custom/generated summary, explicit Plex-media preservation and generated-channel
recurrence copy, and a scrollable roster with aligned numbers/full wrapping names.
No decorative warning icon or duplicated checkbox list. Content determines short
panel height; long content scrolls within viewport bounds. Match Cancel/Delete
alignment, initially focus Cancel, use a clearly labeled destructive-color action.

Luna owns only the private panel widget in `channels_view.dart`. Root wires both
single-row and batch deletion to it while preserving callbacks, snapshot validation,
retry/focus behavior and mutation boundaries. Existing regression checks are reused;
no UI layout tests or independent reviewer are added.


### Surface19 candidate02 — awaiting visual approval

Root integrated the shared panel into single-row and batch confirmation, retaining
transaction, selected-snapshot, currentness, retry and focus behavior. The panel
has an owned/disposed scroll controller with visible thumb, route-title semantics,
opaque primary surface, 680px maximum width and720px maximum height at1080p.
Short selections determine their own smaller height; larger rosters scroll while
consequences and Cancel/Delete remain visible. Cancel retains initial focus.

Six existing Channels behavior tests, targeted analysis, formatting and diff
checks passed. Root inspected fresh single-row deletion and mixed twelve-channel
batch captures, including the bottom of the scrollable roster. No UI layout tests
or independent reviewer were added; independent review is not specifically
recommended. Adaptive/DPI/enlarged-text, grouped accessibility and physical Windows
checks remain pending.

Source SHA-256: `2318f34d3f4f7bc7b58cd1970fdb89a5e01b3498306e564ef33e6ce2c0c95adf`. Local evidence:
`build/desktop-ui/surface-19/candidate-02/`, 1920×1080/DPR1/text100%.

- `mixed-scrolled.png`: `f22e85b37f63fa12f3f10110ef7738b990058e897b3ebc161eac9efd1e922493`
- `mixed.png`: `f3785b4559735fb275df9e46215c93b32f3b2a41f0210b549d5399a5667e4019`
- `single.png`: `785c1917b6a916a83c9df87307f1075285ee13927197e718a5c02a98d5d2f93a`

Surface19 is not visually locked or committed pending user confirmation.


### September 9 — surface19 locked with final text-only amendment

User approved: “remove the rest and its locked. you dont need to inspect the
visual or show me a visual after this small change we are only removing text”.
Keep the heading, lineup-removal/irreversibility explanation, channel roster and
actions. Remove the Custom/Generated breakdown, Plex-media reassurance and
regeneration note. Deletion and generation behavior are unchanged. The active
specification now reflects this later user decision.

No final visual inspection or recapture was performed, as explicitly requested.
The durable PNGs are clearly labeled **before-final-copy**: they establish the
reviewed panel design before the approved text removal, not an exact rendering of
the final commit. Six existing Channels behavior tests, targeted analysis,
formatting and diff checks passed; the existing scope assertion now checks selected
channel identities rather than removed summary text. No new UI layout tests.

Implementation `aa25168f267655bf9b76311c1fa8307e70f604f3`; source hashes, prior-capture boundary and
user waiver are recorded in [durable evidence](design/desktop-ui/approved/2026-09-09-delete-confirmation/evidence.json).
Adaptive, grouped accessibility and physical Windows checks remain outstanding.
Independent review is not specifically recommended.


## September 9, 2026 — surfaces 20–24 correction brief

The user grouped all five Studio surfaces for shared header/spacing corrections,
with root-recommended refinements for browse sources (22), which has no standalone
mock. Base `abde710564aa201b2f7289c905203ea04632b64c`, clean before this work.
Astra inspected the rendered final playback-space HTML, filter-picker B and
Library editor references, and fresh production-widget Studio captures. Frozen
comparison entries 20 and 21 share the same image; the portable packet remains
unchanged.

- Separate back navigation/context from the channel title/status and save/tune
  actions. Remove the oversized amber number tile; retain the editable number
  and accessible channel identity.
- Increase local Studio typography and use the mock's compact playback dropdown
  and shared settings hierarchy without changing scheduling or save contracts.
- Group browse filters horizontally, preserve Add/Added and bulk selection, and
  provide more room for program results. Align Library/Collection and filter
  controls with the same editing workspace.
- Enlarge schedule-preview headings, selected-program details and rows, and use
  more available height. Preserve loading/stale/error and selection behavior.
- Give filter picker B a clear heading, readable choices and stable Done/Cancel
  actions. Preserve pending choices, cancellation and focus restoration.

Worker assignment: existing `worker_luna` / GPT-5.6 Luna / xhigh, exclusive
`lib/app/channel_studio_view.dart`; Astra owns schedule-preview presentation,
capture harness, integration and documentation. No new UI layout tests.
This is an implementation brief, not visual approval.


### Studio first candidate — awaiting visual approval

Astra integrated the initial Luna presentation work and completed the dropdown,
Mini-marathon shared row, local typography/Material host, browse filter grid and
preview geometry. Existing Library five-result sample behavior is preserved.
Only existing playback-control selectors changed in the behavior suite; no new
layout tests were added. All 67 Studio and 24 Air Check behavior checks passed,
including existing reflow/enlarged-text checks; this is not a physical Windows
or complete adaptive visual acceptance claim. Fresh affected-state capture runs
also passed. Analysis of the two production files and updated test file passed.

Local evidence: `build/desktop-ui/surface-20-24/review-evidence.json`, candidate04
hand-picked, browse, populated Library, populated filter picker and empty playlist;
candidate05 Mini-marathons corrects the block-size label width. All images are
1920×1080/DPR1/text100%, with synthetic content. Non-Mini-marathon candidate04
images remain visually current after the isolated Mini-marathon correction.
Subsequent Shuffle wording cleanup does not affect the captured modes.

Current source hashes:

- `lib/app/channel_studio_view.dart`: `9e256683e2a13b07698471581b5d76fe8a93194c22dc3f30d3b506ccdda344b8`

- `lib/app/channel_air_check.dart`: `24a9587cee7aa6c2d34983d29711feebbb67ede0d00b5cd982b947868bca722f`

No surface is locked or committed yet. User visual feedback is the next step.
Remaining checks: grouped adaptive visual review (including1440p/2160p and
enlarged text), accessibility checkpoint and physical Windows input/rendering
validation. Independent review is not specifically recommended for this
presentation-only pass.


### Studio second-pass brief — changes requested

The user requested another critical pass: remove the playback helper, replace
the Browse library/Channel programs pills, fix the Media type field's missing
persistent label, and organize Library programming into aligned controls and a
clear results section. The user also prefers the mock's slash between LINEUP
and CHANNEL STUDIO. None of the first-pass candidates is approved.

Astra re-inspected the rendered Library mock and candidate04. The second pass
uses flat underlined view tabs, a persistent Media type label with All types,
unified labeled Library/Collection/filter fields, a quieter watched-items control
and a separated Matching programs section. Required validation explanations,
filter pending-state/focus behavior and five-item sample remain unchanged.
Existing worker_luna / GPT-5.6 Luna / xhigh owns only the Studio view file for
this bounded correction; root retains tests, capture and acceptance review.


Worker-context preference recorded during the Studio second pass: use a fresh
Luna worker per new surface family/type, then reuse it only within that family.
The user explicitly permits continuing with the current worker for Studio; the
[collaborative handoff](desktop-ui-collaborative-handoff.md) now carries this
standing preference.


### Studio second-pass candidate07 — awaiting approval

Applied the requested slash separator, removed redundant playback helpers,
replaced pills with underlined view tabs, and made Media type an always-labeled
field showing the existing All types choice. Library/Collection and filter
controls now share field styling, full-field click targets and visible keyboard
focus. The watched-items setting is quiet and bounded; Matching programs has a
separate heading and aligned row dividers. Astra also softened schedule metadata.

Astra inspected the fresh candidate07 hand-picked, browse, Library, multi-value
Library, filter-picker and Mini-marathon captures. The 67 Studio and24 Air Check
existing behavior checks pass; only the two obsolete Choose-button selectors
changed in this pass. Captures and targeted analysis pass. No layout tests added.
Local source/capture hashes and reproduction metadata are recorded in
`build/desktop-ui/surface-20-24/second-pass-evidence.json`. All captures use real
Flutter widgets at1920×1080/DPR1/text100% with synthetic content.

This candidate is not locked. Prior Studio candidates are superseded. Grouped
adaptive visual/accessibility and physical Windows checks remain pending; no
independent review is specifically recommended for this presentation pass.

- Candidate07 `lib/app/channel_studio_view.dart` SHA-256: `44fd569e9c4c1dc3774132e9e4cc984b50640a2a8c8e8bbb07f73b018801e18a`

- Candidate07 `lib/app/channel_air_check.dart` SHA-256: `51db45d939275c52c6a6d439298c6585c36e85fb3f65bcc43c7b51d7b6aa51ae`


## September 9, 2026 — Studio surfaces 20–24 approved

User approval: “looks good. we can lock it”. This approves the presented
candidate07 Studio family at 1920×1080/DPR1/text100%: shared hand-picked/full
authoring (20/21), browse sources (22), Library programming including populated
filters (23), and filter picker (24). This supersedes the awaiting-approval
status above. Mini-marathon and empty-playlist captures are supplemental family
evidence, not separately presented state approvals.

Implementation commit: `8c0617c78ed8fd922447571b871f354be8a7ec85`.
The [versioned evidence manifest](design/desktop-ui/approved/2026-09-09-channel-studio/evidence.json)
records the exact source and seven unmodified capture hashes, approval, state
scope and checks. Captures use synthetic content without supplied artwork.
The frozen comparison packet remains unchanged.

All 67 existing Studio and 24 Air Check behavior checks passed, as did targeted
analysis and capture checks. No UI layout tests were added. Existing deterministic
reflow/enlarged-text checks passed; qualitative 720p/1440p/2160p, DPI/enlarged-text,
grouped accessibility and physical Windows validation remain pending. This is
a 1080p visual lock, not complete adaptive or platform acceptance.

Independent review is not specifically recommended for this presentation-only
pass. No push, deployment or publishing is authorized. Future surface families
start with a fresh Luna worker; reuse is limited to the same family.


## September 9, 2026 — Guide 25/26 polish proposal

User requested a fresh Luna implementation worker for this family, mock-led
header and information hierarchy, stronger artwork bleed, aligned controls without
a search magnifier, quieter channel identity, and varied program durations in
evidence. The user asked for recommendations on retaining a stable PiP region
with a static effect when playback is unavailable. This direction remains under
discussion; no implementation worker has been dispatched yet.

Astra inspected the rendered guide-timeline.html fragment and fresh current
Flutter captures at 1920×1080/DPR1/text100%, using an ignored copy of the existing
acceptance fixture with 15/30/45/60/105-minute programs and staggered anchors.
Baseline source: c6f301a23119a39e305a376f612e8010ec8a42ed. Local evidence:
`build/desktop-ui/surface-25-26/baseline`. The synthetic baseline has no supplied
program artwork, summaries or decoded video; its amber fallback does not prove
artwork-color behavior. Later review fixtures should include synthetic artwork,
episode metadata and summaries. The original comparison packet is unchanged.

Proposal: larger light Arial LINEUP wordmark and trailing menu chevron; preserve
optional header playing context. Vertically balance the program information,
use show/title then episode identity, remove Airing now, retain future context,
and bound the progress lane. Broaden artwork-derived color while preserving
background preferences, legibility, 400ms transition and Reduce Motion. Keep the
PiP geometry stable with quiet silent static and an in-place status when
unavailable; freeze the effect for Reduce Motion. Align toolbar controls and
remove the search magnifier. Preserve five rows, increase program text hierarchy,
quiet cell separation, and replace the tuned rail icon with a Watching label.
Preserve accurate time geometry, title-first narrow-cell rules, focus, selection,
tuning and existing channel provenance where useful. Root retains playback
state/contracts; a fresh worker_luna will receive only settled Guide presentation
work after agreement. No UI layout tests or independent reviewers.


### Guide correction brief accepted — implementation in progress

The user replied “sounds good” to the complete first-pass proposal above. This
approves implementation, including stable PiP/static treatment, not a visual lock.
Actual assignment: fresh `guide_polish` worker, exposed `worker_luna` role
(GPT-5.6 Luna/xhigh), exclusive `lib/guide/guide_view.dart`. Astra owns the
Guide-only playback placeholder, shell integration, fixtures, checks and review.
Shared Player OSD/Now Playing and native playback owners remain unchanged.

The existing timeline behavior check mixed a fixed Guide clock with wall-clock
channel anchors. Its fixture is being made deterministic using that same fixed
clock; no layout assertions are added. Existing shell coverage is extended for
unavailable status and navigation away.


### September 12, 2026 — Guide candidate03 awaiting visual approval

Resumed at the same HEAD with existing changes preserved. The fresh Guide Luna
unit was interrupted after its main presentation edits; Astra completed
integration and fixed rounded-border painting, text-height measurement and
small-space overflow. Details center when they fit and scroll when necessary.
The shell keeps a stable Guide PiP region for idle, supported and unavailable
states, with a Guide-only silent static effect for unavailable playback and
the existing Retry callback when available. Reduce Motion freezes the effect.
The protected Player views and native owners are unchanged.

Astra inspected three fresh candidate03 1920×1080/DPR1/text100% captures, using
staggered synthetic program durations, episode metadata, summaries and decoded
poster-derived color. The supported PiP fixture has no decoded video; still
evidence does not validate the static animation or Windows composition. Source
and image hashes are in `build/desktop-ui/surface-25-26/review-evidence.json`.
98 behavior checks and three affected-state capture checks passed; targeted
analysis and diff whitespace checks passed. One existing fixed-clock fixture was
repaired and one unavailable-state behavior check added; no UI layout tests added.

Surfaces 25/26 remain in review, awaiting explicit user visual approval. Grouped
adaptive/accessibility, motion appearance and physical Windows checks remain
pending. Independent review is not specifically recommended for this bounded pass.
The frozen comparison archive and separately extracted packet are preserved.


### September 12 — Guide focus/playback refinement approved for implementation

User accepted removing competing watched-channel illumination and permits a
root-defined playback indicator. Settled brief: neutral unfocused channel rail;
small static play icon plus Watching label in secondary text; no pill/glow or
channel-name recoloring for playback alone. Reserve a brighter warm fill and
strong text for keyboard focus. Remove the normal cell outline, retain the
Large focus indicators outline. Quiet persistent inspection and hover must not
compete with keyboard focus. Root retains truthful playback-state integration;
Luna handles bounded Guide presentation only. No visual lock is implied.

Use a fresh GPT-5.6 Luna/xhigh user-facing task rather than a subagent. Do not
monitor progress; integrate after completion. Current candidate03 and existing
uncommitted changes are preserved; frozen comparison packet remains unchanged.


### September 12 — Guide candidate04 awaiting visual approval

User relayed Luna completion and file-lease release on the shared active branch.
Astra reviewed its incremental change and supplied an explicit playback channel
from the shell: playing/paused/buffering/seeking, excluding errors and active
tuning. Idle, loading/ready-only, stopped/ended and unsupported states no longer
claim Watching; the optional header uses the same input. Browsing focus never
changes that playback identity. Existing semantics/context checks now supply
explicit playback, and the existing focus/context test also verifies its removal
while the remembered channel remains unchanged.

The watched rail has a neutral background with a small static play icon and
Watching text. Focus alone uses the stronger warm fill and text, without the
normal outline; Large focus indicators retains its stronger indication. Astra
personally inspected fresh 1920x1080/DPR1/text1 idle, unavailable, synthetic-playing,
15-minute focused and 60-minute focused captures. Local source/capture hashes:
`build/desktop-ui/surface-25-26/candidate-04/evidence.json`.

Luna reported 80 scoped checks passing. Root Guide/shell checks (40) and capture
cases (3) passed; after extending the existing playback-context regression,
28 Guide checks and the three capture cases passed again. Targeted analysis and
whitespace checks passed. No new UI layout tests or independent review.
Independent review is not specifically recommended for this bounded correction.

Surfaces 25/26 remain in review. No commit or lock yet; grouped adaptive and
accessibility, motion review and physical Windows evidence remain outstanding.
Synthetic playing status/blank PiP does not prove native playback.

## September 12 — Guide surfaces 25/26 locked at 1080p

User explicitly approved: “yes if you have no further refinements, locked.”
Astra has no further refinements for this pass. Candidate04 is approved at
1920×1080/DPR1/text100%: outline-free normal focus, quiet playback identity,
and unavailable playback presentation. Presented evidence includes 15-minute
and 60-minute program focus on channels other than the watched channel.
Idle and initial synthetic-playing captures remain supplemental evidence.

Implementation commit: `e0834448e25cd9592d38466df97b852b9052ac6a`.
[Durable source/capture evidence](design/desktop-ui/approved/2026-09-12-guide/evidence.json)
records exact hashes, verification and the user's approval. Source hashes were
rechecked against the accepted candidate immediately before committing. No
additional UI changes or recapture occurred after approval. The frozen comparison
packet and separately extracted copy are preserved.

Existing focused checks passed as recorded above. No UI layout tests were added.
Grouped adaptive resolution/DPI/enlarged-text, accessibility and physical Windows
checks remain pending, as does unavailable-static motion appearance. Synthetic
playing status and a blank PiP do not establish decoded video or native layering.
Independent review is not specifically recommended for this presentation pass.
No push, deployment or publishing was performed.
