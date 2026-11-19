# Flutter wrapper & Lanjo native bridge / widget / tile / notification listener
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.example.lanjo.** { *; }

# Keep flutter_local_notifications receivers & Gson serialized models
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keepattributes *Annotation*

# Keep SQLite3 / Drift JNI & Biometric classes
-keep class org.sqlite.** { *; }
-keep class androidx.biometric.** { *; }

-dontwarn javax.annotation.**
-dontwarn org.codehaus.mojo.animal_sniffer.**
-dontwarn com.google.android.play.core.**

