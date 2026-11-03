package org.godotengine.editor

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Binder
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import org.json.JSONObject
import java.io.File
import java.lang.ref.WeakReference
import java.security.MessageDigest
import java.util.UUID
import java.util.WeakHashMap

/** Independent lifecycle. The assistant panel is not involved in Ziva ownership or setup. */
object AIZivaRuntime {
    private var host = WeakReference<Activity>(null)
    private val owners = WeakHashMap<Activity, String>()
    private val owner = Binder()
    private val handler = Handler(Looper.getMainLooper())
    private var scheduled = false
    private var project = ""
    private var attempts = 0
    @Volatile private var pending = 0L
    private var prepareJob = ""
    private var prepareAttempts = 0
    internal fun directory(context: Context) = File(context.noBackupFilesDir, "ai-ziva").apply { mkdirs() }
    internal fun stateFile(context: Context) = File(directory(context), "state.json")
    internal fun cancelFile(context: Context) = File(directory(context), "cancel")
    internal fun read(context: Context) = AILinuxRuntimeFiles.readJson(stateFile(context))
    internal fun save(context: Context, state: JSONObject) {
        state.put("heartbeat", System.currentTimeMillis()).put("boot_id", AIZivaSession.bootId())
        AILinuxRuntimeFiles.writeJson(stateFile(context), state)
    }
    internal fun projectId(project: File): String = MessageDigest.getInstance("SHA-256").digest(project.canonicalPath.toByteArray())
        .joinToString("") { "%02x".format(it.toInt() and 255) }.take(24)

    @Synchronized fun register(activity: Activity) { host = WeakReference(activity) }
    @Synchronized fun resume(activity: Activity) {
        register(activity)
        if (owners.containsKey(activity)) { attempts = 0; schedule() }
    }
    @Synchronized fun release(activity: Activity) {
        owners.remove(activity)
        handler.postDelayed({ synchronized(this) {
            if (owners.isEmpty()) {
                project = ""; pending = 0
                try { stop(activity.applicationContext) } catch (_: Exception) { }
            } else schedule()
        } }, 1200)
    }
    private fun stop(context: Context) {
        AIZivaWindow.hide()
        if (!isBusy(context)) return
        // A closing project manager must never stop a newer editor's session.
        val extras = Bundle().apply { putBinder("owner", owner) }
        context.startService(Intent(context, AIZivaService::class.java).putExtra("action", "ziva_detach").putExtra("ownership", extras))
    }

    fun isBusy(context: Context): Boolean = AIZivaSession(directory(context)).active()

    fun status(context: Context): JSONObject {
        val store = AIZivaSession(directory(context))
        val state = read(context)
        val active = store.active()
        if (!active && (state.optString("boot_id") != AIZivaSession.bootId() ||
                state.optString("status") in listOf("queued", "starting", "running", "installing", "stopping"))) {
            // Reconcile only while holding ownership, so a late poll cannot overwrite a new worker.
            store.acquire()?.use {
                val clean = read(context)
                clean.remove("ui_port")
                clean.put("status", "idle").put("message", "Sesiunea anterioară este închisă.")
                save(context, clean)
            }
            return status(context)
        }
        val root = AILinuxRuntime.core(context).root
        val ziva = AIZivaPackage(root)
        val installed = ziva.installed() && AIZivaGodot(root).installed()
        val queued = pending > 0 && SystemClock.elapsedRealtime() - pending < 10000
        if (queued && !active) state.put("status", "starting").put("message", "Pregătesc automat Ziva…")
        val running = active && state.optString("status") == "running"
        return state.put("ok", true).put("enabled", BuildConfig.GODOT_AI_ZIVA).put("installed", installed)
            .put("version", ziva.version).put("running", running).put("ready", running)
            .put("ui_port", if (running) state.optInt("ui_port", 0) else 0).put("busy", active || queued)
            .put("linux_ready", AILinuxRuntime.core(context).state().optBoolean("ready"))
            .put("updates", AIZivaUpdates.status(context))
    }

