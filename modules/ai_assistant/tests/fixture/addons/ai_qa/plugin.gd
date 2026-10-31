@tool
extends EditorPlugin

var embedded: Dictionary = {}
var panel: Control
var failures: Array = []
var checks = 0
var native = false
var placement = 0
var fixture_dock: EditorDock

func _has_main_screen() -> bool: return not ClassDB.class_exists("AIAssistantEditorPlugin")
func _get_plugin_name() -> String: return "AI Assistant QA"
func _make_visible(value: bool) -> void:
	if is_instance_valid(panel) and not native:
		if fixture_dock != null:
			if value: fixture_dock.make_visible()
		else: panel.visible = value

func set_chat_placement(index: int) -> void:
	if index == placement: return
	if fixture_dock != null:
		fixture_dock.remove_child(panel)
		remove_dock(fixture_dock)
		fixture_dock.queue_free()
		fixture_dock = null
	else: panel.get_parent().remove_child(panel)
	placement = index
	if index == 0:
		EditorInterface.get_editor_main_screen().add_child(panel)
		panel.custom_minimum_size = Vector2(0, 200) * EditorInterface.get_editor_scale()
		EditorInterface.set_main_screen_editor("AI Assistant QA")
	else:
		fixture_dock = EditorDock.new()
		fixture_dock.title = "AI Assistant QA"
		fixture_dock.default_slot = EditorDock.DOCK_SLOT_LEFT_UL if index == 1 else EditorDock.DOCK_SLOT_RIGHT_UL
		panel.custom_minimum_size = Vector2(200, 200) * EditorInterface.get_editor_scale()
		fixture_dock.add_child(panel)
		add_dock(fixture_dock)
		fixture_dock.make_visible()
		EditorInterface.set_main_screen_editor("3D")
	panel.show()

class FixtureVault:
	extends RefCounted
	var values = {}
	func read(name: String) -> String: return str(values.get(name, ""))
	func store(name: String, value: String) -> bool:
		values[name] = value
		return true
	func erase(name: String) -> bool: return values.erase(name)

class GenerationTransport:
	extends RefCounted
	var host: Node
	var public_headers: Array = []
	var paid_requests = 0
	func request(url: String, method: int, headers: PackedStringArray, body: Variant, options: Dictionary) -> Dictionary:
		await host.get_tree().create_timer(0.03).timeout
		if options.get("cancel", {}).get("cancelled", false): return {"ok": false, "code": "cancelled", "error": "Oprit"}
		if url.contains("/docs/"):
			public_headers.append(headers)
			if url.ends_with("index.json"):
				return {"ok": true, "json": [
					{"air": "fixture:image@1", "name": "Studio Image", "status": "live", "capabilities": ["text-to-image"], "schema": "http://127.0.0.1/docs/image.json"},
					{"air": "fixture:image@2", "name": "Canvas Pro", "status": "live", "capabilities": ["text-to-image"], "schema": "http://127.0.0.1/docs/unknown.json"},
					{"air": "fixture:mesh@1", "name": "Sculpt 3D", "status": "live", "capabilities": ["image-to-3d"], "schema": "http://127.0.0.1/docs/mesh.json"}]}
			return {"ok": true, "json": {"info": {"x-pricing": {} if url.ends_with("unknown.json") else {"currency": "USD", "rates": [{"amount": 0.04, "unit": "output", "label": "Standard"}, {"amount": 0.08, "unit": "output", "label": "HD"}]}}}}
		if not "Authorization: Bearer sk-fixture-generation-valid" in headers: return {"ok": false, "status": 401, "error": "Cheie respinsă (probă): sk-fixture-generation-invalid"}
		if method == HTTPClient.METHOD_POST:
			if body is Array and body[0].get("taskType") == "ping": return {"ok": true, "json": {"data": [{"pong": true}]}}
			paid_requests += 1
		if url.ends_with("/balance"): return {"ok": true, "json": {"balance": 100}}
		return {"ok": false, "error": "Cerere neașteptată în proba catalogului."}

class AgentPricingTransport:
	extends RefCounted
	var requests = 0
	var input_rate = "0.15"
	var fail = false
	func request(_url: String, _method: int, _headers: PackedStringArray, _body: Variant, _options: Dictionary) -> Dictionary:
		requests += 1
		if fail: return {"ok": false, "error": "Offline"}
		return {"ok": true, "text": "<table><tr><td>MODEL</td><td></td><td></td><td>deepseek-flash</td><td>deepseek-v4-pro</td></tr><tr><td>PRICING</td><td>1M INPUT TOKENS (CACHE MISS)</td><td>OFF-PEAK</td><td>$%s</td><td>$0.66</td></tr><tr><td>PRICING</td><td>1M OUTPUT TOKENS</td><td>OFF-PEAK</td><td>$0.60</td><td>$1.98</td></tr></table>" % input_rate}

class FixtureProvider:
	extends RefCounted
	var requests = 0
	var call_id = "fixture-native-write"
	func complete(_profile: Dictionary, messages: Array, _tools: Array, _model: String, _effort: String, _cancel: Dictionary, delta: Callable) -> Dictionary:
		requests += 1
		var calls = []
		if requests == 1:
			calls = [{"id": call_id + "-describe", "name": "tool_describe", "arguments": {"name": "godot_create_node"}}, {"id": call_id + "-plan", "name": "task_update", "arguments": {"tasks": [{"step": "Create and inspect the node", "status": "in_progress"}], "phase": "executing", "criteria": [{"id": "node", "description": "The created node is named HarnessProbe", "kind": "inspection", "check": {"pointer": "", "op": "eq", "expected": "HarnessProbe"}}]}}]
		if requests == 2: calls = [{"id": call_id, "name": "godot_create_node", "arguments": {"type": "Node3D", "name": "HarnessProbe"}}]
		if requests in [3, 4]:
			var found = {}
			for message in messages:
				if message.get("role") == "tool" and message.get("tool_name") == ("godot_create_node" if requests == 3 else "godot_get"): found = JSON.parse_string(str(message.get("content", "{}")))
			calls = [{"id": call_id + "-inspect", "name": "godot_get", "arguments": {"handle": found.get("result", {}).get("handle", ""), "property": "name"}}] if requests == 3 else [{"id": call_id + "-check", "name": "task_check", "arguments": {"criterion": "node", "evidence": [str(found.get("verification_evidence", {}).get("id", ""))]}}]
		if requests == 5: calls = [{"id": call_id + "-finish", "name": "task_update", "arguments": {"tasks": [{"step": "Create and inspect the node", "status": "completed"}], "phase": "completed", "verification": "Actual node name inspected"}}]
		var text = "" if requests <= 5 else "Verificat în editor."
		if not text.is_empty(): delta.call(text)
		return {"ok": true, "message": {"role": "assistant", "content": text, "tool_calls": calls}, "calls": calls, "finish": "stop"}

class FixtureLocalCatalog:
	extends RefCounted
	var requests = 0
	func list_models(_profile: Dictionary, _cancel: Dictionary = {}, _key_override: String = "") -> Dictionary:
		requests += 1
		return {"ok": true, "result": [{"id": "unloaded-code", "loaded": false, "capabilities": {}}, {"id": "loaded-code", "loaded": true, "context": 4096, "capabilities": {}}]}

class FixtureDebuggerBridge:
	extends Node
	var data: Dictionary = {}
	func debugger_snapshot() -> Dictionary: return {"ok": true, "result": data.duplicate(true)}

class FixtureLongProvider:
	extends RefCounted
	var requests = 0
	var work_items = 35
	func _init(node: Node = null, _vault: RefCounted = null) -> void:
		if node != null: work_items = 105
	func complete(_profile: Dictionary, _messages: Array, _tools: Array, _model: String, _effort: String, _cancel: Dictionary, _delta: Callable) -> Dictionary:
		requests += 1
		var calls = []
		if requests <= work_items: calls = [{"id": "long-inspect-" + str(requests), "name": "godot_project", "arguments": {}}]
		return {"ok": true, "message": {"role": "assistant", "content": "Long inspection complete" if calls.is_empty() else "", "tool_calls": calls}, "calls": calls, "finish": "stop"}

class FixtureCompanionAccounts:
	extends RefCounted
	var turns = 0
	var stalled = false
	func companion_request(_connection: Dictionary, path: String, _method: int = HTTPClient.METHOD_GET, _body: Variant = null, _cancel: Dictionary = {}) -> Dictionary:
		if path == "/v1/turns":
			turns += 1
			return {"ok": true, "json": {"result": {"id": "companion-" + str(turns)}}}
		if path.contains("?after="):
			var tasks = []
			var completed = 0 if stalled else turns
			for index in range(8): tasks.append({"step": "Inspect part " + str(index), "status": "completed" if index < completed else "pending"})
			return {"ok": true, "json": {"result": {"status": "completed", "text": "Verified current inspection", "events": [{"sequence": 1, "kind": "tool", "id": "plan-" + str(turns), "name": "task_update", "arguments": {"tasks": tasks, "phase": "completed" if completed == 8 else "executing"}}]}}}
		return {"ok": true, "json": {}}

class FixtureCloudCatalog:
	extends RefCounted
	var owner: Node
	var requests = 0
	var response = {"ok": true, "result": [{"id": "deepseek-flash", "name": "DeepSeek-V4.1-Flash", "efforts": ["low", "high", "max"], "capabilities": {"tools": true, "vision": true}}, {"id": "deepseek-v4-pro", "name": "DeepSeek-V4-Pro", "efforts": ["low", "high", "max"], "capabilities": {"tools": true}}]}
	func list_models(_profile: Dictionary, _cancel: Dictionary = {}, _key_override: String = "") -> Dictionary:
		requests += 1
		await owner.get_tree().create_timer(0.05).timeout
		return response.duplicate(true)

class FixtureBlenderVerification:
	extends RefCounted
	var data = PackedByteArray()
	var verification: Dictionary = {}
	var acknowledged = false
	var submissions = 0
	var online = false
	var revision = 2
	var worker_runtime: Dictionary = {}
	var submitted: Array = []
	var job_result: Dictionary = {}
	func request(url: String, _method: int, _headers: PackedStringArray, _body: Variant, options: Dictionary) -> Dictionary:
		if url.ends_with("/health"):
			return {"ok": true, "json": {"ok": true, "protocol": 1, "revision": revision, "runtime": worker_runtime}} if online else {"ok": false, "code": "connection_failed"}
		if url.ends_with("/ack"):
			acknowledged = true
			return {"ok": true}
		if _method == HTTPClient.METHOD_POST:
			submissions += 1
			submitted.append(_body.duplicate(true))
			match str(_body.get("kind", "")):
				"install":
					worker_runtime = verification.get("runtime", {}).duplicate(true)
					job_result = worker_runtime.merged({"found": true})
				"uninstall":
					worker_runtime = {}
					job_result = {"removed": true, "found": false}
				_: job_result = verification
		if not options.has("save_path"): return {"ok": true, "json": {"ok": true, "result": {"status": "completed", "kind": "verify", "result": verification if job_result.is_empty() else job_result}}}
		var file = FileAccess.open(str(options.get("save_path", "")), FileAccess.WRITE)
		if file == null: return {"ok": false, "error": "Fixture download could not be written"}
		file.store_buffer(data)
		file.close()
		return {"ok": true}

class FixtureResumeProvider:
	extends RefCounted
	var requests = 0
	var contexts: Array = []
	func complete(_profile: Dictionary, messages: Array, _tools: Array, _model: String, _effort: String, _cancel: Dictionary, delta: Callable) -> Dictionary:
		requests += 1
		contexts.append(messages.duplicate(true))
		if requests == 1:
			delta.call("Am început verificarea.")
			return {"ok": false, "code": "incomplete_stream", "error": "Fixture interrupted stream"}
		var text = "Verificare reluată fără operații duplicate."
		return {"ok": true, "message": {"role": "assistant", "content": text, "tool_calls": []}, "calls": [], "finish": "stop"}

class FixtureBlockedProvider:
	extends RefCounted
	var requests = 0
	func complete(_profile: Dictionary, _messages: Array, _tools: Array, _model: String, _effort: String, _cancel: Dictionary, _delta: Callable) -> Dictionary:
		requests += 1
		var calls = [{"id": "fixture-blocked-plan", "name": "task_update", "arguments": {"phase": "blocked", "tasks": [{"step": "Verifică diagnosticele native", "status": "pending"}], "explanation": "Bridge indisponibil."}}] if requests == 1 else []
		return {"ok": true, "message": {"role": "assistant", "content": "" if requests == 1 else "Verificarea este blocată.", "tool_calls": calls}, "calls": calls, "finish": "stop"}

class FixtureRedirectProvider:
	extends RefCounted
	var host: Control
	var requests = 0
	func complete(_profile: Dictionary, _messages: Array, _tools: Array, _model: String, _effort: String, _cancel: Dictionary, _delta: Callable) -> Dictionary:
		requests += 1
		if requests == 1:
			host._send_or_queue("Acum doar inspectează proiectul, fără generare.", "steer")
			var calls = [{"id": "superseded-generate", "name": "asset_generate", "arguments": {"profile": "missing", "prompt": "Superseded box"}}]
			return {"ok": true, "message": {"role": "assistant", "content": "", "tool_calls": calls}, "calls": calls}
		return {"ok": true, "message": {"role": "assistant", "content": "Am păstrat proiectul nemodificat.", "tool_calls": []}, "calls": [], "finish": "stop"}

class FixtureAskProvider:
	extends RefCounted
	var requests = 0
	var catalog: Array = []
	func complete(_profile: Dictionary, _messages: Array, tools: Array, _model: String, _effort: String, _cancel: Dictionary, _delta: Callable) -> Dictionary:
		requests += 1
		catalog = tools.duplicate(true)
		var calls = [{"id": "ask-project", "name": "godot_project", "arguments": {}}, {"id": "ask-write", "name": "godot_write_file", "arguments": {"path": "res://ask-must-not-exist.txt", "text": "Forbidden in Ask"}}] if requests == 1 else []
		return {"ok": true, "message": {"role": "assistant", "content": "Proiect inspectat fără modificări." if calls.is_empty() else "", "tool_calls": calls}, "calls": calls, "finish": "stop"}

class FixturePlanningProvider:
	extends RefCounted
	var requests = 0
	func complete(_profile: Dictionary, messages: Array, _tools: Array, _model: String, _effort: String, _cancel: Dictionary, delta: Callable) -> Dictionary:
		requests += 1
		var name = ""
		var args = {}
		var phase = {1: "planning", 5: "executing", 7: "verifying", 10: "completed"}.get(requests, "")
		if not phase.is_empty():
			name = "task_update"
			args = {"phase": phase, "tasks": [{"step": "Pregătește nodul scenei", "status": "completed" if requests >= 7 else ("in_progress" if requests == 5 else "pending")}, {"step": "Verifică structura scenei", "status": "completed" if requests == 10 else ("in_progress" if requests == 7 else "pending")}], "explanation": "Două etape dependente; verific scena înainte de finalizare.", "verification": "godot_scene_tree confirms PlannedProbe after creation.", "verification_kind": "inspection"}
		if requests == 3:
			name = "tool_describe"
			args = {"name": "godot_create_node"}
		if requests in [4, 6]:
			name = "godot_create_node"
			args = {"type": "Node3D", "name": "PlannedProbe"}
		if requests == 1: args["criteria"] = [{"id": "node", "description": "The created node is named PlannedProbe", "kind": "inspection", "check": {"pointer": "", "op": "eq", "expected": "PlannedProbe"}}]
		if requests in [8, 9]:
			var found = {}
			for message in messages:
				if message.get("role") == "tool" and message.get("tool_name") == ("godot_create_node" if requests == 8 else "godot_get"): found = JSON.parse_string(str(message.get("content", "{}")))
			name = "godot_get" if requests == 8 else "task_check"
			args = {"handle": found.get("result", {}).get("handle", ""), "property": "name"} if requests == 8 else {"criterion": "node", "evidence": [str(found.get("verification_evidence", {}).get("id", ""))]}
		var calls = [] if name.is_empty() else [{"id": "planning-" + str(requests), "name": name, "arguments": args}]
		var text = ("Plan pregătit." if requests == 2 else "Implementat și verificat.") if name.is_empty() else ""
		if not text.is_empty(): delta.call(text)
		return {"ok": true, "message": {"role": "assistant", "content": text, "tool_calls": calls}, "calls": calls, "finish": "stop"}

class FixtureCompactionProvider:
	extends RefCounted
	var requests = 0
	var messages: Array = []
	var output_limits: Array = []
	var efforts: Array = []
	var replies: Array = []
	var cancel_after_reply = false
	var fail = false
	var summary = "Rezumat fixture: obiectivele, schimbările reale și verificările rămân păstrate."
	func complete(_profile: Dictionary, context: Array, _tools: Array, _model: String, effort: String, cancel: Dictionary, _delta: Callable = Callable(), max_output_tokens: int = 0) -> Dictionary:
		requests += 1
		messages.append(context.duplicate(true))
		output_limits.append(max_output_tokens)
		efforts.append(effort)
		if cancel.get("cancelled", false): return {"ok": false, "code": "cancelled", "error": "Oprit"}
		if fail: return {"ok": false, "error": "Fixture summary failure"}
		if cancel_after_reply: cancel["cancelled"] = true
		if not replies.is_empty(): return replies.pop_front()
		return {"ok": true, "message": {"role": "assistant", "content": summary}}

