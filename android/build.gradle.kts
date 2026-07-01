allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// 强制所有子项目（含 Flutter 插件如 scrfd_ncnn）统一 JVM 17 目标，
// 否则部分插件的 Java(1.8) 与 Kotlin(17) 目标不一致导致 compileReleaseKotlin 失败
// （CI 报错：Inconsistent JVM-target compatibility detected for tasks
//   'compileReleaseJavaWithJavac' (1.8) and 'compileReleaseKotlin' (17)）
// 必须在 evaluationDependsOn(":app") 之前注册，让 afterEvaluate 在插件评估时生效。
subprojects {
    afterEvaluate {
        // 统一 Java 兼容版本
        extensions.findByType<com.android.build.gradle.BaseExtension>()?.let { ext ->
            ext.compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
            // 强制插件 compileSdk ≥ 35：多个插件（scrfd_ncnn 默认较低、video_player_android）
            // 的传递依赖 androidx.media3:1.9.2 / fragment:1.7.1 要求 compileSdk ≥ 35/34，
            // 否则 checkReleaseAarMetadata 失败。统一提到 35（最新稳定 API level）。
            if (ext is com.android.build.gradle.LibraryExtension) {
                ext.compileSdk = 35
            }
        }
        // 统一 Kotlin JVM 目标
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
