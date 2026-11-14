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
        manifestPlaceholders["appLabel"] = "Lineup"
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

    buildTypes {
        getByName("debug") {
            applicationIdSuffix = ".dev"
            manifestPlaceholders["appLabel"] = "Lineup Dev"
        }
        getByName("profile") {
            applicationIdSuffix = ".dev"
            manifestPlaceholders["appLabel"] = "Lineup Dev"
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            signingConfig = null
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

// Session HLS is explicit; Direct Play keeps its progressive-only source.
dependencies {
    constraints {
        implementation("com.google.guava:guava:33.7.2-android") {
            version { strictly("33.7.2-android") }
            because("Use the patched Android runtime for transitive Media3 dependencies")
        }
    }
    implementation("androidx.media3:media3-exoplayer:1.11.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.11.1")
    implementation("androidx.media3:media3-datasource-okhttp:1.11.1")
    implementation("androidx.media3:media3-ui:1.11.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.16.1")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
    testImplementation("com.squareup.okhttp3:okhttp-tls:4.12.0")
}
