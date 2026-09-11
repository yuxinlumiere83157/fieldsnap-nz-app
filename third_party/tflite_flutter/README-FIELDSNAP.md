# Local override: tflite_flutter 0.12.1

Why this directory exists: upstream `tflite_flutter` 0.12.1 contains Kotlin sources
(`android/src/main/kotlin/org/tensorflow/tflite_flutter/TfliteFlutterPlugin.kt`) but its
`android/build.gradle` never applies a Kotlin plugin. With Flutter 3.47.3 / AGP 9 and
`android.builtInKotlin=false`, AGP compiles that Kotlin with the JDK running Gradle (25 on
this machine) while the Java task targets 11, and the build fails with:

```
Inconsistent JVM-target compatibility detected for tasks
'compileDebugJavaWithJavac' (11) and 'compileDebugKotlin' (25).
```

The patch is three lines in `android/build.gradle`: apply `kotlin-android` and pin
`jvmTarget` to 11, matching the plugin's own `compileOptions`. Everything else is the
upstream release, copied verbatim (`version` in its own build file is unchanged).

This is a build-environment fix, not a functional change: no Dart or Kotlin source is
modified. Remove it once upstream applies a Kotlin plugin (or once this project migrates to
built-in Kotlin), and record that removal in `docs/progress.md`.
