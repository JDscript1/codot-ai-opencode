@tool
extends RefCounted
## App-owned Linux jobs. The direct-provider harness remains in Godot.
static var Common: GDScript
signal changed()
signal diagnostic(entry: Dictionary)
var owner: Node
var bridge: Node
var state: Dictionary = {}
var working = false
var active_job = ""
var log_text = ""
var last_refresh = 0
var stopping = false
var preparing = false

func _init(node: Node = null, native_bridge: Node = null) -> void:
	owner = node
	bridge = native_bridge

func _request(action: String, args: Dictionary = {}) -> Dictionary:
	if bridge == null or not bridge.has_method("linux_runtime_request"): return Common.failure("Acest editor nu include runtime-ul Linux integrat.", "runtime_unavailable")
	var payload = args.duplicate(true)
	if action in ["execute", "blender_run"] and not payload.has("project_directory"):
		payload["project_directory"] = ProjectSettings.globalize_path("res://").trim_suffix("/")
	var result: Variant = bridge.call("linux_runtime_request", action, payload)
	return result if result is Dictionary else Common.failure("Răspuns Linux invalid.", "runtime_protocol_error")

func refresh() -> Dictionary:
	last_refresh = Time.get_ticks_msec()
	var result = _request("status")
	state = result.duplicate(true)
	if result.get("ok", false):
		var job = str(result.get("active_job", ""))
		if not job.is_empty() and not working: resume.call_deferred(job)
	changed.emit()
	return result

func available() -> bool:
	return bool(state.get("ok", false)) and bool(state.get("ready", false)) and bool(state.get("installed", false))

static func definitions(ready: bool) -> Array:
	var result = [Common.tool("linux_status", "Inspect the built-in Linux runtime and verified Python, Node.js, Git, ripgrep or Blender utilities. The base prepares automatically; no separate Termux app is required. Availability is measured; do not assume a CLI harness is installed or integrated.", {}, [])]
	if ready:
		result.append(Common.tool("linux_execute", "Execute a shell command in the app-owned Debian runtime with the current Godot project mounted at /workspace. Use explicit paths; output is bounded, jobs are cancellable and return the actual exit code. This can modify project files and use network access. PRoot is not a security sandbox. Never read or print credentials; never claim a CLI agent integration merely because its executable runs. Use native Godot tools for scene operations and GLB previews.", {"command": {"type": "string", "minLength": 1, "maxLength": 16000}, "seconds": {"type": "integer", "minimum": 1, "maximum": 600}}, ["command"], "external"))
		result.append(Common.tool("linux_install_tool", "Install an optional utility into the integrated Linux runtime. Only use when the user requested that utility; package downloads need network access. Blender is bundled by the application and is prepared through blender_prepare, not this tool. Confirm availability from the completed job, not from a queued installation.", {"tool": {"type": "string", "enum": ["python", "node", "git", "ripgrep"]}}, ["tool"], "external"))
	return result

func setup(action: String, tool: String = "") -> Dictionary:
	return await _start(action, {"tool": tool} if action == "tool_install" else {}, {})

func ensure_ready() -> Dictionary:
	if working: return Common.success({"in_progress": true})
	var current = refresh()
	if not current.get("supported", false) or not current.get("packaged", false): return current
	if not str(current.get("active_job", "")).is_empty(): return Common.success({"in_progress": true})
	return await setup("prepare")

func execute(args: Dictionary, cancel: Dictionary) -> Dictionary:
	if not available(): return Common.failure("Linux se pregătește automat. Verifică starea în Integrări → Runtime Linux.", "runtime_unavailable")
	return await _start("execute", args, cancel)

func blender_status() -> Dictionary:
	return _request("blender_status")

func blender(args: Dictionary, cancel: Dictionary) -> Dictionary:
	if not available(): return Common.failure("Runtime-ul Linux nu este pregătit pentru Blender.", "runtime_unavailable")
	var status = blender_status()
	if not status.get("ready", false): return Common.failure(str(status.get("error", "Blender nu este pregătit.")), str(status.get("reason", "blender_unavailable")))
	return await _start("blender_run", args, cancel)

func install_blender(cancel: Dictionary) -> Dictionary:
	if working: return Common.failure("O sarcină Linux este deja în lucru.", "runtime_busy")
	return await _start("packages_update", {}, cancel)

func resume(id: String) -> Dictionary:
	if working: return Common.failure("O sarcină Linux este deja în lucru.", "runtime_busy")
	return await _wait(id, {})

func _start(action: String, args: Dictionary, cancel: Dictionary) -> Dictionary:
	if working: return Common.failure("O sarcină Linux este deja în lucru.", "runtime_busy")
	if cancel.get("cancelled", false): return Common.failure("Operație anulată.", "cancelled")
	log_text = ""
	var submitted = _request(action, args)
	if not submitted.get("ok", false):
		_note(action, submitted)
		return submitted
	var id = str(submitted.get("id", ""))
	if id.is_empty(): return Common.failure("Sarcina Linux nu are ID.", "runtime_protocol_error")
	preparing = action == "prepare"
	return await _wait(id, cancel)

func _wait(id: String, cancel: Dictionary) -> Dictionary:
	working = true
	active_job = id
	stopping = false
	changed.emit()
	# Package preparation includes decompression and dpkg for the bundled
	# Blender/Godot suites. Native jobs still have their own exact timeouts;
	# this bounded wait only prevents the UI from abandoning a live job.
	var deadline = Time.get_ticks_msec() + 7200000
	var outcome = Common.failure("Sarcina Linux nu a întors un rezultat. Verifică jurnalul înainte de reluare.", "runtime_job_unknown")
	while Time.get_ticks_msec() < deadline:
		if (stopping or cancel.get("cancelled", false)) and not stopping:
			stopping = true
			_request("cancel", {"id": id})
		var response = _request("poll", {"id": id})
		if not response.get("ok", false): outcome = response; break
		if response.has("kind"): preparing = str(response["kind"]) == "prepare"
		var text = str(response.get("output", ""))
		if is_instance_valid(owner) and owner.has_method("_redact"): text = owner._redact(text)
		if log_text != text: log_text = text.right(131072); changed.emit()
		var status = str(response.get("status", ""))
		if status in ["completed", "failed", "cancelled", "interrupted"]:
			if status == "completed":
				var result: Dictionary = response.get("result", {}).duplicate(true)
				if result.has("output") and is_instance_valid(owner): result["output"] = owner._redact(str(result["output"]))
				outcome = Common.success(result) if int(result.get("exit_code", 0)) == 0 else Common.failure("Comanda Linux s-a încheiat cu codul " + str(result["exit_code"]) + ".", "command_failed").merged({"result": result})
			else: outcome = Common.failure(str(response.get("error", "Sarcina Linux nu s-a finalizat.")), status)
			break
		if owner == null or not is_instance_valid(owner) or not owner.is_inside_tree(): break
		await owner.get_tree().create_timer(0.25).timeout
	working = false
	active_job = ""
	stopping = false
	preparing = false
	state = _request("status")
	changed.emit()
	_note("job", outcome, id)
	return outcome

func stop() -> void:
	if active_job.is_empty(): return
	stopping = true
	_request("cancel", {"id": active_job})

func _note(action: String, result: Dictionary, job_id: String = "") -> void:
	diagnostic.emit({"action": action, "ok": result.get("ok", false), "code": result.get("code", ""), "error": result.get("error", ""), "job": job_id if not job_id.is_empty() else active_job, "output": log_text.right(12000)})
