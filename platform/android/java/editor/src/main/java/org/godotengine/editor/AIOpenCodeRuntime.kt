package org.godotengine.editor

import android.app.Activity
import android.content.Context
import android.os.Build
import android.os.ParcelFileDescriptor
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream
import java.lang.ref.WeakReference
import java.util.ArrayDeque
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * OpenCode is an optional agent runtime installed by npm inside the app-owned
 * Debian filesystem. The direct-provider assistant never depends on it.
 *
 * Node/npm and the ~250 MB CLI stay in private app storage; they are not part of
 * the APK. The TUI runs behind a native PTY because Android pipes have no
 * controlling terminal. Project files are mounted at /workspace by PRoot.
 */
object AIOpenCodeRuntime {
    const val VERSION = "2.2.5"
    private const val CLI_PATH = "root/.local/node_modules/@opencode/cli/bin/opencode.exe"
    private const val SHIM_PATH = "root/.local/node_modules/.bin/opencode"
    private const val CONFIG_PATH = "root/.config/opencode/opencode.json"
    private const val SCROLLBACK_LIMIT = 512 * 1024
    private const val TAIL_LIMIT = 12000
    private const val MIN_FREE_BYTES = 900L * 1024 * 1024
    private const val INSTALL_TIMEOUT_SECONDS = 2400

    private var host = WeakReference<Activity>(null)
    private val lock = Any()

    @Volatile private var status = "idle"
    @Volatile private var message = "OpenCode nu este instalat."
    @Volatile private var progress = 0

    private var worker: Thread? = null
    private val cancelInstall = AtomicBoolean(false)
    @Volatile private var process: Process? = null
    @Volatile private var runId = 0
    @Volatile private var input: OutputStream? = null
    @Volatile private var control: FileOutputStream? = null
    @Volatile private var writer: java.util.concurrent.ExecutorService? = null
    private var fifo: File? = null
    private var controlDescriptor: ParcelFileDescriptor? = null
    @Volatile private var projectPath = ""
    private var exitWatcher: Thread? = null
    private var reader: Thread? = null
    @Volatile private var mcpPort = 0
    private val scrollback = ArrayDeque<ByteArray>()
    private var scrollbackBytes = 0
    private val tail = StringBuilder()

    fun initialize(activity: Activity) {
        host = WeakReference(activity)
        AIOpenCodeWindow.register(activity)
    }

    fun release(activity: Activity) {
        if (host.get() !== activity) return
        AIOpenCodeWindow.release(activity)
        stop(activity)
    }

    fun directory(context: Context): File = File(context.noBackupFilesDir, "opencode").apply { mkdirs() }

    private fun failure(text: String, code: String = "opencode_error") =
        JSONObject().put("ok", false).put("error", text).put("code", code)

    private fun installed(context: Context): Boolean {
        val root = File(AILinuxRuntime.directory(context), "rootfs")
        val binary = File(root, CLI_PATH)
        return binary.isFile && binary.length() > 1_000_000 && File(root, SHIM_PATH).exists()
    }

    private fun guestVersion(context: Context): String {
        val manifest = File(AILinuxRuntime.directory(context), "rootfs/root/.local/node_modules/@opencode/cli/package.json")
        return try { JSONObject(manifest.readText()).optString("version") } catch (_: Exception) { "" }
    }

    fun status(context: Context, requested: String = ""): JSONObject {
        val runtime = AILinuxRuntime.core(context)
        val running = process?.isAlive == true
        val available = installed(context)
        val version = guestVersion(context)
        if (!running && status == "idle") {
            message = if (available) "OpenCode ${version.ifEmpty { VERSION }} este instalat."
            else "OpenCode nu este instalat."
        }
        val sameProject = requested.isEmpty() || projectPath.isEmpty() ||
            (try { File(requested).canonicalPath == File(projectPath).canonicalPath } catch (_: Exception) { false })
        val current = JSONObject()
            .put("ok", true)
            .put("supported", Build.SUPPORTED_ABIS.contains("arm64-v8a") && Build.VERSION.SDK_INT >= 29)
            .put("enabled", true)
            .put("installed", available)
            .put("version", version)
            .put("linux_ready", runtime.state().optBoolean("ready"))
            .put("running", running)
            .put("run_id", if (running) runId else 0)
            .put("status", if (running) "running" else status)
            .put("message", message)
            .put("progress", progress)
            .put("project", projectPath)
            .put("same_project", if (running) sameProject else true)
            .put("mcp_port", mcpPort)
            .put("free_bytes", context.noBackupFilesDir.usableSpace)
            .put("min_free_bytes", MIN_FREE_BYTES)
        val recent = synchronized(lock) { tail.toString().trim() }
        if (recent.isNotEmpty()) current.put("tail", recent.takeLast(1200))
        return current
    }

