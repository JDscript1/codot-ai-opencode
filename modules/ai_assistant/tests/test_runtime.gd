extends SceneTree

var scripts: Dictionary = {}
var failures = 0
var assertions = 0
var source_directory = ""
var mock_url = ""

class FakeVault:
	extends RefCounted
	var values = {}
	func store(name: String, value: String) -> bool:
		values[name] = value
		return true
	func read(name: String) -> String: return str(values.get(name, ""))
	func erase(name: String) -> bool: return values.erase(name)

class UnreachableBlenderTransport:
	extends RefCounted
	func request(_url: String, _method: int, _headers: PackedStringArray, _body: Variant, _options: Dictionary) -> Dictionary:
		return {"ok": false, "code": "connection_failed", "error": "Fixture connector is not listening"}

class SyntaxBridge:
	extends Node
	func script_diagnostics(source: String, path: String) -> Dictionary:
		var diagnostics = [{"severity": "warning", "line": 1, "column": 1, "message": "Fixture warning"}]
		if "broken" in source:
			for index in range(25):
				diagnostics.append({"severity": "error", "line": index + 2, "column": 1, "message": "Fixture parse error %d" % (index + 1)})
		return {"ok": true, "result": {"path": path, "valid": not "broken" in source, "diagnostics": diagnostics, "functions": [], "truncated": false}}

class DebuggerBridge:
	extends Node
	var snapshot = {"available": true, "errors": 1, "warnings": 0, "truncated": false, "sessions": [{"session": 0, "generation": 2, "active": false}], "events": []}
	func debugger_snapshot() -> Dictionary:
		return {"ok": true, "result": snapshot.duplicate(true)}

class NativePanelBridge:
	extends Node
	var calls = []
	func panel_snapshot(section: String, session: int, offset: int, limit: int, frame: int, monitor: String = "") -> Dictionary:
		var args = [section, session, offset, limit, frame]
		if not monitor.is_empty(): args.append(monitor)
		calls.append(args)
		return {"ok": true, "result": {"available": true, "collected": false, "section": section, "items": []}}

class HarnessHost:
	extends RefCounted
	var replies: Array = []
	var contexts: Array = []
	var catalogs: Array = []
	var executed: Array = []
	var checkpoints: Array = []
	var token = {}
	var stop_after_tool = false
	var tool_result = {"ok": true, "result": "fixture-secret"}
	var tool_results: Array = []
	var narrowed_arguments = {}
	var fail_checkpoint_status = ""
	var reenter: RefCounted
	var reentry_result = {}

	func complete(context: Array, _tools: Array, _cancel: Dictionary, delta: Callable) -> Dictionary:
		if reenter != null: reentry_result = await reenter.run({}, hooks())
		contexts.append(context.duplicate(true))
		catalogs.append(_tools.duplicate(true))
		if replies.is_empty(): return {"ok": false, "code": "fixture_exhausted", "error": "No fixture response"}
		var reply: Dictionary = replies.pop_front()
		if reply.has("_delta"): delta.call(str(reply["_delta"]))
		return reply

	func execute(name: String, arguments: Dictionary) -> Dictionary:
		executed.append({"name": name, "arguments": arguments})
		arguments.merge(narrowed_arguments, true)
		if stop_after_tool: token["cancelled"] = true
		return tool_result if tool_results.is_empty() else tool_results.pop_front()

	func checkpoint(snapshot: Dictionary) -> bool:
		checkpoints.append(snapshot.duplicate(true))
		return snapshot.get("status") != fail_checkpoint_status
	func redact(value: String) -> String: return value.replace("fixture-secret", "[redacted]")
	func hooks() -> Dictionary: return {"complete": complete, "execute": execute, "checkpoint": checkpoint, "redact": redact}

class ResponsesTransport:
	extends RefCounted
	var batches: Array = []
	var requests: Array = []
	func request(_url: String, _method: int, _headers: PackedStringArray, body: Variant, options: Dictionary) -> Dictionary:
		requests.append(body.duplicate(true))
		if batches.is_empty(): return {"ok": false, "error": "No fixture response"}
		var events: Array = batches.pop_front()
		for event in events: options["on_event"].call(event)
		return {"ok": true, "events": events}

class ResponsesHost:
	extends HarnessHost
	var provider: RefCounted
	var kind = "responses"
	func complete(context: Array, definitions: Array, cancel_token: Dictionary, delta: Callable) -> Dictionary:
		contexts.append(context.duplicate(true))
		return await provider.complete({"id": "fixture", "issuer": "openai", "kind": kind, "url": "https://api.openai.com/v1"}, context, definitions, "fixture-model", "", cancel_token, delta)

class PricingTransport:
	extends RefCounted
	var requests = 0
	var seen_headers: Array = []
	var text = ""
	var fail = false
	func request(_url: String, method: int, headers: PackedStringArray, body: Variant, _options: Dictionary) -> Dictionary:
		requests += 1
		seen_headers.append(headers)
		if fail: return {"ok": false, "error": "Offline"}
		return {"text": text, "ok": method == HTTPClient.METHOD_GET and body == null, "json": {"data": [{"id": "fixture/model", "pricing": {"prompt": "0.000002", "completion": "0.000008", "input_cache_read": "0.0000002"}}]}}

func _model_pricing_tests(node: Node) -> void:
	var pricing = scripts["model_pricing"]
	var api = pricing.from_api({"pricing": {"prompt": "0.000002", "completion": "0.000008", "input_cache_read": "0.0000002"}}, "openrouter", "https://openrouter.ai/api/v1/models")
	check(api["input"] == 2 and api["output"] == 8 and is_equal_approx(api["cached_input"], 0.2), "OpenRouter per-token prices convert exactly to per-million input, output and cache rates")
	check(pricing.from_api({"pricing": {"prompt": "-1", "completion": "0"}}, "openrouter", "").is_empty(), "Dynamic routers and negative tariffs are never treated as free models")
	check(pricing.from_api({"pricing": {"prompt": "0.2", "completion": "0.3"}}, "deepseek", "").is_empty(), "Unknown price units and another provider's schema are never guessed")
	check(pricing.rate_label({}).contains("nepublicat") and pricing.rate_label({"input": 0, "output": 0}).begins_with("0 / 0"), "Unpublished prices remain distinct from explicitly free API models")
	var markdown = "| Model | Short context input | Short context output | Short context cached input | Long context input | Long context output |\n| --- | --- | --- | --- | --- | --- |\n| fixture-code | $2 | $8 | $0.2 | $4 | $12 |\n\n### Batch\n| Model | Input | Output |\n| --- | --- | --- |\n| fixture-code | $1 | $4 |\n"
	var rates = pricing.parse_document("openai", markdown)
	var rate: Dictionary = rates.get("fixturecode", {})
	check(rate.get("input") == 2 and rate.get("output") == 8 and pricing.column_label(rate, "input") == "2–4", "Standard tariffs retain long-context variants and are never replaced by discounted batch rates")
	check(pricing.money("$2 through today; $4 tomorrow") == null and pricing.money("$3 / image") == null, "Ambiguous scheduled changes and non-token units fail closed")
	var mistral = pricing.parse_document("mistral", "| Model | API name | Price |\n| --- | --- | --- |\n| Sample model | fixture-code | Input $0.2 /M Tokens<br>Cached input $0.02 /M Tokens<br>Output $0.8 /M Tokens |\n")
	check(mistral.get("fixturecode", {}).get("input") == 0.2 and mistral.get("fixturecode", {}).get("cached_input") == 0.02, "Combined Mistral price cells use the documented API identifier and distinguish cached input")
	var changed = pricing.parse_document("openai", "A redesigned page, no pricing table")
	check(changed.is_empty(), "A provider documentation redesign cannot silently fabricate prices")
	var service = pricing.new(node)
	var fixture = PricingTransport.new()
	service.transport = fixture
	var directory = OS.get_user_data_dir().path_join("pricing-" + scripts["common"].uid())
	service.configure(directory)
	var profile = {"issuer": "openrouter", "kind": "chat", "official_pricing": true}
	var models = [{"id": "fixture/model"}]
	check((await service.refresh(profile, models)).get("ok", false) and models[0]["pricing"]["output"] == 8, "First use fetches and applies the live public catalog")
	await service.refresh(profile, models)
	check(fixture.requests == 1, "A fresh six-hour rate cache avoids repeated background requests")
	var restored = pricing.new(node)
	restored.configure(directory)
	restored.apply(profile, models)
	check(models[0]["pricing"]["input"] == 2, "Numeric tariffs and their source date survive an offline restart")
	fixture.fail = true
	check(not (await service.refresh(profile, models, {}, true)).get("ok", false) and models[0]["pricing"].get("stale", false), "A failed manual update retains the last known rate and marks it stale")
	# Expire the retained cache so automatic retry backoff can be exercised.
	service.cache["openrouter"]["checked_at"] = 1
	await service.refresh(profile, models)
	check(fixture.requests == 2, "Automatic retries back off after a failed pricing request")
	service.apply({"issuer": "deepseek", "official_pricing": false}, models)
	check(not models[0]["pricing"].has("input"), "A custom billing endpoint never inherits official direct-provider prices")
	service.apply({"issuer": "lmstudio"}, models)
	check(models[0]["pricing"].get("mode") == "local", "Local models are labeled separately from cloud API costs")
	service.apply({"issuer": "openai", "kind": "siwc"}, models)
	check(models[0]["pricing"].get("mode") == "subscription", "Subscription accounts are never assigned API token charges")
	check(fixture.seen_headers.all(func(headers: PackedStringArray) -> bool: return not str(headers).contains("Bearer") and not str(headers).contains("api-key")), "Pricing reads send no saved credentials to documentation websites")
	fixture.fail = false
	fixture.text = "Documentation\n".repeat(6000) + "| Model | Input | Output |\n| --- | --- | --- |\n| fixture-code | $2 | $8 |\n"
	var threaded_models = [{"id": "fixture-code"}]
	check((await service.refresh({"issuer": "openai", "official_pricing": true}, threaded_models, {}, true)).get("ok", false) and threaded_models[0]["pricing"]["output"] == 8, "Large price documents parse on a worker and return their verified rates to the UI thread")
	check(not scripts["providers"].pricing_profile({"issuer": "deepseek", "url": "https://another-billing.example/v1"}).get("official_pricing", true), "Official price matching checks the full billing endpoint")
	check(scripts["providers"].pricing_profile({"issuer": "deepseek", "url": ""}).get("official_pricing", false), "A restored default DeepSeek endpoint remains eligible for its own official prices")

