@tool
extends RefCounted

static var Common: GDScript
static var Transport: GDScript
static var ModelPricing: GDScript

const CATALOG = [
	{"id": "openai", "name": "OpenAI", "kind": "responses", "url": "https://api.openai.com/v1", "prefix": "sk-proj-"},
	{"id": "anthropic", "name": "Anthropic Claude", "kind": "anthropic", "url": "https://api.anthropic.com/v1", "prefix": "sk-ant-"},
	{"id": "gemini", "name": "Google Gemini", "kind": "gemini", "url": "https://generativelanguage.googleapis.com/v1beta", "prefix": "AIza"},
	{"id": "deepseek", "name": "DeepSeek", "kind": "chat", "url": "https://api.deepseek.com", "prefix": ""},
	{"id": "openrouter", "name": "OpenRouter", "kind": "chat", "url": "https://openrouter.ai/api/v1", "prefix": "sk-or-v1-"},
	{"id": "qwen", "name": "Qwen International", "kind": "chat", "url": "https://dashscope-intl.aliyuncs.com/compatible-mode/v1", "prefix": ""},
	{"id": "qwen-cn", "name": "Qwen China", "kind": "chat", "url": "https://dashscope.aliyuncs.com/compatible-mode/v1", "prefix": ""},
	{"id": "kimi", "name": "Kimi / Moonshot", "kind": "chat", "url": "https://api.moonshot.ai/v1", "prefix": ""},
	{"id": "mistral", "name": "Mistral", "kind": "chat", "url": "https://api.mistral.ai/v1", "prefix": ""},
	{"id": "groq", "name": "Groq", "kind": "chat", "url": "https://api.groq.com/openai/v1", "prefix": "gsk_"},
	{"id": "xai", "name": "xAI", "kind": "chat", "url": "https://api.x.ai/v1", "prefix": "xai-"},
	{"id": "zai", "name": "Z.AI / GLM", "kind": "chat", "url": "https://api.z.ai/api/paas/v4", "prefix": ""},
	{"id": "minimax", "name": "MiniMax", "kind": "chat", "url": "https://api.minimax.io/v1", "prefix": ""},
	{"id": "nvidia", "name": "NVIDIA NIM", "kind": "chat", "url": "https://integrate.api.nvidia.com/v1", "prefix": "nvapi-"},
	{"id": "siliconflow", "name": "SiliconFlow", "kind": "chat", "url": "https://api.siliconflow.cn/v1", "prefix": ""},
	{"id": "ollama", "name": "Ollama", "kind": "chat", "url": "http://127.0.0.1:11434/v1", "prefix": "", "local": true},
	{"id": "lmstudio", "name": "LM Studio", "kind": "chat", "url": "http://127.0.0.1:1234/v1", "prefix": "", "local": true},
	{"id": "llamacpp", "name": "llama.cpp", "kind": "chat", "url": "http://127.0.0.1:8080/v1", "prefix": "", "local": true},
	{"id": "custom", "name": "OpenAI-compatible", "kind": "chat", "url": "", "prefix": ""},
]

var transport: RefCounted
var vault: RefCounted
var owner: Node

func _init(node: Node = null, secret_store: RefCounted = null) -> void:
	owner = node
	transport = Transport.new(node)
	vault = secret_store

static func private_ipv4(address: String) -> bool:
	var parts = address.split(".")
	if parts.size() != 4: return false
	for part in parts:
		if not part.is_valid_int() or int(part) < 0 or int(part) > 255: return false
	return int(parts[0]) == 10 or (int(parts[0]) == 172 and int(parts[1]) in range(16, 32)) or (int(parts[0]) == 192 and int(parts[1]) == 168)

static func hosting(profile: Dictionary) -> String:
	if profile.get("hosting") in ["cloud", "local"]: return profile["hosting"]
	if profile.get("issuer", profile.get("id", "")) in ["ollama", "lmstudio", "llamacpp"]: return "local"
	var parsed = Common.parse_url(str(profile.get("url", "")), true)
	var host = str(parsed.get("host", "")).to_lower()
	return "local" if host in ["localhost", "127.0.0.1", "::1"] or host.ends_with(".local") or private_ipv4(host) else "cloud"

static func endpoint(profile: Dictionary) -> Dictionary:
	var url = str(profile.get("url", "") if profile.get("url") != null else "").strip_edges().trim_suffix("/")
	var issuer = str(profile.get("issuer", ""))
	if url.is_empty():
		for entry in CATALOG:
			if entry["id"] == issuer and not entry.get("local", false):
				url = str(entry["url"])
				break
	if issuer in ["lmstudio", "ollama", "llamacpp"]:
		var normalized = local_endpoint(url, issuer)
		if not normalized.get("ok", false): return normalized
		url = str(normalized["result"])
	var parsed = Common.parse_url(url, bool(profile.get("allow_http", false)))
	return Common.success(url) if parsed.get("ok", false) else parsed

