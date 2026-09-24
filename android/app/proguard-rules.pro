# Flutter's own rules are applied by the Flutter Gradle plugin.
# Keep plugin entry points that are only reached via reflection.
-keep class io.flutter.plugins.** { *; }
-dontwarn com.google.android.play.core.**
