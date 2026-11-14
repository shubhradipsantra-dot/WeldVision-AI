allprojects {
    repositories {
        google()
        mavenCentral()
    }
    
    // 1. Force Java 17 for all Java compilation tasks globally
    tasks.withType<JavaCompile> {
        sourceCompatibility = "17"
        targetCompatibility = "17"
    }
    
    // 2. Force Kotlin 17 for all Kotlin compilation tasks globally
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile> {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

// Some plugins (notably tflite_flutter) hardcode an old compileSdk (31)
// in their own build.gradle, which is lower than what their AndroidX
// dependencies now require (33/34+). We don't control the plugin's
// source (it lives in the pub cache), so force every Android library
// subproject (except :app, which already sets its own compileSdk) to
// compile against a newer SDK instead. This only affects compile-time
// API surface, not minSdk/targetSdk or runtime behavior.
//
// Guarded because ":app"'s evaluationDependsOn(":app") above can cause
// some subprojects to already be evaluated by the time this block runs,
// and Gradle throws if you call afterEvaluate() on an already-evaluated
// project.
subprojects {
    if (project.name == "app") return@subprojects

    fun applyCompileSdkOverride() {
        val androidExt = project.extensions.findByType(
            com.android.build.gradle.BaseExtension::class.java
        )
        androidExt?.compileSdkVersion(36)
    }

    if (project.state.executed) {
        applyCompileSdkOverride()
    } else {
        afterEvaluate { applyCompileSdkOverride() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}