static func pricing_profile(profile: Dictionary) -> Dictionary:
	var result = profile.duplicate(true)
	var resolved = endpoint(profile)
	result["official_pricing"] = false
	for entry in CATALOG:
		if entry["id"] == profile.get("issuer") and resolved.get("ok", false) and resolved.get("result") == entry["url"]: result["official_pricing"] = true
	return result

static func local_endpoint(value: String, issuer: String) -> Dictionary:
	var url = value.strip_edges().trim_suffix("/")
	if url.is_empty() or "?" in url or "#" in url: return Common.failure("Introdu IP-ul sau adresa serverului, fără parametri suplimentari.", "invalid_url")
	if not "://" in url:
		var raw_authority = url.get_slice("/", 0)
		var suffix = url.substr(raw_authority.length())
		if raw_authority.is_valid_ip_address() and ":" in raw_authority: raw_authority = "[" + raw_authority + "]"
		var has_port = "]:" in raw_authority if raw_authority.begins_with("[") else ":" in raw_authority
		if not has_port: raw_authority += ":" + str({"lmstudio": 1234, "ollama": 11434, "llamacpp": 8080}.get(issuer, 1234))
		url = "http://" + raw_authority + suffix
	var parsed = Common.parse_url(url, true)
	if not parsed.get("ok", false): return parsed
	var path = str(parsed["path"]).trim_suffix("/")
	for suffix in ["/chat/completions", "/models"]:
		if path.ends_with("/v1" + suffix): path = path.trim_suffix(suffix)
	if path in ["", "/", "/api", "/api/tags", "/api/ps", "/api/v0", "/api/v0/models", "/api/v1"]: path = "/v1"
	elif not path.ends_with("/v1"): path += "/v1"
	var host = str(parsed["host"])
	var authority = "[" + host + "]" if ":" in host else host
	return Common.success("%s://%s:%s%s" % [parsed["scheme"], authority, parsed["port"], path])

static func connection_error(profile: Dictionary, result: Dictionary, android: bool = false) -> String:
	var parsed = Common.parse_url(str(profile.get("url", "")), true)
	var host = str(parsed.get("host", ""))
	if result.get("code") == "cancelled": return "Verificare oprită."
	var local = hosting(profile) == "local"
	if int(result.get("status", 0)) in [401, 403]: return "Serverul este accesibil, dar cere un token valid. Introdu tokenul în Cheie API." if local else "Cheia API nu a fost acceptată de " + str(profile.get("name", "furnizor")) + ". Verifică cheia și furnizorul selectat."
	if android and host in ["localhost", "127.0.0.1", "::1"]: return "Adresa locală indică acest dispozitiv. Pentru serverul de pe calculator introdu IP-ul Wi-Fi al calculatorului."
	if host.begins_with("169.254."): return "Adresa nu răspunde. Folosește IPv4-ul adaptorului Wi-Fi activ al calculatorului."
	if result.get("code") in ["timeout", "connection_failed"]:
		return "Serverul nu răspunde. Verifică IP-ul actual, aceeași rețea Wi-Fi/hotspot și accesul LAN al serverului." if local else "Furnizorul nu răspunde. Verifică accesul la internet și reîncearcă actualizarea modelelor."
	if int(result.get("status", 0)) == 429: return "Furnizorul a limitat cererile. Reîncearcă actualizarea modelelor mai târziu."
	if int(result.get("status", 0)) == 404: return "Ruta API nu este disponibilă. Folosește adresa serverului cu /v1." if local else "Ruta API nu este disponibilă. Verifică furnizorul și adresa configurată."
	return str(result.get("error", "Conexiunea nu a putut fi verificată."))

static func inference_options(profile: Dictionary, cancel: Dictionary = {}) -> Dictionary:
	var local = hosting(profile) == "local"
	return {"allow_http": profile.get("allow_http", false), "cancel": cancel, "connect_timeout": 8 if local else 10, "first_response_timeout": 300 if local else 180, "idle_timeout": 180 if local else 120, "timeout": 1800 if local else 900}

