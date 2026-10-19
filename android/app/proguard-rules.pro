# Keep JNI / native bridge
-keepclasseswithmembernames class * {
    native <methods>;
}

# Psiphon Tunnel Core
-keep class ca.psiphon.** { *; }
-dontwarn ca.psiphon.**

# App VPN / tunnel surface
-keep class org.opensignalfoundation.iranvpn.** { *; }

# Kotlin / Coroutines
-dontwarn kotlinx.coroutines.**
-keepclassmembers class kotlinx.coroutines.** { volatile <fields>; }