func _blender_diagnostic_tests(node: Node) -> void:
	var base = OS.get_user_data_dir().path_join("blender-diagnostic-" + scripts["common"].uid())
	var backend = scripts["termux_blender"].new(node)
	backend.configure(base, base.path_join("project"))
	backend.transport = UnreachableBlenderTransport.new()
	var calls = []
	var events = []
	var device = {"ok": true, "installed": false, "permission": false, "supported": true, "compatible": true}
	var secret = "b".repeat(64)
	backend.diagnostic.connect(func(entry: Dictionary) -> void: events.append(entry))
	backend.native_override = func(action: String, _args: Dictionary) -> Dictionary:
		calls.append(action)
		if action == "connection": return {"ok": true, "url": "http://127.0.0.1:34567", "token": secret}
		if action == "start": return {"ok": false, "code": "termux_start_failed", "error": "Fixture Android startup rejected " + secret + " api_key=fixture-redaction-key"}
		return device.duplicate()
	await backend.refresh()
	check(backend.diagnostics().get("code") == "missing_termux" and not backend.log_text.is_empty(), "Termux detection writes a diagnostic before any Blender job exists")
	var count = backend.log_entries.size()
	await backend.refresh()
	check(backend.log_entries.size() == count and events.size() == count, "Unchanged periodic status checks do not fill either journal with duplicate entries")
	device["installed"] = true
	await backend.refresh()
	check(backend.diagnostics().get("code") == "permission_required" and backend.log_text.contains("Permisiunea Android"), "A denied Android permission is explained and logged before startup")
	backend.native("permission")
	check(backend.log_text.contains("Permisiune Android solicitată"), "Requesting the Android permission records the user action")
	device["permission"] = true
	check(not await backend.ensure_ready() and backend.diagnostics().get("code") == "setup_required" and not calls.has("start"), "An enabled but unconfigured backend records its next step without installing or launching anything")
	var result = await backend.setup("connect")
	check(result.get("code") == "termux_start_failed" and backend.log_text.contains("Pornire conector local") and backend.log_text.contains("Fixture Android startup rejected"), "Android startup errors retain the preceding connection steps in the journal")
	check(not backend.log_text.contains(secret) and not backend.log_text.contains("fixture-redaction-key") and not JSON.stringify(events).contains(secret), "Connection secrets are removed from both persistent logs and emitted journal events")
	await backend.refresh()
	check(backend.diagnostics().get("code") == "termux_start_failed", "Refreshing the integration preserves the failed startup reason")
	backend.job_log = "worker-output\n".repeat(4000) + secret
	backend._save_log()
	check(backend.log_text.length() <= backend.LOG_LIMIT * 2 and backend.log_text.contains("Fixture Android startup rejected") and backend.log_text.contains("worker-output"), "Worker output is bounded and retains connection diagnostics")
	var reopened = scripts["termux_blender"].new(node)
	reopened.configure(base, base.path_join("project"))
	check(reopened.log_text == backend.log_text and not reopened.log_text.contains(secret), "Reopening the editor restores the redacted Blender journal")
	var persisted = FileAccess.get_file_as_string(base.path_join("blender/diagnostics.json"))
	check(not persisted.contains(secret) and not persisted.contains("fixture-redaction-key"), "The diagnostics file never stores the fixture credentials")
	calls.clear()
	device["launch_mode"] = "manual"
	device["permission"] = false
	await backend.refresh()
	check(backend.diagnostics().get("code") == "manual_start_required", "A Termux variant without RUN_COMMAND requests terminal pairing instead of an undefined Android permission")
	result = await backend.setup("connect")
	check(result.get("code") == "manual_start_required" and not calls.has("start") and not calls.has("permission"), "Manual connection never requests an unavailable permission or sends RUN_COMMAND")
	result = backend.prepare_manual()
	check(result.get("ok", false) and calls.has("copy_bootstrap") and calls.has("open_termux") and backend.manual_setup_pending, "Explicit manual setup copies the private bootstrap and opens Termux for user execution")
	check(not backend.log_text.contains(secret) and not JSON.stringify(result).contains(secret), "Manual pairing does not return its private command or token to GDScript results or logs")
	var probe = {"ok": true, "run_id": "probe-1", "status": "completed", "result": "Runtime Linux ARM64 verificat."}
	backend.native_override = func(action: String, _args: Dictionary) -> Dictionary:
		return probe.duplicate() if action == "embedded_status" else device.duplicate()
	count = backend.log_entries.size()
	backend._report_embedded_probe()
	backend._report_embedded_probe()
	check(backend.log_entries.size() == count + 1 and backend.log_entries[-1].get("code") == "embedded_runtime_verified", "A completed native runtime probe is journaled once per run")
	check(not backend.available() and backend.runtime.is_empty(), "A Linux probe alone never enables Blender or advertises its tools")
	probe.merge({"run_id": "probe-2", "status": "failed", "error": "Loader rejected by Android"}, true)
	backend._report_embedded_probe()
	check(backend.log_entries[-1].get("failed") and backend.log_text.contains("Loader rejected by Android"), "Android loader errors remain visible in the persistent journal")

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--source="): source_directory = argument.trim_prefix("--source=")
		if argument.begins_with("--mock-url="): mock_url = argument.trim_prefix("--mock-url=")
	if source_directory.is_empty():
		push_error("Pass -- --source=/absolute/path/to/modules/ai_assistant")
		quit(2)
		return
	for name in ["common", "engineering_store", "qa_scenarios", "asset_audit", "experiments", "engineering", "project_knowledge", "diagnostics", "verification", "diff", "change_set", "transport", "tool_registry", "model_pricing", "providers", "panel_reader", "editor_tools", "mcp", "asset_exports", "generation_catalog", "assets", "accounts", "conversations", "icons", "planner", "markdown", "tool_preview", "diagram", "file_registry", "model_preview", "media_view", "chat_view", "harness", "agent_jobs", "speech", "workspace", "termux_blender", "linux_runtime", "ziva", "ziva_screen", "integrations", "store", "editor_control", "panel"]:
		var script = GDScript.new()
		script.take_over_path("res://__godot_ai_builtin__/" + name + ".gd")
		script.source_code = FileAccess.get_file_as_string(source_directory.path_join("runtime/" + name + ".gd"))
		var error = script.reload()
		check(error == OK, "Embedded script compiles: " + name)
		if error != OK:
			quit(1)
			return
		var bindings = {"common": "Common", "engineering_store": "EngineeringStore", "qa_scenarios": "QAScenarios", "asset_audit": "AssetAudit", "experiments": "Experiments", "engineering": "Engineering", "project_knowledge": "ProjectKnowledge", "diagnostics": "Diagnostics", "verification": "Verification", "diff": "Diff", "change_set": "ChangeSet", "transport": "Transport", "tool_registry": "ToolRegistry", "model_pricing": "ModelPricing", "providers": "Providers", "panel_reader": "PanelReader", "editor_tools": "Tools", "mcp": "MCP", "asset_exports": "AssetExports", "generation_catalog": "GenerationCatalog", "assets": "Assets", "accounts": "Accounts", "conversations": "Conversations", "icons": "Icons", "planner": "Planner", "markdown": "Markdown", "tool_preview": "ToolPreview", "diagram": "Diagram", "file_registry": "FileRegistry", "model_preview": "ModelPreview", "media_view": "MediaView", "chat_view": "ChatView", "harness": "Harness", "agent_jobs": "AgentJobs", "speech": "Speech", "workspace": "Workspace", "termux_blender": "TermuxBlender", "linux_runtime": "LinuxRuntime", "ziva": "Ziva", "ziva_screen": "ZivaScreen", "integrations": "Integrations", "store": "Store", "editor_control": "EditorControl"}
		for dependency in scripts: script.set(bindings[dependency], scripts[dependency])
		scripts[name] = script
	var common = scripts["common"]
	var providers = scripts["providers"]
	check(common.project_path("res://../outside.txt").is_empty(), "Reject project traversal")
	check(common.project_path("res://.godot/cache").is_empty(), "Reject editor-private project paths")
	check(common.project_path("res://scripts/player.gd") == "res://scripts/player.gd", "Accept project file")
	check(not common.parse_url("https://example.com@attacker.test").get("ok", false), "Reject URL userinfo")
	check(not common.parse_url("https://example.test/\nAuthorization: secret").get("ok", false), "Reject URL header injection")
	check(not common.parse_url("http://127.0.0.1:1234/v1").get("ok", false), "HTTP requires explicit local opt-in")
	check(common.parse_url("http://192.168.1.8:1234/v1", true).get("ok", false), "Allow configured LAN endpoint")
	check(common.parse_url("http://[::1]:1234/v1", true).get("ok", false), "Allow configured IPv6 endpoint")
	for entry in providers.CATALOG:
		if entry.get("local", false) or entry["id"] == "custom": continue
		var default_endpoint = providers.endpoint({"issuer": entry["id"]})
		check(default_endpoint.get("ok", false) and default_endpoint.get("result") == entry["url"], "Known cloud provider restores its catalog endpoint: " + str(entry["id"]))
	check(providers.endpoint({"issuer": "deepseek", "url": ""}).get("result") == "https://api.deepseek.com", "An empty saved DeepSeek endpoint recovers its official catalog URL")
	check(providers.endpoint({"issuer": "deepseek", "url": "https://gateway.example.test/v1/"}).get("result") == "https://gateway.example.test/v1", "A configured compatible gateway is preserved instead of silently changing destination")
	check(not providers.endpoint({"issuer": "custom"}).get("ok", false) and not providers.endpoint({"issuer": "lmstudio"}).get("ok", false), "Unknown and local endpoints still require an explicit server address")
	check(common.uid().length() == 36 and common.uid().get_slice("-", 2).begins_with("4"), "Task identifiers use UUIDv4")
	var assets_script = scripts["assets"]
	var rodin = assets_script.build_runware_task({"asset_kind": "mesh", "model": "hyper3d:rodin@gen-2"}, "bird", "data:image/png;base64,fixture", common.uid())
	check(rodin.get("result", {}).get("inputs", {}).get("images") == ["data:image/png;base64,fixture"] and not rodin["result"].has("inputImages"), "Rodin reference uses documented nested inputs.images")
	var rapid = assets_script.build_runware_task({"asset_kind": "mesh", "model": "tencent:hunyuan-3d@3.1-rapid"}, "bird", "data:image/png;base64,fixture", common.uid())
	check(rapid.get("result", {}).get("inputs", {}).has("image") and not rapid["result"].has("positivePrompt"), "Hunyuan Rapid reference uses inputs.image without exclusive prompt")
	check(not assets_script.build_runware_task({"asset_kind": "mesh", "model": "microsoft:trellis-2@4b"}, "bird", "", common.uid()).get("ok", false), "Image-only 3D model requires a reference before submitting")
	check(not assets_script.build_runware_task({"asset_kind": "image", "model": "fixture"}, "bird", "fixture-reference", common.uid()).get("ok", false), "Unsupported image reference is reported rather than silently discarded")
	check(common.decode_variant({"$type": "Vector3", "value": [1, 2, 3]}) == Vector3(1, 2, 3), "Decode typed Godot arguments")
	check(not "fixture-secret" in common.redact("Bearer fixture-secret", ["fixture-secret"]), "Redact credentials")
	check(common.contains_inline_secrets({"1": {"inputs": {"api_key": "fixture-key"}}}), "Workflow credentials are detected before saving")
	check(not common.contains_inline_secrets({"1": {"inputs": {"token_count": 77}}}), "Ordinary workflow parameters remain supported")
	var decoder = scripts["transport"].SSEDecoder.new()
	var events = []
	var data = "data: {\"value\":\"română 🐦\"}\r\n\r\ndata: [DONE]\n\n".to_utf8_buffer()
	for byte in data: decoder.feed(PackedByteArray([byte]), func(event: Dictionary) -> void: events.append(event))
	check(events.size() == 1 and events[0]["value"] == "română 🐦", "SSE preserves UTF-8 across arbitrary byte boundaries")
	check(decoder.ended, "SSE recognizes terminal sentinel")
	check(providers.hosting({"issuer": "custom", "url": "http://192.168.2.5:1234/v1"}) == "local" and providers.hosting({"issuer": "custom", "url": "https://api.example.com"}) == "cloud", "LAN compatible profiles and cloud endpoints are grouped by hosting")
	check(providers.hosting({"issuer": "custom", "url": "https://private.example.com", "hosting": "local"}) == "local", "Self-hosted public domains can explicitly select local hosting")
	var targets = providers.lan_targets(["192.168.3.8", "192.168.3.9", "10.0.0.4", "172.16.1.2", "8.8.8.8", "127.0.0.1", "192.168.300.3"])
	check(targets.size() == 1524 and targets.all(func(item: Dictionary) -> bool: return providers.private_ipv4(item["host"]) and item["port"] in [11434, 1234, 8080]), "Discovery is bounded to two private segments and known ports")
	var prioritized = providers.lan_addresses([{"name": "tun0", "addresses": ["10.0.0.9"]}, {"name": "rmnet0", "addresses": ["172.16.2.9"]}, {"name": "wlan0", "addresses": ["192.168.3.8"]}])
	check(prioritized == ["192.168.3.8", "10.0.0.9", "172.16.2.9"] and providers.lan_targets(prioritized)[0]["host"] == "192.168.3.8", "Wi-Fi subnet is searched before VPN or cellular private addresses")
	check(not providers.detect("sk-generic-fixture").get("ok", false), "Ambiguous keys never trigger issuer guessing")
	check(providers.detect("DEEPSEEK_API_KEY=sk-generic-fixture").get("profile", {}).get("id") == "deepseek", "Labeled key determines issuer")
	var messages = [{"role": "system", "content": "Inspect"}, {"role": "user", "content": "Create"}, {"role": "assistant", "content": "", "reasoning_content": "Retained reasoning", "tool_calls": [{"id": "a", "name": "godot_project", "arguments": {}}]}, {"role": "tool", "tool_call_id": "a", "tool_name": "godot_project", "content": "{}"}]
	var chat = providers.build_request("chat", messages, [], "fixture")
	check(chat["body"]["messages"][2]["tool_calls"][0]["function"]["name"] == "godot_project", "Preserve multi-turn chat tool calls")
	check(chat["body"]["messages"][2]["reasoning_content"] == "Retained reasoning", "Retain DeepSeek reasoning during tool loops")
	var siwc = providers.build_request("siwc", messages, [], "fixture")
	check(siwc["body"]["store"] == false and siwc["body"]["stream"] == true, "SIWC streaming and storage requirements")
	check(not siwc["body"].has("max_output_tokens") and not siwc["body"].has("temperature"), "SIWC omits unsupported request parameters")
	check(siwc["body"]["input"][-1]["type"] == "function_call_output", "Responses tool result round trip")
	var anthropic = providers.build_request("anthropic", messages, [], "fixture")
	check(anthropic["body"]["messages"][-1]["content"][0]["type"] == "tool_result", "Anthropic tool result round trip")
	var tools = scripts["editor_tools"].new()
	check(tools.execute("godot_write_file", {"path": "res://must-not-exist.txt", "text": "unsafe"}, 0, true).get("code") == "permission_denied", "Analysis denies mutations even with full control")
	check(tools.execute("godot_call", {"handle": "x", "method": "set", "arguments": []}, 2, false).get("code") == "permission_denied", "Full-control toggle independently gates reflection")
	check(not FileAccess.file_exists("res://must-not-exist.txt"), "Denied tools have no file side effects")
	check(not tools.validate("godot_read_file", {"path": 2}).get("ok", false), "Reject invalid tool argument types")
	var auth = scripts["accounts"]
	check(auth._parse_query("state=abc&code=a%2Bb")["code"] == "a+b", "OAuth callback decoding")
	check(auth._parse_query("client_id=oaiapp_test")["client_id"] == "oaiapp_test", "Issued client ID is retained")
	check(auth._unbase64url(auth._base64url(PackedByteArray([0, 255, 128]))) == PackedByteArray([0, 255, 128]), "PKCE/base64url round trip")
	var panel = scripts["panel"].new()
	panel.history = messages.duplicate(true)
	panel.history.append({"role": "assistant", "content": "", "tool_calls": [{"id": "interrupted", "name": "godot_run", "arguments": {}}]})
	panel._close_unanswered_calls()
	check(panel.history[-1].get("tool_call_id") == "interrupted" and "cancelled" in str(panel.history[-1].get("content", "")), "Interrupted tool loops can be resumed")
	panel.free()
	_new_feature_tests()
	_tool_registry_tests()
	_diff_tests()
	var vision_profile = {"models": [{"id": "vision", "capabilities": {"vision": true}}, {"id": "unknown", "capabilities": {}}], "vision_overrides": {"unknown": 1, "text": 2}}
	check(scripts["providers"].vision_allowed(vision_profile, "vision"), "Declared vision support permits referenced image pixels")
	check(scripts["providers"].vision_allowed(vision_profile, "unknown"), "Explicit per-model vision permission supports catalogs without modality metadata")
	check(not scripts["providers"].vision_allowed(vision_profile, "text") and not scripts["providers"].vision_allowed(vision_profile, "missing"), "Text-only and unknown models never receive images implicitly")
	vision_profile["vision_overrides"]["vision"] = 2
	check(not scripts["providers"].vision_allowed(vision_profile, "vision"), "An explicit text-only choice takes precedence over catalog vision metadata")
	var node = Node.new()
	root.add_child(node)
	var engineering_tests = load(source_directory.path_join("tests/test_engineering.gd"))
	await engineering_tests.run(scripts, self, check)
	await load(source_directory.path_join("tests/test_speech.gd")).new().run(self, scripts)
	_panel_reader_tests(node)
	await _model_pricing_tests(node)
	await _blender_diagnostic_tests(node)
	var transport = scripts["transport"].new(node)
	await _file_registry_tests(node)
	_planning_tests(node)
	await _intelligence_tests(node)
	await _change_set_tests(node)
	await _recovery_tests(node)
	await _context_budget_tests(node)
	await _workflow_tests(node)
	await _harness_tests(node)
	await _responses_continuation_tests(node)
	await _behavior_tests(node)
	var pre_cancelled = await transport.request("http://127.0.0.1:1/", HTTPClient.METHOD_GET, [], null, {"allow_http": true, "cancel": {"cancelled": true}})
	check(not pre_cancelled.get("ok", false), "Pre-cancelled requests terminate")
	if not mock_url.is_empty():
		await _network_tests(node)
		await _local_connection_tests(node)
		await _cloud_generation_tests(node)
		await _integration_tests(node)
		await _store_tests(node)
	node.queue_free()
	await process_frame
	print("Godot AI: %s assertions, %s failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)

func _agent_response(text: String = "", calls: Array = [], finish: String = "stop") -> Dictionary:
	return {"ok": true, "message": {"role": "assistant", "content": text, "tool_calls": calls}, "calls": calls, "finish": finish}

func _integration_tests(node: Node) -> void:
	var service = scripts["integrations"].new(node, FakeVault.new())
	service.api_url = mock_url
	service.test_http = true
	check((await service.github_account()).get("code") == "missing_credentials", "GitHub requires a personal token")
	check((await service.github_request("fixture/project", {"resource": "repository"})).get("code") == "missing_credentials", "Repository access requires the personal token")
	service.vault.store("integration_github", "bad-token")
	check((await service.github_account()).get("code") == "github_auth_error", "Invalid personal token fails account verification")
	service.vault.store("integration_github", "github-fixture-token")
	var signed_in = await service.github_account()
	check(signed_in.get("result", {}).get("login") == "fixture", "Personal token verifies the GitHub account")
	var repositories = await service.github_repositories(1)
	check(repositories.get("result", []).size() == 2 and repositories["result"][1]["private"], "Native GitHub repository picker retrieves public and authorized private repositories")
	var discovered = await scripts["providers"].new(node).probe_targets([{"host": "127.0.0.1", "port": int(mock_url.get_slice(":", 2))}], {})
	check(discovered.get("result", {}).get("servers", []).size() == 1 and discovered["result"]["servers"][0]["model_count"] == 1, "LAN discovery verifies an actual TCP and OpenAI-compatible models endpoint without credentials")
	check((await scripts["providers"].new(node).probe_targets([], {"cancelled": true})).get("code") == "cancelled", "Discovery cancellation is explicit even for an empty address list")
	check(not scripts["integrations"].valid_repository("../outside") and not scripts["integrations"].valid_repository("user/project?token=x"), "GitHub repository scope rejects paths and query injection")
	var result = await service.github_request("fixture/project", {"resource": "repository"})
	check(result.get("result", {}).get("full_name") == "fixture/project", "Native GitHub HTTP adapter reads the configured repository")
	result = await service.github_request("fixture/project", {"resource": "contents", "path": "script.gd", "ref": "main"})
	check(result.get("result", {}).get("text") == "extends Node\n" and result["result"]["sha"] == "fixture-sha", "GitHub content decoding retains source text and revision")
	result = await service.github_request("fixture/project", {"resource": "contents", "path": "../outside"})
	check(result.get("code") == "invalid_path", "GitHub content reads reject parent traversal")
	result = await service.github_request("fixture/project", {"resource": "issues", "page": 2})
	check(result.get("result", []).size() == 1 and not result["result"][0].has("body"), "GitHub lists return bounded summarized entries")
	result = await service.github_request("fixture/project", {"title": "Fixture request", "body": "Test only"}, {}, true)
	check(result.get("result", {}).get("number") == 4, "Issue publication uses the configured endpoint and native POST against a fixture")
	check(scripts["workspace"].valid_id("scene-workflow") and not scripts["workspace"].valid_id("../secret") and not scripts["workspace"].valid_id("folder/name"), "Portable skill identifiers cannot escape their project directory")
	for definition in scripts["workspace"].definitions() + service.definitions(true, true):
		check(scripts["tool_registry"].new([definition]).error.is_empty(), "Integration/skill schema is supported: " + str(definition["name"]))
	if service.desktop_blender() and FileAccess.file_exists("/usr/bin/blender"):
		var scratch = OS.get_user_data_dir().path_join("blender-integration")
		DirAccess.make_dir_recursive_absolute(scratch)
		var target = scratch.path_join("probe.glb")
		var source = "res://ai_test_blender.py"
		var file = FileAccess.open(source, FileAccess.WRITE)
		file.store_string("import bpy\nbpy.ops.mesh.primitive_cube_add()\nbpy.ops.export_scene.gltf(filepath=" + JSON.stringify(target) + ", export_format='GLB')\nprint('GODOT_AI_BLENDER_PROBE')\n")
		file.close()
		result = await service.blender("/usr/bin/blender", {"script": source, "seconds": 45})
		check(result.get("ok", false) and "GODOT_AI_BLENDER_PROBE" in str(result.get("result", {}).get("output", "")) and scripts["assets"].validate_artifact(target, "mesh").get("ok", false), "Real Blender CLI executes project Python and produces a validated GLB")
		var document = GLTFDocument.new()
		var state = GLTFState.new()
		var parsed = document.append_from_file(target, state)
		var scene = document.generate_scene(state) if parsed == OK else null
		check(scene != null and scene.get_child_count() > 0, "Godot imports the GLB produced by the real Blender CLI")
		if scene != null: scene.free()
		file = FileAccess.open(source, FileAccess.WRITE)
		file.store_string("raise RuntimeError('GODOT_AI_EXPECTED_FAILURE')\n")
		file.close()
		result = await service.blender("/usr/bin/blender", {"script": source, "seconds": 15})
		check(result.get("code") == "blender_error" and "EXPECTED_FAILURE" in str(result.get("error", "")), "Blender Python errors propagate as failures instead of success")
		result = await service.blender("/usr/bin/blender", {"script": source}, {"cancelled": true})
		check(result.get("code") == "cancelled" and service.processes.is_empty(), "Cancelled Blender operations do not launch a process")
		file = FileAccess.open(source, FileAccess.WRITE)
		file.store_string("import time\ntime.sleep(6)\n")
		file.close()
		result = await service.blender("/usr/bin/blender", {"script": source, "seconds": 1})
		check(result.get("code") == "timeout" and service.processes.is_empty(), "Blender execution is bounded and terminates a timed-out child")
		DirAccess.remove_absolute(source)

func _planning_tests(node: Node) -> void:
	var planning = scripts["planner"]
	var questions = [{"id": "view", "title": "Ce perspectivă dorești?", "options": [{"id": "top", "label": "De sus"}, {"id": "side", "label": "Lateral"}]}, {"id": "features", "title": "Ce includem?", "multiple": true, "options": [{"id": "save", "label": "Salvare"}, {"id": "touch", "label": "Touch"}]}]
	var definition = planning.question_definition()
	var registry = scripts["tool_registry"].new([definition], true)
	check(definition.get("risk") == "read" and registry.loaded.has("plan_ask"), "Interactive clarification is available initially in the read-only catalog")
	check(scripts["tool_registry"].validate(definition, {"questions": questions}).get("ok", false), "Single and multiple questions validate through the provider tool schema")
	check(not scripts["tool_registry"].validate(definition, {"questions": []}).get("ok", true), "An empty questionnaire is rejected")
	var duplicated = questions.duplicate(true)
	duplicated[1]["id"] = "view"
	check(not planning.validate_questions({"questions": duplicated}).get("ok", true), "Duplicate question identifiers cannot overwrite an answer")
	duplicated = questions.duplicate(true)
	duplicated[0]["options"][1]["id"] = "top"
	check(not planning.validate_questions({"questions": duplicated}).get("ok", true), "Duplicate option identifiers are rejected before displaying the card")
	check(not planning.question_answers(questions, {}).get("ok", true) and planning.question_answers(questions, {}, false).get("ok", false), "An empty draft is allowed but cannot be submitted as user consent")
	var answers = {"view": {"selected": ["side"]}, "features": {"selected": ["touch", "save"], "text": "  Landscape  "}}
	var accepted = planning.question_answers(questions, answers)
	check(accepted.get("ok", false) and accepted["result"]["view"]["labels"] == ["Lateral"] and accepted["result"]["features"]["labels"] == ["Salvare", "Touch"] and accepted["result"]["features"]["text"] == "Landscape", "Submitted IDs resolve to actual option labels in stable question order, with trimmed custom text")
	answers["view"] = {"selected": ["top", "side"]}
	check(not planning.question_answers(questions, answers).get("ok", true), "Single-choice questions refuse multiple selections")
	answers["view"] = {"selected": [], "text": "Izometric"}
	check(planning.question_answers(questions, answers).get("ok", false), "A custom answer can replace every proposed option")
	answers["features"]["selected"] = ["save", "save"]
	check(not planning.question_answers(questions, answers).get("ok", true), "Multiple-choice answers refuse duplicated IDs")
	answers["features"]["selected"] = ["unknown"]
	check(not planning.question_answers(questions, answers).get("ok", true), "An invented option cannot become a confirmed user requirement")
	answers["features"]["selected"] = []
	answers["features"]["text"] = "x".repeat(2001)
	check(not planning.question_answers(questions, answers).get("ok", true), "Custom answers have a measured storage and context limit")
	check(not planning.question_answers(questions, {"foreign": {}}).get("ok", true), "Foreign question keys cannot be silently accepted")
	var plan = scripts["planner"].new()
	plan.reset("plan-test")
	check(plan.can_write() and not plan.needs_continuation(), "Planner starts idle; the host enforces the selected mode policy")
	var steps = [{"step": "Inspect", "status": "in_progress"}, {"step": "Verify", "status": "pending"}]
	check(scripts["tool_registry"].validate(scripts["planner"].definition(), {"tasks": steps, "phase": "planning"}).get("ok", false), "Structured plans use the common tool schema validator")
	check(plan.update({"tasks": steps, "phase": "planning"}).get("ok", false) and not plan.can_write() and plan.needs_continuation(), "Auto planning is inspect-only and remains an unfinished task")
	plan.update({"tasks": steps, "phase": "executing"})
	check(plan.can_write() and plan.needs_continuation(), "Explicit execution phase permits Auto to apply the plan")
	check(not plan.update({"tasks": steps, "phase": "completed"}).get("ok", true) and plan.phase == "executing", "A plan cannot finish with pending steps and failed updates are atomic")
	check(not plan.update({"tasks": [{"step": "A", "status": "in_progress"}, {"step": "B", "status": "in_progress"}]}).get("ok", true), "Only one plan step can be in progress")
	plan.update({"tasks": steps, "phase": "blocked", "explanation": "Need project input"})
	check(not plan.can_write() and not plan.needs_continuation(), "A blocked plan stops automatic continuation and writes")
	plan.update({"tasks": steps, "phase": "executing"})
	plan.pause()
	check(plan.phase == "paused" and plan.steps[1]["status"] == "pending", "Stopping a plan does not mark unfinished steps completed")
	var saved = plan.snapshot()
	var resumed_plan = scripts["planner"].new()
	check(resumed_plan.restore(saved, true).get("ok", false) and resumed_plan.turn == "plan-test" and resumed_plan.phase == "planning" and not resumed_plan.can_write(), "Resuming restores unfinished steps and requires an explicit execution phase before writes")
	check(not resumed_plan.restore({"phase": "unexpected"}).get("ok", false) and resumed_plan.turn == "plan-test", "An invalid saved plan cannot overwrite the restored task")
	plan.reset("proposal", true)
	check(not plan.update({"tasks": steps, "phase": "executing"}, true).get("ok", true), "Manual Plan cannot switch itself into execution")
	check(plan.update({"tasks": steps, "phase": "completed"}, true).get("ok", false) and not plan.can_write() and not plan.needs_continuation(), "A completed proposal retains pending implementation steps without executing them")
	plan.reset()
	check(plan.update({"tasks": ["Legacy checklist"]}).get("ok", false) and plan.steps[0]["status"] == "pending", "Legacy checklist strings remain readable without inventing completed steps")
	var rich = RichTextLabel.new()
	node.add_child(rich)
	scripts["markdown"].render(rich, "## Titlu\n\n**Bold** și `cod`\n- Element\n> Citat\n[b]literal[/b]\n[x](javascript:alert(1))")
	var rendered = rich.get_parsed_text()
	check("Titlu" in rendered and "•  Element" in rendered and not "**Bold**" in rendered and "[b]literal[/b]" in rendered and "javascript:alert" in rendered, "Markdown formats text while keeping BBCode, HTML and unsupported links literal")
	scripts["markdown"].render(rich, "| Nume | Valoare |\n| --- | --- |\n| Nod | 12 |")
	check("Nume" in rich.get_parsed_text() and "12" in rich.get_parsed_text() and not "---" in rich.get_parsed_text(), "Markdown tables render as structured native cells")
	var markdown = scripts["markdown"]
	var pieces = markdown.blocks("Introducere.\n\n```gdscript\nvar marker = \"```\"\n```\n\nRezultat.")
	check(pieces.size() == 3 and pieces[1]["text"] == "var marker = \"```\"" and pieces[1]["complete"], "Fenced code retains literal inline backticks")
	check(markdown.blocks("Text\n\n``", true).size() == 1 and markdown.blocks("```gds", true).is_empty(), "Partial opening fences and language tags do not flash as streamed message text")
	pieces = markdown.blocks("```gdscript\nprint(1)\n``", true)
	check(pieces.size() == 1 and pieces[0]["text"] == "print(1)", "A partial closing fence never leaks into the streamed source")
	pieces = markdown.blocks("~~~python\nprint(1)\n~~~")
	check(pieces.size() == 1 and pieces[0]["language"] == "python" and pieces[0]["complete"], "Tilde code fences render as a complete code block")
	pieces = markdown.blocks("Unu.\n\nDoi.\n\nTrei.")
	check(pieces.size() == 3 and pieces[0]["text"] == "Unu.", "Separate paragraphs allow incremental rendering without changing earlier widgets")
	markdown.render(rich, "## Titlu\nConținut")
	check(rich.get_parsed_text() == "Titlu\nConținut", "Heading rendering avoids adding extra blank lines beyond the source")
	var common = scripts["common"]
	check(common.project_link("res://scripts/player.gd:42:7") == {"path": "res://scripts/player.gd", "line": 42, "column": 7}, "Project chat links preserve one-based line and column")
	check(common.project_link("res://scripts/player.gd#L19").get("line") == 19, "Project links accept the documented line fragment syntax")
	for invalid in ["file:///data/private", "res://../escape.gd:2", "res://.godot/cache:1", "res://a.gd:0", "res://a.gd:1000001", "res://a.gd?execute=yes", "res://a.gd\n"]:
		check(common.project_link(invalid).is_empty(), "Invalid project navigation is rejected: " + invalid.strip_edges())
	markdown.render(rich, "[Player](res://scripts/player.gd:42) și `res://scripts/player.gd#L19` și res://scripts/player.gd:3.")
	check(rich.get_parsed_text() == "Player și res://scripts/player.gd#L19 și res://scripts/player.gd:3.", "Project links retain readable labels, inline code and sentence punctuation")
	var preview_script = scripts["tool_preview"]
	var redact = func(value: String) -> String: return common.redact(value, ["fixture-private-token"])
	var preview = preview_script.build("godot_read_file", {"path": "res://player.gd"}, common.success("var x = 1\n# fixture-private-token"), redact)
	check(preview.get("kind") == "read" and preview["items"][0]["rows"][1]["line"] == 2 and not JSON.stringify(preview).contains("fixture-private-token"), "Read cards preserve original line numbers and redact saved credentials")
	preview = preview_script.build("godot_read_file", {"path": "res://player.gd"}, common.success("x".repeat(11990) + "fixture-private-token" + "tail"), redact)
	check(not JSON.stringify(preview).contains("fixture-private") and preview.get("partial", false), "A secret crossing a preview budget boundary cannot leak its prefix")
	preview = preview_script.build("godot_read_file", {"path": "res://player.gd"}, common.success("row\n".repeat(300)), redact)
	check(preview["items"][0]["rows"].size() == 100 and preview["partial"], "Read snapshots have an explicit row limit and partial marker")
	preview = preview_script.build("godot_read_range", {}, common.success({"path": "res://player.gd", "lines": [{"line": 73, "text": "pass"}], "next_line": 74}), redact)
	check(preview["items"][0]["line"] == 73 and preview["partial"], "Range previews retain nonzero source offsets and report unread remainder")
	check(preview_script.build("godot_read_file", {"path": "res://player.gd"}, common.failure("denied"), redact).is_empty(), "Failed reads never present invented source snapshots")
	check(preview_script.build("godot_read_file", {"path": "res://../outside"}, common.success("private"), redact).is_empty(), "Tool preview paths use the same project boundary as navigation")
	var hits = []
	for index in range(20): hits.append({"path": "res://player.gd", "line": index + 4, "text": "func start():", "before": [{"line": index + 3, "text": "# context"}], "after": [{"line": index + 5, "text": "pass"}]})
	preview = preview_script.build("godot_search_code", {"query": "start"}, common.success({"matches": hits}), redact)
	check(preview["items"].size() == 12 and preview["partial"] and preview["items"][0]["rows"][0]["line"] == 3, "Search cards retain numbered context and bound the number of displayed hits")
	check(preview_script.build("godot_search_code", {}, common.success({"matches": []}), redact).get("kind") == "search", "An empty search is represented explicitly")
	var diagram = scripts["diagram"]
	var graph = diagram.parse('flowchart TD; A["Intrare; joc"] --> B{Atac?}; B -->|Da| C((Luptă)); B -.->|Nu| D([Patrulare]); C --> A')
	check(graph.get("ok", false) and graph["nodes"].size() == 4 and graph["edges"].size() == 4 and graph["nodes"]["A"]["label"] == "Intrare; joc", "Native flowchart parsing preserves quoted labels, decisions, branching, chains and cycles")
	graph = diagram.parse('stateDiagram-v2\ndirection LR\nstate "În repaus" as Idle\n[*] --> Idle\nIdle --> Move: mișcare\nMove --> Idle: stop\nMove --> [*]')
	check(graph.get("ok", false) and graph["nodes"].size() == 4 and graph["direction"] == "LR" and graph["nodes"]["Idle"]["label"] == "În repaus", "Flat state diagrams support aliases, transitions and distinct start/stop markers")
	for invalid in ['sequenceDiagram\nA->>B: hello', 'flowchart TD\nA[broken', 'flowchart TD\nclick A "https://example.org"', 'flowchart TD\nsubgraph Group\nA --> B\nend', '%%{init: {}}%%\nflowchart TD\nA', 'flowchart TD\n' + 'A --> A\n'.repeat(81), 'flowchart TD\n' + 'x'.repeat(16000)]:
		check(not diagram.parse(invalid).get("ok", false), "Unsupported, malformed or excessive diagrams fall back to their source")
	check(diagram.parse("graph LR; A-->B-->C").get("edges", []).size() == 2, "Compact chained arrows do not become part of node identifiers")
	var many = "flowchart TD\n"
	for index in range(41): many += "N%d\n" % index
	check(not diagram.parse(many).get("ok", false), "Native diagram node count is bounded")

	rich.queue_free()

func _tool_registry_tests() -> void:
	var registry_script = scripts["tool_registry"]
	var tools = scripts["editor_tools"].new()
	var first_page: Dictionary = tools._describe({"class": "Node", "limit": 3, "offset": 0}).get("result", {})
	var second_page: Dictionary = tools._describe({"class": "Node", "limit": 3, "offset": 3}).get("result", {})
	check(first_page.get("methods", []).size() == 3 and first_page.get("next_offset", -1) == 3 and first_page.get("total", {}).get("methods", 0) > 3, "Reflection exposes a bounded page with its actual total and continuation")
	check(second_page.get("methods", []).size() == 3 and first_page["methods"][0]["name"] != second_page["methods"][0]["name"], "Reflection pagination advances rather than repeating the same methods")
	var alternatives: Dictionary = tools._describe({"class": "Node", "filter": "set_process|is_processing", "limit": 50}).get("result", {})
	check(alternatives.get("methods", []).any(func(item: Dictionary) -> bool: return item["name"] == "set_process") and alternatives.get("methods", []).any(func(item: Dictionary) -> bool: return item["name"] == "is_processing"), "Reflection accepts documented alternative name filters")
	var classes: Dictionary = tools._describe({"filter": "Mesh", "limit": 4}).get("result", {})
	check(classes.get("classes", []).size() == 4 and classes.get("next_offset", -1) == 4, "Class discovery is paged instead of filling context with the full catalog")
	var reflection = tools._describe({"class": "Node"})
	var unpaged = scripts["common"].success({"methods": ClassDB.class_get_method_list("Node"), "properties": ClassDB.class_get_property_list("Node"), "signals": ClassDB.class_get_signal_list("Node")})
	var paged_size = JSON.stringify(scripts["common"].json_safe(reflection)).length()
	var unpaged_size = JSON.stringify(scripts["common"].json_safe(unpaged)).length()
	check(paged_size < 24000 and paged_size < unpaged_size, "Default reflection pages expose real signatures within the model result budget")
	var method_names = []
	var next_offset = 0
	while next_offset >= 0:
		var page: Dictionary = tools._describe({"class": "Node", "offset": next_offset, "limit": 50}).get("result", {})
		for method in page.get("methods", []): method_names.append(method["name"])
		next_offset = int(page.get("next_offset", -1))
	check(method_names.size() == reflection["result"]["total"]["methods"] and method_names.count("get_node") == 1, "Following reflection pages covers the full catalog without repeating an inherited method")
	var exhausted: Dictionary = tools._describe({"class": "Node", "offset": 100000}).get("result", {})
	check(exhausted.get("methods", []).is_empty() and exhausted.get("next_offset", 0) == -1 and exhausted.get("total") == reflection["result"]["total"], "An exhausted reflection page reports its real total without restarting pagination")
	print("AI_REFLECTION_METRICS ", JSON.stringify({"class": "Node", "unpaged_characters": unpaged_size, "default_page_characters": paged_size, "total": reflection["result"]["total"]}))
	var registry = registry_script.new(tools.definitions(), true)
	var names = registry.active_definitions().map(func(item: Dictionary) -> String: return item["name"])
	check("tool_search" in names and "godot_read_range" in names and not "godot_apply_patch" in names, "Deferred registry starts with discovery and a small inspection set")
	var found = registry.discover("tool_search", {"query": "godot_apply_patch", "limit": 1})
	check(found.get("result", {}).get("tools", [{}])[0].get("name") == "godot_apply_patch" and registry.loaded.has("godot_apply_patch"), "Search returns the exact schema and activates a specialized tool")
	var reads = tools.definitions().filter(func(item: Dictionary) -> bool: return item["risk"] == "read")
	var read_registry = registry_script.new(reads, true)
	check(not read_registry.discover("tool_describe", {"name": "godot_apply_patch"}).get("ok", false), "Discovery cannot expose a tool excluded by the session mode")
	check(not registry_script.new([reads[0], reads[0]]).error.is_empty(), "Duplicate tool definitions are rejected")
	var schema = {"parameters": {"type": "object", "properties": {"items": {"type": "array", "items": {"$ref": "#/$defs/item"}, "minItems": 1}}, "$defs": {"item": {"type": "object", "properties": {"count": {"type": "integer", "minimum": 1}, "name": {"type": "string", "enum": ["allowed"]}}, "required": ["count", "name"], "additionalProperties": false}}, "required": ["items"], "additionalProperties": false}}
	check(registry_script.validate(schema, {"items": [{"count": 2.0, "name": "allowed"}]}).get("ok", false), "Nested schemas and local references accept integral JSON numbers")
	for invalid in [{"items": [{"count": 1.5, "name": "allowed"}]}, {"items": [{"count": 0, "name": "allowed"}]}, {"items": [{"count": 1, "name": "other"}]}, {"items": [{"count": 1, "name": "allowed", "extra": true}]}, {"items": []}, {}]:
		check(not registry_script.validate(schema, invalid).get("ok", false), "Reject invalid nested tool arguments: " + JSON.stringify(invalid))
	check(registry_script.validate({"parameters": {"not": {"if": {}}}}, {}).get("code") == "unsupported_schema", "Unsupported constraints cannot be hidden inside schema negation")
	check(registry_script.validate({"parameters": {"not": {"$ref": "https://example.test/schema"}}}, {}).get("code") == "unsupported_schema", "External schema references fail explicitly without fetching anything")
	check(not tools.validate("godot_restore_file", {"index": 1.5}).get("ok", false), "All native tool calls reject fractional integer arguments")
	var source = "extends Node\r\nvar value = 1 # română 🐦\r\n"
	var patch = scripts["editor_tools"].prepare_patch(source, [{"old_text": "value = 1", "new_text": "value = 2"}])
	check(patch.get("ok", false) and patch["result"]["text"] == source.replace("value = 1", "value = 2") and patch["result"]["changes"][0]["line"] == 2, "Exact patches preserve UTF-8 and CRLF and report line numbers")
	check(not scripts["editor_tools"].prepare_patch("aaa", [{"old_text": "aa", "new_text": "b"}]).get("ok", false), "Overlapping repeated patch anchors are ambiguous")
	check(not scripts["editor_tools"].prepare_patch(source, [{"old_text": "value = 1", "new_text": "value = 2"}, {"old_text": "missing", "new_text": "x"}]).get("ok", false), "A later invalid edit rejects the entire patch before writing")
	var mcp = scripts["mcp"]
	var error = mcp.normalize_result({"isError": true, "content": [{"type": "text", "text": "Fixture execution failed"}]})
	check(not error.get("ok", true) and error.get("code") == "mcp_tool_error", "MCP isError is an execution failure rather than a successful RPC")
	check(mcp.normalize_result({"isError": true, "content": [{"type": "text", "text": "Bad input"}]}, {"type": "object", "required": ["answer"]}).get("code") == "mcp_tool_error", "MCP execution failures do not need the success output schema")
	var image = Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	var encoded = Marshalls.raw_to_base64(image.save_png_to_buffer())
	var result = mcp.normalize_result({"content": [{"type": "text", "text": "Fixture frame"}, {"type": "image", "mimeType": "image/png", "data": encoded}], "structuredContent": {"count": 2}}, {"type": "object", "properties": {"count": {"type": "integer"}}, "required": ["count"]})
	check(result.get("ok", false) and result.get("images", []).size() == 1 and not "data" in result["result"]["content"][1] and result["result"]["structuredContent"]["count"] == 2, "MCP preserves structured data and separates validated image attachments")
	check(not mcp.normalize_result({"content": [], "structuredContent": {"count": "bad"}}, {"type": "object", "properties": {"count": {"type": "integer"}}}).get("ok", false), "MCP output schemas reject mismatched structured results")
	check(mcp.normalize_result({"content": [{"type": "audio"}]}).get("code") == "unsupported_mcp_content", "Unsupported MCP content is reported explicitly")
	var symbol_dir = "res://ai_test_symbols"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(symbol_dir))
	var probe_source = "class_name SymbolProbe\nextends Node\n\nsignal finished(count: int)\n\nconst LIMIT = 4\n\nenum Mode { OFF, ON }\n\n@export var speed: float = 1.0\n\nvar plain = 0\n\nfunc run(value: int) -> int:\n\tvar local = 1\n\treturn value + local\n\nstatic func helper() -> void:\n\tpass\n"
	var probe_path = symbol_dir.path_join("probe.gd")
	var probe = FileAccess.open(probe_path, FileAccess.WRITE)
	probe.store_string(probe_source)
	probe.close()
	var other_path = symbol_dir.path_join("other.gd")
	var other = FileAccess.open(other_path, FileAccess.WRITE)
	other.store_string("extends Node\n\nfunc run_other() -> void:\n\tpass\n")
	other.close()
	var mapped = tools._symbols({"path": symbol_dir})
	var symbols: Array = mapped.get("result", {}).get("symbols", [])
	var by_name = {}
	for symbol in symbols: by_name[symbol["name"]] = symbol
	check(mapped.get("ok", false) and by_name.size() == 9 and not by_name.has("local") and by_name["speed"]["kind"] == "export" and by_name["plain"]["kind"] == "var", "Symbol map lists top-level declarations and ignores locals")
	check(by_name["SymbolProbe"]["kind"] == "class" and by_name["SymbolProbe"]["line"] == 1 and by_name["finished"]["kind"] == "signal" and by_name["LIMIT"]["kind"] == "constant" and by_name["Mode"]["kind"] == "enum" and by_name["helper"]["kind"] == "function", "Symbol map classifies classes, signals, constants, enums and static functions")
	check(by_name["run"]["path"] == probe_path and by_name["run_other"]["path"] == other_path and by_name["run"]["line"] == 14, "Symbols carry project paths and one-based lines across a directory")
	var literal_lines = ["extends Node", "# A comment with \"\"\" and '''", "var help = \"\"\"", "func phantom():", "signal ghost", "\\\"\"\"", "const ALSO_FAKE = 1", "\"\"\" # ''' in a comment", "var more = '''", "class FalseClass:", "'''", "@export_range(0, 4) # \"\"\"", "var actual: int = 1 # signal wrong", "func real():", "\tvar embedded = \"\"\"", "func fake_body():", "\t\"\"\"", "\tpass", "static func last():", "\tpass"]
	var literal_symbols = tools._scan_symbols("res://literal.gd", "\n".join(literal_lines))
	check(literal_symbols.map(func(item: Dictionary) -> String: return item["name"]) == ["help", "more", "actual", "real", "last"], "Symbol scanning ignores both multiline quote styles, escaped delimiters and indented literal content")
	check(literal_symbols[2]["kind"] == "export" and literal_symbols[2]["line"] == 13 and literal_symbols[-1]["line"] == 19, "Masked strings and comments preserve annotations and real declaration line numbers")
	var annotated = tools._scan_symbols("res://annotated.gd", "@export_enum(\"var fake\", \"func false():\")\nvar choice = 0\nvar escaped = \"quote \\\" # still a string\" # '''\nsignal actual_signal # comment\n")
	check(annotated.map(func(item: Dictionary) -> String: return item["name"]) == ["choice", "escaped", "actual_signal"] and annotated[0]["kind"] == "export", "Quoted annotation arguments and escaped single-line quotes cannot inject symbols or open a false multiline literal")
	var functions = tools._symbols({"path": symbol_dir, "kind": "function"}).get("result", {}).get("symbols", [])
	check(functions.size() == 3 and functions.all(func(item: Dictionary) -> bool: return item["kind"] == "function"), "Symbol map filters by declaration kind")
	var filtered = tools._symbols({"path": symbol_dir, "query": "spe"}).get("result", {}).get("symbols", [])
	check(filtered.size() == 1 and filtered[0]["name"] == "speed", "Symbol map filters by case-insensitive name substring")
	var bounded = tools._symbols({"path": symbol_dir, "limit": 2}).get("result", {})
	check(bounded.get("symbols", []).size() == 2 and bounded.get("truncated", false), "Symbol map honors its result limit and reports truncation")
	var cached = tools.symbol_cache.get(probe_path, {})
	check(str(cached.get("sha256", "")) == probe_source.sha256_text(), "Symbol map caches parsed symbols by content hash")
	probe = FileAccess.open(probe_path, FileAccess.WRITE)
	probe.store_string("extends Node\n\nfunc replaced() -> void:\n\tpass\n")
	probe.close()
	var rescanned = tools._symbols({"path": symbol_dir, "query": "replaced"}).get("result", {}).get("symbols", [])
	check(rescanned.size() == 1 and tools._symbols({"path": symbol_dir, "query": "SymbolProbe"}).get("result", {}).get("symbols", []).is_empty(), "Edited files invalidate their cached symbol entries")
	var cleanup = DirAccess.open(symbol_dir)
	if cleanup != null:
		for filename in cleanup.get_files(): cleanup.remove(filename)
	DirAccess.remove_absolute(symbol_dir)
	var search_dir = "res://ai_test_search"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(search_dir))
	var first = FileAccess.open(search_dir.path_join("one.gd"), FileAccess.WRITE)
	first.store_string("alpha\nneedle first\nbeta\n")
	first.close()
	var second = FileAccess.open(search_dir.path_join("two.gd"), FileAccess.WRITE)
	second.store_string("needle second\ngamma\n")
	second.close()
	var third = FileAccess.open(search_dir.path_join("three.gd"), FileAccess.WRITE)
	third.store_string("needle one\nneedle two\n")
	third.close()
	var contextual: Dictionary = tools._search_code({"path": search_dir, "query": "needle", "context": 1}).get("result", {})
	var by_path = {}
	for match in contextual.get("matches", []): by_path[match["path"]] = match
	check(contextual.get("matches", []).size() == 4 and by_path[search_dir.path_join("one.gd")].get("before", []) == [{"line": 1, "text": "alpha"}] and by_path[search_dir.path_join("one.gd")].get("after", []) == [{"line": 3, "text": "beta"}], "Search context returns the surrounding source lines of a match")
	check(not by_path[search_dir.path_join("two.gd")].has("before") and by_path[search_dir.path_join("two.gd")].get("after", []) == [{"line": 2, "text": "gamma"}], "Search context omits lines outside the file instead of inventing them")
	var adjacent: Array = contextual.get("matches", []).filter(func(item: Dictionary) -> bool: return item["path"] == search_dir.path_join("three.gd"))
	check(adjacent.size() == 2 and adjacent[0].has("after") and not adjacent[1].has("before"), "Adjacent matches do not repeat context lines already shown")
	var plain_search: Array = tools._search_code({"path": search_dir, "query": "needle"}).get("result", {}).get("matches", [])
	check(plain_search.size() == 4 and plain_search.all(func(item: Dictionary) -> bool: return not item.has("before") and not item.has("after")), "Search without context keeps the previous compact match shape")
	var search_cleanup = DirAccess.open(search_dir)
	if search_cleanup != null:
		for filename in search_cleanup.get_files(): search_cleanup.remove(filename)
	DirAccess.remove_absolute(search_dir)
	var bridge = SyntaxBridge.new()
	tools.plugin = bridge
	var clean_syntax: Dictionary = tools._syntax_check("extends Node\nvar value = 1\n", "res://clean.gd")
	var broken_syntax: Dictionary = tools._syntax_check("extends Node\nbroken func\n", "res://broken.gd")
	check(clean_syntax.get("valid", false) and clean_syntax.get("errors", []).is_empty() and clean_syntax.get("truncated", true) == false, "Automatic syntax checks treat a valid script without errors as valid and ignore warnings")
	check(broken_syntax.get("valid", true) == false and broken_syntax.get("errors", []).size() == 20 and broken_syntax["errors"][0]["line"] == 2 and broken_syntax.get("truncated", false), "Automatic syntax checks keep bounded line-level parse errors and report truncation")
	check(tools._syntax_check("extends Node\n", "res://note.txt").is_empty(), "Automatic syntax checks skip files that are not GDScript")
	tools.plugin = null
	bridge.free()