static func lan_targets(addresses: Array) -> Array:
	# An explicit search covers at most two private /24 segments, never the Internet.
	var prefixes = []
	for address in addresses:
		if not private_ipv4(str(address)): continue
		var prefix = str(address).rsplit(".", true, 1)[0]
		if prefix not in prefixes and prefixes.size() < 2: prefixes.append(prefix)
	var result = []
	# Probe the device's own LAN address first, then the remaining hosts. This
	# keeps a reachable server visible even when a slow network hits the deadline.
	for address in addresses:
		if private_ipv4(str(address)) and str(address).rsplit(".", true, 1)[0] in prefixes:
			for port in [1234, 11434, 8080]: result.append({"host": str(address), "port": port})
	for prefix in prefixes:
		for last in range(1, 255):
			for port in [1234, 11434, 8080]:
				var target = {"host": prefix + "." + str(last), "port": port}
				if target not in result: result.append(target)
	return result

static func lan_addresses(interfaces: Array) -> Array:
	var wifi = []
	var others = []
	for interface in interfaces:
		var name = str(interface.get("name", "")).to_lower()
		var preferred = name.contains("wlan") or name.contains("wifi")
		for address in interface.get("addresses", []):
			if not private_ipv4(str(address)): continue
			var bucket = wifi if preferred else others
			if str(address) not in bucket: bucket.append(str(address))
	return wifi + others

func discover_lan(cancel: Dictionary) -> Dictionary:
	var addresses = lan_addresses(IP.get_local_interfaces())
	if addresses.is_empty():
		for address in IP.get_local_addresses():
			if private_ipv4(str(address)): addresses.append(str(address))
	if lan_targets(addresses).is_empty(): return Common.failure("Nu am găsit o adresă IPv4 privată pe dispozitiv. Introdu manual adresa LAN a calculatorului.", "lan_address_missing")
	return await probe_targets(lan_targets(addresses), cancel)

func probe_targets(targets: Array, cancel: Dictionary) -> Dictionary:
	if cancel.get("cancelled", false): return Common.failure("Căutare oprită.", "cancelled")
	var pending = []
	var open = []
	var cursor = 0
	var deadline = Time.get_ticks_msec() + 20000
	while (cursor < targets.size() or not pending.is_empty()) and Time.get_ticks_msec() < deadline:
		if cancel.get("cancelled", false) or not is_instance_valid(owner) or not owner.is_inside_tree():
			for item in pending: item["tcp"].disconnect_from_host()
			return Common.failure("Căutare oprită.", "cancelled")
		while pending.size() < 48 and cursor < targets.size():
			var target: Dictionary = targets[cursor]
			cursor += 1
			# Test loopback is allowed here; discover_lan only supplies private addresses.
			if not private_ipv4(str(target.get("host", ""))) and target.get("host") != "127.0.0.1": continue
			if int(target.get("port", 0)) < 1 or int(target.get("port", 0)) > 65535: continue
			var tcp = StreamPeerTCP.new()
			if tcp.connect_to_host(str(target["host"]), int(target["port"])) == OK: pending.append({"tcp": tcp, "target": target, "started": Time.get_ticks_msec()})
		for index in range(pending.size() - 1, -1, -1):
			var item: Dictionary = pending[index]
			item["tcp"].poll()
			var status = item["tcp"].get_status()
			if status == StreamPeerTCP.STATUS_CONNECTED: open.append(item["target"])
			if status != StreamPeerTCP.STATUS_CONNECTING or Time.get_ticks_msec() - int(item["started"]) > 350:
				item["tcp"].disconnect_from_host()
				pending.remove_at(index)
		await owner.get_tree().process_frame
	for item in pending: item["tcp"].disconnect_from_host()
	var found = []
	# Bound HTTP verification as well, including networks with many unrelated servers.
	for target in open.slice(0, 24):
		if cancel.get("cancelled", false): return Common.failure("Căutare oprită.", "cancelled")
		var url = "http://%s:%s/v1" % [target["host"], target["port"]]
		var response = await transport.request(url + "/models", HTTPClient.METHOD_GET, [], null, {"allow_http": true, "cancel": cancel, "timeout": 1, "max_bytes": 512000})
		var payload: Variant = response.get("json")
		if not response.get("ok", false) or not payload is Dictionary or not payload.get("data") is Array: continue
		var issuer = {11434: "ollama", 1234: "lmstudio", 8080: "llamacpp"}.get(int(target["port"]), "custom")
		found.append({"issuer": issuer, "kind": "chat", "url": url, "hosting": "local", "allow_http": true, "model_count": payload["data"].size(), "name": "%s · %s" % [issuer, target["host"]]})
	return Common.success({"servers": found, "searched": cursor, "limited": cursor < targets.size() or open.size() > 24})

