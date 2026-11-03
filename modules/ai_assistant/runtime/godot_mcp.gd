@tool
extends RefCounted
## Minimal MCP (Streamable HTTP, JSON responses) server for the Agent AI session.
##
## It exposes the Godot editor tool catalog as native MCP tools. The agent's
## native tool search decides what reaches the model, so the app does not
## duplicate the harness search, context or session loop.
## The listener is bound to loopback only and every request must carry the
## bearer token written into the guest Pi configuration.

const PROTOCOL = "2025-06-18"
const MAX_HEADER = 32 * 1024
const MAX_BODY = 4 * 1024 * 1024
const IDLE_MS = 30000
const MAX_PEERS = 12
var panel: Node
var store_path := ""
var token := ""
var port := 0
var server := TCPServer.new()
var peers: Array = []
var session_id := ""
var read_only := false

func configure(owner: Node, path: String) -> void:
	panel = owner
	store_path = path

func set_read_only(value: bool) -> void:
	read_only = value

func start() -> Dictionary:
	if server.is_listening():
		return {"ok": true, "port": port, "token": token, "running": true}
	var saved := _load()
	token = str(saved.get("token", ""))
	if token.length() < 32 or not token.is_valid_hex_number():
		token = _new_token()
		_save()
	session_id = _new_token().left(32)
	var error := server.listen(0, "127.0.0.1")
	if error != OK:
		return {"ok": false, "code": "mcp_listen_failed", "error": "Serverul MCP nu poate asculta pe 127.0.0.1 (cod %d)." % error}
	port = server.get_local_port()
	if port <= 0:
		server.stop()
		return {"ok": false, "code": "mcp_listen_failed", "error": "Serverul MCP nu a primit un port local."}
	return {"ok": true, "port": port, "token": token, "running": true}

func stop() -> void:
	for peer in peers:
		peer["closed"] = true
		var stream = peer.get("stream")
		if stream != null and is_instance_valid(stream):
			stream.disconnect_from_host()
	peers.clear()
	if server.is_listening():
		server.stop()
	port = 0

func info() -> Dictionary:
	return {"ok": server.is_listening() and port > 0, "port": port, "token": token, "running": server.is_listening()}

func poll() -> void:
	if not server.is_listening():
		return
	for index in range(peers.size() - 1, -1, -1):
		var peer: Dictionary = peers[index]
		var stream = peer.get("stream")
		if stream == null or not is_instance_valid(stream):
			peers.remove_at(index)
			continue
		if bool(peer.get("closed", false)):
			peers.remove_at(index)
			continue
		if bool(peer.get("busy", false)):
			continue
		stream.poll()
		var state: int = stream.get_status()
		if state != StreamPeerTCP.STATUS_CONNECTED:
			peers.remove_at(index)
			continue
		var available: int = stream.get_available_bytes()
		if available > 0:
			var chunk: Array = stream.get_data(available)
			if chunk[0] == OK:
				peer["buffer"].append_array(chunk[1])
		var buffer: PackedByteArray = peer["buffer"]
		if buffer.size() > MAX_HEADER + MAX_BODY:
			_close(peer)
			continue
		var request := _parse_http(buffer)
		if request.is_empty():
			if Time.get_ticks_msec() - int(peer.get("created", 0)) > IDLE_MS:
				_close(peer)
			continue
		peer["busy"] = true
		_serve(peer, request)
	while peers.size() < MAX_PEERS and server.is_connection_available():
		peers.append({"stream": server.take_connection(), "buffer": PackedByteArray(),
			"created": Time.get_ticks_msec(), "busy": false, "closed": false})

func _serve(peer: Dictionary, request: Dictionary) -> void:
	var response := await _handle(request)
	if bool(peer.get("closed", false)):
		return
	var stream = peer.get("stream")
	if stream != null and is_instance_valid(stream):
		stream.put_data(response.to_utf8_buffer())
		stream.disconnect_from_host()
	peer["closed"] = true
	peer["busy"] = false

