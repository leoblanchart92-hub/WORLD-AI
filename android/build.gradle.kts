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

// Les plugins (file_picker, image_picker, url_launcher) fixent leur propre
// compileSdk, plus ancien que celui qu'exige leur dépendance Android commune
// (flutter_plugin_android_lifecycle, compilée en API 36). Sans cet alignement,
// la vérification des métadonnées AAR fait échouer l'assemblage release.
subprojects {
    afterEvaluate {
        val android = extensions.findByName("android") ?: return@afterEvaluate
        // Propriété compileSdk dans les AGP récents, méthode compileSdkVersion
        // avant ; l'appel reste réflexif pour ne pas dépendre du type exact.
        val setter = android.javaClass.methods.firstOrNull {
            (it.name == "setCompileSdk" || it.name == "compileSdkVersion") && it.parameterCount == 1
        }
        setter?.invoke(android, 36)
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
