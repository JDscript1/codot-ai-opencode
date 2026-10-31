import org.godotengine.editor.AIZivaProjectContext
import org.json.JSONObject
import java.io.File
import java.nio.file.Files

fun main() {
    val scratch = Files.createTempDirectory("ziva-project-context-").toFile()
    var checks = 0
    fun expect(ok: Boolean) { check(ok) { "check ${checks + 1}" }; checks++ }
    try {
        val project = File(scratch, "project").apply { mkdirs() }
        val session = File(scratch, "session").apply { mkdirs() }
        val original = File(project, "AGENTS.md").apply { writeText("USER PROJECT RULES\n") }
        val config = File(project, "project.godot").apply { writeText("""
            config_version=5
            [editor_plugins]
            enabled=PackedStringArray("res://addons/terrain_3d/plugin.cfg")
        """.trimIndent()) }
        val configBefore = config.readText()
        val terrain = File(project, "addons/terrain_3d").apply { mkdirs() }
        File(terrain, "plugin.cfg").writeText("[plugin]\nname=\"Terrain3D\"\nversion=\"1.0.2\"\n")
        File(terrain, "terrain.gdextension").writeText("""
            [configuration]
            entry_symbol="terrain_3d_init"
            [libraries]
            android.debug.arm64="res://addons/terrain_3d/bin/android.so"
            linux.debug.x86_64="res://addons/terrain_3d/bin/x86_64.so"
            linux.debug.arm64="res://addons/terrain_3d/bin/arm64.so"
            linux.arm64.custom="res://addons/terrain_3d/bin/other.so"
        """.trimIndent())
        File(terrain, "bin").mkdirs()
        File(terrain, "bin/android.so").writeText("ANDROID FIXTURE")
        val global = File(scratch, "global-AGENTS.md").apply { writeText("GLOBAL USER RULES\n") }
        expect(AIZivaProjectContext.refresh(project, session, global))
        val first = JSONObject(File(session, "addons.json").readText())
        val plugin = first.getJSONArray("plugins").getJSONObject(0)
        expect(plugin.getString("name") == "Terrain3D" && plugin.getBoolean("installed"))
        expect(plugin.getBoolean("enabled_in_project"))
        val extension = first.getJSONArray("extensions").getJSONObject(0)
        val candidates = extension.getJSONArray("linux_arm64_candidates")
        expect(candidates.length() == 1 && !candidates.getJSONObject(0).getBoolean("file_present"))
        expect(!extension.getBoolean("load_verified"))
        expect(File(session, "AGENTS.md").readText().startsWith(global.readText()))
        expect(File(session, "AGENTS.md").readText().contains(AIZivaProjectContext.INVENTORY))
        expect(original.readText() == "USER PROJECT RULES\n" && config.readText() == configBefore)
        expect(!AIZivaProjectContext.refresh(project, session, global))
        // A store install made while the session is running becomes visible.
        File(terrain, "bin/arm64.so").writeText("LINUX FIXTURE")
        val secondPlugin = File(project, "addons/disabled/plugin.cfg").apply { parentFile.mkdirs(); writeText("[plugin]\nname=\"Disabled addon\"\n") }
        expect(AIZivaProjectContext.refresh(project, session, global))
        val updated = JSONObject(File(session, "addons.json").readText())
        expect(updated.getJSONArray("plugins").length() == 2)
        expect(!updated.getJSONArray("plugins").getJSONObject(0).getBoolean("enabled_in_project"))
        expect(updated.getJSONArray("extensions").getJSONObject(0).getJSONArray("linux_arm64_candidates").getJSONObject(0).getBoolean("file_present"))
        // Native-only addons count even without plugin.cfg.
        val native = File(project, "addons/native/only.gdextension").apply { parentFile.mkdirs(); writeText("[libraries]\nlinux.arm64=\"native.so\"\n") }
        File(native.parentFile, "native.so").writeText("NATIVE FIXTURE")
        expect(AIZivaProjectContext.snapshot(project).getJSONArray("extensions").length() == 2)
        val outside = File(scratch, "outside").apply { mkdirs() }
        File(outside, "plugin.cfg").writeText("[plugin]\nname=\"OUTSIDE\"\n")
        Files.createSymbolicLink(File(project, "addons/link").toPath(), outside.toPath())
        expect(AIZivaProjectContext.snapshot(project).getJSONArray("plugins").length() == 2)
        val oversized = File(project, "addons/big/plugin.cfg").apply { parentFile.mkdirs(); writeText("x".repeat(262145)) }
        expect(AIZivaProjectContext.snapshot(project).getBoolean("scan_truncated"))
        expect(!File(session, "AGENTS.md").readText().contains("USER PROJECT RULES"))
        secondPlugin.delete(); oversized.delete()
        expect(AIZivaProjectContext.refresh(project, session, global))
        expect(JSONObject(File(session, "addons.json").readText()).getJSONArray("plugins").length() == 1)
        expect(global.readText() == "GLOBAL USER RULES\n" && original.readText() == "USER PROJECT RULES\n")
        config.writeText("[editor_plugins]\nenabled=PackedStringArray(\n\"res://addons/terrain_3d/plugin.cfg\"\n)\n")
        expect(AIZivaProjectContext.snapshot(project).getJSONArray("plugins").getJSONObject(0).getBoolean("enabled_in_project"))
        // A previous PRoot bind can leave a zero-byte, unreadable target.
        // Refresh must still create the session overlay, preserving that target.
        val placeholder = File(scratch, "empty-bind-target").apply { createNewFile() }
        val permissions = emptySet<java.nio.file.attribute.PosixFilePermission>()
        Files.setPosixFilePermissions(placeholder.toPath(), permissions)
        try {
            expect(AIZivaProjectContext.refresh(project, session, placeholder))
            expect(AIZivaProjectContext.canOverlay(session))
            expect(JSONObject(File(session, "addons.json").readText()).getBoolean("host_instructions_available"))
            expect(placeholder.length() == 0L && Files.getPosixFilePermissions(placeholder.toPath()) == permissions)
            expect(File(session, "AGENTS.md").readText().contains(AIZivaProjectContext.INVENTORY))
        } finally { placeholder.setReadable(true, true); placeholder.setWritable(true, true) }
        val share = File(scratch, "share").apply { mkdirs() }
        val named = File(scratch, "named").apply { mkdirs() }
        fun userDirectory(config: String) =
            File(named, "project.godot").writeText("[application]\n$config\n").let { AIZivaProjectContext.userDirectory(share, named) }
        expect(userDirectory("config/name=\"Devonian Era\"") == File(share, "godot/app_userdata/Devonian Era"))
        expect(userDirectory("config/name=\"My:Game.\"") == File(share, "godot/app_userdata/My-Game"))
        expect(userDirectory("config/name=\"a/b\\c\"") == File(share, "godot/app_userdata/a-b-c"))
        expect(userDirectory("config/name=\"\"") == File(share, "godot/app_userdata/[unnamed project]"))
        expect(userDirectory("config/name=\"..\"") == File(share, "godot/app_userdata/twodots"))
        expect(userDirectory("config/name=\"Game\"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name=\"Studio/My Game\"") ==
            File(share, "Studio/My Game"))
        expect(userDirectory("config/name=\"Game\"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name=\"\"") == File(share, "Game"))
        expect(userDirectory("config/name=\"Game\"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name=\"../evil\"") ==
            File(share, "-/evil"))
        println("Ziva project addon context: $checks checks, 0 failures")
    } finally { scratch.deleteRecursively() }
}
