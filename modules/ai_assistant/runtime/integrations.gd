@tool
extends RefCounted
## Optional native HTTP integrations and desktop/Termux Blender process control.
static var Common: GDScript
static var Transport: GDScript
static var TermuxBlender: GDScript
static var LinuxRuntime: GDScript
var owner: Node
var vault: RefCounted
var transport: RefCounted
var api_url = "https://api.github.com"
var test_http = false
var processes: Array = []
var github_generation = 0
var termux: RefCounted
var linux: RefCounted

func github_invalidate() -> void:
	github_generation += 1

func _github_headers() -> PackedStringArray:
	var headers = PackedStringArray(["Accept: application/vnd.github+json", "X-GitHub-Api-Version: 2026-03-10", "User-Agent: Godot-AI-Editor"])
	var key = vault.read("integration_github")
	if not key.is_empty(): headers.append("Authorization: Bearer " + key)
	return headers

func github_account(cancel: Dictionary = {}) -> Dictionary:
	if vault.read("integration_github").is_empty(): return Common.failure("Adaugă tokenul personal GitHub.", "missing_credentials")
	var response = await transport.request(api_url + "/user", HTTPClient.METHOD_GET, _github_headers(), null, {"cancel": cancel, "allow_http": test_http, "max_bytes": 64000})
	var data: Variant = response.get("json")
	if not response.get("ok", false) or not data is Dictionary or str(data.get("login", "")).is_empty(): return Common.failure("Token GitHub invalid sau expirat.", "github_auth_error")
	return Common.success({"login": str(data["login"]), "name": str(data.get("name", "")), "id": int(data.get("id", 0))})

func github_repositories(page: int = 1, cancel: Dictionary = {}) -> Dictionary:
	if vault.read("integration_github").is_empty(): return Common.failure("Adaugă tokenul personal GitHub.", "missing_credentials")
	var response = await transport.request(api_url + "/user/repos?sort=updated&per_page=30&page=" + str(clampi(page, 1, 100)), HTTPClient.METHOD_GET, _github_headers(), null, {"cancel": cancel, "allow_http": test_http, "max_bytes": 2 * 1024 * 1024})
	if not response.get("ok", false) or not response.get("json") is Array: return Common.failure("Lista de repository-uri nu este disponibilă.", "github_error")
	var result = []
	for item in response["json"]:
		if item is Dictionary and valid_repository(str(item.get("full_name", ""))): result.append({"full_name": str(item["full_name"]), "private": bool(item.get("private", false))})
	return Common.success(result)

func _init(node: Node = null, store: RefCounted = null) -> void:
	owner = node
	vault = store
	transport = Transport.new(node)
	linux = LinuxRuntime.new(node, node.get("plugin") if node != null else null)
	if OS.has_feature("android"):
		termux = TermuxBlender.new(node, node.get("plugin") if node != null else null)

static func desktop_blender() -> bool:
	return not OS.has_feature("android") and OS.get_name() in ["Windows", "Linux"]