func _recovery_tests(node: Node) -> void:
	var core = scripts["harness"].new(node)
	var host = HarnessHost.new()
	var definition = scripts["common"].tool("godot_files", "Fixture project inspection", {}, [])
	var events = []
	core.event.connect(func(value: Dictionary) -> void: events.append(value))
	for index in range(3): host.replies.append(_agent_response("", [{"id": "repeat-" + str(index), "name": "godot_files", "arguments": {}}]))
	host.tool_result = {"ok": true, "result": ["res://world.tscn"]}
	host.replies.append(_agent_response("Changed the investigation strategy"))
	var history = []
	var outcome = await core.run({"tools": [definition], "messages": history}, host.hooks())
	check(outcome.get("ok", false) and events.any(func(item: Dictionary) -> bool: return item.get("kind") == "recovery"), "Repeated successful inspections trigger a change-of-strategy recovery event")
	check(host.contexts[3].any(func(message: Dictionary) -> bool: return message.get("role") == "system" and "same inspection" in str(message.get("content", ""))) and not history.any(func(message: Dictionary) -> bool: return "same inspection" in str(message.get("content", ""))), "Recovery instructions reach the next model request without becoming persisted user messages")
	host = HarnessHost.new()
	host.tool_result = {"ok": true, "result": ["res://world.tscn"]}
	for index in range(6): host.replies.append(_agent_response("", [{"id": "stuck-" + str(index), "name": "godot_files", "arguments": {}}]))
	outcome = await core.run({"tools": [definition]}, host.hooks())
	check(outcome.get("code") == "no_progress" and host.executed.size() == 6, "Ignoring recovery and repeatedly reading unchanged facts settles without a global step ceiling")
	var patch = core._recovery_guidance("godot_apply_patch", {"ok": false, "code": "patch_conflict"})
	var paid = core._recovery_guidance("asset_generate", {"ok": false, "code": "submission_unknown"})
	check(patch.get("category") == "version_conflict" and "godot_read_range" in patch.get("next", []) and not patch.get("retry_tool_automatically", true), "Conflicted writes require fresh source/hash and never automatic retries")
	check(paid.get("category") == "uncertain_side_effect" and "asset_status" in paid.get("next", []), "Uncertain paid submissions are routed to the existing job instead of regeneration")
	check(core._recovery_guidance("godot_write_file", {"ok": false, "code": "permission_denied"}).get("category") == "user_boundary", "Permission refusals remain a boundary rather than a repair to bypass")
	check(core._recovery_guidance("godot_write_file", {"ok": true, "result": {"syntax": {"valid": false}}}).get("category") == "syntax", "A successful write with parser errors still supplies a syntax-repair strategy")
	host = HarnessHost.new()
	host.replies = [_agent_response("Done"), _agent_response("Done"), _agent_response("Done")]
	var hooks = host.hooks()
	hooks["completion_problem"] = func() -> String: return "Missing measured evidence"
	outcome = await core.run({}, hooks)
	check(outcome.get("status") == "blocked" and outcome.get("code") == "verification_required" and host.contexts.size() == 3, "Tool-free completion claims cannot bypass the host's acceptance-evidence gate")
	check(host.contexts[1].any(func(message: Dictionary) -> bool: return "Missing measured evidence" in str(message.get("content", ""))), "The completion gate asks for the concrete missing verification before settling blocked")

func _context_budget_tests(node: Node) -> void:
	var script = scripts["harness"]
	var paid = scripts["common"].tool("asset_fixture", "Paid generation", {"prompt": {"type": "string"}}, ["prompt"], "external")
	var poll = scripts["common"].tool("poll_fixture", "Read current job status", {}, [])
	var paid_call = {"id": "paid-original", "name": "asset_fixture", "arguments": {"prompt": "one tree"}}
	var poll_call = {"id": "poll", "name": "poll_fixture", "arguments": {}}
	var artifact = {"ok": true, "files": ["tree-file"], "result": {"id": "existing-job", "external_id": "provider-job", "status": "completed", "file": "/generated/tree.glb", "imported_path": "res://trees/tree.glb", "quality": {"ready_for_use": true}, "output": "Old detailed output. 🌲 ".repeat(2000)}}
	var history = [{"role": "system", "content": "Keep res://original.tscn. The plan and evidence are authoritative."}, {"role": "user", "content": "Build the forest; generate one tree only."}, {"role": "assistant", "content": "Generate once, then reuse it.", "tool_calls": [paid_call], "turn_id": "context-turn"}, {"role": "tool", "tool_call_id": "paid-original", "tool_name": "asset_fixture", "content": JSON.stringify(artifact), "execution_started": true}, {"role": "assistant", "content": "Inspect current state", "tool_calls": [poll_call]}, {"role": "tool", "tool_call_id": "poll", "tool_name": "poll_fixture", "content": JSON.stringify({"ok": true, "result": "Latest status. ".repeat(3000)})}]
	var original = history.duplicate(true)
	var prepared = script.prepare_context(history, [paid, poll], 8192)
	check(prepared["trimmed"] == 1 and prepared["saved_bytes"] > 30000 and history == original, "Context budgeting reduces old tool output without changing the full transcript")
	check(prepared["messages"].size() == history.size() and prepared["messages"][0] == history[0] and prepared["messages"][1] == history[1] and prepared["messages"][2] == history[2], "Pruning preserves the original user task, system constraints, assistant plan and tool-call identities")
	check(prepared["messages"][4] == history[4] and prepared["messages"][5] == history[5], "The latest assistant/tool batch remains verbatim for the next decision")
	var compact: Dictionary = JSON.parse_string(prepared["messages"][3]["content"])
	check(compact.get("ok", false) and compact.get("truncated", false) and compact.get("files") == ["tree-file"] and compact.get("result", {}).get("id") == "existing-job" and compact["result"].get("status") == "completed", "A pruned paid result retains success, file cards and the existing job identity")
	check(compact["result"].get("external_id") == "provider-job" and compact["result"].get("imported_path") == "res://trees/tree.glb" and compact["result"].get("quality", {}).get("ready_for_use", false), "Pruning retains provider IDs, imported paths and measured asset quality")
	check(script.prepare_context(history, [], 1048576)["trimmed"] == 0 and script.prepare_context(history, [], 0)["trimmed"] == 0, "A sufficiently large or unknown context window leaves tool details intact")
	var large_schema = paid.duplicate(true)
	large_schema["description"] = "Schema metadata. ".repeat(3000)
	check(script.prepare_context(history, [large_schema], 32768)["trimmed"] == 1, "The context estimate includes active tool schemas rather than messages alone")
	var malformed = history.duplicate(true)
	malformed[3]["content"] = "not JSON ".repeat(2000)
	check(script.prepare_context(malformed, [], 8192)["trimmed"] == 0, "Unknown tool-result formats are preserved instead of being recast as success")
	var core = script.new(node)
	var events = []
	core.event.connect(func(value: Dictionary) -> void: events.append(value))
	var host = HarnessHost.new()
	var repeated_paid = paid_call.duplicate(true)
	repeated_paid["id"] = "paid-new-id"
	host.replies = [{"ok": false, "status": 400, "code": "context_length_exceeded", "error": "Prompt is too long"}, _agent_response("", [repeated_paid]), _agent_response("Recovered existing result")]
	var resumed = history.duplicate(true)
	var outcome = await core.run({"tools": [paid, poll], "messages": resumed, "metadata": {"turn_id": "context-turn"}, "deduplicate_tools": ["asset_fixture"], "max_retries": 0}, host.hooks())
	check(outcome.get("ok", false) and outcome.get("context_recoveries") == 1 and outcome.get("requests") == 3 and outcome.get("retries") == 0, "A rejected oversized prompt recovers once without consuming the connection-retry budget")
	check(host.executed.is_empty() and outcome.get("reused_calls") == 1 and resumed.slice(0, original.size()) == original, "Context recovery preserves the side-effect ledger and never regenerates an existing paid job")
	check(host.contexts[0][3] == original[3] and str(host.contexts[1][3]["content"]).length() <= 2048 and events.any(func(value: Dictionary) -> bool: return value.get("kind") == "context_pruned" and value.get("reason") == "provider_overflow"), "The retried request uses the reduced view and emits a payload-free recovery event")
	for failure in [{"ok": false, "status": 400, "error": "maximum context length"}, {"ok": false, "status": 401, "error": "Invalid credentials"}, {"ok": false, "code": "context_length_exceeded", "error": "Too many tokens", "_delta": "Visible partial answer"}]:
		host = HarnessHost.new()
		host.replies = [failure, failure]
		outcome = await core.run({"tools": [paid, poll], "messages": history.duplicate(true), "max_retries": 0}, host.hooks())
		var expected = 2 if failure.get("status") == 400 else 1
		check(not outcome.get("ok", true) and host.contexts.size() == expected, "Context recovery is bounded and never retries authentication or visible partial output: " + str(failure.get("status", "stream")))
	host = HarnessHost.new()
	host.replies = [{"ok": false, "code": "context_length_exceeded", "error": "Too many tokens"}]
	outcome = await core.run({"tools": [poll], "messages": history.slice(4).duplicate(true)}, host.hooks())
	check(host.contexts.size() == 1 and outcome.get("context_recoveries") == 0, "Overflow with no safely reducible old batch fails without an identical retry")
	host = HarnessHost.new()
	host.token = {"cancelled": false}
	host.replies = [{"ok": false, "code": "context_length_exceeded", "error": "Too many tokens"}]
	var stopping = host.token
	var stop_recovery = func(value: Dictionary) -> void:
		if value.get("kind") == "context_pruned": stopping["cancelled"] = true
	core.event.connect(stop_recovery)
	outcome = await core.run({"tools": [paid, poll], "messages": history.duplicate(true), "cancel": stopping}, host.hooks())
	core.event.disconnect(stop_recovery)
	check(outcome.get("status") == "cancelled" and host.contexts.size() == 1, "Stop during context recovery prevents another provider request")
	host = HarnessHost.new()
	host.replies = [_agent_response("", [poll_call]), _agent_response("Fresh status verified")]
	host.tool_result = {"ok": true, "result": {"status": "completed"}}
	var reads = history.slice(4).duplicate(true)
	outcome = await core.run({"tools": [poll], "messages": reads}, host.hooks())
	check(outcome.get("ok", false) and host.executed.size() == 1 and JSON.parse_string(reads[-2]["content"])["result"]["status"] == "completed", "Reused provider IDs cannot return stale cached status from a read-only tool")
	var write = scripts["common"].tool("write_fixture", "Repair", {}, [], "write")
	host = HarnessHost.new()
	for index in range(6):
		host.replies.append(_agent_response("", [{"id": "failed-%d" % index, "name": "write_fixture", "arguments": {}}, {"id": "read-%d" % index, "name": "poll_fixture", "arguments": {}}]))
		host.tool_results.append_array([{"ok": false, "code": "invalid_method", "error": "Same unavailable method"}, {"ok": true, "result": {"status": "unchanged"}}])
	events.clear()
	outcome = await core.run({"tools": [write, poll]}, host.hooks())
	check(outcome.get("code") == "no_progress" and host.contexts.size() == 6, "Unrelated successful reads cannot mask endless retries of the same failed operation")
	check(events.any(func(value: Dictionary) -> bool: return value.get("kind") == "recovery" and value.get("reason") == "repeated_failure" and value.get("count") == 3), "Interleaved failures receive a change-of-strategy hint before settling")

func _workflow_tests(node: Node) -> void:
	var core = scripts["harness"].new(node)
	var definition = scripts["common"].tool("paid_fixture", "One paid operation", {}, [], "external")
	var a = {"id": "old-a", "name": "paid_fixture", "arguments": {}}
	var b = {"id": "old-b", "name": "paid_fixture", "arguments": {}}
	var incoming = []
	var messages = [{"role": "user", "content": "Build one tree", "turn_id": "workflow"}]
	var host = HarnessHost.new()
	var hooks = host.hooks()
	hooks["steering_pending"] = func() -> bool: return not incoming.is_empty()
	hooks["steering"] = func() -> Array:
		var result = incoming.duplicate(true)
		incoming.clear()
		return result
	hooks["complete"] = func(context: Array, catalog: Array, stopping: Dictionary, delta: Callable) -> Dictionary:
		if host.contexts.is_empty():
			incoming.append({"content": "Inspect only; no generation. fixture-secret", "files": ["reference"], "references": ["res://original.gd"]})
		return await host.complete(context, catalog, stopping, delta)
	host.replies = [_agent_response("", [a, b]), _agent_response("Adjusted task verified")]
	var outcome = await core.run({"messages": messages, "tools": [definition], "metadata": {"turn_id": "workflow"}, "deduplicate_tools": ["paid_fixture"]}, hooks)
	check(outcome.get("ok", false) and outcome.get("requests") == 2 and outcome.get("steering") == 1 and host.executed.is_empty(), "A mid-request adjustment skips unstarted paid calls and continues the same task")
	check(messages[2].get("role") == "tool" and messages[3].get("role") == "tool" and JSON.parse_string(messages[2]["content"]).get("code") == "steered" and messages[4].get("role") == "user", "Steering is delivered after complete tool-result pairs, without orphaning cancelled calls")
	check(messages[4].get("turn_id") == "workflow" and messages[4].get("files") == ["reference"] and messages[4].get("references") == ["res://original.gd"] and not "fixture-secret" in str(messages[4]), "A steering message retains task identity and references while redacting saved text")
	check(host.contexts[1].any(func(item: Dictionary) -> bool: return item.get("role") == "user" and "Inspect only" in str(item.get("content", ""))), "The next model request receives the actual user adjustment")
	check(messages[4].get("delivery") == "steer" and not messages[4].has("tool_calls"), "Delivered adjustments remain ordinary user requirements rather than executable tool messages")
	host = HarnessHost.new()
	incoming.clear()
	messages = []
	hooks = host.hooks()
	hooks["steering_pending"] = func() -> bool: return not incoming.is_empty()
	hooks["steering"] = func() -> Array:
		var result = incoming.duplicate(true)
		incoming.clear()
		return result
	hooks["execute"] = func(name: String, args: Dictionary) -> Dictionary:
		incoming.append({"content": "Keep the generated result and change its placement"})
		return host.execute(name, args)
	host.replies = [_agent_response("", [a, b]), _agent_response("Existing result retained")]
	outcome = await core.run({"messages": messages, "tools": [definition]}, hooks)
	check(outcome.get("ok", false) and host.executed.size() == 1 and JSON.parse_string(messages[1]["content"]).get("ok", false) and JSON.parse_string(messages[2]["content"]).get("code") == "steered", "An adjustment arriving during an operation preserves its confirmed result and skips only later calls")
	host = HarnessHost.new()
	incoming.clear()
	messages = []
	hooks = host.hooks()
	hooks["complete"] = func(context: Array, catalog: Array, stopping: Dictionary, delta: Callable) -> Dictionary:
		if host.contexts.is_empty(): incoming.append({"content": "Also check restart"})
		return await host.complete(context, catalog, stopping, delta)
	hooks["steering"] = func() -> Array:
		var result = incoming.duplicate(true)
		incoming.clear()
		return result
	host.replies = [_agent_response("Old completion"), _agent_response("Restart verified")]
	outcome = await core.run({"messages": messages}, hooks)
	check(outcome.get("ok", false) and outcome.get("text") == "Restart verified" and host.contexts.size() == 2 and messages[1].get("role") == "user", "An adjustment arriving with a final answer is handled before settling the task")
	host = HarnessHost.new()
	var rounds = {"remaining": 1}
	hooks = host.hooks()
	hooks["needs_continuation"] = func() -> bool:
		var unfinished = rounds["remaining"] > 0
		rounds["remaining"] -= 1
		return unfinished
	hooks["continuation_prompt"] = func() -> String: return "Remaining: verify res://restart.tscn"
	host.replies = [_agent_response("Intermediate answer"), _agent_response("Task checked")]
	outcome = await core.run({}, hooks)
	check(outcome.get("ok", false) and host.contexts[1].any(func(item: Dictionary) -> bool: return item.get("role") == "system" and "res://restart.tscn" in str(item.get("content", "")) and "unfinished" in str(item.get("content", ""))), "An unfinished plan produces an explicit continuation instruction with actual remaining task context")
	var paired = [{"role": "user", "content": "Keep the request"}, {"role": "assistant", "tool_calls": [a, b]}, {"role": "tool", "tool_call_id": a["id"]}, {"role": "tool", "tool_call_id": b["id"]}, {"role": "assistant", "tool_calls": [{"id": "recent"}]}, {"role": "tool", "tool_call_id": "recent"}]
	check(scripts["harness"].context_cut(paired, 2) == 4 and scripts["harness"].context_cut(paired, 5) == 4, "Semantic compaction cuts between complete batches and keeps the newest assistant/tool group")
	paired.remove_at(2)
	check(scripts["harness"].context_cut(paired, 2) == 0, "An unresolved call prevents compaction from hiding its unmatched result")
	check(scripts["harness"].context_cut([{"role": "user"}, {"role": "assistant"}], 1) == 0, "Compacting only the original user request is rejected as unhelpful")
	host = HarnessHost.new()
	hooks = host.hooks()
	hooks["prepare_context"] = func(_context: Array, _definitions: Array, _force: bool) -> Dictionary: return {"ok": true, "result": [{"role": "user", "content": "Exact task plus validated summary"}], "compacted": true, "through": 10}
	host.replies = [_agent_response("Completed from prepared context")]
	outcome = await core.run({}, hooks)
	check(outcome.get("ok", false) and outcome.get("compactions") == 1 and host.contexts[0][0]["content"] == "Exact task plus validated summary", "The native loop consumes a validated semantic context without starting another task")
	host = HarnessHost.new()
	hooks = host.hooks()
	hooks["prepare_context"] = func(_context: Array, _definitions: Array, _force: bool) -> Dictionary: return {"ok": false, "code": "summary_save_failed", "error": "Original history retained"}
	outcome = await core.run({}, hooks)
	check(outcome.get("status") == "blocked" and outcome.get("code") == "summary_save_failed" and host.contexts.is_empty(), "A failed semantic checkpoint blocks before sending an incomplete context to the model")
	host = HarnessHost.new()
	hooks = host.hooks()
	hooks["prepare_context"] = func(_context: Array, _definitions: Array, _force: bool) -> Dictionary: return {"ok": true, "result": "invalid"}
	outcome = await core.run({}, hooks)
	check(outcome.get("code") == "invalid_context" and host.contexts.is_empty(), "A malformed context preparation result cannot reach a provider")

