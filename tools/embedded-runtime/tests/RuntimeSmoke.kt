import org.godotengine.editor.AILinuxRuntimeFiles
import org.json.JSONObject
import java.io.File
import java.nio.file.Files

/** Development control only: uses supplied native files, not an installed Godot APK. */
fun main(args: Array<String>) {
    val directory = File(args[0]).canonicalFile
    val native = File(args[1]).canonicalFile
    val assets = File(args[2]).canonicalFile
    val core = AILinuxRuntimeFiles(directory, native, { File(assets, it).inputStream() }, progress = { print(it) })
    when (args[3]) {
        "install" -> { core.install(listOf("1.1.1.1", "8.8.8.8")); check(core.state().getBoolean("ready")) }
        "tools" -> check(core.verify().getBoolean("ready"))
        "execute" -> {
            val project = File(directory, "project").apply { mkdirs() }
            File(project, "project.godot").writeText("config_version=5\n")
            val result = core.execute("python3 -c 'from pathlib import Path; Path(\"probe.txt\").write_text(\"linux-ok\")'; node -e 'console.log(\"NODE_OK\")'; git --version; rg linux-ok probe.txt", project, 60)
            check(result.getInt("exit_code") == 0 && result.getString("output").contains("NODE_OK"))
            check(File(project, "probe.txt").readText() == "linux-ok")
            val noisy = core.execute("python3 -c 'print(\"x\"*200000)'", project, 30)
            check(noisy.getBoolean("truncated") && noisy.getString("output").length <= AILinuxRuntimeFiles.MAX_LOG)
            val start = System.nanoTime()
            try { core.execute("sleep 20", project, 1); error("Timeout was ignored") }
            catch (error: IllegalStateException) { check(error.message!!.contains("limita de timp")) }
            check((System.nanoTime() - start) / 1e9 < 8)
            val cancelAt = System.nanoTime() + 500_000_000
            val cancellable = AILinuxRuntimeFiles(directory, native, { File(assets, it).inputStream() }, { System.nanoTime() > cancelAt })
            try { cancellable.execute("sleep 20", project, 30); error("Cancellation was ignored") }
            catch (error: IllegalStateException) { check(error.message!!.contains("anulată")) }
            val outside = File(directory.parentFile, "preserve-runtime-smoke.txt").apply { writeText("preserve") }
            val disposable = File(directory, "delete-control").apply { mkdirs() }
            Files.createSymbolicLink(File(disposable, "outside").toPath(), outside.toPath())
            AILinuxRuntimeFiles.deleteTree(disposable)
            check(outside.readText() == "preserve"); outside.delete()
            println("\nLINUX_RUNTIME_SMOKE_PASS")
        }
    }
    File(directory, "smoke-result.json").writeText(core.state().toString(2))
}
