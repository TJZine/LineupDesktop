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
| surface-07 | Linking · corrected | Unreviewed | Not assessed in this pass | — |
| surface-08 | Linking expired · corrected | Unreviewed | Not assessed in this pass | — |
| surface-09 | Terminal linking failure | Unreviewed | Not assessed in this pass | — |
| surface-10 | Profile selection | Unreviewed | Not assessed in this pass | — |
| surface-11 | Profile PIN | Unreviewed | Not assessed in this pass | — |
| surface-12 | Server selection | Unreviewed | Not assessed in this pass | — |
| surface-13 | Library scan outcomes · corrected | Approved at 1080p | Behavior checks passed; adaptive/Windows pending | Candidate03 state family; `692083fc` |
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
