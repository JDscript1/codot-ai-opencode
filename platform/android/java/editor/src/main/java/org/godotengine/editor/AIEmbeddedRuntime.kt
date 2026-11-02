package org.godotengine.editor

import android.app.Activity
import android.app.Application
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.Handler
import android.os.Looper
import android.os.Process
import org.json.JSONObject
import java.io.File
import java.lang.ref.WeakReference
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.TimeUnit

/** Short self-test only; success does not make Blender available to the agent. */
object AIEmbeddedRuntime {
    private const val PREFS = "ai_embedded_runtime_probe"
    private const val PROBE = "libai_runtime_probe.so"
    private var activity = WeakReference<Activity>(null)

    fun initialize(value: Activity) {
        activity = WeakReference(value)
        AILinuxRuntime.initialize(value)
        AIZivaRuntime.register(value)
        AIOpenCodeRuntime.initialize(value)
        // Runs once for this editor launch, after Activity.onCreate has returned.
        if (Build.VERSION.SDK_INT >= 29 && Application.getProcessName() == value.packageName) {
            Handler(Looper.getMainLooper()).post { command("embedded_probe") }
        }
    }

    @JvmStatic @Synchronized fun command(action: String): String {
        val current = activity.get() ?: return JSONObject().put("ok", false).put("error", "Editorul Android nu este activ.").toString()
        val prefs = current.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (prefs.getString("status", "") == "running" &&
            System.currentTimeMillis() - prefs.getLong("started_at", 0) > 40_000) {
            prefs.edit().putString("status", "failed").putString("error", "Procesul runtime nu a întors rezultatul în timpul alocat.").commit()
        }
        val file = File(current.applicationInfo.nativeLibraryDir, PROBE)
        val result = JSONObject().put("ok", true)
            .put("supported", Build.SUPPORTED_ABIS.contains("arm64-v8a"))
            .put("packaged", file.isFile)
            .put("result", prefs.getString("result", ""))
            .put("error", prefs.getString("error", ""))
            .put("pid", prefs.getInt("pid", 0))
            .put("status", prefs.getString("status", "unchecked"))
            .put("run_id", prefs.getString("run_id", ""))
            .put("details", prefs.getString("details", ""))
        if (action == "embedded_status") return result.toString()
        if (action != "embedded_probe") return JSONObject().put("ok", false).put("error", "Operație necunoscută.").toString()
        if (!file.isFile || !Build.SUPPORTED_ABIS.contains("arm64-v8a") || Build.VERSION.SDK_INT < 29) {
            return JSONObject().put("ok", false).put("error", "Proba nativă ARM64 lipsește din instalare.").toString()
        }
        if (prefs.getString("status", "") == "running" &&
            System.currentTimeMillis() - prefs.getLong("started_at", 0) < 40_000) {
            return result.put("started", true).toString()
        }
        val runId = UUID.randomUUID().toString()
        if (!prefs.edit().putString("result", "").putString("error", "").putString("details", "")
                .putInt("pid", 0).putString("run_id", runId).putString("status", "running")
                .putLong("started_at", System.currentTimeMillis()).commit()) {
            return JSONObject().put("ok", false).put("error", "Nu pot salva starea probei native.").toString()
        }
        return try {
            current.startService(Intent(current, AIEmbeddedRuntimeService::class.java).putExtra("run_id", runId))
            result.put("started", true).put("status", "running").put("run_id", runId).toString()
        } catch (error: Exception) {
            prefs.edit().putString("status", "failed").putString("error", error.javaClass.simpleName).apply()
            JSONObject().put("ok", false).put("error", "Procesul separat nu a pornit: ${error.javaClass.simpleName}").toString()
        }
    }

    fun receive(context: Context, intent: Intent) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (intent.getStringExtra("run_id") != prefs.getString("run_id", "")) return
        prefs.edit()
            .putString("result", intent.getStringExtra("result") ?: "")
            .putString("error", intent.getStringExtra("error") ?: "")
            .putString("status", if (intent.getStringExtra("error").isNullOrEmpty()) "completed" else "failed")
            .putString("details", intent.getStringExtra("details") ?: "")
            .putInt("pid", intent.getIntExtra("pid", 0)).apply()
    }
}

