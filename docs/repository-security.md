# Repository security and activation

Gate 1 covers activating and testing repository protections. Obtain maintainer
authorization after the proposed checks pass on the reviewed commit.

## Required source checks

The stable `Required CI checks` job in `.github/workflows/ci.yml` requires the
Dart, Android, macOS, native-core, Windows policy, Windows build, release-input
and dependency-advisory jobs to succeed. It runs even when prerequisites fail.
Windows engine tests may skip only when `engine-required` is explicitly `false`.
The patched-engine/package build may skip only when both release-input outputs
are explicitly `false`. Missing decisions, cancellation, unexpected skips and
failure fail the aggregate. The workflow inventory fixture makes additions to
the CI job list require an explicit aggregation decision.

Run the local aggregation fixtures with
`python3 -m unittest discover -s tool/ci -p '*_test.py'`. These fixtures establish
the decision logic and wiring. They do not establish GitHub enforcement.

## Gate 1 activation and observed enforcement

1. Review the full source commit and observe a successful `Required CI checks`
   run for that commit. Observe Security workflow completion and its actual
   CodeQL check names. Resolve configuration failures before requiring checks.
   Review historical Gradle inventory alerts against actual resolved graphs
   separately before release.
2. In GitHub repository settings, create an active branch ruleset for the default
   branch. Require pull requests, zero approvals while solo-maintained, resolved
   review conversations and the observed required checks. Require up-to-date
   branches. Bind required checks to GitHub Actions where the ruleset supports
   the expected integration. Restrict deletion and force pushes. Apply the rules
   to administrators and keep the routine bypass list empty.
3. Create an active tag ruleset for release tags matching `v*`. Restrict tag
   updates and deletions. Retain the ability to create a new reviewed release tag.
   Enable immutable releases before any public release.
4. Enable dependency graph, Dependabot alerts and security updates. Retain secret
   scanning and push protection. Enable code scanning using the committed advanced
   workflow, avoiding a competing default-setup workflow. Dependabot configuration
   schedules weekly Pub, Gradle and Actions updates. Review updates through PRs.
5. Read back branch/tag rules, required check sources and security/release settings
   through GitHub UI or REST. Record the repository, full source SHA, rule IDs,
   observed settings and date in release evidence. A prepared file is insufficient.
6. With separately authorized disposable refs/PRs, demonstrate failed-check merge
   rejection, direct protected updates/force push/deletion rejection, and release
   tag retarget/deletion rejection. Review the canary's scope before mutation.
   Clean up allowed disposable refs. Record observed rejection and restored state.

If emergency administration is necessary, record why and exactly which rule was
temporarily changed. Recover, restore the original rule and read back settings.
Do not leave a standing routine bypass. Preserve unrelated ownership rules.
The current CODEOWNERS owner is `@TJZine`; self-review does not provide independent
review.

## Advisory coverage and gaps

`tool/security/osv-scan.sh` downloads pinned OSV-Scanner 2.7.1 release bytes,
checks the committed upstream digest, runs live affected/fixed Pub controls and
scans explicit committed inputs. CI scans the current `pubspec.lock`. The weekly Security workflow also scans
Android dependency-verification metadata. Scanner failures and
vulnerabilities fail visibly. API/network errors cannot satisfy the affected/fixed
controls. Run the same command locally from the repository root.

```sh
tool/security/osv-scan.sh \
  --lockfile=pubspec.lock \
  --lockfile=android/gradle/verification-metadata.xml
```

Gradle verification metadata includes historical/build-tool coordinates, so its
scan is a conservative inventory observation. It does not prove runtime
resolution. P2's resolved build/runtime graphs establish the actual Android input
set. Review material findings with those graphs and upstream advisories. Record
unavailable package ecosystems or tool errors as gaps, with equivalent manual
advisory review when needed. Do not label failed or unavailable scans clean.

CodeQL covers C/C++ with no-build analysis and Java/Kotlin with an actual Android
build. No-build C++ analysis has reduced knowledge of Windows-specific headers,
generated sources and compiler configuration. CodeQL does not cover Dart. Pub
advisories and Dart tests/analyzer cover distinct obligations. No macOS physical
release gate is added by scanning or existing macOS CI.

The native dependency inventory already exists in
[Windows runtime notices](windows-runtime.md) and
[Android runtime notices](android-runtime.md). Keep those inventories and existing
build metadata current instead of adding a second machine-readable ledger.

| Pinned input | Authoritative identity | Primary advisory review |
| --- | --- | --- |
| Flutter/Dart and patched Windows engine | `tool/flutter_version.json`, `tool/windows/build-metadata.psd1`, committed engine patches and verified SDK action | [Flutter security advisories](https://github.com/flutter/flutter/security/advisories) and [Dart advisories](https://github.com/dart-lang/sdk/security/advisories) |
| libmpv and statically linked media dependencies | `tool/windows/build-metadata.psd1`, `third_party/libmpv/`, Windows runtime inventory with its documented closure limits | [mpv security policy](https://github.com/mpv-player/mpv/security), [FFmpeg security](https://ffmpeg.org/security.html), and each inventoried upstream's advisories |
| Android Media3, OkHttp, Kotlin/Gradle and transitives | Committed Gradle inputs, verification metadata and P2 resolved graphs | [Android security bulletins](https://source.android.com/docs/security/bulletin), [Media3 releases](https://developer.android.com/jetpack/androidx/releases/media3), [OkHttp advisories](https://github.com/square/okhttp/security/advisories), and [GitHub Advisory Database](https://github.com/advisories) |
| Microsoft runtime and SDK/toolchain | P4 selected toolchain CRT with signature/version/hash evidence | [Microsoft Security Update Guide](https://msrc.microsoft.com/update-guide) |

Before release, review alerts, workflow failures, the actual runtime graph and
native inventory advisory sources. Record source/version/date, relevant findings,
mitigation or explicit maintainer disposition and remaining gaps with the release
checks. Do not create general exceptions to make a failing scan appear successful.

See [release security](release-security.md) for isolated signing and exact final
artifact verification after the three maintainer gates.

## Sources

The current [Dependabot ecosystem reference](https://docs.github.com/en/code-security/reference/supply-chain-security/supported-ecosystems-and-repositories),
[CodeQL build options](https://docs.github.com/en/code-security/reference/code-scanning/codeql/build-options-for-compiled-languages),
and [OSV supported artifacts](https://google.github.io/osv-scanner/supported-languages-and-lockfiles/)
describe coverage limits. The Pub control uses
[GHSA-9v85-q87q-g4vg](https://github.com/advisories/GHSA-9v85-q87q-g4vg), fixed in archive 3.3.8.
