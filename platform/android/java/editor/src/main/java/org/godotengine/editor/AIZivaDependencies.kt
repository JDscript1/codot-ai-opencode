package org.godotengine.editor

import org.json.JSONObject
import java.io.File

/** Runtime libraries needed by the official extension, including its linked CEF library. */
class AIZivaDependencies(
    private val root: File,
    private val execute: (List<String>, Int) -> JSONObject,
    private val extension: String = EXTENSION,
) {
    companion object {
        val PACKAGES = listOf("libfontconfig1", "fonts-dejavu-core", "libxcb1", "libglib2.0-0t64", "libnss3",
            "libatk-bridge2.0-0t64", "libcups2t64", "libx11-6", "libxcomposite1", "libxdamage1", "libxext6",
            "libxfixes3", "libxrandr2", "libgbm1", "libxkbcommon0", "libcairo2", "libpango-1.0-0", "libasound2t64")
        const val FONTCONFIG = "/usr/lib/aarch64-linux-gnu/libfontconfig.so.1"
        val EXTENSION = "/opt/godot-tools/ziva/${AIZivaPackage.RELEASE.version}/addons/ziva_agent/bin/linux_arm64/libziva_agent.linux.release.arm64.so"
    }

    fun missing(): List<String> {
        val missing = linkedSetOf<String>()
        val paths = mutableListOf(extension)
        if (File(root, FONTCONFIG.removePrefix("/")).isFile) paths.add(FONTCONFIG)
        else missing.add("libfontconfig.so.1")
        for (path in paths) {
            val result = execute(listOf("/usr/bin/ldd", path), 30)
            val lines = result.optString("output").lineSequence().filter { "not found" in it }.toList()
            missing.addAll(lines.map { it.trim().substringBefore(" =>").take(160) })
            if (result.optInt("exit_code", -1) != 0 && lines.isEmpty()) missing.add("Verificarea bibliotecilor a eșuat: ${File(path).name}")
        }
        return missing.toList()
    }

}
