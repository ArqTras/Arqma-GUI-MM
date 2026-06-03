plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.arqma.arqma_wallet_android"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.arqma.arqma_wallet_android"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            // Phones: arm64-v8a (+ armeabi-v7a when built). Emulator (x86_64 AVD): x86_64.
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    sourceSets {
        getByName("main") {
            // Prebuilt FFI: build/ci/fetch-arqma-wallet-ffi-release.ps1 -> src/main/jniLibs only.
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }

    signingConfigs {
        create("release") {
            val storePath = System.getenv("ARQMA_ANDROID_KEYSTORE_PATH")?.trim()
            if (!storePath.isNullOrEmpty()) {
                storeFile = file(storePath)
                storePassword = System.getenv("ARQMA_ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ARQMA_ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ARQMA_ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            val storePath = System.getenv("ARQMA_ANDROID_KEYSTORE_PATH")?.trim()
            signingConfig = if (!storePath.isNullOrEmpty()) {
                signingConfigs.getByName("release")
            } else {
                // Local `flutter run --release` without keystore env vars.
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