    @Synchronized private fun schedule() {
        if (scheduled || owners.isEmpty() || !BuildConfig.GODOT_AI_ZIVA) return
        scheduled = true
        handler.postDelayed({ synchronized(this) {
            scheduled = false
            val activity = host.get()
            if (activity != null && owners.isNotEmpty()) {
                try { reconcile(activity) } catch (_: Exception) { }
                schedule()
            }
        } }, 2000)
    }
    private fun reconcile(activity: Activity) {
        if (owners.isEmpty()) return
        if (AILinuxRuntime.packageJob(activity).isNotEmpty()) return
        val target = owners[activity]?.takeIf { it.isNotEmpty() } ?: owners.values.firstOrNull { it.isNotEmpty() }.orEmpty()
        if (target != project) { project = target; attempts = 0; pending = 0 }
        val runtime = AILinuxRuntime.core(activity)
        if (!runtime.state().optBoolean("ready")) {
            if (AILinuxRuntime.packageJob(activity).isNotEmpty()) return
            if (prepareJob.isNotEmpty()) {
                val job = JSONObject(AILinuxRuntime.command("poll", JSONObject().put("id", prepareJob).toString()))
                if (job.optString("status") in listOf("queued", "running")) return
                prepareJob = ""
            }
            if (prepareAttempts < 3) {
                prepareAttempts++
                val job = JSONObject(AILinuxRuntime.command("prepare", "{}"))
                prepareJob = job.optString("id")
            }
            return
        }
        prepareJob = ""; prepareAttempts = 0
        val state = status(activity)
        if (target.isEmpty()) {
            if (state.optBoolean("running")) stop(activity)
            return
        }
        if (!state.optBoolean("installed") || state.optString("status") == "installing") return
        if (state.optBoolean("busy") && state.optString("project_id") == projectId(File(target))) { pending = 0; return }
        if (pending > 0 && SystemClock.elapsedRealtime() - pending < 10000) return
        if (attempts >= 3) return
        attempts++
        send(activity, "ziva_start", target, automatic = true)
    }
    private fun send(context: Context, action: String, target: String, release: JSONObject? = null, automatic: Boolean = false) {
        val extras = Bundle().apply { putBinder("owner", owner) }
        val intent = Intent(context, AIZivaService::class.java).putExtra("action", action)
            .putExtra("project_directory", target).putExtra("ownership", extras)
            .putExtra("request_id", UUID.randomUUID().toString()).putExtra("automatic", automatic)
        if (release != null) intent.putExtra("release", release.toString())
        pending = SystemClock.elapsedRealtime()
        try { context.startForegroundService(intent) }
        catch (error: Exception) { pending = 0; throw error }
    }

    fun command(context: Context, action: String, args: JSONObject): JSONObject {
        if (action == "ziva_status") {
            val state = status(context)
            val target = args.optString("project_directory")
            return state.put("same_project", target.isNotEmpty() && projectId(File(target)) == state.optString("project_id"))
        }
        check(BuildConfig.GODOT_AI_ZIVA) { "Disponibil în aplicația separată Godot AI Ziva." }
        if (action.startsWith("ziva_chat_")) return chat(context, action, args)
        if (action == "ziva_embed" && !args.optBoolean("visible")) { AIZivaWindow.hide(); return JSONObject().put("ok", true) }
        if (action == "ziva_embed") {
            val state = status(context)
            check(state.optBoolean("running")) { "Sesiunea Ziva se pregătește automat." }
            check(projectId(File(args.getString("project_directory"))) == state.optString("project_id")) { "Schimb proiectul Ziva…" }
            val bounds = args.getJSONArray("bounds"); require(bounds.length() == 4)
            AIZivaWindow.embed(state.getInt("ui_port"), DoubleArray(4) { bounds.getDouble(it) }, args.optBoolean("reload"))
        } else if (action == "ziva_attach") {
            val activity = host.get() ?: error("Editorul Android se pregătește.")
            val target = args.optString("project_directory")
            if (target.isNotEmpty()) check(File(target, "project.godot").isFile && !target.contains(':')) { "Proiect Godot invalid." }
            handler.post { synchronized(this) {
                owners[activity] = target
                attempts = 0
                try { reconcile(activity) } catch (_: Exception) { }
                schedule()
            } }
        } else if (action == "ziva_check_updates") {
            AIZivaUpdates.check(context)
        } else if (action in listOf("ziva_install", "ziva_update", "ziva_restart")) {
            val target = args.optString("project_directory")
            val release = if (action == "ziva_update") AIZivaUpdates.available(context) else null
            handler.post { synchronized(this) {
                attempts = 0; prepareAttempts = 0
                try { send(context, if (action == "ziva_restart") "ziva_start" else "ziva_install", target, release) }
                catch (error: Exception) {
                    val failed = read(context).put("status", "error").put("message", error.message?.take(240))
                    save(context, failed)
                }
            } }
        } else error("Operație Ziva necunoscută.")
        return JSONObject().put("ok", true)
    }

    /** Delegation to the official agent through its own local RPC, never the WebView. */
    private fun chat(context: Context, action: String, args: JSONObject): JSONObject {
        // Jobs live in this process; reading them never touches the sidecar, so a finished answer survives a stop.
        if (action == "ziva_chat_poll") return AIZivaChat.poll(args.optString("job_id"))
        if (action == "ziva_chat_cancel") return AIZivaChat.cancel(args.optString("job_id"))
        val state = status(context)
        val port = state.optInt("ui_port", 0)
        if (!state.optBoolean("running") || port <= 0)
            return JSONObject().put("ok", false).put("code", "ziva_not_running")
                .put("error", "Sesiunea Ziva nu rulează. Pornește-o din tabul Ziva, apoi reia.")
        val target = args.optString("project_directory")
        if (target.isEmpty() || projectId(File(target)) != state.optString("project_id"))
            return JSONObject().put("ok", false).put("code", "ziva_other_project")
                .put("error", "Ziva rulează pe alt proiect; deschide același proiect în tabul Ziva.")
        return when (action) {
            "ziva_chat_send" -> AIZivaChat.send(port, args.optString("prompt"), args.optString("chat_id"), args.optInt("timeout_seconds", 600))
            else -> JSONObject().put("ok", false).put("code", "ziva_unknown_action").put("error", "Operație Ziva necunoscută.")
        }
    }
}
