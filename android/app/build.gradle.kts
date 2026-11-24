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
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        configureEach {
            val emulatorDebug = name == "debug" &&
                providers.gradleProperty("target-platform").orNull == "android-x64"
            ndk.abiFilters += if (emulatorDebug) {
                listOf("x86_64")
            } else {
                listOf("armeabi-v7a", "arm64-v8a")
            }
        }
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
        implementation("com.google.guava:guava:33.8.0-android") {
            version { strictly("33.8.0-android") }
            because("Use the patched Android runtime for transitive Media3 dependencies")
        }
    }
    implementation("androidx.media3:media3-exoplayer:1.11.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.11.1")
    implementation("androidx.media3:media3-datasource-okhttp:1.11.1")
    implementation("androidx.media3:media3-ui:1.11.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.1")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.18.1")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.1")
    testImplementation("com.squareup.okhttp3:okhttp-tls:4.12.1")
}

repositories {
    exclusiveContent {
        forRepository {
            maven {
                name = "RobolectricTestArtifacts"
                url = uri("https://maven-central.storage-download.googleapis.com/maven2/")
            }
        }
        filter {
            includeModule("org.robolectric", "android-all-instrumented")
            includeModule("org.robolectric", "nativeruntime-dist-compat")
        }
    }
}

val robolectricSdkDirectory = layout.buildDirectory.dir("robolectric-sdks")
val prepareRobolectricSdks by tasks.registering(Sync::class) {
    into(robolectricSdkDirectory)
    for (version in listOf(
        "9-robolectric-4913185-2-i7",
        "11-robolectric-6757853-i7",
        "12-robolectric-7732740-i7",
        "14-robolectric-10818077-i7",
    )) {
        val sdk = dependencies.create("org.robolectric:android-all-instrumented:$version")
        from(configurations.detachedConfiguration(sdk).apply { isTransitive = false })
    }
}

tasks.withType<Test>().configureEach {
    inputs.files(prepareRobolectricSdks)
    systemProperty("robolectric.dependency.dir", robolectricSdkDirectory.get().asFile.absolutePath)
    systemProperty("robolectric.logging.enabled", logger.isInfoEnabled)
}
