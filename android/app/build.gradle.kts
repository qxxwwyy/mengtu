plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mengtu.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // 签名配置：优先使用环境变量（CI Secrets），fallback 到本地 keystore
    signingConfigs {
        getByName("debug") {
            val ksFile = System.getenv("KEYSTORE_FILE")
            if (ksFile != null && File(ksFile).exists()) {
                storeFile = File(ksFile)
                storePassword = System.getenv("KEYSTORE_PASSWORD") ?: "android"
                keyAlias = System.getenv("KEY_ALIAS") ?: "debug"
                keyPassword = System.getenv("KEY_PASSWORD") ?: "android"
            } else {
                // 本地开发：使用默认 debug 签名
                storeFile = file("debug.keystore")
                storePassword = "android"
                keyAlias = "debug"
                keyPassword = "android"
            }
        }
    }

    defaultConfig {
        applicationId = "com.mengtu.app"
        // Android 8.0 (API 26) 最低版本要求
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // 仅打包 arm64-v8a（目标设备均为 ARM64，砍掉 armeabi-v7a/x86_64 约减 80MB）
        ndk { abiFilters += "arm64-v8a" }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            // TODO: Add your own signing config for the release build.
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
