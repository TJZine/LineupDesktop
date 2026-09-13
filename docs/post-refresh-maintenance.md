# Post-refresh maintenance

User authorization: improve Windows launch/package usability, repair the current
non-golden CI failure, reduce goldens to a small useful set, and update dependencies
as far as current compatibility evidence supports. Use sequential fresh Luna/xhigh
implementation tasks in the existing checkout; Astra supplies the decisions,
reviews results, verifies and commits. No worktrees or automatic reviewers.

## Work sequence

1. Small Windows development launcher and clear portable-package instructions.
   Reuse the provisioned patched engine and existing release/package scripts.
   Environment defaults may remember local paths; no new configuration framework.
2. Repair the Settings overflow at800x600/text200 reported by CI, preserving the
   locked1080 appearance. Reduce mandatory goldens to representative Guide,
   Player and Settings coverage, preserving meaningful behavior assertions and
   capture tooling. Astra selects exact retained cases before dispatch.
3. Dependency upgrades after Astra's current upstream/version/compatibility
   assessment. Include Dart dependencies/transitives, Flutter/Dart, CI actions and
   native/toolchain pins in the inventory. Prefer latest stable compatible
   versions; don't bypass SDK constraints or integrity/native-engine contracts.
   Explain any retained pin rather than silently omitting it.

## Starting evidence

Base137b0778c774aea162a206d2dfbd4b41ac3bf923. GitHub PR41 latest run34734716604:
Verify Dart803passed/1failed; theme_shell_test accessible theme check reports an
8.7px horizontal overflow at800x600/text200, reproduced locally at8.8px.
Windows application build/tests and release-policy checks passed. Golden failures
are known; the running patched-engine job is outside this CI-failure diagnosis.

The dependency inventory currently reports secure-storage11.0.0 ->11.1.1 plus
three compatible platform updates. Other reported newer transitives are blocked
by existing package/SDK constraints and require explicit assessment.

## Status

The Windows development launcher and portable-package instructions are complete
in commit 8aa4cf0b. The bounded Settings overflow repair is also complete: the
existing accessible-text regression, full theme shell suite and shared
navigation suite pass, with formatting, analysis and diff checks clean. No
golden or dependency changes were made. The contact sheet and these checks are
portable evidence only; no physical Windows build or launch validation is
implied.

The golden reduction is complete in the current checkout: 30 screenshot
assertions and baselines became 5 representative 1920×1080 snapshots; 23 UI
golden cases were removed, 25 obsolete PNGs were deleted, and the two Guide
opacity cases remain as non-baseline aperture checks. The retained baselines
were refreshed and rerun without `--update-goldens` using the pinned Flutter
SDK, `TZ=America/New_York`, and macOS. The final five renders were reviewed in
one contact sheet. No full-suite run or physical Windows validation is implied;
the dependency-assessment unit remains pending.
