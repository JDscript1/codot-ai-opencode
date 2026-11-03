package org.godotengine.editor

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.zip.ZipFile

/**
 * Installs the runtime environment entirely from assets signed into the APK.
 * The operation is intentionally separate from optional network actions: a
 * first run and the Settings "Update packages" action must not contact a
 * package registry.
 */
object AIPackageManager {
    const val ASSET_DIRECTORY = "godot_ai/packages"
    const val MANIFEST_ASSET = "$ASSET_DIRECTORY/manifest.json"
    private const val OFFLINE_DIR = "var/cache/godot-ai-offline"
    private const val MARKER = "var/lib/godot-ai/packages.json"
    private const val MAX_ASSET_BYTES = 512L * 1024 * 1024
    private const val MAX_EXTRACTED_BYTES = 2L * 1024 * 1024 * 1024
    private const val MAX_PACKAGE_FILES = 20000
    private const val PI_NODE = "root/.local/node_modules/node/bin/node"
    private const val PI_CLI = "root/.local/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js"

    fun manifest(context: Context): JSONObject {
        val value = context.assets.open(MANIFEST_ASSET).bufferedReader().use { JSONObject(it.readText()) }
        check(value.getInt("schema") == 1) { "Manifestul pachetelor runtime este incompatibil." }
        check(value.getString("distribution") in listOf("standard", "ziva-preview")) { "Distribuția pachetelor runtime este invalidă." }
        return value
    }

    fun bundled(context: Context): Boolean = try {
        manifest(context)
        true
    } catch (_: Exception) { false }

    internal fun asset(manifest: JSONObject, name: String): JSONObject {
        require(name.matches(Regex("[A-Za-z0-9][A-Za-z0-9._-]{0,240}"))) { "Nume de pachet runtime invalid." }
        val assets = manifest.optJSONArray("assets") ?: JSONArray()
        for (index in 0 until assets.length()) {
            val value = assets.optJSONObject(index) ?: continue
            if (value.optString("name") == name) return value
        }
        error("Pachetul $name lipsește din APK.")
    }

    private fun stop(cancelled: () -> Boolean) { check(!cancelled()) { "Operație anulată." } }