func _put_change_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _change_set_tests(node: Node) -> void:
	var common = scripts["common"]
	var worker = scripts["change_set"].new()
	worker.configure("user://change-set-tests/" + common.uid())
	var base = "res://change_set_tests/" + common.uid()
	var actor = base.path_join("actor.gd")
	var scene = base.path_join("world.tscn")
	var old = "extends Node\nconst VALUE = 1\n"
	var updated = "extends Node\nconst VALUE = 2\n"
	_put_change_text(actor, old)
	var changes = [{"path": actor, "action": "write", "expected_sha256": old.sha256_text(), "text": updated}, {"path": scene, "action": "write", "expected_sha256": "missing", "text": "[gd_scene format=3]\n[node name=\"World\" type=\"Node\"]\n"}]
	for definition in worker.definitions():
		check(scripts["tool_registry"].validate(definition, {"changes": changes} if definition["name"] == "godot_changes_prepare" else {"id": common.uid()}).get("ok", false), "Coordinated tools expose valid discoverable schemas: " + definition["name"])
	var bridge = SyntaxBridge.new()
	node.add_child(bridge)
	var tools = scripts["editor_tools"].new(bridge)
	tools.backup_directory = worker.directory.get_base_dir().path_join("editor-journal")
	tools.change_set = worker
	tools.turn_id = "batch-runtime"
	var prepared = await tools.execute_changes("godot_changes_prepare", {"changes": changes})
	check(prepared.get("ok", false) and prepared["result"]["state"] == "prepared", "A dependent script/scene set stages without modifying project files")
	check(FileAccess.get_file_as_string(actor) == old and not FileAccess.file_exists(scene), "Preparation leaves every original and expected absence intact")
	check(prepared["result"]["change_preview"].size() == 2 and prepared["result"]["change_preview"][0]["draft_syntax"].get("valid", false), "Preparation supplies per-file diffs and an explicitly draft syntax verdict")
	check(not prepared.get("project_mutated", true) and tools.file_changes.is_empty(), "Private preparation creates no project mutation or file undo entries")
	var id = prepared["result"]["id"]
	var applied = await tools.execute_changes("godot_changes_apply", {"id": id})
	check(applied.get("ok", false) and applied["result"]["state"] == "applied", "A coordinated apply commits the prepared set")
	check(FileAccess.get_file_as_string(actor) == updated and FileAccess.file_exists(scene), "Both dependent outputs match the staged content")
	check(tools.file_changes.size() == 2 and tools.file_changes[0].get("set_id") == id, "Coordinated writes share the existing per-turn recovery journal")
	var repeated = await tools.execute_changes("godot_changes_apply", {"id": id})
	check(repeated.get("ok", false) and tools.file_changes.size() == 2, "Repeated apply returns existing state without writing or duplicating recovery entries")
	var rolled = await tools.execute_changes("godot_changes_rollback", {"id": id})
	check(rolled.get("ok", false) and FileAccess.get_file_as_string(actor) == old and not FileAccess.file_exists(scene), "Rollback restores original bytes and removes only this set's new file")
	check(tools.file_changes.all(func(item: Dictionary) -> bool: return item.get("restored", false)), "Restored coordinated entries no longer appear as outstanding turn changes")
	check((await worker.apply(id)).get("code") == "recovery_required", "A rolled-back set cannot be silently reapplied")
	_put_change_text(actor, "later user edit")
	check(worker.rollback(id).get("ok", false) and FileAccess.get_file_as_string(actor) == "later user edit", "Repeated rollback never touches edits made after a completed rollback")
	_put_change_text(actor, old)
	var stale = worker.prepare(changes)
	_put_change_text(actor, "changed before commit")
	check((await worker.apply(stale["result"]["id"])).get("code") == "patch_conflict" and not FileAccess.file_exists(scene), "A stale member rejects the whole set before the first project write")
	_put_change_text(actor, old)
	var dirty = worker.prepare(changes, "", func(_p: String, _s: String) -> bool: return true)
	check(dirty.get("code") == "unsaved_changes", "Unsaved editor buffers reject preparation")
	var dirty_later = worker.prepare(changes)
	check((await worker.apply(dirty_later["result"]["id"], {}, null, func(_p: String, _s: String) -> bool: return true)).get("code") == "unsaved_changes", "Buffers are checked again at apply, after preparation")
	check(not worker.prepare(changes + [changes[0]]).get("ok", false), "Duplicate paths cannot create ambiguous snapshots")
	check(worker.prepare([{"path": "res://project.godot", "action": "write", "expected_sha256": "missing", "text": ""}]).get("code") == "invalid_path", "Coordinated text writes cannot bypass the project-settings tool")
	check(worker.prepare([{"path": "res://../outside.txt", "action": "write", "expected_sha256": "missing", "text": ""}]).get("code") == "invalid_path", "Coordinated preparation refuses path traversal")
	check(not worker.prepare([{"path": actor, "action": "write", "expected_sha256": old.sha256_text()}]).get("ok", false), "Write operations require explicit text")
	check(not worker.prepare([{"path": scene, "action": "delete", "expected_sha256": "missing"}]).get("ok", false), "Delete requires an existing file")
	check(not worker.prepare([{"path": scene, "action": "write", "expected_sha256": "missing", "text": "a".repeat(1024 * 1024 + 1)}]).get("ok", false), "Coordinated files obey the per-file byte cap")
	# A genuine mid-commit I/O error: create a file where a later parent must be.
	var blocked = base.path_join("blocked")
	var failing_changes = changes.duplicate(true)
	failing_changes[1]["path"] = blocked.path_join("nested.txt")
	var failing = worker.prepare(failing_changes)
	var guard_calls = [0]
	var guard = func(_p: String, _s: String) -> bool:
		guard_calls[0] += 1
		if guard_calls[0] == 4: _put_change_text(blocked, "user-owned parent")
		return false
	var failed = await worker.apply(failing["result"]["id"], {}, null, guard)
	check(not failed.get("ok", false) and failed["result"]["state"] == "rolled_back", "A second-file I/O failure triggers compensating rollback")
	check(FileAccess.get_file_as_string(actor) == old and FileAccess.get_file_as_string(blocked) == "user-owned parent", "Compensation preserves an unrelated parent file and restores the earlier write")
	DirAccess.remove_absolute(blocked)
	var concurrent = worker.prepare(changes)
	var visits = [0]
	var changing_guard = func(_p: String, _s: String) -> bool:
		visits[0] += 1
		if visits[0] == 4: _put_change_text(actor, "user changed the first commit")
		return false
	var raced = await worker.apply(concurrent["result"]["id"], {}, null, changing_guard)
	check(raced.get("code") == "restore_conflict" and raced["result"]["state"] == "rollback_conflict", "A member changed after its commit prevents a false whole-set success")
	check(FileAccess.get_file_as_string(actor) == "user changed the first commit" and not FileAccess.file_exists(scene), "Final consistency failure preserves the intervening edit and compensates the other member")
	_put_change_text(actor, old)
	var stopping = worker.prepare(changes)
	var token = {}
	var seen = [0]
	var on_frame = func() -> void:
		seen[0] += 1
		if seen[0] == 2: token["cancelled"] = true
	node.get_tree().process_frame.connect(on_frame)
	var stopped = await worker.apply(stopping["result"]["id"], token, node.get_tree())
	node.get_tree().process_frame.disconnect(on_frame)
	check(stopped.get("code") == "cancelled" and stopped["result"]["state"] == "rolled_back", "Stop between files compensates earlier writes without continuing the set")
	check(stopped["result"]["files"][0]["touched"] and not stopped["result"]["files"][1]["touched"], "Cancellation fixture proves the first member reached commit and the next did not")
	check(FileAccess.get_file_as_string(actor) == old and not FileAccess.file_exists(scene), "A cancelled application leaves original bytes and absence intact")
	var conflict = worker.prepare(changes)
	await worker.apply(conflict["result"]["id"])
	_put_change_text(actor, "manual edit after agent")
	var refused = worker.rollback(conflict["result"]["id"])
	check(refused.get("code") == "restore_conflict" and refused["result"]["conflicts"].size() == 1, "Rollback reports the exact later-edited file as a conflict")
	check(FileAccess.get_file_as_string(actor) == "manual edit after agent" and not FileAccess.file_exists(scene), "Rollback preserves the manual edit while restoring unaffected members")
	_put_change_text(actor, updated)
	check(worker.rollback(conflict["result"]["id"]).get("ok", false), "An explicit retry completes rollback after the conflict is resolved")
	var corrupt = worker.prepare(changes)
	_put_change_text(worker._blob(corrupt["result"]["id"], 0, "after"), "corrupt draft")
	check((await worker.apply(corrupt["result"]["id"])).get("code") == "recovery_failed" and FileAccess.get_file_as_string(actor) == old, "Corrupt staged content fails hash verification before any write")
	# Recreate the actual write-ahead checkpoint left by process death after rename.
	var interrupted = worker.prepare(changes)
	var interrupted_id = interrupted["result"]["id"]
	var data = worker._load(interrupted_id)
	data["state"] = "applying"
	data["entries"][0]["touched"] = true
	worker._save(data)
	check(worker._replace(data, 0, "before", "after").get("ok", false), "Crash fixture performs the first real rename using a durable write intent")
	var reopened = scripts["change_set"].new()
	reopened.configure(worker.directory)
	var recovered = reopened.status(interrupted_id)
	check(recovered["result"]["state"] == "interrupted" and recovered["result"]["files"][0]["position"] == "after", "A fresh runtime identifies interrupted intent using actual file hashes")
	check((await reopened.apply(interrupted_id)).get("code") == "recovery_required", "Interrupted transactions are never blindly replayed")
	check(reopened.rollback(interrupted_id).get("ok", false) and FileAccess.get_file_as_string(actor) == old, "A fresh runtime restores an interrupted set from verified private copies")
	var temporary_set = worker.prepare(changes)
	var temporary_id = temporary_set["result"]["id"]
	var temporary_data = worker._load(temporary_id)
	temporary_data["state"] = "applying"
	temporary_data["entries"][0]["touched"] = true
	temporary_data["entries"][0]["temporary_owned"] = true
	worker._save(temporary_data)
	var temporary_path = actor + ".ai-" + temporary_id + ".tmp"
	_put_change_text(temporary_path, updated)
	check(reopened.rollback(temporary_id).get("ok", false) and not FileAccess.file_exists(temporary_path) and FileAccess.get_file_as_string(actor) == old, "Recovery removes a hash-verified owned temporary left before rename")
	var partial_set = worker.prepare(changes)
	var partial_id = partial_set["result"]["id"]
	var partial_data = worker._load(partial_id)
	partial_data["state"] = "applying"
	partial_data["entries"][0]["touched"] = true
	partial_data["entries"][0]["temporary_owned"] = true
	worker._save(partial_data)
	var partial_path = actor + ".ai-" + partial_id + ".tmp"
	_put_change_text(partial_path, "unknown partial bytes")
	var partial_rollback = reopened.rollback(partial_id)
	check(partial_rollback.get("code") == "restore_conflict" and FileAccess.get_file_as_string(partial_path) == "unknown partial bytes", "Recovery preserves an unverified partial temporary and reports a conflict")
	DirAccess.remove_absolute(partial_path)
	check(reopened.rollback(partial_id).get("ok", false), "Recovery can complete after a temporary-file conflict is explicitly resolved")
	var delete_set = worker.prepare([{"path": actor, "action": "delete", "expected_sha256": old.sha256_text()}])
	check((await worker.apply(delete_set["result"]["id"])).get("ok", false) and not FileAccess.file_exists(actor), "Delete participates in the same coordinated protocol")
	check(worker.rollback(delete_set["result"]["id"]).get("ok", false) and FileAccess.get_file_as_string(actor) == old, "A coordinated deletion restores the exact original file")
	var empty_file = base.path_join("new/sub/empty.txt")
	var empty = worker.prepare([{"path": empty_file, "action": "write", "expected_sha256": "missing", "text": ""}])
	await worker.apply(empty["result"]["id"])
	check(FileAccess.file_exists(empty_file), "An empty new UTF-8 file is distinguishable from missing")
	worker.rollback(empty["result"]["id"])
	check(not DirAccess.dir_exists_absolute(base.path_join("new")), "Rollback removes the empty directories this set actually created")
	check(worker.status().get("result", {}).get("sets", []).size() >= 8, "Persisted change sets remain discoverable after separate agent turns")
	bridge.queue_free()

func _panel_reader_tests(node: Node) -> void:
	var host = Control.new()
	host.name = "PanelFixture"
	node.add_child(host)
	var tools = scripts["editor_tools"].new()
	var reader = tools._panels()
	var tree = Tree.new()
	tree.name = "HiddenTree"
	tree.columns = 2
	host.add_child(tree)
	tree.hide()
	var root_item = tree.create_item()
	var branch = tree.create_item(root_item)
	branch.set_text(0, "Branch")
	branch.collapsed = true
	var child = tree.create_item(branch)
	child.set_text(0, "Hidden child")
	child.set_text(1, "x".repeat(2000) + "END")
	var other = tree.create_item(root_item)
	other.set_text(0, "Last")
	var catalog = reader.catalog(host, {"filter": "HiddenTree", "limit": 1})
	check(catalog.get("ok", false) and catalog["result"]["total"] >= 1 and not catalog["result"]["items"][0]["visible"], "Panel inventory includes instantiated hidden controls without opening them")
	check(reader.catalog(host, {"filter": "HiddenTree", "include_hidden": false})["result"]["total"] == 0, "Panel inventory can explicitly restrict itself to visible controls")
	var handle = str(tools._encode(tree)["handle"])
	var first = reader.read(tree, {"handle": handle, "limit": 2})
	check(first["result"]["total"] == 4 and first["result"]["next_offset"] == 2 and first["result"]["items"][1]["collapsed"], "Tree snapshots include collapsed descendants and paginate rows")
	var snapshot = str(first["result"]["snapshot"])
	child.set_text(0, "Changed after snapshot")
	var next = reader.read(tree, {"handle": handle, "snapshot": snapshot, "offset": 2, "limit": 2})
	check(next["result"]["items"][0]["cells"][0]["text"] == "Hidden child" and next["result"]["next_offset"] == -1, "Panel pagination remains consistent when live UI changes between pages")
	var long_cell = reader.read(tree, {"handle": handle, "snapshot": snapshot, "item": 2, "column": 1, "text_offset": 1995, "text_limit": 20})
	check(long_cell["result"]["text"]["value"] == "xxxxxEND" and long_cell["result"]["text"]["next_offset"] == -1, "Long Tree cells can be read beyond their compact row excerpt")
	check(branch.collapsed and not tree.visible, "Reading hidden Tree data neither expands branches nor opens the panel")
	reader.snapshots[snapshot]["created"] = Time.get_ticks_msec() - 301000
	reader.snapshots[snapshot]["accessed"] = Time.get_ticks_msec() - 301000
	check(reader.read(tree, {"snapshot": snapshot}).get("code") == "stale_panel_snapshot", "Expired UI snapshots cannot silently become current evidence")
	var text = CodeEdit.new()
	text.text = "a".repeat(9000) + "TAIL"
	host.add_child(text)
	var code = reader.read(text, {"text_offset": 8998, "text_limit": 8})
	check(code["result"]["text"]["value"] == "aaTAIL" and code["result"]["state"]["line_count"] == 1, "Code and text panels expose complete paged source without editing it")
	var secret = LineEdit.new()
	secret.name = "CredentialField"
	secret.secret = true
	secret.text = "fixture-private-password"
	host.add_child(secret)
	check(reader.read(secret, {}).get("code") == "protected_control", "Secret controls are excluded from panel content reads")
	check(not JSON.stringify(reader.catalog(host, {})).contains("fixture-private-password"), "Panel inventory never leaks a secret field through labels")
	var counter = Label.new()
	counter.name = "TokenCounter"
	counter.text = "15"
	host.add_child(counter)
	check(reader.read(counter, {})["result"]["text"]["value"] == "15", "Gameplay token counters are not mistaken for credential fields")
	var tabs = TabContainer.new()
	host.add_child(tabs)
	for title in ["First", "Hidden tab"]:
		var page = Control.new()
		page.name = title
		tabs.add_child(page)
	tabs.set_tab_hidden(1, true)
	var tab_data = reader.read(tabs, {})
	check(tab_data["result"]["items"].size() == 2 and tab_data["result"]["items"][1]["hidden"] and tabs.current_tab == 0, "Hidden tabs are readable without changing the selected tab")
	var list = ItemList.new()
	list.add_item("One")
	list.add_item("Two")
	list.set_item_disabled(1, true)
	host.add_child(list)
	check(reader.read(list, {})["result"]["items"][1]["disabled"], "List snapshots retain disabled item state")
	var graph = GraphEdit.new()
	host.add_child(graph)
	for name in ["Source", "Target"]:
		var graph_node = GraphNode.new()
		graph_node.name = name
		graph_node.title = name
		graph.add_child(graph_node)
		graph_node.add_child(Label.new())
		graph_node.set_slot(0, true, 0, Color.WHITE, true, 0, Color.WHITE)
	graph.connect_node("Source", 0, "Target", 0)
	var graph_data = reader.read(graph, {})
	check(graph_data["result"]["items"].size() == 1 and str(graph_data["result"]["items"][0]["from_node"]) == "Source", "Graph panels expose actual cached connections instead of relying on drawn pixels")
	check(reader.read(graph.get_node("Source"), {})["result"]["state"]["title"] == "Source", "Graph nodes expose their title, ports and position")
	var color = ColorPickerButton.new()
	color.color = Color(0.1, 0.2, 0.3, 0.4)
	host.add_child(color)
	check(absf(reader.read(color, {})["result"]["state"]["color"][3] - 0.4) < 0.0001, "Color controls preserve their numeric value")
	var button = Button.new()
	button.text = "Inspect"
	button.tooltip_text = "t".repeat(5000) + "TIP"
	host.add_child(button)
	check(reader.read(button, {"field": "tooltip", "text_offset": 4998, "text_limit": 10})["result"]["text"]["value"] == "ttTIP", "Long button tooltips can be read past the inventory excerpt without hovering")
	var options = OptionButton.new()
	options.add_item("First", 77)
	options.add_item("Second", 88)
	options.select(1)
	host.add_child(options)
	var option_data = reader.read(options, {})
	check(option_data["result"]["items"][1]["id"] == 88 and option_data["result"]["items"][1]["selected"], "Dropdown snapshots expose item IDs and selection without choosing another option")
	check(tools._panel_data({"section": "monitors"}).get("code") == "panel_data_unavailable", "Missing native panel data cannot be mistaken for zero measurements")
	var bridge = NativePanelBridge.new()
	node.add_child(bridge)
	var native_tools = scripts["editor_tools"].new(bridge)
	var measured = native_tools._panel_data({"section": "profiler", "session": 2, "offset": 10, "limit": 5, "frame": 77})
	check(bridge.calls == [["profiler", 2, 10, 5, 77]] and not measured["result"]["collected"], "Native panel adapter preserves section, session, frame and uncollected state without starting profiling")
	native_tools._panel_data({"section": "monitors", "monitor": "time/fps", "offset": 3})
	check(bridge.calls[-1] == ["monitors", -1, 3, 40, -1, "time/fps"], "Monitor history selectors and page offsets reach the native adapter")
	check(not tools.validate("godot_panel_read", {"offset": -1}).get("ok", false) and not tools.validate("godot_panel_data", {"section": "invented"}).get("ok", false), "Panel reader schemas reject negative offsets and nonexistent native sections")
	var verifier = scripts["verification"].new()
	verifier.declare([{"id": "read", "description": "Read current data", "kind": "inspection"}])
	check(verifier.observe("godot_panel_data", {}, measured).is_empty(), "Uncollected profiler data cannot issue measured inspection evidence")
	check(verifier.observe("godot_panel_data", {}, {"ok": true, "result": {"collected": true, "stale_session": true}}).is_empty(), "Visual profiler or VRAM caches from older sessions cannot issue fresh inspection evidence")
	check(verifier.observe("godot_panel_read", {"snapshot": snapshot}, first).is_empty(), "Old cached UI pages cannot issue newly observed evidence after project changes")
	var opaque = Control.new()
	host.add_child(opaque)
	var opaque_read = reader.read(opaque, {})
	check(not opaque_read["result"]["coverage"]["contents_readable"] and verifier.observe("godot_panel_read", {}, opaque_read).is_empty(), "An opaque custom control cannot issue content-read evidence from an empty container snapshot")
	var many_rows = []
	for index in range(40): many_rows.append({"index": index, "text": "row".repeat(250)})
	var large_page = {"ok": true, "result": {"snapshot": "fixture-panel-snapshot", "offset": 50, "total": 200, "next_offset": 90, "items": many_rows}}
	var bounded = JSON.parse_string(scripts["harness"]._bounded_result(JSON.stringify(large_page), 4000))
	check(bounded is Dictionary and bounded["result"]["snapshot"] == "fixture-panel-snapshot" and bounded["result"]["next_offset"] == 50 + bounded["result"]["items"].size(), "Harness compaction preserves panel cursors without skipping omitted rows")
	var long_text = {"ok": true, "result": {"snapshot": "fixture-text", "offset": 0, "next_offset": -1, "total": 0, "items": [], "text": {"offset": 100, "length": 20000, "next_offset": 16100, "value": "x".repeat(16000)}}}
	var bounded_text = JSON.parse_string(scripts["harness"]._bounded_result(JSON.stringify(long_text), 3000))
	check(bounded_text["result"]["text"]["next_offset"] == 100 + bounded_text["result"]["text"]["value"].length(), "Text compaction advances only past characters actually delivered to the model")
	var minimal_page = scripts["harness"]._bounded_result(JSON.stringify(large_page), 512)
	var minimal = JSON.parse_string(minimal_page)
	check(minimal_page.length() <= 512 and minimal is Dictionary and minimal["result"]["snapshot"] == "fixture-panel-snapshot" and minimal["result"]["next_offset"] == 50, "Small parallel-tool budgets preserve a retryable panel cursor")
	host.free()
	bridge.free()