    fun command(context: Context, action: String, arguments: JSONObject): JSONObject {
        return when (action) {
            "opencode_status" -> status(context, arguments.optString("project_directory"))
            "opencode_install" -> install(context)
            "opencode_cancel" -> cancelInstall(context)
            "opencode_start" -> start(context, arguments)
            "opencode_stop" -> stopCommand(context)
            "opencode_embed" -> embed(context, arguments)
            "opencode_write" -> {
                val data = arguments.optString("data")
                write(android.util.Base64.decode(data, android.util.Base64.NO_WRAP))
                JSONObject().put("ok", true)
            }
            "opencode_resize" -> {
                resize(arguments.optInt("columns", 100), arguments.optInt("rows", 30))
                JSONObject().put("ok", true)
            }
            else -> failure("Operație OpenCode necunoscută.")
        }
    }

    private fun cancelInstall(context: Context): JSONObject {
        cancelInstall.set(true)
        message = "Anulez instalarea OpenCode…"
        return JSONObject().put("ok", true).put("cancelling", true)
    }

    private fun install(context: Context): JSONObject {
        if (worker?.isAlive == true) return JSONObject().put("ok", true).put("started", true).put("running", true)
        if (process?.isAlive == true) return failure("Oprește OpenCode înainte de reinstalare.")
        val runtime = AILinuxRuntime.core(context)
        if (!runtime.state().optBoolean("ready")) return failure("Runtime-ul Linux se pregătește. Reîncearcă după instalare.", "linux_not_ready")
        if (AIZivaRuntime.isBusy(context)) return failure("Oprește Ziva înainte de instalarea OpenCode.", "ziva_busy")
        if (!Build.SUPPORTED_ABIS.contains("arm64-v8a") || Build.VERSION.SDK_INT < 29) return failure("OpenCode necesită Android 10+ ARM64.", "unsupported_platform")
        if (context.noBackupFilesDir.usableSpace < MIN_FREE_BYTES) {
            return failure("Spațiu insuficient: sunt necesari aproximativ 900 MB liberi pentru Node.js și OpenCode.", "no_space")
        }
        cancelInstall.set(false)
        status = "installing"
        progress = 0
        message = "Pregătesc instalarea OpenCode…"
        worker = Thread({ installWorker(context) }, "GodotOpenCodeInstall").apply { isDaemon = true; start() }
        return JSONObject().put("ok", true).put("started", true)
    }

    private fun installWorker(context: Context) {
        fun stage(value: Int, text: String) {
            progress = value
            message = text
        }
        try {
            val runtime = AILinuxRuntime.core(context, { cancelInstall.get() }, { chunk -> installProgress(chunk) })
            check(runtime.state().optBoolean("ready")) { "Runtime-ul Linux nu este pregătit." }
            val present = runtime.state().optJSONObject("tools") ?: JSONObject()
            val missing = listOf("node", "git", "ripgrep").filter { !present.has(it) }
            if (missing.isNotEmpty()) AILinuxRuntime.preparePackageNetwork(context, runtime)
            for ((index, tool) in missing.withIndex()) {
                stage(5 + index * 14, "Instalez ${tool} în runtime-ul Linux…")
                runtime.installTool(tool)
            }
            stage(55, "Instalez OpenCode $VERSION (~250 MB). Poate dura câteva minute…")
            val result = runtime.launch(listOf("/usr/bin/npm", "install", "--prefix", "/root/.local",
                "--no-audit", "--no-fund", "--loglevel=error", "@opencode/cli@$VERSION"), null, INSTALL_TIMEOUT_SECONDS)
            check(result.getInt("exit_code") == 0) { "npm install a eșuat: " + result.optString("output").takeLast(800) }
            check(installed(context)) { "Binarele OpenCode nu au fost găsite după instalare." }
            val version = guestVersion(context)
            stage(95, "Verific instalarea OpenCode ${version.ifEmpty { VERSION }}…")
            val probe = runtime.launch(listOf("/root/.local/node_modules/.bin/opencode", "--version"), null, 180)
            check(probe.getInt("exit_code") == 0) { "OpenCode nu a răspuns: " + probe.optString("output").takeLast(800) }
            status = "idle"
            progress = 100
            message = "OpenCode ${version.ifEmpty { VERSION }} este instalat."
            writeState(context)
        } catch (error: Exception) {
            if (cancelInstall.get()) {
                status = "idle"
                message = "Instalarea OpenCode a fost anulată."
            } else {
                status = "error"
                message = error.message?.take(1200) ?: error.javaClass.simpleName
            }
            progress = 0
        } finally {
            worker = null
            cancelInstall.set(false)
            AIOpenCodeWindow.refreshStatus()
        }
    }