    /** Copy one signed asset and verify the bytes before any extractor sees them. */
    internal fun copyAsset(context: Context, manifest: JSONObject, name: String, destination: File,
        cancelled: () -> Boolean, progress: (String) -> Unit): File {
        val spec = asset(manifest, name)
        val expectedSize = spec.getLong("size")
        val expectedHash = spec.getString("sha256")
        check(expectedSize in 1..MAX_ASSET_BYTES && expectedHash.matches(Regex("[a-f0-9]{64}"))) { "Metadatele pachetului $name sunt invalide." }
        check(destination.parentFile?.let { it.isDirectory || it.mkdirs() } == true) { "Directorul pachetelor runtime nu poate fi creat." }
        val partial = File(destination.parentFile, destination.name + ".part-" + UUID.randomUUID())
        try {
            val digest = MessageDigest.getInstance("SHA-256")
            context.assets.open("$ASSET_DIRECTORY/$name").use { input -> partial.outputStream().use { output ->
                val buffer = ByteArray(65536); var count = 0L; var lastReport = -1L
                while (true) {
                    stop(cancelled)
                    val read = input.read(buffer); if (read < 0) break
                    count += read
                    check(count <= expectedSize) { "Pachetul $name este prea mare." }
                    digest.update(buffer, 0, read); output.write(buffer, 0, read)
                    val step = count / (32L * 1024 * 1024)
                    if (step != lastReport) { lastReport = step; progress("Copiez $name: ${count / (1024 * 1024)} / ${expectedSize / (1024 * 1024)} MB") }
                }
                check(count == expectedSize) { "Pachetul $name este incomplet." }
            } }
            check(digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) } == expectedHash) { "Pachetul $name este corupt." }
            check(destination.delete() || !destination.exists()) { "Pachetul runtime vechi nu poate fi înlocuit." }
            check(partial.renameTo(destination)) { "Pachetul $name nu poate fi activat." }
            return destination
        } finally { partial.delete() }
    }

    private fun extractDebianArchive(context: Context, runtime: AILinuxRuntimeFiles, manifest: JSONObject,
        cancelled: () -> Boolean, progress: (String) -> Unit): File {
        val spec = manifest.getJSONObject("debian")
        val archive = File(context.cacheDir, "godot-ai-debian-${UUID.randomUUID()}.zip")
        try {
            copyAsset(context, manifest, spec.getString("asset"), archive, cancelled, progress)
            val directory = File(runtime.root, OFFLINE_DIR)
            AILinuxRuntimeFiles.deleteTree(directory)
            check(directory.mkdirs()) { "Repository-ul Debian offline nu poate fi creat." }
            var count = 0; var total = 0L
            ZipFile(archive).use { zip ->
                for (entry in zip.entries()) {
                    stop(cancelled)
                    if (entry.isDirectory) continue
                    val name = entry.name
                    require(name.matches(Regex("[A-Za-z0-9][A-Za-z0-9+._~:-]{0,240}"))) { "Nume invalid în repository-ul Debian." }
                    check(entry.size in 0..MAX_ASSET_BYTES) { "Fișier Debian prea mare." }
                    total += entry.size; count += 1
                    check(total <= MAX_EXTRACTED_BYTES && count <= MAX_PACKAGE_FILES) { "Repository-ul Debian este prea mare." }
                    val output = File(directory, name)
                    zip.getInputStream(entry).use { input -> output.outputStream().use { stream ->
                        val buffer = ByteArray(65536); var copied = 0L
                        while (true) {
                            stop(cancelled)
                            val read = input.read(buffer); if (read < 0) break
                            copied += read; check(copied <= entry.size); stream.write(buffer, 0, read)
                        }
                        check(copied == entry.size) { "Fișier Debian incomplet." }
                    } }
                }
            }
            check(File(directory, "Packages").isFile && count > 1) { "Repository-ul Debian offline este incomplet." }
            return directory
        } finally { archive.delete() }
    }

    private fun markerMatches(runtime: AILinuxRuntimeFiles, manifest: JSONObject): Boolean {
        val spec = manifest.optJSONObject("debian") ?: return false
        val marker = AILinuxRuntimeFiles.readJson(File(runtime.root, MARKER))
        val expected = try { asset(manifest, spec.getString("asset")).getString("sha256") } catch (_: Exception) { return false }
        if (marker.optString("asset_sha256") != expected) return false
        val packages = spec.optJSONArray("packages") ?: return false
        if (packages.length() == 0) return false
        val command = mutableListOf("/usr/bin/dpkg-query", "-W", "-f=\${Package}\\t\${Status}\\n")
        for (index in 0 until packages.length()) command.add(packages.getString(index))
        val result = runtime.launch(command, null, 60)
        if (result.optInt("exit_code", -1) != 0) return false
        val installed = result.optString("output").lineSequence().filter { it.isNotBlank() }.map { it.substringAfter('\t') }.toList()
        return installed.size == packages.length() && installed.all { it.contains("install ok installed") }
    }

    internal fun installDebian(context: Context, runtime: AILinuxRuntimeFiles, manifest: JSONObject,
        cancelled: () -> Boolean, progress: (String) -> Unit) {
        val spec = manifest.optJSONObject("debian") ?: return
        if (markerMatches(runtime, manifest)) {
            progress("Pachetele Debian din APK sunt deja instalate.")
            return
        }
        progress("Pregătesc repository-ul Debian offline…")
        extractDebianArchive(context, runtime, manifest, cancelled, progress)
        val packages = spec.getJSONArray("packages")
        val names = mutableListOf<String>()
        for (index in 0 until packages.length()) {
            val name = packages.getString(index)
            require(name.matches(Regex("[a-z0-9][a-z0-9+.-]{0,100}"))) { "Nume de pachet Debian invalid." }
            names.add(name)
        }
        val source = "/etc/apt/sources.list.d/godot-ai-offline.list"
        val list = "/var/cache/godot-ai-offline"
        val emptySources = "/var/lib/apt/lists/godot-ai-empty"
        val apt = listOf("-o", "Dir::Etc::sourcelist=$source", "-o", "Dir::Etc::sourceparts=$emptySources",
            "-o", "APT::Get::List-Cleanup=0", "-o", "Acquire::Retries=0")
        val script = "set -eu\n" +
            "mkdir -p $emptySources\n" +
            "printf '%s\\n' 'deb [trusted=yes] file:$list ./' > $source\n" +
            "DEBIAN_FRONTEND=noninteractive /usr/bin/apt-get ${apt.joinToString(" ")} update\n" +
            "DEBIAN_FRONTEND=noninteractive /usr/bin/apt-get ${apt.joinToString(" ")} install -y --no-install-recommends ${names.joinToString(" ")}\n" +
            "/usr/sbin/ldconfig || true\n" +
            "if command -v fc-cache >/dev/null 2>&1; then fc-cache -f >/dev/null 2>&1 || true; fi\n"
        progress("Instalez ${names.size} pachete Debian din APK, fără internet…")
        val result = runtime.launch(listOf("/bin/sh", "-c", script), null, 2400)
        if (result.optInt("exit_code", -1) != 0) {
            error("Instalarea pachetelor Debian offline a eșuat: " + result.optString("output").takeLast(3000))
        }
        AILinuxRuntimeFiles.writeJson(File(runtime.root, MARKER), JSONObject()
            .put("asset_sha256", asset(manifest, spec.getString("asset")).getString("sha256"))
            .put("suite", spec.optString("suite"))
            .put("packages", JSONArray(names))
            .put("installed_at", System.currentTimeMillis()))
        progress("Pachetele Debian au fost instalate din APK.")
    }

    internal fun installPi(context: Context, runtime: AILinuxRuntimeFiles, manifest: JSONObject,
        cancelled: () -> Boolean, progress: (String) -> Unit) {
        check(runtime.state().optBoolean("ready")) { "Runtime-ul Linux nu este pregătit." }
        val node = manifest.getJSONObject("node")
        val pi = manifest.getJSONObject("pi")
        val nodeDir = node.getString("guest_directory")
        val piDir = pi.getString("guest_directory")
        require(nodeDir.matches(Regex("/root/\\.local/node_modules/node")) && piDir.matches(Regex("/root/\\.local/node_modules/@earendil-works/pi-coding-agent"))) {
            "Destinațiile runtime Pi sunt invalide."
        }
        val cache = File(runtime.root, "tmp/godot-ai-packages")
        val staging = "/root/.local.godot-staging"
        val previous = "/root/.local.godot-previous"
        AILinuxRuntimeFiles.deleteTree(cache)
        check(cache.mkdirs()) { "Spațiul temporar pentru Pi nu poate fi creat." }
        try {
            progress("Pregătesc Node.js ${node.optString("version")} din APK…")
            val nodeAsset = copyAsset(context, manifest, node.getString("asset"), File(cache, node.getString("asset")), cancelled, progress)
            progress("Pregătesc harness-ul Pi ${pi.optString("version")} din APK…")
            val piAsset = copyAsset(context, manifest, pi.getString("asset"), File(cache, pi.getString("asset")), cancelled, progress)
            val script = """
                set -eu
                rm -rf '$staging' '$previous'
                mkdir -p '$staging/node_modules/node' '$staging/node_modules/@earendil-works/pi-coding-agent'
                tar -xJf '/tmp/godot-ai-packages/${nodeAsset.name}' --strip-components=1 -C '$staging/node_modules/node'
                tar -xzf '/tmp/godot-ai-packages/${piAsset.name}' --strip-components=1 -C '$staging/node_modules/@earendil-works/pi-coding-agent'
                test -x '$staging/node_modules/node/bin/node'
                test -f '$staging/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js'
                if [ -e /root/.local ]; then mv /root/.local '$previous'; fi
                if ! mv '$staging' /root/.local; then
                    if [ -e '$previous' ]; then mv '$previous' /root/.local; fi
                    exit 1
                fi
                rm -rf '$previous' /tmp/godot-ai-packages
            """.trimIndent()
            progress("Extrag Node.js și Pi direct din pachetele APK…")
            val extracted = runtime.launch(listOf("/bin/sh", "-c", script), null, 1200)
            if (extracted.optInt("exit_code", -1) != 0) {
                error("Extragerea Node.js/Pi a eșuat: " + extracted.optString("output").takeLast(2500))
            }
            val nodeFile = File(runtime.root, PI_NODE)
            val cliFile = File(runtime.root, PI_CLI)
            check(nodeFile.isFile && nodeFile.length() > 1_000_000 && cliFile.isFile) { "Node.js sau Pi lipsește după extragere." }
            val nodeProbe = runtime.launch(listOf("/root/.local/node_modules/node/bin/node", "--version"), null, 120)
            check(nodeProbe.optInt("exit_code", -1) == 0) { "Node.js din APK nu a răspuns: " + nodeProbe.optString("output").takeLast(1000) }
            val piProbe = runtime.launch(listOf("/root/.local/node_modules/node/bin/node",
                "/root/.local/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js", "--version"), null, 180)
            check(piProbe.optInt("exit_code", -1) == 0) { "Pi din APK nu a răspuns: " + piProbe.optString("output").takeLast(1000) }
            progress("Pi ${pi.optString("version")} a fost instalat și verificat din APK.")
        } finally { AILinuxRuntimeFiles.deleteTree(cache) }
    }

    internal fun ensureZivaDependencies(context: Context, runtime: AILinuxRuntimeFiles, manifest: JSONObject,
        ziva: AIZivaPackage, cancelled: () -> Boolean, progress: (String) -> Unit) {
        installDebian(context, runtime, manifest, cancelled, progress)
        val dependencies = AIZivaDependencies(runtime.root,
            { command, seconds -> runtime.launch(command, null, seconds) }, extension = ziva.extension)
        val missing = dependencies.missing()
        check(missing.isEmpty()) { "Biblioteci Ziva lipsesc din pachetele APK: ${missing.take(6).joinToString(", ")}" }
    }

    internal fun installZiva(context: Context, runtime: AILinuxRuntimeFiles, manifest: JSONObject,
        cancelled: () -> Boolean, progress: (String) -> Unit): AIZivaPackage {
        val zivaSpec = manifest.optJSONObject("ziva") ?: error("Pachetele Ziva lipsesc din această distribuție.")
        check(runtime.root.usableSpace >= 2L * 1024 * 1024 * 1024) {
            "Spațiu insuficient pentru Ziva: sunt necesari aproximativ 2 GB liberi."
        }
        val cache = File(context.cacheDir, "godot-ai-ziva-${UUID.randomUUID()}")
        check(cache.mkdirs()) { "Spațiul temporar Ziva nu poate fi creat." }
        try {
            val ziva = AIZivaPackage(runtime.root, AIZivaPackage.RELEASE)
            val godot = AIZivaGodot(runtime.root, AIZivaGodot.RELEASE)
            val addon = copyAsset(context, manifest, zivaSpec.getJSONObject("addon").getString("asset"),
                File(cache, zivaSpec.getJSONObject("addon").getString("asset")), cancelled, progress)
            val runtimeArchive = copyAsset(context, manifest, zivaSpec.getJSONObject("runtime").getString("asset"),
                File(cache, zivaSpec.getJSONObject("runtime").getString("asset")), cancelled, progress)
            val godotArchive = copyAsset(context, manifest, zivaSpec.getJSONObject("godot").getString("asset"),
                File(cache, zivaSpec.getJSONObject("godot").getString("asset")), cancelled, progress)
            val zivaValid = try { ziva.verify(); true } catch (_: Exception) { false }
            if (!zivaValid) {
                progress("Extrag Ziva ${ziva.version} din APK…")
                ziva.extract(addon, runtimeArchive, cancelled)
            }
            ziva.verify()
            val godotValid = try { godot.verify(); true } catch (_: Exception) { false }
            if (!godotValid) {
                progress("Extrag Godot ${AIZivaGodot.RELEASE.version} Linux ARM64 din APK…")
                godot.extract(godotArchive, cancelled)
            }
            godot.verify()
            ensureZivaDependencies(context, runtime, manifest, ziva, cancelled, progress)
            val version = runtime.launch(listOf(ziva.guestBinary, "--version"), null, 60)
            check(version.optInt("exit_code", -1) == 0 && version.optString("output").lineSequence().any { it.trim() == ziva.version }) {
                "Ziva din APK nu a trecut verificarea: " + version.optString("output").takeLast(1000)
            }
            val engine = runtime.launch(listOf(godot.guestBinary, "--version"), null, 60)
            check(engine.optInt("exit_code", -1) == 0 && engine.optString("output").contains(AIZivaGodot.RELEASE.version + ".stable")) {
                "Godot din APK nu a trecut verificarea: " + engine.optString("output").takeLast(1000)
            }
            ziva.activate()
            progress("Ziva ${ziva.version} și Godot ${AIZivaGodot.RELEASE.version} au fost verificate din APK.")
            return ziva
        } finally { AILinuxRuntimeFiles.deleteTree(cache) }
    }

    fun status(context: Context): JSONObject {
        val runtime = AILinuxRuntime.core(context)
        val linux = runtime.state()
        val manifest = try { manifest(context) } catch (error: Exception) {
            return JSONObject().put("ok", false).put("error", error.message ?: "Pachetele runtime lipsesc.").put("bundled", false)
        }
        val node = File(runtime.root, PI_NODE)
        val cli = File(runtime.root, PI_CLI)
        val piVersion = try {
            JSONObject(File(runtime.root, "root/.local/node_modules/@earendil-works/pi-coding-agent/package.json").readText()).optString("version")
        } catch (_: Exception) { "" }
        val marker = AILinuxRuntimeFiles.readJson(File(runtime.root, MARKER))
        val debianSpec = manifest.optJSONObject("debian")
        val debianReady = if (debianSpec == null) false else try {
            marker.optString("asset_sha256") == asset(manifest, debianSpec.getString("asset")).getString("sha256")
        } catch (_: Exception) { false }
        val zivaSpec = manifest.optJSONObject("ziva")
        var zivaReady = false
        var godotReady = false
        var zivaVersion = ""
        if (zivaSpec != null) {
            try {
                val ziva = AIZivaPackage(runtime.root, AIZivaPackage.RELEASE)
                zivaVersion = ziva.version
                zivaReady = ziva.installed()
                godotReady = AIZivaGodot(runtime.root, AIZivaGodot.RELEASE).installed()
            } catch (_: Exception) {}
        }
        val piReady = node.isFile && node.length() > 1_000_000 && cli.isFile && piVersion == manifest.getJSONObject("pi").optString("version")
        val linuxReady = linux.optBoolean("ready") && linux.optString("base_sha256").isNotEmpty()
        val expectedBase = try {
            context.assets.open("godot_ai/linux/package.json").bufferedReader().use { JSONObject(it.readText()).optString("source_sha256") }
        } catch (_: Exception) { "" }
        val baseCurrent = expectedBase.isNotEmpty() && linux.optString("base_sha256") == expectedBase
        val allReady = linuxReady && baseCurrent && piReady && debianReady && (zivaSpec == null || (zivaReady && godotReady))
        return JSONObject().put("ok", true).put("bundled", true)
            .put("distribution", manifest.optString("distribution"))
            .put("manifest", manifest)
            .put("linux", JSONObject().put("ready", linuxReady).put("current", baseCurrent)
                .put("release", linux.optString("release")).put("base_sha256", linux.optString("base_sha256")))
            .put("node", JSONObject().put("ready", node.isFile && node.length() > 1_000_000)
                .put("version", manifest.getJSONObject("node").optString("version")))
            .put("pi", JSONObject().put("ready", piReady).put("version", piVersion.ifEmpty { manifest.getJSONObject("pi").optString("version") }))
            .put("debian", JSONObject().put("ready", debianReady).put("suite", debianSpec?.optString("suite").orEmpty())
                .put("packages", debianSpec?.optJSONArray("packages")?.length() ?: 0))
            .put("ziva", JSONObject().put("bundled", zivaSpec != null).put("ready", zivaReady).put("version", zivaVersion))
            .put("godot", JSONObject().put("bundled", zivaSpec != null).put("ready", godotReady).put("version", AIZivaGodot.RELEASE.version))
            .put("all_ready", allReady).put("active_job", AILinuxRuntime.packageJob(context))
            .put("last_job", AILinuxRuntime.latestPackageJob(context))
    }

    fun update(context: Context, runtime: AILinuxRuntimeFiles, cancelled: () -> Boolean,
        progress: (String) -> Unit): JSONObject {
        val packageManifest = manifest(context)
        progress("Actualizez mediul runtime exclusiv din pachetele incluse în APK.")
        val linux = runtime.ensureCurrentBase(emptyList())
        check(linux.optBoolean("ready")) { "Baza Debian nu a putut fi pregătită." }
        progress("Debian ${linux.optString("release")} este pregătit.")
        installDebian(context, runtime, packageManifest, cancelled, progress)
        installPi(context, runtime, packageManifest, cancelled, progress)
        if (packageManifest.optJSONObject("ziva") != null) {
            check(BuildConfig.GODOT_AI_ZIVA) { "Pachetele Ziva nu aparțin acestei distribuții." }
            installZiva(context, runtime, packageManifest, cancelled, progress)
        } else if (BuildConfig.GODOT_AI_ZIVA) {
            error("Distribuția Ziva nu conține pachetele Ziva.")
        }
        stop(cancelled)
        runtime.verify()
        val result = status(context)
        check(result.optBoolean("all_ready")) { "Unele pachete nu au trecut verificarea după actualizare." }
        progress("Toate pachetele runtime sunt actualizate și verificate.")
        return result
    }
}