static func detect(key: String, issuer: String = "") -> Dictionary:
	var normalized = key.strip_edges()
	var assignment = normalized.find("=")
	if assignment > 0 and normalized.substr(0, assignment).ends_with("_API_KEY"):
		var label = normalized.substr(0, assignment).trim_prefix("export ").to_lower().trim_suffix("_api_key")
		normalized = normalized.substr(assignment + 1).strip_edges().trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'")
		if issuer.is_empty(): issuer = label
	for entry in CATALOG:
		if (not issuer.is_empty() and entry["id"] == issuer) or (issuer.is_empty() and not str(entry["prefix"]).is_empty() and normalized.begins_with(str(entry["prefix"]))):
			return {"ok": true, "profile": entry.duplicate(true), "secret": normalized}
	return Common.failure("Cheia este ambiguă. Alege furnizorul sau introdu adresa API.", "provider_ambiguous")

func headers(profile: Dictionary, key_override: String = "") -> PackedStringArray:
	var secret = key_override if not key_override.is_empty() else (vault.read(str(profile["id"])) if vault != null else "")
	var stored: Variant = Common.parse_json(secret)
	if profile.get("kind") != "siwc" and stored is Dictionary and stored.has("access_token"): return PackedStringArray()
	if profile.get("kind") == "siwc":
		var tokens: Variant = Common.parse_json(secret)
		secret = str(tokens.get("access_token", "")) if tokens is Dictionary else ""
	var result = PackedStringArray()
	match str(profile.get("kind", "chat")):
		"anthropic":
			result.append("anthropic-version: 2023-06-01")
			if not secret.is_empty(): result.append("x-api-key: " + secret)
		"gemini":
			if not secret.is_empty(): result.append("x-goog-api-key: " + secret)
		_:
			if not secret.is_empty(): result.append("Authorization: Bearer " + secret)
	return result

func list_models(profile: Dictionary, cancel: Dictionary = {}, key_override: String = "") -> Dictionary:
	var credential_error = _credential_error(profile)
	if not credential_error.is_empty(): return Common.failure(credential_error, "credential_type_mismatch")
	var resolved = endpoint(profile)
	if not resolved.get("ok", false): return resolved
	var url = str(resolved["result"])
	var issuer = str(profile.get("issuer", ""))
	var options = {"allow_http": profile.get("allow_http", false), "cancel": cancel, "timeout": 10, "connect_timeout": 4}
	var root = url.trim_suffix("/v1")
	var result = await transport.request(root + "/api/tags" if issuer == "ollama" else url + "/models", HTTPClient.METHOD_GET, headers(profile, key_override), null, options)
	if issuer == "ollama" and int(result.get("status", 0)) == 404: result = await transport.request(url + "/models", HTTPClient.METHOD_GET, headers(profile, key_override), null, options)
	if not result.get("ok", false): return result
	var payload = result.get("json")
	if not payload is Dictionary: return Common.failure("Catalogul de modele nu este JSON valid.")
	var models = []
	var entries: Array = payload.get("data", payload.get("models", []))
	for item in entries:
		if not item is Dictionary: continue
		if profile.get("kind") == "siwc" and item.get("visibility", "list") != "list": continue
		var id = str(item.get("id", item.get("slug", item.get("name", "")))).trim_prefix("models/")
		if id.is_empty(): continue
		if item.has("supportedGenerationMethods") and not "generateContent" in item["supportedGenerationMethods"]: continue
		if str(item.get("type", "")) in ["embedding", "embeddings"]: continue
		var capabilities: Dictionary = item.get("capabilities", {}).duplicate(true) if item.get("capabilities", {}) is Dictionary else {}
		var architecture: Dictionary = item.get("architecture", {}) if item.get("architecture") is Dictionary else {}
		var modalities = item.get("input_modalities", item.get("inputModalities", architecture.get("input_modalities", [])))
		if modalities is Array and modalities.any(func(value: Variant) -> bool: return str(value).to_lower() == "image"): capabilities["vision"] = true
		var supported: Dictionary = item.get("supported_parameters", {}) if item.get("supported_parameters", {}) is Dictionary else {}
		if item.get("supported_parameters", null) is Array: capabilities["tools"] = "tools" in item["supported_parameters"]
		if supported.has("tools"): capabilities["tools"] = supported["tools"]
		models.append({"id": id, "name": str(item.get("display_name", item.get("displayName", item.get("name", id)))), "capabilities": capabilities, "context": item.get("context_window", item.get("inputTokenLimit", 0)), "max_output_tokens": item.get("max_output_tokens", item.get("outputTokenLimit", 0)), "efforts": item.get("effort", {}).get("supported_levels", []) if item.get("effort", {}) is Dictionary else [], "source": "live", "pricing": ModelPricing.from_api(item, issuer, url + "/models")})
	if issuer in ["lmstudio", "ollama"]:
		var metadata = await transport.request(root + ("/api/v0/models" if issuer == "lmstudio" else "/api/ps"), HTTPClient.METHOD_GET, headers(profile, key_override), null, {"allow_http": profile.get("allow_http", false), "cancel": cancel, "timeout": 3, "connect_timeout": 2})
		if cancel.get("cancelled", false): return Common.failure("Verificare oprită.", "cancelled")
		var details: Variant = metadata.get("json")
		if metadata.get("ok", false) and details is Dictionary:
			var entries_by_id = {}
			for item in details.get("data", []) if issuer == "lmstudio" else details.get("models", []):
				if item is Dictionary: entries_by_id[str(item.get("id", item.get("name", "")))] = item
			models = models.filter(func(item: Dictionary) -> bool: return str(entries_by_id.get(item["id"], {}).get("type", "")) not in ["embedding", "embeddings"])
			for item in models:
				var detail: Dictionary = entries_by_id.get(item["id"], {})
				item["loaded"] = detail.get("state") == "loaded" if issuer == "lmstudio" else entries_by_id.has(item["id"])
				var reported_capacity: Variant = detail.get("loaded_context_length", 0) if issuer == "lmstudio" else detail.get("context_length", 0)
				var capacity = int(reported_capacity) if reported_capacity is int or reported_capacity is float else 0
				if capacity > 0: item["context"] = capacity
	return Common.success(models)

