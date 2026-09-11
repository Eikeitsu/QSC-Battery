plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.qsc.battery"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.qsc.battery"
        // miuix 0.9.x 要求较高 API；伴侣 APP 面向常见 Magisk/KSU 机型
        minSdk = 33
        targetSdk = 36
        versionCode = 2026091101
        versionName = "0.1.0"
        buildConfigField("String", "MODULE_UPDATE_URL", "\"https://eikeitsu.github.io/QSC-Battery/update.json\"")
        buildConfigField("String", "APP_UPDATE_URL", "\"https://eikeitsu.github.io/QSC-Battery/app-update.json\"")
        buildConfigField("String", "MODULE_ID", "\"QSC_Battery\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            // CI 暂用 debug 签名产出可安装 APK；正式发布可换成 secrets 密钥
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlin {
        jvmToolchain(17)
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.datastore.preferences)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons)
    debugImplementation(libs.androidx.compose.ui.tooling)

    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.libsu.core)
    implementation(libs.libsu.io)
    implementation(libs.miuix.ui)
    implementation(libs.miuix.preference)
    implementation(libs.material.kolor)
    implementation(libs.okhttp)
    compileOnly(libs.libxposed.api)
}
