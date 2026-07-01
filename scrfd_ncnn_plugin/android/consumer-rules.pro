# consumer-rules.pro — scrfd_ncnn 消费者 ProGuard 规则
#
# 自动应用到依赖本插件的 app。本插件是纯 FFI（无 Java/Kotlin 类），
# 无需 keep 规则。libscrfd_ncnn.so 由 CMake 打包，R8 不处理。
# (empty on purpose)
