# QSC Battery companion
-dontwarn io.github.libxposed.annotation.**
-dontwarn io.github.libxposed.service.**
-adaptresourcefilecontents META-INF/xposed/java_init.list
-keep,allowoptimization public class * extends io.github.libxposed.api.XposedModule {
    public <init>();
}
-keep class com.qsc.battery.xposed.** { *; }
-keep class io.github.libxposed.service.XposedProvider { *; }

# libsu
-keep class com.topjohnwu.superuser.** { *; }
-dontwarn com.topjohnwu.superuser.**

# OkHttp / Kotlin serialization
-dontwarn okhttp3.**
-dontwarn okio.**
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class **$$serializer {
    *** INSTANCE;
}

# Compose / Material Kolor
-keep class com.materialkolor.** { *; }