func _handle(request: Dictionary) -> String:
	var method := str(request.get("method", "GET"))
	if method == "GET":
		return _http(405, null, {}, {"Allow": "POST"})
	if method == "DELETE":
		return _http(200, null, {}, {})
	if method != "POST":
		return _http(405, null, {}, {"Allow": "POST"})
	var headers: Dictionary = request["headers"]
	if not _authorized(headers):
		return _http(401, {}, _rpc_error(null, -32000, "Token MCP invalid."), {"WWW-Authenticate": "Bearer"})
	var body: PackedByteArray = request["body"]
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		return _http(200, {}, _rpc_error(null, -32700, "Corp JSON-RPC invalid."), {})
	var message: Dictionary = parsed
	var id: Variant = message.get("id", null)
	var rpc: String = str(message.get("method", ""))
	if id == null and not rpc.is_empty():
		# JSON-RPC notification: acknowledge without a body.
		return _http(202, null, {}, {})
	match rpc:
		"initialize":
			var params: Dictionary = message.get("params", {}) if message.get("params") is Dictionary else {}
			var requested := str(params.get("protocolVersion", PROTOCOL))
			var protocol := requested if requested in ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"] else PROTOCOL
			return _http(200, id, {
				"protocolVersion": protocol,
				"capabilities": {"tools": {"listChanged": false}},
				"serverInfo": {"name": "godot-ai", "version": "1.0.0"},
				"instructions": _instructions(),
			}, {"Mcp-Session-Id": session_id})
		"ping":
			return _http(200, id, {}, {})
		"tools/list":
			return _http(200, id, {"tools": _tool_list()}, {})
		"tools/call":
			var params: Dictionary = message.get("params", {}) if message.get("params") is Dictionary else {}
			var result := await _call_tool(str(params.get("name", "")), params.get("arguments", {}))
			return _http(200, id, result, {})
		"resources/list", "prompts/list":
			return _http(200, id, {"resources": []} if rpc == "resources/list" else {"prompts": []}, {})
		"resources/templates/list":
			return _http(200, id, {"resourceTemplates": []}, {})
		"":
			return _http(200, id, {}, {})
		_:
			return _http(200, id, _rpc_error(id, -32601, "Metodă MCP necunoscută: " + rpc), {})

func _instructions() -> String:
	return "Godot editor tools for this project. The catalog is registered as MCP tools; use the native tool search to discover the ones relevant to the current task. Call a discovered tool directly with its declared arguments. Full reflection access is available through godot_describe and godot_call; inspect the exact signature before calling generic methods. Plan mode exposes only read tools. Captures return image content. Change sets require prepare, status and apply. Ziva lifecycle/conversation and Blender status/setup/run tools are included when available. Every call is audited in the AI assistant journal; external side effects are never simulated."

func _tool_list() -> Array:
	var tools := []
	if not is_instance_valid(panel) or not panel.has_method("agent_catalog"):
		return tools
	var catalog: Variant = panel.call("agent_catalog")
	if not catalog is Array:
		return tools
	for item in catalog:
		if not item is Dictionary:
			continue
		var name := str(item.get("name", ""))
		if name.is_empty():
			continue
		var risk := str(item.get("risk", "external"))
		if read_only and risk != "read":
			continue
		var schema: Variant = item.get("parameters", {})
		if not schema is Dictionary:
			schema = {"type": "object", "properties": {}, "additionalProperties": false}
		tools.append({
			"name": name,
			"description": str(item.get("description", "")).left(2000),
			"inputSchema": schema,
		})
	return tools

func _call_tool(tool: String, raw_arguments: Variant) -> Dictionary:
	var arguments: Dictionary = raw_arguments if raw_arguments is Dictionary else {}
	if not is_instance_valid(panel):
		return _tool_result({"ok": false, "error": "Panoul AI Assistant nu este disponibil."}, [])
	if not panel.has_method("agent_catalog") or not panel.has_method("agent_execute"):
		return _tool_result({"ok": false, "error": "Catalogul Godot nu este disponibil."}, [])
	var entry := {}
	var catalog: Variant = panel.call("agent_catalog")
	if catalog is Array:
		for item in catalog:
			if item is Dictionary and str(item.get("name", "")) == tool:
				entry = item
				break
	if entry.is_empty():
		return _tool_result({"ok": false, "error": "Instrument MCP necunoscut: " + tool}, [])
	if read_only and str(entry.get("risk", "external")) != "read":
		return _tool_result({"ok": false, "error": "Sesiunea Plan este read-only."}, [])
	var result: Dictionary = await panel.call("agent_execute", tool, arguments)
	return _tool_result(result, _images(result))

func _images(result: Dictionary) -> Array:
	var images := []
	var source: Variant = result.get("images", [])
	if not source is Array:
		return images
	for image in source:
		if not image is Dictionary: continue
		if not str(image.get("mimeType", "")).begins_with("image/"): continue
		if not image.has("data"): continue
		images.append({"type": "image", "data": str(image["data"]), "mimeType": str(image["mimeType"])})
		if images.size() >= 4: break
	return images

func _tool_result(result: Dictionary, images: Array) -> Dictionary:
	var summary := result.duplicate(true)
	summary.erase("images")
	var text := JSON.stringify(summary)
	if text.length() > 120000:
		text = text.left(120000) + "\n[trunchiat]"
	var content: Array = [{"type": "text", "text": text}]
	content.append_array(images)
	return {"content": content, "isError": not bool(result.get("ok", false))}