func _intelligence_tests(node: Node) -> void:
	var common = scripts["common"]
	var directory = "res://ai_test_intelligence"
	DirAccess.make_dir_recursive_absolute(directory)
	var path = directory.path_join("actor.gd")
	var scene_path = directory.path_join("world.tscn")
	var source = "extends Node\nconst RESOURCE = preload(\"res://ai_test_intelligence/missing.tres\")\n# preload(\"res://comment_only.tres\")\nvar description = \"\"\"preload(\"res://string_only.tres\")\"\"\"\nfunc act():\n\tpass\n"
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(source)
	file.close()
	file = FileAccess.open(scene_path, FileAccess.WRITE)
	file.store_string('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://ai_test_intelligence/actor.gd" id="1"]\n[node name="World" type="Node"]\nscript = ExtResource("1")\n')
	file.close()
	var tools = scripts["editor_tools"].new()
	var graph = scripts["project_knowledge"].new(node)
	var private_directory = "user://intelligence-test"
	graph.configure(private_directory)
	var refreshed = await graph.refresh(tools)
	var mapped = graph.query({"path": path})
	var actor: Dictionary = mapped["result"]["files"][0]
	check(refreshed.get("ok", false) and not graph.dirty and actor["sha256"] == source.sha256_text(), "Project map records current content hashes without loading project scripts")
	check(actor["dependencies"] == [directory.path_join("missing.tres")] and actor["dependents"] == [scene_path], "Project map links real literal dependencies and reverse scene references, ignoring comments and quoted examples")
	check(actor["symbols"].any(func(item: Dictionary) -> bool: return item["name"] == "act") and actor["missing"] == [directory.path_join("missing.tres")], "Map returns symbols and exact missing resources for a scoped file")
	check(scripts["project_knowledge"]._dependencies('[application]\nrun/main_scene="uid://bnonexistentprobe"\n[autoload]\nState="*res://state.gd"\n', "godot", tools) == ["uid://bnonexistentprobe", "res://state.gd"], "Project settings index main-scene UIDs and autoload references without loading them")
	var revision = graph.state["revision"]
	await graph.refresh(tools)
	check(graph.state["revision"] == revision, "Unchanged map refreshes retain the revision and cached parse results")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(source.replace("func act", "func updated"))
	file.close()
	await graph.refresh(tools)
	check(graph.state["revision"] > revision and graph.query({"query": "updated"})["result"]["files"].any(func(item: Dictionary) -> bool: return item["path"] == path), "Editing a script invalidates cached graph facts and updates the symbol query")
	var restored_graph = scripts["project_knowledge"].new()
	restored_graph.configure(private_directory)
	check(restored_graph.dirty and restored_graph.state["files"].has(path), "The persisted map survives a new instance but is explicitly stale until refreshed")
	var previous_digest = graph.state["digest"]
	var stopped = await graph.refresh(tools, {"cancelled": true})
	check(stopped.get("code") == "cancelled" and graph.state["digest"] == previous_digest and graph.dirty, "Cancelled indexing preserves the previous durable map and reports staleness")
	check(graph.query({"path": "res://../private"}).get("code") == "invalid_path", "Project-map queries reject paths outside the project")
	await graph.refresh(tools, {}, path)
	check(graph.summary()["coverage_scope"] == path and graph.state["files"].size() == 1, "Large projects can index a specific file independently of the global scan limits")
	var uid = ResourceUID.create_id()
	var uid_text = ResourceUID.id_to_text(uid)
	var uid_path = directory.path_join("uid_probe.gd")
	file = FileAccess.open(uid_path, FileAccess.WRITE)
	file.store_string('extends Node\nconst REF = preload("' + uid_text + '")\n')
	file.close()
	await graph.refresh(tools, {}, uid_path)
	check(graph.query({"path": uid_path})["result"]["files"][0]["unresolved_uids"] == [uid_text], "Unresolved UID references remain identifiable in the map")
	ResourceUID.add_id(uid, path)
	await graph.refresh(tools, {}, uid_path)
	var uid_entry = graph.query({"path": uid_path})["result"]["files"][0]
	check(uid_entry["unresolved_uids"].is_empty() and uid_entry["resolved_dependencies"] == [path], "Cached source dependencies re-resolve when the UID registry changes")
	ResourceUID.remove_id(uid)
	DirAccess.remove_absolute(uid_path)
	var capped_source = "extends Node\n"
	for index in range(101): capped_source += 'var resource_%d = preload("res://missing_%d.tres")\n' % [index, index]
	file = FileAccess.open(uid_path, FileAccess.WRITE)
	file.store_string(capped_source)
	file.close()
	await graph.refresh(tools, {}, uid_path)
	var capped_entry = graph.query({"path": uid_path})["result"]["files"][0]
	check(graph.state["partial"] and capped_entry["symbols_limit_reached"] and capped_entry["dependencies_limit_reached"], "Per-file symbol/dependency limits also mark project-map coverage partial")
	DirAccess.remove_absolute(uid_path)
	var issue_store = scripts["diagnostics"].new()
	issue_store.configure(private_directory)
	var issue = {"path": path, "line": 5, "message": "Fixture error", "severity": "error", "category": "syntax"}
	issue_store.replace_source("script:" + path, [issue, issue], {"sha256": source.sha256_text()})
	var report = issue_store.query()["result"]
	check(report["counts"]["error"] == 1 and report["issues"][0]["occurrences"] == 2, "Unified diagnostics group identical errors while retaining their occurrence count")
	issue_store.invalidate(path)
	check(issue_store.query()["result"]["counts"]["stale"] == 1 and issue_store.query()["result"]["counts"]["error"] == 0, "Edited source invalidates old diagnostics rather than presenting them as current failures")
	issue_store.syntax(path, {"valid": true, "errors": []}, FileAccess.get_sha256(path))
	check(issue_store.query()["result"]["issues"].is_empty() and not issue_store.sources["script:" + path]["stale"], "A fresh successful parser verdict clears only the checked source")
	var output_issues = scripts["diagnostics"].from_output("SCRIPT ERROR: Invalid call\n at: act (res://ai_test_intelligence/actor.gd:5)\nWARNING: Fixture warning\n")
	check(output_issues.size() == 2 and output_issues[0]["path"] == path and output_issues[0]["line"] == 5 and not output_issues[0]["stack"].is_empty(), "Output fallback extracts severity, project path, line and observed stack text")
	var debug_bridge = DebuggerBridge.new()
	node.add_child(debug_bridge)
	var debug_tools = scripts["editor_tools"].new(debug_bridge)
	var debug_issue = {"path": path, "line": 7, "message": "Hidden Debugger error", "function": "_ready", "severity": "error", "session": 0, "generation": 2, "active": false, "stack": [{"path": path, "line": 7, "function": "_ready"}]}
	debug_bridge.snapshot["events"] = [debug_issue]
	var debug_snapshot = debug_tools._debugger_snapshot()
	check(debug_snapshot.get("ok", false) and debug_snapshot["result"]["events"][0]["stack"][0]["line"] == 7 and not debug_snapshot["result"]["sessions"][0]["active"], "Debugger adapter preserves structured stacks and stopped-session provenance without accessing visible controls")
	var debug_text = debug_tools._debugger_text(debug_issue)
	check(debug_text.contains("ERROR: Hidden Debugger error") and debug_text.contains(path + ":7") and debug_text.contains("generation=2 stopped"), "Legacy console formatting includes native errors with source and session state")
	debug_bridge.snapshot["truncated"] = true
	check(debug_tools._debugger_snapshot()["result"]["truncated"], "Debugger adapter preserves native truncation instead of implying complete coverage")
	check(scripts["editor_tools"].new()._debugger_snapshot().get("code") == "debugger_unavailable", "Missing native Debugger bridge is an explicit failure, never an empty clean result")
	issue_store.replace_source("debugger", [debug_issue, debug_issue, debug_issue.merged({"generation": 3, "active": true}, true)], {"available": true, "errors": 3, "partial": false})
	var debug_report = issue_store.query(1)["result"]
	check(debug_report["counts"]["error"] == 2 and debug_report["truncated"] and debug_report["issues"][0]["generation"] == 3, "Debugger generations remain separate and active errors are prioritized even with a one-item query")
	check(issue_store.sources["debugger"]["issues"][0]["occurrences"] == 2 and issue_store.sources["debugger"]["issues"][0]["stack"][0]["line"] == 7, "Repeated native errors retain occurrence counts and structured stack frames")
	issue_store.invalidate(path)
	check(issue_store.sources["debugger"]["stale"], "Project edits invalidate cached Debugger observations")
	issue_store.replace_source("debugger", [], {"available": false, "partial": true})
	check(not issue_store.query()["result"]["sources"]["debugger"]["available"], "Unavailable Debugger coverage remains explicit even when no issues could be collected")
	debug_bridge.queue_free()
	var restored_diagnostics = scripts["diagnostics"].new()
	restored_diagnostics.configure(private_directory)
	check(restored_diagnostics.sources["script:" + path]["stale"], "Reloaded diagnostic caches require a fresh observation")
	var verifier = scripts["verification"].new()
	var syntax_criterion = {"id": "syntax", "description": "Actor parses", "kind": "syntax", "paths": [path]}
	var score_criterion = {"id": "score", "description": "Score reaches three", "kind": "interaction", "paths": [path], "check": {"pointer": "/after/score", "op": "gte", "expected": 3}}
	check(verifier.declare([syntax_criterion, score_criterion]).get("ok", false), "Acceptance criteria declare scoped syntax and measured interaction checks")
	check(not verifier.problem().is_empty() and verifier.check("syntax", ["invented"]).get("code") == "evidence_stale", "Completion needs real executor-issued evidence IDs")
	var read_proof = verifier.observe("godot_read_file", {"path": path}, common.success(FileAccess.get_file_as_string(path)))
	check(not verifier.check("syntax", [read_proof["id"]]).get("ok", true), "Reading source cannot satisfy a syntax criterion")
	var invalid_proof = verifier.observe("godot_script_diagnostics", {"path": path}, common.success({"path": path, "valid": false}))
	check(invalid_proof.is_empty(), "A successful diagnostics tool with invalid source does not issue a syntax-pass proof")
	check(verifier.observe("godot_script_diagnostics", {"path": path, "text": "different unsaved draft"}, common.success({"path": path, "valid": true})).is_empty(), "Valid unsaved drafts cannot verify the different saved script")
	check(verifier.observe("godot_apply_patch", {"path": path, "dry_run": true}, common.success({"path": path, "syntax": {"valid": true}})).is_empty(), "A patch preview cannot become syntax evidence for an unapplied edit")
	var syntax_proof = verifier.observe("godot_script_diagnostics", {"path": path}, common.success({"path": path, "valid": true}))
	check(verifier.check("syntax", [syntax_proof["id"]]).get("ok", false), "Valid native syntax evidence covers the declared file")
	var no_input = verifier.observe("playtest_input", {}, common.success({"sent": true}))
	check(no_input.is_empty(), "Input dispatch alone cannot become proof that a game mechanic works")
	check(verifier.observe("godot_project_map", {}, common.success({"partial": true, "stale": false, "total": 0})).is_empty(), "Incomplete project-map coverage cannot issue a false absence proof")
	check(verifier.observe("godot_output", {}, common.success([])).is_empty(), "An empty visible console cannot issue clean-runtime evidence")
	check(verifier.observe("godot_debugger", {}, common.success({"available": true, "truncated": true, "events": []})).is_empty(), "Truncated native Debugger snapshots cannot issue complete inspection evidence")
	var debug_proof = verifier.observe("godot_debugger", {}, common.success({"available": true, "truncated": false, "events": [debug_issue]}))
	check(not debug_proof.is_empty() and debug_proof.get("kinds", []) == ["inspection"], "Retained native Debugger rows provide inspection evidence rather than proof of a fresh running game")
	var partial_diagnostics = {"collection": {"debugger_available": false, "parser_available": true, "parser_partial": false, "running": false, "map": {"partial": false}}, "sources": {"debugger": {"partial": false}}}
	check(verifier.observe("godot_diagnostics", {}, common.success(partial_diagnostics)).is_empty(), "Unified diagnostics cannot verify completeness when native Debugger access is unavailable")
	partial_diagnostics["collection"]["debugger_available"] = true
	partial_diagnostics["sources"]["debugger"]["partial"] = true
	check(verifier.observe("godot_diagnostics", {}, common.success(partial_diagnostics)).is_empty(), "Unified diagnostics cannot hide native Debugger truncation behind a successful parser check")
	var wrong = verifier.observe("playtest_act", {}, common.success({"until_met": true, "after": {"score": 2}}))
	check(verifier.check("score", [wrong["id"]]).get("code") == "criterion_failed", "A measured result below the declared target fails the acceptance assertion")
	var measured = verifier.observe("playtest_act", {}, common.success({"until_met": true, "after": {"score": 3}}))
	check(verifier.check("score", [measured["id"]]).get("ok", false) and verifier.problem().is_empty(), "Only matching measured interaction evidence completes every declared criterion")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("extends Node\nfunc changed_externally(): pass\n")
	file.close()
	check(not verifier.problem().is_empty(), "External edits invalidate acceptance evidence by content hash even without a tool mutation")
	check(verifier.observe("godot_read_range", {"path": path}, common.success({"sha256": "old-source-hash", "lines": []})).is_empty(), "A source change between reading and recording evidence cannot attach the new file hash to old data")
	check(verifier.observe("godot_read_file", {"path": path}, common.success("old source contents")).is_empty(), "Plain source reads also reject observations that no longer match the saved bytes")
	verifier.changed()
	check(verifier.evidence.is_empty() and verifier.passed.is_empty(), "Project mutations invalidate previously verified criteria and evidence")
	var restored_verifier = scripts["verification"].new()
	restored_verifier.restore(verifier.snapshot())
	check(restored_verifier.criteria.size() == 2 and restored_verifier.passed.is_empty(), "Resuming keeps acceptance requirements but requires fresh observations")
	check(not verifier.declare([score_criterion, score_criterion]).get("ok", true) and verifier.criteria.size() == 2, "Invalid criteria updates cannot replace the previous valid requirements")
	check(scripts["verification"]._pointer({"a/b": {"~value": [2]}}, "/a~1b/~0value/0").get("value") == 2 and not scripts["verification"]._pointer({}, "/absent").get("found", true), "Evidence pointers support escaped keys and reject missing measurements")
	check(not scripts["verification"]._compare("3", {"op": "gte", "expected": 3}), "Numeric acceptance comparisons reject string coercion")
	check(not scripts["verification"]._compare("text", {"op": "contains", "expected": {"invalid": true}}), "Mismatched assertion types fail cleanly instead of throwing an engine error")
	var invalid_cache = private_directory.path_join("invalid-cache")
	common.atomic_json(invalid_cache.path_join("project-map.json"), {"version": 1, "root": ProjectSettings.globalize_path("res://").sha256_text(), "files": {path: {"path": path, "dependencies": "invalid", "symbols": []}}})
	var invalid_graph = scripts["project_knowledge"].new()
	invalid_graph.configure(invalid_cache)
	check(invalid_graph.state["files"].is_empty() and invalid_graph.dirty, "Structurally corrupted project caches are discarded safely")
	common.atomic_json(invalid_cache.path_join("diagnostics.json"), {"version": 1, "sources": {"broken": {"issues": ["invalid"]}}})
	var invalid_diagnostics = scripts["diagnostics"].new()
	invalid_diagnostics.configure(invalid_cache)
	check(invalid_diagnostics.query()["result"]["issues"].is_empty(), "Malformed cached diagnostics cannot crash the collector")
	restored_verifier.restore({"criteria": "invalid"})
	check(restored_verifier.criteria.is_empty() and not restored_verifier.problem().is_empty(), "Malformed restored requirements never become verified or crash Resume")
	var many_issues = []
	for index in range(120): many_issues.append({"path": path, "line": index + 1, "severity": "error", "message": "Issue " + str(index)})
	issue_store.replace_source("bounded", many_issues)
	check(issue_store.sources["bounded"]["issues"].size() == 100 and issue_store.sources["bounded"]["coverage"]["partial"], "Diagnostic truncation is explicit even when the native source buffer itself was not truncated")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(scene_path)
	DirAccess.remove_absolute(directory)

func _responses_continuation_tests(node: Node) -> void:
	for kind in ["responses", "siwc"]:
		var api = scripts["providers"].new(node, FakeVault.new())
		var transport = ResponsesTransport.new()
		api.transport = transport
		var host = ResponsesHost.new()
		host.provider = api
		host.kind = kind
		var reasoning = {"type": "reasoning", "id": "r1", "summary": [], "encrypted_content": "fixture-encrypted"}
		var partial = {"type": "message", "id": "m1", "role": "assistant", "status": "incomplete", "content": [{"type": "output_text", "text": "Part one"}]}
		var complete = {"type": "message", "id": "m2", "role": "assistant", "status": "completed", "content": [{"type": "output_text", "text": " part two"}]}
		transport.batches = [[{"type": "response.output_text.delta", "delta": "Part one"}, {"type": "response.incomplete", "response": {"status": "incomplete", "incomplete_details": {"reason": "max_output_tokens"}, "usage": {"output_tokens": 8}, "output": [reasoning, partial, {"type": "function_call", "call_id": "unfinished", "name": "write_fixture", "arguments": "{\"text\":"}]}}], [{"type": "response.completed", "response": {"status": "completed", "output": [complete]}}]]
		var messages = []
		var core = scripts["harness"].new(node)
		var outcome = await core.run({"messages": messages, "auto_continue": 2}, host.hooks())
		check(outcome.get("ok", false) and outcome.get("continuations") == 1 and outcome.get("text") == "Part one part two" and transport.requests.size() == 2, "Responses max_output_tokens continues through the real provider adapter and harness: " + kind)
		check(messages.size() == 1 and messages[0].get("provider_items", []).size() == 3 and messages[0]["provider_items"][0] == reasoning, "Responses continuation preserves native reasoning/output items in one assistant message: " + kind)
		check(host.executed.is_empty() and messages[0].get("tool_calls", []).is_empty() and not transport.requests[1]["input"].any(func(item: Dictionary) -> bool: return item.get("type") == "function_call"), "Truncated function calls are never executed or sent as orphaned provider items: " + kind)
		check(JSON.stringify(transport.requests[1]).contains("output token limit"), "Responses continuation hint reaches the provider request: " + kind)
		transport.batches = [[{"type": "response.incomplete", "response": {"incomplete_details": {"reason": "max_output_tokens"}, "usage": {"output_tokens": 9}, "output": [partial]}}]]
		var response = await api.complete({"id": "fixture", "kind": kind, "url": "https://api.openai.com/v1"}, [], [], "fixture", "", {})
		check(response.get("ok", false) and response.get("finish") == "length" and response.get("message", {}).get("content") == "Part one" and response.get("usage", {}).get("output_tokens") == 9, "Incomplete terminal output preserves text without deltas and usage: " + kind)
		for reason in ["content_filter", "unknown"]:
			transport.batches = [[{"type": "response.incomplete", "response": {"incomplete_details": {"reason": reason}, "output": []}}]]
			outcome = await core.run({"auto_continue": 2}, host.hooks())
			check(outcome.get("code") == "provider_error" and outcome.get("requests") == 1 and outcome.get("continuations") == 0, "Other Responses incomplete reasons remain failures: " + kind + "/" + reason)
		transport.batches = [[{"type": "response.failed", "response": {"error": {"message": "Fixture failed"}}}]]
		outcome = await core.run({"auto_continue": 2}, host.hooks())
		check(outcome.get("code") == "provider_error" and outcome.get("requests") == 1, "Responses provider failures are not silently continued: " + kind)

func _harness_tests(node: Node) -> void:
	var core = scripts["harness"].new(node)
	var multimedia = [{"role": "user", "content": "Inspect these screenshots", "attachments": []}]
	for index in range(4): multimedia[0]["attachments"].append({"mimeType": "image/png", "data": "a".repeat(1024 * 1024)})
	var image_estimate = core.context_tokens(multimedia)
	var bounded_images: Dictionary = core.prepare_context(multimedia, [], 1048576)
	check(image_estimate < 10000 and bounded_images["trimmed"] == 0 and bounded_images["messages"] == multimedia, "Four large Base64 screenshots do not fill or prune a million-token context")
	multimedia[0]["attachments"][0]["data"] = "b".repeat(8)
	check(core.context_tokens(multimedia) == image_estimate, "Transport encoding size never changes the token estimate of the same image count")
	var calibrated = [{"role": "tool", "content": JSON.stringify({"result": "x".repeat(3000000)})}, {"role": "assistant", "tool_calls": [{"id": "latest", "name": "inspect", "arguments": {}}]}]
	check(core.prepare_context(calibrated, [], 1048576, false, 100000)["trimmed"] == 0, "A provider-calibrated low context load prevents heuristic pruning of a large old tool result")
	check(core.input_tokens({"input_tokens": 5, "cache_read_input_tokens": 100, "cache_creation_input_tokens": 20}) == 125 and core.input_tokens({"prompt_tokens": 125, "prompt_cache_hit_tokens": 100}) == 125, "Context usage includes Anthropic cache input without counting OpenAI-style cache hits twice")
	check(core.context_tokens([{"role": "assistant", "content": "", "reasoning_content": "thought ".repeat(1000)}]) > 2000, "Retained reasoning is included in context estimates")
	var definitions = [scripts["common"].tool("write_fixture", "Fixture", {}, [], "write")]
	var call = {"id": "one", "name": "write_fixture", "arguments": {}}
	var deferred = HarnessHost.new()
	deferred.replies = [_agent_response("", [{"id": "discover", "name": "tool_describe", "arguments": {"name": "write_fixture"}}]), _agent_response("", [call]), _agent_response("Done")]
	var discovered = await core.run({"tools": definitions, "deferred_tools": true}, deferred.hooks())
	check(discovered.get("ok", false) and deferred.executed.size() == 1 and deferred.catalogs[0].size() == 2 and deferred.catalogs[1].any(func(item: Dictionary) -> bool: return item["name"] == "write_fixture"), "Harness loads discovered definitions on the next provider request")
	deferred = HarnessHost.new()
	deferred.replies = [_agent_response("", [call]), _agent_response("Unavailable until discovery")]
	var unloaded_messages = []
	await core.run({"tools": definitions, "deferred_tools": true, "messages": unloaded_messages}, deferred.hooks())
	check(deferred.executed.is_empty() and "tool_not_loaded" in str(unloaded_messages[1].get("content")), "Guessing an undeclared tool name cannot bypass deferred discovery")
	var host = HarnessHost.new()
	host.replies = [{"ok": false, "status": 429, "headers": {"Retry-After": "0"}, "error": "Temporary"}, _agent_response("", [call]), _agent_response("Verified fixture-secret")]
	var messages = [{"role": "user", "content": "Inspect and edit"}]
	var events = []
	core.event.connect(func(value: Dictionary) -> void: events.append(value))
	var outcome = await core.run({"messages": messages, "tools": definitions, "retry_delay_ms": 0}, host.hooks())
	check(outcome.get("status") == "completed" and outcome.get("requests") == 3 and outcome.get("retries") == 1 and outcome.get("steps") == 2, "Native harness retries rate limits and completes a tool turn")
	check(host.executed.size() == 1 and messages.size() == 4 and host.contexts[-1][-1].get("role") == "tool", "Native harness passes tool results back to the model")
	check(outcome.get("duration_ms", -1) >= 0 and events.filter(func(item: Dictionary) -> bool: return item.get("kind") in ["message", "tool_result"]).all(func(item: Dictionary) -> bool: return item.get("duration_ms", -1) >= 0), "Harness records total, provider-response and tool durations without publishing reasoning")
	check(not "fixture-secret" in JSON.stringify(messages) and not "fixture-secret" in JSON.stringify(events), "Harness transcripts and events redact credentials")
	check(host.checkpoints.any(func(value: Dictionary) -> bool: return value.get("status") == "waiting_tool") and host.checkpoints[-1].get("status") == "completed", "Harness checkpoints before side effects and after settlement")
	var blocked_host = HarnessHost.new()
	blocked_host.replies = [_agent_response("Verification is unavailable")]
	var blocked_hooks = blocked_host.hooks()
	blocked_hooks["blocked_reason"] = func() -> String: return "Native diagnostics unavailable"
	var blocked_outcome = await core.run({"tools": definitions}, blocked_hooks)
	check(blocked_outcome.get("status") == "blocked" and blocked_outcome.get("code") == "task_blocked" and not blocked_outcome.get("ok", true), "A blocked task does not become completed when the model ends its tool loop")

	# Simulate resuming a persisted conversation whose provider repeats its call ID.
	host = HarnessHost.new()
	host.replies = [_agent_response("", [call]), _agent_response("Previously applied")]
	outcome = await core.run({"messages": messages, "tools": definitions}, host.hooks())
	check(outcome.get("ok", false) and host.executed.is_empty(), "Resume reuses recorded tool results without replaying project writes")
	var review_definition = scripts["common"].tool("review_fixture", "Fixture partial approval", {"text": {"type": "string"}}, ["text"], "write")
	var requested_call = {"id": "partial-review", "name": "review_fixture", "arguments": {"text": "accepted and rejected changes"}}
	var repeated_call = requested_call.duplicate(true)
	var new_call = requested_call.duplicate(true)
	new_call["id"] = "partial-new-id"
	var reviewed_history = []
	var reviewed_host = HarnessHost.new()
	reviewed_host.narrowed_arguments = {"text": "accepted changes only"}
	reviewed_host.tool_result = {"ok": true, "result": {"path": "res://review.gd"}, "approval": {"partial": true, "selected_hunks": [1], "rejected_hunks": [2]}}
	reviewed_host.replies = [_agent_response("", [requested_call]), _agent_response("", [repeated_call]), _agent_response("", [new_call]), _agent_response("Only the approved change was applied")]
	var reviewed = await core.run({"tools": [review_definition], "messages": reviewed_history, "deduplicate_tools": ["review_fixture"]}, reviewed_host.hooks())
	check(reviewed.get("ok", false) and reviewed_host.executed.size() == 1 and reviewed.get("reused_calls") == 2, "Partial review keeps original call identity for same-ID replay and operation deduplication")
	check(requested_call["arguments"]["text"] == "accepted and rejected changes" and reviewed_history[0]["tool_calls"][0]["arguments"] == requested_call["arguments"] and reviewed_host.executed[0]["arguments"]["text"] == "accepted changes only", "The executor narrows a private copy while provider arguments and history remain immutable")
	check(int(JSON.parse_string(reviewed_history[1]["content"]).get("approval", {}).get("rejected_hunks", [0])[0]) == 2 and JSON.parse_string(reviewed_history[3]["content"]).get("approval", {}).get("partial", false), "Partial approval details reach the model and survive replay")
	var restored_host = HarnessHost.new()
	restored_host.replies = [_agent_response("", [requested_call.duplicate(true)]), _agent_response("Previously approved")]
	var restored_core = scripts["harness"].new(node)
	var restored_outcome = await restored_core.run({"messages": reviewed_history, "tools": [review_definition]}, restored_host.hooks())
	check(restored_outcome.get("ok", false) and restored_host.executed.is_empty(), "Restored partial approval history replays without another write or review")
	var changed = call.duplicate(true)
	changed["arguments"] = {"unexpected": true}
	host = HarnessHost.new()
	host.replies = [_agent_response("", [changed])]
	outcome = await core.run({"messages": messages, "tools": definitions}, host.hooks())
	check(outcome.get("code") == "invalid_response" and host.executed.is_empty(), "Conflicting reused IDs are rejected before any execution")

	host = HarnessHost.new()
	host.replies = [_agent_response("", [call, call])]
	outcome = await core.run({"tools": definitions}, host.hooks())
	check(outcome.get("code") == "invalid_response" and host.executed.is_empty(), "Duplicate IDs in one model response cannot duplicate writes")
	host = HarnessHost.new()
	host.replies = [_agent_response("", [{"id": "unknown", "name": "hidden_tool", "arguments": {}}]), _agent_response("Unavailable")]
	messages = []
	outcome = await core.run({"messages": messages, "tools": definitions}, host.hooks())
	check(host.executed.is_empty() and "tool_unavailable" in str(messages[1].get("content")), "Tools outside the active registry never reach the executor")
	host = HarnessHost.new()
	host.replies = [_agent_response("", [call]), _agent_response("Unavailable")]
	var blocked_messages = [_agent_response("", [call])["message"], {"role": "tool", "tool_call_id": "one", "content": "{\"ok\":true}"}]
	outcome = await core.run({"messages": blocked_messages, "tools": []}, host.hooks())
	check(host.executed.is_empty() and outcome.get("tool_calls") == 0 and "tool_unavailable" in str(blocked_messages[-2].get("content", "")), "A recorded result does not bypass the current tool registry")
	host = HarnessHost.new()
	host.replies = [_agent_response("", [{"id": "bad", "name": "write_fixture", "arguments": "invalid"}])]
	outcome = await core.run({"tools": definitions}, host.hooks())
	check(outcome.get("code") == "invalid_response" and host.executed.is_empty(), "Malformed model arguments cannot reach the executor")

	host = HarnessHost.new()
	host.stop_after_tool = true
	host.token = {"cancelled": false}
	var next = call.duplicate(true)
	next["id"] = "two"
	host.replies = [_agent_response("", [call, next])]
	messages = []
	outcome = await core.run({"messages": messages, "tools": definitions, "cancel": host.token}, host.hooks())
	check(outcome.get("status") == "cancelled" and host.executed.size() == 1, "Stop between batch tools prevents the remaining side effect")
	check(messages.size() == 3 and messages[-1].get("tool_call_id") == "two" and "cancelled" in str(messages[-1].get("content")), "Cancellation closes every pending call for a valid next turn")
	host = HarnessHost.new()
	outcome = await core.run({"cancel": {"cancelled": true}}, host.hooks())
	check(outcome.get("status") == "cancelled" and host.contexts.is_empty(), "Pre-cancelled harness never contacts a model")
	host = HarnessHost.new()
	host.token = {"cancelled": false}
	host.replies = [{"ok": false, "status": 503, "error": "Temporary"}]
	var stopping = host.token
	var stop_retry = func(value: Dictionary) -> void:
		if value.get("kind") == "retry": stopping["cancelled"] = true
	core.event.connect(stop_retry)
	outcome = await core.run({"cancel": stopping}, host.hooks())
	core.event.disconnect(stop_retry)
	check(outcome.get("status") == "cancelled" and host.contexts.size() == 1, "Stop interrupts retry backoff before another request")

	host = HarnessHost.new()
	host.replies = [{"ok": false, "code": "incomplete_stream", "error": "Interrupted", "_delta": "Partial"}]
	outcome = await core.run({}, host.hooks())
	check(outcome.get("status") == "failed" and host.contexts.size() == 1, "A visible partial response is never silently regenerated by retry")
	host = HarnessHost.new()
	host.replies = [{"ok": false, "status": 401, "error": "Invalid credentials"}]
	outcome = await core.run({}, host.hooks())
	check(host.contexts.size() == 1 and outcome.get("status") == "failed", "Authentication errors are not retried")
	host = HarnessHost.new()
	host.replies = [{"ok": false, "status": 503, "error": "Temporary"}, {"ok": false, "status": 503, "error": "Temporary"}, {"ok": false, "status": 503, "error": "Temporary"}]
	outcome = await core.run({"retry_delay_ms": 0}, host.hooks())
	check(outcome.get("status") == "failed" and host.contexts.size() == 3 and outcome.get("retries") == 2, "Transient failures stop at the retry budget")
	host = HarnessHost.new()
	host.reenter = core
	host.replies = [_agent_response("Original turn")]
	outcome = await core.run({}, host.hooks())
	check(outcome.get("ok", false) and host.reentry_result.get("code") == "busy" and outcome.get("text") == "Original turn", "A concurrent turn cannot overwrite an active harness session")
	host.reenter = null
	host = HarnessHost.new()
	host.replies = [_agent_response("", [call])]
	outcome = await core.run({"tools": definitions, "max_steps": 1}, host.hooks())
	check(outcome.get("status") == "limited" and outcome.get("code") == "step_limit" and not outcome.get("ok", true), "An explicitly bounded evaluation stops distinctly from completion")

	var advance = scripts["common"].tool("advance_fixture", "Advance a distinct fixture work item", {"index": {"type": "integer"}}, ["index"], "write")
	for evaluation_limit in [0, 140]:
		host = HarnessHost.new()
		for index in range(135):
			host.replies.append(_agent_response("", [{"id": "long-" + str(index), "name": "advance_fixture", "arguments": {"index": index}}]))
		host.replies.append(_agent_response("All 135 work items verified"))
		var long_options = {"tools": [advance]}
		if evaluation_limit > 0: long_options["max_steps"] = evaluation_limit
		outcome = await core.run(long_options, host.hooks())
		check(outcome.get("ok", false) and outcome.get("steps") == 136 and host.executed.size() == 135, "Progressing tasks pass both old 30/100 ceilings; optional evaluation limit=" + str(evaluation_limit))
		check(host.checkpoints[-1].get("status") == "completed" and host.checkpoints[-1].get("steps") == 136, "Long runs retain the complete settled checkpoint; evaluation limit=" + str(evaluation_limit))

	host = HarnessHost.new()
	host.token = {"cancelled": false}
	for index in range(120):
		host.replies.append(_agent_response("", [{"id": "stop-long-" + str(index), "name": "advance_fixture", "arguments": {"index": index}}]))
	var long_stop_token = host.token
	var stop_long = func(value: Dictionary) -> void:
		if value.get("kind") == "request_started" and value.get("step") == 112: long_stop_token["cancelled"] = true
	core.event.connect(stop_long)
	outcome = await core.run({"tools": [advance], "cancel": long_stop_token, "max_steps": 0}, host.hooks())
	core.event.disconnect(stop_long)
	check(outcome.get("status") == "cancelled" and host.contexts.size() == 111 and host.executed.size() == 111, "An explicitly unlimited run still stops before another request beyond both old ceilings")
	host = HarnessHost.new()
	host.replies = [_agent_response("Partial answer", [], "length")]
	outcome = await core.run({}, host.hooks())
	check(outcome.get("status") == "limited" and outcome.get("code") == "output_limit", "Output exhaustion is distinct from completion")
	host = HarnessHost.new()
	host.replies = [_agent_response("Part one", [], "length"), _agent_response(" part two")]
	messages = []
	var auto_events = []
	var auto_listener = func(value: Dictionary) -> void:
		if value.get("kind") == "auto_continue": auto_events.append(value)
	core.event.connect(auto_listener)
	outcome = await core.run({"messages": messages, "auto_continue": 2}, host.hooks())
	core.event.disconnect(auto_listener)
	check(outcome.get("ok", false) and outcome.get("text") == "Part one part two" and outcome.get("continuations") == 1, "Truncated output continues automatically and completes the answer")
	check(messages.size() == 1 and messages[0].get("role") == "assistant" and messages[0].get("content") == "Part one part two", "Auto-continue merges the continuation into a single assistant record")
	check(host.contexts.size() == 2 and str(host.contexts[1][-1].get("content", "")).contains("output token limit"), "The continuation request carries an internal instruction without adding a user message to history")
	check(auto_events.size() == 1 and auto_events[0].get("attempt") == 1, "Continuation attempts are visible as events")
	host = HarnessHost.new()
	host.replies = [_agent_response("A", [], "length"), _agent_response("B", [], "length"), _agent_response("C", [], "length")]
	messages = []
	outcome = await core.run({"messages": messages, "auto_continue": 2}, host.hooks())
	check(outcome.get("status") == "limited" and outcome.get("code") == "output_limit" and outcome.get("continuations") == 2 and host.contexts.size() == 3, "Auto-continue stops at its two-attempt budget")
	check(messages.size() == 1 and messages[0].get("content") == "ABC", "Bounded continuations still preserve the complete generated text")
	host = HarnessHost.new()
	host.replies = [_agent_response("Let me inspect", [], "length"), _agent_response(" and fix it", [call]), _agent_response("Done")]
	messages = []
	outcome = await core.run({"messages": messages, "tools": definitions, "auto_continue": 2}, host.hooks())
	check(outcome.get("ok", false) and host.executed.size() == 1 and messages[0].get("content") == "Let me inspect and fix it" and messages[0].get("tool_calls", []).size() == 1, "A continuation can carry merged tool calls without splitting the assistant turn")
	host = HarnessHost.new()
	host.fail_checkpoint_status = "waiting_tool"
	host.replies = [_agent_response("", [call])]
	messages = []
	outcome = await core.run({"tools": definitions, "messages": messages}, host.hooks())
	check(outcome.get("code") == "checkpoint_failed" and host.executed.is_empty() and messages.size() == 2 and "checkpoint_failed" in str(messages[-1].get("content", "")), "Failed durable checkpoint stops the write and closes its call")
	host = HarnessHost.new()
	host.tool_result = {"ok": true, "result": "x".repeat(30000)}
	host.replies = [_agent_response("", [call]), _agent_response("Done")]
	messages = []
	outcome = await core.run({"tools": definitions, "messages": messages}, host.hooks())
	var bounded: Variant = JSON.parse_string(str(messages[1]["content"]))
	check(outcome.get("ok", false) and bounded is Dictionary and bounded.get("truncated", false) and str(messages[1]["content"]).length() <= 24000, "Large tool results remain bounded valid JSON")
	check(bounded.get("ok", false), "Truncating a successful tool result preserves its success contract")
	check(str(bounded.get("tail", "")).length() == 2000, "A truncated result keeps the end of the output alongside its start")
	check(events.filter(func(item: Dictionary) -> bool: return item.get("kind") == "tool_result")[-1]["result"].get("ok", false), "Large successful results remain successful in activity events")
	var batch = HarnessHost.new()
	batch.tool_result = {"ok": true, "result": "y".repeat(30000)}
	batch.replies = [_agent_response("", [{"id": "b1", "name": "write_fixture", "arguments": {}}, {"id": "b2", "name": "write_fixture", "arguments": {}}, {"id": "b3", "name": "write_fixture", "arguments": {}}, {"id": "b4", "name": "write_fixture", "arguments": {}}]), _agent_response("Done")]
	messages = []
	outcome = await core.run({"tools": definitions, "messages": messages}, batch.hooks())
	var sizes = [str(messages[1]["content"]).length(), str(messages[2]["content"]).length(), str(messages[3]["content"]).length(), str(messages[4]["content"]).length()]
	var last_bounded: Variant = JSON.parse_string(str(messages[4]["content"]))
	check(outcome.get("ok", false) and sizes.max() <= 24000 and sizes[3] < sizes[0] and sizes.reduce(func(total: int, size: int) -> int: return total + size, 0) <= 48000, "Tool results in one step share a bounded batch budget")
	check(last_bounded is Dictionary and last_bounded.get("ok", false) and last_bounded.get("truncated", false), "An exhausted batch budget still preserves the success contract and the truncation marker")
	for failed in [false, true]:
		batch = HarnessHost.new()
		var batch_calls = []
		for index in range(64): batch_calls.append({"id": "large-batch-" + str(index), "name": "advance_fixture", "arguments": {"index": index}})
		batch.tool_result = {"ok": not failed, "result": {"id": "existing-job", "status": "failed" if failed else "completed", "text": "\"\\\n".repeat(20000)}}
		batch.tool_result["approval"] = {"partial": true, "selected_hunks": [1], "rejected_hunks": range(2, 65), "requested_sha256": "a".repeat(64), "approved_sha256": "b".repeat(64)}
		var batch_errors = []
		for index in range(20): batch_errors.append({"line": index + 1, "message": "Parse error " + "e".repeat(250)})
		batch.tool_result["result"]["syntax"] = {"valid": false, "errors": batch_errors}
		if failed: batch.tool_result.merge({"code": "fixture_failure", "error": "Fixture failure fixture-secret"})
		batch.replies = [_agent_response("", batch_calls), _agent_response("Batch inspected")]
		messages = []
		outcome = await core.run({"tools": [advance], "messages": messages}, batch.hooks())
		var total = 0
		var valid_contracts = true
		var identities = true
		var reviewed_verdicts = true
		for index in range(1, 65):
			var content = str(messages[index]["content"])
			total += content.length()
			var parsed: Variant = JSON.parse_string(content)
			valid_contracts = valid_contracts and parsed is Dictionary and parsed.get("ok") == not failed and content.length() <= 24000
			if failed: valid_contracts = valid_contracts and parsed.get("code") == "fixture_failure" and parsed.get("error") == "Fixture failure [redacted]"
			identities = identities and messages[index].get("tool_call_id") == batch_calls[index - 1]["id"] and parsed.get("result", {}).get("id") == "existing-job"
			var approval: Dictionary = parsed.get("approval", {})
			reviewed_verdicts = reviewed_verdicts and approval.get("partial", false) and int(approval.get("rejected_hunks_count", approval.get("rejected_hunks", []).size())) == 63 and parsed.get("result", {}).get("syntax", {}).get("valid") == false
		check(outcome.get("ok", false) and batch.executed.size() == 64 and total <= 48000, "All 64 valid calls share a strict 48000-character budget; failures=" + str(failed))
		check(valid_contracts and identities, "Even the last reserved result is valid JSON with status, redacted errors and existing job/call identity; failures=" + str(failed))
		check(reviewed_verdicts, "Compact batch results preserve partial approval and the structured invalid syntax verdict; failures=" + str(failed))
	host = HarnessHost.new()
	host.tool_result = {"ok": true, "result": {"path": "res://a.gd", "syntax": {"valid": false, "errors": [{"line": 2, "column": 1, "message": "Expected expression"}], "truncated": false}, "text": "z".repeat(30000)}}
	host.replies = [_agent_response("", [call]), _agent_response("Done")]
	messages = []
	await core.run({"tools": definitions, "messages": messages}, host.hooks())
	bounded = JSON.parse_string(str(messages[1]["content"]))
	check(bounded.get("result", {}).get("syntax", {}).get("valid", true) == false and bounded["result"]["syntax"]["errors"][0]["line"] == 2, "A truncated write result keeps its automatic syntax verdict")
	var many_errors = []
	for index in range(20): many_errors.append({"line": index + 1, "column": 1, "message": "Parse error " + "e".repeat(250)})
	host.tool_result["result"]["syntax"]["errors"] = many_errors
	host.tool_result["approval"] = {"partial": true, "selected_hunks": [1], "rejected_hunks": [2]}
	host.replies = [_agent_response("", [call]), _agent_response("Parser errors inspected")]
	messages = []
	await core.run({"tools": definitions, "messages": messages}, host.hooks())
	bounded = JSON.parse_string(str(messages[1]["content"]))
	check(bounded.get("result", {}).get("syntax", {}).get("valid") == false and bounded["result"]["syntax"].get("errors_count") == 20 and bounded["result"]["syntax"].get("truncated", false), "Long parser diagnostics retain a structured invalid verdict and error count")
	check(bounded.get("approval", {}).get("partial", false) and int(bounded["approval"].get("rejected_hunks", [0])[0]) == 2, "Large reviewed results retain the explicit partial approval contract")
	host = HarnessHost.new()
	host.tool_result = {"ok": true, "files": ["large-artifact"], "result": {"id": "existing-large-job", "status": "completed", "file": "/generated/tree.glb", "imported_path": "res://game/tree.glb", "text": "\"\\\n".repeat(20000)}}
	host.replies = [_agent_response("", [call]), _agent_response("", [call]), _agent_response("Existing job recovered")]
	messages = []
	outcome = await core.run({"tools": definitions, "messages": messages}, host.hooks())
	bounded = JSON.parse_string(str(messages[1]["content"]))
	check(str(messages[1]["content"]).length() <= 24000 and bounded is Dictionary, "Escaped quotes, slashes and newlines cannot exceed the serialized result limit")
	check(bounded.get("ok", false) and bounded.get("files", []) == ["large-artifact"] and bounded.get("result", {}).get("id") == "existing-large-job" and bounded.get("result", {}).get("status") == "completed", "A bounded artifact result retains file references and its existing job identity")
	check(bounded.get("result", {}).get("file") == "/generated/tree.glb" and bounded.get("result", {}).get("imported_path") == "res://game/tree.glb", "Bounded artifact results preserve the actual generated and imported paths")
	var replayed_large: Variant = JSON.parse_string(str(messages[3]["content"]))
	check(outcome.get("ok", false) and host.executed.size() == 1 and replayed_large.get("result", {}).get("id") == "existing-large-job", "Large result replay reuses the confirmed artifact without another execution")
	host = HarnessHost.new()
	host.tool_result = {"ok": false, "code": "invalid_method", "error": "Method unavailable fixture-secret", "result": "\"".repeat(30000)}
	host.replies = [_agent_response("", [call]), _agent_response("Reported real failure")]
	messages = []
	await core.run({"tools": definitions, "messages": messages}, host.hooks())
	bounded = JSON.parse_string(str(messages[1]["content"]))
	check(bounded.has("ok") and bounded["ok"] == false and bounded.get("code") == "invalid_method" and bounded.get("error") == "Method unavailable [redacted]", "Truncated failures keep their real code and redacted reason")
	host = HarnessHost.new()
	var encoded = Marshalls.raw_to_base64(Image.create_empty(2, 2, false, Image.FORMAT_RGBA8).save_png_to_buffer())
	host.tool_result = {"ok": true, "result": {"text": "Frame"}, "images": [{"name": "frame.png", "mimeType": "image/png", "data": encoded}]}
	host.replies = [_agent_response("", [call]), _agent_response("Observed")]
	messages = []
	outcome = await core.run({"tools": definitions, "messages": messages}, host.hooks())
	check(outcome.get("ok", false) and messages[1].get("attachments", []).size() == 1 and not encoded in str(messages[1]["content"]), "Tool images reach the model as attachments without base64 in its text context")

	var repaired = scripts["harness"].repair_messages([_agent_response("", [call])["message"]])
	host = HarnessHost.new()
	host.replies = [_agent_response("", [call]), _agent_response("Inspect first")]
	outcome = await core.run({"tools": definitions, "messages": repaired}, host.hooks())
	check(outcome.get("ok", false) and host.executed.is_empty(), "An interrupted persisted write is not automatically executed again")
	host = HarnessHost.new()
	host.replies = [_agent_response("Plan ready"), _agent_response("Implemented and verified")]
	var pending = {"yes": true}
	var hooks = host.hooks()
	hooks["needs_continuation"] = func() -> bool:
		var result: bool = pending["yes"]
		pending["yes"] = false
		return result
	outcome = await core.run({}, hooks)
	check(outcome.get("ok", false) and host.contexts.size() == 2 and outcome.get("text") == "Implemented and verified", "An unfinished Auto plan continues after an intermediate answer instead of ending the task")
	host = HarnessHost.new()
	host.replies = [_agent_response("Still planning"), _agent_response("Still planning")]
	hooks = host.hooks()
	hooks["needs_continuation"] = func() -> bool: return true
	outcome = await core.run({"max_steps": 2}, hooks)
	check(outcome.get("code") == "step_limit" and host.contexts.size() == 2, "Plan continuation respects an explicit evaluation-only step budget")

