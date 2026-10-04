plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "org.continuity.p0"
    compileSdk = 35

    defaultConfig {
        applicationId = "org.continuity.p0"
        minSdk = 23
        targetSdk = 35
        versionCode = 6
        versionName = "0.3.3"
    }

    buildFeatures {
        compose = true
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}
dependencies {
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.foundation.layout)
    implementation(libs.androidx.compose.material3)
    implementation(libs.google.nearby)
    testImplementation(libs.junit)
    constraints {
        // Nearby pulls an old Fragment version; Activity Result APIs require >= 1.3.
        implementation(libs.androidx.fragment)
    }
}
