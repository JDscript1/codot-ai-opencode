package org.godotengine.editor

import java.io.File
import java.nio.file.Files
import java.util.UUID
import java.util.zip.ZipFile

/** Official Godot Linux ARM64 used only as the headless host of the Ziva addon. */
class AIZivaGodot(private val root: File, private val spec: Release = RELEASE) {
    data class Release(val version: String, val url: String, val archiveSize: Long, val archiveHash: String,
        val member: String, val binarySize: Long, val binaryHash: String)
    companion object {
        val RELEASE = Release("4.7.2",
            "https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.arm64.zip",
            77008699, "5dd0d86405cf7e8adf79fb6377b38ba682a2846cb378ffe5364f38c01ad29b9d",
            "Godot_v4.7.2-stable_linux.arm64", 137953888,
            "3fcb80f4fe794e3859360eb641d8c41d8ffe2c2e54ba1981e55a76851d5ed1f4")
    }
    private val directory get() = safe("opt/godot-tools/godot/${spec.version}")
    val binary get() = File(directory, "godot")
    val guestBinary get() = "/opt/godot-tools/godot/${spec.version}/godot"

    private fun safe(path: String): File {
        require(spec.version.matches(Regex("[0-9]+\\.[0-9]+\\.[0-9]+")))
        check(root.isDirectory && !Files.isSymbolicLink(root.toPath())) { "Linux indisponibil." }
        var file = root
        for (part in path.split('/')) {
            require(part.isNotEmpty() && part != "." && part != "..")
            file = File(file, part)
            check(!Files.isSymbolicLink(file.toPath())) { "Cale Godot nesigură." }
        }
        check(file.canonicalPath.startsWith(root.canonicalPath + File.separator))
        return file
    }

    fun installed(): Boolean = try { binary.isFile && binary.length() == spec.binarySize } catch (_: Exception) { false }
    fun verify() {
        check(installed() && AILinuxRuntimeFiles.sha(binary) == spec.binaryHash) { "Godot pentru Ziva este absent sau corupt. Reinstalează Ziva." }
    }

    fun extract(archive: File, cancelled: () -> Boolean = { false }) {
        check(archive.length() == spec.archiveSize && AILinuxRuntimeFiles.sha(archive) == spec.archiveHash) { "Verificarea SHA-256 Godot a eșuat." }
        val target = directory
        check(target.parentFile!!.isDirectory || target.parentFile!!.mkdirs())
        for (orphan in target.parentFile!!.listFiles().orEmpty()) {
            if (orphan.name.matches(Regex("(staging|previous)-[a-f0-9-]{36}"))) AILinuxRuntimeFiles.deleteTree(orphan)
        }
        val staging = File(target.parentFile, "staging-${UUID.randomUUID()}")
        check(staging.mkdir())
        try {
            ZipFile(archive).use { zip ->
                val member = zip.getEntry(spec.member) ?: error("Executabilul Godot lipsește din arhivă.")
                check(!member.isDirectory && member.size == spec.binarySize) { "Executabil Godot invalid." }
                val file = File(staging, "godot")
                zip.getInputStream(member).use { input -> file.outputStream().use { output ->
                    val buffer = ByteArray(65536); var copied = 0L
                    while (true) {
                        check(!cancelled()) { "Operație anulată." }
                        val read = input.read(buffer); if (read < 0) break
                        copied += read; check(copied <= spec.binarySize); output.write(buffer, 0, read)
                    }
                    check(copied == spec.binarySize) { "Executabil Godot incomplet." }
                } }
            }
            val executable = File(staging, "godot")
            check(executable.length() == spec.binarySize && AILinuxRuntimeFiles.sha(executable) == spec.binaryHash) { "Executabil Godot corupt." }
            check(executable.setExecutable(true, false)) { "Permisiunile Godot nu pot fi setate." }
            check(!cancelled()) { "Operație anulată." }
            val previous = File(target.parentFile, "previous-${UUID.randomUUID()}")
            val hadPrevious = target.exists()
            if (hadPrevious) check(target.renameTo(previous)) { "Instalarea Godot existentă nu a putut fi păstrată." }
            if (!staging.renameTo(target)) {
                if (hadPrevious) check(previous.renameTo(target)) { "Instalarea Godot trebuie reparată." }
                error("Godot nu a putut fi activat.")
            }
            if (hadPrevious) AILinuxRuntimeFiles.deleteTree(previous)
        } finally { AILinuxRuntimeFiles.deleteTree(staging) }
    }
}
