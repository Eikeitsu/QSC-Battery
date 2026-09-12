import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.qsc.battery"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.qsc.battery"
        minSdk = 26
        targetSdk = 35
        versionCode = 2026091201
        versionName = "0.3.1"
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }
        buildConfigField("String", "MODULE_UPDATE_URL", "\"https://eikeitsu.github.io/QSC-Battery/update.json\"")
        buildConfigField("String", "APP_UPDATE_URL", "\"https://eikeitsu.github.io/QSC-Battery/app-update.json\"")
        buildConfigField("String", "MODULE_ID", "\"QSC_Battery\"")
    }

    val keystorePropsFile = rootProject.file("keystore.properties")
    val keystoreProps = Properties().apply {
        if (keystorePropsFile.exists()) {
            keystorePropsFile.inputStream().use { load(it) }
        }
    }
    val releaseStoreFile = (System.getenv("QSC_STORE_FILE") ?: keystoreProps.getProperty("storeFile"))
        ?.let { rootProject.file(it) }
        ?.takeIf { it.isFile }
    val releaseStorePassword = System.getenv("QSC_STORE_PASSWORD")
        ?: keystoreProps.getProperty("storePassword")
    val releaseKeyAlias = System.getenv("QSC_KEY_ALIAS")
        ?: keystoreProps.getProperty("keyAlias")
    val releaseKeyPassword = System.getenv("QSC_KEY_PASSWORD")
        ?: keystoreProps.getProperty("keyPassword")
    val hasReleaseSigning = releaseStoreFile != null &&
        !releaseStorePassword.isNullOrBlank() &&
        !releaseKeyAlias.isNullOrBlank() &&
        !releaseKeyPassword.isNullOrBlank()

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            // 稳定签名：keystore.properties / 环境变量；缺省回退 debug（仅本地临时）
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
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
    implementation(libs.material.kolor)
    implementation(libs.okhttp)
    compileOnly(libs.libxposed.api)
}