func _behavior_tests(node: Node) -> void:
	var core = scripts["harness"].new(node)
	var definitions = scripts["assets"].new(node, FakeVault.new()).definitions()
	var first = {"id": "generate-1", "name": "asset_generate", "arguments": {"profile": "mesh-fixture", "prompt": "A wooden box"}}
	var repeated = first.duplicate(true)
	repeated["id"] = "generate-2"
	var host = HarnessHost.new()
	host.tool_result = {"ok": true, "result": {"id": "existing-job", "status": "processing"}}
	host.replies = [_agent_response("", [first]), _agent_response("", [repeated]), _agent_response("Waiting for existing-job")]
	var messages = [{"role": "user", "content": "Generate one box", "turn_id": "generation-turn"}]
	var options = {"id": "generation-turn", "metadata": {"turn_id": "generation-turn"}, "messages": messages, "tools": definitions, "deduplicate_tools": ["asset_generate"]}
	var result = await core.run(options, host.hooks())
	check(result.get("ok", false) and host.executed.size() == 1, "The same paid generation with a fresh provider call ID reuses its existing job")
	host = HarnessHost.new()
	var resumed = first.duplicate(true)
	resumed["id"] = "generate-resumed"
	host.replies = [_agent_response("", [resumed]), _agent_response("Recovered")]
	result = await core.run(options, host.hooks())
	check(result.get("ok", false) and host.executed.is_empty(), "Resuming the same user turn cannot submit its generation again under another call ID")
	host = HarnessHost.new()
	resumed["id"] = "generate-new-request"
	host.replies = [_agent_response("", [resumed]), _agent_response("New requested variant")]
	options["id"] = "new-user-turn"
	options["metadata"] = {"turn_id": "new-user-turn"}
	result = await core.run(options, host.hooks())
	check(result.get("ok", false) and host.executed.size() == 1, "A genuinely new user turn can request another generation with the same prompt")
	host = HarnessHost.new()
	var variant = repeated.duplicate(true)
	variant["id"] = "generate-variant"
	variant["arguments"]["variant"] = "second-requested-box"
	host.replies = [_agent_response("", [first, variant]), _agent_response("Two requested variants")]
	result = await core.run({"tools": definitions, "deduplicate_tools": ["asset_generate"]}, host.hooks())
	check(result.get("ok", false) and host.executed.size() == 2, "An explicit variant distinguishes multiple requested outputs from accidental generation retries")
	host = HarnessHost.new()
	host.tool_results = [{"ok": false, "code": "plan_required", "error": "Publish a plan"}, {"ok": true, "result": {"id": "after-plan"}}]
	host.replies = [_agent_response("", [first]), _agent_response("", [repeated]), _agent_response("Recovered after preflight")]
	result = await core.run({"tools": definitions, "deduplicate_tools": ["asset_generate"]}, host.hooks())
	check(result.get("ok", false) and host.executed.size() == 2, "A preflight plan refusal does not prevent submitting the operation after its requirements are fixed")
	host = HarnessHost.new()
	host.tool_results = [{"ok": false, "code": "plan_required", "error": "Publish a plan"}, {"ok": true, "result": {"id": "after-plan"}}]
	host.replies = [_agent_response("", [first]), _agent_response("", [first]), _agent_response("Recovered with the original call ID")]
	result = await core.run({"tools": definitions, "deduplicate_tools": ["asset_generate"]}, host.hooks())
	check(result.get("ok", false) and host.executed.size() == 2, "A corrected plan preflight can reuse the original call ID instead of remaining stuck on its earlier refusal")
	host = HarnessHost.new()
	host.tool_result = {"ok": false, "code": "permission_denied", "error": "User declined"}
	var write = scripts["common"].tool("write_fixture", "Write a fixture", {}, [], "write")
	host.replies = [_agent_response("", [{"id": "denied-one", "name": "write_fixture", "arguments": {}}]), _agent_response("", [{"id": "denied-two", "name": "write_fixture", "arguments": {}}]), _agent_response("Permission respected")]
	result = await core.run({"tools": [write]}, host.hooks())
	check(result.get("ok", false) and host.executed.size() == 1, "A fresh tool call ID cannot ask for the same declined operation again in the current turn")
	var interrupted_message = _agent_response("", [first])["message"]
	interrupted_message["turn_id"] = "uncertain-turn"
	var uncertain = scripts["harness"].repair_messages([interrupted_message])
	host = HarnessHost.new()
	host.replies = [_agent_response("", [repeated]), _agent_response("Check the provider job before retrying")]
	result = await core.run({"id": "uncertain-turn", "messages": uncertain, "tools": definitions, "deduplicate_tools": ["asset_generate"]}, host.hooks())
	check(result.get("ok", false) and host.executed.is_empty(), "An interrupted paid submission cannot be blindly repeated after restart with a fresh call ID")
	host = HarnessHost.new()
	for index in range(5): host.replies.append(_agent_response("Still working"))
	var hooks = host.hooks()
	hooks["needs_continuation"] = func() -> bool: return true
	result = await core.run({"max_steps": 5}, hooks)
	check(result.get("code") == "no_progress" and host.contexts.size() == 4, "An unfinished plan receives three reminders before settling without further tools or progress")
	host = HarnessHost.new()
	host.tool_result = {"ok": false, "code": "invalid_path", "error": "Missing file"}
	var read = scripts["common"].tool("read_fixture", "Read a fixture", {}, [])
	for index in range(5): host.replies.append(_agent_response("", [{"id": "failure-" + str(index), "name": "read_fixture", "arguments": {}}]))
	result = await core.run({"tools": [read], "max_steps": 5}, host.hooks())
	check(result.get("code") == "no_progress" and host.executed.size() == 3, "Repeated identical tool failures stop with a useful outcome instead of spending the full budget")
	host = HarnessHost.new()
	host.tool_result = {"ok": false, "code": "invalid_path", "error": "Missing file"}
	var batch = []
	for index in range(5): batch.append({"id": "batch-" + str(index), "name": "read_fixture", "arguments": {}})
	host.replies = [_agent_response("", batch)]
	messages = []
	result = await core.run({"tools": [read], "messages": messages}, host.hooks())
	check(result.get("code") == "no_progress" and host.executed.size() == 3 and messages.size() == 6, "A stalled batch closes all remaining tool calls without executing them")
	host = HarnessHost.new()
	result = await core.run({"cancel": {"cancelled": true, "reason": "new_request"}}, host.hooks())
	check(result.get("code") == "redirected" and result.get("message") == "Trec la cererea nouă." and host.contexts.is_empty(), "A replacement request has an explicit cancellation outcome instead of looking like a user Stop")

func _local_connection_tests(node: Node) -> void:
	var script = scripts["providers"]
	for entry in [["192.168.1.50", "lmstudio", "http://192.168.1.50:1234/v1"], ["192.168.1.50", "ollama", "http://192.168.1.50:11434/v1"], ["192.168.1.50:7777/v1/models", "lmstudio", "http://192.168.1.50:7777/v1"], ["http://192.168.1.50:11434/api/tags", "ollama", "http://192.168.1.50:11434/v1"], ["::1", "lmstudio", "http://[::1]:1234/v1"], ["https://local.example/proxy/v1", "lmstudio", "https://local.example:443/proxy/v1"]]:
		check(script.local_endpoint(entry[0], entry[1]).get("result") == entry[2], "Local connection accepts an IP or URL without requiring manual API paths: " + entry[0])
	check(not script.local_endpoint("http://user@host:1234?token=x", "lmstudio").get("ok", true), "Quick local connection rejects embedded credentials and URL query tokens")
	check(script.connection_error({"url": "http://127.0.0.1:1234/v1"}, {"code": "connection_failed"}, true).contains("acest dispozitiv"), "Android loopback failures explain which device 127.0.0.1 refers to")
	check(script.connection_error({"url": mock_url}, {"status": 401}).contains("token valid"), "An authenticated server is distinguished from an unreachable host")
	var local_options = script.inference_options({"issuer": "lmstudio", "url": mock_url})
	check(local_options["connect_timeout"] < local_options["first_response_timeout"] and local_options["idle_timeout"] > 0 and local_options["timeout"] > local_options["first_response_timeout"], "Local inference has independent connect, initial-response, idle and total budgets")
	var vault = FakeVault.new()
	var service = script.new(node, vault)
	var deepseek = {"id": "deepseek", "issuer": "deepseek", "name": "DeepSeek", "kind": "chat", "url": mock_url + "/deepseek", "allow_http": true}
	vault.store("deepseek", "deepseek-fixture-token")
	var discovered = await service.list_models(deepseek)
	check(discovered.get("ok", false) and discovered["result"].size() == 2 and discovered["result"][0]["id"] == "deepseek-flash", "DeepSeek model discovery uses GET /models with the saved bearer credential")
	check(discovered["result"][0]["context"] == 1048576 and discovered["result"][0]["efforts"] == ["low", "high", "max"] and discovered["result"][0]["capabilities"].get("vision", false), "DeepSeek catalog preserves returned context, reasoning levels and image support")
	check(script.connection_error(deepseek.merged({"url": "https://api.deepseek.com"}, true), {"status": 401}).contains("Cheia API") and not script.connection_error({"issuer": "deepseek", "url": "https://api.deepseek.com"}, {"code": "timeout"}).contains("Wi-Fi"), "Cloud model discovery distinguishes key errors and network failures from LAN setup")
	vault.store("deepseek", "old-invalid-fixture")
	var draft = await service.list_models(deepseek, {}, "deepseek-fixture-token")
	check(draft.get("ok", false) and vault.read("deepseek") == "old-invalid-fixture", "Draft API authentication verifies the in-memory replacement without overwriting the saved vault key")
	var lm = await service.list_models({"id": "lm", "issuer": "lmstudio", "kind": "chat", "url": mock_url + "/local-lm", "allow_http": true})
	check(lm.get("ok", false) and lm.get("result", []).size() == 1 and lm["result"][0]["loaded"] and lm["result"][0]["context"] == 4096, "LM Studio connection reads the actual loaded context and excludes embedding models")
	var ollama = await service.list_models({"id": "ollama", "issuer": "ollama", "kind": "chat", "url": mock_url + "/local-ollama/v1", "allow_http": true})
	check(ollama.get("ok", false) and ollama["result"].size() == 2 and ollama["result"][0]["loaded"] and not ollama["result"][1]["loaded"] and ollama["result"][0]["context"] == 4096, "Ollama connects through its native tags and running-model endpoints without inference")
	var protected = {"id": "auth", "issuer": "lmstudio", "kind": "chat", "url": mock_url + "/auth-lm/v1", "allow_http": true}
	check((await service.list_models(protected)).get("status") == 401, "Local server authentication failure is preserved")
	vault.store("auth", "local-fixture-token")
	check((await service.list_models(protected)).get("ok", false), "Local server tokens use the existing credential vault")
	var transport = scripts["transport"].new(node)
	var slow = await transport.request(mock_url + "/drip", HTTPClient.METHOD_GET, [], null, {"allow_http": true, "timeout": 2.0, "first_response_timeout": 0.25, "idle_timeout": 0.4})
	check(slow.get("ok", false) and slow.get("events", []).size() == 4, "A stream stays connected while data arrives beyond the initial response budget")
	var idle = await transport.request(mock_url + "/idle-drip", HTTPClient.METHOD_GET, [], null, {"allow_http": true, "timeout": 2.0, "idle_timeout": 0.2})
	check(idle.get("code") == "timeout" and idle.get("stage") == "body", "A stream that stops sending data times out with an explicit body stage")
	var hard = await transport.request(mock_url + "/drip", HTTPClient.METHOD_GET, [], null, {"allow_http": true, "timeout": 0.2, "idle_timeout": 1.0})
	check(hard.get("code") == "timeout", "The total stream budget remains enforced even when bytes keep arriving")
	var stopping = {"cancelled": false}
	var stopped = await transport.request(mock_url + "/drip", HTTPClient.METHOD_GET, [], null, {"allow_http": true, "cancel": stopping, "idle_timeout": 2.0, "on_event": func(_event: Dictionary) -> void: stopping["cancelled"] = true})
	check(stopped.get("code") == "cancelled", "Stop remains responsive during an otherwise healthy local stream")

