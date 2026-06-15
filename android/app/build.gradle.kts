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

    // 签名配置：CI 通过环境变量注入（KEYSTORE_PATH/KEYSTORE_PASSWORD/KEY_ALIAS/KEY_PASSWORD），
    // 本地开发 fallback 到固定 debug 签名（android/app/debug.keystore）
    val keystorePath = System.getenv("KEYSTORE_PATH")
    val keystorePassword = System.getenv("KEYSTORE_PASSWORD")
    val keyAlias = System.getenv("KEY_ALIAS")
    val keyPassword = System.getenv("KEY_PASSWORD")
    signingConfigs {
        create("release") {
            if (keystorePath != null && keystorePassword != null &&
                keyAlias != null && keyPassword != null) {
                // CI 环境：用注入的签名
                storeFile = file(keystorePath)
                storePassword = keystorePassword
                this.keyAlias = keyAlias
                this.keyPassword = keyPassword
            } else {
                // 本地开发：fallback 固定 debug 签名（保证每次构建签名一致，可覆盖安装）
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
            // debug 用 Android 默认签名（~/.android/debug.keystore）
        }
        release {
            // release 用 release 签名配置（CI 注入或本地 debug keystore）
            signingConfig = signingConfigs.getByName("release")
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
