plugins {
    id("com.android.application")
}

android {
    namespace = "com.handscore.hexagon"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.handscore.hexagon"
        minSdk = 31
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            assets.srcDir(layout.buildDirectory.dir("generated/assets/handscore"))
        }
    }
}

val syncHandScoreDataset by tasks.registering(Copy::class) {
    description = "Copies the shared HAND-Score ChatAlpaca prompt set into Android assets."
    from(rootProject.layout.projectDirectory.file("../samples/chatalpaca_handscore.json"))
    into(layout.buildDirectory.dir("generated/assets/handscore"))
}

tasks.named("preBuild") {
    dependsOn(syncHandScoreDataset)
}
