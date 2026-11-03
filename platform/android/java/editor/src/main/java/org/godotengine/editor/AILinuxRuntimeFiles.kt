package org.godotengine.editor

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.InputStream
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.Path
import java.nio.file.SimpleFileVisitor
import java.nio.file.FileVisitResult
import java.nio.file.attribute.BasicFileAttributes
import java.nio.file.attribute.PosixFilePermission
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.TimeUnit
import java.util.zip.ZipFile

/** Portable core. Only native executables packaged in the APK start host processes. */
class AILinuxRuntimeFiles(
    val base: File,
    private val nativeDirectory: File,
    private val asset: (String) -> InputStream,
    private val cancelled: () -> Boolean = { false },
    private val progress: (String) -> Unit = {},
) {
    companion object {
        const val MAX_LOG = 131072
        val TOOL_PACKAGES = linkedMapOf(
            "python" to listOf("python3", "python3-venv", "python3-pip", "ca-certificates"),
            "node" to listOf("nodejs", "npm", "ca-certificates"),
            "git" to listOf("git", "ca-certificates"),
            "ripgrep" to listOf("ripgrep"),
            "blender" to listOf("blender"),
        )
        val TOOL_PROBES = mapOf("python" to listOf("python3", "--version"), "node" to listOf("node", "--version"),
            "git" to listOf("git", "--version"), "ripgrep" to listOf("rg", "--version"), "blender" to listOf("blender", "--background", "--version"))

        fun sha(file: File): String = file.inputStream().use { input ->
            val digest = MessageDigest.getInstance("SHA-256")
            val buffer = ByteArray(65536)
            while (true) { val count = input.read(buffer); if (count < 0) break; digest.update(buffer, 0, count) }
            digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
        }
        fun writeJson(file: File, value: JSONObject) {
            check(file.parentFile!!.isDirectory || file.parentFile!!.mkdirs())
            val temporary = File(file.parentFile, file.name + "." + UUID.randomUUID() + ".tmp")
            temporary.outputStream().use { stream -> stream.write(value.toString().toByteArray()); stream.fd.sync() }
            check(temporary.renameTo(file)) { "Starea runtime nu a putut fi salvată." }
        }
        fun readJson(file: File): JSONObject = try { JSONObject(file.readText()) } catch (_: Exception) { JSONObject() }
        fun deleteTree(file: File) {
            if (!Files.exists(file.toPath(), LinkOption.NOFOLLOW_LINKS)) return
            Files.walkFileTree(file.toPath(), object : SimpleFileVisitor<Path>() {
                override fun visitFile(path: Path, attrs: BasicFileAttributes): FileVisitResult { Files.delete(path); return FileVisitResult.CONTINUE }
                override fun postVisitDirectory(path: Path, error: java.io.IOException?): FileVisitResult {
                    if (error != null) throw error
                    Files.delete(path); return FileVisitResult.CONTINUE
                }
            })
        }
        private fun relative(value: String): String {
            require(value.isNotEmpty() && !value.startsWith("/") && !value.contains('\\') && !value.contains('\u0000')) { "Cale runtime invalidă." }
            require(value.split('/').none { it.isEmpty() || it == "." || it == ".." }) { "Cale runtime invalidă." }
            return value
        }
        private fun permissions(file: File, mode: Int) {
            val options = listOf(PosixFilePermission.OWNER_READ, PosixFilePermission.OWNER_WRITE, PosixFilePermission.OWNER_EXECUTE,
                PosixFilePermission.GROUP_READ, PosixFilePermission.GROUP_WRITE, PosixFilePermission.GROUP_EXECUTE,
                PosixFilePermission.OTHERS_READ, PosixFilePermission.OTHERS_WRITE, PosixFilePermission.OTHERS_EXECUTE)
            Files.setPosixFilePermissions(file.toPath(), options.filterIndexed { index, _ -> mode and (1 shl (8 - index)) != 0 }.toSet())
        }
    }

    val root = File(base, "rootfs")
    private val stateFile = File(base, "state.json")

    fun state(): JSONObject {
        val state = readJson(stateFile)
        state.put("installed", Files.exists(root.toPath(), LinkOption.NOFOLLOW_LINKS))
        state.put("packaged", File(nativeDirectory, "libai_proot.so").isFile && File(nativeDirectory, "libai_proot_loader.so").isFile)
        if (!File(root, "etc/os-release").isFile || Files.isSymbolicLink(root.toPath()) || !state.optBoolean("packaged")) state.put("ready", false)
        return state
    }

    fun install(dns: List<String>) {
        check(!root.exists()) { "Linux este deja instalat. Folosește Verifică." }
        check(base.isDirectory || base.mkdirs())
        val spec = packageSpec()
        check(spec.getInt("schema") == 1 && spec.getString("architecture") == "arm64") { "Pachet Linux incompatibil." }
        for (orphan in base.listFiles().orEmpty()) {
            if (orphan.name.matches(Regex("install-[a-f0-9-]{36}"))) deleteTree(orphan)
        }
        val needed = spec.getLong("unpacked_bytes") + spec.getLong("size") + 128L * 1024 * 1024
        check(base.usableSpace >= needed) { "Spațiu insuficient pentru Linux: sunt necesari ${needed / (1024 * 1024)} MB." }
        val staging = File(base, "install-" + UUID.randomUUID())
        try {
            stageRootfs(spec, staging)
            configure(staging, dns)
            check(staging.renameTo(root)) { "Instalarea Linux nu a putut fi activată." }
            writeJson(stateFile, JSONObject().put("ready", false).put("distribution", spec.getString("distribution"))
                .put("release", spec.getString("release")).put("base_sha256", spec.getString("source_sha256")).put("tools", JSONObject()))
            verify()
        } finally { deleteTree(staging) }
    }

    private fun packageSpec(): JSONObject =
        asset("godot_ai/linux/package.json").bufferedReader().use { JSONObject(it.readText()) }

    private fun stageRootfs(spec: JSONObject, staging: File) {
        val archive = File(base, "rootfs-install.zip")
        try {
            progress("Pregătesc Linux în memoria aplicației…")
            asset("godot_ai/linux/rootfs.zip").use { input -> archive.outputStream().use { output ->
                val buffer = ByteArray(65536); var size = 0L
                while (true) { stopCheck(); val count = input.read(buffer); if (count < 0) break; size += count
                    check(size <= spec.getLong("size")) { "Pachet Linux prea mare." }; output.write(buffer, 0, count) }
            } }
            check(archive.length() == spec.getLong("size") && sha(archive) == spec.getString("sha256")) { "Pachet Linux corupt." }
            unpack(archive, staging)
        } finally { archive.delete() }
    }

    /**
     * Apply the Debian base pinned by this APK. A newer APK replaces the base
     * filesystem atomically while retaining Pi configuration and sessions.
     * External Godot projects live under /workspace bindings and are untouched.
     */
    fun ensureCurrentBase(dns: List<String>): JSONObject {
        if (!root.exists()) {
            install(dns)
            return state()
        }
        check(!Files.isSymbolicLink(root.toPath()) && File(root, "etc/os-release").isFile) { "Runtime-ul Linux este corupt." }
        val spec = packageSpec()
        val current = state()
        if (current.optString("base_sha256") == spec.getString("source_sha256")) {
            return try { verify() } catch (error: Exception) {
                progress("Runtime-ul Linux nu a trecut verificarea; reconstruiesc baza din APK…")
                rebuildBase(spec, dns)
            }
        }
        progress("Actualizez baza Debian din APK…")
        return rebuildBase(spec, dns)
    }

    private fun rebuildBase(spec: JSONObject, dns: List<String>): JSONObject {
        val staging = File(base, "install-" + UUID.randomUUID())
        val previous = File(base, "previous-" + UUID.randomUUID())
        val oldState = readJson(stateFile)
        val preserved = File(root, "root/.pi")
        val preserveCopy = File(base, "preserve-" + UUID.randomUUID())
        val needed = spec.getLong("unpacked_bytes") + spec.getLong("size") + 256L * 1024 * 1024
        check(base.usableSpace >= needed) { "Spațiu insuficient pentru actualizarea Linux: sunt necesari ${needed / (1024 * 1024)} MB." }
        try {
            stageRootfs(spec, staging)
            configure(staging, dns)
            if (preserved.isDirectory && !Files.isSymbolicLink(preserved.toPath())) {
                progress("Păstrez configurația și sesiunile Pi…")
                copyTree(preserved, File(preserveCopy, "root/.pi"))
            }
            check(root.renameTo(previous)) { "Runtime-ul Linux vechi nu poate fi păstrat temporar." }
            if (!staging.renameTo(root)) {
                check(previous.renameTo(root)) { "Runtime-ul Linux trebuie reparat." }
                error("Noua bază Linux nu a putut fi activată.")
            }
            return try {
                if (preserveCopy.isDirectory) {
                    val target = File(root, "root/.pi")
                    deleteTree(target)
                    check(target.parentFile!!.isDirectory || target.parentFile!!.mkdirs())
                    copyTree(File(preserveCopy, "root/.pi"), target)
                }
                writeJson(stateFile, JSONObject().put("ready", false).put("distribution", spec.getString("distribution"))
                    .put("release", spec.getString("release")).put("base_sha256", spec.getString("source_sha256")).put("tools", JSONObject()))
                val verified = verify()
                deleteTree(previous)
                verified
            } catch (error: Exception) {
                deleteTree(root)
                check(previous.renameTo(root)) { "Baza Linux anterioară trebuie restaurată manual." }
                writeJson(stateFile, oldState)
                throw error
            }
        } finally {
            deleteTree(staging)
            deleteTree(preserveCopy)
        }
    }

    private fun copyTree(source: File, destination: File) {
        val sourcePath = source.toPath()
        check(!Files.isSymbolicLink(sourcePath) && source.isDirectory)
        Files.walkFileTree(sourcePath, object : SimpleFileVisitor<Path>() {
            override fun preVisitDirectory(path: Path, attrs: BasicFileAttributes): FileVisitResult {
                stopCheck()
                val target = destination.toPath().resolve(sourcePath.relativize(path).toString())
                check(target.startsWith(destination.toPath()))
                Files.createDirectories(target)
                return FileVisitResult.CONTINUE
            }
            override fun visitFile(path: Path, attrs: BasicFileAttributes): FileVisitResult {
                stopCheck()
                val target = destination.toPath().resolve(sourcePath.relativize(path).toString())
                check(target.startsWith(destination.toPath()))
                if (Files.isSymbolicLink(path)) {
                    val link = Files.readSymbolicLink(path)
                    check(!link.isAbsolute && target.parent.resolve(link).normalize().startsWith(destination.toPath())) {
                        "Configurația Pi conține o legătură nesigură."
                    }
                    Files.createSymbolicLink(target, link)
                } else {
                    Files.copy(path, target, java.nio.file.StandardCopyOption.REPLACE_EXISTING,
                        java.nio.file.StandardCopyOption.COPY_ATTRIBUTES, LinkOption.NOFOLLOW_LINKS)
                }
                return FileVisitResult.CONTINUE
            }
        })
    }

    /** Files first, links last. Never extract data through an archive-created symlink. */
    fun unpack(archive: File, destination: File) {
        check(!destination.exists() && destination.mkdirs())
        ZipFile(archive).use { zip ->
            val metadata = zip.getEntry("manifest.json") ?: error("Manifest Linux absent.")
            check(metadata.size in 1..16 * 1024 * 1024)
            val manifest = zip.getInputStream(metadata).bufferedReader().use { JSONObject(it.readText()) }
            check(manifest.getInt("schema") == 1 && manifest.getString("architecture") == "arm64")
            val entries = manifest.getJSONArray("entries")
            check(entries.length() in 1..30000)
            val names = HashSet<String>(); val links = HashSet<String>(); var total = 0L
            for (index in 0 until entries.length()) {
                val entry = entries.getJSONObject(index); val name = relative(entry.getString("path"))
                check(names.add(name)) { "Cale Linux duplicată." }
                if (entry.getString("type") == "symlink") links.add(name)
                if (entry.getString("type") == "file") { total += entry.getLong("size"); check(entry.getLong("size") in 0..128L * 1024 * 1024) }
            }
            check(total == manifest.getLong("unpacked_bytes") && total <= 512L * 1024 * 1024)
            for (name in names) {
                var parent = File(name).parent
                while (parent != null) { check(!links.contains(parent)) { "Pachetul scrie printr-o legătură." }; parent = File(parent).parent }
            }
            for (index in 0 until entries.length()) {
                stopCheck()
                val entry = entries.getJSONObject(index); val file = File(destination, entry.getString("path"))
                if (entry.getString("type") == "symlink") continue
                check(file.parentFile!!.isDirectory || file.parentFile!!.mkdirs())
                when (entry.getString("type")) {
                    "directory" -> check(file.isDirectory || file.mkdirs())
                    "file" -> {
                        val member = zip.getEntry("files/" + entry.getString("path")) ?: error("Fișier Linux absent.")
                        check(member.size == entry.getLong("size"))
                        zip.getInputStream(member).use { input -> file.outputStream().use { output ->
                            val buffer = ByteArray(65536); var copied = 0L
                            while (true) { stopCheck(); val count = input.read(buffer); if (count < 0) break; copied += count
                                check(copied <= member.size); output.write(buffer, 0, count) }
                            check(copied == member.size)
                        } }
                        check(sha(file) == entry.getString("sha256")) { "Fișier Linux corupt." }
                        permissions(file, entry.getInt("mode") and 511)
                    }
                    else -> error("Tip de fișier Linux necunoscut.")
                }
            }
            for (index in 0 until entries.length()) {
                stopCheck()
                val entry = entries.getJSONObject(index)
                if (entry.getString("type") != "symlink") continue
                val file = File(destination, entry.getString("path")); val target = entry.getString("target")
                check(!target.startsWith("/") && !target.contains('\\') && !target.contains('\u0000'))
                val resolved = file.parentFile!!.toPath().resolve(target).normalize()
                check(resolved.startsWith(destination.toPath())) { "Legătura iese din Linux." }
                check(file.parentFile!!.isDirectory || file.parentFile!!.mkdirs())
                Files.createSymbolicLink(file.toPath(), java.nio.file.Paths.get(target))
            }
        }
    }

    private fun configure(directory: File, dns: List<String>) {
        for (path in listOf("tmp", "root", "workspace", "dev", "proc", "sys", "opt/godot-tools", "etc/apt/apt.conf.d")) File(directory, path).mkdirs()
        writeDns(directory, dns)
        File(directory, "etc/hosts").writeText("127.0.0.1 localhost\n::1 localhost\n")
        File(directory, "etc/apt/apt.conf.d/99godot").writeText("APT::Sandbox::User \"root\";\nAcquire::Retries \"2\";\nAcquire::http::Timeout \"30\";\n")
        File(directory, "usr/sbin/policy-rc.d").apply { writeText("#!/bin/sh\nexit 101\n"); setExecutable(true) }
    }

    /** Android can change networks after installation; do not retain the old carrier DNS. */
    fun synchronizeDns(dns: List<String>) {
        if (!root.isDirectory) return
        check(!Files.isSymbolicLink(root.toPath())) { "Filesystem Linux invalid." }
        writeDns(root, dns)
    }

    /** Use Android-resolved repository addresses when raw guest DNS is restricted. */
    fun synchronizePackageHosts(addresses: List<String>) {
        synchronizeHosts(mapOf("deb.debian.org" to addresses))
    }

    /** Pin every repository host so npm and apt do not depend on the guest resolver. */
    fun synchronizeHosts(hosts: Map<String, List<String>>) {
        check(root.isDirectory && !Files.isSymbolicLink(root.toPath())) { "Linux indisponibil." }
        val etc = File(root, "etc")
        check(etc.isDirectory && !Files.isSymbolicLink(etc.toPath()))
        val safeHosts = hosts.mapNotNull { (host, addresses) ->
            if (!host.matches(Regex("[a-zA-Z0-9.-]{1,253}"))) return@mapNotNull null
            val safe = addresses.filter { it.matches(Regex("[a-fA-F0-9:.]+")) }.distinct().take(4)
            if (safe.isEmpty()) null else host to safe
        }
        check(safeHosts.isNotEmpty()) { "Adresele serverelor de pachete nu pot fi rezolvate." }
        val target = File(etc, "hosts")
        val original = if (target.isFile && !Files.isSymbolicLink(target.toPath())) target.readText() else "127.0.0.1 localhost\n::1 localhost\n"
        val start = "# Godot managed package repository"
        val end = "# End Godot managed package repository"
        val old = Regex("(?ms)^" + Regex.escape(start) + "\\n.*?^" + Regex.escape(end) + "(?:\\n|$)")
        val entries = safeHosts.flatMap { (host, addresses) -> addresses.map { "$it $host" } }
        val text = original.replace(old, "").trimEnd() + "\n" + start + "\n" +
            entries.joinToString("\n") + "\n" + end + "\n"
        if (text == original) return
        val temporary = File(etc, "hosts.godot-${UUID.randomUUID()}.tmp")
        try {
            temporary.writeText(text)
            check(temporary.renameTo(target)) { "Rețeaua pachetelor Linux nu poate fi pregătită." }
        } finally { temporary.delete() }
    }

    private fun writeDns(directory: File, dns: List<String>) {
        val etc = File(directory, "etc")
        check(!Files.isSymbolicLink(etc.toPath()) && etc.isDirectory) { "Directorul de rețea Linux este invalid." }
        val servers = dns.filter { it.matches(Regex("[a-fA-F0-9:.]+")) }.distinct().take(4).ifEmpty { listOf("1.1.1.1", "8.8.8.8") }
        val text = servers.joinToString("\n") { "nameserver $it" } + "\noptions timeout:2 attempts:2\n"
        val file = File(etc, "resolv.conf")
        if (!Files.isSymbolicLink(file.toPath()) && file.isFile && file.readText() == text) return
        val temporary = File(etc, "resolv.godot-${UUID.randomUUID()}.tmp")
        try {
            temporary.writeText(text)
            check(temporary.renameTo(file)) { "DNS-ul Linux nu poate fi actualizat." }
        } finally { temporary.delete() }
    }

    fun verify(): JSONObject {
        val previous = state().put("ready", false)
        writeJson(stateFile, previous)
        val result = launch(listOf("/bin/sh", "-c", "printf 'GODOT_LINUX_RUNTIME_V1\\n'; dpkg --print-architecture"), null, 30)
        check(result.getInt("exit_code") == 0 && result.getString("output").contains("GODOT_LINUX_RUNTIME_V1\narm64")) { "Linux nu a trecut verificarea. ${result.optString("output")}" }
        val state = state(); state.put("ready", true).put("verified_at", System.currentTimeMillis())
        val tools = JSONObject()
        for ((name, command) in TOOL_PROBES) {
            if (!File(root, "usr/bin/" + command[0]).exists()) continue
            val probe = launch(command, null, 30)
            if (probe.getInt("exit_code") == 0) tools.put(name, JSONObject().put("ready", true).put("version", probe.getString("output").lineSequence().firstOrNull().orEmpty().take(160)))
        }
        state.put("tools", tools)
        writeJson(stateFile, state)
        return state
    }

    fun installTool(name: String): JSONObject {
        val packages = TOOL_PACKAGES[name] ?: error("Utilitar necunoscut.")
        check(state().optBoolean("ready")) { "Instalează și verifică mai întâi Linux." }
        if (System.currentTimeMillis() - state().optLong("apt_updated_at") > 600_000) {
            progress("Actualizez lista de pachete…")
            check(launch(listOf("/usr/bin/apt-get", "update"), null, 300).getInt("exit_code") == 0) { "Lista de pachete nu a putut fi actualizată." }
            writeJson(stateFile, state().put("apt_updated_at", System.currentTimeMillis()))
        }
        progress("Instalez $name…")
        check(launch(listOf("/usr/bin/apt-get", "install", "-y", "--no-install-recommends") + packages, null, 1200).getInt("exit_code") == 0) { "Instalarea $name a eșuat." }
        launch(listOf("/usr/bin/apt-get", "clean"), null, 30)
        val result = verify()
        check(result.getJSONObject("tools").has(name)) { "Utilitarul instalat nu a trecut verificarea." }
        return result
    }

    fun execute(command: String, project: File, seconds: Int): JSONObject {
        require(command.isNotBlank() && command.length <= 16000 && !command.contains('\u0000')) { "Comandă invalidă." }
        check(state().optBoolean("ready")) { "Runtime Linux indisponibil." }
        check(project.isAbsolute && project.isDirectory && File(project, "project.godot").isFile && !project.path.contains(':')) { "Proiect Godot invalid." }
        return launch(listOf("/bin/sh", "-lc", command), project.canonicalFile, seconds.coerceIn(1, 600))
    }

    private fun stopCheck() { check(!cancelled()) { "Operație anulată." } }

    /** A managed service owns the lifetime when no command timeout is appropriate. */
    fun startProcess(command: List<String>, project: File?, extraEnvironment: Map<String, String> = emptyMap(),
        binds: List<Pair<String, String>> = emptyList()): Process {
        stopCheck()
        val arguments = prootArguments(command, project, binds)
        return ProcessBuilder(arguments).redirectErrorStream(true).apply {
            environment().clear()
            environment().putAll(processEnvironment(extraEnvironment))
        }.start()
    }

    /** PRoot invocation shared with the PTY host, which execs it on a terminal. */
    fun prootArguments(command: List<String>, project: File?, binds: List<Pair<String, String>> = emptyList()): List<String> {
        check(root.isDirectory && !Files.isSymbolicLink(root.toPath())) { "Filesystem Linux invalid. Dezinstalează și reinstalează Linux." }
        val proot = File(nativeDirectory, "libai_proot.so"); val loader = File(nativeDirectory, "libai_proot_loader.so")
        check(proot.canExecute() && loader.canExecute()) { "Executabilele Linux nu sunt ambalate în aplicație." }
        val args = mutableListOf(proot.absolutePath, "--kill-on-exit", "--link2symlink", "--sysvipc", "-L", "-0", "-r", root.absolutePath,
            "-b", "/dev", "-b", "/proc", "-b", "/sys")
        if (project != null) args.addAll(listOf("-b", project.absolutePath + ":/workspace"))
        for ((source, destination) in binds) {
            val host = File(source).absoluteFile
            check(host.exists() && !Files.isSymbolicLink(host.toPath())) { "Legătură privată invalidă." }
            require(destination.startsWith("/") && !destination.contains(':') && !destination.contains('\u0000') &&
                destination.split('/').none { it == ".." || it == "." }) { "Destinație Ziva invalidă." }
            args.addAll(listOf("-b", host.path + ":" + destination))
        }
        args.addAll(listOf("-w", if (project != null) "/workspace" else "/root")); args.addAll(command)
        return args
    }

    fun processEnvironment(extra: Map<String, String> = emptyMap()): Map<String, String> {
        val loader = File(nativeDirectory, "libai_proot_loader.so")
        val scratch = File(base, "tmp").apply { mkdirs() }
        val environment = linkedMapOf(
            "PATH" to "/root/.local/node_modules/.bin:/usr/local/bin:/usr/bin:/bin", "HOME" to "/root", "USER" to "root", "LANG" to "C.UTF-8",
            "TMPDIR" to "/tmp", "ANDROID_ROOT" to "/system", "ANDROID_DATA" to "/data", "PROOT_LOADER" to loader.absolutePath,
            "PROOT_TMP_DIR" to scratch.absolutePath, "DEBIAN_FRONTEND" to "noninteractive")
        environment.putAll(extra)
        return environment
    }

    fun launch(command: List<String>, project: File?, seconds: Int): JSONObject {
        val child = startProcess(command, project)
        val output = StringBuilder(); var truncated = false
        val reader = Thread({
            try { child.inputStream.bufferedReader().use { input ->
                val buffer = CharArray(2048)
                while (true) { val count = input.read(buffer); if (count < 0) break
                    val text = String(buffer, 0, count)
                    synchronized(output) { output.append(text); if (output.length > MAX_LOG) { output.delete(0, output.length - MAX_LOG); truncated = true } }
                    progress(text)
                }
            } } catch (_: Exception) { /* process cancellation closes the pipe */ }
        }, "GodotLinuxOutput").apply { isDaemon = true; start() }
        var timedOut = false
        try {
            val deadline = System.nanoTime() + seconds * 1_000_000_000L
            while (!child.waitFor(100, TimeUnit.MILLISECONDS)) {
                if (cancelled() || System.nanoTime() >= deadline) {
                    timedOut = !cancelled()
                    child.destroy(); if (!child.waitFor(2, TimeUnit.SECONDS)) child.destroyForcibly()
                    break
                }
            }
            reader.join(3000)
            stopCheck()
            check(!timedOut) { "Comanda a depășit limita de timp." }
            return JSONObject().put("exit_code", child.exitValue()).put("output", synchronized(output) { output.toString() }).put("truncated", truncated)
        } finally { child.destroy(); reader.join(1000) }
    }

    fun uninstall() { deleteTree(root); stateFile.delete() }
}
