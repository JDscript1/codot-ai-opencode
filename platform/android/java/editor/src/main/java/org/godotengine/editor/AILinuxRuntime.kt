package org.godotengine.editor

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.os.Build
import android.os.IBinder
import android.os.Process
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Native bridge for a persistent, app-owned Linux filesystem. Termux is not consulted. */
object AILinuxRuntime {
    private var context: Context? = null
    fun initialize(activity: Activity) { context = activity.applicationContext; AIZivaWindow.register(activity) }
    internal fun directory(context: Context) = File(context.noBackupFilesDir, "ai-linux")
    internal fun jobFile(context: Context, id: String) = File(directory(context), "jobs/$id.json")
    internal fun core(context: Context, cancel: () -> Boolean = { false }, log: (String) -> Unit = {}) =
        AILinuxRuntimeFiles(directory(context), File(context.applicationInfo.nativeLibraryDir), { context.assets.open(it) }, cancel, log).apply {
            val network = context.getSystemService(ConnectivityManager::class.java)
            synchronizeDns(network.getLinkProperties(network.activeNetwork)?.dnsServers?.mapNotNull { it.hostAddress }.orEmpty())
        }
    internal fun preparePackageNetwork(context: Context, runtime: AILinuxRuntimeFiles) {
        val connectivity = context.getSystemService(ConnectivityManager::class.java)
        val network = connectivity.activeNetwork
        val addresses = if (network != null) network.getAllByName("deb.debian.org").toList()
            else java.net.InetAddress.getAllByName("deb.debian.org").toList()
        val ipv4 = addresses.filterIsInstance<java.net.Inet4Address>()
        runtime.synchronizePackageHosts((if (ipv4.isNotEmpty()) ipv4 else addresses).mapNotNull { it.hostAddress })
    }
    private fun failure(message: String, code: String = "runtime_error") = JSONObject().put("ok", false).put("error", message).put("code", code)

    @JvmStatic @Synchronized fun command(action: String, text: String): String {
        val current = context ?: return failure("Editorul Android nu este activ.").toString()
        if (Build.VERSION.SDK_INT < 29 || !Build.SUPPORTED_ABIS.contains("arm64-v8a")) return failure("Runtime Linux necesită Android 10+ ARM64.", "unsupported_platform").toString()
        return try {
            val arguments = JSONObject(text)
            if (action.startsWith("ziva_")) return AIZivaRuntime.command(current, action, arguments).toString()
            if (action.startsWith("opencode_")) return AIOpenCodeRuntime.command(current, action, arguments).toString()
            when (action) {
                "status" -> {
                    val result = core(current).state().put("ok", true).put("supported", true)
                    val packaged = try { current.assets.open("godot_ai/linux/package.json").close(); true } catch (_: Exception) { false }
                    result.put("packaged", result.optBoolean("packaged") && packaged)
                    result.put("active_job", active(current))
                    result.toString()
                }
                "poll", "cancel" -> {
                    val id = arguments.getString("id"); check(validId(id)) { "ID sarcină invalid." }
                    val file = jobFile(current, id); check(file.isFile) { "Sarcina nu există." }
                    if (action == "cancel") File(file.parentFile, "$id.cancel").writeText("cancel")
                    val job = AILinuxRuntimeFiles.readJson(file)
                    recoverStale(job, file)
                    job.put("ok", true).toString()
                }
                "prepare", "install", "verify", "tool_install", "execute", "uninstall" -> {
                    if (action in listOf("install", "tool_install", "uninstall")) check(!AIZivaRuntime.isBusy(current)) { "Oprește Ziva înainte de modificarea runtime-ului Linux." }
                    val active = active(current)
                    if (action == "prepare" && active.isNotEmpty()) return JSONObject().put("ok", true).put("id", active).put("status", "running").toString()
                    check(active.isEmpty()) { "O sarcină Linux este deja în lucru." }
                    if (action == "tool_install") check(AILinuxRuntimeFiles.TOOL_PACKAGES.containsKey(arguments.getString("tool"))) { "Utilitar necunoscut." }
                    if (action == "execute") {
                        val command = arguments.getString("command")
                        check(command.isNotBlank() && command.length <= 16000 && !command.contains('\u0000')) { "Comandă invalidă." }
                        val project = File(arguments.getString("project_directory"))
                        check(project.isAbsolute && File(project, "project.godot").isFile) { "Deschide un proiect Godot." }
                    }
                    trimJobs(current)
                    val id = UUID.randomUUID().toString()
                    val job = JSONObject().put("id", id).put("kind", action).put("status", "queued").put("arguments", arguments)
                        .put("created_at", System.currentTimeMillis()).put("heartbeat", System.currentTimeMillis()).put("output", "")
                    AILinuxRuntimeFiles.writeJson(jobFile(current, id), job)
                    try { current.startForegroundService(Intent(current, AILinuxRuntimeService::class.java).putExtra("job_id", id)) }
                    catch (error: Exception) {
                        job.put("status", "failed").put("error", "Serviciul Linux nu a pornit: ${error.javaClass.simpleName}")
                        AILinuxRuntimeFiles.writeJson(jobFile(current, id), job); throw error
                    }
                    JSONObject().put("ok", true).put("id", id).put("status", "queued").toString()
                }
                else -> failure("Operație Linux necunoscută.").toString()
            }
        } catch (error: Exception) { failure(error.message?.take(2000) ?: error.javaClass.simpleName).toString() }
    }

