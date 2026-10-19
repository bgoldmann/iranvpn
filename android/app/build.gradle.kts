plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}
android {
    namespace = "org.opensignalfoundation.iranvpn"
    compileSdk = 35
    defaultConfig {
        applicationId = "org.opensignalfoundation.iranvpn"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"
        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++11"
                arguments += "-DANDROID_STL=c++_static"
            }
        }
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64")
        }
    }
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }
    ndkVersion = "26.1.10909125"
    signingConfigs {
        create("release") {
            val storeFilePath = System.getenv("IRANVPN_KEYSTORE") ?: project.findProperty("IRANVPN_KEYSTORE") as String?
            val storePasswordValue = System.getenv("IRANVPN_KEYSTORE_PASSWORD") ?: project.findProperty("IRANVPN_KEYSTORE_PASSWORD") as String?
            val keyAliasValue = System.getenv("IRANVPN_KEY_ALIAS") ?: project.findProperty("IRANVPN_KEY_ALIAS") as String?
            val keyPasswordValue = System.getenv("IRANVPN_KEY_PASSWORD") ?: project.findProperty("IRANVPN_KEY_PASSWORD") as String?
            if (storeFilePath != null && storePasswordValue != null && keyAliasValue != null && keyPasswordValue != null) {
                storeFile = file(storeFilePath)
                storePassword = storePasswordValue
                keyAlias = keyAliasValue
                keyPassword = keyPasswordValue
            }
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            val releaseSigning = signingConfigs.findByName("release")?.takeIf { it.storeFile != null }
            // Never silently fall back to the debug keystore for Play uploads.
            signingConfig = releaseSigning
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // Fail release packaging early if no upload keystore (debug builds still work).
    afterEvaluate {
        listOf("assembleRelease", "bundleRelease").forEach { taskName ->
            tasks.findByName(taskName)?.doFirst {
                val cfg = android.signingConfigs.findByName("release")
                require(cfg?.storeFile != null) {
                    "Release signing missing. Set IRANVPN_KEYSTORE, IRANVPN_KEYSTORE_PASSWORD, " +
                        "IRANVPN_KEY_ALIAS, IRANVPN_KEY_PASSWORD (env or gradle.properties)."
                }
            }
        }
    }
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
    // lintVitalAnalyzeRelease currently crashes with AGP/Gradle toolchain mismatch ("25.0.1").
    // Keep assembling release APKs; re-enable after AGP/lint alignment.
    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
    composeOptions { kotlinCompilerExtensionVersion = "1.5.14" }
}
dependencies {
    // Psiphon Tunnel Core (includes Conduit). HostService.protectSocket avoids TUN loop.
    implementation("ca.psiphon:psiphontunnel:2.0.35")
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.6.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation("androidx.activity:activity-compose:1.8.1")
    implementation(platform("androidx.compose:compose-bom:2023.10.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
}
