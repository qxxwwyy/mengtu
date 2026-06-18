# ==============================================================================
# 1. 调试信息剥离 (丢弃源文件名和代码行号，但保留反射和泛型所需的关键属性)
# ==============================================================================
-keepattributes !SourceFile,!LineNumberTable,Signature,InnerClasses,EnclosingMethod,*Annotation*

# ==============================================================================
# 2. Flutter 引擎及插件的保留规则
# ==============================================================================
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.provider.** { *; }
-keep class org.chromium.** { *; }

# ==============================================================================
# 3. TensorFlow Lite 混淆保留
# ==============================================================================
-keep class org.tensorflow.lite.** { *; }
-keep class com.google.android.gms.tflite.** { *; }
-dontwarn org.tensorflow.lite.**
-dontwarn com.google.android.gms.tflite.**

# ==============================================================================
# 4. Glide (图片加载框架，由 photo_manager/wechat_assets_picker 依赖) 混淆保留
#    若不保留，Release 包在获取/显示缩略图时会因找不到 GeneratedAppGlideModuleImpl 而崩溃
# ==============================================================================
-keep public class * extends com.bumptech.glide.module.AppGlideModule
-keep class com.bumptech.glide.GeneratedAppGlideModuleImpl
-keep class * extends com.bumptech.glide.module.LibraryGlideModule
-keep class * extends com.bumptech.glide.module.AppGlideModule { *; }
-keep class com.bumptech.glide.util.GlideSuppliers { *; }
-keep class com.bumptech.glide.util.GlideSuppliers$* { *; }
-dontwarn com.bumptech.glide.**

# ==============================================================================
# 5. photo_manager 插件混淆保留
# ==============================================================================
-keep class com.fluttercandies.photo_manager.** { *; }

# ==============================================================================
# 6. Play Core 缺失类（Flutter PlayStoreDeferredComponentManager 引用，
#    本应用未集成 Play Core 分包，R8 严格模式需要忽略这些引用）
# ==============================================================================
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
