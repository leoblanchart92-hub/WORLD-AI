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
    val alignCompileSdk = {
        // Propriété compileSdk dans les AGP récents, méthode compileSdkVersion
        // avant ; l'appel reste réflexif pour ne pas dépendre du type exact.
        val android = extensions.findByName("android")
        val setter = android?.javaClass?.methods?.firstOrNull {
            (it.name == "setCompileSdk" || it.name == "compileSdkVersion") && it.parameterCount == 1
        }
        setter?.invoke(android, 36)
        setter != null
    }
    // evaluationDependsOn(":app") fait évaluer certains modules plus tôt :
    // afterEvaluate n'est alors plus permis et il faut appliquer tout de suite.
    if (state.executed) {
        alignCompileSdk()
    } else {
        afterEvaluate { alignCompileSdk() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
