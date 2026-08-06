allprojects {
    repositories {
        google()
        mavenCentral()
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

// Some plugins (flutter_pdf_annotations) and material 1.11.0 declare
// androidx.cardview:cardview:1.1.0, which was never published on Google
// Maven. Force the real latest version (1.0.0) for ALL modules.
subprojects {
    configurations.configureEach {
        resolutionStrategy {
            force("androidx.cardview:cardview:1.0.0")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