    private fun installProgress(chunk: String) {
        val lines = chunk.lines().map { it.trim() }.filter { it.isNotEmpty() }
        if (lines.isEmpty()) return
        synchronized(lock) {
            tail.append(chunk)
            if (tail.length > TAIL_LIMIT) tail.delete(0, tail.length - TAIL_LIMIT)
        }
        message = lines.last().take(300)
    }

    private fun writeState(context: Context) {
        try {
            AILinuxRuntimeFiles.writeJson(File(directory(context), "state.json"), JSONObject()
                .put("status", status).put("message", message).put("progress", progress)
                .put("version", guestVersion(context)).put("updated_at", System.currentTimeMillis()))
        } catch (_: Exception) {
        }
    }

    private fun readConfig(primary: File, alternate: File): JSONObject? {
        val source = when {
            primary.isFile -> primary
            alternate.isFile -> alternate
            else -> null
        }
        if (source == null) return JSONObject()
        return try { JSONObject(stripJsonComments(source.readText())) } catch (_: Exception) { null }
    }

    /** Minimal JSONC comment and trailing-comma stripper; strings are preserved verbatim. */
    private fun stripJsonComments(text: String): String {
        val output = StringBuilder(text.length)
        var index = 0
        var string = false
        while (index < text.length) {
            val current = text[index]
            if (string) {
                output.append(current)
                if (current == '\\' && index + 1 < text.length) {
                    output.append(text[index + 1]); index += 2; continue
                }
                if (current == '"') string = false
                index++; continue
            }
            if (current == '"') { string = true; output.append(current); index++; continue }
            if (current == '/' && index + 1 < text.length && text[index + 1] == '/') {
                while (index < text.length && text[index] != '\n') index++
                continue
            }
            if (current == '/' && index + 1 < text.length && text[index + 1] == '*') {
                index += 2
                while (index + 1 < text.length && !(text[index] == '*' && text[index + 1] == '/')) index++
                index = minOf(text.length, index + 2)
                continue
            }
            if (current == '}' || current == ']') {
                var trim = output.length
                while (trim > 0 && output[trim - 1].isWhitespace()) trim--
                if (trim > 0 && output[trim - 1] == ',') output.deleteCharAt(trim - 1)
            }
            output.append(current)
            index++
        }
        return output.toString()
    }

    private fun writeConfig(context: Context, port: Int, token: String) {
        val root = AILinuxRuntime.core(context).root
        val primary = File(root, CONFIG_PATH)
        val alternate = File(root, "root/.config/opencode/opencode.jsonc")
        val file = when {
            primary.isFile -> primary
            alternate.isFile -> alternate
            else -> primary
        }
        val config = readConfig(file, if (file == primary) alternate else primary)
            ?: error("Configurația OpenCode existentă nu poate fi citită. Corectează opencode.jsonc și reîncearcă.")
        config.put("\$schema", "https://opencode.ai/config.json")
        val mcp = config.optJSONObject("mcp") ?: JSONObject().also { config.put("mcp", it) }
        val servers = mcp.optJSONObject("servers") ?: JSONObject().also { mcp.put("servers", it) }
        servers.put("godot", JSONObject()
            .put("type", "remote")
            .put("url", "http://127.0.0.1:$port/mcp")
            .put("oauth", false)
            .put("codemode", false)
            .put("headers", JSONObject().put("Authorization", "Bearer $token")))
        val managed = setOf("read", "edit", "shell", "godot_search", "godot_describe", "godot_call")
        val permissions = JSONArray()
        config.optJSONArray("permissions")?.let { previous ->
            for (index in 0 until previous.length()) {
                val rule = previous.optJSONObject(index) ?: continue
                if (rule.optString("action") !in managed) permissions.put(rule)
            }
        }
        permissions.put(JSONObject().put("action", "read").put("resource", "*").put("effect", "allow"))
        permissions.put(JSONObject().put("action", "edit").put("resource", "*").put("effect", "ask"))
        permissions.put(JSONObject().put("action", "shell").put("resource", "*").put("effect", "ask"))
        permissions.put(JSONObject().put("action", "godot_search").put("resource", "*").put("effect", "allow"))
        permissions.put(JSONObject().put("action", "godot_describe").put("resource", "*").put("effect", "allow"))
        permissions.put(JSONObject().put("action", "godot_call").put("resource", "*").put("effect", "ask"))
        config.put("permissions", permissions)
        check(file.parentFile?.isDirectory == true || file.parentFile?.mkdirs() == true) { "Configurația OpenCode nu poate fi scrisă." }
        file.writeText(config.toString(2))
        file.setReadable(false, false); file.setReadable(true, true)
        file.setWritable(false, false); file.setWritable(true, true)
    }