    private fun trimJobs(context: Context) {
        val jobs = File(directory(context), "jobs").listFiles()?.filter { it.extension == "json" }?.sortedByDescending { it.lastModified() }.orEmpty()
        for (file in jobs.drop(20)) {
            val job = AILinuxRuntimeFiles.readJson(file)
            if (job.optString("status") !in listOf("queued", "running")) {
                file.delete(); File(file.parentFile, file.nameWithoutExtension + ".cancel").delete()
            }
        }
    }
    private fun validId(id: String) = id.matches(Regex("[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}"))
    private fun active(context: Context): String {
        val files = File(directory(context), "jobs").listFiles()?.filter { it.extension == "json" }.orEmpty()
        for (file in files) {
            val job = AILinuxRuntimeFiles.readJson(file)
            recoverStale(job, file)
            if (job.optString("status") in listOf("queued", "running")) return job.optString("id")
        }
        return ""
    }
    private fun recoverStale(job: JSONObject, file: File) {
        if (job.optString("status") in listOf("queued", "running") && System.currentTimeMillis() - job.optLong("heartbeat") > 45_000) {
            job.put("status", "interrupted").put("error", "Procesul Linux s-a întrerupt. Verifică rezultatele înainte de reluare.")
            AILinuxRuntimeFiles.writeJson(file, job)
        }
    }
}

/** Long operations are visible in Android and keep running when the editor loses focus. */
class AILinuxRuntimeService : Service() {
    private val cancelled = AtomicBoolean(false)
    private val executor = Executors.newSingleThreadExecutor()
    private val heartbeat = Executors.newSingleThreadScheduledExecutor()
    @Volatile private var running = false
    private var activeId = ""
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("godot_ai_linux", "Runtime Linux", NotificationManager.IMPORTANCE_LOW))
        startForeground(7342, notification("Pregătesc runtime-ul Linux…"))
    }
    private fun notification(text: String): Notification {
        val cancel = Intent(this, AILinuxRuntimeService::class.java).putExtra("cancel", true).putExtra("job_id", activeId)
        val pending = PendingIntent.getService(this, 7342, cancel, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, "godot_ai_linux").setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle("Godot · Linux").setContentText(text.take(120)).setOngoing(true)
            .addAction(Notification.Action.Builder(null, "Oprește", pending).build()).build()
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.getBooleanExtra("cancel", false) == true) {
            if (intent.getStringExtra("job_id") == activeId) cancelled.set(true)
            if (!running) stopSelf(startId)
            return START_NOT_STICKY
        }
        val id = intent?.getStringExtra("job_id") ?: run { stopSelf(startId); return START_NOT_STICKY }
        if (!id.matches(Regex("[a-f0-9-]{36}")) || running) return START_NOT_STICKY
        activeId = id; running = true; cancelled.set(false)
        getSystemService(NotificationManager::class.java).notify(7342, notification("Sarcină Linux în lucru"))
        executor.execute { runJob(id, startId) }
        return START_NOT_STICKY
    }
    private fun runJob(id: String, startId: Int) {
        val file = AILinuxRuntime.jobFile(this, id)
        val job = AILinuxRuntimeFiles.readJson(file)
        val lock = Any(); val output = StringBuilder(); var lastFlush = 0L
        fun save() { synchronized(lock) {
            job.put("output", output.toString()).put("heartbeat", System.currentTimeMillis())
            AILinuxRuntimeFiles.writeJson(file, job)
        } }
        val timer = heartbeat.scheduleAtFixedRate({ try { save() } catch (_: Exception) {} }, 0, 2, TimeUnit.SECONDS)
        val cancelFile = File(file.parentFile, "$id.cancel")
        val runtime = AILinuxRuntime.core(this, { cancelled.get() || cancelFile.exists() }) { text -> synchronized(lock) {
            output.append(text)
            if (output.length > AILinuxRuntimeFiles.MAX_LOG) { output.delete(0, output.length - AILinuxRuntimeFiles.MAX_LOG); job.put("truncated", true) }
            if (System.currentTimeMillis() - lastFlush > 300) { lastFlush = System.currentTimeMillis(); save() }
        } }
        try {
            check(job.optString("id") == id && job.optString("status") == "queued") { "Sarcină Linux invalidă." }
            synchronized(lock) { job.put("status", "running").put("pid", Process.myPid()); save() }
            val args = job.getJSONObject("arguments")
            val result = when (job.getString("kind")) {
                "prepare", "install" -> {
                    val network = getSystemService(ConnectivityManager::class.java)
                    val dns = network.getLinkProperties(network.activeNetwork)?.dnsServers?.mapNotNull { it.hostAddress }.orEmpty()
                    if (job.getString("kind") == "prepare" && runtime.state().optBoolean("installed")) runtime.verify()
                    else { runtime.install(dns); runtime.state() }
                }
                "verify" -> runtime.verify()
                "tool_install" -> { AILinuxRuntime.preparePackageNetwork(this, runtime); runtime.installTool(args.getString("tool")) }
                "execute" -> runtime.execute(args.getString("command"), File(args.getString("project_directory")), args.optInt("seconds", 120))
                "uninstall" -> { runtime.uninstall(); runtime.state() }
                else -> error("Operație Linux necunoscută.")
            }
            synchronized(lock) { job.put("status", "completed").put("result", result) }
        } catch (error: Exception) {
            synchronized(lock) { job.put("status", if (cancelled.get() || cancelFile.exists()) "cancelled" else "failed")
                .put("error", error.message?.take(3000) ?: error.javaClass.simpleName) }
        } finally {
            timer.cancel(false)
            synchronized(lock) { job.remove("arguments"); save() }
            cancelFile.delete()
            running = false
            stopForeground(STOP_FOREGROUND_REMOVE); stopSelf(startId)
        }
    }
    override fun onDestroy() { cancelled.set(true); executor.shutdown(); heartbeat.shutdownNow(); super.onDestroy() }
}
