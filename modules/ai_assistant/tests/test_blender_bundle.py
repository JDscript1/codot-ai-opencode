"""Static guards for the app-owned bundled Blender backend."""

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
LINUX_FILES = ROOT / "platform/android/java/editor/src/main/java/org/godotengine/editor/AILinuxRuntimeFiles.kt"
LINUX_RUNTIME = ROOT / "platform/android/java/editor/src/main/java/org/godotengine/editor/AILinuxRuntime.kt"
PACKAGE_MANAGER = ROOT / "platform/android/java/editor/src/main/java/org/godotengine/editor/AIPackageManager.kt"
INTEGRATIONS = ROOT / "modules/ai_assistant/runtime/integrations.gd"
LINUX_GD = ROOT / "modules/ai_assistant/runtime/linux_runtime.gd"
PANEL = ROOT / "modules/ai_assistant/runtime/panel.gd"
PI_RUNTIME = ROOT / "platform/android/java/editor/src/main/java/org/godotengine/editor/AIPiRuntime.kt"
ZIVA_UPDATES = ROOT / "platform/android/java/editor/src/main/java/org/godotengine/editor/AIZivaUpdates.kt"


class BundledBlenderTests(unittest.TestCase):
    def test_blender_is_in_the_signed_offline_package_set(self):
        packages = json.loads((ROOT / "tools/embedded-runtime/packages.json").read_text())
        self.assertIn("blender", packages["debian"]["packages"])
        offer = ROOT / "platform/android/java/editor/src/main/assets/godot_ai/BLENDER_SOURCE_OFFER.txt"
        self.assertIn("4.3.2+dfsg-2", offer.read_text())

    def test_blender_runs_in_the_app_linux_runtime_without_termux(self):
        source = LINUX_FILES.read_text()
        self.assertIn('put("backend", "app-linux")', source)
        self.assertIn('put("requires_termux", false)', source)
        self.assertIn('"/usr/bin/blender", "--background", "--factory-startup", "--version"', source)
        self.assertIn('"--python-exit-code", "1", "--python"', source)
        self.assertIn('"GODOT_AI_OUTPUT_DIR" to "/workspace/$outputRelative"', source)
        self.assertIn("safeProjectFile(project, relative)", source)
        self.assertIn("import numpy, requests, PIL", source)
        self.assertIn("GODOT_AI_BLENDER_PYTHON_OK", source)
        self.assertIn("/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin", source)
        self.assertNotIn("apt-get update", source)

        runtime = LINUX_RUNTIME.read_text()
        self.assertIn('if (action == "blender_status") return core(current).blenderStatus()', runtime)
        self.assertIn('"blender_run" -> runtime.blenderRun(', runtime)

    def test_blender_tools_are_exposed_to_the_agent(self):
        integrations = INTEGRATIONS.read_text()
        self.assertIn('Common.tool("blender_status"', integrations)
        self.assertIn('Common.tool("blender_prepare"', integrations)
        self.assertIn('Common.tool("blender_run"', integrations)
        self.assertIn("if bundled_blender():", integrations)
        self.assertIn("return await linux.blender(args, cancel)", integrations)

        linux = LINUX_GD.read_text()
        self.assertIn("func blender_status() -> Dictionary:", linux)
        self.assertIn("func install_blender(cancel: Dictionary) -> Dictionary:", linux)
        self.assertIn("func blender(args: Dictionary, cancel: Dictionary) -> Dictionary:", linux)
        self.assertNotIn('"blender"]', linux)
        self.assertIn("blender_prepare", PI_RUNTIME.read_text())

    def test_panel_prepares_bundled_blender_from_the_apk(self):
        panel = PANEL.read_text()
        self.assertIn("func _build_bundled_blender", panel)
        self.assertIn("Pregătește din APK", panel)
        self.assertIn("integrations.linux.install_blender({})", panel)
        self.assertIn("integrations.bundled_blender_ready()", panel)

    def test_package_status_requires_a_verified_blender(self):
        source = PACKAGE_MANAGER.read_text()
        self.assertIn('val blenderReady = File(runtime.root, "usr/bin/blender").isFile', source)
        self.assertIn("piReady && debianReady && blenderReady", source)
        self.assertIn('.put("blender", JSONObject()', source)
        self.assertIn("2684354560L", source)

    def test_bundled_tools_install_without_network(self):
        files = LINUX_FILES.read_text()
        runtime = LINUX_RUNTIME.read_text()
        packages = PACKAGE_MANAGER.read_text()
        self.assertIn("/root/.local/node_modules/node/bin:/root/.local/node_modules/.bin", files)
        self.assertIn('"/root/.local/node_modules/node/bin/node", "--version"', files)
        self.assertIn('listOf("/bin/sh", "-c", command)', files)
        self.assertNotIn("preparePackageNetwork", runtime)
        self.assertNotIn("runtime.installTool", runtime)
        self.assertIn("AIPackageManager.installDebian", runtime)
        self.assertIn("AIPackageManager.installPi", runtime)
        self.assertIn("AIPackageManager.piInstalled", runtime)
        self.assertIn("internal fun piInstalled", packages)
        self.assertIn("AIMemoryGuard.ensure", runtime)
        self.assertIn("hasActiveJob", runtime)
        self.assertIn("Pregătesc pachetele Debian și Blender din APK", runtime)
        self.assertIn("if (!AIPackageManager.piInstalled(runtime, packages))", runtime)
        self.assertNotIn("installTool", files)
        self.assertNotIn("TOOL_PACKAGES", files)
        self.assertNotIn("tool_install", runtime)
        self.assertTrue((ROOT / "platform/android/java/editor/src/main/java/org/godotengine/editor/AIMemoryGuard.kt").is_file())
        updates = ZIVA_UPDATES.read_text()
        self.assertNotIn("HttpURLConnection", updates)
        self.assertNotIn("https://api.github.com", updates)
        panel = PANEL.read_text()
        self.assertIn("form[\"statuses\"]", panel)
        self.assertNotIn("form[\"buttons\"]", panel)
        linux = LINUX_GD.read_text()
        self.assertNotIn('Common.tool("linux_install_tool"', linux)


if __name__ == "__main__":
    unittest.main()