func complete(profile: Dictionary, messages: Array, tools: Array, model: String, effort: String, cancel: Dictionary, on_delta: Callable = Callable(), max_output_tokens: int = 0) -> Dictionary:
	var credential_error = _credential_error(profile)
	if not credential_error.is_empty(): return Common.failure(credential_error, "credential_type_mismatch")
	var resolved = endpoint(profile)
	if not resolved.get("ok", false): return resolved
	messages = normalize_context(profile, model, messages)
	var kind = str(profile.get("kind", "chat"))
	if not tools.is_empty() and str(profile.get("issuer", profile.get("id", ""))) == "deepseek":
		# DeepSeek thinking mode rejects tool requests where a prior assistant
		# turn lacks reasoning_content; an empty replay satisfies it without
		# resending foreign or legacy reasoning.
		for message in messages:
			if message.get("role") == "assistant" and not message.has("reasoning_content"): message["reasoning_content"] = ""
	var wire = build_request(kind, messages, tools, model, effort, max_output_tokens)
	var path = str(wire["path"])
	var collected = {"text": "", "reasoning": "", "calls": {}, "blocks": {}, "items": [], "terminal": false, "finish": "", "usage": {}, "error": ""}
	var receive = func(event: Dictionary) -> void:
		var before = str(collected["text"])
		consume_event(kind, event, collected)
		var delta = str(collected["text"]).substr(before.length())
		if not delta.is_empty() and on_delta.is_valid(): on_delta.call(delta)
	var options = inference_options(profile, cancel)
	options["on_event"] = receive
	var result = await transport.request(str(resolved["result"]) + path, HTTPClient.METHOD_POST, headers(profile), wire["body"], options)
	if not result.get("ok", false):
		if result.get("code") == "timeout" and result.get("stage") in ["response", "body"]: return Common.failure("Modelul nu a mai trimis date în intervalul de așteptare. Verifică încărcarea și resursele serverului înainte de reluare.", "inference_timeout")
		return result
	# Some otherwise compatible local servers return a complete JSON message despite stream=true.
	if kind == "chat" and result.get("events", []).is_empty() and result.get("json") is Dictionary:
		consume_event(kind, result["json"], collected)
	if not str(collected["error"]).is_empty(): return Common.failure(str(collected["error"]), "provider_error")
	if not collected["terminal"]: return Common.failure("Fluxul s-a încheiat înaintea confirmării de finalizare.", "incomplete_stream")
	var calls = []
	for index in collected["calls"]:
		var item: Dictionary = collected["calls"][index]
		var arguments: Variant = item.get("arguments", {})
		if arguments is String: arguments = Common.parse_json(arguments)
		if not arguments is Dictionary: return Common.failure("Modelul a produs argumente JSON invalide.", "invalid_tool_arguments")
		calls.append({"id": str(item.get("id", Common.uid())), "name": str(item.get("name", "")), "arguments": arguments})
	var message = {"role": "assistant", "content": str(collected["text"]), "tool_calls": calls, "wire_source": str(profile.get("id", "")) + ":" + model}
	if not str(collected["reasoning"]).is_empty(): message["reasoning_content"] = collected["reasoning"]
	if not collected["items"].is_empty(): message["provider_items"] = collected["items"]
	if not collected["blocks"].is_empty(): message["provider_blocks"] = collected["blocks"].values()
	return {"ok": true, "message": message, "calls": calls, "usage": collected["usage"], "finish": collected["finish"]}

