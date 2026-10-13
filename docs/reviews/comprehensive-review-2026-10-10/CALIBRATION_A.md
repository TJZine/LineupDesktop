Calibration complete at HEAD `4fb7758034f4f47290fae13a4ea8275860ba1284`. **Keep all three findings**, with the limits below. No source changes or probe executions were performed by this reviewer; `git diff --name-only -- lib test` remained empty.

**Duration validation — keep, S2 Medium, High confidence.**

Malformed PMS metadata reaches the scheduler through real production owners:

- [parseMediaItem](/Users/tristan/Software/LineupDesktop/lib/plex/plex_client.dart:1694) accepts `9007199254740991` milliseconds under its general numeric bound.
- Positive duration and a nonempty Part path satisfy `isPlayable`; `channelItemFor` preserves that duration.
- [buildSchedule](/Users/tristan/Software/LineupDesktop/lib/channels/scheduler.dart:111) rejects only nonpositive durations and accumulates the loop without overflow validation.
- [programAt projection](/Users/tristan/Software/LineupDesktop/lib/channels/scheduler.dart:259) constructs start/end dates that can exceed Dart’s supported range.

The parent’s reported real-owner probe supplies behavioral evidence: ordinary `1800000ms` projects successfully; one oversized item builds but projection throws `RangeError`; two oversized items produce a negative loop duration and fail projection. I inspected the probe source, but did not execute it. Its passing characterization assertions demonstrate the defect, not successful acceptance.

The typed fallback does **not** contain this path. The worker returns the successfully built schedule without projecting it. [Guide completion](/Users/tristan/Software/LineupDesktop/lib/guide/guide_controller.dart:771) caches it before projection; its sibling `onError` handles loading failures, not exceptions thrown by the success callback. Those errors belong to the returned future, consistent with [Dart’s Future.then contract](https://api.dart.dev/dart-async/Future/then.html). Subsequent cached projection paths also lack containment. Initial Air Check projection has the same callback seam.

Bound the finding to affected schedules and consumers. This requires malformed metadata from the selected PMS; it is not evidence of a public exploit, data loss, credential exposure, or a fatal application crash. Legacy restoration’s outer controller catch provides a safe generic fallback and preserves saved data. The exact Guide widget/retry consequence remains unexecuted here.

Suggested wording: **“Oversized positive media durations pass validation and produce schedules that fail projection outside the normal schedule-error recovery path.”**

Remediation should establish checked temporal invariants in the scheduler—including cumulative and transition arithmetic—and return `invalidProgramDuration` before publishing an unusable schedule. Parser validation alone leaves persisted and directly constructed items exposed. Projection consumers should also route failure through their error owner without retaining a bad cached schedule. Avoid inventing an arbitrary media-length cap.

**C-F01 — keep, S2 Medium, High confidence from source and pinned framework.**

The [outer Guide key handler](/Users/tristan/Software/LineupDesktop/lib/guide/guide_view.dart:505) receives descendant events and consumes Enter, Space, numpad Enter, and Select for logical grid activation. Ordinary toolbar buttons, dropdowns, and row-local Retry have no corresponding focus exception.

The pinned Flutter implementation supports the reported mechanism: `InkWell` supplies activation Actions, while `WidgetsApp` supplies ancestor activation Shortcuts. Focus dispatch walks from the focused leaf toward ancestors and stops at `handled`. Consequently, the Guide handler suppresses focused-control activation before the default shortcut can invoke it. An airing logical grid selection can tune instead.

Retain the search, global Retry, and Setup exceptions as counterpoints. Pointer and semantics callbacks remain available; this does not prove packaged Windows remote behavior. Keep the finding scoped to controls beneath this handler, not already opened popup routes.

Suggested wording: **“Guide activation shortcuts consume keys intended for focused controls, suppressing their action and potentially tuning the logical grid selection.”**

The pending actual-key probes will strengthen runtime evidence; they are not required to establish this source/framework defect.

**C-F02 — keep, S3 Low, High confidence.**

[Search synchronization](/Users/tristan/Software/LineupDesktop/lib/guide/guide_view.dart:426) compares raw editor text against the controller’s trimmed, lowercase query on **every** Guide notification. When they differ, it replaces the entire editing value and moves the caret to the end.

Trailing whitespace does not change the normalized query, so it can survive the local edit until a schedule completion or ordinary reconciliation notification deletes it. Continued typing can then join two intended words. A case-changing edit that changes the normalized query can trigger replacement immediately; otherwise it awaits another notification.

Normalization remains appropriate for matching, and explicit external search changes should synchronize the editor. The defect is using that normalized state to overwrite locally owned editing state. Composition is cleared by the replacement, but **observed IME malfunction is not established**.

Suggested wording: **“Ordinary Guide notifications replace an active search editor with its normalized query, removing trailing spaces and resetting selection.”**

No severity upgrades or removals are warranted. The remaining gaps are integrated Guide observations and physical Windows input acceptance, not additional broad repository investigation.
