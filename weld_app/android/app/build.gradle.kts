plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.weld_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.example.weld_app"
        // tflite_flutter requires API 26+ (Android 8.0) — its manifest
        // declares minSdk 26, which is higher than Flutter's default
        // flutter.minSdkVersion, so it must be set explicitly here.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

// Workaround for a namespace collision between tensorflow-lite,
// tensorflow-lite-gpu, and tensorflow-lite-api (all declare the same
// package "org.tensorflow.lite" in their manifests, which newer AGP
// versions reject as a duplicate namespace).
//   - tensorflow-lite-api is a compile-time-only stub — the real classes
//     ship in tensorflow-lite itself — so it's always safe to drop.
//   - tensorflow-lite-gpu provides the GPU delegate. It's excluded here
//     too because the app doesn't currently use GpuDelegateV2 (see
//     tflite_inference_service.dart). If GPU delegate support is added
//     later, this exclusion must be removed and a different fix used
//     (e.g. pinning a newer tflite_flutter/TF Lite release that ships
//     unique namespaces, once one is available).
configurations.all {
    exclude(group = "org.tensorflow", module = "tensorflow-lite-api")
    exclude(group = "org.tensorflow", module = "tensorflow-lite-gpu")
}

flutter {
    source = "../.."
}