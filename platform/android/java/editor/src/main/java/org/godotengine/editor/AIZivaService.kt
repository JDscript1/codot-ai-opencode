package org.godotengine.editor

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.nio.file.Files
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.atomic.AtomicBoolean

/** Runs the official addon in its own headless Godot Linux editor, beside the Android editor. */
class AIZivaService : Service() {
    companion object {
        const val FIRST_PORT = 7012
        const val LAST_PORT = 7041
        const val READY_TIMEOUT_MS = 180_000L
        const val MAX_LOG = 131072
    }
    private val stopping = AtomicBoolean(false)
    private val executor = Executors.newSingleThreadExecutor()
    private val timer = Executors.newSingleThreadScheduledExecutor()
    private val lock = Any()
    private var state = JSONObject()
    @Volatile private var running = false
    @Volatile private var child: Process? = null
    @Volatile private var guestPidFile: File? = null
    @Volatile private var owner: IBinder? = null
    private var death: IBinder.DeathRecipient? = null
    private val main = Handler(Looper.getMainLooper())
    private var pending: Intent? = null
    private var currentProject = ""
    private var lastStartId = 0
    private var lease: AIZivaSession.Lease? = null
    private var version = AIZivaPackage.RELEASE.version
    private var sessionNonce = ""
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel("godot_ai_ziva", "Ziva", NotificationManager.IMPORTANCE_LOW))
        startForeground(7343, notification("Pregătesc Ziva…"))
    }
    private fun notification(message: String): Notification {
        return Notification.Builder(this, "godot_ai_ziva").setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle("Godot AI · Ziva").setContentText(message.take(120)).setOngoing(true).build()
    }
    private fun cancelled() = stopping.get() || owner?.isBinderAlive != true || AIZivaRuntime.cancelFile(this).exists()
    private fun update(status: String, message: String) = synchronized(lock) {
        state.put("status", status).put("message", message)
        AIZivaRuntime.save(this, state)
        getSystemService(NotificationManager::class.java).notify(7343, notification(message))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        lastStartId = startId
        if (intent?.getBooleanExtra("cancel", false) == true) {
            pending = null; stopping.set(true)
            if (!running) stopSelf(startId)
            return START_NOT_STICKY
        }
        val action = intent?.getStringExtra("action")
        val newOwner = intent?.getBundleExtra("ownership")?.getBinder("owner")
        if (action == "ziva_detach") {
            if (newOwner == owner) { pending = null; stopping.set(true); stopSelf(startId) }
            else if (!running) stopSelf(startId)
            return START_NOT_STICKY
        }
        if (!BuildConfig.GODOT_AI_ZIVA || action !in listOf("ziva_install", "ziva_start") || newOwner?.isBinderAlive != true) {
            if (!running) stopSelf(startId)
            return START_NOT_STICKY
        }
        if (running) {
            // Duplicate automatic attach is idempotent. Explicit restart has a new request.
            if (intent.getBooleanExtra("automatic", false) && action == "ziva_start" &&
                currentProject == intent.getStringExtra("project_directory") && !stopping.get()) return START_NOT_STICKY
            pending = intent
            stopping.set(true)
        } else launch(intent)
        return START_NOT_STICKY
    }

    private fun launch(intent: Intent) {
        val token = intent.getBundleExtra("ownership")?.getBinder("owner") ?: return
        if (!token.isBinderAlive) { stopSelf(lastStartId); return }
        lease = AIZivaSession(AIZivaRuntime.directory(this)).acquire()
        if (lease == null) { stopSelf(lastStartId); return }
        owner?.let { old -> death?.let { try { old.unlinkToDeath(it, 0) } catch (_: Exception) { } } }
        owner = token
        val recipient = IBinder.DeathRecipient {
            if (owner === token) { stopping.set(true); main.post { pending = null; stopSelf() } }
        }
        death = recipient
        try { token.linkToDeath(recipient, 0) } catch (_: Exception) {
            lease?.close(); lease = null; stopSelf(lastStartId); return
        }
        currentProject = intent.getStringExtra("project_directory").orEmpty()
        running = true; stopping.set(false)
        AIZivaRuntime.cancelFile(this).delete()
        state = AIZivaRuntime.read(this)
        state.put("request_id", intent.getStringExtra("request_id"))
        executor.execute { work(intent) }
    }

    private fun work(intent: Intent) {
        val action = intent.getStringExtra("action")
        val projectPath = intent.getStringExtra("project_directory")
        var finalStatus = "stopped"
        var finalMessage = "Ziva oprit"
        var logFile: File? = null
        val output = StringBuilder()
        var heartbeat: ScheduledFuture<*>? = null
        try {
            check(!cancelled()) { "Operație anulată." }
            AIMemoryGuard.ensure(this, if (action == "ziva_install") 512 else 768,
                if (action == "ziva_install") "instalarea Ziva" else "pornirea Ziva")
            heartbeat = timer.scheduleAtFixedRate({ synchronized(lock) {
                try { AIZivaRuntime.save(this, state) } catch (_: Exception) { }
            } }, 0, 2, TimeUnit.SECONDS)
            // A service may have been killed while PRoot tracees survived. Recover only
            // our recorded PID from this boot, with the exact process start time.
            if (AIZivaSession.bootId().isNotEmpty() && state.optString("boot_id") == AIZivaSession.bootId()) {
                val pid = state.optInt("guest_pid")
                val start = state.optString("guest_start")
                if (pid > 0 && start.isNotEmpty() && AIZivaSession.processStart(pid) == start) {
                    signalGuest(pid, 15); Thread.sleep(300)
                    if (AIZivaSession.processStart(pid) == start) signalGuest(pid, 9)
                }
            }
            for (previous in privateDirectory("sessions").listFiles().orEmpty()) {
                if (previous.name.matches(Regex("[a-f0-9-]{36}")) && !Files.isSymbolicLink(previous.toPath())) AILinuxRuntimeFiles.deleteTree(previous)
            }
            synchronized(lock) { state.remove("ui_port"); state.remove("guest_pid"); state.remove("guest_start"); AIZivaRuntime.save(this, state) }
            val runtime = AILinuxRuntime.core(this, ::cancelled)
            check(runtime.state().optBoolean("ready")) { "Runtime Linux indisponibil." }
            val release = intent.getStringExtra("release")?.let { AIZivaPackage.fromJson(JSONObject(it)) }
            val ziva = if (release == null) AIZivaPackage(runtime.root) else AIZivaPackage(runtime.root, release)
            version = ziva.version
            val godot = AIZivaGodot(runtime.root)
            val packages = AIPackageManager.manifest(this)
            if (action == "ziva_install") {
                update("installing", "Instalez componentele Debian din APK…")
                AIPackageManager.installDebian(this, runtime, packages, ::cancelled) { update("installing", it) }
                update("installing", "Extrag Node.js, Pi, Ziva și Godot din APK…")
                if (!AIPackageManager.piInstalled(runtime, packages)) {
                    AIPackageManager.installPi(this, runtime, packages, ::cancelled) { update("installing", it) }
                }
                AIPackageManager.installZiva(this, runtime, packages, ::cancelled) { update("installing", it) }
                check(!cancelled()) { "Operație anulată." }
                runtime.verify()
                finalStatus = "installed"
                finalMessage = "Ziva instalat · ${ziva.version}"
            } else {
                ziva.verify()
                godot.verify()
                AIPackageManager.ensureZivaDependencies(this, runtime, packages, ziva, ::cancelled) { update("starting", it) }
                val project = File(projectPath ?: error("Proiect absent.")).canonicalFile
                check(File(project, "project.godot").isFile && !project.path.contains(':')) { "Proiect Godot invalid." }
                val projectId = AIZivaRuntime.projectId(project)
                val data = privateDirectory("projects/$projectId")
                synchronized(lock) { state.put("project_id", projectId) }
                update("starting", "Pornesc editorul oficial Godot…")
                sessionNonce = java.util.UUID.randomUUID().toString()
                val identity = privateDirectory("sessions/$sessionNonce")
                File(identity, "owner").writeText("GODOT_AI_ZIVA_OWNER=$sessionNonce\n")
                val globalAgents = File(runtime.root, "root/.agents")
                check(!Files.isSymbolicLink(globalAgents.parentFile!!.toPath()) && !Files.isSymbolicLink(globalAgents.toPath()))
                check(globalAgents.isDirectory || globalAgents.mkdirs()) { "Directorul contextului Ziva nu poate fi creat." }
                val globalInstructions = File(globalAgents, "AGENTS.md")
                AIZivaProjectContext.refresh(project, identity, globalInstructions)
                val guestIdentity = File(runtime.root, "run/godot-ai-ziva")
                check(!Files.isSymbolicLink(File(runtime.root, "run").toPath()) && !Files.isSymbolicLink(guestIdentity.toPath()))
                check(guestIdentity.isDirectory || guestIdentity.mkdirs()) { "Directorul de identificare Ziva nu poate fi creat." }
                val binds = mutableListOf(
                    identity.absolutePath to "/run/godot-ai-ziva",
                    File(identity, "addons.json").absolutePath to AIZivaProjectContext.INVENTORY,
                    ziva.addon.absolutePath to "/workspace/addons/ziva_agent",
                    privateDirectory("projects/$projectId/local-share").absolutePath to "/root/.local/share",
                    privateDirectory("projects/$projectId/cache").absolutePath to "/root/.cache",
                    privateDirectory("projects/$projectId/config").absolutePath to "/root/.config",
                    privateDirectory("projects/$projectId/godot").absolutePath to "/workspace/.godot"
                )
                if (AIZivaProjectContext.canOverlay(identity))
                    binds += File(identity, "AGENTS.md").absolutePath to "/root/.agents/AGENTS.md"
                // Discard endpoint hints only; account/session history stays intact.
                val share = privateDirectory("projects/$projectId/local-share")
                share.walkTopDown().maxDepth(10).filter { it.isFile && it.name.matches(Regex("sidecar-[0-9]+-.*\\.port")) }.forEach { it.delete() }
                update("starting", "Pregătesc componentele Ziva…")
                ziva.seedRuntime(AIZivaProjectContext.userDirectory(share, project))
                logFile = File(data, "godot.log")
                guestPidFile = File(privateDirectory("projects/$projectId/cache"), "godot-ai-ziva.pid").also { it.delete() }
                child = runtime.startProcess(
                    listOf("/bin/sh", "-c", "printf '%s\\n' \"\$\$\" > /root/.cache/godot-ai-ziva.pid; exec \"\$@\"",
                        "godot-ai-ziva", godot.guestBinary, "--headless", "--editor", "--path", "/workspace"), project,
                    AIZivaSession.startupEnvironment(), binds)
                val reader = drain(child!!, output, logFile)
                try {
                    val deadline = System.nanoTime() + READY_TIMEOUT_MS * 1_000_000L
                    var port = 0
                    var tools = false
                    while (!cancelled() && child!!.isAlive && System.nanoTime() < deadline) {
                        synchronized(output) {
                            check(!AIZivaSession.officialExtensionFailed(output)) {
                                "Pluginul oficial Ziva nu s-a încărcat. Reia instalarea și verifică jurnalul sesiunii."
                            }
                        }
                        if (port == 0) {
                            val pid = try { guestPidFile?.readText()?.trim()?.toIntOrNull() } catch (_: Exception) { null }
                            if (pid != null && pid > 0) {
                                synchronized(lock) { state.put("guest_pid", pid).put("guest_start", AIZivaSession.processStart(pid)) }
                                port = ownedPort(share, pid)
                            }
                        }
                        if (port > 0 && !tools) tools = editorToolReady(port)
                        if (tools && uiReady(port)) break
                        Thread.sleep(500)
                    }
                    check(!cancelled()) { "Operație anulată." }
                    check(port > 0 && tools && child!!.isAlive && uiReady(port)) {
                        "Interfața Ziva nu a pornit în editorul separat. Verifică jurnalul privat al sesiunii."
                    }
                    synchronized(lock) { state.put("ui_port", port) }
                    update("running", "Editorul separat Ziva rulează · interfața este disponibilă")
                    var failures = 0
                    var lastContextRefresh = 0L
                    while (!cancelled() && !child!!.waitFor(2, TimeUnit.SECONDS)) {
                        if (System.nanoTime() - lastContextRefresh > 5_000_000_000L) {
                            // Metadata refresh never restarts an active agent or edits project files.
                            try {
                                AIZivaProjectContext.refresh(project, identity, globalInstructions)
                                synchronized(lock) { state.remove("addon_context_error") }
                            } catch (_: Exception) {
                                synchronized(lock) { state.put("addon_context_error", "Inventarul addonurilor nu s-a putut actualiza; verifică accesul la fișierele proiectului.") }
                            }
                            lastContextRefresh = System.nanoTime()
                        }
                        failures = if (uiReady(port)) 0 else failures + 1
                        check(failures < 30) { "Interfața Ziva nu mai răspunde. Repornește sesiunea." }
                    }
                    if (!cancelled()) error("Editorul Ziva s-a oprit (cod ${child!!.exitValue()}).")
                } finally {
                    terminate()
                    reader.join(2000)
                }
                finalMessage = "Ziva oprit · istoricul propriu este păstrat"
            }
        } catch (error: Exception) {
            finalStatus = if (cancelled()) "stopped" else "error"
            finalMessage = if (cancelled()) "Ziva oprit" else (error.message?.take(240) ?: "Ziva nu a pornit.")
        } finally {
            terminate()
            try {
                val log = logFile
                if (log != null && output.isNotEmpty()) log.writeText(output.toString())
            } catch (_: Exception) { }
            heartbeat?.cancel(false)
            if (sessionNonce.matches(Regex("[a-f0-9-]{36}"))) {
                try { AILinuxRuntimeFiles.deleteTree(privateDirectory("sessions/$sessionNonce")) } catch (_: Exception) { }
            }
            main.post {
                try { synchronized(lock) {
                    state.remove("ui_port"); state.remove("guest_pid"); state.remove("guest_start")
                    state.put("status", finalStatus).put("message", finalMessage)
                    AIZivaRuntime.save(this, state)
                } } catch (_: Exception) { /* Ownership must still be released if storage is full. */ }
                finally { try { lease?.close() } catch (_: Exception) { }; lease = null; running = false }
                val next = pending; pending = null
                if (next != null && !executor.isShutdown) launch(next)
                else { stopForeground(STOP_FOREGROUND_REMOVE); stopSelf(lastStartId) }
            }
        }
    }

    private fun privateDirectory(relative: String): File {
        var file = AIZivaRuntime.directory(this)
        for (part in relative.split('/')) {
            require(part.isNotEmpty() && part != "." && part != "..")
            file = File(file, part)
            check(!Files.isSymbolicLink(file.toPath())) { "Director Ziva privat nesigur." }
        }
        check(file.isDirectory || file.mkdirs()) { "Directorul privat Ziva nu poate fi creat." }
        return file
    }

    private fun drain(process: Process, output: StringBuilder, log: File?): Thread = Thread({
        var lastWrite = 0L
        try { process.inputStream.use { input ->
            val buffer = ByteArray(8192)
            while (true) {
                val read = input.read(buffer); if (read < 0) break
                synchronized(output) {
                    output.append(String(buffer, 0, read))
                    if (output.length > MAX_LOG) output.delete(0, output.length - MAX_LOG)
                    if (log != null && System.currentTimeMillis() - lastWrite > 1000) {
                        try { log.writeText(output.toString()); lastWrite = System.currentTimeMillis() } catch (_: Exception) { }
                    }
                }
            }
        } } catch (_: Exception) { }
    }, "ZivaEditorOutput").apply { isDaemon = true; start() }

    private fun post(port: Int, body: String): JSONObject? {
        val connection = URL("http://127.0.0.1:$port/api/mcp").openConnection() as HttpURLConnection
        return try {
            connection.connectTimeout = 400; connection.readTimeout = 3000
            connection.instanceFollowRedirects = false
            connection.requestMethod = "POST"; connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Accept", "application/json, text/event-stream")
            connection.outputStream.use { it.write(body.toByteArray()) }
            if (connection.responseCode != 200) return null
            val text = connection.inputStream.use { input ->
                val bytes = ByteArray(65536); var count = 0
                while (count < bytes.size) { val read = input.read(bytes, count, bytes.size - count); if (read < 0) break; count += read }
                String(bytes, 0, count)
            }
            val data = if (text.trimStart().startsWith("{")) text else text.lineSequence()
                .filter { it.startsWith("data:") }.map { it.removePrefix("data:").trimStart() }.joinToString("\n")
            if (data.isBlank()) null else JSONObject(data)
        } catch (_: Exception) { null } finally { connection.disconnect() }
    }

    /** Identifies the official endpoint; a random local HTTP server is not a Ziva editor. */
    private fun identity(port: Int): Boolean {
        val json = post(port, """{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"godot-ai-ziva","version":"1"}}}""") ?: return false
        val info = json.optJSONObject("result")?.optJSONObject("serverInfo") ?: return false
        return info.optString("name") == "ziva-godot" && info.optString("version") == version
    }

    private fun ownedPort(share: File, pid: Int): Int {
        // Upstream consumes its transient .port hint. Ownership is proved by a
        // unique per-session mount read through the public MCP file tool.
        // A different editor, including an orphan from this project, sees a
        // different /run/godot-ai-ziva mount and cannot match this nonce.
        for (port in (AIZivaSession.ownedPorts(share, pid) + (FIRST_PORT..LAST_PORT)).distinct()) {
            if (cancelled()) return 0
            if (!identity(port)) continue
            val body = JSONObject().put("jsonrpc", "2.0").put("id", 3).put("method", "tools/call")
                .put("params", JSONObject().put("name", "read").put("arguments", JSONObject()
                    .put("reasoning", "Read-only ownership check for the app-managed Ziva session.")
                    .put("file_path", AIZivaSession.OWNER_FILE).put("limit", 1)))
            if (AIZivaSession.ownerMatches(post(port, body.toString()), sessionNonce)) return port
        }
        return 0
    }

    /** A read-only editor tool call proves that the addon is running inside a real editor. */
    private fun editorToolReady(port: Int): Boolean {
        val json = post(port, """{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_project_info","arguments":{"reasoning":"Readiness check."}}}""") ?: return false
        val content = json.optJSONObject("result")?.optJSONArray("content") ?: return false
        return content.length() > 0 && content.optJSONObject(0)?.optString("text").orEmpty().isNotBlank()
    }

    private fun uiReady(port: Int): Boolean {
        val connection = URL("http://127.0.0.1:$port/").openConnection() as HttpURLConnection
        return try {
            connection.connectTimeout = 400; connection.readTimeout = 1200
            connection.instanceFollowRedirects = false
            connection.responseCode == 200 && connection.contentType.orEmpty().startsWith("text/html")
        } catch (_: Exception) { false } finally { connection.disconnect() }
    }

    private fun signalGuest(pid: Int?, signal: Int) {
        if (pid == null || pid <= 0) return
        try {
            val args = File("/proc/$pid/cmdline").readText().split('\u0000')
            // The PID comes from our private session mount. Verify the exact host
            // executable as well, so a reused PID can never target another app task.
            if (args.firstOrNull() == "/opt/godot-tools/godot/${AIZivaGodot.RELEASE.version}/godot" &&
                "--headless" in args && "--editor" in args) android.os.Process.sendSignal(pid, signal)
        } catch (_: Exception) { }
    }

    @Synchronized private fun terminate() {
        val process = child ?: return
        val pid = try { guestPidFile?.readText()?.trim()?.toIntOrNull() } catch (_: Exception) { null }
        try {
            // Stop the main tracee first. PRoot's --kill-on-exit then reaps its
            // sidecars; terminating only the tracer can leave a listening server.
            signalGuest(pid, 15)
            if (!process.waitFor(2, TimeUnit.SECONDS)) {
                signalGuest(pid, 9)
                process.destroy()
                if (!process.waitFor(2, TimeUnit.SECONDS)) process.destroyForcibly()
            }
        } catch (_: InterruptedException) {
            signalGuest(pid, 9)
            process.destroyForcibly()
            Thread.currentThread().interrupt()
        } finally {
            guestPidFile?.delete(); guestPidFile = null
            child = null
        }
    }
    override fun onTimeout(startId: Int, fgsType: Int) { stopping.set(true); terminate(); stopSelf(startId) }
    override fun onTaskRemoved(rootIntent: Intent?) { pending = null; stopping.set(true); stopSelf(); super.onTaskRemoved(rootIntent) }
    override fun onDestroy() {
        pending = null; stopping.set(true); terminate()
        owner?.let { token -> death?.let { try { token.unlinkToDeath(it, 0) } catch (_: Exception) { } } }
        owner = null
        // Let the worker finish its state write and release the kernel lease.
        executor.shutdown(); timer.shutdownNow()
        super.onDestroy()
    }
}
