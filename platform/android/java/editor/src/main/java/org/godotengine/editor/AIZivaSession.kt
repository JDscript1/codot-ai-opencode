package org.godotengine.editor

import org.json.JSONObject
import java.io.File
import java.io.RandomAccessFile
import java.nio.file.Files
import java.nio.channels.FileLock
import java.nio.channels.OverlappingFileLockException

/** Kernel-held ownership: a saved JSON status can never keep a dead session alive. */
class AIZivaSession(private val directory: File) {
    class Lease(private val file: RandomAccessFile, private val lock: FileLock, private val key: String) : AutoCloseable {
        override fun close() = synchronized(held) {
            try { if (lock.isValid) lock.release() } finally { file.close(); held.remove(key) }
        }
    }
    fun acquire(): Lease? = synchronized(held) {
        val key = directory.canonicalPath
        if (key in held) return null
        check(directory.isDirectory || directory.mkdirs())
        val target = File(directory, "session.lock")
        check(!Files.isSymbolicLink(directory.toPath()) && !Files.isSymbolicLink(target.toPath()))
        val file = RandomAccessFile(target, "rw")
        return try {
            val lock = try { file.channel.tryLock() } catch (_: OverlappingFileLockException) { null }
            if (lock == null) { file.close(); null } else { held.add(key); Lease(file, lock, key) }
        } catch (error: Exception) { file.close(); throw error }
    }
    fun active(): Boolean {
        val lease = acquire() ?: return true
        lease.close()
        return false
    }
    companion object {
        private val held = HashSet<String>()
        const val OWNER_FILE = "/run/godot-ai-ziva/owner"
        fun startupEnvironment(): Map<String, String> = mapOf(
            "ZIVA_ENABLE_HEADLESS" to "1", "GODOT_SILENCE_ROOT_WARNING" to "1",
            // The official plugin cannot restart this session; versioning belongs to the wrapper.
            "ZIVA_AUTOUPDATE_DRY_RUN" to "1",
            // Android denies real hardlinks. PRoot's emulated links become stale
            // when Git promotes a bulk-fsync temporary object directory.
            "GIT_CONFIG_COUNT" to "1", "GIT_CONFIG_KEY_0" to "core.createObject", "GIT_CONFIG_VALUE_0" to "rename"
        )
        /** Project extensions may lack Linux builds without preventing Ziva from starting. */
        fun officialExtensionFailed(output: CharSequence): Boolean = output.lineSequence().any { raw ->
            val line = raw.replace('\\', '/')
            val loaderFailure = line.contains("Error loading extension:") ||
                line.contains("Can't open GDExtension dynamic library") || line.contains("Can't open dynamic library")
            loaderFailure && (line.contains("res://addons/ziva_agent/") ||
                line.contains("/workspace/addons/ziva_agent/") || line.contains("/opt/godot-tools/ziva/"))
        }
        fun ownerMatches(reply: JSONObject?, nonce: String): Boolean {
            if (!nonce.matches(Regex("[a-f0-9-]{36}"))) return false
            val result = reply?.optJSONObject("result") ?: return false
            if (result.optBoolean("isError")) return false
            val content = result.optJSONArray("content") ?: return false
            val expected = "GODOT_AI_ZIVA_OWNER=$nonce"
            return (0 until content.length()).any { index ->
                content.optJSONObject(index)?.optString("text").orEmpty().lineSequence().any {
                    it.trim().replaceFirst(Regex("^[0-9]+:\\s*"), "") == expected
                }
            }
        }
        fun ownedPorts(share: File, pid: Int): List<Int> = share.walkTopDown().maxDepth(10).filter {
            it.isFile && !Files.isSymbolicLink(it.toPath()) && it.name.startsWith("sidecar-$pid-") && it.name.endsWith(".port") && it.length() < 16
        }.mapNotNull { it.readText().trim().toIntOrNull()?.takeIf { port -> port in 1024..65535 } }.distinct().toList()
        fun bootId(): String = try { File("/proc/sys/kernel/random/boot_id").readText().trim() } catch (_: Exception) { "" }
        fun processStart(pid: Int): String = try {
            File("/proc/$pid/stat").readText().substringAfterLast(") ").split(' ')[19]
        } catch (_: Exception) { "" }
    }
}
