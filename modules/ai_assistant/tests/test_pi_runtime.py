"""Static guards for the app-owned Pi runtime and Android wiring."""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PI = ROOT / "platform/android/java/editor/src/main/java/org/godotengine/editor/AIPiRuntime.kt"
PANEL = ROOT / "modules/ai_assistant/runtime/panel.gd"
MCP = ROOT / "modules/ai_assistant/runtime/godot_mcp.gd"


class PiRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.source = PI.read_text()

    def test_pinned_runtime_versions_and_rpc_entrypoint(self):
        self.assertIn('const val PI_VERSION = "1.5.0"', self.source)
        self.assertIn('const val NODE_VERSION = "22.19.0"', self.source)
        self.assertIn('"--mode", "rpc"', self.source)
        self.assertIn('"--no-approve"', self.source)
        self.assertIn('"PI_CODING_AGENT_DIR"', self.source)

    def test_mcp_allows_human_approval_time(self):
        self.assertIn('.put("timeout", 3600)', self.source)
        self.assertIn('provider.put("apiKey", piLiteral(key.ifEmpty { "pi-local" }))', self.source)
        self.assertIn("if (character == '$' || character == '!') output.append('$')", self.source)
        self.assertIn('.put("headers", JSONObject().put("Authorization", "Bearer $token"))', self.source)

    def test_mcp_catalog_is_deferred_to_pi_native_tool_search(self):
        self.assertIn('.put("exposure", "deferred")', self.source)
        self.assertNotIn('.put("exposure", "direct")', self.source)
        self.assertIn('"tool_search"', self.source)
        self.assertIn("APPEND_SYSTEM.md", self.source)
        mcp = MCP.read_text()
        self.assertIn('panel.call("agent_catalog")', mcp)
        self.assertIn('panel.call("agent_execute", tool, arguments)', mcp)
        self.assertNotIn('"name": "search"', mcp)

    def test_native_tools_and_read_only_toolset_are_explicit(self):
        self.assertIn(
            'JSONArray(listOf("read", "bash", "edit", "write", "grep", "find", "ls", "tool_search"))',
            self.source,
        )
        self.assertIn('"read,grep,find,ls,tool_search"', self.source)
        self.assertIn('mode in setOf("plan", "read_only")', self.source)

    def test_pi_owns_session_and_context(self):
        panel = PANEL.read_text()
        self.assertIn("_pi_can_reuse_session", panel)
        self.assertIn("if not keep_session", panel)
        self.assertIn("if not pi_owned_turn and _auto_compact_enabled()", panel)
        start = panel.index("func _pi_prompt(")
        end = panel.index("\nfunc _pi_images(", start)
        prompt = panel[start:end]
        self.assertNotIn("compact_summary", prompt)
        self.assertNotIn("AGENT.md", prompt)
        self.assertNotIn("Current app task plan", prompt)
        self.assertIn("<app_turn>", prompt)

    def test_app_mcp_calls_use_the_normal_approval_path(self):
        panel = PANEL.read_text()
        self.assertIn("var result: Dictionary = await _execute_call(name, args)", panel)
        self.assertNotIn("await _execute_call(name, args, true)", panel)
        self.assertIn('if result.get("ok", false): _track_verification(name)', panel)

    def test_legacy_opencode_surface_is_absent(self):
        for relative in [
            "modules/ai_assistant/runtime/opencode.gd",
            "modules/ai_assistant/runtime/opencode_screen.gd",
            "platform/android/java/editor/src/main/java/org/godotengine/editor/AIOpenCodeRuntime.kt",
            "platform/android/java/editor/src/main/java/org/godotengine/editor/AIOpenCodeWindow.kt",
            "platform/android/java/editor/src/main/native/ai_pty.c",
        ]:
            with self.subTest(relative=relative):
                self.assertFalse((ROOT / relative).exists())


if __name__ == "__main__":
    unittest.main()
