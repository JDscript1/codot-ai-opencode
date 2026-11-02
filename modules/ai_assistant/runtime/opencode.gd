@tool
extends RefCounted
## Bridge to the optional OpenCode runtime. It never touches the assistant's
## provider credentials; OpenCode owns its own auth through /connect.

signal changed()

var bridge: Node
var state: Dictionary = {}
var last_refresh := 0
var project_directory := ""

func _init(native_bridge: Node = null, project: String = "") -> void:
	bridge = native_bridge
	project_directory = project

func refresh() -> Dictionary:
	last_refresh = Time.get_ticks_msec()
	state = _request("status")
	changed.emit()
	return state

func _request(action: String, args: Dictionary = {}) -> Dictionary:
	if not is_instance_valid(bridge) or not bridge.has_method("opencode_request"):
		return _failure("OpenCode este disponibil doar în editorul Android.", "opencode_unavailable")
	var payload := args.duplicate(true)
	payload["project_directory"] = project_directory
	var result: Variant = bridge.call("opencode_request", action, payload)
	return result if result is Dictionary else _failure("Răspuns OpenCode invalid.", "opencode_protocol_error")

func install() -> Dictionary:
	return _request("install")

func cancel() -> Dictionary:
	return _request("cancel")

func start(port: int, token: String) -> Dictionary:
	return _request("start", {"mcp_port": port, "mcp_token": token})

func stop() -> Dictionary:
	return _request("stop")

func embed(rect: Rect2, visible: bool) -> Dictionary:
	return _request("embed", {"visible": visible, "bounds": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]})

func busy() -> bool:
	var value := str(state.get("status", ""))
	return value in ["installing", "starting", "stopping"]

func caption() -> String:
	if not state.get("ok", false):
		return "OpenCode · disponibil doar pe Android"
	if state.get("running", false):
		var port := int(state.get("mcp_port", 0))
		return "OpenCode · activ" + (" · MCP %d" % port if port > 0 else "")
	if str(state.get("status", "")) == "installing":
		return "OpenCode · instalez %d%%" % int(state.get("progress", 0))
	if str(state.get("status", "")) == "error":
		return "OpenCode · eroare"
	if state.get("installed", false):
		var version := str(state.get("version", ""))
		return "OpenCode instalat" + (" · " + version if not version.is_empty() else "")
	return "OpenCode nu este instalat"

func _failure(message: String, code: String) -> Dictionary:
	return {"ok": false, "error": message, "code": code}