func _network_tests(node: Node) -> void:
	var vault = FakeVault.new()
	var adapter = scripts["providers"].new(node, vault)
	vault.store("oauth-record", JSON.stringify({"access_token": "fixture-access", "refresh_token": "fixture-refresh"}))
	var mismatched = await adapter.list_models({"id": "oauth-record", "kind": "chat", "url": mock_url + "/v1", "allow_http": true})
	check(mismatched.get("code") == "credential_type_mismatch", "OAuth records never become API-key headers")
	var wrong_host = await adapter.list_models({"id": "oauth-record", "kind": "siwc", "url": mock_url + "/v1", "allow_http": true})
	check(wrong_host.get("code") == "credential_type_mismatch", "ChatGPT credentials are bound to the official OpenAI endpoint")
	var profile = {"id": "fixture", "kind": "chat", "url": mock_url + "/v1", "allow_http": true}
	var resume_profile = profile.merged({"url": mock_url + "/thinking/v1"}, true)
	var interrupted = [{"role": "user", "content": "Finish"}, {"role": "assistant", "content": "", "wire_source": "fixture:m", "reasoning_content": "fixture reasoning", "tool_calls": [{"id": "thinking-call", "name": "godot_project", "arguments": {}}]}, {"role": "tool", "tool_call_id": "thinking-call", "content": "{\"ok\":true}"}, {"role": "assistant", "content": "Stopped; changes preserved", "run_status": "cancelled"}]
	var resume_tools = [scripts["common"].tool("godot_project", "Inspect", {}, [])]
	var invalid_body: Dictionary = scripts["providers"].build_request("chat", interrupted.slice(0, 3), resume_tools, "m", "high")["body"]
	invalid_body["messages"].append({"role": "assistant", "content": "Stopped; changes preserved"})
	var rejected = await adapter.transport.request(resume_profile["url"] + "/chat/completions", HTTPClient.METHOD_POST, [], invalid_body, {"allow_http": true})
	check(rejected.get("status") == 400, "Strict thinking protocol reproduces the native Stop/Resume rejection for synthetic assistant notices")
	var resumed = await adapter.complete(resume_profile, interrupted, resume_tools, "m", "high", {})
	check(resumed.get("ok", false) and resumed.get("message", {}).get("content") == "Resume verified" and resumed.get("message", {}).get("reasoning_content") == "fixture continuation", "Real HTTP Stop/Resume preserves provider reasoning and sends application notices separately")
	var replay_profile = profile.merged({"id": "deepseek-replay", "issuer": "deepseek", "url": mock_url + "/replay/v1"}, true)
	var replay_history = [{"role": "user", "content": "Continue the task"}, {"role": "assistant", "content": "Earlier verified answer", "wire_source": "another-provider:m"}, {"role": "user", "content": "Apply the next change"}]
	var replayed = await adapter.complete(replay_profile, replay_history, resume_tools, "m", "high", {})
	check(replayed.get("ok", false) and replayed.get("message", {}).get("content") == "Replay verified", "DeepSeek tool requests replay every prior assistant turn, including foreign or legacy turns without saved reasoning")
	var core = scripts["harness"].new(node)
	var direct_messages = [{"role": "user", "content": "Inspect through the native harness"}]
	var direct_complete = func(context: Array, catalog: Array, stopping: Dictionary, delta: Callable) -> Dictionary:
		return await adapter.complete(profile, context, catalog, "fixture", "", stopping, delta)
	var direct_tools = []
	var dispatch = func(name: String, args: Dictionary) -> Dictionary:
		direct_tools.append(name)
		return scripts["common"].success(args)
	var direct = await core.run({"messages": direct_messages, "tools": [scripts["common"].tool("godot_project", "Inspect", {}, [])]}, {"complete": direct_complete, "execute": dispatch})
	check(direct.get("ok", false) and direct_tools == ["godot_project"] and direct.get("steps") == 2 and direct_messages[-1].get("content") == "Verificat: română 🐦", "Own harness performs a real HTTP model/tool/result loop without a companion")
	var listed = await adapter.list_models(profile)
	check(listed.get("ok", false) and listed.get("result", []).size() == 1, "Real HTTP model discovery")
	check(listed.get("result", [{}])[0].get("efforts", []) == ["high", "max"], "Use provider-declared reasoning efforts")
	var bounded_profile = profile.duplicate()
	bounded_profile["url"] = mock_url + "/bounded/v1"
	var bounded = await adapter.complete(bounded_profile, [{"role": "user", "content": "Summarize"}], [], "fixture", "", {}, Callable(), 512)
	check(bounded.get("ok", false) and bounded.get("message", {}).get("content") == "Bounded summary verified", "Real HTTP summary request carries its reserved output allowance")
	var history = [{"role": "user", "content": "Inspect"}]
	var first = await adapter.complete(profile, history, [], "fixture", "", {})
	check(first.get("ok", false) and first.get("calls", []).size() == 1, "Real HTTP streaming tool call")
	if first.get("ok", false):
		history.append(first["message"])
		history.append({"role": "tool", "tool_call_id": "fixture-call", "tool_name": "godot_project", "content": "{}"})
		var second = await adapter.complete(profile, history, [], "fixture", "", {})
		check(second.get("ok", false) and second.get("message", {}).get("content") == "Verificat: română 🐦", "Real multi-turn tool/result continuation")
	var incomplete_profile = profile.duplicate()
	var json_profile = profile.duplicate()
	json_profile["url"] = mock_url + "/json/v1"
	var json_first = await adapter.complete(json_profile, [{"role": "user", "content": "Inspect"}], [], "fixture", "", {})
	check(json_first.get("ok", false) and json_first.get("calls", []).size() == 2, "Compatible JSON-only servers retain separate tool calls")
	if json_first.get("ok", false):
		var json_history = [{"role": "user", "content": "Inspect"}, json_first["message"]]
		for call in json_first["calls"]: json_history.append({"role": "tool", "tool_call_id": call["id"], "tool_name": call["name"], "content": "{}"})
		var json_second = await adapter.complete(json_profile, json_history, [], "fixture", "", {})
		check(json_second.get("ok", false) and json_second.get("message", {}).get("content") == "JSON verified", "Compatible JSON-only server tool continuation")
	incomplete_profile["url"] = mock_url + "/incomplete/v1"
	var incomplete = await adapter.complete(incomplete_profile, [{"role": "user", "content": "Inspect"}], [], "fixture", "", {})
	check(not incomplete.get("ok", false) and incomplete.get("code") == "incomplete_stream", "Interrupted provider streams never report success")
	for kind in ["responses", "anthropic", "gemini"]:
		var native_profile = profile.duplicate()
		native_profile["kind"] = kind
		var result = await adapter.complete(native_profile, [{"role": "user", "content": "Inspect"}], [], "fixture", "", {})
		check(result.get("ok", false) and not str(result.get("message", {}).get("content", "")).is_empty(), "Real HTTP adapter: " + kind)
	var stopping = {"cancelled": false}
	var slow_profile = profile.duplicate()
	slow_profile["url"] = mock_url + "/slow/v1"
	create_timer(0.05).timeout.connect(func() -> void: stopping["cancelled"] = true)
	var stopped = await adapter.complete(slow_profile, [{"role": "user", "content": "Inspect"}], [], "fixture", "", stopping)
	check(not stopped.get("ok", false) and stopped.get("code") == "cancelled", "Cancel a provider HTTP request in flight")
	var mcp = scripts["mcp"].new(node, vault)
	var server = {"id": "fixture-mcp", "url": mock_url + "/mcp", "allow_http": true, "trusted_read": false}
	var catalog = await mcp.discover(server)
	check(catalog.get("ok", false) and catalog.get("result", []).size() == 2, "MCP initialize, session and paginated discovery")
	if catalog.get("ok", false):
		var name = str(catalog["result"][0]["name"])
		var denied = await mcp.call_tool(name, {}, 0, false, {})
		check(denied.get("code") == "permission_denied", "Untrusted MCP read annotations do not grant access")
		var called = await mcp.call_tool(name, {}, 2, true, {})
		check(called.get("ok", false) and "real fixture tool result" in JSON.stringify(called), "MCP real HTTP tool execution")
		var failed = await mcp.call_tool(name, {"fail": true}, 2, true, {})
		check(not failed.get("ok", true) and failed.get("code") == "mcp_tool_error", "Real MCP HTTP execution errors propagate through the normalized result")
	var assets = scripts["assets"].new(node, vault)
	var scratch = OS.get_user_data_dir().path_join("ai_test_generation")
	assets.configure(scratch)
	for kind in ["image", "mesh"]:
		var generation = {"id": "fixture-comfy", "kind": "comfy", "asset_kind": kind, "url": mock_url, "allow_http": true, "destination": "res://ai_test_assets", "workflow": {"1": {"class_type": "SaveGLB" if kind == "mesh" else "SaveImage", "inputs": {"text": ""}}}, "prompt_node": "1", "prompt_input": "text", "output_node": "1"}
		var submitted = await assets.submit(generation, "Fixture", "", {})
		check(submitted.get("ok", false), "ComfyUI submit: " + kind)
		if not submitted.get("ok", false): continue
		var refreshed = await assets.refresh(str(submitted["result"]["id"]), generation, {})
		check(refreshed.get("ok", false) and refreshed.get("result", {}).get("status") == "completed", "ComfyUI download and artifact validation: " + kind)
		if not refreshed.get("ok", false): continue
		check(FileAccess.file_exists(str(refreshed["result"].get("imported_path", ""))) and str(refreshed["result"].get("imported_path", "")).begins_with("res://ai_test_assets/fixture_"), "Completed ComfyUI asset is auto-imported into its named folder: " + kind)
		var waited = await assets.wait_for_job(str(submitted["result"]["id"]), generation, {}, 1)
		check(waited.get("ok", false) and waited.get("result", {}).get("status") == "completed", "Generation wait returns the verified result: " + kind)
		if kind == "mesh":
			var document = GLTFDocument.new()
			var state = GLTFState.new()
			check(document.append_from_file(str(refreshed["result"]["file"]), state) == OK, "Generated GLB actually loads through Godot's importer")
			var scene = document.generate_scene(state)
			check(scene != null, "Godot builds the generated GLB scene")
			if scene != null: scene.free()
		var imported = assets.import_job(str(submitted["result"]["id"]), "res://ai_test_assets")
		check(imported.get("ok", false) and FileAccess.file_exists(str(imported.get("result", {}).get("path", ""))) and str(imported.get("result", {}).get("path", "")).contains("/fixture_"), "Completed artifact is organized under the configured folder: " + kind)
		var again = assets.import_job(str(submitted["result"]["id"]), "res://ai_test_assets")
		check(again.get("ok", false) and again.get("result", {}).get("path") == imported.get("result", {}).get("path"), "Repeated import reuses the organized artifact without overwriting: " + kind)
	var bad_profile = {"id": "fixture-bad-output", "kind": "comfy", "asset_kind": "mesh", "url": mock_url, "allow_http": true, "workflow": {"2": {"class_type": "FixturePrompt", "inputs": {"text": ""}}}, "prompt_node": "2", "prompt_input": "text", "output_node": "2"}
	var bad_submit = await assets.submit(bad_profile, "Fixture", "", {})
	if bad_submit.get("ok", false):
		var missing = await assets.refresh(str(bad_submit["result"]["id"]), bad_profile, {})
		check(missing.get("code") == "missing_artifact", "Completed workflows with wrong output bindings fail explicitly")

func _new_feature_tests() -> void:
	var common = scripts["common"]
	var directory = OS.get_user_data_dir().path_join("conversation_" + common.uid())
	common.atomic_json(directory.path_join("history.json"), [{"id": "legacy", "role": "user", "content": "Original"}])
	var store = scripts["conversations"].new()
	store.configure(directory)
	var original_id = str(store.index["active"])
	check(store.load_active().size() == 1, "Migrate legacy conversation without losing messages")
	store.configure(directory)
	check(store.index["items"].size() == 1 and str(store.index["active"]) == original_id, "Conversation migration is idempotent")
	check(FileAccess.file_exists(directory.path_join("history.json")), "Migration preserves original history file")
	var image = Image.create(2, 2, false, Image.FORMAT_RGB8)
	image.fill(Color.RED)
	var data = Marshalls.raw_to_base64(image.save_png_to_buffer())
	store.save([{"id": "image", "role": "user", "content": "Image", "attachments": [{"mimeType": "image/png", "data": data}]}], {"profile": "local", "model": "vision"})
	check(store.load_active()[0]["attachments"][0]["data"] == data, "Attachment cache survives conversation reload")
	check(not "data" in common.read_json(store._path(original_id), {})["messages"][0]["attachments"][0], "History JSON references image cache instead of duplicating base64")
	var fork_id = store.fork_at("image")
	check(fork_id != original_id and store.load_active().size() == 1 and store.index["items"].size() == 2, "Fork preserves the original conversation")
	store.update(fork_id, {"title": "Local vision", "favorite": true})
	check(store.listing("VISION").size() == 1, "Conversation search ignores case")
	store.update(fork_id, {"archived": true})
	check(store.listing("", true).size() == 1, "Archive and active history have separate lists")
	var capture_history = scripts["conversations"].new()
	capture_history.configure(directory.path_join("automatic-captures"))
	var capture_messages = [{"id": "capture", "role": "tool", "content": "Frame", "attachments": [{"mimeType": "image/png", "data": data, "temporary_capture": true}]}]
	check(capture_history.save(capture_messages) == OK, "Temporary capture metadata survives a cache-write failure")
	check(not DirAccess.dir_exists_absolute(capture_history.directory.path_join("attachments")), "Temporary captures never fall back to an unbounded permanent attachment copy")
	check(not capture_history.load_active()[0]["attachments"][0].has("data"), "Temporary pixel buffers are omitted from saved history")
	var provider = scripts["providers"]
	var summary_input = [{"role": "user", "content": "Summarize for continuation."}]
	check(provider.build_request("chat", summary_input, [], "m", "", 512)["body"].get("max_tokens") == 512, "Bounded summaries reserve output on the Chat protocol")
	check(provider.build_request("anthropic", summary_input, [], "m", "", 512)["body"].get("max_tokens") == 512, "Bounded summaries override the Anthropic default output allowance")
	check(provider.build_request("responses", summary_input, [], "m", "", 512)["body"].get("max_output_tokens") == 512, "Bounded summaries reserve output on the Responses protocol")
	check(provider.build_request("gemini", summary_input, [], "m", "", 512)["body"].get("generationConfig", {}).get("maxOutputTokens") == 512, "Bounded summaries reserve output on the Gemini protocol")
	check(not provider.build_request("chat", summary_input, [], "m")["body"].has("max_tokens"), "Ordinary agent requests retain their existing output policy")
	var internals = [{"role": "assistant", "content": "Public", "wire_source": "a:m", "reasoning_content": "private", "provider_items": [{"type": "reasoning"}], "provider_blocks": [{"type": "thinking"}]}]
	var normalized = provider.normalize_context({"id": "b"}, "m", internals)
	check(not normalized[0].has("reasoning_content") and not normalized[0].has("provider_blocks") and not normalized[0].has("provider_items"), "Provider switching strips foreign reasoning and signed blocks")
	check(provider.normalize_context({"id": "a"}, "m", internals)[0].has("reasoning_content"), "Same-model tool loops retain required reasoning")
	var resumed_history = [{"role": "user", "content": "Finish the scene"}, {"role": "assistant", "content": "", "wire_source": "a:m", "reasoning_content": "fixture reasoning", "tool_calls": [{"id": "resume-call", "name": "godot_project", "arguments": {}}]}, {"role": "tool", "tool_call_id": "resume-call", "content": "{\"ok\":true}"}, {"role": "assistant", "content": "Stopped; changes preserved", "run_status": "cancelled", "turn_id": "resume-turn"}, {"role": "assistant", "content": "Interrupted draft", "application_message": "partial"}, {"role": "assistant", "content": "Referenced files: tree.glb", "origin_label": "Fișiere generate", "files": ["file-one"]}]
	var resume_wire = provider.build_request("chat", provider.normalize_context({"id": "a"}, "m", resumed_history), [], "m")["body"]["messages"]
	check(resume_wire.filter(func(m: Dictionary) -> bool: return m.get("role") == "assistant").size() == 1 and resume_wire[1].get("reasoning_content") == "fixture reasoning", "Resume excludes synthetic assistant notices while preserving exact model reasoning and tool calls")
	check(resume_wire.any(func(m: Dictionary) -> bool: return m.get("role") == "system" and str(m.get("content", "")).contains("Stopped; changes preserved")) and resume_wire.any(func(m: Dictionary) -> bool: return m.get("role") == "system" and str(m.get("content", "")).contains("tree.glb")), "Interruption and file-card context remain available as application state")
	check(resume_wire[2].get("tool_call_id") == "resume-call" and not resumed_history[3].has("reasoning_content") and resumed_history[3]["role"] == "assistant", "Protocol repair neither invents reasoning nor changes saved UI history or tool result identity")
	for kind in ["responses", "anthropic", "gemini"]:
		var body: Dictionary = provider.build_request(kind, resumed_history, [], "m")["body"]
		var system_text = str(body.get("instructions", body.get("system", body.get("systemInstruction", {}))))
		check(system_text.contains("Stopped; changes preserved") and system_text.contains("tree.glb"), "Synthetic local state uses system context across protocols: " + kind)
	var reasoning_store = scripts["conversations"].new()
	reasoning_store.configure(directory + "-reasoning")
	reasoning_store.save([{"id": "confirmed-answer", "role": "assistant", "content": "Verified answer", "wire_source": "a:m", "reasoning_content": "fixture reasoning"}])
	var reasoning_fork = reasoning_store.fork_at("confirmed-answer")
	check(not reasoning_fork.is_empty() and reasoning_store.load_active()[0].get("reasoning_content") == "fixture reasoning", "Forking a confirmed answer preserves reasoning needed by the originating provider")
	var multimodal = [{"role": "user", "content": "Describe", "attachments": [{"mimeType": "image/png", "data": data}]}]
	check(provider.build_request("chat", multimodal, [], "v")["body"]["messages"][0]["content"][1]["type"] == "image_url", "Chat image request uses image_url")
	check(provider.build_request("responses", multimodal, [], "v")["body"]["input"][0]["content"][1]["type"] == "input_image", "Responses image request uses input_image")
	check(provider.build_request("anthropic", multimodal, [], "v")["body"]["messages"][0]["content"][1]["source"]["type"] == "base64", "Anthropic image request uses base64 source")
	check(provider.build_request("gemini", multimodal, [], "v")["body"]["contents"][0]["parts"][0].has("inlineData"), "Gemini image request uses inlineData")
	var pcm = PackedByteArray()
	pcm.resize(192000)
	var wav = scripts["speech"].wav_16k(pcm, 48000, 2)
	check(wav.slice(0, 4).get_string_from_ascii() == "RIFF" and wav.decode_u32(24) == 16000 and wav.decode_u16(22) == 1 and wav.size() == 32044, "Voice resampling creates valid mono 16kHz one-second WAV")
	var tools = scripts["editor_tools"].new()
	check(tools.execute("godot_write_file", {"path": "res://blocked.txt", "text": "x"}, 3, true).get("code") == "permission_denied", "Plan mode independently denies mutations")

	check(store.item(fork_id).get("selection", {}).get("model") == "vision", "Fork retains its originating model selection")
	var fork_path = store._path(fork_id)
	check(store.remove(fork_id) == OK and not FileAccess.file_exists(fork_path) and store.item(fork_id).is_empty() and store.index["active"] == original_id, "Archived deletion removes the actual transcript and selects a surviving conversation")
	var invalid_count = store.index["items"].size()
	check(store.fork_at("missing-message") == "" and store.index["items"].size() == invalid_count, "A stale message action cannot fork the entire conversation")
	check(store.update(original_id, {"title": "   "}) == ERR_INVALID_DATA, "An empty rename cannot erase the conversation title")
	var index_path = store.directory.path_join("index.json")
	DirAccess.rename_absolute(index_path, index_path + ".fixture-backup")
	DirAccess.make_dir_absolute(index_path)
	var original_bytes = FileAccess.get_file_as_bytes(store._path(original_id))
	check(store.create().is_empty() and store.index["active"] == original_id and store.index["items"].size() == 1, "A failed new-chat save preserves the existing active conversation")
	check(store.remove(original_id) != OK and store.index["active"] == original_id and FileAccess.get_file_as_bytes(store._path(original_id)) == original_bytes, "Failed index writes roll deletion back without losing transcript bytes")
	DirAccess.remove_absolute(index_path)
	DirAccess.rename_absolute(index_path + ".fixture-backup", index_path)
	check(store.remove(original_id) == OK and store.item(original_id).is_empty() and not store.item(str(store.index["active"])).is_empty() and store.load_active().is_empty(), "Deleting the last unarchived conversation creates a usable empty chat")
	var replacement_id = str(store.index["active"])
	store.configure(directory)
	check(store.index["active"] == replacement_id and store.index["items"].size() == 1, "Deletion and replacement survive reloading the on-disk index")
	var recovery_path = store._path(replacement_id)
	DirAccess.rename_absolute(recovery_path, recovery_path + ".deleting")
	store.configure(directory)
	check(FileAccess.file_exists(recovery_path) and not FileAccess.file_exists(recovery_path + ".deleting"), "An interrupted deletion restores a transcript still referenced by the committed index")
	var jobs = scripts["agent_jobs"].new()
	jobs.jobs = {"one": {"status": "running", "profile": {"id": "one"}}, "two": {"status": "running", "profile": {"id": "two"}}}
	check(not jobs.spawn("Inspect", "Explore", {"id": "third"}, "m", "", "p").get("ok", false), "Cloud child limit applies across provider profiles")
	jobs.jobs.erase("two")
	check(not jobs.spawn("Inspect", "General", {"id": "local", "issuer": "ollama"}, "m", "", "p").get("ok", false), "Local models do not start an extra parallel child")

func _image_purpose_tests(assets: RefCounted, vault: RefCounted, cache: String) -> void:
	var script = scripts["assets"]
	var image_profile = {"id": "fixture-purpose-image", "kind": "openai_image", "asset_kind": "image", "destination": "res://ai_test_assets"}
	vault.store(image_profile["id"], "generation-fixture-key")
	var sprite = script.generation_contract(image_profile, "A walking bird, 4 frames", {"purpose": "sprite"})
	var texture = script.generation_contract(image_profile, "Wood planks", {"purpose": "texture"})
	var scenery = script.generation_contract(image_profile, "A forest", {"purpose": "background"})
	check(sprite.get("result", {}).get("background") == "transparent" and "2D game sprite" in sprite["result"]["generation_prompt"] and "4 frames" in sprite["result"]["generation_prompt"], "Sprite requests preserve the user's frame layout and require a real cutout instead of a reconstruction render")
	check(texture.get("result", {}).get("background") == "opaque" and "tileable" in texture["result"]["generation_prompt"] and scenery.get("result", {}).get("background") == "opaque" and "complete composition" in scenery["result"]["generation_prompt"], "Textures and scenery retain opaque surfaces and environments rather than isolated sprite rules")
	var generic = script.generation_contract(image_profile, "An ordinary painting")
	var override = script.generation_contract(image_profile, "A bird on white", {"purpose": "reference_3d", "background": "opaque"})
	check(generic["result"]["generation_prompt"] == "An ordinary painting" and generic["result"]["background"] == "auto" and override["result"]["background"] == "opaque" and not "real alpha" in override["result"]["generation_prompt"], "Ordinary illustrations remain unrestricted and an explicit opaque reference overrides the cutout default")
	var submitted = await assets.submit(image_profile, "A wooden box", "", {}, {"purpose": "reference_3d"})
	check(submitted.get("ok", false) and submitted.get("result", {}).get("purpose") == "reference_3d" and "3D reconstruction" in submitted.get("result", {}).get("generation_prompt", ""), "A real adapter submission carries the distinct reconstruction contract into its saved job")
	if not submitted.get("ok", false): return
	var source: Dictionary = submitted["result"]
	check(source.get("status") == "completed" and not source.get("quality", {}).get("ready_for_use", true) and not source["quality"]["has_transparency"] and FileAccess.file_exists(source["imported_path"]), "An opaque RGBA PNG is preserved but never certified as a transparent 3D reference")
	var mesh_profile = {"id": "fixture-purpose-mesh", "kind": "meshy", "asset_kind": "mesh", "destination": "res://ai_test_assets"}
	vault.store(mesh_profile["id"], "generation-fixture-key")
	var blocked = await assets.submit(mesh_profile, "must-not-submit", source["imported_path"], {})
	check(blocked.get("code") == "reference_needs_review", "A known invalid reference cannot start a paid 3D conversion")
	var source_hash = FileAccess.get_sha256(source["file"])
	var removal_profile = {"id": "runware-image", "kind": "runware", "credential_id": "generation_runware", "asset_kind": "image", "destination": "res://ai_test_assets"}
	var corrected = await assets.remove_background(removal_profile, source["file"], {}, "reference_3d")
	check(corrected.get("ok", false) and corrected.get("result", {}).get("operation") == "remove_background", "The native background-removal adapter processes the existing image without regenerating it")
	if not corrected.get("ok", false): return
	var id = str(corrected["result"]["id"])
	var completed = await assets.wait_for_job(id, removal_profile, {}, 1)
	check(completed.get("ok", false) and completed.get("result", {}).get("quality", {}).get("ready_for_use", false) and completed["result"]["quality"]["has_transparency"], "Background removal downloads and verifies a PNG with visible content and actual alpha")
	if not completed.get("ok", false): return
	var cutout: Dictionary = completed["result"]
	var repeated = await assets.remove_background(removal_profile, source["imported_path"], {}, "reference_3d")
	check(repeated.get("result", {}).get("id") == id, "Using the imported alias of the same image reuses the existing cutout job instead of charging again")
	check(cutout["file"] != source["file"] and FileAccess.get_sha256(source["file"]) == source_hash and str(cutout["imported_path"]).get_file().begins_with("a-wooden-box-cutout"), "Cutouts preserve original bytes and keep object-based names in a separate folder")
	var recovered = script.new(assets.owner, vault)
	recovered.test_http = true
	recovered.api_urls = assets.api_urls.duplicate(true)
	recovered.configure(cache)
	var restored = await recovered.refresh(id, removal_profile, {})
	check(restored.get("result", {}).get("quality", {}).get("ready_for_use", false), "Background-removal completion and alpha verification survive restart without another submission")
	var converted = await assets.submit(mesh_profile, "existing-cutout", cutout["imported_path"], {})
	check(converted.get("ok", false), "The corrected existing reference can proceed to image-to-3D")
	var empty_image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	empty_image.fill(Color.TRANSPARENT)
	var empty_path = cache.path_join("empty-reference.png")
	empty_image.save_png(empty_path)
	check(not script.image_quality(empty_path, "transparent")["ready_for_use"] and script.image_quality(source["file"], "auto")["ready_for_use"], "An empty transparent image fails quality while an ordinary opaque illustration stays usable")
	check((await assets.remove_background(image_profile, source["imported_path"], {})).get("code") == "unsupported_provider", "Background removal never invents unsupported provider parameters")
	var transport = scripts["transport"].new(assets.owner)
	var counts = await transport.request(mock_url + "/fixture-submissions", HTTPClient.METHOD_GET, [], null, {"allow_http": true})
	check(counts.get("json", {}).get("remove_background") == 1 and counts.get("json", {}).get("must-not-submit", 0) == 0, "Polling and recovering a cutout sends exactly one removal POST and no invalid 3D POST")

