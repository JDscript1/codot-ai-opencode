package org.godotengine.editor

import android.content.Context
import org.json.JSONObject
import java.io.File

/** Ziva releases are delivered only through the signed APK; this object never uses the network. */
object AIZivaUpdates {
    private fun file(context: Context) = File(AIZivaRuntime.directory(context), "updates.json")

    fun status(context: Context): JSONObject {
        val current = try {
            AIZivaPackage.activeRelease(AILinuxRuntime.core(context).root).version
        } catch (_: Exception) { "" }
        return JSONObject()
            .put("available", true)
            .put("bundled", true)
            .put("checking", false)
            .put("version", current)
            .put("message", "Ziva $current este inclusă în APK. Reinstalarea folosește exclusiv pachetele locale; actualizarea versiunii se face cu un APK nou.")
    }

    fun check(context: Context) {
        AILinuxRuntimeFiles.writeJson(file(context), status(context).put("checked_at", System.currentTimeMillis()))
    }

    fun newer(candidate: String, current: String): Boolean {
        fun parts(value: String) = value.removePrefix("v").split('.').map { it.toIntOrNull() ?: -1 }
        val a = parts(candidate); val b = parts(current)
        if (a.size != 3 || b.size != 3 || a.any { it < 0 } || b.any { it < 0 }) return false
        for (i in 0..2) if (a[i] != b[i]) return a[i] > b[i]
        return false
    }

    fun release(metadata: JSONObject): AIZivaPackage.Release {
        check(!metadata.optBoolean("draft") && !metadata.optBoolean("prerelease")) { "Versiune Ziva nestabilă." }
        val version = metadata.getString("tag_name")
        val assets = metadata.getJSONArray("assets")
        val available = (0 until assets.length()).map { assets.getJSONObject(it) }
        fun asset(name: String): JSONObject {
            val matches = available.filter { it.optString("name") == name }
            check(matches.size == 1) { "Versiunea oficială nu are un pachet Linux ARM64 compatibil." }
            return matches.single()
        }
        fun digest(asset: JSONObject): String {
            val value = asset.optString("digest")
            check(value.startsWith("sha256:")) { "Versiunea oficială nu publică SHA-256." }
            return value.removePrefix("sha256:")
        }
        val addon = asset("ziva-ai-agent-$version-godot-v4.2.0-linux-arm64.zip")
        val runtime = asset("ziva-runtime-$version-linux-arm64.zip")
        return AIZivaPackage.fromJson(JSONObject().put("version", version)
            .put("url", addon.getString("browser_download_url")).put("archive_size", addon.getLong("size"))
            .put("archive_hash", digest(addon))
            .put("runtime_url", runtime.getString("browser_download_url")).put("runtime_size", runtime.getLong("size"))
            .put("runtime_hash", digest(runtime)))
    }
}
