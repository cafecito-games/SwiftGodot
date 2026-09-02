import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

val pluginName = "SwiftGodot"
val pluginPackageName = "games.cafecito.swiftgodot"

android {
    namespace = pluginPackageName
    compileSdk = 36

    defaultConfig {
        minSdk = 28
        ndk {
            abiFilters += setOf("arm64-v8a", "x86_64")
        }
        manifestPlaceholders["godotPluginName"] = pluginName
        manifestPlaceholders["godotPluginInitializer"] = "$pluginPackageName.SwiftGodotPlugin"
        setProperty("archivesBaseName", pluginName)
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }
}

dependencies {
    implementation("org.godotengine:godot:4.7.2.stable")
}