func _authorized(headers: Dictionary) -> bool:
	var value := str(headers.get("authorization", ""))
	if not value.begins_with("Bearer "):
		return false
	var provided := value.trim_prefix("Bearer ").strip_edges()
	return provided.length() == token.length() and provided.sha256_text() == token.sha256_text()

func _rpc_error(id: Variant, code: int, text: String) -> Dictionary:
	return {"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": text}}

func _http(status: int, id: Variant, result: Dictionary, headers: Dictionary) -> String:
	var reason: String = {200: "OK", 202: "Accepted", 401: "Unauthorized", 405: "Method Not Allowed"}.get(status, "OK")
	var body := ""
	if status != 202:
		# _rpc_error() already returns a complete JSON-RPC envelope.
		var message: Dictionary = result if result.has("jsonrpc") else {"jsonrpc": "2.0", "id": id, "result": result}
		body = JSON.stringify(message)
	var head := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n" % [status, reason, body.to_utf8_buffer().size()]
	for key in headers:
		head += "%s: %s\r\n" % [str(key), str(headers[key])]
	return head + "\r\n" + body

func _parse_http(buffer: PackedByteArray) -> Dictionary:
	var header_end := _find(buffer, PackedByteArray([13, 10, 13, 10]), 0)
	if header_end < 0:
		return {}
	var header_text := buffer.slice(0, header_end).get_string_from_utf8()
	var lines := header_text.split("\r\n")
	if lines.is_empty():
		return {}
	var request_line := lines[0].split(" ")
	if request_line.size() < 2:
		return {"method": "GET"}
	var headers := {}
	for index in range(1, lines.size()):
		var line := lines[index]
		var colon := line.find(":")
		if colon <= 0: continue
		headers[line.substr(0, colon).strip_edges().to_lower()] = line.substr(colon + 1).strip_edges()
	var body_start := header_end + 4
	var body := PackedByteArray()
	if str(headers.get("transfer-encoding", "")).to_lower().contains("chunked"):
		var chunked := _decode_chunked(buffer, body_start)
		if not chunked.get("complete", false):
			return {}
		body = chunked["body"]
	else:
		var length := int(str(headers.get("content-length", "0")))
		if length < 0 or length > MAX_BODY:
			return {"method": "GET", "path": "/", "headers": headers, "body": PackedByteArray()}
		if buffer.size() < body_start + length:
			return {}
		body = buffer.slice(body_start, body_start + length)
	return {"method": request_line[0].to_upper(), "path": request_line[1], "headers": headers, "body": body}

func _decode_chunked(buffer: PackedByteArray, start: int) -> Dictionary:
	var offset := start
	var output := PackedByteArray()
	while true:
		var line_end := _find(buffer, PackedByteArray([13, 10]), offset)
		if line_end < 0:
			return {"complete": false}
		var size_text := buffer.slice(offset, line_end).get_string_from_utf8().split(";")[0].strip_edges()
		if not size_text.is_valid_hex_number():
			return {"complete": false}
		var size := size_text.hex_to_int()
		offset = line_end + 2
		if size == 0:
			return {"complete": true, "body": output}
		if size < 0 or buffer.size() < offset + size + 2:
			return {"complete": false}
		output.append_array(buffer.slice(offset, offset + size))
		offset += size + 2
		if output.size() > MAX_BODY:
			return {"complete": false}
	return {"complete": false}

func _find(buffer: PackedByteArray, needle: PackedByteArray, from: int) -> int:
	if needle.is_empty() or buffer.size() < needle.size():
		return -1
	for index in range(maxi(0, from), buffer.size() - needle.size() + 1):
		var matches := true
		for offset in range(needle.size()):
			if buffer[index + offset] != needle[offset]:
				matches = false
				break
		if matches:
			return index
	return -1

func _new_token() -> String:
	return Crypto.new().generate_random_bytes(32).hex_encode()

func _load() -> Dictionary:
	if store_path.is_empty() or not FileAccess.file_exists(store_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(store_path))
	return parsed if parsed is Dictionary else {}

func _save() -> void:
	if store_path.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(store_path.get_base_dir())
	var file := FileAccess.open(store_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"token": token}))
	file.close()
	FileAccess.set_unix_permissions(store_path, 0600)

func _close(peer: Dictionary) -> void:
	var stream = peer.get("stream")
	if stream != null and is_instance_valid(stream):
		stream.disconnect_from_host()
	peer["closed"] = true
