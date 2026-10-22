plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingValues = listOf(
    "ANDROID_BETA_KEYSTORE_PATH", "ANDROID_BETA_STORE_PASSWORD",
    "ANDROID_BETA_KEY_ALIAS", "ANDROID_BETA_KEY_PASSWORD"
).associateWith { System.getenv(it)?.takeIf(String::isNotBlank) }
val signingReady = signingValues.values.all { it != null }
val releaseRequested = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
if (releaseRequested && !signingReady) {
    throw GradleException("Falta la firma propia de beta. Configura los secretos ANDROID_BETA_*; no se usara firma debug.")
}

android {
    namespace = "io.github.alexcore123r.vetdosis"
    compileSdk = maxOf(36, flutter.compileSdkVersion)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.alexcore123r.vetdosis"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "distribution"
    productFlavors {
        create("beta") {
            dimension = "distribution"
            applicationIdSuffix = ".beta"
            manifestPlaceholders["appLabel"] = "VetDosis Pro Beta"
        }
    }
    signingConfigs {
        create("betaRelease") {
            // Missing configuration also fails signing if a generic task requests release.
            storeFile = file(signingValues["ANDROID_BETA_KEYSTORE_PATH"] ?: ".signing-not-configured.jks")
            storePassword = signingValues["ANDROID_BETA_STORE_PASSWORD"] ?: "not-configured"
            keyAlias = signingValues["ANDROID_BETA_KEY_ALIAS"] ?: "not-configured"
            keyPassword = signingValues["ANDROID_BETA_KEY_PASSWORD"] ?: "not-configured"
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("betaRelease")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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
