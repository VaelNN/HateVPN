allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
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



































subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.api.dsl.LibraryExtension>("android") {
            defaultConfig {
                externalNativeBuild {
                    cmake {
                        arguments += "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,--build-id=none"
                    }
                }
            }
        }
    }
}









val pluginsNeedingKgp = setOf("file_picker")
subprojects {
    if (name !in pluginsNeedingKgp) return@subprojects
    plugins.withId("com.android.library") {
        if (!plugins.hasPlugin("org.jetbrains.kotlin.android")) {
            plugins.apply("org.jetbrains.kotlin.android")
            extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension>("kotlin") {
                compilerOptions {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
