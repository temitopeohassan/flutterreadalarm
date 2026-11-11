import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Play Store builds are signed with your upload key, described by
// android/key.properties (never committed; see README). Without it the
// release build is signed with the test key (see signingConfigs).
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { stream -> load(stream) }
}

android {
    namespace = "com.readalarm.readalarm"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications for scheduled alarms.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.readalarm.readalarm"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // flutter_local_notifications and permission_handler need API 24+.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // AdMob app id: Google's test app unless the real one is passed with
        // -PadmobAppId=ca-app-pub-…~… (see README).
        // (CI passes an empty value when the secret isn't set.)
        manifestPlaceholders["admobAppId"] =
            (project.findProperty("admobAppId") as String?)
                ?.takeIf { it.isNotBlank() }
                ?: "ca-app-pub-3940256099942544~3347511713"
    }

    signingConfigs {
        // Test builds (CI's APKs) are all signed with this one key, so each
        // new APK installs over the last. It is not secret and must never
        // sign a Play Store build: those use the upload key below.
        create("test") {
            storeFile = file("test-signing.p12")
            storeType = "PKCS12"
            storePassword = "readalarm-test"
            keyAlias = "test"
            keyPassword = "readalarm-test"
        }
        if (keyProperties.isNotEmpty()) {
            create("upload") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("upload")
                ?: signingConfigs.getByName("test")
            // Keeps code R8 can't see is used (see the file).
            proguardFiles("proguard-rules.pro")
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
