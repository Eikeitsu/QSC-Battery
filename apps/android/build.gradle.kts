import java.util.Properties

// AGP 内置 Kotlin 默认带 KGP≥2.2.10；显式抬到 catalog 版本以匹配 Compose / serialization 插件
buildscript {
    dependencies {
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:${libs.versions.kotlin.get()}")
    }
}

plugins {
    alias(libs.plugins.android.application)
    // AGP 9 built-in Kotlin：不再 apply org.jetbrains.kotlin.android
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.spotless)
}

android {
    namespace = "com.qsc.battery"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.qsc.battery"
        minSdk = 26
        // 运行行为仍按 35；compileSdk 37 仅为满足 Compose BOM 依赖的 AAR metadata
        targetSdk = 35
        // CI / 预发布可通过 -PqscVersionName / -PqscVersionCode 覆盖展示名与检测码
        val qscVersionName = providers.gradleProperty("qscVersionName")
        val qscVersionCode = providers.gradleProperty("qscVersionCode")
        versionName = qscVersionName.orNull ?: "0.3.1"
        versionCode = qscVersionCode.orNull?.toIntOrNull() ?: 2026091201
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }
        buildConfigField(
            "String",
            "MODULE_UPDATE_URL",
            "\"https://cdn.jsdelivr.net/gh/Eikeitsu/QSC-Battery@updates/stable/update.json\"",
        )
        buildConfigField(
            "String",
            "APP_UPDATE_URL",
            "\"https://cdn.jsdelivr.net/gh/Eikeitsu/QSC-Battery@updates/stable/app-update.json\"",
        )
        buildConfigField(
            "String",
            "DAEMON_UPDATE_URL",
            "\"https://cdn.jsdelivr.net/gh/Eikeitsu/QSC-Battery@updates/stable/qscd/manifest.json\"",
        )
        buildConfigField(
            "String",
            "CI_MODULE_UPDATE_URL",
            "\"https://cdn.jsdelivr.net/gh/Eikeitsu/QSC-Battery@updates/ci/update.json\"",
        )
        buildConfigField(
            "String",
            "CI_APP_UPDATE_URL",
            "\"https://cdn.jsdelivr.net/gh/Eikeitsu/QSC-Battery@updates/ci/app-update.json\"",
        )
        buildConfigField(
            "String",
            "CI_DAEMON_UPDATE_URL",
            "\"https://cdn.jsdelivr.net/gh/Eikeitsu/QSC-Battery@updates/ci/qscd/manifest.json\"",
        )
        buildConfigField(
            "String",
            "PRE_MODULE_UPDATE_URL",
            "\"https://cdn.jsdelivr.net/gh/Eikeitsu/QSC-Battery@updates/prerelease/update.json\"",
        )
        buildConfigField(
            "String",
            "PRE_APP_UPDATE_URL",
            "\"https://cdn.jsdelivr.net/gh/Eikeitsu/QSC-Battery@updates/prerelease/app-update.json\"",
        )
        buildConfigField(
            "String",
            "PRE_DAEMON_UPDATE_URL",
            "\"https://cdn.jsdelivr.net/gh/Eikeitsu/QSC-Battery@updates/prerelease/qscd/manifest.json\"",
        )
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

kotlin {
    jvmToolchain(17)
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
    implementation(libs.libxposed.service)
}

spotless {
    // Android Kotlin 约定 4 空格；显式覆盖，避免仓库根 .editorconfig(indent=2) 影响
    val kotlinStyle =
        mapOf(
            "indent_size" to "4",
            "ij_kotlin_imports_layout" to "*,java.**,javax.**,kotlin.**,^",
            // Compose @Composable 使用 PascalCase 是惯例
            "ktlint_function_naming_ignore_when_annotated_with" to "Composable",
        )
    kotlin {
        target("src/**/*.kt")
        ktlint().editorConfigOverride(kotlinStyle)
        trimTrailingWhitespace()
        endWithNewline()
    }
    kotlinGradle {
        target("*.gradle.kts")
        ktlint().editorConfigOverride(kotlinStyle)
        trimTrailingWhitespace()
        endWithNewline()
    }
}
