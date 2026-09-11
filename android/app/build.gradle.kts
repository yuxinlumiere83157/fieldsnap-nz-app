plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android Gradle Plugin.
    // Kotlin support comes from the Kotlin plugin declared in settings.gradle.kts,
    // matched to the Flutter 3.47.3 template.
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "nz.fieldsnap.app"
    // Compile against the platform Flutter 3.47.3 defaults to (API 36).
    compileSdk = flutter.compileSdkVersion
    // Kept because the Flutter Gradle plugin expects it; Iteration 0 contains no
    // native code, so the NDK is not required for this build.
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "nz.fieldsnap.app"
        // M1 §3 records that Flutter itself supports Android API 24+, but that the
        // tflite_flutter dependency makes API 26 the practical minimum for this MVP,
        // and M1 §6 commits to an ARM64 device on API 26 or later. Pinned to 26 so the
        // declared design baseline and the build agree.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Iteration 0 has no release signing configuration yet; release builds
            // are out of scope until the model and UI are real. Debug keys are used
            // so that `flutter run --release` still works.
            signingConfig = signingConfigs.getByName("debug")
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
