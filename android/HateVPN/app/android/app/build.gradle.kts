plugins {
    id("com.android.application")
    id("kotlin-android")

    id("dev.flutter.flutter-gradle-plugin")
}

import java.io.FileInputStream
import java.util.Properties

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

fun hasReleaseKeystore(): Boolean =
    keystorePropertiesFile.exists() &&
        !keystoreProperties.getProperty("storeFile").isNullOrBlank()

android {
    namespace = "com.leadaxe.lxbox"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }












    dependenciesInfo {
        includeInApk = false
        includeInBundle = true
    }

    defaultConfig {
        applicationId = "com.darkside.hatevpn"














        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName











    }












    val abiFilterEnv: String? = System.getenv("LXBOX_ABI_FILTER")
    if (!abiFilterEnv.isNullOrBlank()) {
        val keepAbis = abiFilterEnv.split(",").map { it.trim() }.toSet()
        defaultConfig.ndk.abiFilters.clear()
        defaultConfig.ndk.abiFilters.addAll(keepAbis)



        val allAbis = setOf("armeabi-v7a", "arm64-v8a", "x86_64", "x86")
        val excludeAbis = allAbis - keepAbis
        packaging {
            for (abi in excludeAbis) {
                jniLibs.excludes += "lib/$abi/**"
            }
        }
    }

    signingConfigs {
        if (hasReleaseKeystore()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")!!
                keyPassword = keystoreProperties.getProperty("keyPassword")!!
                storePassword = keystoreProperties.getProperty("storePassword")!!
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile")!!)
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (hasReleaseKeystore()) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }

    packaging {
        jniLibs { useLegacyPackaging = true }
    }
}

dependencies {




    implementation(files("libs/libbox.aar"))
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}

flutter {
    source = "../.."
}
