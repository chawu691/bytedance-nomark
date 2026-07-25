import org.gradle.api.Action
import org.gradle.api.Project

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

// Fix -Werror treating deprecated Java 8 target warnings as errors
subprojects {
    tasks.withType<JavaCompile> {
        options.compilerArgs.add("-Xlint:-options")
    }
}

// 强制插件子项目使用 compileSdk 36，解决 file_picker 间接依赖的
// flutter_plugin_android_lifecycle 要求 android-36 的问题。
// 必须在子项目自身脚本执行后再覆盖（file_picker 默认 34，会覆盖回 34），
// 故用 gradle.afterProject 而非 afterEvaluate（后者在已评估项目上会报错）。
// AGP 9 默认 android.newDsl=true，需用 com.android.build.api.dsl 下的新类型。
gradle.afterProject(object : Action<Project> {
    override fun execute(proj: Project) {
        val ext = proj.extensions.findByName("android") ?: return
        when (ext) {
            is com.android.build.api.dsl.LibraryExtension -> ext.compileSdk = 36
            is com.android.build.api.dsl.ApplicationExtension -> ext.compileSdk = 36
        }
    }
})

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
