plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.goldenfalcons.sailinggps"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.goldenfalcons.sailinggps"
        minSdk = 26
        targetSdk = 36
        versionCode = providers.gradleProperty("appVersionCode").get().toInt()
        versionName = providers.gradleProperty("appVersionName").get()
        buildConfigField("String", "UPDATE_REPOSITORY", "\"GoldenFalcons18/gps-pwa\"")
    }

    buildFeatures {
        viewBinding = true
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    val signingFile = System.getenv("SAILING_KEYSTORE_FILE")
    if (!signingFile.isNullOrBlank()) {
        signingConfigs.create("distribution") {
            storeFile = file(signingFile)
            storePassword = System.getenv("SAILING_KEYSTORE_PASSWORD") ?: error("Missing signing password")
            keyAlias = System.getenv("SAILING_KEY_ALIAS") ?: error("Missing signing alias")
            keyPassword = System.getenv("SAILING_KEY_PASSWORD") ?: error("Missing key password")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            if (!signingFile.isNullOrBlank()) signingConfig = signingConfigs.getByName("distribution")
        }
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    implementation("org.osmdroid:osmdroid-android:6.1.20")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
}