static func definitions(github: bool, blender: bool, android_ready: bool = false, bundled_packaged: bool = false, bundled_ready: bool = false) -> Array:
	var result = []
	if github:
		result.append(Common.tool("github_read", "Inspect the configured GitHub repository: repository, branches, issues, pulls or a file/directory. No git CLI required. Lists are paginated, 30 per page.", {"resource": {"type": "string", "enum": ["repository", "branches", "issues", "pulls", "contents"]}, "path": Common.string_field(), "ref": Common.string_field(), "page": {"type": "integer", "minimum": 1, "maximum": 100}}, ["resource"]))
		result.append(Common.tool("github_create_issue", "Create an issue in the configured repository only when the user requested it. This publishes externally. Never put credentials or private project data into the issue.", {"title": Common.string_field(), "body": Common.string_field()}, ["title", "body"], "external"))
	if blender and bundled_packaged:
		result.append(Common.tool("blender_status", "Inspect the Blender CLI bundled in this application. Reports whether Linux and the Blender packages are ready, the measured version, and that Termux is not required.", {}, [], "read"))
		if not bundled_ready:
			result.append(Common.tool("blender_prepare", "Prepare the Blender packages already bundled in this APK. This installs the signed offline Debian packages; it never downloads Blender or contacts a package registry. It can take several minutes and requires Agent AI and Ziva to be stopped. Use only when the user requested Blender or the task needs it.", {}, [], "external"))
		else:
			result.append(Common.tool("blender_run", "Run a saved project Python script with the bundled Blender CLI in background mode. The Godot project is mounted at /workspace. Read declared inputs through os.environ['GODOT_AI_PROJECT_DIR'] and write all generated files under os.environ['GODOT_AI_OUTPUT_DIR']. Blender Python has the full Blender API. Inspect the script first, save a GLB preview for Godot, and verify the returned output paths. PRoot is not a security sandbox. Never download packages or change the runtime through this tool.", {"script": Common.string_field(), "blend": Common.string_field(), "inputs": {"type": "array", "maxItems": 126, "items": {"type": "string"}}, "output_directory": Common.string_field(), "seconds": {"type": "integer", "minimum": 1, "maximum": 1800}}, ["script"], "external"))
	elif blender and android_ready:
		result.append(Common.tool("blender_run", "Run a saved project Python script in the verified Android Termux Blender backend. Inspect the script first. Only declared project inputs are copied; use os.environ['GODOT_AI_PROJECT_DIR'] to read them and os.environ['GODOT_AI_OUTPUT_DIR'] for generated files. Returns imported project output paths. Blender Python has the permissions of its Termux backend; PRoot is not a security sandbox. Never install packages or change runtime configuration through this tool.", {"script": Common.string_field(), "blend": Common.string_field(), "inputs": {"type": "array", "maxItems": 126, "items": {"type": "string"}}, "output_directory": Common.string_field(), "seconds": {"type": "integer", "minimum": 1, "maximum": 600}}, ["script"], "external"))
	elif blender and desktop_blender():
		result.append(Common.tool("blender_run", "Run a saved project Python script in Blender background mode on Windows/Linux. Blender has desktop filesystem access. Inspect the script first, use explicit project output paths, then inspect/import the produced assets with Godot tools.", {"script": Common.string_field(), "blend": Common.string_field(), "seconds": {"type": "integer", "minimum": 1, "maximum": 600}}, ["script"], "external"))
	return result

static func valid_repository(value: String) -> bool:
	var pattern = RegEx.new()
	pattern.compile("^[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+$")
	return pattern.search(value) != null and value.get_slice("/", 1) not in [".", ".."]

func github_request(repository: String, args: Dictionary, cancel: Dictionary = {}, issue: bool = false) -> Dictionary:
	if vault.read("integration_github").is_empty(): return Common.failure("Adaugă tokenul personal GitHub.", "missing_credentials")
	if not valid_repository(repository): return Common.failure("Repository invalid. Folosește proprietar/proiect.", "invalid_repository")
	var route = "/repos/" + repository
	var resource = str(args.get("resource", "repository"))
	var body: Variant = null
	if issue:
		var title = str(args.get("title", "")).strip_edges()
		if title.is_empty() or title.length() > 256 or str(args.get("body", "")).length() > 16000: return Common.failure("Issue invalid.")
		route += "/issues"
		body = {"title": title, "body": str(args.get("body", ""))}
	elif resource == "contents":
		var path = str(args.get("path", ""))
		if path.begins_with("/") or "\\" in path or ".." in path.split("/"): return Common.failure("Cale GitHub invalidă.", "invalid_path")
		var parts = []
		for part in path.split("/", false): parts.append(part.uri_encode())
		route += "/contents/" + "/".join(parts)
		if not str(args.get("ref", "")).is_empty(): route += "?ref=" + str(args["ref"]).uri_encode()
	elif resource in ["branches", "issues", "pulls"]:
		route += "/" + resource + "?per_page=30&page=" + str(clampi(int(args.get("page", 1)), 1, 100))
	elif resource != "repository": return Common.failure("Resursă GitHub invalidă.")
	var headers = _github_headers()
	var response = await transport.request(api_url + route, HTTPClient.METHOD_POST if issue else HTTPClient.METHOD_GET, headers, body, {"cancel": cancel, "allow_http": test_http, "max_bytes": 2 * 1024 * 1024})
	if not response.get("ok", false): return Common.failure(str(response.get("error", "GitHub indisponibil.")), "github_error")
	var value: Variant = response.get("json")
	if resource == "contents" and value is Dictionary and value.get("type") == "file":
		if value.get("encoding") != "base64" or int(value.get("size", 0)) > 256000: return Common.failure("Fișier prea mare sau codificare nesuportată.")
		value = {"path": value.get("path"), "sha": value.get("sha"), "text": Marshalls.base64_to_raw(str(value.get("content", "")).replace("\n", "")).get_string_from_utf8()}
	elif value is Array:
		value = value.slice(0, 30).map(func(item: Dictionary) -> Dictionary:
			var entry = {}
			for field in ["name", "path", "type", "sha", "number", "title", "state", "html_url"]:
				if item.has(field): entry[field] = item[field]
			return entry)
	elif value is Dictionary:
		var entry = {}
		for field in ["full_name", "description", "private", "default_branch", "html_url", "open_issues_count", "number", "title", "state", "permissions"]:
			if value.has(field): entry[field] = value[field]
		value = entry
	else: return Common.failure("Răspuns GitHub invalid.")
	return Common.success(value)

