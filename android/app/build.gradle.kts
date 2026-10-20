import java.util.Properties

// Release signing: android/key.properties (gitignored) from tool/write-key-properties.sh.
// Without it, release builds fall back to debug signing (fine for local testing only).
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase Cloud Messaging — wires app/google-services.json into the build.
    id("com.google.gms.google-services")
}

android {
    namespace = "com.novalinkfiber.novalink_voice"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Permanent Play package name (decided 2026-10-16) — never change it.
        applicationId = "com.novalinkfiber.novalink_voice"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24  // Linphone SDK requires >= 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keyProps.getProperty("storeFile") != null) {
            create("release") {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keyProps.getProperty("storeFile") != null)
                signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Native Linphone SDK (SIP/TLS + mediastreamer2 media engine)
    implementation("org.linphone:linphone-sdk-android:5.4.0")
    // Firebase Cloud Messaging — the Linphone SDK's FirebaseMessaging service uses
    // this to fetch the FCM token and deliver push-wake messages from Flexisip.
    implementation(platform("com.google.firebase:firebase-bom:34.13.0"))
    implementation("com.google.firebase:firebase-messaging")
    // SIP credentials at rest: Keystore-backed EncryptedSharedPreferences.
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
}