/** Android creates this service under :ai_runtime; it never accepts outside intents. */
class AIEmbeddedRuntimeService : Service() {
    private var busy = false
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val runId = intent?.getStringExtra("run_id")
        if (runId == null || !runId.matches(Regex("[a-f0-9-]{36}")) || busy) {
            if (!busy) stopSelf(startId)
            return START_NOT_STICKY
        }
        busy = true
        Thread({
            var output = ""
            var error = ""
            val details = JSONObject()
            val directory = File(cacheDir, "ai-runtime-probe/$runId")
            try {
                val executable = File(applicationInfo.nativeLibraryDir, "libai_runtime_probe.so")
                check(executable.isFile && executable.canExecute()) { "Executabilul ambalat nu este disponibil." }
                val host = execute(listOf(executable.absolutePath))
                details.put("native", host)
                check(host.startsWith("AI_RUNTIME_PROBE_V1 ")) { "Răspuns nativ invalid." }
                val manifest = assets.open("godot_ai/embedded/manifest.json").bufferedReader().use { JSONObject(it.readText()) }
                check(manifest.getInt("schema") == 1 && manifest.getString("abi") == "arm64-v8a") { "Manifest runtime incompatibil." }
                val files = manifest.getJSONObject("files")
                val proot = File(applicationInfo.nativeLibraryDir, "libai_proot.so")
                val loader = File(applicationInfo.nativeLibraryDir, "libai_proot_loader.so")
                for (native in listOf(proot, loader)) {
                    check(native.isFile && native.canExecute()) { "Componentă nativă absentă: ${native.name}" }
                    verify(native.readBytes(), files.getJSONObject("jniLibs/arm64-v8a/${native.name}"))
                }
                val guest = assets.open("godot_ai/embedded/linux-probe").use { it.readBytes() }
                verify(guest, files.getJSONObject("assets/godot_ai/embedded/linux-probe"))
                val rootfs = File(directory, "rootfs")
                val bin = File(rootfs, "bin").apply { check(mkdirs()) }
                val temporary = File(directory, "tmp").apply { check(mkdirs()) }
                File(bin, "probe").apply { writeBytes(guest); check(setExecutable(true, true)) }
                val environment = mapOf("PATH" to "/system/bin", "ANDROID_DATA" to "/data", "ANDROID_ROOT" to "/system",
                    "HOME" to "/", "PROOT_LOADER" to loader.absolutePath, "PROOT_TMP_DIR" to temporary.absolutePath)
                val linux = execute(listOf(proot.absolutePath, "-0", "-r", rootfs.absolutePath, "-w", "/", "/bin/probe"), environment)
                details.put("linux", linux)
                check(linux == "AI_LINUX_GUEST_V1") { "Răspuns Linux invalid." }
                output = "Runtime integrat verificat: proces Android separat și program Linux ARM64."
            } catch (failure: Exception) {
                error = failure.message?.take(4000) ?: failure.javaClass.simpleName
            } finally {
                directory.deleteRecursively()
                sendBroadcast(Intent(this, AIEmbeddedRuntimeResult::class.java).apply {
                    putExtra("run_id", runId)
                    putExtra("result", output)
                    putExtra("error", error)
                    putExtra("details", details.toString())
                    putExtra("pid", Process.myPid())
                })
                Handler(Looper.getMainLooper()).post { busy = false; stopSelf(startId) }
            }
        }, "AIEmbeddedRuntimeProbe").start()
        return START_NOT_STICKY
    }

    private fun verify(bytes: ByteArray, spec: JSONObject) {
        val actual = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it.toInt() and 255) }
        check(bytes.size == spec.getInt("size") && actual == spec.getString("sha256")) { "Componentă runtime coruptă." }
    }

    private fun execute(arguments: List<String>, environment: Map<String, String> = mapOf("PATH" to "/system/bin")): String {
        val builder = ProcessBuilder(arguments).redirectErrorStream(true)
        builder.environment().apply { clear(); putAll(environment) }
        val child = builder.start()
        try {
            if (!child.waitFor(8, TimeUnit.SECONDS)) {
                child.destroyForcibly()
                error("Proba runtime a depășit limita de 8 secunde.")
            }
            val text = child.inputStream.bufferedReader().use { it.readText().take(4000) }.trim()
            check(child.exitValue() == 0) { "Runtime: cod ${child.exitValue()}. $text" }
            return text
        } finally { child.destroy() }
    }
}

class AIEmbeddedRuntimeResult : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        AIEmbeddedRuntime.receive(context, intent)
    }
}
