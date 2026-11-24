# A. Verified Android JVM test dependencies

The branch is `followup/android-gradle-cache`, based on `76419674e`. Source commit `676f5d1c022fa4635c2cdd219c0a8a5757521091` contains the implementation. The PR description records the hosted evidence for the published head. [PR #99](https://github.com/TJZine/LineupDesktop/pull/99)

## Failure and repair

Gradle received HTTP 429 fetching `org.robolectric:nativeruntime-dist-compat:1.0.20` from Maven Central while preparing the JVM test runtime. Its JAR already has a pinned SHA-256 in Gradle’s verification metadata. The two required Android jobs now use the pinned `setup-gradle` action. Both jobs allow cache writes only for a push to `refs/heads/main`. The Android build job installs the cache action after `tool/android/build-release.sh` completes with its own fresh scratch Gradle home. The dedicated wrapper checks and committed-build-input diff remain in place. [Failed Gradle fetch](https://github.com/TJZine/LineupDesktop/actions/runs/45368377445/job/138356177151) · [Pinned action](https://github.com/gradle/actions/tree/0723195856401067f7a2779048b490ace7a47d7c)

The v5.0.2 action uses Gradle cache keys scoped by job and commit and can replenish a partially populated cache on later main pushes. This matters because the startup job builds an APK while the Android JVM job also fetches large test-only artifacts. The open-source basic provider in v6.4.1 gives both jobs a build-file key and skips saving after an exact hit. Its post action can also run after a failed build. Revisit the action pin when the newer provider supports safe replenishment or distinct job keys with successful-build-only writes. [v5 cache key construction](https://github.com/gradle/actions/blob/0723195856401067f7a2779048b490ace7a47d7c/sources/src/caching/cache-key.ts) · [v6 basic provider](https://github.com/gradle/actions/blob/8da46b539cd8fe6ab27ca75128919a18d757604c/sources/src/cache-service-basic.ts)

Robolectric also fetched SDKs inside test workers. A `--info` run of `DeviceCaptionsTest` at the base used a fresh local Maven directory and `robolectric.logging.enabled=true`. It logged four transfers from `repo1.maven.org` for the SDK 34 JAR, POM and their SHA-512 sidecars. Gradle had no independent expected hash for this download. Hosted #92 showed its Maven artifact fetcher failing during test setup. The log did not print the HTTP status for that request. [Hosted fetcher failure](https://github.com/TJZine/LineupDesktop/actions/runs/45122916414/job/138354470948)

Each tested SDK version now resolves separately through Gradle. The test worker receives a flat directory containing the verified JARs through `robolectric.dependency.dir`. Robolectric selects its local resolver when that property is set. The CI JVM test runs with `--info` to expose Gradle downloads and the resolver selection. [SDK version mapping](https://github.com/robolectric/robolectric/blob/robolectric-4.18.1/robolectric/src/main/java/org/robolectric/plugins/DefaultSdkProvider.java) · [Resolver selection](https://github.com/robolectric/robolectric/blob/robolectric-4.18.1/robolectric/src/main/java/org/robolectric/plugins/LegacyDependencyResolver.java)

## Checksum provenance

The new `org.robolectric:android-all-instrumented` pins cover Android API levels 28, 30, 31 and 34. For each JAR and POM, the SHA-256 computed from pre-existing local bytes agreed with the published `.sha256` at Maven Central and at Google’s Maven Central mirror. The mirror distributes the same upstream publication. The eight expected hashes are in `android/gradle/verification-metadata.xml`. [Central artifacts](https://repo.maven.apache.org/maven2/org/robolectric/android-all-instrumented/) · [Central mirror](https://maven-central.storage-download.googleapis.com/maven2/org/robolectric/android-all-instrumented/14-robolectric-10818077-i7/android-all-instrumented-14-robolectric-10818077-i7.jar.sha256)

## Local verification

All JVM runs used Flutter 3.47.7, JDK 17 and the pinned Gradle 9.3.1 wrapper. An isolated local init script directed test-worker Maven storage to a disposable empty directory. The cold and warm Gradle daemons also received `-Dmaven.repo.local` pointing there.

| Case | Command from `android/` | Observation |
| --- | --- | --- |
| Cold Gradle and Maven stores | `./gradlew :app:testDebugUnitTest --rerun --no-daemon --info` | Gradle downloaded the four SDK JARs and four POMs from Central, plus the native runtime JAR. Robolectric selected its local resolver. All 190 tests passed. |
| Restored Gradle state in a fresh checkout | Same command | Copied only `caches/` and `wrapper/` from the cold Gradle home. The checkout had no staged SDKs or build output. All 190 tests passed. The log contained zero Robolectric HTTP GET, download or transfer records, and the test worker's Maven store contained no JARs. |
| Warm SDK integrity control | `./gradlew :app:testDebugUnitTest --rerun --offline --no-daemon --info` | Changed only the API 34 SDK JAR’s expected SHA-256 in an isolated checkout. `:app:prepareRobolectricSdks` failed with “One artifact failed verification” naming `android-all-instrumented-14-robolectric-10818077-i7.jar`. Restored the original metadata. |
| Warm native runtime integrity control | Same offline command | Changed only the expected SHA-256 for `nativeruntime-dist-compat-1.0.20.jar`. Resolution of `:app:debugUnitTestRuntimeClasspath` failed with “One artifact failed verification” naming that JAR. Restored the original metadata. |
| Restored expected hashes | Same offline command | All 190 tests passed. The metadata matched the source commit byte-for-byte, the SDK resolver stayed local, and the log contained zero Robolectric HTTP GET, download or transfer records. |

The Android tooling suite passed 20 tests and the CI tooling suite passed four. The separate Kotlin CodeQL workflow also consumes the verified SDK configuration when it runs JVM tests. Package A adds the cache action to the two requested CI workflow jobs.

## Hosted verification

A GitHub-hosted cold run, a cache write on a push to main, and a following PR restoring that cache require their respective Actions runs. The PR description carries the job links and observations as they complete. [Hosted evidence in PR #99](https://github.com/TJZine/LineupDesktop/pull/99)