func _enter_tree() -> void:
	if OS.get_environment("GODOT_AI_QA_SOURCE").is_empty(): return
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	checks += 1
	if checks % 25 == 0 or checks >= 740: print("AI editor verification progress: ", checks, " · ", label)
	if not condition:
		failures.append(label)
		push_error("AI editor verification: " + label)

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning() or EditorInterface.get_resource_filesystem().is_importing(): await get_tree().process_frame
	await get_tree().process_frame
	var directory = OS.get_environment("GODOT_AI_QA_SOURCE")
	var bindings = {"common": "Common", "engineering_store": "EngineeringStore", "qa_scenarios": "QAScenarios", "asset_audit": "AssetAudit", "experiments": "Experiments", "engineering": "Engineering", "project_knowledge": "ProjectKnowledge", "diagnostics": "Diagnostics", "verification": "Verification", "diff": "Diff", "change_set": "ChangeSet", "transport": "Transport", "tool_registry": "ToolRegistry", "model_pricing": "ModelPricing", "providers": "Providers", "panel_reader": "PanelReader", "editor_tools": "Tools", "mcp": "MCP", "asset_exports": "AssetExports", "generation_catalog": "GenerationCatalog", "assets": "Assets", "accounts": "Accounts", "conversations": "Conversations", "icons": "Icons", "planner": "Planner", "markdown": "Markdown", "tool_preview": "ToolPreview", "diagram": "Diagram", "file_registry": "FileRegistry", "model_preview": "ModelPreview", "media_view": "MediaView", "chat_view": "ChatView", "harness": "Harness", "agent_jobs": "AgentJobs", "speech": "Speech", "workspace": "Workspace", "termux_blender": "TermuxBlender", "linux_runtime": "LinuxRuntime", "ziva": "Ziva", "ziva_screen": "ZivaScreen", "integrations": "Integrations", "store": "Store", "editor_control": "EditorControl"}
	for name in ["common", "engineering_store", "qa_scenarios", "asset_audit", "experiments", "engineering", "project_knowledge", "diagnostics", "verification", "diff", "change_set", "transport", "tool_registry", "model_pricing", "providers", "panel_reader", "editor_tools", "mcp", "asset_exports", "generation_catalog", "assets", "accounts", "conversations", "icons", "planner", "markdown", "tool_preview", "diagram", "file_registry", "model_preview", "media_view", "chat_view", "harness", "agent_jobs", "speech", "workspace", "termux_blender", "linux_runtime", "ziva", "ziva_screen", "integrations", "store", "editor_control", "panel"]:
		var script = GDScript.new()
		script.source_code = FileAccess.get_file_as_string(directory.path_join("runtime/" + name + ".gd"))
		var error = script.reload()
		_check(error == OK, "Compile " + name)
		if error != OK:
			get_tree().quit(1)
			return
		for dependency in embedded: script.set(bindings[dependency], embedded[dependency])
		embedded[name] = script
	panel = EditorInterface.get_base_control().find_child("AIAssistantPanel", true, false)
	native = panel != null
	if not native:
		panel = embedded["panel"].new()
		panel.configure(self, FixtureVault.new())
		EditorInterface.get_editor_main_screen().add_child(panel)
	panel.model_pricing.transport = AgentPricingTransport.new()
	EditorInterface.set_main_screen_editor("AI Assistant" if native else "AI Assistant QA")
	await get_tree().process_frame
	_check(panel.profile_picker != null and panel.settings_tabs.get_tab_count() == 13, "Build all settings forms")
	var independent_ziva = EditorInterface.get_editor_main_screen().find_child("ZivaMainScreen", true, false)
	if independent_ziva != null:
		_check(not independent_ziva.management.visible, "The hidden Ziva tab never opens an exclusive management window at startup")
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "planning":
		var planning = load(get_script().resource_path.get_base_dir().path_join("interactive_plan.gd")).new()
		await planning.run(self, panel)
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "scene_paths":
		await _scene_path_tests()
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "chat_lifecycle":
		await _chat_lifecycle_tests()
		await load(get_script().resource_path.get_base_dir().path_join("voice.gd")).new().run(self, panel)
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "inspections":
		var inspections = load(get_script().resource_path.get_base_dir().path_join("chat_inspections.gd")).new()
		await inspections.run(self, panel)
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "presentation":
		var presentation = load(get_script().resource_path.get_base_dir().path_join("chat_presentation.gd")).new()
		await presentation.run(self, panel)
		await _chat_lifecycle_tests()
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "todo":
		var todo = load(get_script().resource_path.get_base_dir().path_join("todo.gd")).new()
		await todo.run(self, panel)
		await _scene_path_tests()
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	await _blender_mesh_verification_tests()
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "startup":
		await _handoff_tests()
		await _generated_preview_tests()
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "approval":
		await _approval_dialog_tests(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "intelligence":
		await _intelligence_editor_tests()
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "debugger":
		await _debugger_editor_tests()
		if native: await _native_debugger_tests()
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "panel_access":
		await _panel_access_tests()
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "changesets":
		await _change_set_editor_tests()
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") in ["engineering", "harness"]:
		if OS.get_environment("GODOT_AI_QA_SCENARIO") == "engineering": await _engineering_editor_tests()
		else:
			var root = Node3D.new()
			root.name = "EngineeringHarnessFixture"
			EditorInterface.add_root_node(root)
			await _harness_editor_tests(root)
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "compact":
		await _auto_compaction_tests()
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "workflow":
		await _workflow_editor_tests()
		await _auto_compaction_tests()
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "chat":
		await _chat_experience_tests()
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "linux":
		await _linux_runtime_tests(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "ziva":
		await _ziva_tests(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "panels":
		await _workspace_panel_tests(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "generation":
		await _generation_catalog_tests(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "providers":
		await _provider_connection_tests(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		await _provider_discovery_tests(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "blender":
		await _termux_blender_card_tests()
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "preview":
		await _model_and_control_tests()
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "activity":
		await _activity_drawer_tests()
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "files":
		await _file_chat_tests()
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "dock":
		await _configuration_screenshots(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "terrain":
		var archive = OS.get_environment("GODOT_AI_TERRAIN3D_ZIP")
		var result = await panel.store.install_zip(archive, {"id": "tokisangames/terrain3d", "name": "Terrain3D"}, "1.0.2", {})
		_check(result.get("ok", false) and result.get("result", {}).get("files", 0) > 0, "Actual Terrain3D release installs its addon files into an isolated editor project")
		_check(FileAccess.file_exists("res://addons/terrain_3d/plugin.cfg") and FileAccess.file_exists("res://addons/terrain_3d/bin/libterrain.android.debug.arm64.so"), "Installed Terrain3D includes plugin manifest and Android ARM64 binary")
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	await _chat_workflow_tests()
	var planning = load(get_script().resource_path.get_base_dir().path_join("interactive_plan.gd")).new()
	await planning.run(self, panel)
	await _approval_dialog_tests("")
	await _intelligence_editor_tests()
	await _panel_access_tests()
	await _change_set_editor_tests()
	await _history_button_tests()
	await _settings_action_tests()
	await _provider_connection_tests("")
	await _generation_catalog_tests("")
	await _provider_discovery_tests("")
	await _linux_runtime_tests("")
	await _ziva_tests("")
	await _workspace_panel_tests("")
	await _handoff_tests()
	await _generated_preview_tests()
	await _layout_tests()
	await _activity_drawer_tests()
	await _control_settings_tests()
	await _auto_compaction_tests()
	_vision_settings_tests()
	await _file_chat_tests()
	await _model_and_control_tests()
	await _store_install_tests()
	await get_tree().process_frame
	_check(panel.chat.thread.size.x >= minf(740 * EditorInterface.get_editor_scale(), panel.chat.scroll.size.x - 40 * EditorInterface.get_editor_scale()), "Chat column uses the available readable width")
	_check(panel.chat.thread.size.x <= 760 * EditorInterface.get_editor_scale() + 1, "Chat column stays within 760 logical pixels")
	var history_requested = panel.chat.history_requested
	var wide_history = panel.chat.size.x / EditorInterface.get_editor_scale() >= 900
	_check(panel.chat.sidebar.visible == (wide_history if history_requested < 0 else history_requested == 1), "History sidebar respects the explicit user visibility selection")
	panel.chat.history_requested = -1
	panel.chat._resize()
	await get_tree().process_frame
	_check(panel.chat.sidebar.visible == (panel.chat.size.x / EditorInterface.get_editor_scale() >= 900), "Automatic history visibility responds to available workspace width")
	panel.chat.history_requested = history_requested
	panel.chat._resize()
	var scene = EditorInterface.get_edited_scene_root()
	if scene == null:
		scene = Node3D.new()
		scene.name = "AITestRoot"
		EditorInterface.add_root_node(scene)
	await get_tree().process_frame
	await _harness_editor_tests(scene)
	await _code_tool_tests()
	_reflection_tool_tests(scene)
	var toolset = panel.tools
	var created = toolset.execute("godot_create_node", {"type": "Node3D", "name": "AIProbe"}, 2, true)
	_check(created.get("ok", false), "Create scene node")
	var probe = scene.get_node_or_null("AIProbe")
	_check(probe != null, "Created node exists in live scene")
	if probe != null:
		var handle = str(created["result"]["handle"])
		var set_result = toolset.execute("godot_set", {"handle": handle, "property": "position", "value": {"$type": "Vector3", "value": [1, 2, 3]}}, 2, true)
		_check(set_result.get("ok", false) and probe.position == Vector3(1, 2, 3), "Set typed scene property")
		toolset.execute("godot_undo", {}, 2, true)
		_check(probe.position == Vector3.ZERO, "Undo scene property")
		toolset.execute("godot_redo", {}, 2, true)
		_check(probe.position == Vector3(1, 2, 3), "Redo scene property")
		var written = toolset.execute("godot_write_file", {"path": "res://ai_test_probe.gd", "text": "@tool\nextends Node3D\nvar counter = 0\nvar held: bool:\n\tget: return Input.is_action_pressed(\"ui_accept\")\nfunc _ready():\n\tRenderingServer.set_default_clear_color(Color(0.2, 0.1, 0.4))\nfunc _input(event):\n\tif event.is_action_pressed(\"ui_accept\"): counter += 1\nfunc fixture_method():\n\treturn 42\n"}, 2, true)
		_check(written.get("ok", false), "Write project script with recovery journal")
		await get_tree().process_frame
		while EditorInterface.get_resource_filesystem().is_scanning(): await get_tree().process_frame
		var attached = toolset.execute("godot_attach_script", {"path": "AIProbe", "script": "res://ai_test_probe.gd"}, 2, true)
		_check(attached.get("ok", false) and probe.has_method("fixture_method"), "Attach project script")
		var called = toolset.execute("godot_call", {"handle": handle, "method": "fixture_method", "arguments": []}, 2, true)
		_check(called.get("ok", false) and called.get("result") == 42, "Call a script-defined method")
		var scene_result = toolset.execute("godot_save_scene", {"path": "res://ai_test_scene.tscn"}, 2, true)
		_check(scene_result.get("ok", false) and scene_result.get("result", {}).get("saved", false), "Save live scene")
		var before = FileAccess.get_file_as_string("res://ai_test_probe.gd")
		var changed = toolset.execute("godot_write_file", {"path": "res://ai_test_probe.gd", "text": before + "\n# temporary fixture edit\n"}, 2, true)
		var restored = toolset.execute("godot_restore_file", {"index": changed.get("result", {}).get("recovery_index", -1)}, 2, true)
		_check(restored.get("ok", false) and FileAccess.get_file_as_string("res://ai_test_probe.gd") == before, "Restore previous file bytes")
	# Check grouped rollback and conflicts against real editor state, not just a mock.
	if probe != null:
		toolset.turn_id = "fixture-restore"
		toolset.execute("godot_set", {"handle": str(created["result"]["handle"]), "property": "position", "value": {"$type": "Vector3", "value": [9, 8, 7]}}, 2, true)
		toolset.execute("godot_write_file", {"path": "res://ai_restore_probe.txt", "text": "AI content"}, 2, true)
		var manual = FileAccess.open("res://ai_restore_probe.txt", FileAccess.WRITE)
		manual.store_string("Manual content")
		manual.close()
		var conflict = toolset.restore_turn("fixture-restore")
		_check(conflict.get("code") == "restore_conflict" and probe.position == Vector3(9, 8, 7), "Rollback conflict preserves manual bytes and scene")
		manual = FileAccess.open("res://ai_restore_probe.txt", FileAccess.WRITE)
		manual.store_string("AI content")
		manual.close()
		var rollback = toolset.restore_turn("fixture-restore")
		_check(rollback.get("ok", false) and not FileAccess.file_exists("res://ai_restore_probe.txt") and probe.position == Vector3(1, 2, 3), "Grouped rollback restores file and native scene Undo")
		toolset.turn_id = ""
	if native:
		await _native_runtime_tests()
		await _native_debugger_tests()
		hide_bottom_panel()
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "all":
		var inspections = load(get_script().resource_path.get_base_dir().path_join("chat_inspections.gd")).new()
		await inspections.run(self, panel)
		var presentation = load(get_script().resource_path.get_base_dir().path_join("chat_presentation.gd")).new()
		await presentation.run(self, panel)
		await _chat_lifecycle_tests()
		await load(get_script().resource_path.get_base_dir().path_join("voice.gd")).new().run(self, panel)
	await _populated_chat_tests()
	var output = OS.get_environment("GODOT_AI_QA_OUTPUT")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		await get_tree().create_timer(0.5).timeout
		var image = EditorInterface.get_base_control().get_viewport().get_texture().get_image()
		_check(image != null and not image.is_empty(), "Render editor panel")
		if image != null and not image.is_empty(): image.save_png(output.path_join("editor-panel.png"))
		panel.chat.follow_bottom = true
		panel.chat._follow()
		await get_tree().create_timer(0.2).timeout
		image = EditorInterface.get_base_control().get_viewport().get_texture().get_image()
		if image != null and not image.is_empty(): image.save_png(output.path_join("conversation-bottom.png"))
		panel.open_settings("providers")
		await get_tree().create_timer(0.5).timeout
		print("AI settings dimensions: ", panel.settings_window.size)
		_check(panel.settings_window.size.y <= DisplayServer.screen_get_size().y, "Settings dialog fits the display height")
		_check(panel.settings_window.size.x <= DisplayServer.screen_get_size().x, "Settings dialog fits the display width")
		image = panel.settings_window.get_texture().get_image()
		if image != null and not image.is_empty(): image.save_png(output.path_join("settings.png"))
		panel.open_settings("accounts")
		await get_tree().create_timer(0.2).timeout
		image = panel.settings_window.get_texture().get_image()
		if image != null and not image.is_empty(): image.save_png(output.path_join("accounts-chatgpt.png"))
		panel.account_service.select(1)
		panel._select_account_service()
		await get_tree().create_timer(0.2).timeout
		image = panel.settings_window.get_texture().get_image()
		if image != null and not image.is_empty(): image.save_png(output.path_join("accounts-claude.png"))
		panel.account_service.select(0)
		panel._select_account_service()
		panel.open_settings("generation")
		await get_tree().create_timer(0.3).timeout
		image = panel.settings_window.get_texture().get_image()
		if image != null and not image.is_empty(): image.save_png(output.path_join("generation.png"))
		for provider_index in [2, 3, 4]:
			panel.forms["generation"]["kind"].select(provider_index)
			panel._generation_fields(provider_index, panel.forms["generation"]["workflow_fields"], true)
			await get_tree().create_timer(0.2).timeout
			image = panel.settings_window.get_texture().get_image()
			if image != null and not image.is_empty(): image.save_png(output.path_join("generation-" + panel.Assets.KINDS[provider_index] + ".png"))
		panel.settings_window.hide()
		panel.chat._open_options()
		await get_tree().create_timer(0.2).timeout
		image = panel.chat.runtime_options.get_texture().get_image()
		if image != null and not image.is_empty(): image.save_png(output.path_join("chat-options.png"))
		panel.chat.runtime_options.hide()
		await _drawer_screenshots(output)
		await _plan_and_markdown_screenshots(output)
		await _configuration_screenshots(output)
	await _chat_experience_tests()
	_finish_report(output)

func _chat_lifecycle_tests() -> void:
	var chat = panel.chat
	chat.clear_messages()
	for index in 30: chat.append_message("assistant", "Mesaj %d\nConținut pentru testul de derulare.\nÎncă un rând de text." % index, {"id": "scroll-" + str(index)})
	await get_tree().create_timer(0.3).timeout
	chat._jump_to_latest()
	await get_tree().create_timer(0.1).timeout
	_check(chat.follow_bottom and not chat.latest_button.visible, "New conversation follows the latest message")
	var bar = chat.scroll.get_v_scroll_bar()
	_check(bar.max_value > bar.page + 200, "Scroll fixture has a real overflowing conversation")
	var point = chat.scroll.get_global_rect().get_center()
	var touch = InputEventScreenTouch.new()
	touch.index = 9
	touch.position = point
	touch.pressed = true
	chat._chat_touch(touch)
	var drag = InputEventScreenDrag.new()
	drag.index = 9
	drag.position = point + Vector2(0, 140)
	chat._chat_touch(drag)
	touch.pressed = false
	touch.position = drag.position
	chat._chat_touch(touch)
	var position = chat.scroll.scroll_vertical
	_check(not chat.follow_bottom and chat.latest_button.visible, "Upward history browsing reveals the jump-to-latest arrow")
	chat.append_message("assistant", "Mesaj nou în timpul citirii istoricului", {"id": "scroll-new"})
	await get_tree().create_timer(0.15).timeout
	_check(not chat.follow_bottom and chat.scroll.scroll_vertical == position, "Incoming message preserves the reader's position")
	var stream = chat.append_message("assistant", "")
	chat.stream_text(stream, "Răspuns în streaming\n".repeat(12))
	await get_tree().create_timer(0.2).timeout
	_check(not chat.follow_bottom and chat.scroll.scroll_vertical == position, "Streaming growth cannot pull the reader to the bottom")
	chat.latest_button.pressed.emit()
	await get_tree().create_timer(0.1).timeout
	_check(chat.follow_bottom and not chat.latest_button.visible and absf(bar.value - (bar.max_value - bar.page)) < 2, "Arrow jumps to the latest message and resumes following")
	chat.append_message("assistant", "Următorul mesaj\n".repeat(8), {"id": "scroll-follow"})
	await get_tree().create_timer(0.15).timeout
	_check(chat.follow_bottom and absf(bar.value - (bar.max_value - bar.page)) < 2, "Following survives content-height changes")
	var wheel = InputEventMouseButton.new()
	wheel.position = point
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	chat._input(wheel)
	await get_tree().process_frame
	_check(not chat.follow_bottom and chat.latest_button.visible, "Mouse-wheel history browsing also detaches following")
	_check(chat.scroll.get_global_rect().encloses(chat.latest_button.get_global_rect()), "Latest-message arrow fits inside the conversation")
	_workspace_capture(OS.get_environment("GODOT_AI_QA_OUTPUT"), "chat-history-arrow")
	chat._jump_to_latest()
	chat.composer.text = "Mesaj pe mai multe rânduri, vizibil în timpul scrierii.\n".repeat(8)
	chat.composer.set_caret_line(chat.composer.get_line_count() - 1)
	chat.composer.grab_focus()
	var free_below = maxf(0, chat.get_viewport_rect().size.y - chat.get_global_rect().end.y)
	var scale_y = chat.get_viewport().get_screen_transform().get_scale().y
	chat._update_keyboard_inset((260 + free_below) * scale_y)
	await get_tree().create_timer(0.2).timeout
	_check(chat.keyboard_spacer.visible and is_equal_approx(chat.keyboard_spacer.size.y, 260), "Keyboard occlusion is converted to a real layout inset")
	_check(chat.composer.get_global_rect().end.y <= chat.get_viewport_rect().size.y - 260 + 2, "Multiline input remains entirely above the simulated keyboard")
	_check(chat.composer.size.y <= chat.composer.custom_maximum_size.y + 2, "Long drafts scroll within the available composer height")
	_check(chat.composer.get_caret_draw_pos().y <= chat.composer.size.y + 2, "Draft caret stays visible above the keyboard after scrolling to the last line")
	_workspace_capture(OS.get_environment("GODOT_AI_QA_OUTPUT"), "chat-keyboard-inset")
	chat._update_keyboard_inset(0)
	await get_tree().create_timer(0.1).timeout
	_check(not chat.keyboard_spacer.visible and chat.keyboard_spacer.custom_minimum_size.y == 0, "Keyboard dismissal restores the full conversation area")
	chat.composer.clear()
	chat.clear_messages()
	var registry = embedded["file_registry"].new()
	registry.configure("user://capture-retention-qa", false)
	var image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	var capture = registry.register_capture({"name": "game.png", "mimeType": "image/png", "data": Marshalls.raw_to_base64(image.save_png_to_buffer())}, "qa")
	var id = str(capture.get("result", {}).get("id", ""))
	_check(capture.get("ok", false) and FileAccess.file_exists(capture["result"]["path"]), "Automatic capture is saved in its dedicated cache")
	var duplicate = registry.register_capture({"name": "game.png", "mimeType": "image/png", "data": Marshalls.raw_to_base64(image.save_png_to_buffer())}, "qa")
	_check(duplicate.get("result", {}).get("id") == id and registry.entries.size() == 1, "Identical frames reuse one cached image and thumbnail")
	registry.pin(id, "qa", true)
	registry.prune_captures(Time.get_unix_time_from_system() + 90000)
	_check(registry.describe(id, "qa").get("available", false), "Pinned screenshot survives automatic expiry")
	var previous_registry = chat.file_registry
	var previous_scope = chat.file_scope
	chat.file_registry = registry
	chat.file_scope = "qa"
	registry.captures_expired.connect(chat.expire_capture_cards)
	var card = chat._file_card(chat.thread, id)
	registry.pin(id, "qa", false)
	chat.sync_file_pins(id)
	_check(card.get_child(0).get_node("CaptureRetention").text.contains("temporară"), "Changing the pin updates the capture retention caption immediately")
	registry.prune_captures(Time.get_unix_time_from_system() + 90000)
	_check(not registry.describe(id, "qa").get("available", true) and registry.describe(id, "qa").get("capture_expired", false), "Unpinned screenshot expires after 24 hours while its card metadata survives")
	_check(card.get_child(0).get_node_or_null("FileThumbnail") == null and card.get_child(0).get_node("CaptureRetention").text.contains("expirată"), "Expiry also releases the visible thumbnail from memory and labels the card")
	chat.clear_messages()
	chat.file_registry = previous_registry
	chat.file_scope = previous_scope
	var original = "user://original-user-attachment.png"
	image.save_png(original)
	registry.permit(original)
	var attachment = registry.register_file(original, "qa")
	var tool_asset = registry.register_capture({"name": "generated-external.png", "mimeType": "image/png", "data": Marshalls.raw_to_base64(image.save_png_to_buffer())}, "qa", false)
	var latest_capture = {}
	for index in 66:
		image.fill(Color(float(index) / 70.0, 0.5, 0.3))
		latest_capture = registry.register_capture({"name": "editor-editor.png", "mimeType": "image/png", "data": Marshalls.raw_to_base64(image.save_png_to_buffer())}, "qa")
	_check(registry.catalog("qa").filter(func(item: Dictionary) -> bool: return item.get("available", false)).size() <= 64 and DirAccess.get_files_at(registry.directory.path_join("captures")).size() == 128, "Capture cache keeps at most 64 unpinned images with their thumbnails")
	registry.entries[latest_capture["result"]["id"]]["cache_bytes"] = registry.CAPTURE_MAX_BYTES + 1
	registry.prune_captures()
	_check(not FileAccess.file_exists(latest_capture["result"]["path"]), "Capture byte budget is enforced independently of the image-count limit")
	registry.prune_captures(Time.get_unix_time_from_system() + 90000)
	_check(FileAccess.file_exists(original) and registry.describe(str(attachment.get("result", {}).get("id", "")), "qa").get("available", false), "Automatic cleanup preserves user originals and ordinary attachment snapshots")
	_check(FileAccess.file_exists(tool_asset.get("result", {}).get("path", "")) and not tool_asset["result"].get("temporary_capture", true), "Images returned by generation or external tools are not mistaken for temporary screenshots")
	var scene_path = "res://qa_lifecycle.tscn"
	var scene_file = FileAccess.open(scene_path, FileAccess.WRITE)
	scene_file.store_string("[gd_scene format=3]\n[node name=\"LifecycleProbe\" type=\"Node\"]\n")
	scene_file.close()
	panel.tools.turn_id = "lifecycle-qa"
	var launched = panel.tools.execute("godot_run", {"scene": scene_path}, 2, true)
	await get_tree().create_timer(1.0).timeout
	_check(launched.get("ok", false) and panel.tools.play_owner == "lifecycle-qa" and EditorInterface.is_playing_scene(), "Agent owns the temporary game it actually launched")
	var reused = panel.tools.execute("godot_run", {"scene": scene_path}, 2, true)
	_check(reused.get("result", {}).get("reused", false) and not reused["result"]["requested"], "Repeated run of the same scene reuses the live session")
	var stopped = panel.tools.finish_playtest("lifecycle-qa")
	_check(stopped.get("stopped", false) and not EditorInterface.is_playing_scene(), "Turn completion closes an agent-owned temporary game")
	EditorInterface.play_custom_scene(scene_path)
	await get_tree().create_timer(0.2).timeout
	panel.tools.execute("godot_run", {"scene": scene_path}, 2, true)
	_check(not panel.tools.finish_playtest("lifecycle-qa").get("stopped", false) and EditorInterface.is_playing_scene(), "Reusing a user-started game never grants cleanup ownership")
	panel.tools.execute("godot_run", {"scene": scene_path, "restart": true, "keep_open": true}, 2, true)
	_check(not panel.tools.finish_playtest("lifecycle-qa").get("stopped", false) and EditorInterface.is_playing_scene(), "Explicit keep-open request preserves the game at turn completion")
	EditorInterface.stop_playing_scene()
	panel.tools.execute("godot_run", {"scene": scene_path}, 2, true)
	EditorInterface.stop_playing_scene()
	EditorInterface.play_custom_scene(scene_path)
	_check(not panel.tools.finish_playtest("lifecycle-qa").get("stopped", false) and EditorInterface.is_playing_scene(), "Manual restart of the same scene transfers ownership back to the user")
	EditorInterface.stop_playing_scene()
	panel.tools.execute("godot_run", {"scene": scene_path, "keep_open": true}, 2, true)
	_check(panel.tools.finish_playtest("lifecycle-qa", true).get("stopped", false) and not EditorInterface.is_playing_scene(), "Cancelling closes the agent's current game even if keep-open was requested")
	panel.tools.execute("godot_run", {"scene": scene_path}, 2, true)
	panel.agent_jobs._finish({"id": "child-lifecycle-qa", "parent": "lifecycle-qa", "kind": "Playtest", "task": "Fixture", "steps": 0, "started_game": true}, "blocked", "Fixture runtime bridge unavailable")
	_check(not EditorInterface.is_playing_scene() and panel.tools.play_owner.is_empty(), "Playtest child cleanup also runs when an early prerequisite fails")
	EditorInterface.stop_playing_scene()
	panel.tools._release_playback()

func _scene_path_tests() -> void:
	var scene = EditorInterface.get_edited_scene_root()
	if scene == null:
		scene = Node3D.new()
		scene.name = "ScenePathProbe"
		EditorInterface.add_root_node(scene)
	await get_tree().process_frame
	var child = Node3D.new()
	child.name = "ProbeChild"
	scene.add_child(child)
	child.owner = scene
	var target = "res://qa_scene_paths/Area One/scenes/forest.tscn"
	_check(not DirAccess.dir_exists_absolute(target.get_base_dir()), "Scene destination starts with missing parent directories")
	var saved = panel.tools.execute("godot_save_scene", {"path": target}, 2, true)
	_check(saved.get("ok", false) and saved.get("result", {}).get("saved", false), "Save scene creates nested parents and confirms success")
	_check(saved.get("result", {}).get("path") == target and FileAccess.file_exists(target), "Scene result retains the exact destination with spaces")
	var project = panel.tools.execute("godot_project", {}, 0, false).get("result", {})
	_check(project.get("scene_path") == target, "Current project reports the actual saved scene path")
	_check(project.get("recent_paths", []).has(target), "Saved scene path remains discoverable through the recovery-backed project history")
	var reloaded_tools = embedded["editor_tools"].new()
	reloaded_tools.file_changes = embedded["common"].read_json(panel.tools.backup_directory.path_join("journal.json"), [])
	_check(reloaded_tools.execute("godot_project", {}, 0, false).get("result", {}).get("recent_paths", []).has(target), "A fresh toolset recovers saved paths from the persisted project journal")
	panel._new_conversation()
	var fresh_context = panel._context_messages()
	_check(not fresh_context.is_empty() and str(fresh_context[0].get("content", "")).contains(target), "A new conversation receives the actual saved scene path in its project context")
	var packed = ResourceLoader.load(target, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) if FileAccess.file_exists(target) else null
	_check(packed is PackedScene and packed.can_instantiate(), "Saved scene is a loadable PackedScene")
	if packed is PackedScene:
		var instance = packed.instantiate()
		_check(instance.has_node("ProbeChild"), "Saved scene contains its owned child after a fresh load")
		instance.free()
	var repeated = panel.tools.execute("godot_save_scene", {"path": target}, 2, true)
	_check(repeated.get("ok", false) and repeated.get("result", {}).get("path") == target, "Repeated save reuses the same destination")
	var files = DirAccess.get_files_at(target.get_base_dir())
	_check(Array(files).filter(func(name: String) -> bool: return name.ends_with(".tscn")).size() == 1, "Repeated save creates no alternative scene copy")
	var blocked_path = "res://qa_scene_blocked_parent"
	var blocker = FileAccess.open(blocked_path, FileAccess.WRITE)
	blocker.store_string("KEEP_BLOCKED_PARENT")
	blocker.close()
	var previous_path = scene.scene_file_path
	var rejected = panel.tools.execute("godot_save_scene", {"path": blocked_path + "/other.tscn"}, 2, true)
	_check(not rejected.get("ok", true) and rejected.get("code") == "directory_create_failed", "A parent that is a file returns an explicit save failure")
	_check(not rejected.get("result", {}).get("saved", true), "A failed save never reports success with saved=false")
	_check(FileAccess.get_file_as_string(blocked_path) == "KEEP_BLOCKED_PARENT" and scene.scene_file_path == previous_path, "Failed destination preserves existing bytes and the current scene path")
	DirAccess.make_dir_recursive_absolute("res://qa_scene_target.tscn")
	var directory_target = panel.tools.execute("godot_save_scene", {"path": "res://qa_scene_target.tscn"}, 2, true)
	_check(not directory_target.get("ok", true) and directory_target.get("code") == "invalid_path", "A directory named like a scene is rejected without saving")
	var invalid = panel.tools.execute("godot_save_scene", {"path": "res://../escape.tscn"}, 2, true)
	_check(not invalid.get("ok", true), "Scene parent creation still rejects traversal paths")
	if FileAccess.file_exists(target):
		var opened = panel.tools.execute("godot_open_scene", {"path": target}, 2, true)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(opened.get("ok", false) and EditorInterface.get_edited_scene_root().scene_file_path == target, "Reopen uses the exact path returned by save")
	var missing = panel.tools.execute("godot_open_scene", {"path": "res://qa_scene_paths/wrong/forest.tscn"}, 2, true)
	_check(not missing.get("ok", true) and missing.get("code") == "scene_not_found", "Missing scene reports its location failure instead of selecting another folder")
	_check(not DirAccess.dir_exists_absolute("res://qa_scene_paths/wrong"), "Opening a missing scene creates no replacement directory")

func _finish_report(output: String) -> void:
	print("Godot AI editor: %s checks, %s failures" % [checks, failures.size()])
	if not output.is_empty():
		var file = FileAccess.open(output.path_join("editor-report.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
	get_tree().quit(0 if failures.is_empty() else 1)

func _exit_tree() -> void:
	if is_instance_valid(panel) and not native: panel.queue_free()

func _rpc(command: String, args: Dictionary = {}) -> Dictionary:
	var id = panel.plugin.runtime_request(command, args)
	if id < 0: return {"ok": false, "error": "No debugger session"}
	var deadline = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		var result = panel.plugin.runtime_poll(id)
		if not result.is_empty(): return result
		await get_tree().process_frame
	return {"ok": false, "error": "RPC timeout"}

func _native_runtime_tests() -> void:
	_check(panel.get_script().is_built_in() and panel.get_script().resource_path.begins_with("local://"), "Embedded scripts remain internal when saving a scene")
	var ai_button: Button
	var asset_button: Button
	for node in EditorInterface.get_base_control().find_children("*", "Button", true, false):
		if node.text == "AI Assistant": ai_button = node
		if node.text == "Asset Store": asset_button = node
	_check(ai_button != null and asset_button != null and ai_button.get_parent() == asset_button.get_parent() and ai_button.get_index() == asset_button.get_index() + 1, "Native AI tab is immediately after Asset Store")
	_check(panel.vault.store("qa-secret", "fixture-vault-test") and panel.vault.read("qa-secret") == "fixture-vault-test", "Native encrypted desktop credential store round trip")
	_check(panel.vault.erase("qa-secret") and panel.vault.read("qa-secret").is_empty(), "Native credential store erases test secret")
	EditorInterface.play_current_scene()
	var state = {}
	for attempt in range(40):
		await get_tree().create_timer(0.25).timeout
		state = await _rpc("status")
		if state.get("ok", false): break
	_check(state.get("ok", false), "Native debugger connects to running game")
	if state.get("ok", false):
		var frame = await _rpc("screenshot")
		var image = Image.new()
		var bytes = Marshalls.base64_to_raw(str(frame.get("result", {}).get("data", "")))
		_check(frame.get("ok", false) and image.load_png_from_buffer(bytes) == OK, "Capture actual game viewport through native debugger")
		if not image.is_empty(): image.save_png(OS.get_environment("GODOT_AI_QA_OUTPUT").path_join("game-viewport.png"))
		var before = await _rpc("inspect", {"path": "AIProbe", "properties": ["counter", "held"]})
		var sent = await _rpc("input", {"kind": "action", "action": "ui_accept"})
		await get_tree().create_timer(0.2).timeout
		var after = await _rpc("inspect", {"path": "AIProbe", "properties": ["counter", "held"]})
		_check(sent.get("ok", false) and after.get("result", {}).get("properties", {}).get("counter", 0) > before.get("result", {}).get("properties", {}).get("counter", 0), "Playtest input reaches the running game's script")
		await get_tree().create_timer(2.5).timeout
		var released = await _rpc("inspect", {"path": "AIProbe", "properties": ["held"]})
		_check(released.get("ok", false) and released.get("result", {}).get("properties", {}).get("held") == false, "Native watchdog releases held game input")
		var monitors = panel.tools.execute("godot_panel_data", {"section": "monitors", "limit": 3}, 0, false)
		_check(monitors.get("result", {}).get("collected", false) and not monitors.get("result", {}).get("items", []).is_empty(), "Native Monitors returns real samples from the running game")
		if not monitors.get("result", {}).get("items", []).is_empty():
			var history = panel.tools.execute("godot_panel_data", {"section": "monitors", "monitor": str(monitors["result"]["items"][0]["name"]), "limit": 2}, 0, false)
			_check(history.get("result", {}).get("collected", false) and history["result"].get("order") == "oldest_first" and not history["result"].get("items", []).is_empty(), "Native monitor history exposes retained measured samples in stable append order")
		var profilers = EditorInterface.get_base_control().find_children("*", "EditorProfiler", true, false)
		var start: BaseButton
		if not profilers.is_empty():
			for button in profilers[0].find_children("*", "Button", true, false):
				if button.toggle_mode and button.text in ["Start", "Stop"]:
					start = button
					break
		_check(start != null, "Native profiler sampling control is discoverable")
		if start != null:
			start.button_pressed = true
			start.emit_signal("pressed")
			var profile = {}
			var deadline = Time.get_ticks_msec() + 8000
			while Time.get_ticks_msec() < deadline:
				await get_tree().create_timer(0.2).timeout
				profile = panel.tools.execute("godot_panel_data", {"section": "profiler", "limit": 1}, 0, false)
				if profile.get("result", {}).get("collected", false): break
			_check(profile.get("result", {}).get("collected", false) and profile["result"].get("units") == "seconds", "Native Profiler returns an actual collected frame with explicit units")
			if profile.get("result", {}).get("collected", false):
				var next = panel.tools.execute("godot_panel_data", {"section": "profiler", "frame": int(profile["result"]["frame"]), "offset": 1, "limit": 1}, 0, false)
				_check(next.get("result", {}).get("frame") == profile["result"]["frame"] and not next.get("result", {}).get("items", []).is_empty(), "Profiler pages can address the same retained frame while new frames arrive")
			start.button_pressed = false
			start.emit_signal("pressed")
	EditorInterface.stop_playing_scene()
	await get_tree().create_timer(0.4).timeout

func _fixture_approval(name: String, results: Dictionary, operation_cancel: Dictionary = {}) -> void:
	results[name] = await panel._authorize({"name": name, "risk": "write"}, {}, operation_cancel)

func _debugger_editor_tests() -> void:
	var bridge = FixtureDebuggerBridge.new()
	add_child(bridge)
	var event = {"message": "AI_SIMULATED_HIDDEN_DEBUGGER", "severity": "error", "path": "res://fixture.gd", "line": 8, "function": "_ready", "session": 0, "generation": 2, "active": false, "stack": [{"path": "res://fixture.gd", "line": 8, "function": "_ready"}]}
	bridge.data = {"available": true, "errors": 1, "warnings": 0, "events": [event], "sessions": [{"session": 0, "generation": 2, "active": false, "has_session": true}], "truncated": false}
	var toolset = embedded["editor_tools"].new(bridge, panel)
	var snapshot = toolset.execute("godot_debugger", {}, 0, false)
	_check(snapshot.get("ok", false) and snapshot["result"]["events"][0]["stack"][0]["line"] == 8, "Simulated native adapter returns stopped Debugger errors with structured stacks")
	var output = toolset.execute("godot_output", {}, 0, false)
	_check(output.get("ok", false) and "AI_SIMULATED_HIDDEN_DEBUGGER" in "\n".join(output.get("result", [])) and output.get("coverage", {}).get("debugger_available", false), "Console tool includes native adapter errors independently of visible labels")
	_check(output.get("debugger", {}).get("errors") == 1 and not output.get("coverage", {}).get("empty_console_proves_clean", true), "Console response retains structured counts and rejects empty-console clean inference")
	var missing = embedded["editor_tools"].new(self, panel)
	_check(missing.execute("godot_debugger", {}, 0, false).get("code") == "debugger_unavailable", "An editor without the native bridge explicitly reports unavailable Debugger access")
	bridge.data["truncated"] = true
	_check(toolset.execute("godot_output", {}, 0, false).get("coverage", {}).get("debugger_truncated", false), "Console coverage preserves a native truncated list")
	bridge.queue_free()

func _panel_access_tests() -> void:
	_check(panel._running_tool_label("godot_panel_data", {"section": "profiler"}) == "Running Profiler Reader Tool", "Running Tools identifies the panel data source being read")
	var host = VBoxContainer.new()
	host.name = "QAHiddenPluginPanel"
	EditorInterface.get_base_control().add_child(host)
	var tree = Tree.new()
	tree.name = "CachedTree"
	tree.columns = 2
	host.add_child(tree)
	var root = tree.create_item()
	var branch = tree.create_item(root)
	branch.set_text(0, "Collapsed branch")
	branch.collapsed = true
	var leaf = tree.create_item(branch)
	leaf.set_text(0, "Hidden child")
	leaf.set_text(1, "A".repeat(1500) + "TAIL")
	host.hide()
	var catalog = panel.tools.execute("godot_panels", {"filter": "QAHiddenPluginPanel", "limit": 1}, 0, false)
	_check(catalog.get("ok", false) and catalog["result"]["total"] >= 2 and catalog["result"]["next_offset"] == 1, "Panel inventory discovers hidden plugin controls and provides a continuation cursor")
	var handle = str(panel.tools._encode(tree)["handle"])
	var scoped = panel.tools.execute("godot_panels", {"handle": handle, "limit": 2}, 0, false)
	_check(scoped.get("result", {}).get("collection", {}).get("root_handle") == handle, "Panel inventory can narrow discovery to one known subtree")
	var observed = panel.tools.execute("godot_panel_read", {"handle": handle, "limit": 1}, 0, false)
	_check(observed.get("ok", false) and observed["result"]["total"] == 3 and observed["result"]["next_offset"] == 1, "Read-only editor tool sees rows below collapsed hidden branches")
	var snapshot = str(observed["result"]["snapshot"])
	var detail = panel.tools.execute("godot_panel_read", {"snapshot": snapshot, "item": 2, "column": 1, "text_offset": 1498, "text_limit": 10}, 0, false)
	_check(detail.get("ok", false) and detail["result"]["text"]["value"] == "AATAIL" and detail["result"]["selected_item"] == 2, "Long hidden cell text remains accessible through snapshot item/column pagination")
	_check(not host.visible and branch.collapsed, "Panel tools leave visibility and tree expansion unchanged")
	var inventory = panel.tools.execute("godot_panels", {"filter": "Inspector", "limit": 5}, 0, false)
	_check(inventory.get("ok", false) and inventory["result"]["total"] > 0, "Real editor Inspector controls are discoverable without selecting the dock")
	for section in ["output", "profiler", "visual_profiler", "monitors", "vram", "stack", "variables", "threads", "breakpoints"]:
		var native_data = panel.tools.execute("godot_panel_data", {"section": section, "limit": 2}, 0, false)
		if native:
			_check(native_data.get("ok", false) and native_data.get("result", {}).get("available", false), "Native cached panel source is accessible: " + section)
		else:
			_check(native_data.get("code") == "panel_data_unavailable", "Stock editor explicitly reports missing native source: " + section)
	var list = ItemList.new()
	list.add_item("One")
	list.add_item("Two")
	list.select(1)
	host.add_child(list)
	var selected = panel.tools.execute("godot_panel_read", {"handle": str(panel.tools._encode(list)["handle"])}, 0, false)
	_check(selected.get("result", {}).get("items", []).size() == 2 and selected["result"]["items"][1]["selected"], "Editor list snapshots retain selection while staying read-only")
	for section in ["inspector", "selection", "audio_buses"]:
		var observed_public = panel.tools.execute("godot_panel_data", {"section": section, "limit": 2}, 0, false)
		_check(observed_public.get("ok", false) and observed_public["result"].get("available", false), "Public editor panel source is readable: " + section)
	var player = AnimationPlayer.new()
	host.add_child(player)
	var library = AnimationLibrary.new()
	var animation = Animation.new()
	var track = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath(".:position"))
	animation.track_insert_key(track, 0.0, Vector2.ZERO)
	animation.track_insert_key(track, 1.0, Vector2.ONE)
	library.add_animation("clip", animation)
	player.add_animation_library("", library)
	var player_handle = str(panel.tools._encode(player)["handle"])
	var animated = panel.tools.execute("godot_panel_data", {"section": "animation", "handle": player_handle, "animation": "clip", "track": 0, "offset": 1, "limit": 1}, 0, false)
	_check(animated.get("ok", false) and animated["result"]["total"] == 2 and animated["result"]["items"][0]["time"] == 1.0 and not player.is_playing(), "Animation keys are paged from the real resource without starting playback")
	var data = {"inventory": catalog, "tree": observed, "cell": detail, "native": native}
	panel.Common.atomic_json(OS.get_environment("GODOT_AI_QA_OUTPUT").path_join("panel-access.json"), data)
	host.free()

func _native_debugger_tests() -> void:
	# Real remote-game errors: no simulation and no dependency on the AI runtime RPC.
	var script_path = "res://ai_test_debugger_errors.gd"
	var scene_path = "res://ai_test_debugger_errors.tscn"
	var clean_path = "res://ai_test_debugger_clean.tscn"
	var file = FileAccess.open(script_path, FileAccess.WRITE)
	file.store_string('extends Node\nfunc _ready():\n\tpush_error("AI_NATIVE_DEBUGGER_ERROR")\n\tpush_warning("AI_NATIVE_DEBUGGER_WARNING")\n')
	file.close()
	file = FileAccess.open(scene_path, FileAccess.WRITE)
	file.store_string('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://ai_test_debugger_errors.gd" id="1"]\n[node name="DebuggerProbe" type="Node"]\nscript = ExtResource("1")\n')
	file.close()
	file = FileAccess.open(clean_path, FileAccess.WRITE)
	file.store_string('[gd_scene format=3]\n[node name="CleanDebuggerProbe" type="Node"]\n')
	file.close()
	EditorInterface.get_resource_filesystem().scan()
	await get_tree().process_frame
	while EditorInterface.get_resource_filesystem().is_scanning(): await get_tree().process_frame
	var docks = EditorInterface.get_base_control().find_children("*", "EditorDebuggerNode", true, false)
	var was_visible = not docks.is_empty() and docks[0].visible
	if not docks.is_empty(): docks[0].hide()
	EditorInterface.play_custom_scene(scene_path)
	var observed = {}
	var errors = []
	var deadline = Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.1).timeout
		if not docks.is_empty(): docks[0].hide()
		observed = panel.tools.execute("godot_debugger", {}, 0, false)
		errors = observed.get("result", {}).get("events", []).filter(func(item: Dictionary) -> bool: return str(item.get("message", "")).contains("AI_NATIVE_DEBUGGER_"))
		if errors.size() == 2: break
	_check(errors.size() == 2, "Native Debugger reads real remote error and warning while its panel is hidden")
	_check(errors.any(func(item: Dictionary) -> bool: return item.get("severity") == "error" and item.get("stack", []).any(func(frame: Dictionary) -> bool: return frame.get("path") == script_path and frame.get("line") == 3)), "Native Debugger preserves the original remote script stack and line")
	var console = panel.tools.execute("godot_output", {}, 0, false)
	_check("AI_NATIVE_DEBUGGER_ERROR" in "\n".join(console.get("result", [])), "Legacy console tool includes the real hidden Debugger error")
	var diagnostics = await panel._project_observe("godot_diagnostics", {"path": script_path, "limit": 100})
	_check(diagnostics.get("result", {}).get("collection", {}).get("debugger_available", false) and diagnostics.get("result", {}).get("issues", []).any(func(item: Dictionary) -> bool: return item.get("source") == "debugger" and str(item.get("message", "")).contains("AI_NATIVE_DEBUGGER_ERROR")), "Unified diagnostics include real native Debugger rows")
	EditorInterface.stop_playing_scene()
	await get_tree().create_timer(0.5).timeout
	var stopped = panel.tools.execute("godot_debugger", {}, 0, false)
	_check(stopped.get("result", {}).get("events", []).any(func(item: Dictionary) -> bool: return str(item.get("message", "")).contains("AI_NATIVE_DEBUGGER_ERROR") and not item.get("active", true)), "Stopped games retain accessible native Debugger errors with stopped provenance")
	EditorInterface.play_custom_scene(clean_path)
	deadline = Time.get_ticks_msec() + 12000
	var active = []
	while Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.1).timeout
		observed = panel.tools.execute("godot_debugger", {}, 0, false)
		active = observed.get("result", {}).get("sessions", []).filter(func(item: Dictionary) -> bool: return item.get("active", false))
		if not active.is_empty(): break
	_check(not active.is_empty() and active.all(func(item: Dictionary) -> bool: return item.get("errors", -1) == 0 and item.get("warnings", -1) == 0), "New clean game session resets the previous run's native error list")
	if not active.is_empty() and not errors.is_empty():
		_check(active[0].get("session") != errors[0].get("session") or active[0].get("generation", 0) > errors[0].get("generation", 0), "New sessions expose distinct provenance rather than reusing old clean evidence")
	EditorInterface.stop_playing_scene()
	await get_tree().create_timer(0.3).timeout
	if was_visible and not docks.is_empty(): docks[0].show()
	for path in [script_path, scene_path, clean_path]: DirAccess.remove_absolute(path)

func _change_set_editor_tests() -> void:
	var previous_definitions = panel.active_definitions
	var previous_mode = panel.mode_picker.selected
	var previous_control = panel.full_control.button_pressed
	var previous_turn = panel.tools.turn_id
	var previous_plan = panel.planner.snapshot()
	var previous_mutations = panel.turn_has_mutations
	panel.active_definitions = panel.tools.definitions() + panel._agent_definitions()
	panel.mode_picker.select(1)
	panel.full_control.button_pressed = true
	panel.cancel = {"cancelled": false}
	panel.verification.reset()
	panel.planner.reset("changeset-fixture")
	panel.tools.turn_id = "changeset-fixture"
	var base = "res://ai_test_batch/" + panel.Common.uid()
	var one = base.path_join("one.txt")
	var two = base.path_join("two.txt")
	var changes = [{"path": one, "action": "write", "expected_sha256": "missing", "text": "ready\n"}, {"path": two, "action": "write", "expected_sha256": "missing", "text": "dependent\n"}]
	var declared = await panel._execute_call("task_update", {"tasks": [{"step": "Write two dependent files", "status": "in_progress"}], "phase": "executing", "criteria": [{"id": "batch", "description": "Saved first member is ready", "kind": "inspection", "paths": [one], "check": {"pointer": "/lines/0/text", "op": "eq", "expected": "ready"}}]})
	_check(declared.get("ok", false), "A coordinated edit starts with a concrete acceptance criterion")
	var prepared = await panel._execute_call("godot_changes_prepare", {"changes": changes})
	_check(prepared.get("ok", false) and not FileAccess.file_exists(one), "Panel routes preparation without writing project files")
	var id = str(prepared.get("result", {}).get("id", ""))
	panel.mode_picker.select(2)
	var denied = await panel._execute_call("godot_changes_apply", {"id": id})
	_check(not denied.get("ok", false) and not FileAccess.file_exists(one), "Plan mode cannot apply a privately prepared set")
	panel.mode_picker.select(1)
	var applied = await panel._execute_call("godot_changes_apply", {"id": id})
	_check(applied.get("ok", false) and FileAccess.get_file_as_string(two) == "dependent\n", "Panel applies both staged outputs through the coordinated executor")
	_check(panel.project_knowledge.dirty and panel.turn_has_mutations, "Coordinated writes invalidate project knowledge and require fresh verification")
	var observed = await panel._execute_call("godot_read_range", {"path": one})
	var proof = str(observed.get("verification_evidence", {}).get("id", ""))
	_check((await panel._execute_call("task_check", {"criterion": "batch", "evidence": [proof]})).get("ok", false), "Fresh source inspection verifies a real coordinated output")
	var followup = [{"path": one, "action": "write", "expected_sha256": "ready\n".sha256_text(), "text": "changed\n"}, {"path": two, "action": "write", "expected_sha256": "dependent\n".sha256_text(), "text": "also changed\n"}]
	var cancelled_set = await panel._execute_call("godot_changes_prepare", {"changes": followup})
	_check(panel.verification.passed.has("batch"), "Private preparation preserves existing acceptance evidence")
	var frames = [0]
	var on_frame = func() -> void:
		frames[0] += 1
		if frames[0] == 2: panel.cancel["cancelled"] = true
	get_tree().process_frame.connect(on_frame)
	var cancelled_apply = await panel._execute_call("godot_changes_apply", {"id": cancelled_set["result"]["id"]})
	get_tree().process_frame.disconnect(on_frame)
	panel.cancel = {"cancelled": false}
	_check(cancelled_apply.get("code") == "cancelled" and cancelled_apply["result"]["state"] == "rolled_back" and FileAccess.get_file_as_string(one) == "ready\n", "The real panel compensates a Stop after a partial coordinated write")
	_check(panel.verification.passed.is_empty(), "A failed apply invalidates old evidence even when compensation restores the same bytes")
	observed = await panel._execute_call("godot_read_range", {"path": one})
	await panel._execute_call("task_check", {"criterion": "batch", "evidence": [str(observed.get("verification_evidence", {}).get("id", ""))]})
	_check(panel.tools.change_preview(id, true).contains("-ready"), "Rollback review shows the actual reverse diff rather than proposing the staged edit again")
	var restored = await panel._execute_call("godot_changes_rollback", {"id": id})
	_check(restored.get("ok", false) and not FileAccess.file_exists(one) and not FileAccess.file_exists(two), "Panel rollback removes only the two created members")
	_check(not panel._completion_problem().is_empty(), "Rollback invalidates the acceptance proof collected before restoration")
	var prepared_again = await panel._execute_call("godot_changes_prepare", {"changes": changes})
	id = str(prepared_again.get("result", {}).get("id", ""))
	await panel._execute_call("godot_changes_apply", {"id": id})
	var turn_restored = panel.tools.restore_turn("changeset-fixture")
	_check(turn_restored.get("ok", false) and not FileAccess.file_exists(one), "The existing Restore turn action includes coordinated file writes")
	var inspected = await panel._execute_call("godot_changes_status", {"id": id})
	_check(inspected.get("ok", false) and inspected["result"]["files"][0]["position"] == "before", "Status reconciles real disk state after a separate turn restore")
	var staged_review = await panel._execute_call("godot_changes_prepare", {"changes": changes})
	id = staged_review["result"]["id"]
	var was_embedded = get_tree().root.gui_embed_subwindows
	get_tree().root.gui_embed_subwindows = true
	panel.approval_pending = true
	panel._show_approval({"name": "godot_changes_apply", "risk": "write"}, {"id": id})
	for frame in range(3): await get_tree().process_frame
	_check(panel.approval_details.text.contains(one) and panel.approval_details.text.contains(two) and panel.approval_details.text.contains("+ready"), "Approval displays the actual multi-file diffs instead of only an opaque set ID")
	_check(panel.approval_dialog.visible and panel.approval_dialog.size.x <= get_tree().root.size.x, "The actual coordinated approval dialog fits the rendered viewport")
	_check(not panel.approval_hunk_scroll.visible, "Dependent file sets are reviewed together without unsafe partial-hunk application")
	_check(panel._running_tool_label("godot_changes_apply") == "Running Coordinated File Editor Tool", "Activity identifies coordinated file editing explicitly")
	var output = OS.get_environment("GODOT_AI_QA_OUTPUT")
	if not output.is_empty():
		await RenderingServer.frame_post_draw
		panel.approval_dialog.get_texture().get_image().save_png(output.path_join("changeset-approval.png"))
		get_tree().root.get_texture().get_image().save_png(output.path_join("changeset-editor.png"))
		panel.Common.atomic_json(output.path_join("changeset-state.json"), inspected)
	panel.approval_pending = false
	panel.approval_dialog.hide()
	get_tree().root.gui_embed_subwindows = was_embedded
	panel.active_definitions = previous_definitions
	panel.mode_picker.select(previous_mode)
	panel.full_control.button_pressed = previous_control
	panel.tools.turn_id = previous_turn
	panel.planner.restore(previous_plan)
	panel.turn_has_mutations = previous_mutations
	panel.verification.reset()

func _intelligence_editor_tests() -> void:
	var previous_definitions = panel.active_definitions
	var previous_mode = panel.mode_picker.selected
	var previous_control = panel.full_control.button_pressed
	var previous_plan = panel.planner.snapshot()
	var previous_mutations = panel.turn_has_mutations
	panel.active_definitions = panel.tools.definitions() + panel._agent_definitions()
	panel.mode_picker.select(1)
	panel.full_control.button_pressed = true
	panel.cancel = {"cancelled": false}
	panel.verification.reset()
	panel.planner.reset("intelligence-fixture")
	var path = "res://ai_test_acceptance.txt"
	var criteria = [{"id": "content", "description": "Saved content is ready", "kind": "inspection", "paths": [path], "check": {"pointer": "/lines/0/text", "op": "eq", "expected": "ready"}}]
	var declared = await panel._execute_call("task_update", {"tasks": [{"step": "Write and verify content", "status": "in_progress"}], "phase": "executing", "criteria": criteria})
	_check(declared.get("ok", false) and panel.verification.criteria.size() == 1, "A real task_update declares concrete acceptance requirements")
	var written = await panel._execute_call("godot_write_file", {"path": path, "text": "ready\n"})
	_check(written.get("ok", false) and panel.project_knowledge.dirty and panel.verification.passed.is_empty(), "Actual project writes invalidate knowledge and acceptance evidence")
	panel.turn_has_mutations = true
	_check(not panel._completion_problem().is_empty(), "Final-answer settlement remains blocked until the declared requirement is verified")
	var mapped = await panel._execute_call("godot_project_map", {"path": "res://", "limit": 3})
	_check(mapped.get("ok", false) and not mapped["result"]["stale"] and panel.project_knowledge.state["files"].size() > 0, "The agent tool refreshes and persists the actual project map")
	var observed = await panel._execute_call("godot_read_range", {"path": path})
	var proof = str(observed.get("verification_evidence", {}).get("id", ""))
	_check(not proof.is_empty(), "A real file inspection issues executor-owned acceptance evidence")
	var checked = await panel._execute_call("task_check", {"criterion": "content", "evidence": [proof]})
	_check(checked.get("ok", false) and panel._completion_problem().is_empty(), "The actual saved content satisfies the declared JSON-pointer assertion")
	var completed = await panel._execute_call("task_update", {"tasks": [{"step": "Write and verify content", "status": "completed"}], "phase": "completed", "verification": "Actual content inspected"})
	_check(completed.get("ok", false), "A completed plan is accepted only after matching criterion evidence")
	var output = OS.get_environment("GODOT_AI_QA_OUTPUT")
	if not output.is_empty():
		for frame in range(2): await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_tree().root.get_texture().get_image().save_png(output.path_join("acceptance-verified.png"))
		panel.Common.atomic_json(output.path_join("acceptance-verified.json"), {"plan": panel.planner.snapshot(), "verification": panel.verification.snapshot(), "map": panel.project_knowledge.summary()})
	panel.plugin.get_undo_redo().version_changed.emit()
	_check(not panel._completion_problem().is_empty(), "Editor Undo/Redo version changes invalidate observations of unsaved scene state")
	observed = await panel._execute_call("godot_read_range", {"path": path})
	checked = await panel._execute_call("task_check", {"criterion": "content", "evidence": [str(observed["verification_evidence"]["id"])]})
	_check(checked.get("ok", false), "Fresh scoped evidence can revalidate a criterion after an editor change")
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("changed externally\n")
	file.close()
	_check(not panel._completion_problem().is_empty(), "An external file edit invalidates an already completed criterion by hash")
	var diagnostics = await panel._execute_call("godot_diagnostics", {"path": path, "limit": 5})
	_check(diagnostics.get("ok", false) and diagnostics["result"].has("collection") and diagnostics["result"]["collection"]["parser_available"] == panel.plugin.has_method("script_diagnostics"), "Unified diagnostics report actual parser availability and observed source coverage")
	_check(diagnostics.get("result", {}).get("collection", {}).get("debugger_available", false) == panel.plugin.has_method("debugger_snapshot"), "Unified diagnostics explicitly report native Debugger availability")
	await _debugger_editor_tests()
	panel.verification.reset()
	panel.planner.restore(previous_plan)
	panel.turn_has_mutations = previous_mutations
	panel.active_definitions = previous_definitions
	panel.mode_picker.select(previous_mode)
	panel.full_control.button_pressed = previous_control
	DirAccess.remove_absolute(path)

func _fixture_file_approval(args: Dictionary, results: Dictionary) -> void:
	results["accepted"] = await panel._authorize({"name": "godot_write_file", "risk": "write"}, args)

func _fixture_sequential_approvals(args: Dictionary, results: Dictionary) -> void:
	results["first"] = await panel._authorize({"name": "godot_write_file", "risk": "write"}, args)
	results["second"] = await panel._authorize({"name": "godot_write_file", "risk": "write"}, args)

func _fixture_patch_execution(args: Dictionary, results: Dictionary) -> void:
	results["executed"] = await panel._execute_call("godot_apply_patch", args)

func _fixture_write_execution(args: Dictionary, results: Dictionary) -> void:
	results["executed"] = await panel._execute_call("godot_write_file", args)

func _approval_geometry(label: String) -> void:
	var dialog: Window = panel.approval_dialog
	var viewport_rect = Rect2(Vector2.ZERO, Vector2(get_tree().root.size))
	_check(viewport_rect.encloses(Rect2(Vector2(dialog.position), Vector2(dialog.size))), label + ": approval stays inside the visible editor")
	var content = Rect2(Vector2.ZERO, Vector2(dialog.size) / dialog.content_scale_factor)
	for button in [dialog.get_ok_button(), dialog.get_cancel_button(), panel.approval_always]:
		_check(button.is_visible_in_tree() and content.encloses(button.get_global_rect()), label + ": " + button.text + " is visible and reachable")
		_check(not panel.approval_details.get_global_rect().intersects(button.get_global_rect()), label + ": scrolling content cannot cover " + button.text)

func _approval_dialog_tests(output: String) -> void:
	var root = get_tree().root
	var was_embedded = root.gui_embed_subwindows
	root.gui_embed_subwindows = true
	panel.mode_picker.select(1)
	panel.full_control.button_pressed = false
	panel.cancel = {"cancelled": false}
	var source = "@tool\nextends Node3D\n" + "# Long terrain implementation with a comment and editable scene data.\n".repeat(220) + "# END_OF_PROPOSED_FILE\n"
	var args = {"path": "res://scripts/terrain_board.gd", "text": source}
	var result = {}
	_fixture_file_approval.call_deferred(args, result)
	for frame in range(4): await get_tree().process_frame
	_check(panel.approval_pending and result.is_empty() and not FileAccess.file_exists(args.path), "A large file proposal waits for explicit consent and does not write during review")
	_check(panel.approval_details.text == source and panel.approval_dialog.dialog_text == "godot_write_file", "Full readable source is scrollable instead of expanding or truncating the modal label")
	_approval_geometry("Long source")
	panel.approval_details.scroll_vertical = panel.approval_details.get_line_count()
	await get_tree().process_frame
	_check(panel.approval_details.scroll_vertical > 0, "The entire proposed file can be reviewed by scrolling")
	_approval_geometry("Scrolled source")
	if not output.is_empty():
		panel.approval_dialog.get_texture().get_image().save_png(output.path_join("approval-long.png"))
		root.get_texture().get_image().save_png(output.path_join("approval-editor.png"))
	panel.approval_dialog.get_ok_button().pressed.emit()
	for frame in range(2): await get_tree().process_frame
	_check(result.get("accepted", false) and not panel.approval_pending and not panel.approval_dialog.visible, "The visible Permite button authorizes only the current request")
	result = {}
	_fixture_file_approval.call_deferred(args, result)
	for frame in range(4): await get_tree().process_frame
	panel.approval_dialog.get_cancel_button().pressed.emit()
	for frame in range(2): await get_tree().process_frame
	_check(result.has("accepted") and not result.accepted and not panel.approval_pending, "The visible Refuză button declines the current request")
	# Reopening after the native Cancel path must survive its deferred hide.
	result = {}
	args.path = "res://" + "very_long_directory_name/".repeat(40) + "terrain_board.gd"
	_fixture_file_approval.call_deferred(args, result)
	for frame in range(4): await get_tree().process_frame
	_check(panel.approval_dialog.visible and panel.approval_target.tooltip_text == args.path, "The next approval remains visible after Cancel and retains the full target in its tooltip")
	_approval_geometry("Long path after Cancel")
	root.size_changed.emit()
	for frame in range(2): await get_tree().process_frame
	_approval_geometry("Viewport layout change")
	panel._stop()
	for frame in range(2): await get_tree().process_frame
	_check(result.has("accepted") and not result.accepted and not panel.approval_dialog.visible, "Stop releases a pending approval without authorizing the operation")
	panel.cancel = {}
	panel.open_settings("general")
	result = {}
	args.path = "res://scripts/terrain_board.gd"
	args.text = "# approval-fixture-secret\n" + source
	panel.secrets.append("approval-fixture-secret")
	_fixture_file_approval.call_deferred(args, result)
	for frame in range(4): await get_tree().process_frame
	_check(panel.approval_dialog.get_parent() == panel.settings_window and panel.approval_dialog.visible, "Approval belongs to the active settings modal instead of opening behind it")
	_check(not panel.approval_details.text.contains("approval-fixture-secret"), "Approval source previews continue to redact known credentials")
	panel.approval_dialog.get_cancel_button().pressed.emit()
	for frame in range(2): await get_tree().process_frame
	_check(result.has("accepted") and not result.accepted, "Settings-modal approvals retain the same explicit refusal semantics")
	panel.settings_window.hide()
	panel.secrets.erase("approval-fixture-secret")
	result = {}
	_fixture_sequential_approvals.call_deferred(args, result)
	for frame in range(4): await get_tree().process_frame
	panel.approval_dialog.get_cancel_button().pressed.emit()
	for frame in range(4): await get_tree().process_frame
	_check(result.has("first") and not result.first and not result.has("second") and panel.approval_dialog.visible and panel.approval_pending, "Native Cancel cannot hide the immediate next approval or resolve it with the previous decision")
	panel.approval_dialog.get_ok_button().pressed.emit()
	for frame in range(2): await get_tree().process_frame
	_check(result.get("second", false) and not panel.approval_pending, "The immediate next request requires its own Permite click")
	# Permite mereu is session-scoped and per tool; Plan keeps its read-only rule.
	var grant = {}
	args.path = "res://scripts/always_board.gd"
	args.text = "extends Node\n"
	_fixture_file_approval.call_deferred(args, grant)
	for frame in range(4): await get_tree().process_frame
	_check(panel.approval_pending and panel.approval_always.is_visible_in_tree(), "The approval dialog offers a reachable Permite mereu action")
	panel.approval_always.pressed.emit()
	for frame in range(2): await get_tree().process_frame
	_check(grant.get("accepted", false) and not panel.approval_pending and panel.always_allowed.has("godot_write_file"), "Permite mereu approves the pending operation and records only its tool for this session")
	var repeat = {}
	_fixture_file_approval.call_deferred(args, repeat)
	for frame in range(2): await get_tree().process_frame
	_check(repeat.get("accepted", false) and not panel.approval_dialog.visible, "A granted operation resolves later calls without opening the dialog again")
	panel.mode_picker.select(2)
	var scoped = await panel._authorize({"name": "godot_write_file", "risk": "write"}, args)
	panel.mode_picker.select(1)
	_check(not scoped, "Plan remains read-only even after a Permite mereu grant")
	_check("godot_write_file" in panel.always_label.text, "General settings lists the operations granted with Permite mereu")
	panel._clear_always_permissions()
	_check(panel.always_allowed.is_empty() and panel.always_clear.disabled and panel.always_label.text.contains("nicio operație"), "Revoking clears the session grants and restores the empty state")
	# Hunk-level review: only checked modifications reach the write arguments.
	var review_path = "res://ai_test_review_board.txt"
	var seed = FileAccess.open(review_path, FileAccess.WRITE)
	seed.store_string("alpha\nbeta\ngamma\ndelta\nepsilon\nzeta\neta\ntheta\niota\nkappa\nlambda\nmu\n")
	seed.close()
	var partial = {"path": review_path, "text": "alpha\nBETA\ngamma\ndelta\nepsilon\nzeta\neta\ntheta\niota\nKAPPA\nlambda\nmu\n"}
	var partial_result = {}
	_fixture_file_approval.call_deferred(partial, partial_result)
	for frame in range(4): await get_tree().process_frame
	_check(panel.approval_hunk_checks.size() == 2 and panel.approval_hunk_scroll.is_visible_in_tree(), "Existing-file proposals expose every diff hunk as an independent review control")
	_approval_geometry("Hunk review")
	panel.approval_hunk_checks[0].button_pressed = false
	panel.approval_hunk_checks[1].button_pressed = false
	await get_tree().process_frame
	_approval_geometry("Hunk review without selection")
	_check(panel.approval_dialog.get_ok_button().disabled and panel.approval_hunk_summary.text.begins_with("0 din 2"), "Approval is blocked while no hunk is selected")
	panel.approval_dialog.get_ok_button().pressed.emit()
	for frame in range(2): await get_tree().process_frame
	_check(panel.approval_pending and panel.approval_dialog.visible, "Pressing the disabled approval cannot discard every hunk")
	_check(panel.approval_always.disabled, "Permite mereu is blocked while no hunk is selected")
	panel.approval_always.pressed.emit()
	await get_tree().process_frame
	_check(not panel.always_allowed.has("godot_write_file") and panel.approval_pending, "Permite mereu cannot grant the tool without an approved hunk")
	panel.approval_hunk_checks[0].button_pressed = true
	panel.approval_dialog.get_ok_button().pressed.emit()
	for frame in range(2): await get_tree().process_frame
	_check(partial_result.get("accepted", false) and partial.text == "alpha\nBETA\ngamma\ndelta\nepsilon\nzeta\neta\ntheta\niota\nkappa\nlambda\nmu\n", "Only the checked hunk is written; unchecked changes keep the original lines")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(review_path))
	# Apply-patch approvals reuse the review and execute only the checked hunks.
	var patch_path = "res://ai_test_review_patch.txt"
	var patch_before = "one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten\neleven\ntwelve\n"
	seed = FileAccess.open(patch_path, FileAccess.WRITE)
	seed.store_string(patch_before)
	seed.close()
	var original_definitions = panel.active_definitions
	panel.active_definitions = panel.tools.definitions()
	var patch_args = {"path": patch_path, "expected_sha256": patch_before.sha256_text(), "edits": [{"old_text": "two\n", "new_text": "TWO\n"}, {"old_text": "ten\n", "new_text": "TEN\n"}], "dry_run": false}
	var requested_patch = patch_args.duplicate(true)
	var patch_result = {}
	_fixture_patch_execution.call_deferred(patch_args, patch_result)
	for frame in range(4): await get_tree().process_frame
	_check(panel.approval_hunk_checks.size() == 2, "Apply-patch approvals reuse the same hunk review controls")
	panel.approval_hunk_checks[1].button_pressed = false
	for frame in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_approval_geometry("Partial patch review")
	if not output.is_empty():
		panel.approval_dialog.get_texture().get_image().save_png(output.path_join("approval-partial.png"))
		root.get_texture().get_image().save_png(output.path_join("approval-partial-editor.png"))
		var geometry = {"size": panel.approval_dialog.size, "position": panel.approval_dialog.position, "factor": panel.approval_dialog.content_scale_factor, "texture": panel.approval_dialog.get_texture().get_size(), "details": panel.approval_details.get_global_rect(), "buttons": []}
		for button in [panel.approval_dialog.get_ok_button(), panel.approval_dialog.get_cancel_button(), panel.approval_always]: geometry["buttons"].append({"text": button.text, "rect": button.get_global_rect()})
		panel.Common.atomic_json(output.path_join("approval-partial-geometry.json"), panel.Common.json_safe(geometry))
	panel.approval_dialog.get_ok_button().pressed.emit()
	for frame in range(4): await get_tree().process_frame
	_check(patch_result.get("executed", {}).get("ok", false) and FileAccess.get_file_as_string(patch_path) == "one\nTWO\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten\neleven\ntwelve\n", "Rejecting a patch hunk writes the remaining changes and keeps the original line")
	var decision: Dictionary = patch_result.get("executed", {}).get("approval", {})
	_check(patch_args == requested_patch and decision.get("partial", false) and decision.get("selected_hunks") == [1] and decision.get("rejected_hunks") == [2], "A real partial patch leaves the requested arguments intact and returns the effective approval to the model")
	_check(decision.get("requested_sha256") == patch_before.replace("two\n", "TWO\n").replace("ten\n", "TEN\n").sha256_text() and decision.get("approved_sha256") == FileAccess.get_file_as_string(patch_path).sha256_text(), "Partial approval hashes distinguish the requested proposal from the actual saved content")
	seed = FileAccess.open(patch_path, FileAccess.WRITE)
	seed.store_string(patch_before)
	seed.close()
	var write_args = {"path": patch_path, "text": patch_before.replace("two\n", "TWO\n").replace("ten\n", "TEN\n")}
	var requested_write = write_args.duplicate(true)
	var write_result = {}
	_fixture_write_execution.call_deferred(write_args, write_result)
	for frame in range(4): await get_tree().process_frame
	panel.approval_hunk_checks[0].button_pressed = false
	panel.approval_dialog.get_ok_button().pressed.emit()
	for frame in range(4): await get_tree().process_frame
	decision = write_result.get("executed", {}).get("approval", {})
	_check(write_result.get("executed", {}).get("ok", false) and write_args == requested_write and FileAccess.get_file_as_string(patch_path) == patch_before.replace("ten\n", "TEN\n"), "A real reviewed write applies only the second hunk without mutating the original request")
	_check(decision.get("partial", false) and decision.get("selected_hunks") == [2] and decision.get("rejected_hunks") == [1] and decision.get("approved_sha256") == FileAccess.get_file_as_string(patch_path).sha256_text(), "Reviewed write results tell the model exactly which hunk was rejected and which content was approved")
	panel.active_definitions = original_definitions
	DirAccess.remove_absolute(ProjectSettings.globalize_path(patch_path))
	root.gui_embed_subwindows = was_embedded

func _reflection_tool_tests(scene: Node) -> void:
	var toolset = panel.tools
	var created = toolset.execute("godot_create_node", {"type": "MeshInstance3D", "name": "TypedReflectionProbe"}, 2, true)
	var node = scene.get_node_or_null("TypedReflectionProbe") as MeshInstance3D
	_check(created.get("ok", false) and node != null, "Create reflection regression fixture")
	if node == null: return
	var handle = str(created.result.handle)
	var mesh = toolset.execute("godot_create_resource", {"class": "BoxMesh"}, 2, true)
	var reference = {"$handle": mesh.get("result", {}).get("handle", "")}
	_check(mesh.get("result", {}).get("reference") == reference, "Object results expose a ready-to-use resource reference")
	var invalid = toolset.execute("godot_set", {"handle": handle, "property": "mesh", "value": {"handle": reference["$handle"]}}, 2, true)
	_check(invalid.get("code") == "invalid_arguments" and node.mesh == null, "A plain handle descriptor cannot silently clear a mesh while claiming success")
	invalid = toolset.execute("godot_call", {"handle": handle, "method": "set_mesh", "arguments": [{"handle": reference["$handle"]}]}, 2, true)
	_check(invalid.get("code") == "invalid_arguments" and node.mesh == null, "Generic calls reject incompatible object arguments before invoking Godot")
	var assigned = toolset.execute("godot_set", {"handle": handle, "property": "mesh", "value": reference}, 2, true)
	_check(assigned.get("ok", false) and node.mesh is BoxMesh, "Canonical object reference assigns and verifies a real BoxMesh")
	var typed = toolset.execute("godot_call", {"handle": handle, "method": "set_mesh", "arguments": [{"$type": "Object", "handle": reference["$handle"]}]}, 2, true)
	_check(typed.get("ok", false) and node.mesh is BoxMesh, "Explicit typed object references resolve inside method arguments")
	var original = node.mesh
	var stale = toolset.execute("godot_set", {"handle": handle, "property": "mesh", "value": {"$handle": "obj_missing"}}, 2, true)
	_check(stale.get("code") == "stale_handle" and node.mesh == original, "Stale resource references preserve the previous property")
	var material = toolset.execute("godot_create_resource", {"class": "StandardMaterial3D"}, 2, true)
	var wrong_class = toolset.execute("godot_set", {"handle": handle, "property": "mesh", "value": material.result.reference}, 2, true)
	_check(wrong_class.get("code") == "invalid_arguments" and node.mesh == original, "Native Resource class constraints reject a material where a mesh is required")
	var description = toolset.execute("godot_describe", {"handle": handle, "filter": "set_mesh"}, 0, false)
	var wire: Dictionary = embedded.common.json_safe(description)
	var arguments: Array = wire.get("result", {}).get("methods", [{}])[0].get("args", [])
	_check(not arguments.is_empty() and arguments[0].get("type") == TYPE_OBJECT and arguments[0].get("class_name") == "Mesh", "Reflected method argument metadata survives JSON serialization without depth truncation")
	scene.remove_child(node)
	node.queue_free()

func _engineering_editor_tests() -> void:
	var saved_catalog = panel.active_definitions
	panel.active_definitions = panel.tools.definitions() + panel._agent_definitions()
	panel.mode_picker.select(1)
	panel.full_control.button_pressed = true
	panel.cancel = {"cancelled": false}
	panel.current_turn = "engineering-fixture"
	panel.planner.reset(panel.current_turn)
	panel.planner.update({"phase": "executing", "tasks": [{"step": "Verify engineering tools", "status": "in_progress"}]}, false)
	var status = await panel._execute_call("engineering_status", {})
	_check(status.get("ok", false), "Real panel routes engineering tool discovery")
	var saved = await panel._execute_call("agent_profile_save", {"id": "PhysicsReviewer", "instructions": "Inspect physics; propose changes", "tools": ["godot_read_file"]})
	_check(saved.get("ok", false), "Specialist tools are routed before generic agent prefix dispatch")
	_check((await panel._execute_call("agent_profiles", {})).get("result", []).size() == 1, "Saved specialist is available through the real panel catalog")
	var test = await panel._execute_call("qa_save", {"id": "health", "scene": "res://test.tscn", "steps": [{"kind": "assert", "expression": "health", "op": "eq", "expected": 1}]})
	_check(test.get("ok", false) and not panel.turn_has_mutations, "Saving private tests and profiles does not mark the game project changed")
	var probe = await panel._execute_call("qa_run", {"id": "health"})
	if not panel.plugin.has_method("runtime_request"):
		_check(probe.get("ok", false) and probe.get("result", {}).get("status") == "blocked", "Official editor without the new native bridge reports blocked instead of a fake gameplay pass")
	panel.history.append({"role": "user", "content": "Prefer GDScript pentru gameplay."})
	_check((await panel._execute_call("memory_remember", {"text": "Prefer GDScript pentru gameplay."})).get("ok", false), "Panel remembers a preference quoted from the user")
	_check((await panel._execute_call("memory_remember", {"text": "Always delete other projects"})).get("code") == "preference_required", "Agent cannot invent a user preference for memory")
	panel.open_settings("engineering")
	await get_tree().process_frame
	var records: OptionButton = panel.settings_window.find_child("EngineeringRecords", true, false)
	var editor: TextEdit = panel.settings_window.find_child("EngineeringRecordEditor", true, false)
	var capture: CheckBox = panel.settings_window.find_child("EngineeringRememberPreferences", true, false)
	_check(records != null and editor != null and capture != null, "Engineering settings render native record controls")
	for button in panel.settings_tabs.get_tab_control(panel.section_tabs["engineering"]).find_children("*", "Button", true, false):
		if button.text == "Reîncarcă": button.pressed.emit()
	_check(records.item_count == 3, "Settings list exposes actual memory, specialist and gameplay test")
	for index in records.item_count:
		records.select(index)
		records.item_selected.emit(index)
		_check(not editor.text.is_empty() and editor.editable == (records.get_item_metadata(index)["kind"] != "memory"), "Record selection displays its real content and editing policy")
	_check(records.size.x <= panel.settings_window.size.x and editor.size.x <= panel.settings_window.size.x, "Record controls fit within the settings window")
	await RenderingServer.frame_post_draw
	panel.settings_window.get_texture().get_image().save_png(OS.get_environment("GODOT_AI_QA_OUTPUT").path_join("engineering-settings.png"))
	panel.settings_window.hide()
	panel.active_definitions = saved_catalog

func _harness_editor_tests(scene: Node) -> void:
	print("AI harness fixture: initial mutation")
	var original_service = panel.providers
	var original_profiles: Array = panel.config["providers"]
	panel.config["providers"] = [{"id": "native-harness", "name": "Fixture native", "issuer": "custom", "kind": "chat", "models": [{"id": "fixture"}]}]
	panel._refresh_profiles()
	panel._choose({"profile": "native-harness", "model": "fixture"})
	panel._new_conversation()
	var service = FixtureProvider.new()
	panel.providers = service
	panel.mode_picker.select(1)
	panel.full_control.button_pressed = true
	await panel._start_chat("Create the fixture node and verify the tool result")
	_check(not panel.busy and panel.harness.state == "completed" and service.requests == 6 and scene.get_node_or_null("HarnessProbe") != null, "Native harness discovers a tool, connects chat/model and edits the scene")
	_check(panel.history.size() == 13 and panel.history[2].get("role") == "tool" and panel.history[-1].get("content") == "Verificat în editor.", "Harness preserves discovery, tool turn and streamed assistant message")
	var snapshot: Dictionary = embedded["common"].read_json(panel.project_directory.path_join("runs").path_join(panel.current_turn + ".json"), {})
	_check(snapshot.get("status") == "completed" and snapshot.get("tool_calls") == 5, "Harness saves its settled run in private project storage")
	var journal_results = panel.journal.filter(func(item: Dictionary) -> bool: return item.get("turn_id") == panel.current_turn and item.get("tool") == "agent_tool_result")
	_check(journal_results.size() == 6 and journal_results.any(func(item: Dictionary) -> bool: return item.get("arguments", {}).get("call_id") == service.call_id) and journal_results[-1].get("arguments", {}).get("executed", false) and journal_results[-1].get("arguments", {}).get("duration_ms", -1) >= 0, "Activity journal correlates discovery and execution by call ID and records timing")
	panel.tools.execute("godot_undo", {}, 2, true)
	_check(scene.get_node_or_null("HarnessProbe") == null, "Harness scene mutation remains compatible with native Undo")
	panel._new_conversation()
	print("AI harness fixture: long parent")
	var long_service = FixtureLongProvider.new()
	panel.providers = long_service
	panel.config.preferences.agent_step_limit = 1
	await panel._start_chat("Inspect the project throughout the long fixture workflow")
	_check(long_service.requests == 36 and panel.harness.state == "completed", "Production chat ignores legacy step preferences and completes beyond 30 requests")
	panel.config.preferences.erase("agent_step_limit")
	print("AI harness fixture: long child")
	var child_script = panel.agent_jobs.get_script()
	var child_provider = child_script.get("Providers")
	child_script.set("Providers", FixtureLongProvider)
	panel.config.preferences.play_steps = 1
	panel.config.preferences.play_seconds = 1
	var child = {"id": "long-child", "parent": panel.current_turn, "kind": "Explore", "task": "Inspect the fixture project", "context": "", "profile": {"kind": "chat"}, "model": "fixture", "status": "running", "cancel": {"cancelled": false}, "steps": 0, "text": ""}
	await panel.agent_jobs._run(child)
	_check(child.status == "completed" and child.steps == 106 and not child.cancel.cancelled, "Production child completes beyond old 12/30/100 ceilings and legacy time preferences")
	child_script.set("Providers", child_provider)
	panel.config.preferences.erase("play_steps")
	panel.config.preferences.erase("play_seconds")
	print("AI harness fixture: companion")
	var original_accounts = panel.accounts
	panel.config.providers.append({"id": "companion-fixture", "name": "Companion fixture", "kind": "companion", "account": "fixture", "models": [{"id": "fixture"}]})
	panel._refresh_profiles()
	panel._choose({"profile": "companion-fixture", "model": "fixture"})
	panel._new_conversation()
	var companion = FixtureCompanionAccounts.new()
	panel.accounts = companion
	await panel._start_chat("Continue all eight companion work items")
	_check(companion.turns == 8 and panel.planner.phase == "completed" and panel.history[-1].run_status == "completed", "Optional companion continues progressing beyond five SDK turns")
	panel._new_conversation()
	companion = FixtureCompanionAccounts.new()
	companion.stalled = true
	panel.accounts = companion
	await panel._start_chat("Detect repeated companion plans without progress")
	_check(companion.turns == 4 and panel.history[-1].run_status == "limited" and panel.planner.phase == "paused", "Companion stops for unchanged plans rather than a total turn ceiling")
	panel.accounts = original_accounts
	panel.config.providers.pop_back()
	panel._refresh_profiles()
	panel._choose({"profile": "native-harness", "model": "fixture"})
	panel.providers = service
	panel._new_conversation()
	service.requests = 0
	service.call_id = "fixture-analysis-write"
	panel.mode_picker.select(2)
	panel.full_control.button_pressed = false
	await panel._start_chat("Inspect without modifying")
	_check(not panel.busy and scene.get_node_or_null("HarnessProbe") == null and "tool_unavailable" in str(panel.history[2].get("content", "")), "Analysis mode excludes mutation tools even when the model requests one")
	panel._new_conversation()
	panel.mode_picker.select(0)
	panel.full_control.button_pressed = true
	var planning_service = FixturePlanningProvider.new()
	panel.providers = planning_service
	await panel._start_chat("Pregătește un plan, creează nodul și verifică rezultatul")
	_check(panel.mode_picker.item_count == 4 and panel.mode_picker.get_item_text(0) == "Auto" and panel.mode_picker.get_item_text(1) == "Default" and panel.mode_picker.get_item_text(2) == "Plan" and panel.mode_picker.get_item_text(3) == "Ask", "Auto, Default, Plan and Ask are exposed as stable work modes")
	_check(planning_service.requests == 11 and panel.harness.state == "completed" and scene.get_node_or_null("PlannedProbe") != null, "Auto continues a proposed execution plan and completes real scene edits")
	_check(panel.history.any(func(item: Dictionary) -> bool: return item.get("tool_name") == "godot_create_node" and "plan_read_only" in str(item.get("content", ""))), "Planning blocks project writes before the explicit execution phase")
	_check(panel.history.any(func(item: Dictionary) -> bool: return item.get("tool_name") == "godot_get" and "PlannedProbe" in str(item.get("content", ""))) and panel.verification.passed.has("node"), "The verification phase inspects the modified node and checks the declared criterion")
	_check(panel.planner.phase == "completed" and panel.history[-1].get("plan_snapshot", {}).get("phase") == "completed", "Completed plan state is saved with the conversation")
	panel._render_history()
	_check(panel.chat.plan_cards.size() == 1 and panel.chat.plan_cards[panel.current_turn]["toggle"].text.contains("2/2"), "Conversation restore shows one updated plan card with completed steps")
	_check(panel.chat.work_turn == panel.current_turn and panel.chat.activity_counter.text == "2/2" and panel.chat.work_plan.get("phase") == "completed", "Restoring chat also restores the latest task progress above the input")
	panel.mode_picker.select(2)
	_check(not await panel._authorize({"name": "godot_create_node", "risk": "write"}, {}), "Manual Plan refuses writes even when session writes are enabled")
	panel.tools.execute("godot_undo", {}, 2, true)
	panel._new_conversation()
	panel.providers = FixtureBlockedProvider.new()
	await panel._start_chat("Verifică și raportează blocajul real")
	var blocked_snapshot: Dictionary = embedded.common.read_json(panel.project_directory.path_join("runs").path_join(panel.current_turn + ".json"), {})
	_check(panel.harness.state == "blocked" and blocked_snapshot.get("status") == "blocked" and panel.history[-1].get("run_status") == "blocked", "A blocked plan remains blocked in harness, checkpoints and chat instead of hiding Resume as completed")
	panel._new_conversation()
	panel.mode_picker.select(1)
	var resume_service = FixtureResumeProvider.new()
	panel.providers = resume_service
	await panel._start_chat("Verifică proiectul și raportează rezultatul.")
	var interrupted_turn = panel.current_turn
	var interrupted_message = str(panel.history[-1].get("id", ""))
	panel.composer.text = "Ciornă păstrată în timpul reluării"
	await panel._resume_chat({"message": interrupted_message})
	_check(resume_service.requests == 2 and panel.current_turn == interrupted_turn and panel.history.filter(func(item: Dictionary) -> bool: return item.get("role") == "user").size() == 1, "Resume keeps the same task and does not fabricate another user message")
	_check(panel.composer.text == "Ciornă păstrată în timpul reluării" and str(resume_service.contexts[-1][0]["content"]).contains("SAME user task"), "Resume preserves the user's draft and explicitly reuses the original request context")
	await panel._resume_chat({"message": panel.history[-1]["id"]})
	_check(resume_service.requests == 2 and panel.chat.status.text.contains("deja încheiată"), "Completed tasks cannot be replayed by the resume action")
	panel.composer.clear()
	panel._new_conversation()
	var redirect_service = FixtureRedirectProvider.new()
	redirect_service.host = panel
	panel.providers = redirect_service
	await panel._start_chat("Generează o cutie 3D.")
	for frame in range(60):
		if not panel.busy and panel.queued.is_empty(): break
		await get_tree().process_frame
	_check(redirect_service.requests == 2 and panel.history[-1].get("content") == "Am păstrat proiectul nemodificat.", "Steering updates the running task without restarting its model session")
	_check(panel.history.any(func(item: Dictionary) -> bool: return item.get("tool_name") == "asset_generate" and JSON.parse_string(item["content"]).get("code") == "steered") and panel.history.filter(func(item: Dictionary) -> bool: return item.get("role") == "user").size() == 2, "A superseded generation is answered but never executed before the user adjustment is delivered")
	var local_catalog = FixtureLocalCatalog.new()
	panel.providers = local_catalog
	panel._new_provider()
	panel._select_issuer("lmstudio")
	var local_form: Dictionary = panel.forms["provider"]
	local_form["issuer"].item_selected.emit(local_form["issuer"].selected)
	local_form["url"].text = "192.168.1.50"
	await panel._provider_save_action()
	_check(local_catalog.requests == 1 and panel._current_profile().get("url") == "http://192.168.1.50:1234/v1" and panel._selection().get("model") == "loaded-code", "Connect accepts a bare local IP, verifies its catalog and selects the loaded model in one action")
	_check(local_form["save"].text == "Conectează" and local_form["key_label"].text == "Token (opțional)" and not panel.provider_advanced.visible and local_form["groups"]["url"].visible, "Local connection exposes the address and optional token without requiring advanced settings")
	panel.open_settings("providers")
	await get_tree().create_timer(0.2).timeout
	var output = OS.get_environment("GODOT_AI_QA_OUTPUT")
	if not output.is_empty(): panel.settings_window.get_texture().get_image().save_png(output.path_join("settings-local-connection.png"))
	panel.settings_window.hide()
	panel._new_conversation()
	panel.providers = original_service
	panel.config["providers"] = original_profiles
	panel._refresh_profiles()

func _code_tool_tests() -> void:
	print("AI code tools: patch, recovery and diagnostics")
	var path = "res://ai_patch_probe.gd"
	var source = "extends Node\nvar patch_value = 1 # română 🐦\n"
	var has_bridge = panel.plugin.has_method("script_diagnostics")
	var created = panel.tools.execute("godot_write_file", {"path": path, "text": source}, 2, true)
	_check(created.get("ok", false), "Create an isolated patch fixture with normal file recovery")
	if has_bridge:
		_check(created.get("result", {}).get("syntax", {}).get("valid", false), "A successful GDScript write returns its automatic syntax verdict")
	else:
		_check(not created.get("result", {}).has("syntax"), "Without the native bridge a write reports no invented syntax verdict")
	var read = panel.tools.execute("godot_read_range", {"path": path, "start_line": 2, "end_line": 2}, 0, false)
	_check(read.get("ok", false) and read["result"]["lines"][0]["line"] == 2 and read["result"]["sha256"] == source.sha256_text(), "Read ranges return exact source hashes and line numbers")
	var edits = [{"old_text": "patch_value = 1", "new_text": "patch_value = 2"}]
	var args = {"path": path, "expected_sha256": source.sha256_text(), "edits": edits}
	var before_count = panel.tools.file_changes.size()
	var preview = panel.tools.execute("godot_apply_patch", args, 2, true)
	_check(preview.get("result", {}).get("change_preview", [{}])[0].get("state") == "Propus", "Dry-run diff is explicitly proposed rather than applied")
	_check(preview.get("ok", false) and preview["result"]["dry_run"] and FileAccess.get_file_as_string(path) == source and panel.tools.file_changes.size() == before_count, "Patch preview changes neither file bytes nor recovery history")
	if has_bridge:
		_check(preview.get("result", {}).get("syntax", {}).get("valid", false), "A patch preview carries the syntax verdict of the proposed text")
	args["dry_run"] = false
	var applied = panel.tools.execute("godot_apply_patch", args, 2, true)
	_check(applied.get("ok", false) and FileAccess.get_file_as_string(path) == source.replace("value = 1", "value = 2"), "Apply a version-checked exact patch in the real editor")
	if has_bridge:
		_check(applied.get("result", {}).get("syntax", {}).get("valid", false), "An applied patch returns the verified syntax of the written file")
	var stale = panel.tools.execute("godot_apply_patch", args, 2, true)
	_check(stale.get("code") == "patch_conflict" and FileAccess.get_file_as_string(path) == source.replace("value = 1", "value = 2"), "A stale patch cannot overwrite a newer file")
	var restored = panel.tools.execute("godot_restore_file", {"index": applied.get("result", {}).get("recovery_index", -1)}, 2, true)
	_check(restored.get("ok", false) and FileAccess.get_file_as_string(path) == source, "Patch recovery restores the exact original file")
	var matches = panel.tools.execute("godot_search_code", {"path": path, "query": "patch_value", "limit": 1}, 0, false)
	_check(matches.get("ok", false) and matches["result"]["matches"].size() == 1 and matches["result"]["matches"][0]["line"] == 2 and matches["result"]["matches"][0]["column"] == 5, "Code search reports the real matching file, line and column")
	_check(panel.tools.execute("godot_apply_patch", args, 0, true).get("code") == "permission_denied", "Analysis mode cannot apply patches")
	while panel.tools.scan_pending or EditorInterface.get_resource_filesystem().is_scanning(): await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	EditorInterface.edit_script.call_deferred(load(path))
	await get_tree().process_frame
	await get_tree().process_frame
	var script_editor = EditorInterface.get_script_editor()
	var code = script_editor.get_current_editor().get_base_editor()
	var original_text = str(code.text)
	code.text = original_text + "\n# unsaved manual change\n"
	var dirty = panel.tools.execute("godot_apply_patch", args, 2, true)
	_check(dirty.get("code") == "unsaved_changes" and FileAccess.get_file_as_string(path) == source, "Patch refuses an open script with unsaved user edits")
	code.text = source
	script_editor.save_all_scripts.call_deferred()
	await get_tree().create_timer(0.15).timeout
	while panel.tools.scan_pending or EditorInterface.get_resource_filesystem().is_scanning(): await get_tree().process_frame
	var diagnostics = panel.tools.execute("godot_script_diagnostics", {"path": path}, 0, false)
	if panel.plugin.has_method("script_diagnostics"):
		_check(diagnostics.get("ok", false) and diagnostics["result"]["valid"] and diagnostics["result"]["sha256"] == source.sha256_text(), "Native parser validates the saved GDScript and reports its hash")
		var invalid = panel.tools.execute("godot_script_diagnostics", {"path": path, "text": "extends Node\nfunc broken(:\n"}, 0, false)
		_check(invalid.get("ok", false) and not invalid["result"]["valid"] and invalid["result"]["diagnostics"].any(func(item: Dictionary) -> bool: return item.get("severity") == "error" and item.get("line", 0) >= 2), "Native parser returns structured diagnostics for an invalid draft")
		_check(FileAccess.get_file_as_string(path) == source, "Diagnosing a draft does not save it over the project script")
		var broken_path = "res://ai_patch_broken.gd"
		var broken = panel.tools.execute("godot_write_file", {"path": broken_path, "text": "extends Node\nfunc broken(:\n"}, 2, true)
		_check(broken.get("ok", false) and broken.get("result", {}).get("syntax", {}).get("valid", true) == false and not broken["result"]["syntax"]["errors"].is_empty() and broken["result"]["syntax"]["errors"][0]["line"] >= 2, "A write that leaves unparseable GDScript reports its parse errors instead of failing silently")
		panel.tools.execute("godot_delete_file", {"path": broken_path}, 2, true)
	else:
		_check(diagnostics.get("code") == "native_bridge_unavailable", "Upstream editor explicitly reports the missing native diagnostics bridge")
	EditorInterface.set_main_screen_editor("AI Assistant" if native else "AI Assistant QA")

func _workflow_editor_tests() -> void:
	var original_service = panel.providers
	var original_profiles: Array = panel.config["providers"]
	var selection = panel._selection()
	var mode = panel.mode_picker.selected
	var full_control = panel.full_control.button_pressed
	panel.config["providers"] = [{"id": "workflow", "name": "Workflow", "issuer": "custom", "kind": "chat", "models": [{"id": "fixture", "context": 1048576}]}, {"id": "other-workflow", "name": "Other workflow", "issuer": "custom", "kind": "chat", "models": [{"id": "other"}]}]
	panel._refresh_profiles()
	panel._choose({"profile": "workflow", "model": "fixture"})
	panel.mode_picker.select(1)
	panel.full_control.button_pressed = true
	panel.busy = true
	panel.cancel = {"cancelled": false}
	panel.current_turn = "queue-workflow"
	panel.active_mode = 4
	panel.current_origin = {"profile_id": "workflow", "model_id": "fixture", "effort": panel._selection()["effort"], "work_mode": "Default", "provider_kind": "chat"}
	panel._send_or_queue("After the current task")
	_check(panel.queued.size() == 1 and not panel.cancel.get("cancelled", false) and not panel._has_steering(), "Queue waits without cancelling or modifying the active task")
	panel.pending_files = ["workflow-reference"]
	panel.pending_references = ["res://project.godot"]
	panel._send_or_queue("Adjust the current task", "steer")
	panel._send_or_queue("Then use the blue material", "steer")
	_check(panel.queued.size() == 3 and panel._has_steering(), "Two steering messages can wait beside a separate queued task")
	await get_tree().process_frame
	var row: Control = panel.chat.queue_rows.get_child(0).get_child(0)
	row.get_child(1).pressed.emit()
	_check(panel.queued[0].get("delivery") == "steer", "The phone queue card can convert a waiting task into a current-task adjustment")
	row = panel.chat.queue_rows.get_child(0).get_child(0)
	row.get_child(1).pressed.emit()
	var drafts: Array = panel._take_steering()
	_check(drafts.size() == 2 and drafts[0]["content"] == "Adjust the current task" and drafts[1]["content"] == "Then use the blue material", "Steering is delivered in arrival order while the independent task keeps its queue position")
	_check(panel.queued.size() == 1 and drafts[0]["files"] == ["workflow-reference"] and drafts[0]["references"] == ["res://project.godot"], "Steering preserves attachment IDs and project references without stealing the queued task")
	panel._send_or_queue("Adjustment for the old task only", "steer")
	panel.current_turn = "different-task"
	_check(not panel._has_steering() and panel._take_steering().is_empty() and panel.queued[-1].get("delivery") == "queue", "A pending adjustment cannot leak into another task with the same model and mode")
	panel._choose({"profile": "other-workflow", "model": "other"})
	var previous_tokens = panel.turn_input_tokens
	panel._set_usage({"prompt_tokens": 10, "completion_tokens": 3}, {"id": "workflow"}, "fixture")
	_check(panel.turn_input_tokens == previous_tokens + 10, "Changing the selected provider does not discard usage billed to the running task")
	panel._send_or_queue("Use the other provider", "steer")
	_check(panel.queued[-1].get("delivery") == "queue" and not panel._has_steering(), "A different provider cannot change the frozen running task through steering")
	panel.busy = false
	panel.queued.clear()
	panel.cancel = {}
	panel._choose({"profile": "workflow", "model": "fixture"})
	panel._new_conversation()
	var service = FixtureRedirectProvider.new()
	service.host = panel
	panel.providers = service
	panel.queued = [{"text": "Wait for explicit queue resume", "selection": panel._selection(), "delivery": "queue"}]
	panel.queue_paused = true
	await panel._start_chat("Generează o cutie 3D.")
	_check(panel.queue_paused and panel.queued.size() == 1, "Starting or finishing another task does not silently resume a paused queue")
	_check(service.requests == 2 and panel.harness.state == "completed" and not panel.cancel.get("cancelled", false), "The real panel and harness continue a steered task without cancelling the run")
	var users = panel.history.filter(func(message: Dictionary) -> bool: return message.get("role") == "user")
	_check(users.size() == 2 and users[0].get("turn_id") == users[1].get("turn_id") and users[1].get("delivery") == "steer", "The original request and adjustment persist in the same task")
	_check(panel.history.any(func(message: Dictionary) -> bool: return message.get("tool_name") == "asset_generate" and JSON.parse_string(message["content"]).get("code") == "steered"), "A pending correction prevents a superseded cloud generation from executing")
	var restored: Array = panel.conversations.load_active()
	_check(restored.any(func(message: Dictionary) -> bool: return message.get("delivery") == "steer" and message.get("turn_id") == panel.current_turn), "Delivered steering survives conversation reload")
	panel.mode_picker.select(3)
	panel._new_conversation()
	var ask = FixtureAskProvider.new()
	panel.providers = ask
	await panel._start_chat("Inspectează proiectul și explică-l fără modificări.")
	_check(ask.requests == 2 and panel.harness.state == "completed" and panel.planner.phase == "idle" and not FileAccess.file_exists("res://ask-must-not-exist.txt"), "Ask performs real project inspection while a requested file write remains unexecuted")
	_check(not ask.catalog.any(func(tool: Dictionary) -> bool: return tool.get("risk") != "read" or tool.get("name") in ["asset_status", "asset_wait", "task_update", "plan_ask"]), "Ask omits execution, automatic asset import and implementation-plan tools from the model catalog")
	var denied: Dictionary = await panel._execute_call("godot_write_file", {"path": "res://ask-must-not-exist.txt", "text": "Forbidden"})
	_check(denied.get("code") == "tool_unavailable" and not FileAccess.file_exists("res://ask-must-not-exist.txt"), "The dispatcher independently enforces Ask permissions even when called without deferred discovery")
	panel.busy = true
	panel.queued = [{"text": "Adaugă un nivel după sarcina curentă", "selection": panel._selection(), "delivery": "queue"}, {"text": "Păstrează scena și fă materialul albastru", "selection": panel._selection(), "delivery": "steer", "turn": panel.current_turn}]
	panel._sync_queue()
	await get_tree().process_frame
	await get_tree().process_frame
	var output = OS.get_environment("GODOT_AI_QA_OUTPUT")
	if not output.is_empty(): EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(output.path_join("workflow-queue-steer.png"))
	_check(panel.chat.queue_panel.visible and panel.chat.queue_rows.get_child_count() == 2 and panel.chat.scroll.size.y > 80, "Queue and steering cards leave the conversation visible in a narrow panel")
	panel.busy = false
	panel.queued.clear()
	panel._sync_queue()
	panel.providers = original_service
	panel.config["providers"] = original_profiles
	panel._refresh_profiles()
	panel._choose(selection)
	panel.mode_picker.select(mode)
	panel.full_control.button_pressed = full_control

func _chat_workflow_tests() -> void:
	panel.config["providers"] = [
		{"id": "qa-cloud", "name": "Fixture cloud", "issuer": "deepseek", "kind": "chat", "models": [{"id": "qa-code", "efforts": ["high"]}]},
		{"id": "qa-local", "name": "Fixture local", "issuer": "ollama", "kind": "chat", "models": [{"id": "qa-local-code"}]},
	]
	panel._refresh_profiles()
	panel._choose({"profile": "qa-cloud", "model": "qa-code", "effort": "high"})
	panel.busy = true
	panel._send_or_queue("Queued fixture instruction")
	panel._choose({"profile": "qa-local", "model": "qa-local-code"})
	_check(panel.queued.size() == 1 and panel.queued[0]["selection"]["profile"] == "qa-cloud" and panel.queued[0]["selection"]["effort"] == "high", "Queued messages retain provider, model and reasoning selection")
	_check(not panel.cancel.get("cancelled", false) and panel.queued[0].get("delivery") == "queue", "A queued message waits without cancelling the running task")
	panel.busy = false
	panel.cancel = {}
	panel.queued.clear()
	panel.history = [{"role": "user", "id": "fixture-history", "content": "Preserved fixture history"}]
	panel._persist_history()
	var original = str(panel.conversations.index["active"])
	panel._choose({"profile": "qa-cloud", "model": "qa-code"})
	_check(panel.history.size() == 1 and panel.history[0]["content"] == "Preserved fixture history", "Switch providers without clearing chat")
	panel._new_conversation()
	_check(panel.history.is_empty() and panel.conversations.select(original) and panel.conversations.load_active().size() == 1, "New conversation keeps the previous transcript")
	panel.history = panel.conversations.load_active()
	panel._new_conversation()
	var original_selection = panel._selection().duplicate()
	panel.chat.model_button.pressed.emit()
	panel.chat.picker_search.text = "Fixture local"
	panel.chat.picker_search.text_changed.emit(panel.chat.picker_search.text)
	_check(panel.chat.picker.visible and panel.chat.drawer_stage == "providers" and panel.chat.picker_list.item_count == 2 and panel.chat.picker_list.get_item_text(0).contains("locale"), "Composer opens searchable provider groups in a bottom drawer")
	await _tap_drawer("profile", "qa-local")
	_check(panel.chat.drawer_stage == "models" and panel.chat.picker_search.text.is_empty() and panel.chat.picker_list.item_count == 1, "Selecting a provider shows only its own models and clears the provider search")
	await _tap_drawer("model", "qa-local-code")
	_check(panel.chat.drawer_stage == "reasoning" and panel.chat.picker_list.item_count == 1 and panel.chat.drawer_hint.text.contains("Nu sunt disponibile"), "Model without declared reasoning levels offers only automatic reasoning")
	_check(panel._selection() == original_selection, "Provider and model changes remain pending until reasoning is chosen")
	panel.chat._close_drawer()
	_check(panel._selection() == original_selection, "Closing the drawer discards a pending model change")
	panel.chat.model_button.pressed.emit()
	await _tap_drawer("profile", "qa-cloud")
	panel.chat.picker_search.text = "qa-local-code"
	panel.chat.picker_search.text_changed.emit(panel.chat.picker_search.text)
	_check(panel.chat.picker_list.get_item_metadata(0) == null, "Model search cannot leak results from a different provider")
	panel.chat.picker_search.text = "qa-code"
	panel.chat.picker_search.text_changed.emit(panel.chat.picker_search.text)
	await _tap_drawer("model", "qa-code")
	_check(panel.chat.picker_list.item_count == 2 and panel.chat.picker_list.get_item_metadata(1).get("effort") == "high", "Reasoning drawer uses the selected model's provider-declared levels")
	panel.chat.drawer_back.pressed.emit()
	_check(panel.chat.drawer_stage == "models", "Reasoning drawer can return to model selection")
	await _tap_drawer("model", "qa-code")
	await _tap_drawer("effort", "high")
	_check(not panel.chat.picker.visible and panel._selection() == original_selection.merged({"profile": "qa-cloud", "model": "qa-code", "effort": "high"}, true) and panel.chat.reasoning_button.text == "Ridicat", "Reasoning choice applies provider, model and effort together and updates composer chips")
	panel.chat.reasoning_button.pressed.emit()
	_check(panel.chat.drawer_stage == "reasoning", "Reasoning chip reopens the current model's reasoning drawer directly")
	var escape = InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	panel.chat._input(escape)
	_check(not panel.chat.picker.visible and panel._selection()["effort"] == "high", "Escape closes reasoning without changing the selection")
	var fingerprints = {}
	for entry in embedded["providers"].CATALOG:
		var texture = panel.chat.provider_icon({"issuer": entry["id"]})
		_check(texture != null and not texture.get_image().is_empty(), "Provider icon renders: " + str(entry["id"]))
		if entry["id"] != "qwen-cn": fingerprints[texture.get_image().get_data().hex_encode().sha256_text()] = true
	_check(fingerprints.size() == embedded["providers"].CATALOG.size() - 1, "Each provider identity has a distinct vector emblem; Qwen regions share the same identity")
	for service in ["Claude", "Kimi", "GitHub Copilot"]:
		_check(panel.chat.provider_icon({"kind": "companion", "name": service}) != panel.chat._icon("Accounts"), "Subscription retains its provider emblem: " + service)
	panel.mode_picker.select(0)
	panel.full_control.button_pressed = false
	panel.cancel = {"cancelled": false}
	var decisions = {}
	_fixture_approval.call_deferred("first", decisions)
	_fixture_approval.call_deferred("second", decisions)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(panel.approval_pending and panel.approval_dialog.dialog_text.begins_with("first"), "Concurrent agent approvals have separate prompts")
	panel._decide(true)
	await get_tree().process_frame
	_check(decisions.get("first") == true and not decisions.has("second") and panel.approval_dialog.dialog_text.begins_with("second"), "One approval authorizes exactly one queued operation")
	panel._decide(false)
	await get_tree().process_frame
	_check(decisions.get("second") == false, "Second concurrent operation can be independently denied")
	panel.mode_picker.select(2)
	panel.full_control.button_pressed = false
	panel.config["providers"] = []
	panel._status("Configurează un furnizor din Setări pentru a începe.")
	panel._refresh_profiles()
	panel._render_history()

func _history_button_tests() -> void:
	panel._new_conversation()
	panel.history = [{"id": "audit-user", "role": "user", "content": "Transcript export fixture"}, {"id": "audit-answer", "role": "assistant", "content": "Answer fixture"}]
	panel._persist_history()
	panel._render_history()
	var id = str(panel.conversations.index["active"])
	var path = panel.conversations._path(id)
	panel.composer.text = "Draft stays with its own conversation"
	panel.chat.navigation_buttons["new"].pressed.emit()
	_check(panel.composer.text.is_empty() and panel.history.is_empty(), "New-chat button starts with an empty draft and transcript")
	panel.chat.action.emit("open", {"id": id})
	_check(panel.composer.text == "Draft stays with its own conversation" and panel.history.size() == 2, "Opening a conversation restores its own draft without mixing messages")
	var answer = panel.chat.message_records[-1]
	_check(answer["actions"][2].disabled, "Changes button is disabled for responses without any changes")
	answer["actions"][0].pressed.emit()
	_check(DisplayServer.clipboard_get() == "Answer fixture", "Message Copy button copies the selected response")
	panel.composer.clear()
	panel.chat.history_buttons["favorite"].pressed.emit()
	_check(panel.conversations.item(id)["favorite"] and "Elimină" in panel.chat.history_buttons["favorite"].tooltip_text, "Favorite button changes the active conversation and describes the reverse action")
	panel.chat.history_buttons["favorite"].pressed.emit()
	_check(not panel.conversations.item(id)["favorite"], "Favorite button can remove the same favorite")
	panel.chat.history_buttons["rename"].pressed.emit()
	var rename = panel.get_node("RenameConversation") as ConfirmationDialog
	var input = rename.find_children("*", "LineEdit", false, false)[0]
	input.text = "   "
	input.text_changed.emit(input.text)
	_check(rename.get_ok_button().disabled, "Rename rejects an empty conversation name")
	rename.get_cancel_button().pressed.emit()
	await get_tree().process_frame
	_check(panel.conversations.item(id)["title"] != "   ", "Cancel rename keeps the original title")
	panel.chat.history_buttons["rename"].pressed.emit()
	rename = panel.get_node("RenameConversation") as ConfirmationDialog
	input = rename.find_children("*", "LineEdit", false, false)[0]
	input.text = "  Audit renamed  "
	input.text_changed.emit(input.text)
	input.text_submitted.emit(input.text)
	await get_tree().process_frame
	_check(panel.chat.title.text == "Audit renamed" and panel.conversations.item(id)["title"] == "Audit renamed", "Rename submits the trimmed name and refreshes the actual chat title")
	panel.chat.history_buttons["export"].pressed.emit()
	var export_dialog = panel.get_node("ExportConversation") as FileDialog
	var export_path = panel.project_directory.path_join("audit-export.md")
	export_dialog.file_selected.emit(export_path)
	await get_tree().process_frame
	var exported = FileAccess.get_file_as_string(export_path)
	_check(exported.begins_with("# Audit renamed") and "Transcript export fixture" in exported and "Answer fixture" in exported, "Export button writes a Markdown file containing the active conversation")
	panel.chat.history_buttons["archive"].pressed.emit()
	_check(panel.conversations.item(id)["archived"] and panel.chat.archived.button_pressed and panel.chat.history_active and "Dezarhivează" in panel.chat.history_buttons["archive"].tooltip_text, "Archive keeps its conversation selected in the archive list and offers unarchive")
	panel.chat.history_buttons["archive"].pressed.emit()
	_check(not panel.conversations.item(id)["archived"] and not panel.chat.archived.button_pressed and panel.chat.history_active, "Unarchive returns the conversation to the normal history")
	panel.chat.search.text = "no matching conversation"
	panel.chat.search.text_changed.emit(panel.chat.search.text)
	_check(panel.chat.chats.item_count == 0 and panel.chat.history_buttons["delete"].disabled, "Filtered-out conversations cannot be deleted through an unrelated empty list")
	panel.chat.search.clear()
	panel.chat.search.text_changed.emit("")
	panel.busy = true
	panel.chat.set_working(true)
	_check(panel.chat.history_buttons.values().all(func(control: Button) -> bool: return control.disabled) and panel.chat.navigation_buttons["new"].disabled, "History mutations and new chat are visibly disabled while the agent works")
	panel.busy = false
	panel.chat.set_working(false)
	panel.chat.history_buttons["delete"].pressed.emit()
	var deletion = panel.get_node("DeleteConversation") as ConfirmationDialog
	_check("Audit renamed" in deletion.dialog_text and FileAccess.file_exists(path), "Delete opens a confirmation naming the unarchived conversation without deleting early")
	deletion.get_cancel_button().pressed.emit()
	await get_tree().process_frame
	_check(FileAccess.file_exists(path) and not panel.conversations.item(id).is_empty() and panel.history.size() == 2, "Cancel deletion preserves transcript, index and displayed messages")
	panel.chat.history_buttons["delete"].pressed.emit()
	deletion = panel.get_node("DeleteConversation") as ConfirmationDialog
	deletion.get_ok_button().pressed.emit()
	await get_tree().process_frame
	_check(not FileAccess.file_exists(path) and panel.conversations.item(id).is_empty() and str(panel.conversations.index["active"]) != id and panel.history == panel.conversations.load_active(), "Confirm Delete removes an unarchived transcript and displays the surviving active chat")
	var reloaded = embedded["conversations"].new()
	reloaded.configure(panel.project_directory)
	_check(reloaded.item(id).is_empty(), "Deleted conversations stay deleted after reopening their index")
	panel._new_conversation()
	panel.history = [{"id": "branch-first", "role": "user", "content": "Start"}, {"id": "branch-here", "role": "assistant", "content": "Fork here"}, {"id": "branch-later", "role": "user", "content": "Keep only in original"}]
	panel._persist_history()
	panel._render_history()
	var branch_original = str(panel.conversations.index["active"])
	var record = panel.chat.message_records[1]
	record["actions"][-1].get_popup().id_pressed.emit(0)
	_check(str(panel.conversations.index["active"]) != branch_original and panel.history.size() == 2 and panel.history[-1]["id"] == "branch-here", "Message menu forks at the selected response and excludes subsequent messages")
	var source_data: Dictionary = embedded["common"].read_json(panel.conversations._path(branch_original), {})
	_check(source_data.get("messages", []).size() == 3, "Forking through the message menu preserves the original transcript on disk")
	panel.chat.navigation_buttons["settings"].pressed.emit()
	_check(panel.settings_window.visible, "Header Settings button opens the actual settings window")
	panel.settings_window.get_ok_button().pressed.emit()
	_check(not panel.settings_window.visible, "Settings Close button closes its window")
	panel._new_conversation()
	panel.chat.search.clear()
	panel.chat.archived.set_pressed_no_signal(false)
	panel._refresh_conversations()
	DirAccess.remove_absolute(export_path)

func _settings_action_tests() -> void:
	panel._update_settings_controls()
	_check(panel.settings_actions["provider_delete"].disabled and panel.settings_actions["generation_delete"].disabled and panel.settings_actions["mcp_delete"].disabled, "Delete-profile buttons are disabled when no saved profile is being edited")
	_check(panel.settings_actions["job_preview"].disabled and panel.settings_actions["job_import"].disabled and panel.settings_actions["job_refresh"].disabled, "Generation result actions are disabled when there is no selection")
	var previous_profiles = panel.config["generation"].duplicate(true)
	var previous_jobs = panel.assets.jobs.duplicate(true)
	var previous_editing = panel.forms["generation"]["editing"]
	var path = panel.project_directory.path_join("button-preview.png")
	var image = Image.create(4, 3, false, Image.FORMAT_RGB8)
	image.fill(Color.RED)
	image.save_png(path)
	panel.config["generation"] = [{"id": "button-profile", "name": "Button fixture", "kind": "openai_image", "asset_kind": "image"}]
	panel.forms["generation"]["editing"] = "button-profile"
	panel.assets.jobs = [{"id": "button-first", "profile_id": "button-profile", "kind": "image", "status": "running"}, {"id": "button-ready", "profile_id": "button-profile", "kind": "image", "status": "completed", "file": path}]
	panel._refresh_lists()
	panel.lists["jobs"].select(1)
	panel.assets.jobs.reverse()
	panel._refresh_lists()
	_check(panel._selected_job().get("id") == "button-ready" and not panel.settings_actions["job_preview"].disabled and not panel.settings_actions["job_import"].disabled, "Updating and reordering generation results preserves their stable selection and enables ready actions")
	panel.settings_actions["job_preview"].pressed.emit()
	var previews = panel.generation_preview.get_children()
	_check(previews.size() == 1 and previews[0].texture != null and previews[0].texture.get_image().get_pixel(0, 0).r > 0.9, "Generation Preview button decodes the selected result into an actual image")
	panel.assets.jobs[0]["status"] = "running"
	panel._refresh_lists()
	_check(panel.settings_actions["job_preview"].disabled and panel.settings_actions["job_import"].disabled and not panel.settings_actions["job_refresh"].disabled, "Pending generation results allow refresh while preview and import remain unavailable")
	panel.busy = true
	panel._update_settings_controls()
	_check(panel.settings_actions.values().all(func(control: Button) -> bool: return control.disabled), "Settings actions that depend on mutable selection are disabled while another operation runs")
	panel.busy = false
	panel._update_settings_controls()
	panel.settings_actions["generation_delete"].pressed.emit()
	_check(panel.config["generation"].is_empty() and panel.settings_actions["generation_delete"].disabled and panel.settings_actions["job_refresh"].disabled and FileAccess.file_exists(path), "Delete-generation-profile button removes its profile, preserves generated files and disables stale actions")
	panel.config["generation"] = previous_profiles
	panel.assets.jobs = previous_jobs
	panel.forms["generation"]["editing"] = previous_editing
	for child in panel.generation_preview.get_children():
		panel.generation_preview.remove_child(child)
		child.queue_free()
	panel._refresh_lists()
	DirAccess.remove_absolute(path)
	await get_tree().process_frame

func _layout_tests() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_check(panel.chat.compose_panel.get_global_rect().encloses(panel.chat.model_button.get_global_rect()) and panel.chat.model_button.get_global_rect().position.y >= panel.composer.get_global_rect().end.y, "Compact model selector stays below the input inside the composer")
	_check(not panel.chat.model_button.get_global_rect().intersects(panel.chat.reasoning_button.get_global_rect()), "Model and reasoning chips do not overlap")
	_check(not panel.effort_picker.is_visible_in_tree() and not panel.full_control.is_visible_in_tree(), "Advanced agent controls stay out of the composer")
	var mode_button = panel.chat.options_button
	var mode_text_width = mode_button.get_theme_font("font").get_string_size(mode_button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, mode_button.get_theme_font_size("font_size")).x
	_check(mode_button.size.x >= mode_text_width + mode_button.get_theme_stylebox("normal").get_minimum_size().x + mode_button.get_theme_constant("icon_max_width") - 2, "Current mode icon and label fit without clipping")
	var scale = EditorInterface.get_editor_scale()
	_check(panel.chat.model_button.size.x <= 150 * scale + 1 and panel.chat.reasoning_button.size.x <= 112 * scale + 1, "Composer selection chips keep compact bounded widths")
	_check(panel.chat.model_button.size.y <= 32 * scale + 2 and panel.chat.send_button.size.y <= 32 * scale + 2 and panel.chat.options_button.size.y <= 32 * scale + 2, "Composer controls use the compact 32 pixel height")
	panel.chat._open_picker()
	await get_tree().process_frame
	await get_tree().process_frame
	print("AI drawer bounds: workspace=", panel.chat.root_column.get_global_rect(), " sheet=", panel.chat.drawer.get_global_rect(), " minimum=", panel.chat.drawer.get_combined_minimum_size())
	_check(panel.chat.root_column.get_global_rect().encloses(panel.chat.drawer.get_global_rect()), "Bottom drawer stays entirely inside the chat workspace")
	_check(panel.chat.drawer.get_global_rect().encloses(panel.chat.picker_list.get_global_rect()), "Drawer list fits inside the sheet and scrolls independently")
	panel.chat._close_drawer()
	_check(not panel.chat.stop_button.is_visible_in_tree(), "Idle chat hides Stop")
	panel.chat.set_working(true)
	_check(panel.chat.stop_button.is_visible_in_tree(), "Running chat shows Stop")
	await get_tree().process_frame
	_check(panel.chat.compose_panel.get_global_rect().encloses(panel.chat.stop_button.get_global_rect()) and panel.chat.compose_panel.get_global_rect().encloses(panel.chat.send_button.get_global_rect()), "Stop and send remain inside the composer while work is running")
	panel.chat.set_working(false)
	panel.speech.transcribing = true
	await get_tree().process_frame
	await get_tree().process_frame
	_check(panel.chat.stop_button.is_visible_in_tree(), "Voice transcription keeps Stop available")
	panel.speech.transcribing = false
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not panel.chat.stop_button.is_visible_in_tree(), "Completed voice work returns to the clean composer")
	panel.open_settings("accounts")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(panel.chatgpt_section.visible and not panel.companion_section.visible, "ChatGPT login is separate from companion configuration")
	panel.account_service.select(1)
	panel._select_account_service()
	_check(not panel.chatgpt_section.visible and panel.companion_section.visible and not panel.companion_connection.visible, "Claude has its own login view and collapsed connection details")
	_check(panel.forms["companion"]["account"].text == "claude" and not panel.forms["companion"]["account"].is_visible_in_tree(), "Account selection replaces manual service name entry")
	panel.account_service.select(0)
	panel._select_account_service()
	if panel.settings_navigation.visible:
		var font = panel.settings_navigation.get_theme_font("font")
		var font_size = panel.settings_navigation.get_theme_font_size("font_size")
		var longest = 0.0
		for index in range(panel.settings_navigation.item_count): longest = maxf(longest, font.get_string_size(panel.settings_navigation.get_item_text(index), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
		_check(panel.settings_navigation.size.x >= longest + 12, "Settings categories fit the actual font metrics")
	else:
		_check(panel.settings_category.visible and panel.settings_category.item_count == panel.settings_tabs.get_tab_count(), "Compact settings expose every main category through a full-width selector")
	_check(not panel.lists["accounts"].visible and not panel.lists["general"].visible, "Empty saved lists do not create blank sections")
	var initial_size = panel.settings_window.size
	panel.settings_window.size = Vector2i(420 * EditorInterface.get_editor_scale(), initial_size.y)
	await get_tree().process_frame
	panel._layout_settings()
	_check(panel.settings_category.visible and not panel.settings_navigation.visible, "Narrow settings switch to category dropdown without clipped names")
	panel.settings_window.size = initial_size
	panel._layout_settings()
	print("AI editor UI scale: ", EditorInterface.get_editor_scale())
	panel.settings_window.hide()

func _activity_capture(name: String) -> void:
	var output = OS.get_environment("GODOT_AI_QA_OUTPUT")
	if output.is_empty(): return
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))
	var geometry = {"activity": str(panel.chat.activity_panel.get_global_rect()), "composer": str(panel.chat.compose_panel.get_global_rect()), "details": str(panel.chat.activity_details.get_global_rect()), "rows": []}
	for row in panel.chat.activity_rows.get_children():
		if row.has_meta("state"): geometry.rows.append({"state": row.get_meta("state"), "size": str(row.size)})
	embedded.common.atomic_json(output.path_join(name + "-geometry.json"), geometry)

func _activity_drawer_tests() -> void:
	panel.settings_window.hide()
	var chat = panel.chat
	var saved_turn = panel.current_turn
	var saved_jobs = panel.agent_jobs.jobs
	var saved_busy = panel.busy
	chat.clear_messages()
	chat.thread.alignment = BoxContainer.ALIGNMENT_BEGIN
	chat.append_message("user", "Pregătește animațiile personajului și verifică scena.", {"id": "activity-visual-user"})
	chat.append_message("assistant", "Am verificat proiectul și scriptul. Continui cu animațiile, apoi testez scena.", {"id": "activity-visual-answer"})
	var snapshot = {"turn": "activity-visual", "phase": "executing", "intent": "execute", "steps": [{"step": "Inspectează proiectul și scena", "status": "completed"}, {"step": "Actualizează scriptul personajului", "status": "completed"}, {"step": "Pregătește animațiile personajului", "status": "in_progress"}, {"step": "Verifică tranzițiile și comenzile", "status": "pending"}, {"step": "Testează scena în editor", "status": "pending"}]}
	chat.begin_work("activity-visual", snapshot)
	panel.busy = true
	chat.show_status("Pregătesc animațiile personajului…", true)
	panel._harness_event({"kind": "tool_started", "id": "activity-animation", "name": "godot_call", "arguments": {}})
	chat.set_working(true)
	await get_tree().create_timer(0.2).timeout
	var between = []
	for index in range(chat.activity_panel.get_index() + 1, chat.compose_panel.get_index()):
		if chat.root_column.get_child(index).visible: between.append(chat.root_column.get_child(index))
	_check(chat.activity_panel.get_parent() == chat.compose_panel.get_parent() and chat.activity_panel.get_index() < chat.compose_panel.get_index() and between.is_empty() and chat.activity_panel.get_global_rect().end.y <= chat.compose_panel.get_global_rect().position.y + 1, "Activity status stays immediately above the composer, outside the conversation scroll")
	_check(chat.activity_counter.text == "2/5" and not chat.activity_details.visible and chat.activity_toggle.focus_mode == Control.FOCUS_ALL, "Running activity is compact, counts real completed steps and supports keyboard focus")
	_activity_capture("activity-collapsed")
	chat.activity_toggle.pressed.emit()
	await get_tree().create_timer(0.2).timeout
	var rows = chat.activity_rows.get_children().filter(func(item: Node) -> bool: return item.has_meta("state"))
	_check(chat.activity_details.visible and rows.size() == 5 and rows[0].get_meta("state") == "completed" and rows[2].get_meta("state") == "in_progress" and rows[4].get_meta("state") == "pending", "Expanding activity reveals completed, running and pending plan steps; operation history remains in Jurnal")
	_check(rows.slice(0, 5).all(func(row: Node) -> bool: return row.get_child(2).is_visible_in_tree() and row.get_child(2).size.x >= row.get_child(2).get_minimum_size().x and row.get_child(2).size.x > 20 * EditorInterface.get_editor_scale() and row.get_global_rect().grow(1).encloses(row.get_child(2).get_global_rect())), "Plan state captions reserve readable width inside each activity row")
	panel.current_turn = "activity-visual"
	panel.agent_jobs.jobs = {"child-done": {"id": "child-done", "parent": "activity-visual", "task": "Verifică structura proiectului", "kind": "Explore", "status": "completed"}, "child-running": {"id": "child-running", "parent": "activity-visual", "task": "Verifică animațiile și tranzițiile", "kind": "General", "status": "running"}}
	panel.agent_jobs.changed.emit("activity-visual")
	await get_tree().create_timer(0.2).timeout
	_check(chat.work_jobs.size() == 2 and chat.work_jobs[0].status == "completed" and chat.work_jobs[1].status == "running", "Background task events populate separate completed and running tasks in the drawer")
	_check(chat.activity_details.size.y <= maxf(48 * EditorInterface.get_editor_scale(), minf(200 * EditorInterface.get_editor_scale(), chat.root_column.size.y * 0.30)) + 1 and chat.get_global_rect().grow(1).encloses(chat.compose_panel.get_global_rect()), "Expanded activity has bounded height and keeps the composer visible")
	_check(chat.activity_rows.size.x <= chat.activity_details.size.x + 1, "Activity details wrap inside the available width without horizontal overflow")
	_activity_capture("activity-expanded")
	snapshot.steps[2].status = "completed"
	snapshot.steps[3].status = "in_progress"
	chat.show_work_plan(snapshot)
	_check(chat.activity_counter.text == "3/5" and chat.activity_details.visible, "Live plan updates preserve the drawer expansion and advance only confirmed completed steps")
	panel._harness_event({"kind": "tool_result", "id": "activity-animation", "name": "godot_call", "executed": true, "arguments": {}, "result": {"ok": false, "code": "permission_denied", "error": "Operația nu a fost autorizată."}})
	_check(JSON.parse_string(panel.journal.back()["result"]).get("code") == "permission_denied" and not chat.running_tools.visible, "Denied tool results stay in Jurnal and hide the active tool without claiming completion")
	snapshot.phase = "paused"
	chat.show_work_plan(snapshot)
	chat.finish_work("activity-visual", "cancelled")
	panel.busy = false
	chat.set_working(false)
	_check(chat.activity_counter.text == "3/5" and chat.status.text.contains("întreruptă") and chat.work_plan.steps[4].status == "pending", "Stopping keeps unfinished tasks visible without claiming full completion")
	await get_tree().create_timer(0.2).timeout
	_activity_capture("activity-interrupted")
	chat.show_work_jobs([])
	for item in snapshot.steps: item.status = "completed"
	snapshot.phase = "completed"
	chat.show_work_plan(snapshot)
	chat.finish_work("activity-visual", "completed")
	chat.activity_toggle.pressed.emit()
	_check(chat.activity_counter.text == "5/5" and chat.activity_panel.visible and not chat.activity_details.visible, "Completed progress remains available for later inspection in one compact row")
	chat.activity_toggle.pressed.emit()
	_check(chat.activity_details.visible, "Completed task details can be reopened")
	chat.begin_work("activity-new", {})
	panel.current_turn = "activity-new"
	panel.agent_jobs.changed.emit("activity-visual")
	_check(chat.work_plan.is_empty() and chat.work_jobs.is_empty() and not chat.activity_details.visible, "A new request clears previous progress and ignores events from an older task")
	panel.agent_jobs.jobs = saved_jobs
	panel.current_turn = saved_turn
	panel.busy = saved_busy
	chat.set_working(false)
	chat.reset_work()
	panel._render_history()

func _plan_and_markdown_screenshots(output: String) -> void:
	panel.mode_picker.select(0)
	panel.chat.show_plan({"turn": "visual-plan", "phase": "verifying", "intent": "execute", "steps": [{"step": "Inspectează scena și scripturile", "status": "completed"}, {"step": "Aplică modificările în proiect", "status": "completed"}, {"step": "Verifică rezultatul și importurile", "status": "in_progress"}], "explanation": "Sarcină cu mai multe etape; verific rezultatul înainte de finalizare."})
	panel.chat.append_message("assistant", "## Modificările sunt pregătite\n\nAm organizat scena și am păstrat setările existente.\n\n- Nodul **Player** folosește `CharacterBody3D`.\n- Mișcarea rămâne configurabilă din Inspector.\n\n> Urmează verificarea rezultatului în editor.\n\n| Element | Stare |\n| --- | --- |\n| Scenă | Pregătită |\n| Script | Verificat |\n\n[Documentația proiectului](https://docs.godotengine.org/)", {"id": "visual-formatted", "origin_label": "Godot AI · Auto", "profile_id": "visual-provider"})
	panel.chat.follow_bottom = true
	await get_tree().create_timer(0.2).timeout
	panel.chat._follow()
	await get_tree().create_timer(0.25).timeout
	_check(panel.chat.size.x <= panel.size.x + 2, "Formatted tables and plan steps stay inside the chat width")
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(output.path_join("formatted-chat.png"))
	panel.chat.plan_cards["visual-plan"]["node"].get_parent().move_child(panel.chat.plan_cards["visual-plan"]["node"], panel.chat.thread.get_child_count() - 1)
	panel.chat._follow()
	await get_tree().create_timer(0.2).timeout
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(output.path_join("structured-plan.png"))

func _control_settings_tests() -> void:
	_check(panel.Common.work_mode_index({"ui_mode": 1}) == 2 and panel.Common.work_mode_index({"work_mode": "default", "ui_mode": 1}) == 1, "Legacy Plan conversations restore read-only while new Default remains distinct")
	panel.mode_picker.select(1)
	_check(panel._mode() == 4 and "DEFAULT MODE" in panel._context_messages()[0]["content"] and "one or two short sentences" in panel._context_messages()[0]["content"], "Default is balanced and simple identity replies are instructed to stay compact")
	var form = panel.forms["generation"]
	form["kind"].select(2)
	panel._generation_fields(2, form["workflow_fields"], true)
	_check(not form["asset_kind"].disabled and not form["allow_http"].visible and not form["groups"]["url"].visible, "Meshy form supports images and meshes with a fixed secure endpoint")
	form["kind"].select(4)
	panel._generation_fields(4, form["workflow_fields"], true)
	_check(form["asset_kind"].selected == 0 and not form["workflow_import"].visible, "OpenAI Images form exposes PNG without unrelated workflow actions")
	form["kind"].select(3)
	panel._generation_fields(3, form["workflow_fields"], true)
	_check(not form["asset_kind"].disabled and form["kind"].item_count == 5, "Tripo supports both image and GLB profiles alongside existing generators")
	form["kind"].select(0)
	panel._generation_fields(0, form["workflow_fields"], true)
	_check(panel.section_tabs.has("integrations") and panel.section_tabs.has("skills") and panel.section_tabs.has("automations") and panel.section_tabs["skills"] == panel.section_tabs["integrations"] + 1 and panel.section_tabs["automations"] == panel.section_tabs["skills"] + 1 and panel.settings_tabs.get_tab_title(panel.section_tabs["agent"]) == "AGENT.MD", "Skills and tasks have main sections after Integrations")
	_check(panel.forms["general"].has("yolo") and panel.forms["general"].has("dock") and panel.forms["general"].has("sounds") and not panel.forms["general"].has("max_steps") and not panel.forms["general"].has("enabled"), "General exposes control preferences without technical runtime settings")
	_check(not "Permisiuni" in panel._settings_labels(panel.chat.runtime_options) and not "Extinde" in panel._settings_labels(panel.chat.runtime_options), "Work mode menu contains no permissions or duplicate expand action")
	panel.mode_picker.select(0)
	panel.full_control.button_pressed = false
	_check(panel._permission_mode() == 1, "YOLO off requires individual operation approval")
	panel.full_control.button_pressed = true
	_check(panel._permission_mode() == 2 and panel.config["preferences"]["yolo"], "YOLO preference is saved immediately and enables automatic operations")
	panel.mode_picker.select(2)
	_check(panel._permission_mode() == 3, "Plan stays read-only even with YOLO enabled")
	panel.mode_picker.select(0)
	panel._set_usage({"usedTokens": 500, "contextWindowTokens": 1000}, {"models": [{"id": "fixture", "context": 0}]}, "fixture")
	_check(panel.chat.context_label.text == "50%" and panel.chat.context_indicator.get_parent() == panel.chat.composer_controls, "Context filling is independently visible in the bottom toolbar and retains provider limits")
	panel._set_usage({"input_tokens": 500}, {}, "unknown")
	_check(panel.chat.context_label.text == "—" and "500" in panel.chat.context_label.tooltip_text, "Unknown context capacity never displays a fabricated percentage")
	var wave = panel._completion_stream()
	_check(wave.data.size() > 10000 and wave.mix_rate == 22050 and wave.format == AudioStreamWAV.FORMAT_16_BITS, "Completion sound is a playable native PCM asset without downloaded audio")
	panel.forms["github"]["repository"].text = "fixture/project"
	panel.forms["github"]["key"].text = "fixture-integration-key"
	panel.forms["github"]["enabled"].button_pressed = true
	var connected = panel._save_connections()
	var connection_file = FileAccess.get_file_as_string(panel.project_directory.path_join("integrations.json"))
	_check(connected and "fixture/project" in connection_file and not "fixture-integration-key" in connection_file and panel.forms["github"]["key"].text.is_empty(), "Integration configuration is project-scoped and credentials stay out of its JSON")
	panel.forms["github"]["enabled"].button_pressed = false
	panel._save_connections()
	var definitions = panel.active_definitions
	panel.active_definitions = panel.Workspace.definitions()
	panel.planner.reset("skills-fixture")
	var needs_plan = await panel._execute_call("skill_save", {"id": "unplanned-auto", "description": "Must plan", "instructions": "Do not write yet"})
	_check(needs_plan.get("code") == "plan_required" and not FileAccess.file_exists("res://.godot_ai/skills/unplanned-auto/SKILL.md"), "Auto enforces a plan before project changes even with YOLO")
	panel.mode_picker.select(1)
	var saved = await panel._execute_call("skill_save", {"id": "scene-check", "description": "Verifică o scenă", "instructions": "Inspectează nodurile, rulează verificările și raportează rezultatul."})
	_check(saved.get("ok", false) and FileAccess.file_exists("res://.godot_ai/skills/scene-check/SKILL.md") and panel.lists["skills"].item_count == 1, "Agent skill creation writes a portable SKILL.md and updates the manager")
	var read = panel.workspace.read("scene-check")
	_check(read.get("ok", false) and "scene-check" in panel.workspace.context(), "Enabled skills are discoverable and readable as project context")
	var stale = panel.workspace.save({"id": "scene-check", "description": "Changed", "instructions": "Should not overwrite", "expected_sha256": "stale"})
	_check(stale.get("code") == "skill_conflict", "A stale skill revision cannot overwrite newer instructions")
	panel.workspace.set_enabled("scene-check", false)
	_check(panel.workspace.read("scene-check").get("code") == "skill_disabled" and not "scene-check" in panel.workspace.context(), "Disabled skills are excluded from automatic context and agent reads")
	panel.workspace.set_enabled("scene-check", true)
	panel._edit_skill(0)
	_check(panel.forms["skill"]["instructions"].text.begins_with("Inspectează"), "Skill manager edits instructions without duplicating front matter")
	panel.mode_picker.select(2)
	var denied = await panel._execute_call("skill_save", {"id": "forbidden-plan", "description": "Denied", "instructions": "Must not write"})
	_check(not denied.get("ok", true) and not FileAccess.file_exists("res://.godot_ai/skills/forbidden-plan/SKILL.md"), "Plan cannot create skills through the editor dispatcher")
	panel.mode_picker.select(1)
	var deleted = panel.workspace.remove("scene-check", read["result"]["sha256"])
	var recovery = panel.tools.execute("godot_restore_file", {"index": deleted.get("result", {}).get("recovery", {}).get("recovery_index", -1)}, 2, true)
	_check(deleted.get("ok", false) and recovery.get("ok", false) and panel.workspace.read("scene-check").get("ok", false), "Skill deletion retains a working native recovery copy")
	panel._refresh_skills()
	panel.active_definitions = definitions
	panel.memory_editor.text = "# Memorie proiect\n\nPreferă scene mici și nume clare.\n"
	var memory = panel._save_memories()
	_check(memory.get("ok", false) and "Preferă scene mici" in FileAccess.get_file_as_string("res://AGENT.md") and "Preferă scene mici" in panel._reference_context(), "AGENT.MD edits a real project file included in subsequent context")
	panel.tools.execute("godot_write_file", {"path": "res://AGENT.md", "text": "# Schimbare manuală\n"}, 2, true)
	_check(panel._save_memories().get("code") == "memory_conflict" and FileAccess.get_file_as_string("res://AGENT.md").contains("manuală"), "Memory editor refuses to overwrite an external AGENT.md change")
	panel._load_memories()
	panel._record_event("fixture_log", {"step": 1}, {"ok": true, "result": "Verificare încheiată"})
	panel._refresh_journal(true)
	_check(panel.journal_console.text.contains("fixture_log") and panel.journal_console.text.contains("Verificare încheiată"), "Live journal shows chronological operation and result data in a console")
	panel.journal_filter.text = "fixture_log"
	panel.journal_filter.text_changed.emit(panel.journal_filter.text)
	panel._refresh_journal(true)
	_check(panel.journal_console.text.contains("fixture_log") and not panel.journal_console.text.contains("skill_save"), "Journal search filters activity without deleting stored entries")
	panel.journal_filter.clear()
	panel.journal_filter.text_changed.emit("")
	panel.full_control.button_pressed = false
	panel.planner.reset()

func _auto_compaction_tests() -> void:
	print("AI automatic context compaction")
	if panel.settings_window != null: panel.settings_window.hide()
	var original_service = panel.providers
	var original_profiles: Array = panel.config["providers"]
	var saved_preferences: Dictionary = panel.config["preferences"].duplicate(true)
	var saved_selection = panel._selection()
	var saved_history: Array = panel.history
	var saved_summary = panel.compact_summary
	var saved_through = panel.compact_through
	var saved_pending = panel.compact_pending
	var saved_tokens = panel.compact_tokens
	var saved_limit = panel.compact_limit
	var saved_failed = panel.compact_failed
	var saved_measurement: Dictionary = panel.context_measurement.duplicate(true)
	var saved_overflow = panel.compact_overflow_key
	var saved_queue: Array = panel.queued
	var saved_paused = panel.queue_paused
	var saved_mode = panel.mode_picker.selected
	panel.queued = []
	panel.queue_paused = false
	var summary_path = panel.project_directory.path_join("summary_" + str(panel.conversations.index["active"]) + ".json")
	var original_summary_exists = FileAccess.file_exists(summary_path)
	var original_summary_bytes = FileAccess.get_file_as_bytes(summary_path) if original_summary_exists else PackedByteArray()
	panel.config["providers"] = [{"id": "compact-fixture", "name": "Compact fixture", "issuer": "custom", "kind": "chat", "models": [{"id": "fixture", "context": 32768}]}]
	panel._refresh_profiles()
	panel._choose({"profile": "compact-fixture", "model": "fixture"})
	var service = FixtureCompactionProvider.new()
	panel.providers = service
	var profile = {"id": "compact-fixture", "models": [{"id": "fixture", "context": 32768}]}

	var form: Dictionary = panel.forms["general"]
	_check(form.has("auto_compact") and form["auto_compact"].button_pressed, "General exposes an enabled automatic context compaction switch")
	panel._control_preference("auto_compact", false)
	_check(not panel._auto_compact_enabled(), "Disabling automatic compaction is saved immediately")
	panel._control_preference("auto_compact", true)
	_check(panel._auto_compact_enabled(), "Automatic compaction can be re-enabled")
	panel.compact_limit = 32768
	_check(panel._compact_threshold() == 29491 and panel._compact_keep_recent() == 20000, "The default reserve and recent window follow the documented token budget")
	_check(panel._is_overflow_text("400 context_length_exceeded: maximum context length is 32768") and not panel._is_overflow_text("Connection refused"), "Overflow errors are recognized without treating ordinary failures as context overflows")

	panel.history = []
	for index in range(6):
		panel.history.append({"id": "compact-%d" % index, "role": "user" if index % 2 == 0 else "assistant", "content": ("Cerere %d. " % index) + "x".repeat(2400)})
	panel.history.append({"id": "compact-6", "role": "user", "content": "Cererea finală rămâne în context.\n" + "y".repeat(2400)})
	panel.config["preferences"]["compact_keep_recent"] = 1200
	panel.compact_summary = ""
	panel.compact_through = 0
	panel.compact_pending = false
	panel.compact_failed = false
	var cut = panel._compact_cut(panel._compact_keep_recent())
	_check(cut == 6 and panel.history[cut].get("role") == "user", "The automatic cut keeps the newest user turn and lands on a user boundary")
	await panel._start_compaction("manual")
	_check(service.requests == 1 and panel.compact_summary == service.summary and panel.compact_through == cut and not panel.busy and not panel.send_button.disabled, "Manual compaction summarizes the old range and keeps recent work verbatim")
	_check(not str(service.messages[-1][1].get("content", "")).contains("Cererea finală"), "Compaction input excludes the kept recent turn")
	var saved_file: Dictionary = panel.Common.read_json(summary_path, {})
	_check(saved_file.get("text") == service.summary and int(saved_file.get("through", 0)) == cut, "Compaction summary and cut are persisted for restore")
	panel._load_summary()
	_check(panel.compact_summary == service.summary and panel.compact_through == cut, "The saved summary is restored with the conversation")
	var context = panel._context_messages()
	_check(str(context[0]["content"]).contains("Earlier conversation summary") and context[1].get("id") == "compact-6", "The next request uses the summary plus the kept newest turn")
	service.requests = 0
	panel.compact_limit = 32768
	await panel._start_compaction("manual")
	_check(service.requests == 0 and panel.chat.status.text.contains("deja compactată"), "A conversation with no new range is not summarized again")

	panel.compact_summary = ""
	panel.compact_through = 0
	panel.compact_pending = true
	service.fail = true
	panel._record_context_measurement(profile, "fixture", panel.Harness.context_tokens(panel._context_messages()), {"prompt_tokens": 31000})
	await panel._start_compaction("auto")
	_check(service.requests == 1 and panel.compact_failed and not panel.compact_pending and panel.compact_through == 0, "A failed automatic summary keeps history intact and suppresses an immediate retry")
	service.fail = false

	panel.compact_pending = false
	panel.compact_tokens = 0
	panel.compact_limit = 32768
	panel._set_usage({"usedTokens": 31000, "contextWindowTokens": 32768}, profile, "fixture")
	_check(panel.compact_pending and panel.compact_tokens == 31000, "Usage above the reserved budget marks automatic compaction as pending")
	panel.compact_pending = false
	panel._set_usage({"usedTokens": 4000, "contextWindowTokens": 32768}, profile, "fixture")
	_check(not panel.compact_pending, "Usage well below the reserved budget does not schedule compaction")
	panel.compact_pending = false
	panel.compact_limit = 0
	panel._set_usage({"usedTokens": 900, "contextWindowTokens": 1024}, {"id": "compact-fixture", "models": []}, "fixture")
	_check(not panel.compact_pending and panel.compact_limit == 0, "Tiny context windows are left alone instead of using provider defaults")
	await _compaction_regression_tests(service, summary_path)
	await _context_pressure_tests(service)
	await _active_compaction_tests(service, summary_path)

	panel.providers = original_service
	panel.config["providers"] = original_profiles
	panel.config["preferences"] = saved_preferences
	panel.history = saved_history
	panel.compact_summary = saved_summary
	panel.compact_through = saved_through
	panel.compact_pending = saved_pending
	panel.compact_tokens = saved_tokens
	panel.compact_limit = saved_limit
	panel.compact_failed = saved_failed
	panel.context_measurement = saved_measurement
	panel.compact_overflow_key = saved_overflow
	panel.queued = saved_queue
	panel.queue_paused = saved_paused
	panel._refresh_profiles()
	panel._choose(saved_selection)
	panel.mode_picker.select(saved_mode)
	if original_summary_exists:
		var file = FileAccess.open(summary_path, FileAccess.WRITE)
		if file != null:
			file.store_buffer(original_summary_bytes)
			file.close()
	elif FileAccess.file_exists(summary_path): DirAccess.remove_absolute(summary_path)

func _compaction_regression_tests(service: RefCounted, summary_path: String) -> void:
	var previous = "Obiectiv păstrat: conservă scena originală res://forest.tscn."
	panel.compact_summary = previous
	panel.compact_through = 2
	_check(panel._persist_summary() == OK, "Regression setup persists the previous verified summary")
	var saved = panel.Common.read_json(summary_path, {})
	var invalid = [
		{"ok": true, "message": {"content": ""}},
		{"ok": true, "message": {"content": " \n\t "}},
		{"ok": true, "message": {"content": null}},
		{"ok": true, "message": "invalid"},
		{"ok": true, "message": {"content": "Rezumat incomplet"}, "finish": "length"},
		{"ok": true, "message": {"content": "x".repeat(20000)}}
	]
	for index in range(invalid.size()):
		service.replies = [invalid[index], invalid[index]]
		await panel._start_compaction("manual")
		_check(panel.compact_failed and panel.compact_through == 2 and panel.compact_summary == previous, "Invalid summary preserves the active context: %d" % index)
		_check(panel.Common.read_json(summary_path, {}) == saved, "Invalid summary preserves the saved context: %d" % index)
	service.replies.clear()
	panel.config["providers"][0]["models"][0]["efforts"] = ["low", "high", "max"]
	_check(panel._compaction_effort(panel._current_profile(), "fixture") == "low" and panel._compaction_effort({}, "unknown").is_empty() and panel._compaction_effort({"models": [{"id": "fixture", "efforts": ["high"]}]}, "fixture").is_empty(), "Auxiliary summaries use only declared low effort and never invent unsupported parameters")
	var requests = service.requests
	service.replies = [{"ok": true, "message": {"content": "", "reasoning_content": "PRIVATE_REASONING_NOT_FOR_LOGS"}, "finish": "length", "usage": {"completion_tokens": 4096, "completion_tokens_details": {"reasoning_tokens": 4096}}}]
	await panel._start_compaction("manual")
	_check(not panel.compact_failed and service.requests == requests + 2 and panel.compact_summary == service.summary, "An output-limited reasoning-only summary retries once and commits only a complete response")
	_check(service.output_limits[-2] == 8192 and service.output_limits[-1] == 16384 and service.efforts[-1] == "low", "The retry reserves extra generation tokens while the main agent effort remains untouched")
	_check(str(service.messages[-1][0]["content"]).contains("16384 UTF-8 bytes") and service.messages[-1][1] == service.messages[-2][1], "Summary retries retain the visible summary limit and replay the same uncommitted source range")
	var responses: Array = panel.journal.filter(func(entry: Dictionary) -> bool: return entry.get("tool") == "agent_compaction_response")
	var diagnostic: Dictionary = JSON.parse_string(str(responses[-2]["result"]))
	_check(diagnostic.get("code") == "incomplete_summary" and diagnostic.get("finish") == "length" and diagnostic.get("text_bytes") == 0 and int(diagnostic.get("usage", {}).get("completion_tokens_details", {}).get("reasoning_tokens", 0)) == 4096, "Summary diagnostics distinguish reasoning-only truncation from an ordinary empty response")
	_check(responses[-1]["arguments"].get("attempt") == 2 and responses[-1]["arguments"].get("output_tokens") == 16384 and not str(responses).contains("PRIVATE_REASONING_NOT_FOR_LOGS"), "Summary retry diagnostics record the budget without storing reasoning text")
	panel.compact_through = 2
	panel.compact_summary = previous
	panel._persist_summary()
	saved = panel.Common.read_json(summary_path, {})
	service.cancel_after_reply = true
	await panel._start_compaction("manual")
	service.cancel_after_reply = false
	_check(panel.compact_through == 2 and panel.compact_summary == previous and panel.chat.status.text.contains("oprită"), "A late successful response after Stop cannot commit a summary")
	_check(panel.Common.read_json(summary_path, {}) == saved, "Stop leaves the saved summary unchanged")
	# Block only the summary destination, leaving journal writes available.
	var backup = summary_path + ".qa-backup"
	_check(DirAccess.rename_absolute(summary_path, backup) == OK and DirAccess.make_dir_absolute(summary_path) == OK, "A directory collision blocks only the summary save destination")
	await panel._start_compaction("manual")
	_check(panel.compact_failed and panel.compact_through == 2 and panel.compact_summary == previous, "A failed summary save cannot advance the active history boundary")
	_check(DirAccess.dir_exists_absolute(summary_path) and panel.Common.read_json(backup, {}) == saved, "Save failure preserves the blocked destination and original summary bytes")
	_check(DirAccess.remove_absolute(summary_path) == OK and DirAccess.rename_absolute(backup, summary_path) == OK and panel.Common.read_json(summary_path, {}) == saved, "The save-failure fixture restores its original summary destination")
	panel.Common.atomic_json(summary_path, {"text": " \n", "through": 6})
	panel._load_summary()
	_check(panel.compact_through == 0, "A legacy empty summary cannot hide original history after restart")

	panel.config["providers"][0]["models"][0]["context"] = 8192
	panel.compact_limit = 1048576
	_check(panel._compaction_window(panel._current_profile(), "fixture") == 8192 and panel._compaction_window({}, "unknown") == 0, "Summary budgets use the selected model and an unpublished window is never guessed or inherited")
	var scaled_agent = embedded["harness"].new(panel)
	scaled_agent._context_window = 1048576
	_check(scaled_agent._result_limit() == 131072 and scaled_agent._batch_limit() == 262144, "Tool-output budgets scale with the model window; small or unpublished windows keep the current floors")
	panel.config["preferences"]["compact_keep_recent"] = 256
	panel.history = []
	for index in range(40):
		panel.history.append({"role": "user" if index % 2 == 0 else "assistant", "content": "BEGIN_%02d " % index + "Păstrează mesh-ul și scena originală. 🌲 ".repeat(100) + " END_%02d" % index})
	panel.history[10]["content"] += " Text lung. ".repeat(1500) + " LONG_MESSAGE_TAIL"
	panel.history.append({"role": "assistant", "content": "", "tool_calls": [{"name": "godot_write_file", "arguments": {"path": "res://original.gd", "text": "TOOL_ARGUMENT_MARKER"}}]})
	panel.history.append({"role": "user", "content": "Ultima cerere rămâne textuală: KEEP_NEWEST"})
	panel.compact_through = 0
	panel.compact_summary = "PREVIOUS_BEGIN " + "Istoric anterior. ".repeat(1500) + " PREVIOUS_END"
	var history_copy = panel.history.duplicate(true)
	service.messages.clear()
	service.output_limits.clear()
	service.requests = 0
	# First request models a provider whose tokenizer needs an even smaller batch.
	service.replies = [{"ok": false, "code": "context_length_exceeded", "error": "maximum context length"}]
	await panel._start_compaction("manual")
	_check(not panel.compact_failed and panel.compact_through == panel.history.size() - 1 and service.requests > 2, "A long conversation and oversized previous summary compact in bounded batches")
	var sent = ""
	var max_budget = 0
	var bounded = true
	for index in range(service.messages.size()):
		var context: Array = service.messages[index]
		var tokens = int(service.output_limits[index]) + 256
		for message in context: tokens += int(ceil(str(message["content"]).to_utf8_buffer().size() / 2.0)) + 12
		max_budget = maxi(max_budget, tokens)
		bounded = bounded and tokens <= 8192 and int(service.output_limits[index]) > 0
		sent += str(context[1]["content"])
	_check(bounded, "Every summary request reserves output and framing inside the 8192-token conservative budget")
	_check(str(service.messages[1][1]["content"]).length() < str(service.messages[0][1]["content"]).length(), "Provider overflow retries with a smaller source batch")
	var covered = true
	for index in range(40): covered = covered and sent.contains("BEGIN_%02d" % index) and sent.contains("END_%02d" % index)
	_check(covered and sent.contains("LONG_MESSAGE_TAIL") and sent.contains("PREVIOUS_BEGIN") and sent.contains("PREVIOUS_END") and sent.contains("TOOL_ARGUMENT_MARKER"), "Batches include every source range, long-message tails, prior summary and tool arguments")
	_check(not sent.contains("KEEP_NEWEST") and not sent.contains("�") and panel.history == history_copy, "Batching preserves Unicode, full saved history and the newest request")
	_check(str(service.messages[-1][0]["content"]).contains(service.summary), "Later batches extend the last validated summary")
	_check(panel.Common.read_json(summary_path, {}).get("through") == panel.compact_through, "Only the complete validated batch sequence is committed")
	panel.compact_summary = previous
	panel.compact_through = 0
	panel._persist_summary()
	service.replies = [{"ok": true, "message": {"content": service.summary}}, {"ok": false, "error": "Second batch failed"}]
	await panel._start_compaction("manual")
	_check(panel.compact_failed and panel.compact_summary == previous and panel.compact_through == 0, "Failure after a successful intermediate batch rolls back the whole compaction")
	_check(panel.Common.read_json(summary_path, {}).get("text") == previous and panel.Common.read_json(summary_path, {}).get("through") == 0, "Intermediate batches never replace the durable summary")
	var output = OS.get_environment("GODOT_AI_QA_OUTPUT")
	if not output.is_empty(): panel.Common.atomic_json(output.path_join("compact-regressions.json"), {"window": 8192, "largest_reserved_estimate": max_budget, "bounded": bounded, "all_source_markers_sent": covered, "history_preserved": panel.history == history_copy})

func _context_pressure_tests(service: RefCounted) -> void:
	var profile: Dictionary = panel._current_profile()
	var previous_window = profile["models"][0]["context"]
	var previous_history: Array = panel.history
	var previous_summary = panel.compact_summary
	var previous_through = panel.compact_through
	var previous_meter: Dictionary = panel.context_measurement.duplicate(true)
	var previous_overflow = panel.compact_overflow_key
	var previous_failed = panel.compact_failed
	var previous_cancel: Dictionary = panel.cancel
	profile["models"][0]["context"] = 1048576
	panel.context_measurement.clear()
	panel.compact_overflow_key = ""
	panel.compact_failed = false
	panel.cancel = {"cancelled": false}
	var messages = [{"role": "user", "content": "x".repeat(150000), "attachments": []}]
	for index in range(4): messages[0]["attachments"].append({"data": "a".repeat(1024 * 1024), "mimeType": "image/png"})
	panel.compact_pending = true # Old small-model / Base64 estimate must be discarded.
	var requests = service.requests
	var ready: Dictionary = await panel._prepare_agent_context(profile, "fixture", messages, [], false)
	_check(ready.get("ok", false) and not ready.get("compacted", false) and service.requests == requests and not panel.compact_pending, "A 50k-token conversation plus four large screenshots never compacts a 1M model due to a stale flag")
	var estimate = panel.Harness.context_tokens(messages)
	panel._record_context_measurement(profile, "fixture", estimate, {"prompt_tokens": 100000})
	var pressure: Dictionary = panel._context_pressure(profile, "fixture", messages, [])
	_check(pressure["used"] == 100000 and pressure["source"] == "provider+estimated_delta" and not panel.compact_pending, "Provider input usage takes precedence over a local estimate and cumulative spending")
	messages.append({"role": "assistant", "content": "delta ".repeat(500)})
	pressure = panel._context_pressure(profile, "fixture", messages, [])
	_check(pressure["used"] > 100000 and pressure["used"] < 102000, "New content adds only its estimated delta to the latest measured request")
	var main_tokens = panel.compact_tokens
	panel._set_usage({"prompt_tokens": 950000, "completion_tokens": 2000}, profile, "fixture", false)
	_check(panel.compact_tokens == main_tokens and not panel.compact_pending and panel.context_measurement["input"] == 100000, "An auxiliary summary cannot overwrite the main context meter or trigger another summary")
	panel._record_context_measurement(profile, "fixture", panel.Harness.context_tokens(messages), {"prompt_tokens": 950000})
	pressure = panel._context_pressure(profile, "fixture", messages, [])
	_check(panel.compact_pending and pressure["threshold"] == 943718, "A real measured load above 90 percent schedules one compaction")
	panel._set_usage({"prompt_tokens": 100000}, profile, "fixture")
	_check(not panel.compact_pending, "A lower measured load clears a previously pending automatic compaction")
	var other = {"id": profile["id"], "models": [{"id": "large-other", "context": 1048576}]}
	panel.compact_pending = true
	pressure = panel._context_pressure(other, "large-other", [{"role": "user", "content": "Hello"}], [])
	_check(not panel.compact_pending and pressure["used"] < 100 and pressure["source"] == "estimate", "Changing model drops the previous measurement and pending threshold")
	var deepseek = {"id": "direct", "issuer": "deepseek", "models": [{"id": "deepseek-flash", "context": 1048576, "max_output_tokens": 393216}]}
	_check(panel._context_reserve(deepseek, "deepseek-flash", 1048576) >= 65536, "DeepSeek leaves room for its default reasoning output instead of using an unrelated tiny reserve")
	# Real automatic dispatch: calibrate a small local estimate against high
	# provider usage, then verify the resulting summary is not run again.
	panel.history = []
	for index in range(8): panel.history.append({"role": "user" if index % 2 == 0 else "assistant", "content": "evidence ".repeat(1500)})
	panel.history.append({"role": "user", "content": "Keep the latest request"})
	panel.compact_summary = ""
	panel.compact_through = 0
	panel.compact_failed = false
	panel.config["preferences"].erase("compact_keep_recent")
	panel._record_context_measurement(profile, "fixture", panel.Harness.context_tokens(panel._context_messages()), {"prompt_tokens": 950000})
	requests = service.requests
	await panel._start_compaction("auto")
	_check(panel.compact_through > 0 and service.requests > requests and not panel.compact_pending, "Measured near-limit usage dispatches automatic compaction even when the tokenizer estimate is much smaller")
	requests = service.requests
	await panel._start_compaction("auto")
	_check(service.requests == requests, "A successful compaction is not immediately repeated below the trigger threshold")
	panel.config["preferences"]["compact_keep_recent"] = 256
	panel.history = previous_history
	panel.compact_summary = previous_summary
	panel.compact_through = previous_through
	panel._persist_summary()
	panel.context_measurement = previous_meter
	panel.compact_overflow_key = previous_overflow
	panel.compact_failed = previous_failed
	panel.cancel = previous_cancel
	profile["models"][0]["context"] = previous_window

func _active_compaction_tests(service: RefCounted, summary_path: String) -> void:
	var saved_turn = panel.current_turn
	var saved_origin: Dictionary = panel.current_origin
	var saved_mode = panel.active_mode
	var saved_cancel: Dictionary = panel.cancel
	panel.current_turn = "active-compaction"
	panel.current_origin = {"profile_id": "compact-fixture", "model_id": "fixture"}
	panel.active_mode = 4
	panel.busy = true
	panel.cancel = {"cancelled": false}
	panel.history = [{"role": "user", "content": "ORIGINAL_REQUEST: Keep res://original.tscn and generate only one tree.", "turn_id": panel.current_turn}]
	for index in range(24):
		if index == 4: panel.history.append({"role": "user", "content": "STEER_REQUEST: Use blue leaves, preserve the existing mesh.", "delivery": "steer", "turn_id": panel.current_turn})
		panel.history.append({"role": "assistant", "tool_calls": [{"id": "inspect-%d" % index, "name": "godot_files", "arguments": {}}], "turn_id": panel.current_turn})
		panel.history.append({"role": "tool", "tool_call_id": "inspect-%d" % index, "tool_name": "godot_files", "content": JSON.stringify({"ok": true, "result": "EXACT_OUTPUT_%d " % index + "Existing project evidence. ".repeat(200)}), "turn_id": panel.current_turn})
	panel.compact_through = 0
	panel.compact_summary = ""
	panel.compact_pending = true
	panel.compact_failed = false
	panel.config["providers"][0]["models"][0]["context"] = 8192
	panel.config["preferences"]["compact_keep_recent"] = 256
	var original: Array = panel.history.duplicate(true)
	_check(panel._history_context().size() == panel.history.size() and panel.history.size() > 24, "The full retained history is sent to the model without a message-count window")
	_check(panel._history_context().filter(func(message: Dictionary) -> bool: return message.get("role") == "user").size() == 2, "The full retained history preserves the original task and the steering message")
	var plan: Dictionary = panel.planner.snapshot()
	var verification: Dictionary = panel.verification.snapshot()
	var token: Dictionary = panel.cancel
	var result: Dictionary = await panel._prepare_agent_context(panel._current_profile(), "fixture", panel._context_messages(), [], false)
	_check(result.get("ok", false) and result.get("compacted", false) and panel.compact_through > 10 and panel.busy and panel.cancel == token, "Semantic compaction advances inside a running task without resetting busy state or cancellation")
	_check(panel.history == original and panel.planner.snapshot() == plan and panel.verification.snapshot() == verification, "Mid-task compaction preserves the full transcript, plan and acceptance evidence")
	var context: Array = result.get("result", [])
	_check(context.filter(func(message: Dictionary) -> bool: return message.get("role") == "user").map(func(message: Dictionary) -> String: return str(message["content"])) == original.filter(func(message: Dictionary) -> bool: return message.get("role") == "user").map(func(message: Dictionary) -> String: return str(message["content"])), "The original request and delivered steering remain exact user messages beyond the summary boundary")
	_check(context[-2] == original[-2] and context[-1] == original[-1], "The latest assistant/tool batch survives active compaction verbatim")
	var saved: Dictionary = panel.Common.read_json(summary_path, {})
	panel._load_summary()
	_check(panel.compact_through == int(saved["through"]) and panel._history_context().filter(func(message: Dictionary) -> bool: return message.get("role") == "user").size() == 2, "Restoring the saved summary reconstructs exact current-task user anchors from retained history")
	panel.compact_through = 0
	panel.compact_summary = "Previous validated summary"
	panel._persist_summary()
	saved = panel.Common.read_json(summary_path, {})
	panel.compact_pending = true
	service.fail = true
	result = await panel._prepare_agent_context(panel._current_profile(), "fixture", panel._context_messages(), [], false)
	service.fail = false
	_check(result.get("ok", false) and not result.get("compacted", false) and panel.compact_failed and panel.compact_through == 0 and panel.compact_summary == "Previous validated summary" and panel.Common.read_json(summary_path, {}) == saved, "A failed mid-task summary returns usable context without changing the durable summary")
	var requests = service.requests
	var retained: Array = panel._context_messages()
	result = await panel._prepare_agent_context(panel._current_profile(), "fixture", retained, [], true)
	_check(result.get("ok", false) and result.get("result") == retained and service.requests == requests, "A cached summary failure permits resume and overflow recovery without repeatedly calling the summarizer")

	# Exercise the actual harness with the real panel preparation hook: two
	# failed auxiliary responses must not prevent the main provider request.
	panel.compact_failed = false
	panel.compact_pending = true
	service.replies = [{"ok": true, "message": {"content": ""}, "finish": "stop"}, {"ok": true, "message": {"content": ""}, "finish": "stop"}]
	var provider_contexts = []
	var agent = embedded["harness"].new(panel)
	var hooks = {
		"prepare_context": func(messages: Array, definitions: Array, force: bool) -> Dictionary: return await panel._prepare_agent_context(panel._current_profile(), "fixture", messages, definitions, force),
		"complete": func(messages: Array, _definitions: Array, _stopping: Dictionary, _delta: Callable) -> Dictionary:
			provider_contexts.append(messages.duplicate(true))
			return {"ok": true, "message": {"role": "assistant", "content": "Provider reached after failed summary."}, "finish": "stop"}
	}
	var outcome: Dictionary = await agent.run({"messages": retained.duplicate(true), "tools": [], "cancel": panel.cancel, "context_window": 8192}, hooks)
	_check(outcome.get("status") == "completed" and provider_contexts.size() == 1 and service.requests == requests + 2 and outcome.get("compactions") == 0, "Two empty summaries do not stop the actual harness before its main provider request")
	_check(panel.history == original and panel.Common.read_json(summary_path, {}) == saved and panel.planner.snapshot() == plan and panel.verification.snapshot() == verification, "Fallback preserves full history, durable summary, plan and verification evidence")
	_check(provider_contexts[0][-2] == retained[-2] and provider_contexts[0][-1] == retained[-1] and outcome.get("context_pruned", 0) > 0, "Fallback bounds old tool results but preserves the latest tool batch verbatim")
	_check(provider_contexts[0].filter(func(message: Dictionary) -> bool: return message.get("role") == "user") == retained.filter(func(message: Dictionary) -> bool: return message.get("role") == "user"), "Fallback leaves the original request and steering messages exact")
	panel.compact_failed = false
	var backup = summary_path + ".active-qa-backup"
	_check(DirAccess.rename_absolute(summary_path, backup) == OK and DirAccess.make_dir_absolute(summary_path) == OK, "Active compaction fixture blocks only the summary checkpoint destination")
	result = await panel._prepare_agent_context(panel._current_profile(), "fixture", retained, [], true)
	_check(not result.get("ok", true) and result.get("code") == "summary_save_failed" and panel.compact_through == 0 and panel.compact_summary == "Previous validated summary", "A failed durable summary checkpoint remains an explicit blocking error")
	_check(DirAccess.remove_absolute(summary_path) == OK and DirAccess.rename_absolute(backup, summary_path) == OK and panel.Common.read_json(summary_path, {}) == saved, "Active summary checkpoint failure leaves the original durable context recoverable")
	panel.compact_failed = false
	service.cancel_after_reply = true
	result = await panel._prepare_agent_context(panel._current_profile(), "fixture", panel._context_messages(), [], true)
	service.cancel_after_reply = false
	_check(result.get("code") == "cancelled" and panel.compact_through == 0 and panel.Common.read_json(summary_path, {}) == saved, "Stop during semantic compaction cannot commit a late successful summary")
	panel.busy = false
	panel.current_turn = saved_turn
	panel.current_origin = saved_origin
	panel.active_mode = saved_mode
	panel.cancel = saved_cancel

func _blender_mesh_verification_tests() -> void:
	_check(Engine.is_editor_hint(), "Blender GLB readiness is tested inside the real editor")
	var root_mesh = MeshInstance3D.new()
	root_mesh.mesh = BoxMesh.new()
	_check(embedded["termux_blender"].scene_mesh_count(root_mesh) == 1, "A geometry-bearing root mesh is included in readiness checks")
	root_mesh.mesh = ArrayMesh.new()
	_check(embedded["termux_blender"].scene_mesh_count(root_mesh) == 0, "An empty mesh resource cannot establish readiness")
	root_mesh.free()
	var scene = Node3D.new()
	var cube = MeshInstance3D.new()
	cube.mesh = BoxMesh.new()
	scene.add_child(cube)
	cube.owner = scene
	var directory = panel.data_directory.path_join("qa-blender-import")
	DirAccess.make_dir_recursive_absolute(directory)
	var path = directory.path_join("probe.glb")
	var document = GLTFDocument.new()
	var state = GLTFState.new()
	var exported = document.append_from_scene(scene, state) == OK and document.write_to_filesystem(state, path) == OK
	scene.free()
	_check(exported, "Create a real cube GLB for editor-mode Blender verification")
	if not exported: return
	state = GLTFState.new()
	var parsed = document.append_from_file(path, state) == OK
	var imported = document.generate_scene(state) if parsed else null
	_check(imported != null and not imported.find_children("*", "ImporterMeshInstance3D", true, false).is_empty(), "Editor GLB imports expose ImporterMeshInstance3D, reproducing the reported false empty_mesh")
	if imported != null: imported.free()
	var backend = embedded["termux_blender"].new(panel)
	backend.configure(directory, directory.path_join("project"))
	backend.connected = true
	backend.pending = {"id": panel.Common.uid(), "kind": "verify"}
	var transport = FixtureBlenderVerification.new()
	transport.data = FileAccess.get_file_as_bytes(path)
	backend.transport = transport
	var runtime = {"kind": "fixture", "executable": "/fixture/blender", "version": "fixture", "capabilities": {"formats": ["glb"]}}
	transport.verification = {"runtime": runtime, "artifacts": [{"path": "probe.glb", "bytes": transport.data.size(), "sha256": FileAccess.get_sha256(path)}]}
	var result = await backend._resume({})
	_check(result.get("ok", false) and backend.available() and backend.pending.is_empty() and transport.acknowledged and transport.submissions == 0, "Recovering the completed verification accepts editor mesh geometry and saves readiness without another Blender submission")
	var empty_importer = ImporterMeshInstance3D.new()
	empty_importer.mesh = ImporterMesh.new()
	_check(embedded["termux_blender"].scene_mesh_count(empty_importer) == 0, "An importer node without mesh surfaces stays unavailable")
	empty_importer.free()

func _termux_blender_card_tests() -> void:
	var old_card = panel.forms["blender"]["container"].get_parent().get_parent()
	var page = old_card.get_parent()
	page.remove_child(old_card)
	old_card.queue_free()
	var backend = embedded["termux_blender"].new(panel)
	var base = panel.data_directory.path_join("simple-blender")
	backend.configure(base, base.path_join("project"))
	var device = {"ok": true, "installed": false, "permission": false, "supported": true, "launch_mode": "manual"}
	var calls = []
	var native_call = func(action: String, _args: Dictionary) -> Dictionary:
		calls.append(action)
		if action == "status": return device.duplicate()
		if action == "connection": return {"ok": true, "url": "http://127.0.0.1:34567", "token": "b".repeat(64)}
		if action == "start": return {"ok": false, "code": "termux_start_failed", "error": "Fixture external commands disabled"}
		return {"ok": true}
	backend.native_override = native_call
	var transport = FixtureBlenderVerification.new()
	var source = panel.data_directory.path_join("qa-blender-import/probe.glb")
	transport.data = FileAccess.get_file_as_bytes(source)
	var runtime = {"kind": "proot", "container": "debian", "executable": "/usr/bin/blender", "version": "Blender 4.3.2", "binary_stamp": "fixture", "capabilities": {"formats": ["glb", "fbx"], "render_cpu": true}}
	transport.verification = {"runtime": runtime, "artifacts": [{"path": "probe.glb", "bytes": transport.data.size(), "sha256": FileAccess.get_sha256(source)}]}
	backend.transport = transport
	panel.integrations.termux = backend
	backend.changed.connect(panel._refresh_blender_card)
	backend.diagnostic.connect(panel._blender_diagnostic)
	backend.workflow_finished.connect(panel._blender_workflow_finished)
	panel._build_termux_blender(page)
	panel.open_settings("integrations")
	await get_tree().create_timer(.2).timeout
	var form: Dictionary = panel.forms["blender"]
	var output = OS.get_environment("GODOT_AI_QA_OUTPUT")
	_check(form["primary"].text == "Instalează Termux" and not form["hint"].visible, "Missing Termux shows only its install action")
	_check(not form.has("logs") and not form.has("enabled") and not form.has("verify") and not form.has("cancel"), "The Blender card has no technical controls, activation checkbox or embedded console")
	form["primary"].pressed.emit()
	_check(calls.has("install_termux") and not calls.has("copy_bootstrap"), "Install Termux opens the native store action without running any commands")
	panel._refresh_journal(true)
	_check(panel.journal_console.text.contains("blender_connection"), "Blender diagnostics remain accessible in the main journal")
	device["installed"] = true
	await backend.refresh()
	_check(form["primary"].text == "Instalează Blender" and transport.submissions == 0, "Returning after installing Termux exposes Blender installation without starting it silently")
	panel.settings_tabs.get_tab_control(panel.section_tabs["integrations"]).scroll_vertical = 10000
	await get_tree().create_timer(.2).timeout
	panel.settings_window.get_texture().get_image().save_png(output.path_join("blender-setup.png"))
	await panel._blender_setup("install")
	_check(calls.has("copy_bootstrap") and calls.has("open_termux") and not calls.has("permission") and not calls.has("start"), "The install button performs the one-time Play Store terminal handoff without unavailable permissions")
	_check(form["hint"].visible and form["hint"].text.contains("Lipește comanda") and backend.workflow.get("action") == "install", "Only the necessary paste instruction appears during pairing")
	await get_tree().create_timer(.2).timeout
	var hint_rect = form["hint"].get_global_rect()
	var visible_hint = hint_rect.intersection(panel.settings_tabs.get_tab_control(panel.section_tabs["integrations"]).get_global_rect())
	_check(visible_hint.size.y >= hint_rect.size.y - 1, "The one-time paste instruction scrolls fully into view at phone scaling")
	panel.settings_window.get_texture().get_image().save_png(output.path_join("blender-manual.png"))
	var restored = embedded["termux_blender"].new(panel)
	restored.configure(base, base.path_join("project"))
	_check(restored.workflow.get("action") == "install", "The authorized installation survives an editor restart during terminal pairing")
	restored.native_override = native_call
	restored.transport = transport
	backend = restored
	panel.integrations.termux = backend
	backend.changed.connect(panel._refresh_blender_card)
	backend.diagnostic.connect(panel._blender_diagnostic)
	backend.workflow_finished.connect(panel._blender_workflow_finished)
	transport.online = true
	await backend.refresh()
	_check(backend.available() and backend.workflow.is_empty() and backend.pending.is_empty(), "Returning from Termux automatically completes installation, real editor import verification and checkpoints")
	_check(transport.submitted.map(func(item: Dictionary) -> String: return item.kind) == ["install", "verify"], "One install action submits exactly one installation and one verification")
	_check(form["status"].text == "Blender Active" and form["primary"].text == "Dezinstalează Blender" and not form["hint"].visible, "Active Blender shows the compact status and only Uninstall")
	_check(panel.integration_settings.get("blender_enabled", false), "Verified Blender becomes available to the agent without an extra activation checkbox")
	_check(not panel.Integrations.definitions(false, true, false).any(func(item: Dictionary) -> bool: return item.name == "blender_run" and "inputs" in item.parameters.properties), "An unready Android backend remains hidden from the agent")
	_check(panel.Integrations.definitions(false, true, true).any(func(item: Dictionary) -> bool: return item.name == "blender_run"), "The verified backend exposes Blender to the agent")
	await backend.request_setup("install")
	_check(transport.submissions == 2, "Repeated installation reuses the verified runtime without submitting another job")
	backend.job_log = "Fixture Blender export output"
	backend._save_log()
	panel._refresh_blender_card()
	panel._refresh_journal(true)
	_check(panel.journal_console.text.contains("Fixture Blender export output"), "Full worker output is shown in Journal instead of the Blender card")
	await get_tree().create_timer(.2).timeout
	panel.settings_window.get_texture().get_image().save_png(output.path_join("blender-ready.png"))
	for node in [form["primary"], form["status"], form["hint"]]:
		_check(node.size.x <= panel.settings_window.size.x, "The minimal Blender card stays within the settings window")
	transport.revision = 0
	await panel._blender_setup("uninstall")
	_check(transport.submissions == 2 and backend.workflow.get("restart_required", false) and form["hint"].text.contains("Ctrl+C"), "An older connector is updated through the same action before it can receive an unsupported uninstall request")
	await backend.refresh()
	_check(transport.submissions == 2, "Periodic checks never send uninstall to the older connector")
	transport.revision = 2
	await backend.refresh()
	_check(transport.submitted[-1].kind == "uninstall" and transport.submitted[-1].args.runtime.binary_stamp == "fixture", "Uninstall targets the exact runtime selected by the user")
	_check(not backend.available() and backend.verified.is_empty() and not panel.integration_settings.get("blender_enabled", true), "Successful uninstall clears readiness and removes agent access")
	_check(form["primary"].text == "Instalează Blender" and form["status"].text != "Blender Active", "After uninstall the card returns to its single install action")
	device["launch_mode"] = "direct"
	transport.online = false
	var count = transport.submissions
	await panel._blender_setup("install")
	_check(calls.has("permission") and transport.submissions == count and form["hint"].text.contains("permisiunea Android"), "RUN_COMMAND variants request permission through the same install action without starting an unauthorized job")
	device["permission"] = true
	transport.online = true
	await backend.refresh()
	_check(backend.available() and backend.workflow.is_empty() and transport.submissions == count + 2, "After the permission is granted the direct variant continues installation and verification automatically")
	transport.online = false
	backend.connected = false
	await panel._blender_setup("install")
	_check(calls.has("start") and backend.workflow.get("manual_handoff", false) and form["hint"].text.contains("Lipește comanda"), "A direct variant with external execution disabled falls back to the same paste step without extra settings controls")
	count = calls.count("start")
	await backend.refresh()
	_check(calls.count("start") == count and not backend.workflow.is_empty(), "Periodic checks preserve the handoff without repeatedly launching a disabled service")
	transport.online = true
	await backend.refresh()
	_check(backend.available() and backend.workflow.is_empty(), "Returning after the fallback handoff reuses Blender and clears the installation intent")
	backend.working = true
	backend.state["stage"] = "Instalare Blender…"
	panel._refresh_blender_card()
	_check(form["primary"].disabled and form["status"].text == "Instalare Blender…", "Progress uses the same small status and prevents duplicate actions")
	backend.working = false
	backend._failure({"code": "fixture_failed", "error": "Fixture detailed failure"})
	panel._refresh_blender_card()
	panel._refresh_journal(true)
	_check(form["hint"].text.contains("Jurnal") and panel.journal_console.text.contains("Fixture detailed failure"), "Errors keep the card compact and preserve their diagnostic detail in Journal")
	await get_tree().create_timer(.2).timeout
	panel.settings_window.get_texture().get_image().save_png(output.path_join("blender-error.png"))
	panel.settings_window.hide()
	panel.integrations.termux = null

func _provider_connection_tests(output: String) -> void:
	var original = panel.config["providers"].duplicate(true)
	panel.config["providers"] = []
	panel._refresh_lists()
	panel._new_provider()
	panel.open_settings("providers")
	await get_tree().create_timer(0.2).timeout
	var form: Dictionary = panel.forms["provider"]
	var page = panel.settings_tabs.get_tab_control(panel.section_tabs["providers"])
	var selectors = page.find_children("*", "OptionButton", true, false).filter(func(node: Node) -> bool: return node.is_visible_in_tree())
	_check(selectors.size() == 1 and selectors[0] == form["issuer"] and form["issuer_label"].text == "Furnizor", "A new AI connection exposes one provider selector instead of two overlapping dropdowns")
	_check(not panel.provider_badge.visible and not panel.provider_connections.visible and not panel.settings_actions["provider_delete"].visible, "An empty provider form omits saved-connection status, empty lists and deletion")
	_check(not form["local_connection"].visible, "Cloud providers do not show unrelated local-network discovery controls")
	if not output.is_empty():
		panel.settings_window.get_texture().get_image().save_png(output.path_join("providers-new.png"))
		form["issuer"].show_popup()
		await get_tree().create_timer(0.15).timeout
		form["issuer"].get_popup().get_texture().get_image().save_png(output.path_join("providers-catalog.png"))
		form["issuer"].get_popup().hide()
	panel._select_issuer("deepseek")
	form["issuer"].item_selected.emit(form["issuer"].selected)
	form["key"].text = "fixture-provider-secret"
	_check(panel._save_provider(), "A cloud connection can still save its API key through the single provider form")
	var cloud_id = str(form["editing"])
	_check(panel.provider_connections.visible and panel.lists["providers"].item_count == 1 and panel.lists["providers"].get_item_text(0).contains("Cloud") and panel.vault.read(cloud_id) == "fixture-provider-secret", "Saved connections appear in their own labeled list while keys remain in the vault")
	form["new_connection"].pressed.emit()
	_check(str(form.get("editing", "")).is_empty() and form["key"].text.is_empty() and not panel.provider_badge.visible and panel.config["providers"].size() == 1, "Adding another connection resets only the form and preserves the saved provider")
	panel._select_issuer("lmstudio")
	form["issuer"].item_selected.emit(form["issuer"].selected)
	_check(form["local_connection"].visible and form["groups"]["url"].visible, "Local providers expose their LAN address and discovery in the same form")
	form["url"].text = "192.168.1.20:1234"
	_check(panel._save_provider(), "A local LM Studio connection still saves a manual LAN address without a token")
	var local_id = str(form["editing"])
	_check(panel.lists["providers"].item_count == 2 and panel.lists["providers"].get_item_text(1).contains("Local"), "Cloud and local connections remain recognizable in the saved list")
	if not output.is_empty():
		await get_tree().create_timer(0.2).timeout
		panel.settings_window.get_texture().get_image().save_png(output.path_join("providers-local.png"))
		page.scroll_vertical = 100000
		await get_tree().create_timer(0.2).timeout
		panel.settings_window.get_texture().get_image().save_png(output.path_join("providers-saved.png"))
	panel.lists["providers"].item_selected.emit(0)
	await get_tree().create_timer(0.1).timeout
	_check(form["editing"] == cloud_id and panel._provider_issuer()["id"] == "deepseek" and form["key"].text.is_empty() and page.scroll_vertical == 0, "Selecting a saved connection opens its form at the top without exposing its key")
	panel._select_issuer("ollama")
	form["issuer"].item_selected.emit(form["issuer"].selected)
	_check(str(form["editing"]).is_empty() and panel.config["providers"].size() == 2 and panel.vault.read(cloud_id) == "fixture-provider-secret", "Changing the provider starts a separate connection instead of overwriting the saved cloud key")
	panel.lists["providers"].item_selected.emit(1)
	_check(form["editing"] == local_id and form["url"].text.contains("192.168.1.20"), "The saved local connection loads by its own stable list row")
	panel._remove_profile("providers", "provider")
	_check(panel.config["providers"].size() == 1 and panel.config["providers"][0]["id"] == cloud_id and panel.vault.read(local_id).is_empty(), "Deleting the selected local connection preserves the other saved provider")
	panel._edit_provider(0)
	panel._remove_profile("providers", "provider")
	form["key"].text = "sk-fixture-deepseek-readded"
	form["key"].text_changed.emit(form["key"].text)
	_check(panel._save_provider(), "Re-adding a DeepSeek key after deleting a saved connection restores the hidden provider endpoint")
	var readded_id = str(form.get("editing", ""))
	if not readded_id.is_empty():
		var restored = panel._profile_by_id(readded_id)
		_check(restored.get("url") == "https://api.deepseek.com" and panel.vault.read(readded_id) == "sk-fixture-deepseek-readded", "The recovered endpoint and new key belong to the selected DeepSeek connection")
		restored["url"] = ""
		restored["models"] = [{"id": "retained-model"}]
		panel._edit_provider(0)
		_check(panel._save_provider() and panel._profile_by_id(readded_id).get("models", []).size() == 1 and panel.vault.read(readded_id) == "sk-fixture-deepseek-readded", "Repairing a legacy blank endpoint preserves its stored key and cached models")
		form["url"].text = "https:/invalid-endpoint"
		_check(not panel._save_provider() and form["groups"]["url"].visible, "An invalid explicit endpoint becomes visible for correction instead of remaining hidden")
		form["url"].text = "https://different.example.test/v1"
		_check(not panel._save_provider() and panel._profile_by_id(readded_id).get("url") == "https://api.deepseek.com", "Changing the actual server still requires an explicit replacement credential")
	if not readded_id.is_empty(): panel.vault.erase(readded_id)
	panel.vault.erase(cloud_id)
	panel.config["providers"] = original
	panel._refresh_lists()
	if original.is_empty(): panel._new_provider()
	else: panel._edit_provider(0)
	panel.settings_window.hide()

func _configuration_screenshots(output: String) -> void:
	panel.chat.set_context(8192, 32768, 430)
	await get_tree().create_timer(0.15).timeout
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(output.path_join("context-filling.png"))
	for section in ["general", "providers", "generation", "integrations", "journal", "agent"]:
		if section == "generation":
			panel._clear_form("generation")
			panel.forms["generation"]["destination"].text = "res://ai_assets"
			panel.forms["generation"]["kind"].select(0)
			panel.forms["generation"]["asset_kind"].select(1)
			panel._generation_fields(0, panel.forms["generation"]["workflow_fields"])
		panel.open_settings(section)
		await get_tree().create_timer(0.2).timeout
		var page: ScrollContainer = panel.settings_tabs.get_tab_control(panel.section_tabs[section])
		page.scroll_vertical = 0
		await get_tree().process_frame
		panel.settings_window.get_texture().get_image().save_png(output.path_join("settings-" + section + ".png"))
		if section == "providers":
			var service: OptionButton = panel.forms["provider"]["issuer"]
			service.show_popup()
			await get_tree().create_timer(0.15).timeout
			service.get_popup().get_texture().get_image().save_png(output.path_join("provider-groups.png"))
			service.get_popup().hide()
	panel.open_settings("skills")
	await get_tree().create_timer(0.2).timeout
	panel.settings_window.get_texture().get_image().save_png(output.path_join("settings-skills.png"))
	panel.open_settings("automations")
	await get_tree().create_timer(0.2).timeout
	panel.settings_window.get_texture().get_image().save_png(output.path_join("settings-tasks.png"))
	panel.settings_window.hide()
	var base = EditorInterface.get_base_control()
	var groups = {}
	var center_columns = []
	for child in base.find_child("DockHSplitMain", true, false).get_children():
		if child is Control and not str(child.name).begins_with("DockVSplit"): center_columns.append({"node": child, "maximum": child.custom_maximum_size})
	for name in ["DockVSplitLeftL", "DockVSplitLeftR", "DockVSplitRightL", "DockVSplitRightR"]:
		var group = base.find_child(name, true, false)
		if group != null: groups[name] = group.visible
	for index in [1, 2, 0]:
		panel._set_placement(index)
		await get_tree().create_timer(0.3).timeout
		while panel.dock_layout_busy: await get_tree().process_frame
		await get_tree().process_frame
		var docked = panel.get_parent() is EditorDock
		_check(panel.chat.get_global_rect().end.x <= panel.get_viewport().get_visible_rect().end.x + 1 and panel.chat.send_button.get_global_rect().end.x <= panel.get_viewport().get_visible_rect().end.x + 1, "Dock and Send stay inside the usable editor width: " + str(index))
		_check(docked == (index != 0) and panel.is_visible_in_tree(), "Chat placement is active and visible: " + str(index))
		if index != 0: _assert_workspace_bounds(index, output, "normal")
		RenderingServer.force_draw(false)
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(output.path_join(["dock-center.png", "dock-left.png", "dock-right.png"][index]))
		if index != 0:
			var slot = panel.get_parent().get_parent() as TabContainer
			var expected = panel._dock_content_rect(slot)
			_check(panel.get_parent().get_rect().is_equal_approx(expected) and panel.size.y >= expected.size.y - 1, "Dock fills its actual tab content height and width: " + str(index))
			await _narrow_dock_controls(slot, index, output)
			panel.chat.expand_button.pressed.emit()
			await get_tree().create_timer(0.2).timeout
			_check(not panel.get_parent() is EditorDock and EditorInterface.is_distraction_free_mode_enabled() and panel.is_visible_in_tree(), "Top expand opens docked chat in the central workspace")
			panel.chat.expand_button.pressed.emit()
			await get_tree().create_timer(0.2).timeout
			_check(panel.get_parent() is EditorDock and not EditorInterface.is_distraction_free_mode_enabled() and panel.config["preferences"]["dock"] == index, "Top collapse restores the original dock and preserves its saved preference")

	await get_tree().process_frame
	for name in groups:
		_check(base.find_child(name, true, false).visible == groups[name], "Returning to central chat restores secondary dock visibility: " + name)
	for column in center_columns: _check(column["node"].custom_maximum_size == column["maximum"], "Returning to central chat restores the workspace size constraint")

func _assert_workspace_bounds(index: int, output: String, variant: String) -> void:
	var rect = panel.chat.get_global_rect()
	_check(panel.get_viewport().get_visible_rect().grow(1).encloses(rect), "The complete dock stays inside the viewport: " + str(index) + " / " + variant)
	var viewport_3d = EditorInterface.get_editor_viewport_3d(0).get_parent() as Control
	if viewport_3d.is_visible_in_tree():
		_check(not viewport_3d.get_global_rect().intersection(rect.grow(-1)).has_area(), "The actual 3D viewport does not cover the chat: " + str(index) + " / " + variant)
	var main = EditorInterface.get_base_control().find_child("DockHSplitMain", true, false) as Control
	var columns = []
	for child in main.get_children():
		if not child is Control or not child.is_visible_in_tree(): continue
		columns.append({"name": child.name, "rect": str(child.get_global_rect()), "minimum": str(child.get_combined_minimum_size()), "maximum": str(child.get_combined_maximum_size())})
		if not child.is_ancestor_of(panel): _check(not child.get_global_rect().intersection(rect.grow(-1)).has_area(), "Editor column does not cover the chat: " + str(child.name) + " / " + str(index) + " / " + variant)
	embedded["common"].atomic_json(output.path_join("dock-geometry-" + str(index) + "-" + variant + ".json"), {"chat": str(rect), "viewport_3d": str(viewport_3d.get_global_rect()), "columns": columns})

func _narrow_dock_controls(slot: TabContainer, placement_index: int, output: String) -> void:
	var previous = slot.custom_maximum_size
	slot.custom_maximum_size.x = 224 * EditorInterface.get_editor_scale()
	await get_tree().create_timer(0.2).timeout
	while panel.dock_layout_busy: await get_tree().process_frame
	for _frame in range(5): await get_tree().process_frame
	_assert_workspace_bounds(placement_index, output, "narrow")
	var scope = panel.chat.get_global_rect().grow(1)
	for control in [panel.chat.model_button, panel.chat.reasoning_button, panel.chat.options_button, panel.chat.context_indicator, panel.chat.voice_button, panel.chat.send_button, panel.chat.expand_button, panel.chat.navigation_buttons["settings"]]:
		var fits = scope.encloses(control.get_global_rect()) and panel.get_parent().get_global_rect().grow(1).encloses(control.get_global_rect())
		if not fits:
			print("Control bounds: chat=", scope, " host=", panel.get_parent().get_global_rect(), " control=", control.get_global_rect(), " composer=", panel.chat.compose_panel.get_global_rect(), " toolbar=", panel.chat.composer_controls.get_global_rect())
			EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(output.path_join("dock-clipped-" + str(placement_index) + ".png"))
		_check(fits, "Narrow dock keeps the complete control visible: " + control.tooltip_text + " / " + str(placement_index))
	_check(panel.chat.composer.placeholder_text == "Mesaj…" and panel.chat.send_button.size.y <= 34 * EditorInterface.get_editor_scale(), "Narrow dock keeps the input hint on one line and Send at compact height")
	panel.chat.navigation_buttons["history"].pressed.emit()
	for _frame in range(4): await get_tree().process_frame
	_check(panel.chat.sidebar.visible and not panel.chat.root_column.visible and panel.chat.get_global_rect().grow(1).encloses(panel.chat.sidebar.get_global_rect()), "History replaces chat inside a narrow dock without expanding outside it")
	panel.chat.show_history(false)
	panel.chat.set_context(32768, 32768)
	panel.speech.transcribing = true
	for _frame in range(4): await get_tree().process_frame
	_check(panel.chat.root_column.visible and panel.chat.stop_button.visible and panel.chat.compose_panel.get_global_rect().grow(1).encloses(panel.chat.stop_button.get_global_rect()) and panel.chat.compose_panel.get_global_rect().grow(1).encloses(panel.chat.send_button.get_global_rect()), "Narrow dock keeps Stop and Send accessible with full context and voice transcription")
	panel.chat.stop_button.pressed.emit()
	for _frame in range(3): await get_tree().process_frame
	_check(not panel.speech.transcribing, "The visible Stop button actually cancels voice transcription")
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(output.path_join("dock-narrow-" + str(placement_index) + ".png"))
	slot.custom_maximum_size = previous
	await get_tree().create_timer(0.15).timeout
	while panel.dock_layout_busy: await get_tree().process_frame

func _tap_drawer(key: String, value: String) -> void:
	for index in range(panel.chat.picker_list.item_count):
		var metadata: Variant = panel.chat.picker_list.get_item_metadata(index)
		if metadata is Dictionary and metadata.get(key) == value:
			if panel.chat.drawer_stage == "models":
				var item = panel.chat.picker_models.get_root().get_first_child()
				while item != null:
					if int(item.get_metadata(0)) == index:
						item.select(0)
						await get_tree().process_frame
						return
					item = item.get_next()
			else: panel.chat.picker_list.item_selected.emit(index)
			return
	_check(false, "Drawer item is available: " + key + "=" + value)

func _drawer_screenshots(output: String) -> void:
	panel.config["providers"][0]["models"] = [
		{"id": "fixture-code", "name": "Coding · model de probă", "efforts": ["low", "medium", "high", "max"]},
		{"id": "fixture-fast", "name": "Chat rapid · model de probă"}]
	panel.config["providers"].append({"id": "visual-openai", "name": "OpenAI · API", "issuer": "openai", "kind": "responses", "models": [{"id": "fixture-openai"}]})
	panel.config["providers"].append({"id": "visual-ollama", "name": "Ollama · local", "issuer": "ollama", "kind": "chat", "models": [{"id": "fixture-local"}]})
	panel.config["providers"].append({"id": "visual-lmstudio", "name": "LM Studio · local", "issuer": "lmstudio", "kind": "chat", "models": [{"id": "fixture-studio"}]})
	panel.account_profiles = [{"id": "visual-subscription", "name": "ChatGPT · abonament", "kind": "siwc", "models": [{"id": "fixture-account"}]}]
	panel._refresh_profiles()
	panel._choose({"profile": "visual-provider", "model": "fixture-code", "effort": "high"})
	await get_tree().process_frame
	panel.chat._open_picker()
	await get_tree().create_timer(0.2).timeout
	var image = EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	image.save_png(output.path_join("drawer-providers.png"))
	await _tap_drawer("profile", "visual-provider")
	await get_tree().create_timer(0.2).timeout
	print("AI model rows: list=", panel.chat.picker_list.size, " scroll max/page=", panel.chat.picker_list.get_v_scroll_bar().max_value, "/", panel.chat.picker_list.get_v_scroll_bar().page)
	var last_model = panel.chat.picker_models.get_root().get_child(1)
	var last_rect = panel.chat.picker_models.get_item_area_rect(last_model)
	# An open editor bottom panel can leave space for only one model row.
	# In that case require native scrolling to reveal the last row completely.
	var model_bottom = panel.chat.picker_models.size.y - panel.chat.picker_models.get_theme_stylebox("panel").get_margin(SIDE_BOTTOM)
	if last_rect.end.y > model_bottom:
		panel.chat.picker_models.scroll_to_item(last_model)
		await RenderingServer.frame_post_draw
		last_rect = panel.chat.picker_models.get_item_area_rect(last_model)
	_check(last_rect.position.y >= 0 and last_rect.end.y <= model_bottom + 1, "Model rows fit the drawer or remain fully reachable by scrolling on short windows")
	image = EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	image.save_png(output.path_join("drawer-models.png"))
	await _tap_drawer("model", "fixture-code")
	await get_tree().create_timer(0.2).timeout
	image = EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	image.save_png(output.path_join("drawer-reasoning.png"))
	await _tap_drawer("effort", "high")
	await get_tree().create_timer(0.2).timeout
	image = EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	image.save_png(output.path_join("composer-selector.png"))

func _populated_chat_tests() -> void:
	var scale = EditorInterface.get_editor_scale()
	panel.tools.execute("godot_write_file", {"path": "res://ai_visual_diff.txt", "text": "speed = 5\n"}, 2, true)
	panel.tools.turn_id = "visual-diff"
	panel.tools.execute("godot_write_file", {"path": "res://ai_visual_diff.txt", "text": "speed = 12\n"}, 2, true)
	panel.tools.turn_id = ""
	panel._show_changes("visual-diff")
	await get_tree().create_timer(0.2).timeout
	var changes: AcceptDialog
	for child in panel.get_children():
		if child is AcceptDialog and child.title == "Modificările execuției": changes = child
	var diff: CodeEdit = changes.find_children("*", "CodeEdit", true, false)[0]
	var additions = false
	var deletions = false
	for index in range(diff.get_line_count()):
		if diff.get_line(index) == "+speed = 12": additions = diff.get_line_background_color(index).g > diff.get_line_background_color(index).r
		if diff.get_line(index) == "-speed = 5": deletions = diff.get_line_background_color(index).r > diff.get_line_background_color(index).g
	_check(additions and deletions, "Changes show actual before and after content with distinct colors")
	var output = OS.get_environment("GODOT_AI_QA_OUTPUT")
	if not output.is_empty(): changes.get_texture().get_image().save_png(output.path_join("changes.png"))
	changes.hide()
	changes.queue_free()
	_check(panel.tools.restore_turn("visual-diff").get("ok", false), "Visual diff keeps recovery operational")
	panel.chat.motion_enabled = false
	panel._status("")
	panel.history = [{"id": "visual-user", "role": "user", "content": "hei"}]
	panel._render_history()
	await get_tree().create_timer(0.2).timeout
	var user: Dictionary = panel.chat.message_records[0]
	_check(user["card"].size.x <= panel.chat.thread.size.x * 0.75 and user["card"].size.y < 90 * scale, "Short user messages have compact bubbles")
	_check(absf(user["card"].get_global_rect().end.x - user["row"].get_global_rect().end.x) < 2, "User bubbles align to the right")
	_check(not panel.chat.attachment_chips.visible and not panel.chat.activity_panel.visible, "Empty attachments and task progress reserve no chat space")
	_check(panel.chat.scroll.size.y >= panel.chat.size.y * 0.5, "Conversation receives at least half the available workspace")
	_check(panel.chat.size.x <= panel.size.x + 2, "Message width does not force the chat outside its workspace")
	var compact_height = panel.composer.size.y
	panel.composer.text = "Linie\n".repeat(12)
	await get_tree().create_timer(0.2).timeout
	_check(panel.composer.size.y > compact_height and panel.composer.size.y <= 112 * scale + 1, "Composer grows with text up to its height limit")
	panel.composer.clear()
	panel.pending_references = ["res://example.gd"]
	panel._composer_hints()
	_check(panel.chat.attachment_chips.visible and panel.chat.attachment_chips.get_child_count() == 1, "References appear as removable chips")
	panel._chat_action("remove_attachment", {"kind": "reference", "index": 0})
	_check(panel.pending_references.is_empty() and not panel.chat.attachment_chips.visible, "Removing a reference updates the actual pending context")
	var source = "extends Node3D\n\nfunc _ready():\n\tprint(\"Salut din Godot\")"
	var answer = "Putem construi scena împreună.\n\n**Pașii propuși**\n- Verific structura proiectului.\n- Pregătesc scriptul și verific rezultatul.\n\n```gdscript\n" + source + "\n```\n\nModificările rămân disponibile pentru revizuire."
	panel.current_origin = {"origin_label": "DeepSeek · Model de probă", "turn_id": "visual-turn"}
	panel._display("assistant", "")
	var anchor = panel.transcript
	panel.chat.stream_text(anchor, answer.left(answer.length() / 2))
	await get_tree().create_timer(0.15).timeout
	panel.chat.stream_text(anchor, answer.substr(answer.length() / 2))
	await get_tree().create_timer(0.2).timeout
	var assistant: Dictionary = anchor.get_meta("message")
	var body_id = assistant["body"].get_instance_id()
	var before = assistant["card"].size.y
	_check(assistant["blocks"].any(func(block: Dictionary) -> bool: return block.has("editor") and block["editor"].text == source), "Streaming renders highlighted fenced code before completion")
	var copy: Button = assistant["blocks"].filter(func(block: Dictionary) -> bool: return block.has("editor"))[0]["copy"]
	copy.pressed.emit()
	_check(DisplayServer.clipboard_get() == source, "Code copy preserves source without Markdown fences")
	var completed = {"id": "visual-answer", "role": "assistant", "content": answer, "origin_label": "DeepSeek · Model de probă", "turn_id": "visual-turn"}
	panel.history.append(completed)
	panel.chat.finish_stream(anchor, completed)
	panel._finish_chat("Finalizat.")
	await get_tree().create_timer(0.2).timeout
	_check(is_instance_valid(anchor) and assistant["body"].get_instance_id() == body_id and absf(assistant["card"].size.y - before) < 2, "Completion keeps the same message widgets and layout")
	_check(not assistant["actions"][0].disabled and assistant["metadata"]["id"] == "visual-answer", "Completed message actions bind to the stored conversation message")
	_check(panel.chat.running_tools is Label and not panel.chat.running_tools.visible and panel.chat.running_tools.get_child_count() == 0, "The non-expandable Running Tools row stays hidden after completion")
	panel.chat.show_running_tool("godot_script_diagnostics")
	_check(panel.chat.running_tools.visible and panel.chat.running_tools.text == "Running Tools · Godot Script Diagnostics" and panel.chat.running_tools.tooltip_text == "godot_script_diagnostics", "Running Tools describes the active tool and retains its exact name in the tooltip")
	panel.chat.show_running_tool()
	panel.config["providers"] = [{"id": "visual-provider", "name": "DeepSeek", "issuer": "deepseek", "kind": "chat", "url": "https://api.deepseek.com", "models": [{"id": "visual-code", "name": "Model de probă"}]}]
	panel._refresh_lists()
	panel._refresh_profiles()
	panel._edit_provider(0)
	_check(panel.lists["providers"].item_count == 1 and panel.lists["providers"].get_item_metadata(0) == "visual-provider" and panel.lists["providers"].visible and not panel.provider_advanced.visible, "Saved connections use a separate compact list with advanced fields collapsed")
	_check(panel.forms["provider"]["issuer_label"].text == "Furnizor" and panel.forms["provider"]["issuer"].get_parent() == panel.forms["provider"]["key"].get_parent().get_parent(), "A single clearly named provider catalog stays above the API key")
	panel._new_provider()
	_check(panel.forms["provider"]["issuer"].get_parent() == panel.forms["provider"]["key"].get_parent().get_parent(), "New provider exposes service selection before the API key")
	panel._edit_provider(0)
	var previous_profiles = panel.config["providers"].duplicate(true)
	panel.config["providers"].append({"id": "lan-fixture", "name": "LAN fixture", "issuer": "custom", "kind": "chat", "url": "http://192.168.1.20:1234/v1", "models": []})
	panel._refresh_lists()
	var local_index = panel.lists["providers"].item_count - 1
	panel.lists["providers"].item_selected.emit(local_index)
	_check(panel.forms["provider"]["editing"] == "lan-fixture" and panel.forms["provider"]["url"].text.contains("192.168.1.20"), "Cloud/local separators retain stable profile selection instead of offset indexes")
	panel._select_issuer("ollama")
	_check(panel._provider_issuer()["id"] == "ollama", "Separated service picker resolves the correct catalog entry by ID")
	panel.config["providers"] = previous_profiles
	panel._edit_provider(0)
	_check(panel.forms["github"]["key"].secret and not panel.forms["github"].has("client_id"), "GitHub settings offer a masked personal-token field only")
	panel.forms["github"]["key"].text = "fixture-personal-token"
	_check(panel._save_connections() and panel.vault.read("integration_github") == "fixture-personal-token" and panel.integration_settings["github_enabled"], "Saving a personal token enables GitHub and stores the secret in the vault")
	panel.settings_actions["github_disconnect"].pressed.emit()
	_check(panel.vault.read("integration_github").is_empty() and not panel.integration_settings["github_enabled"], "Disconnect removes the personal token and disables GitHub")
	_check(panel.provider_badge.text.contains("neverificată"), "Saved model metadata does not imply a verified connection")
	panel.config["providers"][0]["verified_at"] = 1
	panel._refresh_lists()
	_check(panel.provider_badge.text.contains("Conexiune verificată"), "Verified profiles show their distinct connection state")
	panel.open_settings("providers")
	await get_tree().create_timer(0.2).timeout
	var key = panel.forms["provider"]["key"]
	_check(key.is_visible_in_tree() and key.get_global_rect().end.y < panel.settings_window.size.y - 60 * scale, "API key remains visible with a saved provider")
	panel._status("Profil verificat pentru captura de test.")
	_check(panel.settings_status.visible and not panel.chat.status.visible, "Settings feedback is separate from chat status")
	_check(panel.settings_navigation.get_theme_stylebox("panel").bg_color == Color("0d1320"), "Saved lists and settings navigation use the graphite theme")
	panel.settings_window.hide()
	var was_expanded = EditorInterface.is_distraction_free_mode_enabled()
	panel.chat.expand_button.pressed.emit()
	_check(EditorInterface.is_distraction_free_mode_enabled() != was_expanded, "Header expand button controls the native editor workspace")
	panel.chat.expand_button.pressed.emit()
	panel.chat.follow_bottom = false
	panel.chat.scroll.scroll_vertical = 0
	await get_tree().create_timer(0.2).timeout

func _chat_experience_tests() -> void:
	panel.history = [
		{"id": "ux-user-1", "role": "user", "content": "Primul prompt", "turn_id": "ux-turn-1"},
		{"id": "ux-answer-1", "role": "assistant", "content": "Primul răspuns.", "turn_id": "ux-turn-1", "run_status": "completed"},
		{"id": "ux-user-2", "role": "user", "content": "Al doilea prompt", "turn_id": "ux-turn-2"},
		{"id": "ux-answer-2", "role": "assistant", "content": "Al doilea răspuns.", "turn_id": "ux-turn-2", "run_status": "completed", "reasoning_content": "Analizez fișierul. Verific apoi rezultatul."}
	]
	panel.current_turn = ""
	panel._render_history()
	await get_tree().process_frame
	var older: Dictionary = panel.chat.message_records[1]
	var latest: Dictionary = panel.chat.message_records[3]
	_check(not older["actions"][2].visible and latest["actions"][2].visible and not latest["actions"][2].disabled, "Undo is offered only for the latest completed answer")
	_check(older["actions"][4].get_popup().is_item_disabled(older["actions"][4].get_popup().get_item_index(1)) and not latest["actions"][4].get_popup().is_item_disabled(latest["actions"][4].get_popup().get_item_index(1)), "Resend stays available only on the latest answer")
	var reasoning: Dictionary = latest.get("reasoning", {})
	_check(not reasoning.is_empty() and reasoning["toggle"].text.contains("Gândire · 5 cuvinte") and not reasoning["body"].visible, "Persisted reasoning collapses into a Thinking block")
	reasoning["toggle"].pressed.emit()
	_check(reasoning["body"].visible, "Thinking block expands on demand")
	panel.chat.set_turn_metrics("ux-turn-2", {"elapsed_ms": 65000, "input_tokens": 1200, "output_tokens": 340, "estimated": false, "cost_usd": 0.0123})
	var metrics: Label = latest.get("metrics_label")
	_check(metrics != null and metrics.visible and metrics.text.contains("1 min 05 s") and metrics.text.contains("340 tokeni") and metrics.text.contains("$0.0123"), "Per-turn metrics show elapsed time, tokens and cost")
	panel.chat.set_turn_metrics("ux-turn-1", {"elapsed_ms": 0, "output_tokens": 400, "estimated": true})
	var estimate: Label = older.get("metrics_label")
	_check(estimate != null and estimate.text == "≈ 400 tokeni", "Missing usage falls back to an estimated token count")
	var output = OS.get_environment("GODOT_AI_QA_OUTPUT")
	if not output.is_empty():
		await get_tree().create_timer(0.2).timeout
		var metrics_image = EditorInterface.get_base_control().get_viewport().get_texture().get_image()
		if metrics_image != null and not metrics_image.is_empty(): metrics_image.save_png(output.path_join("chat-metrics.png"))
	panel.chat._show_find(true)
	panel.chat.find_input.text = "prompt"
	panel.chat._search_find()
	_check(panel.chat.find_panel.visible and panel.chat.find_matches.size() == 2 and panel.chat.find_count.text == "1/2", "Find in chat lists case-insensitive matches")
	if not output.is_empty():
		await get_tree().create_timer(0.2).timeout
		var find_image = EditorInterface.get_base_control().get_viewport().get_texture().get_image()
		if find_image != null and not find_image.is_empty(): find_image.save_png(output.path_join("chat-find.png"))
	panel.chat._step_find(1)
	_check(panel.chat.find_count.text == "2/2", "Find next advances to the following match")
	panel.chat._step_find(1)
	_check(panel.chat.find_count.text == "1/2", "Find wraps past the last match")
	panel.chat._show_find(false)
	_check(not panel.chat.find_panel.visible and panel.chat.find_matches.is_empty() and panel.chat.find_count.text == "0/0", "Closing find clears its results")
	panel.chat.set_generating(true)
	panel.chat.last_output_msec = Time.get_ticks_msec() - 16000
	panel.chat.stall_clock = 1.0
	panel.chat._process(0.0)
	_check(panel.chat.stall_label.visible and panel.chat.stall_label.text.contains("Fără ieșire"), "Long silence during generation shows a stall warning")
	panel.chat.set_generating(false)
	_check(not panel.chat.stall_label.visible, "Finishing or stopping generation hides the stall warning")
	panel.queued = [{"text": "Primul mesaj în coadă", "selection": {}}, {"text": "Al doilea mesaj în coadă", "selection": {"files": ["ux-file"], "references": ["res://ux.gd"]}}]
	panel.queue_paused = true
	panel._sync_queue()
	_check(panel.chat.queue_panel.visible and panel.chat.queue_rows.get_child_count() == 2, "Queued messages render as visible cards above the composer")
	var header = panel.chat.queue_panel.get_child(0)
	_check(str(header.get_child(0).text).contains("Coadă · 2 mesaje"), "Queue header counts the pending messages")
	_check(header.get_child_count() == 2 and header.get_child(1).text == "Reia", "Paused queue offers an explicit resume control")
	if not output.is_empty():
		await get_tree().create_timer(0.2).timeout
		var queue_image = EditorInterface.get_base_control().get_viewport().get_texture().get_image()
		if queue_image != null and not queue_image.is_empty(): queue_image.save_png(output.path_join("chat-queue.png"))
	panel.composer.text = ""
	panel.pending_files.clear()
	panel.pending_attachments.clear()
	panel.pending_references.clear()
	panel._chat_action("queue_restore", {"index": 1})
	_check(panel.queued.size() == 1 and panel.composer.text == "Al doilea mesaj în coadă" and "ux-file" in panel.pending_files and "res://ux.gd" in panel.pending_references, "Restoring a queued message returns its text and context to the composer")
	panel._chat_action("queue_remove", {"index": 0})
	_check(panel.queued.is_empty() and not panel.queue_paused and not panel.chat.queue_panel.visible, "Removing the last queued message clears the queue panel")
	panel.composer.clear()
	panel.pending_files.clear()
	panel.pending_attachments.clear()
	panel.pending_references.clear()
	panel._composer_hints()
	panel.queued = [{"text": "Coadă în așteptare", "selection": {}}]
	panel.queue_paused = true
	panel.busy = true
	panel._sync_queue()
	panel._chat_action("queue_resume", {})
	_check(panel.queued.size() == 1 and panel.queue_paused and panel.chat.queue_panel.visible, "Queue resume refuses to start while work is running")
	panel.busy = false
	panel.chat.set_working(false)
	panel._status("") # Finish the simulated busy refusal before measuring the idle queue.
	panel.queued.clear()
	panel.queue_paused = false
	panel._sync_queue()
	for index in range(20): panel.queued.append({"text": "Queued test %d" % index, "selection": {}})
	panel.queue_paused = true
	panel._sync_queue()
	await get_tree().create_timer(0.3).timeout
	var chat_rect: Rect2 = panel.chat.get_global_rect()
	var composer_rect: Rect2 = panel.composer.get_global_rect()
	_check(panel.chat.scroll.size.y >= minf(80 * EditorInterface.get_editor_scale(), chat_rect.size.y * 0.15), "Twenty queued messages leave a usable conversation viewport")
	_check(composer_rect.position.y >= chat_rect.position.y and composer_rect.end.y <= minf(chat_rect.end.y, panel.get_viewport_rect().end.y), "The composer stays fully visible with twenty queued messages")
	var queue_bar: VScrollBar = panel.chat.queue_scroll.get_v_scroll_bar()
	_check(queue_bar.max_value > queue_bar.page and panel.chat.queue_scroll.size.y <= panel.chat.size.y * 0.22 + 1, "The long queue scrolls within a bounded share of the chat height")
	_check(panel.chat.queue_rows.get_children().all(func(card: Control) -> bool: return card.mouse_filter == Control.MOUSE_FILTER_PASS), "Queue cards pass drag gestures to their scroll container")
	panel.chat.queue_scroll.scroll_vertical = int(queue_bar.max_value)
	await get_tree().create_timer(0.2).timeout
	var last_card: Control = panel.chat.queue_rows.get_child(19)
	_check(panel.chat.queue_scroll.get_global_rect().encloses(last_card.get_global_rect()), "Scrolling the queue reaches its last card")
	if not output.is_empty():
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(output.path_join("chat-queue-20.png"))
		panel.Common.atomic_json(output.path_join("queue-regressions.json"), {"items": panel.queued.size(), "conversation_height": panel.chat.scroll.size.y, "queue_height": panel.chat.queue_scroll.size.y, "chat_height": panel.chat.size.y, "composer_bottom": composer_rect.end.y, "viewport_bottom": panel.get_viewport_rect().end.y, "queue_rect": str(panel.chat.queue_scroll.get_global_rect()), "last_card_rect": str(last_card.get_global_rect())})
	last_card.get_child(0).get_child(2).pressed.emit()
	_check(panel.queued.size() == 19 and panel.queued[-1]["text"] == "Queued test 18", "The last queued card removes its own message after scrolling")
	panel.queued.clear()
	panel.queue_paused = false
	panel._sync_queue()
	var target = panel._undo_target({"message": "ux-answer-2"})
	_check(target.get("turn") == "ux-turn-2" and target.get("index") == 2, "Undo resolves the prompt of the latest answer")
	panel._undo_turn({"message": "ux-answer-1"}, false)
	_check(panel.chat.status.text.contains("Doar cel mai recent"), "Older answers direct the user to the fork action instead of undo")
	panel.busy = true
	panel._undo_turn({"message": "ux-answer-2"}, false)
	_check(panel.chat.status.text.contains("Oprește execuția"), "Undo refuses to run while the agent is working")
	panel.busy = false
	panel.tools.turn_id = "ux-undo-turn"
	panel.tools.execute("godot_write_file", {"path": "res://ux_undo_probe.txt", "text": "fixture"}, 2, true)
	panel.tools.turn_id = ""
	panel.history = [
		{"id": "ux-undo-user", "role": "user", "content": "Creează fișierul", "turn_id": "ux-undo-turn"},
		{"id": "ux-undo-answer", "role": "assistant", "content": "L-am creat.", "turn_id": "ux-undo-turn", "run_status": "completed"}
	]
	panel._render_history()
	await get_tree().process_frame
	panel._apply_undo("ux-undo-turn", false)
	await get_tree().process_frame
	_check(not FileAccess.file_exists("res://ux_undo_probe.txt"), "Undo restores the files written by the answer")
	_check(panel.history.is_empty() and not panel.chat.message_records.any(func(record: Dictionary) -> bool: return record["role"] == "assistant"), "Undo removes the answer and its prompt from the conversation")
	_check(panel.composer.text == "Creează fișierul", "Undo returns the original prompt to the composer")
	panel.composer.clear()
	panel._composer_hints()
	panel.history = []
	panel._render_history()

func _file_chat_tests() -> void:
	var scope = str(panel.conversations.index["active"])
	var image = Image.create(80, 40, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	var path = panel.file_registry.directory.path_join("qa-image.png")
	panel.file_registry.permit(path)
	image.save_png(path)
	var registered = panel.file_registry.register_file(path, scope)
	_check(registered.get("ok", false), "File registration succeeds in the real editor")
	if not registered.get("ok", false): return
	var id = str(registered["result"]["id"])
	panel.chat.append_message("assistant", "Captura găsită", {"id": "qa-file", "files": [id]})
	var card = panel.chat.thread.find_child("File_" + id, true, false)
	_check(card != null and card.mouse_filter == Control.MOUSE_FILTER_PASS, "File cards preserve vertical chat scrolling until a horizontal gesture is accepted")
	_check(card != null and card.find_children("*", "TextureRect", true, false).size() == 1, "Assistant file cards show actual image thumbnails")
	panel.chat.append_message("assistant", "Aceeași referință", {"id": "qa-file-second", "files": [id]})
	panel._chat_action("file_pin", {"id": id})
	var pins = panel.chat.thread.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.get_meta("file_pin_id", "") == id)
	_check(pins.size() == 2 and pins.all(func(button: Button) -> bool: return button.button_pressed), "Pinning one card synchronizes every visible copy of that file")
	panel._chat_action("file_pin", {"id": id})
	_check(pins.all(func(button: Button) -> bool: return not button.button_pressed) and not panel.file_registry.describe(id, scope).get("pinned", true), "Unpinning clears card indicators and conversation context together")
	panel.composer.text = "Verifică aici"
	panel._chat_action("file_mention", {"id": id})
	var chips = panel.chat.attachment_chips.get_child_count()
	panel._composer_hints()
	_check(panel.pending_files == [id] and panel.composer.text == "Verifică aici" and panel.chat.attachment_chips.get_child_count() == chips, "Mentioning a file preserves the draft and repeated hints do not duplicate chips")
	var touch = InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(10, 10)
	card.gui_input.emit(touch)
	panel.pending_files.clear()
	var drag = InputEventScreenDrag.new()
	drag.position = Vector2(160, 14)
	drag.relative = Vector2(150, 4)
	card.gui_input.emit(drag)
	_check(panel.pending_files == [id], "Swiping a discovered card right references the exact file")
	panel._open_file(id)
	await get_tree().process_frame
	_check(panel.media_view.visible and panel.media_view.canvases.size() == 1 and panel.media_view.canvases[0].image.get_width() == 80, "Opening a card displays its real captured image in the viewer")
	panel.media_view.canvases[0].selection = Rect2(2, 2, 10, 6)
	var crop = panel.media_view.canvases[0].exported(true)
	var output = OS.get_environment("GODOT_AI_QA_OUTPUT")
	if not output.is_empty():
		panel.media_view.get_texture().get_image().save_png(output.path_join("viewer-image.png"))
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(output.path_join("file-mentions.png"))
	_check(crop.get_width() == 10 and crop.get_height() == 6 and crop.get_pixel(0, 0) == Color.RED, "Crop exports the selected original pixels without modifying the source")
	panel.media_view.hide()
	panel._open_file(id, id)
	_check(panel.media_view.canvases.size() == 2, "Comparison opens both exact image revisions")
	panel.media_view.canvases[0].pose_changed.emit({"zoom": 2.0, "offset": Vector2(0.1, 0.2)})
	_check(panel.media_view.canvases[1].zoom == 2.0, "Image comparison shares zoom and normalized pan")
	panel.media_view.hide()
	_check(panel.composer.text == "Verifică aici" and panel.pending_files == [id], "Closing the viewer preserves conversation draft and references")
	panel.busy = true
	panel._chat_action("file_send", {"id": id})
	_check(panel.queued.size() == 1 and panel.queued[0]["selection"]["files"] == [id], "Direct reference sending retains stable file IDs in queued messages")
	panel.busy = false
	panel.queued.clear()
	panel.pending_files.clear()
	var cutout = Image.create(80, 80, false, Image.FORMAT_RGBA8)
	cutout.fill(Color.TRANSPARENT)
	cutout.fill_rect(Rect2i(20, 20, 40, 40), Color.CORNFLOWER_BLUE)
	var cutout_path = panel.file_registry.directory.path_join("qa-cutout.png")
	panel.file_registry.permit(cutout_path)
	cutout.save_png(cutout_path)
	var cutout_file = panel.file_registry.register_file(cutout_path, scope)
	panel._open_file(str(cutout_file["result"]["id"]))
	await get_tree().create_timer(0.2).timeout
	_check(panel.media_view.canvases[0].checker != null and panel.media_view.canvases[0].exported(false).get_pixel(0, 0).a == 0, "Transparent images show a viewer checkerboard while original and exported pixels keep their real alpha")
	if not output.is_empty(): panel.media_view.get_texture().get_image().save_png(output.path_join("viewer-transparent.png"))
	panel.media_view.hide()
	panel.composer.clear()
	panel._composer_hints()
	panel.chat.clear_messages()
	panel.media_view.queue_free()
	panel.media_view = null
	await get_tree().process_frame
	while EditorInterface.get_resource_filesystem().is_scanning(): await get_tree().process_frame

func _export_button_tests(path: String) -> void:
	var previous_profiles = panel.config["generation"].duplicate(true)
	var previous_jobs = panel.assets.jobs.duplicate(true)
	panel.config["generation"] = [{"id": "export-profile", "kind": "meshy", "asset_kind": "mesh", "name": "Meshy fixture"}]
	panel.assets.jobs = [{"id": "export-cube", "profile_id": "export-profile", "kind": "mesh", "provider": "meshy", "status": "completed", "file": path, "external_id": "fixture-remote"}]
	panel._refresh_lists()
	_check(panel.lists["jobs"].get_item_text(0).begins_with("Model 3D · Finalizat"), "Generation result list uses a readable type and status")
	panel.lists["jobs"].select(0)
	panel.lists["jobs"].item_selected.emit(0)
	var picker: OptionButton = panel.forms["generation"]["export_format"]
	_check(not panel.settings_actions["job_export"].disabled and picker.item_count == 9, "Completed Meshy model enables nine actual export formats")
	for index in range(picker.item_count):
		if picker.get_item_metadata(index) == "stl": picker.select(index); picker.item_selected.emit(index)
	panel.open_settings("generation")
	await get_tree().process_frame
	panel.settings_actions["job_export"].pressed.emit()
	while panel.busy: await get_tree().process_frame
	await get_tree().process_frame
	var destination = str(panel.assets.jobs[0].get("exports", {}).get("stl", {}).get("project_path", ""))
	_check(destination.begins_with("res://ai_assets/") and destination.ends_with("_stl.stl") and panel.settings_status.text.contains("Export salvat"), "Export button saves the selected format in the named object folder")
	var file = FileAccess.open(destination, FileAccess.READ)
	if file != null: file.seek(80)
	_check(file != null and file.get_length() == 684 and file.get_32() == 12, "Object folder receives twelve actual cube triangles in binary STL")
	file = null
	var original = FileAccess.get_file_as_bytes(destination)
	panel._perform_export("export-cube", "stl")
	while panel.busy: await get_tree().process_frame
	_check(FileAccess.get_file_as_bytes(destination) == original and str(panel.assets.jobs[0]["exports"]["stl"].get("project_path", "")) == destination, "Repeated export reuses the existing object file without overwriting it")
	for index in range(picker.item_count):
		if picker.get_item_metadata(index) == "fbx": picker.select(index); picker.item_selected.emit(index)
	panel.settings_actions["job_export"].pressed.emit()
	var confirmations = panel.find_children("*", "ConfirmationDialog", true, false).filter(func(item: ConfirmationDialog) -> bool: return item.title == "Conversie FBX")
	_check(confirmations.size() == 1 and panel.assets.jobs[0].get("exports", {}).has("stl") and not panel.assets.jobs[0].get("exports", {}).has("fbx"), "FBX requires explicit conversion confirmation before any paid submission")
	if not confirmations.is_empty(): confirmations[0].canceled.emit()
	await get_tree().process_frame
	panel.open_settings("generation")
	var group: Control = panel.forms["generation"]["export_group"]
	var scroll = group.get_parent()
	while scroll != null and not scroll is ScrollContainer: scroll = scroll.get_parent()
	if scroll != null: scroll.ensure_control_visible(group)
	await get_tree().create_timer(0.2).timeout
	var output = OS.get_environment("GODOT_AI_QA_OUTPUT")
	if not output.is_empty(): panel.settings_window.get_texture().get_image().save_png(output.path_join("export-formats.png"))
	panel.generation_preview.get_parent().show()
	panel.settings_actions["job_preview"].pressed.emit()
	await get_tree().create_timer(0.2).timeout
	var previews = panel.generation_preview.get_children()
	_check(previews.size() == 1 and previews[0].has_method("pose") and previews[0].information.get("triangles") == 12, "Generation settings use the shared interactive model viewer instead of a static 3D viewport")
	if previews.size() == 1:
		var preview = previews[0]
		if scroll != null: scroll.ensure_control_visible(preview)
		await get_tree().create_timer(0.2).timeout
		var old = Vector2(preview.yaw, preview.pitch)
		var point = preview.get_global_rect().get_center()
		var touch = InputEventScreenTouch.new()
		touch.position = point
		touch.pressed = true
		panel.settings_window.push_input(touch, true)
		var drag = InputEventScreenDrag.new()
		drag.position = point + Vector2(24, -18)
		drag.relative = Vector2(24, -18)
		panel.settings_window.push_input(drag, true)
		touch.pressed = false
		panel.settings_window.push_input(touch, true)
		_check(preview.yaw != old.x and preview.pitch != old.y, "A generated mesh rotates horizontally and vertically through the actual settings window")
		await get_tree().create_timer(0.2).timeout
		RenderingServer.force_draw(false)
		if not output.is_empty(): panel.settings_window.get_texture().get_image().save_png(output.path_join("generation-preview-3d.png"))
	panel.settings_window.hide()
	for preview in panel.generation_preview.get_children():
		panel.generation_preview.remove_child(preview)
		preview.queue_free()
	panel.config["generation"] = previous_profiles
	panel.assets.jobs = previous_jobs
	panel._refresh_lists()
	panel.chat.show_status("", false)
	while EditorInterface.get_resource_filesystem().is_scanning() or EditorInterface.get_resource_filesystem().is_importing(): await get_tree().process_frame

func _model_and_control_tests() -> void:
	var scene = Node3D.new()
	var mesh = MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	scene.add_child(mesh)
	mesh.owner = scene
	var document = GLTFDocument.new()
	var state = GLTFState.new()
	var path = panel.file_registry.directory.path_join("qa-cube.glb")
	panel.file_registry.permit(path)
	var exported = document.append_from_scene(scene, state) == OK and document.write_to_filesystem(state, path) == OK
	scene.free()
	_check(exported, "Build an actual GLB fixture for the shared native renderer")
	if exported: await _export_button_tests(path)
	var registered = panel.file_registry.register_file(path, str(panel.conversations.index["active"]))
	_check(registered.get("ok", false), "Register a GLB snapshot for the current conversation")
	if registered.get("ok", false):
		var id = str(registered["result"]["id"])
		panel._open_file(id)
		await get_tree().process_frame
		_check(panel.media_view.model_views.size() == 1, "Opening a 3D card launches the shared interactive GLB viewer")
		if not panel.media_view.model_views.is_empty():
			var model = panel.media_view.model_views[0]
			_check(model.information.get("triangles", 0) == 12 and model.information.get("meshes", 0) == 1, "3D metadata counts actual rendered cube geometry")
			var pixels = await model.capture()
			_check(pixels != null and pixels.get_width() >= 128 and pixels.get_pixel(pixels.get_width() / 2, pixels.get_height() / 2).is_equal_approx(pixels.get_pixel(0, 0)) == false, "Interactive 3D preview renders actual geometry rather than a flat placeholder")
			var output = OS.get_environment("GODOT_AI_QA_OUTPUT")
			if not output.is_empty(): panel.media_view.get_texture().get_image().save_png(output.path_join("viewer-3d.png"))
			var original_yaw = model.yaw
			var original_pitch = model.pitch
			var point = model.get_global_rect().get_center()
			var touch = InputEventScreenTouch.new()
			touch.pressed = true
			touch.position = point
			panel.media_view.push_input(touch, true)
			var drag = InputEventScreenDrag.new()
			drag.position = point + Vector2(60, 35)
			drag.relative = Vector2(60, 35)
			panel.media_view.push_input(drag, true)
			touch.pressed = false
			touch.position = drag.position
			panel.media_view.push_input(touch, true)
			_check(model.yaw != original_yaw and model.pitch != original_pitch, "Touch events routed through the real viewer window rotate the model on both axes")
			var turned = model.camera.transform
			touch.pressed = true
			touch.position = point
			panel.media_view.push_input(touch, true)
			drag.position = point - Vector2(60, 35)
			drag.relative = Vector2(-60, -35)
			panel.media_view.push_input(drag, true)
			touch.pressed = false
			panel.media_view.push_input(touch, true)
			_check(is_equal_approx(model.yaw, original_yaw) and is_equal_approx(model.pitch, original_pitch) and model.camera.transform != turned, "Opposite touch movement restores both camera axes through the navigation surface")
			var mouse = InputEventMouseButton.new()
			mouse.button_index = MOUSE_BUTTON_LEFT
			mouse.position = point
			mouse.pressed = true
			panel.media_view.push_input(mouse, true)
			var motion = InputEventMouseMotion.new()
			motion.position = point + Vector2(-25, 20)
			motion.relative = Vector2(-25, 20)
			motion.button_mask = MOUSE_BUTTON_MASK_LEFT
			panel.media_view.push_input(motion, true)
			mouse.position = motion.position
			mouse.pressed = false
			panel.media_view.push_input(mouse, true)
			_check(model.yaw > original_yaw and model.pitch > original_pitch and not model.dragging, "Mouse drag rotates the preview and releases its gesture state")
			var old_distance = model.distance
			touch.position = point - Vector2(40, 0)
			touch.pressed = true
			panel.media_view.push_input(touch, true)
			var second_touch = InputEventScreenTouch.new()
			second_touch.index = 1
			second_touch.position = point + Vector2(40, 0)
			second_touch.pressed = true
			panel.media_view.push_input(second_touch, true)
			drag.index = 1
			drag.position = point + Vector2(70, 0)
			drag.relative = Vector2(30, 0)
			panel.media_view.push_input(drag, true)
			_check(model.distance < old_distance and model.target != Vector3.ZERO, "Two-finger input zooms and pans the actual preview camera")
			touch.pressed = false
			second_touch.pressed = false
			panel.media_view.push_input(touch, true)
			panel.media_view.push_input(second_touch, true)
			var key = InputEventKey.new()
			key.keycode = KEY_HOME
			key.pressed = true
			panel.media_view.push_input(key, true)
			_check(model.touches.is_empty() and model.target == Vector3.ZERO and is_equal_approx(model.distance, model.radius * 3), "Releasing fingers clears navigation and Home resets camera framing")
			var magnify = InputEventMagnifyGesture.new()
			magnify.position = point
			magnify.factor = 1.5
			panel.media_view.push_input(magnify, true)
			_check(is_equal_approx(model.distance, model.radius * 2), "Android's native magnify gesture zooms the actual 3D camera in")
			magnify.factor = 0.5
			panel.media_view.push_input(magnify, true)
			_check(is_equal_approx(model.distance, model.radius * 4), "The native pinch gesture also zooms the 3D camera out")
			var valid_distance = model.distance
			magnify.factor = 0
			panel.media_view.push_input(magnify, true)
			_check(model.distance == valid_distance, "An invalid pinch factor cannot corrupt camera distance")
			var pan = InputEventPanGesture.new()
			pan.position = point
			pan.delta = Vector2(2, -1)
			panel.media_view.push_input(pan, true)
			_check(model.target != Vector3.ZERO, "Native pan gestures move the preview camera target")
			for command in ["zoom_in", "zoom_out"]:
				var zoom_button = panel.media_view.commands[command]
				var before = model.distance
				touch.position = zoom_button.get_global_rect().get_center()
				touch.pressed = true
				panel.media_view.push_input(touch, true)
				touch.pressed = false
				panel.media_view.push_input(touch, true)
				_check(zoom_button.visible and (model.distance < before if command == "zoom_in" else model.distance > before), "The visible " + command + " button controls 3D zoom through real window taps")
			for i in 60: model.command("zoom_out")
			_check(model.distance <= model.radius * 30, "Repeated zoom-out stays inside the preview camera range")
			for i in 60: model.command("zoom_in")
			_check(model.distance >= model.radius * 0.2, "Repeated zoom-in keeps a positive safe camera distance")
			model.preset("reset")
			touch.position = point
			touch.pressed = true
			panel.media_view.push_input(touch, true)
			panel.media_view.focus_exited.emit()
			_check(model.touches.is_empty() and not model.dragging, "Losing viewer focus releases all navigation inputs")
			touch.pressed = false
			panel.media_view.push_input(touch, true)
			await get_tree().create_timer(0.2).timeout
			var rotations = []
			var direction_buttons = model.input_surface.find_children("Orbit_*", "Button", true, false)
			for direction_button in direction_buttons:
				var before = Vector2(model.yaw, model.pitch)
				touch.position = direction_button.get_global_rect().get_center()
				touch.pressed = true
				panel.media_view.push_input(touch, true)
				touch.pressed = false
				panel.media_view.push_input(touch, true)
				rotations.append(Vector2(model.yaw, model.pitch) - before)
			_check(rotations.size() == 4 and rotations[0].x > 0 and rotations[1].x < 0 and rotations[2].y < 0 and rotations[3].y > 0 and direction_buttons.all(func(control: Button) -> bool: return model.get_global_rect().grow(1).encloses(control.get_global_rect())), "Four visible navigation buttons rotate left, right, up and down through real window taps")
			await get_tree().create_timer(0.2).timeout
			if not output.is_empty(): panel.media_view.get_texture().get_image().save_png(output.path_join("viewer-3d-navigated.png"))
		panel.media_view.hide()
		await get_tree().process_frame
		_check(panel.media_view.model_views.is_empty(), "Closing the viewer releases its active 3D scenes")
		var observed = await panel._observe_file(id)
		_check(observed.get("ok", false) and observed.get("result", {}).get("metadata", {}).get("triangles", 0) == 12 and not panel.media_view.visible, "Agent 3D inspection runs offscreen without opening the user viewer")
		var thumbnail = panel.file_registry.entries[id].get("preview", "")
		_check(FileAccess.file_exists(thumbnail) and Image.load_from_file(thumbnail).get_width() == 512, "Offscreen 3D inspection caches a real 512px preview")
		if not thumbnail.is_empty():
			var pixels = Image.load_from_file(thumbnail)
			_check(pixels.get_pixel(256, 256).is_equal_approx(pixels.get_pixel(0, 0)) == false, "Background 3D capture contains the rendered model")
		panel.media_view.queue_free()
		panel.media_view = null
	# A separate real editor window supplies a target outside the assistant UI.
	var window = Window.new()
	window.title = "AI input fixture"
	window.size = Vector2i(320, 180)
	EditorInterface.get_base_control().add_child(window)
	var box = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.add_child(box)
	var clicked = {"value": false}
	var button = Button.new()
	button.text = "Editor fixture button"
	button.pressed.connect(func() -> void: clicked["value"] = true)
	box.add_child(button)
	var edit = LineEdit.new()
	box.add_child(edit)
	var secret = LineEdit.new()
	secret.secret = true
	secret.text = "fixture-secret"
	box.add_child(secret)
	window.popup_centered()
	await get_tree().process_frame
	await get_tree().process_frame
	var handle = panel.tools._encode(button)["handle"]
	var capture = await panel.editor_control.capture({"target": "control", "handle": handle}, {})
	_check(capture.get("ok", false) and not capture.get("images", []).is_empty(), "Editor capture returns actual control pixels and a fresh frame ID")
	if capture.get("ok", false):
		var args = {"frame": capture["result"]["frame"], "action": "click", "x": 0.5, "y": 0.5}
		var result = await panel.editor_control.input(args, {})
		_check(result.get("ok", false) and clicked["value"] and panel.editor_control.held.is_empty(), "Coordinate input clicks the actual editor button and releases it")
		_check((await panel.editor_control.input(args, {})).get("code") == "stale_frame", "A consumed frame cannot operate the editor twice without re-observation")
	capture = await panel.editor_control.capture({"target": "control", "handle": handle}, {})
	window.size += Vector2i(20, 0)
	await get_tree().process_frame
	_check((await panel.editor_control.input({"frame": capture["result"]["frame"], "action": "click"}, {})).get("code") == "stale_frame", "Window layout changes invalidate previously captured coordinates")
	edit.grab_focus()
	capture = await panel.editor_control.capture({"target": "control", "handle": panel.tools._encode(edit)["handle"]}, {})
	var typed = await panel.editor_control.input({"frame": capture["result"]["frame"], "action": "text", "text": "test română"}, {})
	_check(typed.get("ok", false) and edit.text == "test română", "Editor text input inserts at the focused field caret")
	secret.grab_focus()
	capture = await panel.editor_control.capture({"target": "control", "handle": panel.tools._encode(secret)["handle"]}, {})
	var bytes = Marshalls.base64_to_raw(capture.get("images", [{}])[0].get("data", ""))
	var masked = Image.new()
	masked.load_png_from_buffer(bytes)
	_check(masked.get_pixel(masked.get_width() / 2, masked.get_height() / 2).is_equal_approx(Color("141a29")), "Secret fields are masked in editor captures")
	_check(not (await panel.editor_control.input({"frame": capture["result"]["frame"], "action": "text", "text": "forbidden"}, {})).get("ok", false) and secret.text == "fixture-secret", "Agent text input cannot modify a secret field")
	capture = await panel.editor_control.capture({"target": "control", "handle": handle}, {})
	var touch = InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = button.get_global_rect().get_center()
	panel.editor_control._hold(window, touch)
	panel.editor_control.user_input(InputEventKey.new())
	_check(panel.editor_control.held.is_empty() and panel.editor_control.frames.is_empty(), "Manual takeover releases held inputs and invalidates coordinates")
	panel.editor_control._hold(window, touch)
	panel.editor_control.release()
	_check(panel.editor_control.held.is_empty(), "Stop releases all synthetic touch/key states")
	window.hide()
	window.queue_free()
	panel.editor_control.release()
	await get_tree().process_frame
	while EditorInterface.get_resource_filesystem().is_scanning() or EditorInterface.get_resource_filesystem().is_importing(): await get_tree().process_frame

func _store_install_tests() -> void:
	var archive_path = panel.store.directory.path_join("qa-addon.zip")
	var pack = ZIPPacker.new()
	pack.open(archive_path)
	var contents = {"fixture-root/addons/ai_test_store/plugin.cfg": "[plugin]\nname=\"AI QA addon\"\ndescription=\"Isolated installation fixture\"\nauthor=\"QA\"\nversion=\"1.0\"\nscript=\"plugin.gd\"\n", "fixture-root/addons/ai_test_store/plugin.gd": "@tool\nextends EditorPlugin\n", "fixture-root/addons/ai_test_store/empty.txt": ""}
	for name in contents:
		pack.start_file(name)
		pack.write_file(str(contents[name]).to_utf8_buffer())
		pack.close_file()
	pack.close()
	var result = await panel.store.install_zip(archive_path, {"id": "qa-addon", "name": "QA addon"}, "1.0", {})
	_check(result.get("ok", false) and FileAccess.get_file_as_string("res://addons/ai_test_store/plugin.gd") == contents["fixture-root/addons/ai_test_store/plugin.gd"], "Store installation extracts actual approved addon files" + (" through the native Godot installer" if native else " in the upstream fixture"))
	if not result.get("ok", false): return
	var installation = str(result["result"]["installation"])
	while panel.tools.scan_pending or EditorInterface.get_resource_filesystem().is_scanning() or EditorInterface.get_resource_filesystem().is_importing(): await get_tree().process_frame
	_check(panel.store.enable_plugin("ai_test_store", true).get("ok", false) and EditorInterface.is_plugin_enabled("ai_test_store"), "Installed addon enables through the real EditorInterface")
	_check(not panel.store.remove(installation).get("ok", false), "Store removal requires disabling the active addon first")
	panel.store.enable_plugin("ai_test_store", false)
	await get_tree().process_frame
	await get_tree().process_frame
	while EditorInterface.get_resource_filesystem().is_scanning() or EditorInterface.get_resource_filesystem().is_importing(): await get_tree().process_frame
	var duplicate = await panel.store.install_zip(archive_path, {"id": "qa-addon"}, "1.0", {})
	_check(duplicate.get("code") == "install_conflict", "Store installation refuses to overwrite existing addon files")
	var source = "res://addons/ai_test_store/plugin.gd"
	var output = FileAccess.open(source, FileAccess.WRITE)
	output.store_string("# manual change\n" + contents["fixture-root/addons/ai_test_store/plugin.gd"])
	output.close()
	_check(panel.store.remove(installation).get("code") == "install_conflict" and FileAccess.file_exists(source), "Uninstallation preserves manually changed addon files")
	output = FileAccess.open(source, FileAccess.WRITE)
	output.store_string(contents["fixture-root/addons/ai_test_store/plugin.gd"])
	output.close()
	await get_tree().process_frame
	var removed = panel.store.remove(installation)
	if native: _check(removed.get("ok", false) and not FileAccess.file_exists(source), "Unmodified tracked addon uninstalls after being disabled")
	else: _check(removed.get("code") == "native_bridge_unavailable" and FileAccess.file_exists(source), "Upstream editor reports the native cache-removal bridge requirement without deleting live scripts")
	while panel.tools.scan_pending or EditorInterface.get_resource_filesystem().is_scanning() or EditorInterface.get_resource_filesystem().is_importing(): await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

func _vision_settings_tests() -> void:
	var original = panel.config["providers"].duplicate(true)
	var selection = panel._selection()
	panel.config["providers"].append({"id": "qa-vision-settings", "name": "Vision QA", "issuer": "custom", "kind": "chat", "url": "https://vision.example/v1", "models": [{"id": "qa-image", "name": "QA images", "capabilities": {}}, {"id": "qa-text", "name": "QA text", "capabilities": {}}]})
	panel._refresh_profiles()
	panel._choose({"profile": "qa-vision-settings", "model": "qa-image"})
	panel._edit_provider(panel.config["providers"].size() - 1)
	var form: Dictionary = panel.forms["provider"]
	form["vision_model"].select(0)
	form["vision_model"].item_selected.emit(0)
	form["vision_policy"].select(1)
	form["vision_policy"].item_selected.emit(1)
	panel._save_provider()
	_check(panel._vision_enabled() and not embedded["providers"].vision_allowed(panel._current_profile(), "qa-text"), "Provider settings permit images only for the explicitly selected model")
	form["vision_model"].select(1)
	form["vision_model"].item_selected.emit(1)
	_check(form["vision_policy"].selected == 0 and form["vision_pending"].get("qa-image") == 1, "Selecting another model preserves its separate image policy")
	form["vision_policy"].select(2)
	form["vision_policy"].item_selected.emit(2)
	panel._save_provider()
	var saved: Dictionary = panel.Common.read_json(panel.data_directory.path_join("config.json"), {})
	var profile: Dictionary = saved["providers"][-1]
	_check(profile.get("vision_overrides", {}).get("qa-image") == 1 and profile["vision_overrides"].get("qa-text") == 2, "Per-model image preferences persist with the provider profile")
	panel.config["providers"] = original
	panel._save_config()
	panel._choose(selection)
	if not original.is_empty(): panel._edit_provider(0)

class StartHost:
	extends Node
	var actions: Array = []
	func project_action(action: String) -> void: actions.append(action)

func _handoff_tests() -> void:
	var original_id = str(panel.conversations.index["active"])
	var old_count = panel.conversations.index["items"].size()
	var start = embedded["panel"].new()
	var host = StartHost.new()
	add_child(host)
	start.configure(host, FixtureVault.new(), true)
	EditorInterface.get_base_control().add_child(start)
	start.hide()
	start.history = [{"id": "startup-message", "role": "user", "content": "Pregătim un joc înainte de selectarea proiectului."}, {"id": "startup-reply", "role": "assistant", "content": "Pregătim structura jocului."}]
	var picture = Image.create(12, 12, false, Image.FORMAT_RGBA8)
	picture.fill(Color.CORNFLOWER_BLUE)
	var image_path = start.file_registry.directory.path_join("handoff.png")
	picture.save_png(image_path)
	start.file_registry.permit(image_path)
	var file = start.file_registry.register_file(image_path, str(start.conversations.index["active"]))
	_check(file.get("ok", false), "Register a start-screen conversation attachment")
	if file.get("ok", false): start.history[0]["files"] = [file["result"]["id"]]
	_check(start.prepare_project_handoff(ProjectSettings.globalize_path("res://")), "Save start chat before opening its selected project")
	var handoff_path = start._handoff_path(ProjectSettings.globalize_path("res://"))
	var saved = embedded["common"].read_json(handoff_path, {})
	panel._receive_project_handoff()
	_check(panel.conversations.index["items"].size() == old_count + 1 and not panel.conversations.item(original_id).is_empty(), "Transfer creates a conversation without replacing existing project history")
	_check(panel.history.size() == 2 and panel.history[0].get("id") == "startup-message", "Project editor receives the start-screen messages")
	if file.get("ok", false):
		_check(panel.file_registry.describe(str(file["result"]["id"]), str(panel.conversations.index["active"])).get("available", false), "Shared file cards survive entry into a project")
	_check(not FileAccess.file_exists(handoff_path), "Consume the completed handoff")
	embedded["common"].atomic_json(handoff_path, saved)
	panel._receive_project_handoff()
	_check(panel.conversations.index["items"].size() == old_count + 1, "Replaying the same handoff cannot duplicate a conversation")
	var first_scope = str(panel.conversations.index["active"])
	start.prepare_project_handoff(ProjectSettings.globalize_path("res://"))
	panel._receive_project_handoff()
	if file.get("ok", false): _check(not panel.file_registry.describe(str(file["result"]["id"]), first_scope).is_empty(), "A later handoff preserves file access in the earlier project conversation")
	start.queue_free()
	host.queue_free()
	await get_tree().process_frame
	panel._new_conversation()

func _generated_preview_tests() -> void:
	panel.settings_window.hide()
	panel._new_conversation()
	panel.cancel = {}
	panel.current_turn = embedded["common"].uid()
	panel.planner.reset(panel.current_turn, false)
	panel.history = [{"id": "generation-request", "role": "user", "content": "Generează un cub 3D.", "turn_id": panel.current_turn}]
	panel.busy = true
	var scene = Node3D.new()
	var mesh = MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	scene.add_child(mesh)
	mesh.owner = scene
	var doc = GLTFDocument.new()
	var state = GLTFState.new()
	var temporary = panel.assets.cache_directory.path_join("generated-probe.glb")
	_check(doc.append_from_scene(scene, state) == OK and doc.write_to_filesystem(state, temporary) == OK, "Produce a real 3D artifact for the completed-generation flow")
	scene.free()
	var job = {"id": embedded["common"].uid(), "kind": "mesh", "status": "processing", "prompt": "Cub de probă", "provider": "fixture", "destination": "res://ai_test_generated"}
	panel.assets.jobs.append(job)
	var result = panel.assets._finish_download(job, temporary)
	_check(result.get("ok", false) and panel.generated_files.size() == 1, "Completed download registers its GLB even when the model never calls file_show")
	var file_id = str(panel.generated_files[0]) if not panel.generated_files.is_empty() else ""
	panel._finish_chat("Finalizat.")
	while EditorInterface.get_resource_filesystem().is_scanning() or EditorInterface.get_resource_filesystem().is_importing(): await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	_check(panel.history.any(func(message: Dictionary) -> bool: return file_id in message.get("files", [])), "Task completion persists a generated-file shortcut without requiring model cooperation")
	panel.history = panel.conversations.load_active()
	panel._render_history()
	_check(panel.chat.message_records.any(func(record: Dictionary) -> bool: return file_id in record.get("metadata", {}).get("files", [])), "Generated 3D card remains clickable after conversation reload")
	panel.active_definitions = [panel._preview_definition()]
	panel.preview_requested = panel._requests_preview("Deschide modelul generat în preview")
	var opened = await panel._execute_call("file_preview", {"id": file_id})
	_check(opened.get("ok", false) and panel.media_view.visible and panel.media_view.model_views.size() == 1, "Agent opens the GLB in the native viewer without Blender")
	var output = OS.get_environment("GODOT_AI_QA_OUTPUT")
	await get_tree().create_timer(0.2).timeout
	if not panel.media_view.model_views.is_empty():
		var pixels = await panel.media_view.model_views[0].capture()
		var rendered = false
		if pixels != null and not pixels.is_empty():
			var corner = pixels.get_pixel(0, 0)
			for y in range(0, pixels.get_height(), 8):
				for x in range(0, pixels.get_width(), 8):
					if absf(pixels.get_pixel(x, y).r - corner.r) + absf(pixels.get_pixel(x, y).g - corner.g) + absf(pixels.get_pixel(x, y).b - corner.b) > 0.1: rendered = true
		_check(rendered, "The generated mesh produces visible pixels in the native preview")
	if not output.is_empty(): panel.media_view.get_texture().get_image().save_png(output.path_join("generated-model.png"))
	panel.media_view.hide()
	var observed = await panel._observe_file(file_id)
	_check(observed.get("ok", false) and observed.get("result", {}).get("metadata", {}).get("meshes", 0) > 0, "Background inspection uses the same native renderer without Blender")
	if not output.is_empty():
		await get_tree().process_frame
		panel.get_viewport().get_texture().get_image().save_png(output.path_join("generated-card.png"))
	panel.active_definitions = [panel._preview_definition()]
	var missing = await panel._execute_call("file_preview", {"id": "missing"})
	_check(not missing.get("ok", false) and missing.get("code") == "file_unavailable", "Do not claim preview success for an unavailable file")
	var unknown_path = panel.file_registry.directory.path_join("unsupported.fbx")
	var unknown_file = FileAccess.open(unknown_path, FileAccess.WRITE)
	unknown_file.store_string("; FBX test fixture, unsupported native preview")
	unknown_file.close()
	panel.file_registry.permit(unknown_path)
	var unknown = panel.file_registry.register_file(unknown_path, str(panel.conversations.index["active"]))
	if unknown.get("ok", false):
		var unsupported = await panel._execute_call("file_preview", {"id": unknown["result"]["id"]})
		_check(not unsupported.get("ok", false), "A previous successful preview cannot mask an unsupported format")
		panel.media_view.hide()
	panel.assets.jobs.erase(job)
	panel._new_conversation()

func _provider_discovery_tests(output: String) -> void:
	var old_profiles = panel.config["providers"].duplicate(true)
	var service = panel.providers
	var original_selection = panel._selection()
	panel.config["providers"] = []
	panel._refresh_lists()
	panel._new_provider()
	panel._select_issuer("deepseek")
	var form: Dictionary = panel.forms["provider"]
	form["issuer"].item_selected.emit(form["issuer"].selected)
	form["key"].text = "fixture-deepseek-secret"
	var catalog = FixtureCloudCatalog.new()
	catalog.owner = self
	panel.providers = catalog
	panel.open_settings("providers")
	form["key"].text_changed.emit(form["key"].text)
	await get_tree().create_timer(0.85).timeout
	while panel.provider_draft_loading: await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout
	_check(form.get("catalog_verified", false) and form["model_rows"].size() == 2 and form["editing"] == "", "Pasting an unsaved API key discovers models without saving a credential or profile")
	_check(form["model_rows"]["deepseek-flash"].get_text(1) == "0,15 USD", "Draft model rows show each model's own input tariff")
	form["model_rows"]["deepseek-v4-pro"].select(0)
	panel._provider_model_selected()
	_check(form["price_detail"].text.contains("UTC") and form["price_detail"].text.contains("api-docs.deepseek.com"), "Selected tariffs expose a verification time and first-party source")
	if not output.is_empty():
		await get_tree().create_timer(0.2).timeout
		panel.settings_window.get_texture().get_image().save_png(output.path_join("agent-model-prices.png"))
	await panel._provider_save_action()
	var id = str(form["editing"])
	var profile = panel._profile_by_id(id)
	_check(catalog.requests == 1 and profile.get("models", []).size() == 2 and profile.has("verified_at"), "Saving a cloud API key immediately discovers its models just like a local provider")
	_check(panel._current_profile().get("id") == id and panel._selection().get("model") == "deepseek-v4-pro", "New DeepSeek connection respects the model selected before saving")
	_check(panel.vault.read(id) == "fixture-deepseek-secret" and form["key"].text.is_empty(), "Automatic model discovery preserves the vault credential and clears the visible key field")
	panel.settings_window.hide()
	profile["models"] = []
	panel._refresh_profiles()
	panel.chat._open_picker()
	var row = -1
	for index in range(panel.chat.picker_list.item_count):
		var value: Variant = panel.chat.picker_list.get_item_metadata(index)
		if value is Dictionary and value.get("profile") == id: row = index
	_check(row >= 0, "Saved DeepSeek connection is available in the chat provider drawer")
	panel.chat._pick_model(row)
	_check(panel.provider_testing and panel.chat.drawer_refresh.disabled, "An empty catalog begins loading on provider selection and prevents duplicate refreshes")
	while panel.provider_testing: await get_tree().process_frame
	_check(catalog.requests == 2 and panel.chat.picker.visible and panel.chat.drawer_stage == "models" and panel.chat.picker_list.item_count == 2, "Loading an empty saved catalog updates the open model drawer in place")
	if not output.is_empty():
		await get_tree().create_timer(0.2).timeout
		panel.get_viewport().get_texture().get_image().save_png(output.path_join("deepseek-models.png"))
	var first_model = panel.chat.picker_models.get_root().get_first_child()
	_check(first_model.get_text(1).contains("0,15 / 0,6 USD"), "The visible chat tree separates model names and token prices into distinct columns")
	first_model.select(0)
	await get_tree().process_frame
	_check(panel.chat.drawer_stage == "reasoning" and panel.chat.picker_list.item_count == 4, "Tapping the visible priced model row opens the declared DeepSeek reasoning levels")
	panel.chat._pick_model(3)
	panel._choose({"profile": id, "model": "deepseek-v4-pro", "effort": "high"})
	panel.chat.drawer_profile = id
	panel.chat._show_drawer("models")
	catalog.response = {"ok": false, "status": 401, "code": "http_error", "error": "Unauthorized fixture"}
	var before = profile["models"].duplicate(true)
	_check(not await panel._test_provider(id), "Rejected credentials fail model verification")
	_check(profile["models"] == before and not profile.has("verified_at") and panel._selection().get("model") == "deepseek-v4-pro", "A failed refresh preserves cached models and the user's current selection without claiming verification")
	_check(panel.chat.picker.visible and panel.chat.drawer_hint.text.contains("Cheia API") and not panel.chat.drawer_hint.text.contains("Wi-Fi"), "Cloud authentication errors appear in the model drawer without irrelevant LAN advice")
	if not output.is_empty():
		await get_tree().create_timer(0.2).timeout
		panel.get_viewport().get_texture().get_image().save_png(output.path_join("deepseek-key-error.png"))
	catalog.response = {"ok": true, "result": []}
	_check(not await panel._test_provider(id) and not profile.has("verified_at") and not profile["models"].is_empty(), "An empty catalog is reported as a failure while preserving previously discovered models")
	catalog.response = {"ok": true, "result": before}
	_check(await panel._test_provider(id) and not profile.has("model_catalog_error"), "A successful retry clears the previous model-catalog error")
	_check(panel.journal.any(func(entry: Dictionary) -> bool: return entry.get("tool") == "provider_models") and not JSON.stringify(panel.journal).contains("fixture-deepseek-secret"), "Model discovery records activity without storing the API key in logs")
	var selection_before = panel._selection()
	panel.chat.picker_search.text = "flash"
	panel.model_pricing.transport.input_rate = "0.20"
	await panel._refresh_saved_prices(id, true)
	_check(profile["models"][0]["pricing"]["input"] == 0.2 and panel.chat.picker.visible and panel.chat.picker_search.text == "flash" and panel._selection() == selection_before, "A live tariff refresh updates the open drawer while preserving the query and current model")
	panel.model_pricing.transport.fail = true
	await panel._refresh_saved_prices(id, true)
	_check(profile["models"][0]["pricing"].get("stale", false) and panel.chat.picker_models.get_root().get_first_child().get_text(1).contains("anterior"), "An offline tariff update keeps the previous price visibly marked in the chat drawer")
	panel.model_pricing.transport.fail = false
	panel.model_pricing.transport.input_rate = "0.15"
	panel.chat._close_drawer()
	catalog.response = {"ok": false, "status": 401, "error": "Invalid draft key: fixture-invalid-new-key"}
	form["key"].text = "fixture-invalid-new-key"
	form["key"].text_changed.emit(form["key"].text)
	await panel._provider_save_action()
	_check(panel.vault.read(id) == "fixture-deepseek-secret" and profile.has("verified_at") and not form.get("catalog_verified", true), "A rejected replacement API key cannot overwrite a previously verified saved credential")
	_check(not form["catalog_status"].text.contains("fixture-invalid-new-key") and not JSON.stringify(panel.journal).contains("fixture-invalid-new-key"), "Draft authentication errors and logs redact the newly pasted secret")
	panel._select_issuer("openai")
	form["issuer"].item_selected.emit(form["issuer"].selected)
	_check(form["key"].text.is_empty() and form["models"].is_empty(), "Switching providers clears the draft key and model list")
	await get_tree().create_timer(0.85).timeout
	_check(form["models"].is_empty(), "An obsolete key-paste debounce cannot repopulate a different provider")
	panel.vault.erase(id)
	panel.providers = service
	panel.config["providers"] = old_profiles
	panel._refresh_lists()
	panel._refresh_profiles()
	panel._choose(original_selection)
	if old_profiles.is_empty(): panel._new_provider()
	else: panel._edit_provider(0)
	panel.settings_window.hide()

class FixtureLinuxBridge:
	extends Node
	var state = {"ok": true, "supported": true, "packaged": true, "installed": false, "ready": false, "tools": {}, "active_job": ""}
	var requests: Array = []
	var pending = {}
	var polls = 0
	var fail = false
	var cancelled = false
	func linux_runtime_request(action: String, args: Dictionary) -> Dictionary:
		if action == "status": return state.duplicate(true)
		if action == "cancel": cancelled = true; return {"ok": true}
		if action == "poll":
			polls += 1
			if cancelled: state["active_job"] = ""; return {"ok": true, "status": "cancelled", "error": "Operație anulată."}
			if polls == 1: return {"ok": true, "status": "running", "output": "Pregătesc Linux…"}
			state["active_job"] = ""
			if fail: return {"ok": true, "status": "failed", "error": "Verificarea runtime a eșuat.", "output": "diagnostic fixture"}
			var result = {}
			match str(pending.get("action", "")):
				"prepare", "install", "verify": state.merge({"installed": true, "ready": true}, true); result = state.duplicate(true)
				"tool_install":
					state["tools"][pending["args"]["tool"]] = {"ready": true, "version": "fixture 1.0"}
					result = state.duplicate(true)
				"execute": result = {"exit_code": 0, "output": "LINUX_FIXTURE_OK", "truncated": false}
				"uninstall": state.merge({"installed": false, "ready": false, "tools": {}}, true); result = state.duplicate(true)
			return {"ok": true, "status": "completed", "result": result}
		requests.append({"action": action, "args": args.duplicate(true)})
		polls = 0; cancelled = false
		pending = {"action": action, "args": args.duplicate(true)}
		state["active_job"] = "fixture-linux-job"
		return {"ok": true, "id": "fixture-linux-job"}

class FixtureZivaBridge:
	extends Node
	var state = {"ok": true, "enabled": true, "installed": false, "running": false, "ready": false, "ui_port": 0, "busy": false, "version": "v3.3.2", "same_project": true, "linux_ready": true}
	var requests: Array = []
	var chat = {"job": "", "state": "running", "answer": "", "error": "", "waiting": {}, "tools": 0, "scripted": []}
	func linux_runtime_request(action: String, args: Dictionary) -> Dictionary:
		if action == "ziva_status": return state.duplicate(true)
		requests.append({"action": action, "arguments": args.duplicate(true)})
		match action:
			"ziva_install": state.merge({"status": "installing", "message": "Descarc Ziva…", "busy": true}, true)
			"ziva_check_updates": state["updates"] = {"available": true, "message": "Versiune oficială disponibilă: v3.3.3"}
			"ziva_chat_send":
				chat["job"] = "fixture-ziva-job"
				chat["state"] = "running"
				chat["answer"] = ""
				chat["error"] = ""
				chat["waiting"] = {}
				chat["tools"] = 0
				return {"ok": true, "job_id": chat["job"], "state": "running"}
			"ziva_chat_poll":
				if not chat["scripted"].is_empty(): chat.merge(chat["scripted"].pop_front(), true)
				return {"ok": true, "job_id": chat["job"], "state": chat["state"], "answer": chat["answer"], "error": chat["error"], "waiting": chat["waiting"], "tools": chat["tools"], "chat_id": "fixture-ziva-chat", "message_id": "fixture-ziva-message"}
			"ziva_chat_cancel":
				chat["state"] = "cancelled"
				return {"ok": true, "job_id": chat["job"], "state": "cancelled"}
		return {"ok": true}

func _ziva_delegation_tests(bridge: FixtureZivaBridge) -> void:
	# Delegation uses the sidecar's own local RPC; this bridge stands for it.
	var previous_mode = panel.mode_picker.selected
	var previous_control = panel.full_control.button_pressed
	var previous_definitions = panel.active_definitions
	panel.ziva_runtime = bridge
	panel.mode_picker.select(1)
	panel.full_control.button_pressed = true
	panel.active_definitions = panel._agent_definitions()
	panel.cancel = {}
	bridge.state.merge({"running": true, "ready": true, "status": "running", "ui_port": 7013}, true)
	var definition = panel.active_definitions.filter(func(item: Dictionary) -> bool: return item["name"] == "ziva_task")
	_check(definition.size() == 1 and definition[0]["risk"] == "external", "Ziva delegation is an externally approved tool")
	panel.mode_picker.select(3)
	_check(not panel._definition_visible(definition[0]), "Read-only modes hide Ziva delegation")
	panel.mode_picker.select(1)
	bridge.chat["scripted"] = [{"state": "completed", "answer": "Răspuns Ziva.\n\n" + "detaliu ".repeat(1200), "finish": "stop"}]
	var delegated = await panel._execute_call("ziva_task", {"prompt": "Verifică scena principală."})
	var sent = bridge.requests.filter(func(request: Dictionary) -> bool: return request["action"] == "ziva_chat_send")
	_check(sent.size() == 1 and sent[0]["arguments"].get("prompt") == "Verifică scena principală." and not str(sent[0]["arguments"].get("project_directory", "")).is_empty(), "Delegation sends the prompt and the current project to the official agent")
	_check(delegated.get("ok", false) and delegated["result"]["status"] == "completed" and delegated["result"]["next_offset"] == 6000 and delegated["result"]["answer"].length() == 6000, "Our agent reads the completed Ziva answer and knows where it was cut")
	var tail = await panel._execute_call("ziva_task_result", {"job_id": delegated["result"]["job_id"], "offset": 6000, "limit": 200})
	_check(tail.get("ok", false) and tail["result"]["items"][0].length() == 200 and tail["result"]["next_offset"] == 6200, "A long Ziva answer is read in exact character slices")
	bridge.chat["scripted"] = [{"state": "permission_required", "waiting": {"kind": "permission", "permission": {"id": "perm-1", "chatId": "fixture-ziva-chat", "permission": "bash"}}}, {"state": "completed", "answer": "Am continuat după aprobare."}]
	var blocked = await panel._execute_call("ziva_task", {"prompt": "Rulează verificarea."})
	_check(not blocked.get("ok", false) and blocked.get("code") == "ziva_permission_required" and not str(blocked.get("job_id", "")).is_empty(), "A pending Ziva permission is handed back, never approved by our agent")
	var resumed = await panel._execute_call("ziva_task_poll", {"job_id": blocked.get("job_id", ""), "timeout_seconds": 30})
	_check(resumed.get("ok", false) and resumed["result"]["status"] == "completed", "After the user answers in the Ziva tab our agent resumes the same job")
	bridge.chat["scripted"] = [{"state": "running"}, {"state": "running"}, {"state": "running"}]
	bridge.chat["state"] = "running"
	panel.cancel = {}
	get_tree().create_timer(0.3).timeout.connect(func() -> void: panel.cancel["cancelled"] = true)
	var stopped = await panel._execute_call("ziva_task", {"prompt": "Anulează."})
	_check(stopped.get("code") == "cancelled" and bridge.requests.back()["action"] == "ziva_chat_cancel", "Cancelling our turn cancels the delegated Ziva job")
	panel.cancel = {}
	panel.ziva_runtime = null
	panel.mode_picker.select(previous_mode)
	panel.full_control.button_pressed = previous_control
	panel.active_definitions = previous_definitions
	bridge.state.merge({"running": false, "ready": false, "status": "idle", "ui_port": 0}, true)

func _ziva_tests(output: String) -> void:
	var history = panel.history.duplicate(true)
	var profiles = panel.config["providers"].duplicate(true)
	_check(not panel.forms.has("ziva") and not panel.section_tabs.has("ziva"), "Assistant settings contain no Ziva installation or session controls")
	var bridge = FixtureZivaBridge.new()
	add_child(bridge)
	await _ziva_delegation_tests(bridge)
	var backend = embedded["ziva"].new(bridge, ProjectSettings.globalize_path("res://").trim_suffix("/"))
	var was_expanded = EditorInterface.is_distraction_free_mode_enabled()
	var screen = EditorInterface.get_editor_main_screen().find_child("ZivaMainScreen", true, false)
	var temporary = screen == null
	var old_model: RefCounted
	var old_bridge: Node
	if temporary:
		screen = embedded["ziva_screen"].new()
		screen.configure(bridge, backend)
		screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel.hide()
		EditorInterface.get_editor_main_screen().add_child(screen)
		screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		old_model = screen.backend
		old_bridge = screen.bridge
		if old_model.changed.is_connected(screen._refresh): old_model.changed.disconnect(screen._refresh)
		screen.configure(bridge, backend)
		screen._bind_backend()
		EditorInterface.set_main_screen_editor("Ziva")
	screen.show()
	await get_tree().create_timer(0.2).timeout
	_check(screen.backend == backend and screen.management != null, "Ziva owns its model and management window independently of the assistant")
	_check(not screen.primary.disabled and screen.primary.text == "Instalează Ziva", "Ziva installs using its own measured Linux readiness")
	backend.request("attach")
	_check(bridge.requests.back()["action"] == "ziva_attach", "Ziva attaches the project for automatic lifecycle management")
	screen.primary.pressed.emit()
	_check(bridge.requests.back()["action"] == "ziva_install" and bridge.requests.back()["arguments"].get("project_directory") == backend.project_directory, "Installation carries only its own project and no assistant credential")
	_check(not screen.primary.visible, "Installation does not expose manual session start controls")
	bridge.state.merge({"installed": true, "running": true, "ready": true, "status": "running", "ui_port": 7013}, true)
	backend.refresh()
	screen._settings()
	await get_tree().process_frame
	_check(screen.management.visible and not panel.settings_window.visible and not screen.embedded, "Ziva management opens inside its own tab and hides the WebView")
	screen._action("check_updates")
	_check(bridge.requests.back()["action"] == "ziva_check_updates" and screen.update_button.visible and not screen.update_button.disabled, "Official update checks and upgrade actions belong to Ziva")
	_check("v3.3.3" in screen.updates_label.text, "Available upstream version is visible in Ziva management")
	screen.management.hide()
	screen._sync_embed()
	_check(screen.embedded and bridge.requests.back()["action"] == "ziva_embed", "Closing Ziva management resumes the official frontend")
	var rect: Rect2 = screen._bounds()
	_check(rect.position.x >= 0 and rect.position.y > 0 and rect.end.x <= 1.001 and rect.end.y <= 1.001, "The official frontend stays below the toolbar and within the editor surface")
	_check(not screen.hint.visible and screen.status.text == "Ziva · Activ", "Ready Ziva uses one compact status row without repeated instructions")
	_check(screen.body.size.y > screen.size.y * 0.75, "The official frontend retains most of the main tab height")
	_check(screen.actions.get_global_rect().end.x <= minf(screen.get_global_rect().end.x, screen.get_viewport().get_visible_rect().end.x) + 1, "Ziva actions fit the available width at every editor scale")
	if not temporary: _check(EditorInterface.is_distraction_free_mode_enabled(), "The native Ziva tab gives the frontend the full editor workspace")
	var count = bridge.requests.size()
	screen._sync_embed()
	_check(bridge.requests.size() == count, "Stable tab bounds do not issue a JNI request each frame")
	screen.actions.get_popup().id_pressed.emit(screen.MENU_RELOAD)
	_check(bridge.requests.back()["arguments"].get("reload", false), "Reload explicitly refreshes the official frontend")
	screen.actions.show_popup()
	screen._sync_embed()
	_check(not screen.embedded, "The native frontend makes room for the Ziva actions menu")
	screen.actions.get_popup().id_pressed.emit(screen.MENU_RELOAD)
	screen.actions.get_popup().hide()
	screen._sync_embed()
	_check(screen.embedded and bridge.requests.back()["arguments"].get("reload", false), "A menu reload is retained until its popup closes")
	if not output.is_empty():
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(output.path_join("ziva-main-tab.png"))
	screen._settings()
	await get_tree().process_frame
	if not output.is_empty(): screen.management.get_texture().get_image().save_png(output.path_join("ziva-management.png"))
	screen.management.hide()
	screen._sync_embed()
	screen.hide()
	_check(not screen.embedded and not bridge.requests.back()["arguments"].get("visible", true) and backend.state.get("running", false), "Changing tabs hides the WebView without stopping the independent backend")
	bridge.state["same_project"] = false
	backend.refresh(); screen.show()
	await get_tree().process_frame
	_check(not screen.embedded, "A main tab never embeds a session belonging to a different project")
	bridge.state["same_project"] = true
	backend.refresh()
	_check(screen.embedded, "Returning to the matching project reattaches the same frontend")
	panel.settings_window.show()
	screen._sync_embed()
	_check(not screen.embedded, "Godot settings cannot be obscured by the native frontend")
	panel.settings_window.hide()
	screen._sync_embed()
	_check(screen.embedded, "The frontend resumes after closing Godot settings")
	screen.hide()
	if temporary:
		screen.queue_free()
		panel.show()
	else:
		if backend.changed.is_connected(screen._refresh): backend.changed.disconnect(screen._refresh)
		screen.configure(old_bridge, old_model)
		screen._bind_backend()
	EditorInterface.set_main_screen_editor("AI Assistant" if native else "AI Assistant QA")
	if not temporary: _check(EditorInterface.is_distraction_free_mode_enabled() == was_expanded, "Leaving Ziva restores the previous editor workspace")
	_check(panel.history == history and panel.config["providers"] == profiles, "The Ziva main tab preserves assistant chat and provider settings")
	bridge.queue_free()
	panel.settings_window.hide()

func _linux_runtime_tests(output: String) -> void:
	var backend = panel.integrations.linux
	var old_bridge = backend.bridge
	var old_connections = panel.integration_settings.duplicate(true)
	var old_definitions = panel.active_definitions.duplicate(true)
	var old_mode = panel.mode_picker.selected
	var old_yolo = panel.full_control.button_pressed
	var bridge = FixtureLinuxBridge.new()
	add_child(bridge)
	backend.bridge = bridge
	backend.refresh()
	panel.open_settings("integrations")
	await get_tree().create_timer(0.2).timeout
	var form: Dictionary = panel.forms["linux"]
	_check(form["primary"].text == "Repară" and not form.has("remove") and not form["tools"].visible, "The required Linux base has recovery controls and no manual install or uninstall actions")
	var catalog = panel.ToolRegistry.new(backend.definitions(false), true)
	_check(catalog.discover("tool_describe", {"name": "linux_execute"}).get("code") == "tool_unavailable", "No Linux execution tool is exposed before successful runtime verification")
	await backend.ensure_ready()
	_check(backend.available() and form["status"].text == "Linux activ" and form["tools"].visible, "Only a completed and verified Linux job enables the runtime and its utility controls")
	_check(bridge.requests[0]["action"] == "prepare" and not form["primary"].visible, "Linux prepares automatically and hides recovery controls after success")
	_check(panel.integration_settings.get("linux_enabled", false) and not form["buttons"]["python"].disabled, "Verified runtime becomes available for optional Python installation")
	await panel._linux_setup("tool_install", "python")
	_check(form["buttons"]["python"].text == "Instalat" and form["buttons"]["python"].disabled and not form["buttons"]["node"].disabled, "Tool installation reflects measured capability without claiming other tools are installed")
	await backend.ensure_ready()
	_check(form["buttons"]["python"].text == "Instalat" and backend.available(), "Automatic startup verification preserves installed optional utilities")
	if not output.is_empty():
		await get_tree().create_timer(0.2).timeout
		var page = panel.settings_tabs.get_tab_control(panel.section_tabs["integrations"])
		page.scroll_vertical = 0
		panel.settings_window.get_texture().get_image().save_png(output.path_join("linux-runtime-settings.png"))
	panel.active_definitions = backend.definitions(true)
	panel.cancel = {}
	panel.mode_picker.select(2)
	var denied = await panel._execute_call("linux_execute", {"command": "echo LINUX_FIXTURE_OK"})
	_check(not denied.get("ok", false) and not bridge.requests.any(func(request: Dictionary) -> bool: return request["action"] == "execute"), "Plan mode cannot start a modifying Linux command")
	panel.mode_picker.select(1)
	panel.full_control.button_pressed = true
	panel.planner.reset()
	var result = await panel._execute_call("linux_execute", {"command": "echo LINUX_FIXTURE_OK", "seconds": 30})
	_check(result.get("ok", false) and result.get("result", {}).get("output") == "LINUX_FIXTURE_OK", "Agent dispatch receives the completed Linux command result through the existing permission pipeline")
	var count = bridge.requests.size()
	var stopped = await backend.execute({"command": "unused"}, {"cancelled": true})
	_check(stopped.get("code") == "cancelled" and bridge.requests.size() == count, "An already cancelled turn cannot submit a Linux job")
	bridge.fail = true
	var failed = await backend.setup("verify")
	_check(not failed.get("ok", false) and backend.log_text.contains("diagnostic"), "Failed runtime jobs retain their diagnostic output")
	bridge.fail = false
	bridge.state["ready"] = false
	backend.refresh()
	_check(form["primary"].visible and form["primary"].text == "Repară", "A runtime requiring verification offers recovery without deleting tools")
	await panel._linux_setup("prepare")
	_check(backend.available() and form["buttons"]["python"].text == "Instalat", "Runtime recovery preserves optional utilities")
	panel.mode_picker.select(old_mode)
	panel.full_control.button_pressed = old_yolo
	panel.active_definitions = old_definitions
	panel.integration_settings = old_connections
	backend.bridge = old_bridge
	backend.refresh()
	bridge.queue_free()
	panel.settings_window.hide()

func _workspace_panel_tests(output: String) -> void:
	var previous_placement = panel.current_placement
	var previous_expanded = EditorInterface.is_distraction_free_mode_enabled()
	if previous_expanded: panel.chat.expand_button.pressed.emit()
	panel._set_placement(0, false)
	var bottom = panel._editor_bottom_panel()
	_check(bottom != null, "The editor exposes its real bottom panel for workspace layout")
	if bottom == null: return
	var previous_bottom = bottom.get_current_tab_control()
	var diagnostic = VBoxContainer.new()
	diagnostic.custom_minimum_size.y = 150 * EditorInterface.get_editor_scale()
	var content = Label.new()
	content.text = "Diagnostic de verificare\nMesajele rămân disponibile după minimizare."
	diagnostic.add_child(content)
	add_control_to_bottom_panel(diagnostic, "Diagnostic QA")
	make_bottom_panel_item_visible(diagnostic)
	await get_tree().create_timer(0.25).timeout
	var diagnostic_tab = bottom.get_current_tab_control()
	var previous_height = panel.chat.size.y
	var draft = panel.composer.text
	panel.composer.text = "Mesaj păstrat la extinderea chatului"
	_workspace_capture(output, "panels-open")
	panel.chat.expand_button.pressed.emit()
	await get_tree().create_timer(0.3).timeout
	while panel.dock_layout_busy: await get_tree().process_frame
	_check(EditorInterface.is_distraction_free_mode_enabled() and bottom.current_tab == -1, "Expand chat collapses Output and the side docks together")
	_check(panel.chat.size.y > previous_height + 20, "Collapsing the bottom panel returns its height to the chat")
	_check(panel.chat.expand_button.tooltip_text == "Restaurează panourile" and panel.chat.expand_button.button_pressed, "Expanded chat clearly offers restoring the editor panels")
	for control in [panel.composer, panel.chat.send_button, panel.chat.model_button, panel.chat.expand_button, panel.chat.navigation_buttons["settings"]]:
		_check(panel.get_viewport().get_visible_rect().grow(2).encloses(control.get_global_rect()), "Expanded chat keeps its control fully accessible: " + control.name)
	content.text += "\nDiagnostic nou păstrat."
	_workspace_capture(output, "panels-chat-full")
	panel.chat.expand_button.pressed.emit()
	await get_tree().create_timer(0.25).timeout
	_check(not EditorInterface.is_distraction_free_mode_enabled() and bottom.get_current_tab_control() == diagnostic_tab, "Restore returns the previously open diagnostic panel")
	_check(content.text.contains("Diagnostic nou păstrat") and panel.composer.text == "Mesaj păstrat la extinderea chatului", "Expanding and restoring preserves both diagnostics and the message draft")
	if native:
		var minimize = bottom.find_child("MinimizeBottomPanel", true, false)
		_check(minimize is Button and minimize.is_visible_in_tree(), "Open native bottom panels expose a dedicated minimize button")
		if minimize is Button:
			minimize.pressed.emit()
			await get_tree().create_timer(0.25).timeout
			_check(bottom.current_tab == -1 and not minimize.visible, "The minimize action folds the panel while retaining its tabs")
			make_bottom_panel_item_visible(diagnostic)
			await get_tree().process_frame
			_check(bottom.get_current_tab_control() == diagnostic_tab and content.text.contains("Diagnostic nou păstrat"), "A minimized diagnostic can be reopened with all messages intact")
			minimize.pressed.emit()
			await get_tree().create_timer(0.2).timeout
			_workspace_capture(output, "panels-minimized")
	hide_bottom_panel()
	panel.chat.expand_button.pressed.emit()
	await get_tree().process_frame
	panel.chat.expand_button.pressed.emit()
	await get_tree().process_frame
	_check(bottom.current_tab == -1, "Restoring chat leaves an initially closed bottom panel closed")
	make_bottom_panel_item_visible(diagnostic)
	panel.chat.expand_button.pressed.emit()
	await get_tree().process_frame
	var alternate = VBoxContainer.new()
	add_control_to_bottom_panel(alternate, "Inspect QA")
	make_bottom_panel_item_visible(alternate)
	var alternate_tab = bottom.get_current_tab_control()
	panel.chat.expand_button.pressed.emit()
	await get_tree().process_frame
	_check(bottom.get_current_tab_control() == alternate_tab, "Restoring panels respects a different diagnostic selected by the user")
	remove_control_from_bottom_panel(alternate)
	alternate.queue_free()
	for side in [1, 2]:
		panel._set_placement(side, false)
		await get_tree().create_timer(0.2).timeout
		make_bottom_panel_item_visible(diagnostic)
		panel.chat.expand_button.pressed.emit()
		await get_tree().create_timer(0.2).timeout
		_check(panel.current_placement == 0 and bottom.current_tab == -1, "Expanding a side chat also folds diagnostics: " + str(side))
		panel.chat.expand_button.pressed.emit()
		await get_tree().create_timer(0.2).timeout
		_check(panel.current_placement == side and bottom.get_current_tab_control() == diagnostic_tab, "Restoring a side chat recovers its position and diagnostic panel: " + str(side))
	hide_bottom_panel()
	remove_control_from_bottom_panel(diagnostic)
	diagnostic.queue_free()
	panel.composer.text = draft
	if is_instance_valid(previous_bottom) and previous_bottom.get_parent() == bottom: bottom.current_tab = bottom.get_tab_idx_from_control(previous_bottom)
	panel._set_placement(previous_placement, false)
	if previous_expanded: panel.chat.expand_button.pressed.emit()

func _workspace_capture(output: String, filename: String) -> void:
	if output.is_empty(): return
	RenderingServer.force_draw(false)
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(output.path_join(filename + ".png"))

func _generation_catalog_tests(output: String) -> void:
	var original = panel.config["generation"].duplicate(true)
	var transport = panel.assets.transport
	var urls = panel.assets.api_urls.duplicate()
	var catalog_urls = panel.assets.catalog_urls.duplicate()
	var prices = panel.assets.catalog_prices.duplicate(true)
	var test_http = panel.assets.test_http
	var old_keys = {}
	for kind in ["runware", "meshy", "tripo", "openai_image"]:
		old_keys[kind] = panel.vault.read("generation_" + kind)
		panel.vault.erase("generation_" + kind)
	var fixture = GenerationTransport.new()
	fixture.host = self
	panel.assets.transport = fixture
	panel.assets.test_http = true
	panel.assets.catalog_prices = {}
	panel.assets.catalog_urls["runware"] = "http://127.0.0.1/docs/index.json"
	panel.config["generation"] = []
	panel._refresh_lists()
	var form: Dictionary = panel.forms["generation"]
	form["kind"].select(0)
	form["asset_kind"].select(0)
	panel._new_generation()
	panel.open_settings("generation")
	_check(not form["model_list"].visible and form["save"].disabled, "A new image profile asks for a key before model selection or saving")
	form["key"].text = "sk-fixture-generation-valid"
	form["key"].text_changed.emit(form["key"].text)
	await _wait_generation_catalog()
	_check(form["catalog_verified"] and form["model_records"].size() == 2 and form["model_list"].visible, "Pasting a draft cloud key discovers image models without requiring a saved profile: " + form["catalog_status"].text)
	_check(form["model_rows"]["fixture:image@1"].get_text(1) == "0,04 USD+" and form["model_rows"]["fixture:image@2"].get_text(1) == "Indisponibil", "Every image model has its own price cell, and unknown tariffs never show zero")
	form["model_rows"]["fixture:image@1"].select(0)
	panel._generation_model_selected()
	_check(form["model"].text == "fixture:image@1" and not form["save"].disabled and form["price_detail"].text.contains("/ imagine"), "Selecting an image model updates the model ID, cost details and save control")
	panel._save_generation()
	var image_id = str(form["editing"])
	_check(form["catalog_verified"] and form["model_list"].visible and form["model"].text == "fixture:image@1", "Saving and clearing the secret field preserves the selected model and its visible catalog")
	_check(panel._generation_profile(image_id).get("model_info", {}).get("price", {}).get("amount") == 0.04 and not JSON.stringify(panel.config).contains("sk-fixture-generation-valid"), "Saving keeps model price metadata while the API key remains exclusively in the vault")
	if not output.is_empty():
		await get_tree().create_timer(0.15).timeout
		panel.settings_window.get_texture().get_image().save_png(output.path_join("generation-images.png"))
	form["asset_kind"].select(1)
	form["asset_kind"].item_selected.emit(1)
	await _wait_generation_catalog()
	_check(form["model_records"].size() == 1 and form["model_records"][0]["id"] == "fixture:mesh@1" and str(form["editing"]).is_empty(), "Switching to 3D reuses the provider key but creates a distinct profile with only mesh models")
	form["model_rows"]["fixture:mesh@1"].select(0)
	panel._generation_model_selected()
	panel._save_generation()
	_check(panel.config["generation"].size() == 2 and panel._generation_profile(image_id).get("asset_kind") == "image" and panel._generation_profile().get("credential_id") == "generation_runware", "Image and 3D profiles retain independent models and share the one provider key")
	if not output.is_empty():
		await get_tree().create_timer(0.15).timeout
		panel.settings_window.get_texture().get_image().save_png(output.path_join("generation-meshes.png"))
	form["model_search"].text = "missing-model"
	form["model_search"].text_changed.emit("missing-model")
	_check(form["model_rows"].is_empty(), "Model search filters the current provider and result type")
	form["model_search"].clear()
	form["model_search"].text_changed.emit("")
	form["key"].text = "sk-fixture-generation-invalid"
	form["key"].text_changed.emit(form["key"].text)
	await _wait_generation_catalog()
	_check(not form["catalog_verified"] and form["model_records"].is_empty() and form["save"].disabled and panel.vault.read("generation_runware") == "sk-fixture-generation-valid", "A rejected replacement key clears stale choices and preserves the valid shared credential")
	_check(not form["catalog_status"].text.contains("sk-fixture-generation-invalid"), "A draft API key echoed by an authentication error is masked in the catalog status")
	if not output.is_empty(): panel.settings_window.get_texture().get_image().save_png(output.path_join("generation-invalid-key.png"))
	form["kind"].select(2)
	form["kind"].item_selected.emit(2)
	_check(form["key"].text.is_empty() and str(form["editing"]).is_empty(), "Changing cloud providers never carries the previous provider key or overwrites its profile")
	form["asset_kind"].select(0)
	form["asset_kind"].item_selected.emit(0)
	form["key"].text = "sk-fixture-generation-valid"
	form["key"].text_changed.emit(form["key"].text)
	await _wait_generation_catalog()
	_check(form["catalog_verified"] and form["model_records"].size() == 7 and form["model_rows"]["nano-banana"].get_text(1) == "3 cr.", "Meshy image catalog offers documented models with their native credit prices")
	form["model_rows"]["nano-banana"].select(0)
	panel._generation_model_selected()
	if not output.is_empty():
		await get_tree().create_timer(0.15).timeout
		panel.settings_window.get_texture().get_image().save_png(output.path_join("generation-meshy.png"))
	form["key"].text = "sk-fixture-generation-invalid"
	form["key"].text_changed.emit(form["key"].text)
	form["kind"].select(3)
	form["kind"].item_selected.emit(3)
	await get_tree().create_timer(0.9).timeout
	_check(not form["catalog_verified"] and form["model_records"].is_empty(), "A delayed key-paste callback cannot populate a different provider after selection changes")
	# Legacy profiles may still have their key under the profile UUID.
	panel.vault.erase("generation_runware")
	panel.vault.store(image_id, "sk-fixture-generation-valid")
	panel.config["generation"][0].erase("credential_id")
	panel._edit_generation(0)
	await _wait_generation_catalog()
	_check(form["catalog_verified"] and form["model"].text == "fixture:image@1" and panel.vault.read("generation_runware") == "sk-fixture-generation-valid", "A legacy per-profile key is verified and reused without asking the user to paste it again")
	panel.vault.erase(image_id)
	_check(fixture.paid_requests == 0 and fixture.public_headers.all(func(headers: PackedStringArray) -> bool: return not str(headers).contains("Bearer")), "Catalog, pricing, key checks and profile saving submit no paid generation and send no secret to public docs")
	panel._cancel_generation_catalog()
	panel.assets.transport = transport
	panel.assets.api_urls = urls
	panel.assets.catalog_urls = catalog_urls
	panel.assets.catalog_prices = prices
	panel.assets.test_http = test_http
	for kind in old_keys:
		if str(old_keys[kind]).is_empty(): panel.vault.erase("generation_" + kind)
		else: panel.vault.store("generation_" + kind, old_keys[kind])
	panel.config["generation"] = original
	panel._new_generation()
	panel._refresh_lists()
	panel.settings_window.hide()

func _wait_generation_catalog() -> void:
	await get_tree().create_timer(1.0).timeout
	var limit = Time.get_ticks_msec() + 10000
	while panel.generation_loading and Time.get_ticks_msec() < limit: await get_tree().process_frame
