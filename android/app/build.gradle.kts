import java.util.Properties
import java.io.FileInputStream
import java.util.Base64

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Load keystore properties
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val dartDefinesEncoded = (project.findProperty("dart-defines") as String?)
    ?.split(",")
    ?: emptyList()
val dartDefines = dartDefinesEncoded.mapNotNull { encoded ->
    try {
        String(Base64.getDecoder().decode(encoded))
    } catch (_: IllegalArgumentException) {
        null
    }
}

val isAdminBuild = dartDefines.contains("APP_VARIANT=admin")
val baseApplicationId = "com.sstranswaysindia.app"
val adminApplicationId = "com.sstranswaysindia.admin"
val bundleBaseName = if (isAdminBuild) "admin-app" else "main-app"

android {
    namespace = "com.sstranswaysindia.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_1_8.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = if (isAdminBuild) adminApplicationId else baseApplicationId
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        resValue(
            "string",
            "app_name",
            if (isAdminBuild) "SS Admin" else "SS Transways India"
        )
    }

    signingConfigs {
        create("release") {
            if (keystoreProperties.containsKey("keyAlias") && keystoreProperties.containsKey("keyPassword") && 
                keystoreProperties.containsKey("storeFile") && keystoreProperties.containsKey("storePassword")) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}

android.applicationVariants.all {
    outputs
        .map { it as com.android.build.gradle.internal.api.BaseVariantOutputImpl }
        .forEach { output ->
            if (buildType.name == "release") {
                output.outputFileName = when {
                    output.outputFileName.endsWith(".apk") -> "${bundleBaseName}-release.apk"
                    output.outputFileName.endsWith(".aab") -> "${bundleBaseName}-release.aab"
                    else -> output.outputFileName
                }
            }
        }
}
