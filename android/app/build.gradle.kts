plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes from Gradle properties (CI passes them as
// ORG_GRADLE_PROJECT_* from secrets). Without them the release build falls
// back to the debug key, which is new on every CI runner — such an APK
// cannot update an earlier install, so sideload builds must be signed.
val uploadKey: Map<String, String?> =
    listOf(
        "anischedUploadStoreFile",
        "anischedUploadStorePassword",
        "anischedUploadKeyAlias",
        "anischedUploadKeyPassword",
    ).associateWith { providers.gradleProperty(it).orNull }
val uploadKeyMissing: List<String> =
    uploadKey.filterValues { it.isNullOrEmpty() }.keys.toList()

android {
    namespace = "com.myoun.anisched"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.myoun.anisched"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Same floor as Anicel: Galaxy Tab S6 Lite and up, Android 10+.
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Galaxy Tab is arm64 only; dropping other ABIs halves the APK.
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    signingConfigs {
        if (uploadKeyMissing.isEmpty()) {
            create("upload") {
                storeFile = file(uploadKey.getValue("anischedUploadStoreFile")!!)
                storePassword = uploadKey.getValue("anischedUploadStorePassword")
                keyAlias = uploadKey.getValue("anischedUploadKeyAlias")
                keyPassword = uploadKey.getValue("anischedUploadKeyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                signingConfigs.findByName("upload") ?: signingConfigs.getByName("debug")
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
