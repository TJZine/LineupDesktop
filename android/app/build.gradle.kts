plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.tjzine.lineup"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.tjzine.lineup"
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        // Native-asset hooks can otherwise add x86_64 even when Flutter targets
        // only ARM. Distribution is a two-ABI universal TV APK.
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a")
        }
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val useDebugKey = System.getenv("LINEUP_ANDROID_SIGNING") == "debug-key"
    val keyPath = System.getenv("LINEUP_ANDROID_KEYSTORE")
    val lineupKeyAlias = System.getenv("LINEUP_ANDROID_KEY_ALIAS")
    val lineupKeyPassword = System.getenv("LINEUP_ANDROID_KEY_PASSWORD")
    val hasLineupKey = !keyPath.isNullOrBlank() &&
        !lineupKeyAlias.isNullOrBlank() && !lineupKeyPassword.isNullOrBlank()

    signingConfigs {
        if (hasLineupKey && !useDebugKey) {
            create("lineup") {
                storeFile = file(keyPath!!)
                storePassword = lineupKeyPassword
                keyAlias = lineupKeyAlias
                keyPassword = lineupKeyPassword
            }
        }
    }
    buildTypes {
        debug {
            if (!useDebugKey && hasLineupKey) {
                signingConfig = signingConfigs.getByName("lineup")
            }
        }
        getByName("profile") {
            // Flutter creates profile by copying debug before this script sets
            // debug's signingConfig, so configure it explicitly for upgrades.
            signingConfig = if (hasLineupKey && !useDebugKey) {
                signingConfigs.getByName("lineup")
            } else {
                null
            }
        }
        release {
            // Never use the contributor/CI debug key for release.
            signingConfig = if (hasLineupKey && !useDebugKey) {
                signingConfigs.getByName("lineup")
            } else {
                null
            }
        }
    }

    // Fail before assembling an unsigned APK or accidentally using a debug key.
    // Keep IDE sync and non-packaging unit tests usable without private signing.
    gradle.taskGraph.whenReady {
        val packagesRelease = allTasks.any {
            it.project == project &&
                it.name.contains("Release") &&
                (it.name.startsWith("package") || it.name.startsWith("bundle"))
        }
        val packagesProfile = allTasks.any {
            it.project == project && it.name.startsWith("package") &&
                it.name.contains("Profile")
        }
        val packagesDebug = allTasks.any {
            it.project == project && it.name.startsWith("package") &&
                it.name.contains("Debug")
        }
        if (((packagesRelease || packagesProfile) && (!hasLineupKey || useDebugKey)) ||
            (packagesDebug && !hasLineupKey && !useDebugKey)) {
            throw GradleException(
                "Lineup signing key required. Build through tool/android/with-signing.sh. " +
                    "Contributors may set LINEUP_ANDROID_SIGNING=debug-key for debug only."
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// Progressive HTTP only: no HLS/DASH/RTSP modules or external-reference loader.
dependencies {
    implementation("androidx.media3:media3-exoplayer:1.11.1")
    implementation("androidx.media3:media3-datasource-okhttp:1.11.1")
    implementation("androidx.media3:media3-ui:1.11.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.16.1")
}
