import org.godotengine.editor.AILinuxRuntimeFiles
import org.godotengine.editor.AIZivaDependencies
import org.json.JSONObject
import java.io.File
import java.nio.file.Files

fun main() {
    val scratch = Files.createTempDirectory("ziva-dependencies-").toFile()
    var checks = 0
    fun result(output: String = "", exit: Int = 0) = JSONObject().put("output", output).put("exit_code", exit)
    try {
        val root = File(scratch, "root").apply { mkdirs() }
        val font = File(root, AIZivaDependencies.FONTCONFIG.removePrefix("/"))
        var installed = false
        var failUpdate = false
        val calls = mutableListOf<List<String>>()
        val dependencies = AIZivaDependencies(root, { args, _ ->
            calls.add(args)
            when {
                args.first().endsWith("ldd") -> result(if (installed) "libcef.so => /private/libcef.so" else "libxcb.so.1 => not found\nlibnss3.so => not found")
                "update" in args -> result("DNS failure", if (failUpdate) 100 else 0)
                "install" in args -> { installed = true; font.parentFile.mkdirs(); font.writeText("fixture"); result() }
                else -> result()
            }
        })
        check(dependencies.missing().containsAll(listOf("libfontconfig.so.1", "libxcb.so.1", "libnss3.so"))); checks++
        failUpdate = true
        var rejected = false
        try { dependencies.ensure() } catch (_: IllegalStateException) { rejected = true }
        check(rejected && calls.none { "install" in it }); checks++
        failUpdate = false; calls.clear()
        dependencies.ensure()
        check(installed && dependencies.missing().isEmpty()); checks++
        check(calls.single { "update" in it }.contains("APT::Update::Error-Mode=any")); checks++
        check(calls.single { "install" in it }.containsAll(AIZivaDependencies.PACKAGES)); checks++
        calls.clear(); dependencies.ensure()
        check(calls.none { it.first().endsWith("apt-get") }); checks++
        val broken = AIZivaDependencies(root, { args, _ ->
            if (args.first().endsWith("ldd")) result("libstillmissing.so => not found") else result()
        })
        rejected = false
        try { broken.ensure() } catch (_: IllegalStateException) { rejected = true }
        check(rejected); checks++

        val base = File(scratch, "runtime").apply { mkdirs() }
        val core = AILinuxRuntimeFiles(base, scratch, { error("No archive needed") })
        core.root.mkdirs(); File(core.root, "etc").mkdir()
        core.synchronizeDns(listOf("193.231.252.1"))
        val dns = File(core.root, "etc/resolv.conf")
        check("193.231.252.1" in dns.readText()); checks++
        core.synchronizeDns(listOf("10.146.52.7", "10.146.52.7"))
        check(dns.readText().lineSequence().count { it.startsWith("nameserver") } == 1 && "193.231.252.1" !in dns.readText()); checks++
        val stamp = dns.lastModified(); core.synchronizeDns(listOf("10.146.52.7"))
        check(dns.lastModified() == stamp); checks++
        val keep = File(scratch, "keep").apply { writeText("KEEP") }
        dns.delete(); Files.createSymbolicLink(dns.toPath(), keep.toPath())
        core.synchronizeDns(listOf("malformed\nserver"))
        check(keep.readText() == "KEEP" && !Files.isSymbolicLink(dns.toPath()) && "1.1.1.1" in dns.readText()); checks++
        File(core.root, "etc/hosts").writeText("127.0.0.1 localhost\n10.1.2.3 keep.local\n")
        core.synchronizePackageHosts(listOf("151.101.2.132"))
        core.synchronizePackageHosts(listOf("151.101.66.132"))
        var hosts = File(core.root, "etc/hosts").readText()
        check("keep.local" in hosts && "151.101.66.132 deb.debian.org" in hosts && "151.101.2.132" !in hosts); checks++
        val hostStamp = File(core.root, "etc/hosts").lastModified()
        core.synchronizePackageHosts(listOf("151.101.66.132"))
        check(File(core.root, "etc/hosts").lastModified() == hostStamp); checks++
        core.synchronizeHosts(mapOf(
            "deb.debian.org" to listOf("151.101.66.132"),
            "registry.npmjs.org" to listOf("104.16.8.34")
        ))
        hosts = File(core.root, "etc/hosts").readText()
        check("registry.npmjs.org" in hosts && "104.16.8.34 registry.npmjs.org" in hosts); checks++
        check(hosts.lineSequence().count { it == "# Godot managed package repository" } == 1); checks++
        println("Ziva dependencies and network: $checks checks, 0 failures")
    } finally { AILinuxRuntimeFiles.deleteTree(scratch) }
}