func _cloud_generation_tests(node: Node) -> void:
	var script = scripts["assets"]
	var common = scripts["common"]
	var catalog_script = scripts["generation_catalog"]
	var measured = catalog_script.runware_price({"info": {"x-pricing": {"measured": [{"price": 0.0045, "configuration": "1024 × 1024 · steps 20"}]}}})
	check(measured.get("basis") == "estimate" and catalog_script.price_label(measured).begins_with("≈"), "Measured GPU costs are shown as estimates, not fixed generation prices")
	var token_price = catalog_script.runware_price({"info": {"x-pricing": {"rates": [{"amount": 0.00003, "unit": "outputToken"}]}}})
	check(token_price.get("basis") == "usage" and not token_price.has("amount"), "Per-token rates cannot become a misleading per-generation amount")
	check(catalog_script.price_label({"basis": "unknown"}) == "Indisponibil" and catalog_script.price_label({"amount": 0.0, "currency": "USD", "basis": "fixed"}) == "0 USD", "Unknown prices differ visibly from a genuinely zero tariff")
	check(catalog_script.openai_price("gpt-image-2-2026-04-21").get("amount") == 0.006 and not catalog_script.openai_price("gpt-image-unannounced").has("amount"), "Only documented OpenAI versions inherit a documented estimate")
	check(catalog_script.presets("meshy", "image").size() == 7 and catalog_script.presets("meshy", "mesh").size() == 5, "Meshy image and mesh catalogs are distinct and priced in provider credits")
	check(not catalog_script.presets("tripo", "image").any(func(item: Dictionary) -> bool: return item["id"] == "chat_image_1"), "Retired Tripo image models are not offered for new profiles")
	check(common.work_mode_index({"ui_mode": 1}) == 2 and common.work_mode_index({"work_mode": "default", "ui_mode": 1}) == 1, "Old Plan selections migrate safely and Default has a stable name")
	check(common.work_mode_index({"work_mode": "ask", "ui_mode": 3}) == 3 and common.MODE_IDS[3] == 0 and common.MODES[2] == "Plan", "Ask has a stable read-only identity without changing existing Plan selections")
	var meshy_text = script.cloud_payload({"kind": "meshy", "asset_kind": "mesh", "model": "latest"}, "bird")
	check(meshy_text.get("result", {}).get("endpoint") == "/openapi/v2/text-to-3d" and meshy_text["result"]["body"]["mode"] == "preview", "Meshy text-to-3D uses preview v2 schema")
	var meshy_image = script.cloud_payload({"kind": "meshy", "asset_kind": "mesh"}, "bird", "data:image/png;base64,fixture")
	check(meshy_image["result"]["endpoint"] == "/openapi/v1/image-to-3d" and meshy_image["result"]["body"]["should_texture"], "Meshy image-to-3D requests a textured GLB")
	var tripo_image = script.cloud_payload({"kind": "tripo", "asset_kind": "image"}, "bird")
	check(tripo_image["result"]["endpoint"] == "/generation/text-to-image" and tripo_image["result"]["body"]["output_format"] == "png", "Tripo image generation uses v3 and PNG output")
	check(not script.cloud_payload({"kind": "openai_image", "asset_kind": "image"}, "bird", "reference").get("ok", false), "OpenAI text-image profiles reject unsupported references before HTTP")
	var vault = FakeVault.new()
	var assets = script.new(node, vault)
	assets.test_http = true
	for provider in ["meshy", "tripo", "openai_image"]: assets.api_urls[provider] = mock_url + "/" + provider
	var cache = OS.get_user_data_dir().path_join("cloud-generation")
	assets.configure(cache)
	assets.api_urls["runware"] = mock_url + "/runware"
	vault.store("generation_runware", "generation-fixture-key")
	var runware_profile = {"id": "runware-image", "kind": "runware", "credential_id": "generation_runware", "asset_kind": "image"}
	check((await assets.verify_key(runware_profile, {})).get("ok", false), "One shared Runware credential validates image and 3D profiles without generating credits")
	vault.store("generation_runware", "invalid-fixture-key")
	check(not (await assets.verify_key(runware_profile, {})).get("ok", false), "Invalid Runware key is rejected by the authenticated ping")
	vault.store("generation_runware", "generation-fixture-key")
	assets.catalog_urls["runware"] = mock_url + "/catalog/index.json"
	var catalog_events = []
	var cloud_catalog = await assets.catalog(runware_profile, {}, "", func(event: Dictionary) -> void: catalog_events.append(event.duplicate(true)))
	check(cloud_catalog.get("ok", false) and cloud_catalog.get("credential_verified", false) and cloud_catalog.get("result", []).size() == 1 and cloud_catalog["result"][0]["id"] == "fixture:image@1", "Draft Runware catalog validates the key and filters out meshes and retired models")
	check(cloud_catalog["result"][0]["price"].get("amount") == 0.04 and cloud_catalog["result"][0]["price"].get("basis") == "from" and catalog_events.size() >= 2, "Runware schema prices load progressively without sending credentials to public docs")
	var mesh_catalog = await assets.catalog({"id": "runware-mesh", "kind": "runware", "credential_id": "generation_runware", "asset_kind": "mesh"}, {})
	check(mesh_catalog.get("result", []).size() == 1 and mesh_catalog["result"][0]["id"] == "fixture:mesh@1", "The same Runware key discovers the separate 3D catalog")
	var bad_catalog = await assets.catalog(runware_profile, {}, "invalid-fixture-key")
	check(not bad_catalog.get("ok", false) and vault.read("generation_runware") == "generation-fixture-key", "A failing draft credential cannot overwrite the saved shared key")
	var reference = "res://ai_test_reference.png"
	var transport = scripts["transport"].new(node)
	await transport.request(mock_url + "/artifact/image.png", HTTPClient.METHOD_GET, [], null, {"allow_http": true, "save_path": reference})
	for entry in [["meshy", "image", ""], ["meshy", "mesh", ""], ["meshy", "mesh", reference], ["tripo", "mesh", ""], ["tripo", "mesh", reference], ["tripo", "image", ""], ["openai_image", "image", ""]]:
		var profile = {"id": "fixture-" + entry[0], "kind": entry[0], "asset_kind": entry[1], "model": "", "destination": "res://ai_test_assets"}
		vault.store(profile["id"], "generation-fixture-key")
		var catalog = await assets.models(profile, {})
		check(catalog.get("ok", false) and catalog.get("credential_verified", false) and not catalog.get("result", []).is_empty(), "Provider credential check and model presets: " + str(entry))
		var submitted = await assets.submit(profile, "bird", entry[2], {})
		check(submitted.get("ok", false), "Native generation HTTP submission: " + str(entry))
		if not submitted.get("ok", false): continue
		var id = str(submitted["result"]["id"])
		var recovered = script.new(node, vault)
		recovered.configure(cache)
		check(not recovered.find_job(id).is_empty(), "Generation jobs survive runtime restart: " + str(entry))
		var completed = await assets.wait_for_job(id, profile, {}, 1)
		check(completed.get("ok", false) and completed.get("result", {}).get("status") == "completed", "Cloud download without API-key leakage and artifact validation: " + str(entry))
		if not completed.get("ok", false): continue
		check(FileAccess.file_exists(str(completed["result"].get("imported_path", ""))) and str(completed["result"].get("imported_path", "")).begins_with("res://ai_test_assets/bird_"), "Cloud asset is auto-imported under its object name: " + str(entry))
		var imported = assets.import_job(id, "res://ai_test_assets")
		check(imported.get("ok", false) and FileAccess.file_exists(str(imported.get("result", {}).get("path", ""))), "Generated PNG/GLB imports into project: " + str(entry))
		if entry[1] == "mesh":
			var document = GLTFDocument.new()
			var state = GLTFState.new()
			check(document.append_from_file(str(completed["result"]["file"]), state) == OK, "Provider GLB loads through Godot importer: " + str(entry))
		var wrong = profile.duplicate()
		wrong["id"] = "wrong-profile"
		check(not (await assets.refresh(id, wrong, {})).get("ok", false), "Saved generation job refuses a different credential profile")
	await _image_purpose_tests(assets, vault, cache)
	await _export_tests(assets, vault, cache)
	var profile = {"id": "fixture-tripo", "kind": "tripo", "asset_kind": "mesh"}
	for prompt in ["fail", "foreign"]:
		var submitted = await assets.submit(profile, prompt, "", {})
		var outcome = await assets.refresh(str(submitted.get("result", {}).get("id", "")), profile, {})
		check(not outcome.get("ok", true), "Cloud generation failure or untrusted CDN is rejected: " + prompt)
	check((await assets.submit(profile, "bird", "", {"cancelled": true})).get("code") == "cancelled", "Pre-cancelled generation cannot submit a paid task")
	var lost = await assets.submit(profile, "lost-submit", "", {})
	check(lost.get("code") == "submission_unknown" and lost.get("result", {}).get("status") == "submission_unknown", "A dropped submission response records uncertainty instead of pretending that the provider rejected it")
	var recovered = script.new(node, vault)
	recovered.configure(cache)
	var lost_id = str(lost.get("result", {}).get("id", ""))
	check(not lost_id.is_empty() and recovered.find_job(lost_id).get("status") == "submission_unknown", "An uncertain paid submission survives restart in the generation job list")
	check((await recovered.refresh(lost_id, profile, {})).get("code") == "submission_unknown", "A job without its provider ID cannot be polled as a new or fictitious task")
	var previous_cache = assets.cache_directory
	var previous_count = assets.jobs.size()
	assets.cache_directory = reference
	var unsaved = await assets.submit(profile, "blocked-save", "", {})
	assets.cache_directory = previous_cache
	var counts = await transport.request(mock_url + "/fixture-submissions", HTTPClient.METHOD_GET, [], null, {"allow_http": true})
	check(unsaved.get("code") == "checkpoint_failed" and assets.jobs.size() == previous_count and counts.get("json", {}).get("blocked-save", 0) == 0, "Generation cannot reach the provider when its pre-submission checkpoint cannot be saved")
	check(counts.get("json", {}).get("lost-submit", 0) == 1, "Recovering and inspecting an uncertain submission never sends another paid POST")
	var interrupted_cache = cache.path_join("interrupted-submit")
	common.atomic_json(interrupted_cache.path_join("jobs.json"), [{"id": "interrupted-job", "status": "submitting"}])
	recovered.configure(interrupted_cache)
	check(recovered.find_job("interrupted-job").get("status") == "submission_unknown", "Restart converts an unfinished submission checkpoint into explicit uncertainty")
	var runware_submission = runware_profile.duplicate(true)
	runware_submission["model"] = "runware:fixture@1"
	var runware_lost = await assets.submit(runware_submission, "lost-runware-submit", "", {})
	check(runware_lost.get("code") == "submission_unknown" and not str(runware_lost.get("result", {}).get("external_id", "")).is_empty(), "Runware preserves its locally assigned task UUID when the submission response is lost")
	var recovery_profile = runware_submission.duplicate(true)
	recovery_profile["destination"] = "res://ai_test_assets"
	var uncertain = await assets.submit(recovery_profile, "http500-result", "", {})
	check(uncertain.get("code") == "submission_unknown", "Runware HTTP 500 acknowledgement does not falsely confirm a submission")
	var recovered_result = await assets.refresh(str(uncertain["result"]["id"]), recovery_profile, {})
	check(recovered_result.get("ok", false) and recovered_result.get("result", {}).get("status") == "completed" and recovered_result["result"].get("cost_usd") == 0.02 and FileAccess.file_exists(recovered_result["result"].get("file", "")), "Contradictory HTTP 500 success recovers and downloads the exact existing job")
	await assets.wait_for_job(str(uncertain["result"]["id"]), recovery_profile, {})
	var recovery_counts = await transport.request(mock_url + "/fixture-submissions", HTTPClient.METHOD_GET, [], null, {"allow_http": true})
	check(recovery_counts.get("json", {}).get("http500-result") == 1, "Runware recovery and waiting submit no duplicate paid generation")
	var invalid = await assets.submit({"id": "fixture-openai_image", "kind": "openai_image", "asset_kind": "image"}, "invalid", "", {})
	check(not invalid.get("ok", true) and assets.jobs[-1].get("status") == "failed", "Invalid base64 image output is recorded as failure without import")
	vault.erase("fixture-tripo")
	check((await assets.submit(profile, "bird", "", {})).get("code") == "missing_credentials", "Cloud generation requires this profile's own API key")
	DirAccess.remove_absolute(reference)

func _export_tests(assets: RefCounted, vault: RefCounted, cache: String) -> void:
	var exports = scripts["asset_exports"]
	var mesh_job: Dictionary = assets.jobs.filter(func(item: Dictionary) -> bool: return item["kind"] == "mesh")[0]
	var original = FileAccess.get_file_as_bytes(mesh_job["file"])
	for format in ["obj", "stl", "ply", "gltf"]:
		var result = await assets.export_job(mesh_job["id"], {}, format, {})
		check(result.get("ok", false) and result.get("result", {}).get("status") == "completed", "Real GLB exports to native " + format)
		if not result.get("ok", false): continue
		check(FileAccess.file_exists(str(result["result"].get("project_path", ""))) and str(result["result"].get("project_path", "")).get_base_dir() == str(mesh_job.get("imported_path", "")).get_base_dir(), "Export " + format + " is filed beside the named original")
		var path = str(result["result"]["file"])
		if format == "stl":
			var file = FileAccess.open(path, FileAccess.READ)
			file.seek(80)
			check(file.get_32() == 1 and file.get_length() == 134, "Binary STL contains the real source triangle and valid record length")
		elif format == "obj": check(FileAccess.get_file_as_string(path).contains("f 1 2 3") and FileAccess.get_file_as_string(path).contains("v -1.000000000 0.000000000 0.000000000"), "OBJ contains real vertices and topology rather than a renamed GLB")
		elif format == "ply": check(FileAccess.get_file_as_string(path).contains("element vertex 3") and FileAccess.get_file_as_string(path).contains("element face 1"), "PLY declares the correct geometry counts")
		else:
			var archive = ZIPReader.new()
			var opened = archive.open(path) == OK
			var document: Variant = scripts["common"].parse_json(archive.read_file("model.gltf").get_string_from_utf8()) if opened else {}
			var buffers: Array = document.get("buffers", [])
			check(opened and not buffers.is_empty() and buffers.all(func(buffer: Dictionary) -> bool: return archive.file_exists(str(buffer.get("uri", "")))), "glTF export bundles its JSON and referenced binary dependencies")
			archive.close()
	var cached_local = await assets.export_job(mesh_job["id"], {}, "gltf", {})
	var repeated_local = await assets.export_job(mesh_job["id"], {}, "gltf", {})
	check(cached_local.get("result", {}).get("file") == repeated_local.get("result", {}).get("file"), "Repeated native export reuses its immutable-source cache instead of duplicating files")
	check(FileAccess.get_file_as_bytes(mesh_job["file"]) == original, "All exports preserve original GLB bytes")
	for provider in ["meshy", "tripo"]:
		var job: Dictionary = assets.jobs.filter(func(item: Dictionary) -> bool: return item["provider"] == provider and item["kind"] == "mesh")[0]
		var profile = {"id": job["profile_id"], "kind": provider}
		vault.store(profile["id"], "generation-fixture-key")
		var result = await assets.export_job(job["id"], profile, "fbx", {})
		check(result.get("ok", false) and str(result.get("result", {}).get("file", "")).ends_with(".fbx"), "Documented " + provider + " conversion task downloads a validated FBX without credentials on CDN")
		check(result.get("ok", false) and FileAccess.file_exists(str(result.get("result", {}).get("project_path", ""))), "Converted FBX is saved under the configured object folder: " + provider)
		var recovered = scripts["assets"].new(assets.owner, vault)
		recovered.configure(cache)
		recovered.test_http = true
		recovered.api_urls = assets.api_urls.duplicate()
		check((await recovered.export_job(job["id"], profile, "fbx", {})).get("ok", false), "Cached conversion survives restart and avoids a duplicate paid POST: " + provider)
	for format in ["usdz", "blend", "3mf"]:
		var profile = {"id": mesh_job["profile_id"], "kind": "meshy"}
		if format == "3mf":
			var token = {"cancelled": false}
			_cancel_export_when_submitted(mesh_job, format, token, assets.owner)
			var interrupted = await assets.export_job(mesh_job["id"], profile, format, token)
			check(interrupted.get("code") == "cancelled" and not str(mesh_job.get("exports", {}).get(format, {}).get("external_id", "")).is_empty(), "Cancelled conversion wait retains its provider ID for later resume")
		var result = await assets.export_job(mesh_job["id"], profile, format, {})
		check(result.get("ok", false) and str(result.get("result", {}).get("file", "")).ends_with("." + format), "Cloud conversion checks the actual " + format.to_upper() + " container")
	var unknown: Dictionary = mesh_job.duplicate(true)
	unknown["id"] = scripts["common"].uid()
	unknown["exports"] = {"fbx": {"status": "unknown", "endpoint": "/openapi/v1/convert", "external_id": "", "format": "fbx", "file": ""}}
	assets.jobs.append(unknown)
	var original_profile = {"id": mesh_job["profile_id"], "kind": "meshy"}
	check((await assets.export_job(unknown["id"], original_profile, "fbx", {})).get("code") == "conversion_unknown", "Lost conversion response blocks blind duplicate paid submissions")
	check((await assets.export_job(unknown["id"], original_profile, "fbx", {}, "convert-fbx")).get("ok", false), "Existing task ID recovers a lost conversion response through GET without a paid POST")
	check(not (await assets.export_job(mesh_job["id"], {}, "exe", {})).get("ok", false), "Export rejects unsupported formats")
	var fake = cache.path_join("not-fbx.part")
	var fake_file = FileAccess.open(fake, FileAccess.WRITE)
	fake_file.store_string("<html>server error</html>")
	fake_file.close()
	check(not exports.validate_export(fake, "fbx").get("ok", false), "Provider HTML cannot masquerade as FBX")
	var archive_path = cache.path_join("traversal.zip")
	var unsafe_zip = ZIPPacker.new()
	unsafe_zip.open(archive_path)
	unsafe_zip.start_file("../model.fbx")
	unsafe_zip.write_file("; FBX fake".to_utf8_buffer())
	unsafe_zip.close_file()
	unsafe_zip.close()
	check(not exports.validate_export(archive_path, "fbx").get("ok", false), "Export bundles reject parent traversal paths")


func _cancel_export_when_submitted(job: Dictionary, format: String, cancel: Dictionary, node: Node) -> void:
	var deadline = Time.get_ticks_msec() + 10000
	while str(job.get("exports", {}).get(format, {}).get("external_id", "")).is_empty() and Time.get_ticks_msec() < deadline:
		await node.get_tree().process_frame
	cancel["cancelled"] = true

func _file_registry_tests(node: Node) -> void:
	var registry = scripts["file_registry"].new(node)
	var scratch = OS.get_user_data_dir().path_join("file-registry-" + scripts["common"].uid())
	registry.configure(scratch)
	var sources = scratch.path_join("sources")
	DirAccess.make_dir_recursive_absolute(sources)
	registry.permit(sources, true)
	var source = sources.path_join("screenshot-a.png")
	var image = Image.create(40, 20, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	image.save_png(source)
	for extension in ["jpg", "webp"]:
		var output_path = sources.path_join("dimension-probe." + extension)
		if extension == "jpg": image.save_jpg(output_path)
		else: image.save_webp(output_path)
		check(scripts["file_registry"].image_dimensions(output_path) == Vector2i(40, 20), "Image budget preflight reads native dimensions before decoding: " + extension)
		DirAccess.remove_absolute(output_path)
	var registered = registry.register_file(source, "conversation-a")
	check(registered.get("ok", false), "File registry captures an accessible image revision")
	if not registered.get("ok", false): return
	var id = str(registered["result"]["id"])
	check(registry.describe(id, "conversation-b").is_empty(), "A file ID cannot leak across unrelated conversations")
	check(registry.image_attachment(id, "conversation-a").get("mimeType") == "image/png", "Selected file snapshots provide actual image pixels for vision")
	image.fill(Color.BLUE)
	image.save_png(source)
	var original = Image.load_from_file(registry.describe(id, "conversation-a")["path"])
	check(original.get_pixel(1, 1) == Color.RED, "A file mention retains the captured version when its source changes")
	var updated = registry.register_file(source, "conversation-a")
	check(updated.get("result", {}).get("id") != id, "A changed source creates a separate stable revision ID")
	check(registry.register_file(source, "conversation-a").get("result", {}).get("id") == updated["result"]["id"], "Repeated registration reuses the same file revision")
	check(registry.pin(id, "conversation-a", true) == OK and registry.catalog("conversation-b", true).is_empty(), "Pinned references remain conversation scoped")
	var recovery = scripts["file_registry"].new(node)
	recovery.configure(scratch)
	check(recovery.allowed(sources.path_join("new-file.png")) and recovery.catalog("conversation-a", true).size() == 1, "Folder grants and pinned file references survive restart")
	check(not recovery.describe(id, "conversation-a").is_empty(), "File references and snapshots survive registry restart")
	var searched = await registry.search({"path": sources, "kind": "image", "limit": 2}, "conversation-a")
	check(searched.get("files", []).size() == 1 and searched.get("result", [])[0].get("name") == "screenshot-a.png", "Native file search returns actual matching preview cards")
	check((await registry.search({}, "conversation-a", {"cancelled": true})).get("code") == "cancelled", "File discovery can be cancelled before reading storage")
	check(not registry.allowed("/not-authorized/secret.png") and not registry.allowed(sources.path_join(".git/config")), "Storage discovery rejects ungranted and hidden private roots")
	var model_path = sources.path_join("model.gltf")
	var buffer_path = sources.path_join("mesh.bin")
	var buffer = FileAccess.open(buffer_path, FileAccess.WRITE)
	buffer.store_string("before"); buffer.close()
	scripts["common"].atomic_json(model_path, {"asset": {"version": "2.0"}, "buffers": [{"uri": "mesh.bin", "byteLength": 6}]})
	var first_model = registry.register_file(model_path, "conversation-a")
	buffer = FileAccess.open(buffer_path, FileAccess.WRITE)
	buffer.store_string("after!"); buffer.close()
	var second_model = registry.register_file(model_path, "conversation-a")
	check(first_model.get("ok", false) and second_model.get("ok", false) and first_model["result"]["id"] != second_model["result"]["id"], "glTF dependency edits create a new revision even when the JSON is unchanged")
	check(FileAccess.get_file_as_string(str(first_model["result"]["path"]).get_base_dir().path_join("mesh.bin")) == "before", "Earlier glTF buffer snapshots remain immutable")
	scripts["common"].atomic_json(model_path, {"asset": {"version": "2.0"}, "buffers": null})
	check(not registry.register_file(model_path, "conversation-a").get("ok", false), "Malformed glTF dependency metadata returns a tool failure without throwing a script error")
	var json = FileAccess.get_file_as_string(registry.directory.path_join("index.json"))
	check(not "base64" in json and not "data:image" in json and FileAccess.file_exists(registered["result"]["preview"]), "Registry persists metadata and thumbnails without duplicating binary blobs in JSON")
	for definition in scripts["file_registry"].definitions(): check(scripts["tool_registry"].new([definition]).error.is_empty(), "File tool schema is discoverable: " + str(definition["name"]))

func _diff_tests() -> void:
	var diff = scripts["diff"]
	for sample in [["a\nb\nc\n", "a\nB\nc\nd\n", 2, 1], ["", "one\ntwo\n", 2, 0], ["one\ntwo\n", "", 0, 2], ["same\n", "same\n", 0, 0], ["line\n", "line", 1, 1], ["a\nb\na\n", "a\na\n", 0, 1]]:
		var compared = diff.compare(sample[0], sample[1])
		check(compared.get("exact", false) and compared.get("added") == sample[2] and compared.get("removed") == sample[3], "Exact line diff counts insertions/deletions: " + str(sample))
		var reconstructed = []
		for op in compared.get("operations", []):
			if op[0] != "-": reconstructed.append(op[1])
		check(reconstructed == diff.lines(sample[1]), "Applying diff operations reconstructs the actual updated file")
	var unified = diff.unified("player.gd", diff.compare("a\nb\nc\n", "a\nB\nc\n"))
	check("@@ -1,3 +1,3 @@" in unified and "-b\n+B" in unified and not "-a" in unified, "Unified diff retains unchanged context instead of deleting the entire original")
	check(not diff.compare("a\n".repeat(20001), "b\n").get("exact", true), "Oversized diffs report a bound instead of fabricated line totals")
	var review_before = "a\nb\nc\nd\ne\nf\ng\nh\ni\nj\nk\nl\n"
	var review_after = "a\nB\nc\nd\ne\nf\ng\nh\ni\nJ\nk\nl\n"
	var reviewed = diff.compare(review_before, review_after)
	var spans = diff.hunks(reviewed)
	check(spans.size() == 2 and spans[0]["added"] == 1 and spans[1]["removed"] == 1 and spans[1]["new_start"] == 7, "Distant changes become separate reviewable hunks with their own line locations")
	check(diff.select(reviewed, [0]) == "a\nB\nc\nd\ne\nf\ng\nh\ni\nj\nk\nl\n" and diff.select(reviewed, [1]) == "a\nb\nc\nd\ne\nf\ng\nh\ni\nJ\nk\nl\n", "Accepting a hunk applies only its lines and reverts the rest")
	check(diff.select(reviewed, [0, 1]) == review_after and diff.select(reviewed, []) == review_before, "Selecting every or no hunk reproduces the proposed or the original file")
	var newline_change = diff.compare("a\nb\n", "a\nB")
	check(diff.select(newline_change, [0]) == "a\nB" and diff.select(newline_change, []) == "a\nb\n", "Partial review preserves the original trailing newline unless its hunk is accepted")
	var newline_only = diff.compare("a\n", "a")
	check(diff.select(newline_only, [0]) == "a" and diff.select(newline_only, []) == "a\n", "A newline-only change is still a selectable hunk")
	check(scripts["panel"]._match_eol("a\nb\n", "a\r\nb\r\n") == "a\r\nb\r\n" and scripts["panel"]._match_eol("a\nb\n", "a\nb\n") == "a\nb\n", "Reviewed writes keep the proposed file's CRLF convention")

func _store_tests(node: Node) -> void:
	var service = scripts["store"].new(node)
	service.api_url = mock_url + "/store"
	service.test_http = true
	var result = await service.search("fixture", 1, {})
	check(result.get("ok", false) and result.get("store_items", []).size() == 1 and result["store_items"][0]["id"] == "fixture/fixture-addon", "Store search uses the editor v1 schema and publisher/slug identity")
	result = await service.describe("fixture/fixture-addon", {})
	check(result.get("ok", false) and result["result"]["releases"].size() == 1 and result["result"]["releases"][0]["version"] == "1.0", "Store filters incompatible releases before offering installation")
	check(not (await service.describe("../outside", {})).get("ok", false), "Store IDs cannot inject paths")
	var transport = scripts["transport"].new(node)
	result = await transport.request(mock_url + "/store/redirect", HTTPClient.METHOD_GET, ["Authorization: Bearer must-not-follow"], null, {"allow_http": true, "follow_redirects": true})
	check(result.get("ok", false) and result.get("bytes", PackedByteArray()).size() > 0, "Redirected downloads never forward credentials to the artifact host")
	result = await transport.request(mock_url + "/store/loop", HTTPClient.METHOD_GET, [], null, {"allow_http": true, "follow_redirects": true})
	check(not result.get("ok", false), "Download redirect loops stop at a finite limit")
	var path = OS.get_user_data_dir().path_join("store-zip-test.zip")
	for filename in ["../escape.gd", "addons/fixture/plugin.cfg"]:
		var writer = ZIPPacker.new()
		writer.open(path)
		writer.start_file(filename)
		writer.write_file("fixture".to_utf8_buffer())
		writer.close_file()
		writer.close()
		var inspected = scripts["store"].zip_manifest(path)
		check(inspected.get("ok", false) == (not filename.begins_with("..")), "ZIP preflight validates paths before extraction: " + filename)
	for machine in [183, 62]:
		var native_path = OS.get_user_data_dir().path_join("store-native-test.zip")
		var native_zip = ZIPPacker.new()
		native_zip.open(native_path)
		native_zip.start_file("release/addons/native/native.gdextension")
		native_zip.write_file("[libraries]\nandroid.debug.arm64 = \"res://addons/native/bin/libnative.so\"\n".to_utf8_buffer())
		native_zip.close_file()
		var elf = PackedByteArray()
		elf.resize(20)
		elf[0] = 127; elf[1] = 69; elf[2] = 76; elf[3] = 70; elf[4] = 2; elf[5] = 1
		elf.encode_u16(18, machine)
		native_zip.start_file("release/addons/native/bin/libnative.so")
		native_zip.write_file(elf)
		native_zip.close_file()
		native_zip.close()
		var native_manifest = scripts["store"].zip_manifest(native_path)
		var native_reader = ZIPReader.new()
		native_reader.open(native_path)
		var native_supported = scripts["store"]._android_native_support(native_reader, native_manifest.get("result", []))
		native_reader.close()
		check(native_supported.get("ok", false) == (machine == 183), "Android GDExtension requires referenced ARM64 ELF instead of rejecting all native addons: " + str(machine))
	var release_archive = OS.get_environment("GODOT_AI_TERRAIN3D_ZIP")
	if not release_archive.is_empty():
		var release_manifest = scripts["store"].zip_manifest(release_archive)
		check(release_manifest.get("ok", false), "Actual Terrain3D release passes ZIP preflight")
		if release_manifest.get("ok", false):
			var release_reader = ZIPReader.new()
			if release_reader.open(release_archive) == OK:
				check(scripts["store"]._android_native_support(release_reader, release_manifest["result"]).get("ok", false), "Actual Terrain3D release contains a referenced Android ARM64 GDExtension")
				release_reader.close()
	for definition in scripts["store"].definitions(): check(scripts["tool_registry"].new([definition]).error.is_empty(), "Store tool schema is discoverable: " + str(definition["name"]))
