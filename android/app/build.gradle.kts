plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun envValue(name: String): String? = System.getenv(name)?.takeIf { it.isNotBlank() }

val releaseSigningEnv = listOf(
    "QSO_RELEASE_STORE_FILE",
    "QSO_RELEASE_STORE_PASSWORD",
    "QSO_RELEASE_KEY_ALIAS",
    "QSO_RELEASE_KEY_PASSWORD",
)
val isReleaseTask = gradle.startParameter.taskNames.any {
    it.contains("Release", ignoreCase = true)
}
val hasReleaseSigning = releaseSigningEnv.all { envValue(it) != null }

if (isReleaseTask && !hasReleaseSigning) {
    throw org.gradle.api.GradleException(
        "Release signing requires QSO_RELEASE_STORE_FILE, QSO_RELEASE_STORE_PASSWORD, " +
            "QSO_RELEASE_KEY_ALIAS, and QSO_RELEASE_KEY_PASSWORD."
    )
}

android {
    namespace = "com.example.qso_scribe_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.qso_scribe_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                storeFile = file(envValue("QSO_RELEASE_STORE_FILE")!!)
                storePassword = envValue("QSO_RELEASE_STORE_PASSWORD")
                keyAlias = envValue("QSO_RELEASE_KEY_ALIAS")
                keyPassword = envValue("QSO_RELEASE_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
}
