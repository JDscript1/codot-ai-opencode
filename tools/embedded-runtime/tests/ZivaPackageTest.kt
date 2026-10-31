import org.godotengine.editor.AILinuxRuntimeFiles
import org.godotengine.editor.AIZivaPackage
import java.io.File
import java.nio.file.Files
import java.security.MessageDigest
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

fun main() {
    val scratch = Files.createTempDirectory("godot-ziva-package-").toFile()
    var checks = 0
    val addon = "addons/ziva_agent"
    val member = "$addon/zivacode/linux_arm64/zivacode"
    val payload = "fixture ELF".toByteArray()
    val base = "https://github.com/ziva-sh/ziva-agent-plugin-godot/releases/download"

    fun hash(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes)
        .joinToString("") { "%02x".format(it.toInt() and 255) }

    fun zip(name: String, entries: List<Pair<String, ByteArray>>): File {
        val archive = File(scratch, "$name.zip")
        ZipOutputStream(archive.outputStream()).use { out ->
            for ((path, data) in entries) {
                out.putNextEntry(ZipEntry(path)); out.write(data); out.closeEntry()
            }
        }
        return archive
    }

    fun release(archive: File, binary: ByteArray, runtime: File? = null) = AIZivaPackage.Release("v3.3.2",
        "$base/v3.3.2/ziva-ai-agent-v3.3.2-godot-v4.2.0-linux-arm64.zip",
        archive.length(), AILinuxRuntimeFiles.sha(archive), member, binary.size.toLong(), hash(binary),
        if (runtime == null) "" else "$base/v3.3.2/ziva-runtime-v3.3.2-linux-arm64.zip",
        runtime?.length() ?: 0, if (runtime == null) "" else AILinuxRuntimeFiles.sha(runtime))

    fun addonEntries(binary: ByteArray = payload, license: Boolean = true, gdextension: Boolean = true,
        manifest: Boolean = true, binaryEntry: Boolean = true): List<Pair<String, ByteArray>> {
        val files = mutableListOf<Pair<String, ByteArray>>()
        if (binaryEntry) files += member to binary
        files += "$addon/bin/linux_arm64/libziva.so" to "runtime".toByteArray()
        files += "$addon/zivacode/linux_arm64/zivacode-helper" to "helper".toByteArray()
        if (gdextension) files += "$addon/ziva_agent.gdextension" to "[configuration]\n".toByteArray()
        if (manifest) files += "$addon/manifest.json" to "{\"version\":\"v3.3.2\"}".toByteArray()
        if (license) files += "$addon/LICENSE.md" to "Fixture license".toByteArray()
        // Entries outside the addon prefix are ignored, never interpreted as paths.
        files += "bin/zivacode" to "decoy".toByteArray()
        files += "../../outside.txt" to "untrusted".toByteArray()
        return files
    }

    // Since v3.3.3 the runtime archive is rooted at the addon directory.
    fun runtimeEntries(binary: ByteArray = payload): List<Pair<String, ByteArray>> = listOf(
        "zivacode/linux_arm64/zivacode" to binary,
        "bin/linux_arm64/libcef.so" to "cef".toByteArray(),
        "bin/linux_arm64/ziva_cef_helper" to "helper".toByteArray(),
        "bin-deps/tool" to "dep".toByteArray())

    fun reject(block: () -> Unit) {
        var rejected = false
        try { block() } catch (_: IllegalStateException) { rejected = true } catch (_: IllegalArgumentException) { rejected = true }
        check(rejected); checks++
    }

    try {
        val root = File(scratch, "linux").apply { mkdirs() }
        val good = zip("good", addonEntries())
        val spec = release(good, payload)
        val distribution = AIZivaPackage(root, spec)
        check(!distribution.installed()); checks++
        distribution.extract(good)
        distribution.verify()
        check(distribution.installed() && distribution.binary.readText() == "fixture ELF"); checks++
        check(File(distribution.addon, "ziva_agent.gdextension").isFile &&
            File(distribution.addon, "manifest.json").isFile && File(distribution.addon, "LICENSE.md").isFile); checks++
        check(distribution.binary.canExecute() &&
            File(distribution.addon, "bin/linux_arm64/libziva.so").canExecute()); checks++
        check(!File(distribution.addon, "bin/zivacode").exists() &&
            !File(distribution.addon.parentFile, "bin/zivacode").exists() && !File(scratch, "outside.txt").exists()); checks++

        val history = File(root, "var/lib/godot-ai-ziva/project/history.db").apply { parentFile.mkdirs(); writeText("KEEP") }
        distribution.binary.writeText("corrupt".padEnd(payload.size, '!'))
        reject { distribution.verify() }
        distribution.extract(good)
        distribution.verify()
        check(history.readText() == "KEEP" && distribution.binary.readText() == "fixture ELF"); checks++

        reject { AIZivaPackage(root, spec.copy(archiveHash = "0".repeat(64))).extract(good) }
        check(distribution.binary.readText() == "fixture ELF"); checks++

        val cancelled = AIZivaPackage(File(scratch, "cancelled").apply { mkdirs() }, spec)
        reject { cancelled.extract(good) { true } }
        check(!cancelled.installed()); checks++

        for ((name, files) in listOf(
            "no-license" to addonEntries(license = false),
            "no-gdextension" to addonEntries(gdextension = false),
            "no-manifest" to addonEntries(manifest = false),
            "no-binary" to addonEntries(binaryEntry = false))) {
            val archive = zip(name, files)
            val target = AIZivaPackage(File(scratch, name).apply { mkdirs() }, release(archive, payload))
            reject { target.extract(archive) }
            check(!target.installed()); checks++
        }
        val empty = zip("empty", listOf("bin/zivacode" to "decoy".toByteArray()))
        reject { AIZivaPackage(File(scratch, "empty").apply { mkdirs() }, release(empty, payload)).extract(empty) }

        for ((name, path) in listOf("dotdot" to "$addon/../evil.txt", "backslash" to "$addon/..\\evil.txt",
            "blank" to "$addon//evil.txt")) {
            val archive = zip(name, addonEntries() + (path to "evil".toByteArray()))
            val target = AIZivaPackage(File(scratch, name).apply { mkdirs() }, release(archive, payload))
            reject { target.extract(archive) }
            check(!target.installed()); checks++
        }

        reject { AIZivaPackage(root, spec.copy(version = "../../outside")).extract(good) }

        val unsafe = File(scratch, "unsafe").apply { mkdirs() }
        Files.createSymbolicLink(File(unsafe, "opt").toPath(), File(scratch, "target").apply { mkdirs() }.toPath())
        reject { AIZivaPackage(unsafe, spec).extract(good) }

        val broken = File(scratch, "bad-binary").apply { mkdirs() }
        reject { AIZivaPackage(broken, spec.copy(binaryHash = "0".repeat(64))).extract(good) }
        check(!File(broken, "opt/godot-tools/ziva/v3.3.2").exists() &&
            File(broken, "opt/godot-tools/ziva").listFiles().orEmpty().isEmpty()); checks++

        val upgrade = zip("upgrade", addonEntries(binary = "upgrade ELF".toByteArray()))
        reject { AIZivaPackage(root, release(upgrade, "upgrade ELF".toByteArray()).copy(binaryHash = "0".repeat(64))).extract(upgrade) }
        check(distribution.installed() && distribution.binary.readText() == "fixture ELF"); checks++

        val installed = AIZivaPackage(File(scratch, "installed-no-manifest").apply { mkdirs() }, spec)
        installed.extract(good)
        File(installed.addon, "manifest.json").delete()
        check(!installed.installed()); checks++

        val splitRoot = File(scratch, "split").apply { mkdirs() }
        val splitAddon = zip("split-addon", addonEntries(binaryEntry = false))
        val splitRuntime = zip("split-runtime", runtimeEntries())
        val splitSpec = release(splitAddon, payload, splitRuntime).copy(version = "v3.3.3",
            url = "$base/v3.3.3/ziva-ai-agent-v3.3.3-godot-v4.2.0-linux-arm64.zip",
            runtimeUrl = "$base/v3.3.3/ziva-runtime-v3.3.3-linux-arm64.zip")
        val split = AIZivaPackage(splitRoot, splitSpec)
        reject { split.extract(splitAddon) } // the runtime archive is mandatory
        split.extract(splitAddon, splitRuntime)
        split.verify()
        check(split.binary.readText() == "fixture ELF" && File(split.addon, "bin/linux_arm64/libcef.so").isFile); checks++
        check(split.binary.canExecute() && File(split.addon, "bin/linux_arm64/libcef.so").canExecute()); checks++
        check(File(split.addon, "bin-deps/tool").canExecute() && !File(scratch, "outside.txt").exists()); checks++
        reject { AIZivaPackage(splitRoot, splitSpec.copy(runtimeHash = "0".repeat(64))).extract(splitAddon, splitRuntime) }
        check(split.installed() && split.binary.readText() == "fixture ELF"); checks++
        reject { AIZivaPackage(root, spec).extract(good, splitRuntime) } // a legacy release rejects an extra archive
        val mismatched = zip("mismatched-runtime", runtimeEntries("other ELF".toByteArray()))
        reject { AIZivaPackage(splitRoot, splitSpec.copy(runtimeSize = mismatched.length(),
            runtimeHash = AILinuxRuntimeFiles.sha(mismatched))).extract(splitAddon, mismatched) }
        val missingRuntimeBinary = zip("missing-runtime-binary",
            runtimeEntries().filterNot { it.first == "zivacode/linux_arm64/zivacode" })
        reject { AIZivaPackage(splitRoot, release(splitAddon, payload, missingRuntimeBinary)
            .copy(version = "v3.3.3", url = splitSpec.url, runtimeUrl = splitSpec.runtimeUrl))
            .extract(splitAddon, missingRuntimeBinary) }
        val leaky = zip("leaky-runtime", runtimeEntries() + ("../evil.txt" to "evil".toByteArray()))
        reject { AIZivaPackage(File(scratch, "leaky").apply { mkdirs() }, release(splitAddon, payload, leaky)
            .copy(version = "v3.3.3", url = splitSpec.url, runtimeUrl = splitSpec.runtimeUrl))
            .extract(splitAddon, leaky) }
        val clash = zip("clash-addon", addonEntries(binaryEntry = false) + ("$addon/bin/linux_arm64/libcef.so" to "addon".toByteArray()))
        reject { AIZivaPackage(splitRoot, splitSpec.copy(archiveSize = clash.length(),
            archiveHash = AILinuxRuntimeFiles.sha(clash))).extract(clash, splitRuntime) }

        val versionsRoot = File(scratch, "versions").apply { mkdirs() }
        val first = AIZivaPackage(versionsRoot, spec)
        first.extract(good); first.activate()
        // A recorded v3.3.2 must not outlive the version pinned by this app.
        check(AIZivaPackage(versionsRoot).version == AIZivaPackage.RELEASE.version); checks++
        val replacement = AIZivaPackage(versionsRoot, splitSpec)
        replacement.extract(splitAddon, splitRuntime); replacement.verify()
        // Extraction never replaces the recorded active release on its own.
        check(AILinuxRuntimeFiles.readJson(File(versionsRoot, "opt/godot-tools/ziva/active.json"))
            .getString("version") == "v3.3.2"); checks++
        replacement.activate()
        val active = AIZivaPackage(versionsRoot)
        active.verify()
        check(active.version == "v3.3.3" && active.binary.readText() == "fixture ELF"); checks++
        check(first.binary.readText() == "fixture ELF" && history.readText() == "KEEP"); checks++
        active.binary.appendText("tampered")
        reject { active.verify() }

        println("Ziva package: $checks checks, 0 failures")
    } finally { AILinuxRuntimeFiles.deleteTree(scratch) }
}