func _credential_error(profile: Dictionary) -> String:
	if profile.get("kind") == "siwc" and str(profile.get("url", "")).trim_suffix("/") != "https://api.openai.com/v1": return "Conturile ChatGPT folosesc exclusiv endpointul oficial OpenAI."
	var stored: Variant = Common.parse_json(vault.read(str(profile["id"]))) if vault != null else null
	if profile.get("kind") != "siwc" and stored is Dictionary and stored.has("access_token"): return "Un cont cu abonament nu poate fi convertit într-o cheie API. Reconectează profilul din Abonamente."
	return ""

static func build_request(kind: String, messages: Array, tools: Array, model: String, effort: String = "", max_output_tokens: int = 0) -> Dictionary:
	messages = expand_tool_images(application_context(messages))
	var system = []
	for message in messages:
		if message.get("role") == "system": system.append(str(message.get("content", "")))
	var body: Dictionary = {"model": model, "stream": true}
	var path = "/chat/completions"
	if kind in ["responses", "siwc"]:
		path = "/responses"
		body["store"] = false
		body["instructions"] = "\n\n".join(system)
		var input = []
		for message in messages:
			var role = str(message.get("role", "user"))
			if role == "system": continue
			if role == "tool":
				input.append({"type": "function_call_output", "call_id": message["tool_call_id"], "output": str(message["content"])})
			elif role == "assistant" and message.has("provider_items"):
				input.append_array(message["provider_items"])
			else:
				input.append({"role": role, "content": parts(message, "responses") if not message.get("attachments", []).is_empty() and role == "user" else str(message.get("content", ""))})
				for call in message.get("tool_calls", []): input.append({"type": "function_call", "call_id": call["id"], "name": call["name"], "arguments": JSON.stringify(call["arguments"])})
		body["input"] = input
		if not tools.is_empty():
			var definitions = []
			for tool in tools: definitions.append({"type": "function", "name": tool["name"], "description": tool["description"], "parameters": tool["parameters"], "strict": false})
			body["tools"] = [{"type": "namespace", "name": "godot", "description": "Godot editor and configured external tools", "tools": definitions}] if kind == "siwc" else definitions
		if not effort.is_empty(): body["reasoning"] = {"effort": effort}
		if kind == "responses": body["include"] = ["reasoning.encrypted_content"]
	elif kind == "anthropic":
		path = "/messages"
		body["max_tokens"] = 8192
		body["system"] = "\n\n".join(system)
		var history = []
		for message in messages:
			var role = str(message.get("role", "user"))
			if role == "system": continue
			var content = []
			if role == "tool":
				role = "user"
				content.append({"type": "tool_result", "tool_use_id": message["tool_call_id"], "content": str(message["content"])})
			elif message.has("provider_blocks"):
				content = message["provider_blocks"].duplicate(true)
			else:
				content.append_array(parts(message, "anthropic"))
				for call in message.get("tool_calls", []): content.append({"type": "tool_use", "id": call["id"], "name": call["name"], "input": call["arguments"]})
			if not history.is_empty() and history[-1]["role"] == role: history[-1]["content"].append_array(content)
			else: history.append({"role": role, "content": content})
		body["messages"] = history
		if not tools.is_empty():
			body["tools"] = []
			for tool in tools: body["tools"].append({"name": tool["name"], "description": tool["description"], "input_schema": tool["parameters"]})
	elif kind == "gemini":
		path = "/models/" + model.uri_encode() + ":streamGenerateContent?alt=sse"
		body = {"systemInstruction": {"parts": [{"text": "\n\n".join(system)}]}, "contents": []}
		for message in messages:
			var role = str(message.get("role", "user"))
			if role == "system": continue
			var parts = []
			if role == "tool": parts.append({"functionResponse": {"name": message.get("tool_name", ""), "response": {"result": str(message["content"])}}})
			elif message.has("provider_items"): parts = message["provider_items"].duplicate(true)
			else:
				parts.append_array(image_parts(message, "gemini"))
				if not str(message.get("content", "")).is_empty(): parts.append({"text": str(message["content"])})
				for call in message.get("tool_calls", []): parts.append({"functionCall": {"name": call["name"], "args": call["arguments"]}})
			body["contents"].append({"role": "model" if role == "assistant" else "user", "parts": parts})
		if not tools.is_empty():
			var declarations = []
			for tool in tools: declarations.append({"name": tool["name"], "description": tool["description"], "parameters": tool["parameters"]})
			body["tools"] = [{"functionDeclarations": declarations}]
	else:
		body["messages"] = []
		for message in messages:
			var wire = {"role": message["role"], "content": parts(message, "chat") if not message.get("attachments", []).is_empty() else str(message.get("content", ""))}
			if message.get("role") == "tool": wire["tool_call_id"] = message["tool_call_id"]
			if message.has("reasoning_content"): wire["reasoning_content"] = message["reasoning_content"]
			if not message.get("tool_calls", []).is_empty():
				wire["tool_calls"] = []
				for call in message["tool_calls"]: wire["tool_calls"].append({"id": call["id"], "type": "function", "function": {"name": call["name"], "arguments": JSON.stringify(call["arguments"])}})
			body["messages"].append(wire)
		if not tools.is_empty():
			body["tools"] = []
			for tool in tools: body["tools"].append({"type": "function", "function": {"name": tool["name"], "description": tool["description"], "parameters": tool["parameters"]}})
		if not effort.is_empty(): body["reasoning_effort"] = effort
	if max_output_tokens > 0:
		if kind in ["responses", "siwc"]: body["max_output_tokens"] = max_output_tokens
		elif kind == "gemini": body["generationConfig"] = {"maxOutputTokens": max_output_tokens}
		else: body["max_tokens"] = max_output_tokens
	return {"path": path, "body": body}

