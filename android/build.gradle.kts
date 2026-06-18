allprojects {
    repositories {
        google()
        mavenCentral()
    }

    // tflite_flutter 0.11 间接依赖 org.tensorflow:tensorflow-lite{,-gpu,-api}:2.11.0，
    // 三者共用 namespace org.tensorflow.lite，触发 AGP 9.x 严格 uniqueManifestNamespace 校验
    // （该降级 flag android.uniqueManifestNamespaceRequired 在 AGP 9 已被忽略，无法关闭）。
    // 强制升级到 2.16.1（已正确声明独立 namespace）规避冲突。
    // 必须放在 allprojects 内，让 :tflite_flutter 插件模块的依赖解析也生效。
    configurations.configureEach {
        resolutionStrategy.eachDependency {
            if (requested.group == "org.tensorflow") {
                when (requested.name) {
                    "tensorflow-lite", "tensorflow-lite-gpu", "tensorflow-lite-api",
                    "tensorflow-lite-support", "tensorflow-lite-gpu-delegate-plugin" -> {
                        useVersion("2.16.1")
                        because("AGP 9 uniqueManifestNamespace: 2.11 三库共用 namespace，2.16 已修复")
                    }
                }
            }
        }
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

// 强制所有子项目（含 Flutter 插件如 tflite_flutter）统一 JVM 17 目标，
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
            // 强制插件 compileSdk ≥ 34：tflite_flutter 默认 31，但其传递依赖
            // androidx.fragment:fragment:1.7.1 要求 compileSdk ≥ 34，否则 checkReleaseAarMetadata 失败
            if (ext is com.android.build.gradle.LibraryExtension) {
                ext.compileSdk = 34
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