    private fun start(context: Context, arguments: JSONObject): JSONObject {
        if (process?.isAlive == true) {
            return JSONObject().put("ok", true).put("running", true).put("already", true)
                .put("run_id", runId).put("mcp_port", mcpPort)
        }
        if (!installed(context)) return failure("OpenCode nu este instalat.", "not_installed")
        val runtime = AILinuxRuntime.core(context)
        if (!runtime.state().optBoolean("ready")) return failure("Runtime-ul Linux nu este pregătit.", "linux_not_ready")
        val project = File(arguments.optString("project_directory"))
        check(project.isAbsolute && File(project, "project.godot").isFile && !project.path.contains(':')) { "Proiect Godot invalid." }
        val port = arguments.optInt("mcp_port", 0)
        val token = arguments.optString("mcp_token")
        check(port in 1..65535) { "Portul serverului MCP este invalid." }
        check(token.length >= 32 && token.matches(Regex("[A-Za-z0-9_-]+"))) { "Tokenul serverului MCP este invalid." }
        writeConfig(context, port, token)

        val dir = directory(context)
        val controlFile = File(dir, "pty.fifo")
        if (controlFile.exists() && !controlFile.delete()) error("Canalul terminalului nu poate fi recreat.")
        try {
            android.system.Os.mkfifo(controlFile.path, 384)
        } catch (failure: Exception) {
            error("Canalul terminalului nu poate fi creat: " + failure.message)
        }
        val native = File(context.applicationInfo.nativeLibraryDir, "libai_pty.so")
        check(native.isFile && native.canExecute()) { "Terminalul nativ lipsește din instalare." }
        val command = mutableListOf(native.absolutePath, "100", "30", controlFile.absolutePath, "--")
        command.addAll(runtime.prootArguments(listOf("/root/.local/node_modules/.bin/opencode", "--standalone", "/workspace"), project))
        val builder = ProcessBuilder(command).redirectErrorStream(true)
        builder.environment().clear()
        builder.environment().putAll(runtime.processEnvironment(mapOf("TERM" to "xterm-256color", "COLORTERM" to "truecolor")))
        synchronized(lock) {
            scrollback.clear(); scrollbackBytes = 0; tail.setLength(0)
        }
        val child = builder.start()
        @Suppress("DEPRECATION")
        val descriptor = try {
            ParcelFileDescriptor.open(controlFile, ParcelFileDescriptor.MODE_READ_WRITE)
        } catch (error: Exception) {
            child.destroy()
            controlFile.delete()
            throw error
        }
        synchronized(lock) {
            process = child
            runId += 1
            projectPath = project.canonicalPath
            mcpPort = port
            status = "running"
            progress = 100
            message = "OpenCode rulează pe proiectul curent."
            input = child.outputStream
            controlDescriptor = descriptor
            control = FileOutputStream(descriptor.fileDescriptor)
            fifo = controlFile
            writer = Executors.newSingleThreadExecutor { runnable ->
                Thread(runnable, "GodotOpenCodeInput").apply { isDaemon = true }
            }
            startReader(child)
            startWatcher(context, child)
        }
        AIOpenCodeWindow.refreshStatus()
        return JSONObject().put("ok", true).put("running", true).put("run_id", runId)
            .put("mcp_port", port).put("version", guestVersion(context))
    }

    private fun startReader(child: Process) {
        reader = Thread({
            val buffer = ByteArray(8192)
            try {
                child.inputStream.use { stream ->
                    while (true) {
                        val count = stream.read(buffer)
                        if (count < 0) break
                        if (count == 0) continue
                        onOutput(buffer.copyOf(count))
                    }
                }
            } catch (_: Exception) {
                // The stream closes when the PTY helper stops.
            }
        }, "GodotOpenCodeOutput").apply { isDaemon = true; start() }
    }