static func consume_event(kind: String, event: Dictionary, state: Dictionary) -> void:
	if event.has("error"):
		state["error"] = JSON.stringify(event["error"])
		return
	if kind in ["responses", "siwc"]:
		match str(event.get("type", "")):
			"response.output_text.delta": state["text"] += str(event.get("delta", ""))
			"response.completed", "response.incomplete":
				var response: Dictionary = event.get("response", {})
				var incomplete = event.get("type") == "response.incomplete"
				if incomplete and response.get("incomplete_details", {}).get("reason") != "max_output_tokens":
					state["error"] = JSON.stringify(event)
					return
				state["terminal"] = true
				state["finish"] = "length" if incomplete else "stop"
				# A truncated function call is never executable or sent back as an orphan call.
				state["items"] = response.get("output", []).filter(func(item: Dictionary) -> bool: return not incomplete or item.get("type") != "function_call")
				state["usage"] = response.get("usage", {})
				var final_text = ""
				for item in state["items"]:
					if item.get("type") == "function_call": state["calls"][str(item.get("call_id", item.get("id", Common.uid())))] = {"id": item.get("call_id", item.get("id", Common.uid())), "name": item.get("name", ""), "arguments": item.get("arguments", "{}")}
					if item.get("type") == "message":
						for part in item.get("content", []):
							if part.get("type") == "output_text": final_text += str(part.get("text", ""))
				if str(state["text"]).is_empty(): state["text"] = final_text
			"response.failed", "error": state["error"] = JSON.stringify(event)
	elif kind == "anthropic":
		var index = str(event.get("index", 0))
		match str(event.get("type", "")):
			"content_block_start": state["blocks"][index] = event.get("content_block", {}).duplicate(true)
			"content_block_delta":
				var delta: Dictionary = event.get("delta", {})
				if not state["blocks"].has(index): return
				var block: Dictionary = state["blocks"][index]
				match str(delta.get("type", "")):
					"text_delta":
						state["text"] += str(delta.get("text", ""))
						block["text"] = str(block.get("text", "")) + str(delta.get("text", ""))
					"input_json_delta": block["_partial_json"] = str(block.get("_partial_json", "")) + str(delta.get("partial_json", ""))
					"thinking_delta": block["thinking"] = str(block.get("thinking", "")) + str(delta.get("thinking", ""))
					"signature_delta": block["signature"] = str(block.get("signature", "")) + str(delta.get("signature", ""))
			"content_block_stop":
				if not state["blocks"].has(index): return
				var block: Dictionary = state["blocks"][index]
				if block.has("_partial_json"):
					block["input"] = Common.parse_json(str(block["_partial_json"]))
					block.erase("_partial_json")
				if block.get("type") == "tool_use": state["calls"][index] = {"id": block["id"], "name": block["name"], "arguments": block.get("input", {})}
			"message_delta":
				state["finish"] = str(event.get("delta", {}).get("stop_reason", ""))
				state["usage"] = event.get("usage", {})
			"message_stop": state["terminal"] = true
	elif kind == "gemini":
		state["usage"] = event.get("usageMetadata", state["usage"])
		for candidate in event.get("candidates", []):
			for part in candidate.get("content", {}).get("parts", []):
				state["items"].append(part)
				if part.has("text") and not part.get("thought", false): state["text"] += str(part["text"])
				if part.has("functionCall"):
					var call: Dictionary = part["functionCall"]
					state["calls"][Common.uid()] = {"id": call.get("id", Common.uid()), "name": call.get("name", ""), "arguments": call.get("args", {})}
			if candidate.has("finishReason"):
				state["terminal"] = true
				state["finish"] = str(candidate["finishReason"])
	else:
		state["usage"] = event.get("usage", state["usage"])
		for choice in event.get("choices", []):
			var delta: Dictionary = choice.get("delta", choice.get("message", {}))
			state["text"] += str(delta.get("content", "")) if delta.get("content") != null else ""
			state["reasoning"] += str(delta.get("reasoning_content", "")) if delta.get("reasoning_content") != null else ""
			var fragments: Array = delta.get("tool_calls", [])
			for fragment_index in range(fragments.size()):
				var fragment: Dictionary = fragments[fragment_index]
				var index = str(fragment.get("index", fragment_index))
				if not state["calls"].has(index): state["calls"][index] = {"id": Common.uid(), "name": "", "arguments": ""}
				var call: Dictionary = state["calls"][index]
				if fragment.has("id"): call["id"] = fragment["id"]
				call["name"] += str(fragment.get("function", {}).get("name", ""))
				call["arguments"] += str(fragment.get("function", {}).get("arguments", ""))
			if choice.get("finish_reason") != null:
				state["terminal"] = true
				state["finish"] = str(choice["finish_reason"])

