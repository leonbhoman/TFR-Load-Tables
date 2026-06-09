pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        val propertiesFile = settingsDir.resolve("local.properties")
        if (propertiesFile.exists()) {
            propertiesFile.inputStream().use { properties.load(it) }
        }
        properties.getProperty("flutter.sdk") ?: System.getenv("FLUTTER_ROOT")
        ?: error("Flutter SDK not found. Define 'flutter.sdk' in local.properties or set 'FLUTTER_ROOT' env variable.")
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-gradle-plugin") apply false
    // Bumped from 8.1.0 to 8.6.0 to satisfy the modern Flutter framework
    id("com.android.application") version "8.6.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
}

include(":app")