    private fun startWatcher(context: Context, child: Process) {
        exitWatcher = Thread({
            val code = try { child.waitFor() } catch (_: Exception) { -1 }
            synchronized(lock) {
                if (process !== child) return@synchronized
                process = null
                projectPath = ""
                mcpPort = 0
                try { input?.close() } catch (_: Exception) { }
                try { control?.close() } catch (_: Exception) { }
                try { controlDescriptor?.close() } catch (_: Exception) { }
                input = null
                control = null
                controlDescriptor = null
                writer?.shutdownNow()
                writer = null
                fifo?.delete()
                fifo = null
                if (status == "stopping") {
                    status = "idle"
                    message = "OpenCode este oprit."
                } else {
                    status = if (code == 0) "idle" else "error"
                    message = if (code == 0) "Sesiunea OpenCode s-a închis."
                    else "OpenCode s-a închis cu codul $code. Verifică terminalul."
                }
                writeState(context)
            }
            AIOpenCodeWindow.refreshStatus()
        }, "GodotOpenCodeWatch").apply { isDaemon = true; start() }
    }

    private fun stopCommand(context: Context): JSONObject {
        return if (process?.isAlive == true) {
            status = "stopping"
            message = "Închid OpenCode…"
            try {
                control?.write("Q\n".toByteArray()); control?.flush()
            } catch (_: Exception) { }
            Thread({
                val child = process ?: return@Thread
                child.destroy()
                try {
                    if (!child.waitFor(4, TimeUnit.SECONDS)) child.destroyForcibly()
                } catch (_: Exception) {
                    child.destroyForcibly()
                }
            }, "GodotOpenCodeStop").apply { isDaemon = true; start() }
            JSONObject().put("ok", true).put("stopping", true)
        } else {
            JSONObject().put("ok", true).put("running", false)
        }
    }

    fun stop(context: Context) {
        stopCommand(context)
    }

    private fun embed(context: Context, arguments: JSONObject): JSONObject {
        if (!arguments.optBoolean("visible")) {
            AIOpenCodeWindow.hide()
            return JSONObject().put("ok", true).put("visible", false)
        }
        if (process?.isAlive != true) return failure("OpenCode nu rulează.", "not_running")
        val bounds = arguments.getJSONArray("bounds")
        require(bounds.length() == 4) { "Încadrare invalidă." }
        AIOpenCodeWindow.embed(DoubleArray(4) { bounds.getDouble(it) })
        return JSONObject().put("ok", true).put("visible", true)
    }

    fun write(data: ByteArray) {
        if (data.isEmpty()) return
        val executor = writer ?: return
        try {
            executor.execute {
                try {
                    input?.write(data)
                    input?.flush()
                } catch (_: Exception) {
                }
            }
        } catch (_: Exception) {
        }
    }

    fun resize(columns: Int, rows: Int) {
        val stream = control ?: return
        val width = columns.coerceIn(20, 400)
        val height = rows.coerceIn(5, 200)
        try {
            stream.write("R $width $height\n".toByteArray())
            stream.flush()
        } catch (_: Exception) {
        }
    }

    private fun onOutput(chunk: ByteArray) {
        synchronized(lock) {
            scrollback.addLast(chunk)
            scrollbackBytes += chunk.size
            while (scrollbackBytes > SCROLLBACK_LIMIT && scrollback.size > 1) {
                scrollbackBytes -= scrollback.removeFirst().size
            }
            tail.append(stripAnsi(String(chunk, Charsets.UTF_8)))
            if (tail.length > TAIL_LIMIT) tail.delete(0, tail.length - TAIL_LIMIT)
        }
        AIOpenCodeWindow.push(chunk)
    }

    fun snapshot(): ByteArray = synchronized(lock) {
        val output = ByteArrayOutputStream()
        for (chunk in scrollback) output.write(chunk)
        output.toByteArray()
    }

    fun tail(): String = synchronized(lock) { stripAnsi(tail.toString()) }

    private fun stripAnsi(text: String): String = text
        .replace(Regex("\\u001B\\][^\\u0007\\u001B]*(?:\\u0007|\\u001B\\\\)"), "")
        .replace(Regex("\\u001B\\[[0-9;?]*[ -/]*[@-~]"), "")
        .replace(Regex("\\u001B[()][A-Za-z0-9]"), "")
        .replace(Regex("[\\u0000-\\u0008\\u000B-\\u001F]"), "")
}