static func normalize_context(profile: Dictionary, model: String, messages: Array) -> Array:
	var result = messages.duplicate(true)
	var source = str(profile.get("id", "")) + ":" + model
	for message in result:
		if message.get("wire_source", "") != source:
			for key in ["provider_items", "provider_blocks", "reasoning_content"]: message.erase(key)
	return result

static func application_context(messages: Array) -> Array:
	var result = []
	for message in messages:
		# UI notices are not provider responses. In particular, do not fabricate
		# reasoning_content to make a locally generated assistant turn replayable.
		var local = message.get("role") == "assistant" and message.has("application_message")
		# Compatibility with interruptions and file cards saved before provenance
		# was recorded. Actual provider messages always carry wire_source.
		if message.get("role") == "assistant" and not message.has("wire_source") and message.get("tool_calls", []).is_empty() and not message.has("reasoning_content") and not message.has("provider_items") and not message.has("provider_blocks"):
			local = local or message.has("run_status") or message.get("origin_label") == "Fișiere generate"
		if local:
			var text = str(message.get("content", ""))
			if message.get("application_message") == "partial": text = "Unconfirmed interrupted response; not proof of completed work: " + text
			if not message.get("files", []).is_empty(): text += "\nFile IDs: " + JSON.stringify(message["files"])
			if not text.is_empty(): result.append({"role": "system", "content": "Application state (not a model response): " + text})
		else:
			result.append(message)
	return result

static func expand_tool_images(messages: Array) -> Array:
	var result = []
	var pending = []
	for original in messages:
		var message = original.duplicate(true)
		if message.get("role") != "tool" and not pending.is_empty():
			result.append({"role": "user", "content": "Actual tool screenshots:", "attachments": pending})
			pending = []
		if message.get("role") == "tool":
			pending.append_array(message.get("attachments", []))
			message.erase("attachments")
		result.append(message)
	if not pending.is_empty(): result.append({"role": "user", "content": "Actual tool screenshots:", "attachments": pending})
	return result

static func image_parts(message: Dictionary, kind: String) -> Array:
	var output = []
	for image in message.get("attachments", []).slice(0, 4):
		var data = str(image.get("data", ""))
		var mime = str(image.get("mimeType", "image/png"))
		if data.is_empty() or data.length() > 2800000 or mime not in ["image/png", "image/jpeg", "image/webp"]: continue
		match kind:
			"responses": output.append({"type": "input_image", "image_url": "data:" + mime + ";base64," + data})
			"anthropic": output.append({"type": "image", "source": {"type": "base64", "media_type": mime, "data": data}})
			"gemini": output.append({"inlineData": {"mimeType": mime, "data": data}})
			_: output.append({"type": "image_url", "image_url": {"url": "data:" + mime + ";base64," + data}})
	return output

static func parts(message: Dictionary, kind: String) -> Array:
	var output = []
	var text = str(message.get("content", ""))
	if not text.is_empty(): output.append({"type": "input_text" if kind == "responses" else "text", "text": text})
	output.append_array(image_parts(message, kind))
	return output

static func vision_allowed(profile: Dictionary, model_id: String) -> bool:
	var policy = int(profile.get("vision_overrides", {}).get(model_id, 0))
	if policy != 0: return policy == 1
	for model in profile.get("models", []):
		if model.get("id") == model_id: return bool(model.get("capabilities", {}).get("vision", false))
	return false