func stop() -> void:
	if linux != null and not linux.preparing: linux.stop()
	github_invalidate()
	if termux != null: termux.stop()
	for pid in processes:
		if OS.is_process_running(pid): OS.kill(pid)
	processes.clear()

func bundled_blender() -> bool:
	if not OS.has_feature("android") or linux == null: return false
	return bool(linux.state.get("packaged", false))

func bundled_blender_ready() -> bool:
	if not bundled_blender(): return false
	var tools = linux.state.get("tools", {})
	return tools is Dictionary and bool(tools.get("blender", {}).get("ready", false))

func blender(executable: String, args: Dictionary, cancel: Dictionary = {}, version: bool = false) -> Dictionary:
	if cancel.get("cancelled", false): return Common.failure("Blender oprit.", "cancelled")
	if bundled_blender():
		if version:
			var status = linux.blender_status()
			if not status.get("ready", false): return status
			return Common.success({"output": str(status.get("version", ""))})
		return await linux.blender(args, cancel)
	if termux != null:
		return await termux.setup("verify") if version else await termux.run(args, cancel)
	if not desktop_blender(): return Common.failure("Blender CLI este disponibil pe Windows și Linux.", "unsupported_platform")
	if executable.is_empty() or not executable.is_absolute_path() or not FileAccess.file_exists(executable): return Common.failure("Selectează executabilul Blender.", "missing_blender")
	var command = PackedStringArray(["--version"])
	if not version:
		var script = Common.project_path(str(args.get("script", "")))
		if script.is_empty() or script.get_extension().to_lower() != "py" or not FileAccess.file_exists(script): return Common.failure("Selectează un script Python din proiect.", "invalid_script")
		command = PackedStringArray(["--background", "--factory-startup", "--disable-autoexec"])
		if not str(args.get("blend", "")).is_empty():
			var blend = Common.project_path(str(args["blend"]))
			if blend.is_empty() or blend.get_extension().to_lower() != "blend" or not FileAccess.file_exists(blend): return Common.failure("Fișier .blend invalid.")
			command.append(ProjectSettings.globalize_path(blend))
		command.append_array(["--python-exit-code", "1", "--python", ProjectSettings.globalize_path(script)])
	var process = OS.execute_with_pipe(executable, command, false)
	if process.is_empty(): return Common.failure("Blender nu a putut porni.")
	var pid = int(process["pid"])
	processes.append(pid)
	var deadline = Time.get_ticks_msec() + (15 if version else clampi(int(args.get("seconds", 120)), 1, 600)) * 1000
	var output = PackedByteArray()
	var interrupted = ""
	while true:
		for key in ["stdio", "stderr"]:
			var chunk: PackedByteArray = process[key].get_buffer(4096)
			if output.size() < 64000: output.append_array(chunk.slice(0, 64000 - output.size()))
		if not OS.is_process_running(pid): break
		if cancel.get("cancelled", false) or not is_instance_valid(owner) or not owner.is_inside_tree(): interrupted = "cancelled"
		elif Time.get_ticks_msec() > deadline: interrupted = "timeout"
		if not interrupted.is_empty():
			OS.kill(pid)
			break
		await owner.get_tree().process_frame
	# Drain trailing data without blocking, including output after process exit.
	for key in ["stdio", "stderr"]:
		for attempt in range(16):
			var chunk: PackedByteArray = process[key].get_buffer(4096)
			if chunk.is_empty(): break
			if output.size() < 64000: output.append_array(chunk.slice(0, 64000 - output.size()))
		process[key].close()
	processes.erase(pid)
	if cancel.get("cancelled", false): interrupted = "cancelled"
	if not interrupted.is_empty(): return Common.failure("Blender oprit: " + interrupted, interrupted)
	var exit_code = OS.get_process_exit_code(pid)
	return Common.success({"exit_code": exit_code, "output": output.get_string_from_utf8()}) if exit_code == 0 else Common.failure("Blender: cod %s\n%s" % [exit_code, output.get_string_from_utf8()], "blender_error")
