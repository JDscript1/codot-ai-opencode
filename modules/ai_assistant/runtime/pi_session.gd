@tool
extends RefCounted
## App-owned Pi RPC session. The Agent AI chat remains the UI; Pi owns the
## provider agent loop and receives Godot tools through the local MCP server.

static var Common: GDScript

signal event(value: Dictionary)
signal changed()

var bridge: Node
var project_directory := ""
var state: Dictionary = {}
var providers: Array = []
var targets: Dictionary = {}
var active_target: Dictionary = {}
var last_poll_msec := 0

func configure(native_bridge: Node, project: String) -> void:
	bridge = native_bridge
	project_directory = project

func _request(action: String, args: Dictionary = {}) -> Dictionary:
	if not is_instance_valid(bridge) or not bridge.has_method("linux_runtime_request"):
		return _failure("Pi este disponibil doar în editorul Android.", "pi_unavailable")
	var payload := args.duplicate(true)
	payload["project_directory"] = project_directory
	var result: Variant = bridge.call("linux_runtime_request", action, payload)
	return result if result is Dictionary else _failure("Răspuns Pi invalid.", "pi_protocol_error")

func refresh() -> Dictionary:
	state = _request("pi_status")
	changed.emit()
	return state

func install() -> Dictionary:
	return _request("pi_install")

func cancel() -> Dictionary:
	return _request("pi_cancel")

func start(config: Dictionary) -> Dictionary:
	active_target = config.get("target", {})
	var result = _request("pi_start", {
		"profiles": providers,
		"provider": str(active_target.get("provider", "")),
		"model": str(active_target.get("model", "")),
		"mode": str(config.get("mode", "agent")),
		"mcp_port": int(config.get("mcp_port", 0)),
		"mcp_token": str(config.get("mcp_token", "")),
		"session_id": str(config.get("session_id", "app")),
	})
	state = result
	changed.emit()
	return result

func send(command: Dictionary) -> Dictionary:
	return _request("pi_send", {"command": command})

func poll() -> Dictionary:
	last_poll_msec = Time.get_ticks_msec()
	var result = _request("pi_poll")
	if result.get("ok", false):
		state["running"] = result.get("running", false)
		state["status"] = result.get("status", state.get("status", ""))
		for value in result.get("events", []):
			if value is Dictionary: event.emit(value)
	return result

func abort() -> Dictionary:
	return _request("pi_abort")

func stop() -> Dictionary:
	var result = _request("pi_stop")
	state = result
	active_target = {}
	changed.emit()
	return result

func running() -> bool:
	return bool(state.get("running", false))

func installed() -> bool:
	return bool(state.get("installed", false))

func target(profile_id: String, model_id: String) -> Dictionary:
	return targets.get(profile_id + "|" + model_id, {}).duplicate(true)

func signature() -> String:
	return JSON.stringify(providers).sha256_text()

func build_profiles(app_profiles: Array, vault: RefCounted) -> Array:
	providers = []
	targets = {}
	for profile in app_profiles:
		if not profile is Dictionary: continue
		var kind = str(profile.get("kind", "chat"))
		if kind in ["siwc", "companion"]: continue
		var secret = vault.read(str(profile.get("id", ""))) if vault != null else ""
		var local = bool(profile.get("local", false)) or str(profile.get("hosting", "")) == "local"
		if secret.is_empty() and not local: continue
		var groups := {}
		for model in profile.get("models", []):
			if not model is Dictionary: continue
			var model_id = str(model.get("id", ""))
			if model_id.is_empty(): continue
			var route = _route(profile, model)
			if route.is_empty(): continue
			var key = route["api"] + "|" + route["base_url"]
			if not groups.has(key): groups[key] = {"api": route["api"], "base_url": route["base_url"], "models": []}
			groups[key]["models"].append(model)
		for group_key in groups:
			var group: Dictionary = groups[group_key]
			var provider_id = _provider_id(profile, group)
			var models := []
			for model in group["models"]:
				var model_id = str(model.get("id", ""))
				var capabilities: Dictionary = model.get("capabilities", {}) if model.get("capabilities", {}) is Dictionary else {}
				var efforts: Array = model.get("efforts", []) if model.get("efforts", []) is Array else []
				var input := ["text"]
				if bool(capabilities.get("vision", false)): input.append("image")
				models.append({
					"id": model_id,
					"name": str(model.get("name", model_id)),
					"reasoning": bool(capabilities.get("reasoning", false)) or not efforts.is_empty(),
					"input": input,
					"context": int(model.get("context", 0)),
					"max_tokens": int(model.get("max_output_tokens", 0)),
				})
				targets[str(profile.get("id", "")) + "|" + model_id] = {"provider": provider_id, "model": model_id}
			providers.append({
				"id": provider_id,
				"name": str(profile.get("name", provider_id)),
				"api": group["api"],
				"base_url": group["base_url"],
				"key": secret if not secret.is_empty() else "pi-local",
				"models": models,
			})
	return providers

func _route(profile: Dictionary, model: Dictionary) -> Dictionary:
	var protocol = str(model.get("protocol", ""))
	var transport = str(model.get("transport_url", "")).strip_edges().trim_suffix("/")
	var api = ""
	var base = transport
	if str(profile.get("issuer", "")) == "opencode" or not protocol.is_empty():
		api = {"chat-completions": "openai-completions", "responses": "openai-responses", "messages": "anthropic-messages", "generate-content": "google-generative-ai"}.get(protocol, "")
	if api.is_empty():
		api = {"chat": "openai-completions", "responses": "openai-responses", "anthropic": "anthropic-messages", "gemini": "google-generative-ai"}.get(str(profile.get("kind", "chat")), "")
		base = str(profile.get("url", "")).strip_edges().trim_suffix("/")
	if api.is_empty() or base.is_empty(): return {}
	return {"api": api, "base_url": base}

func _provider_id(profile: Dictionary, group: Dictionary) -> String:
	var raw = str(profile.get("id", "provider")) + "_" + str(group.get("api", "api"))
	var expression = RegEx.new()
	expression.compile("[^a-z0-9._-]+")
	var clean = expression.sub(raw.to_lower(), "-", true).trim_prefix("-").trim_suffix("-")
	var digest = (str(group.get("base_url", "")) + "|" + str(group.get("api", ""))).sha256_text().left(10)
	return ("app_" + clean + "_" + digest).substr(0, 96)

func _failure(message: String, code: String) -> Dictionary:
	return {"ok": false, "error": message, "code": code}
