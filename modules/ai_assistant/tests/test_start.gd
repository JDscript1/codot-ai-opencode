extends SceneTree
## Runs inside a real project manager, without an EditorNode or an open project.
var checks = 0
var failures: Array = []
var panel: Control

class Vault:
	extends RefCounted
	var values = {}
	func read(key: String) -> String: return str(values.get(key, ""))
	func store(key: String, value: String) -> bool: values[key] = value; return true
	func erase(key: String) -> bool: return values.erase(key)

class Host:
	extends Node
	var actions: Array = []
	func project_action(action: String) -> void: actions.append(action)

class Provider:
	extends RefCounted
	var contexts: Array = []
	var catalogs: Array = []
	func complete(_profile: Dictionary, messages: Array, tools: Array, _model: String, _effort: String, _cancel: Dictionary, delta: Callable) -> Dictionary:
		contexts.append(messages.duplicate(true))
		catalogs.append(tools.duplicate(true))
		var text = "Te ajut să pregătești proiectul."
		delta.call(text)
		return {"ok": true, "message": {"role": "assistant", "content": text, "tool_calls": []}, "calls": [], "finish": "stop"}

func _initialize() -> void: _run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func _run() -> void:
	await create_timer(1).timeout
	check(not Engine.is_editor_hint(), "Project manager runs without editor mode")
	var manager: Control
	for child in root.get_children():
		if child.get_class() == "ProjectManager": manager = child
	check(manager != null, "A real project manager is present")
	if manager == null: _finish(); return
	var bindings: Dictionary = JSON.parse_string(OS.get_environment("GODOT_AI_QA_BINDINGS"))
	var scripts = {}
	for name in bindings:
		var script = GDScript.new()
		script.source_code = FileAccess.get_file_as_string(OS.get_environment("GODOT_AI_QA_SOURCE").path_join("runtime/" + name + ".gd"))
		var error = script.reload()
		check(error == OK, "Compile " + name + " without a project editor")
		if error != OK: _finish(); return
		for dependency in scripts: script.set(bindings[dependency], scripts[dependency])
		scripts[name] = script
	var host = Host.new()
	manager.add_child(host)
	var vault = Vault.new()
	var asset_tab = manager.find_child("AssetLibraryTab", true, false)
	check(asset_tab != null, "Keep the native Asset Store view")
	var native_host = manager.find_child("AIAssistantStart", true, false)
	if native_host != null:
		panel = native_host.find_child("AIAssistantStartPanel", true, false)
		check(panel != null, "Use the fork's real shared start-screen panel")
		if panel == null: _finish(); return
		panel.plugin = host
		panel.vault = vault
		var matching_buttons = []
		for button in manager.find_children("*", "Button", true, false):
			if button.text == "AI Assistant": matching_buttons.append(button)
		check(matching_buttons.size() == 1, "The native start tab uses the same AI Assistant name as the project editor")
		var ziva_buttons = []
		for button in manager.find_children("*", "Button", true, false):
			if button.text == "Ziva": ziva_buttons.append(button)
		check(ziva_buttons.size() == 1, "Ziva has its own native top tab before project selection")
		var ziva_screen = manager.find_child("ZivaMainScreen", true, false)
		check(ziva_screen != null and ziva_screen.backend != null and ziva_screen.backend.bridge == ziva_screen, "The start-screen Ziva owns its native bridge and process model")
		if ziva_buttons.size() == 1: ziva_buttons[0].pressed.emit()
		await process_frame
		check(ziva_screen != null and ziva_screen.is_visible_in_tree() and ziva_screen.backend.project_directory.is_empty() and ziva_screen.primary.disabled, "Ziva can be configured before opening a project but cannot start an arbitrary project")
		if matching_buttons.size() == 1: matching_buttons[0].pressed.emit()
		check(ziva_screen != null and not ziva_screen.is_visible_in_tree(), "Returning to AI Assistant hides the independent Ziva tab")
	else:
		panel = scripts["panel"].new()
		panel.configure(host, vault, true)
		var container = asset_tab.get_parent()
		for child in container.get_children(): child.hide()
		container.add_child(panel)
		var toggle = Button.new()
		toggle.text = "AI Assistant"
		toggle.theme_type_variation = "MainScreenButton"
		for button in manager.find_children("*", "Button", true, false):
			if button.text == "Asset Store": button.get_parent().add_child(toggle); break
		toggle.toggle_mode = true
		toggle.button_pressed = true
	await process_frame
	check(panel.chat != null and panel.composer != null, "Build the shared chat before project selection")
	check(panel.project_directory.ends_with("/start"), "Use independent start-screen conversation storage")
	check(not panel.file_registry.roots.has(ProjectSettings.globalize_path("res://").trim_suffix("/")), "Do not treat the working directory as a project")
	check(panel.tools.definitions().is_empty(), "Do not advertise scene tools before a project opens")
	check(panel.tools.execute("godot_create_scene", {"type": "Node3D", "name": "Forbidden"}, 2, true).get("code") == "project_required", "Block direct project mutations in start mode")
	check(panel.workspace.catalog().is_empty(), "Do not read project skills from the working directory")
	check(not panel.chat.expand_button.visible, "Hide editor dock expansion before project selection")
	var actions = panel.chat.find_child("StartProjectActions", true, false)
	check(actions != null, "Show compact project creation/import shortcuts")
	for button in actions.get_children():
		if button is Button: button.pressed.emit()
	await process_frame
	check(actions.size.y < 100 * EditorInterface.get_editor_scale(), "Project action row remains compact")
	check(host.actions == ["create", "import", "projects"], "Project shortcuts route to their native host")
	var form: Dictionary = panel.forms["provider"]
	panel._select_issuer("deepseek")
	form["issuer"].item_selected.emit(form["issuer"].selected)
	form["url"].text = ""
	form["key"].text = "sk-fixture-start-deepseek"
	check(panel._save_provider(), "The global provider form restores DeepSeek's hidden empty endpoint")
	var saved_id = str(form.get("editing", ""))
	check(panel._profile_by_id(saved_id).get("url") == "https://api.deepseek.com" and vault.read(saved_id) == "sk-fixture-start-deepseek", "Start-screen DeepSeek connection saves the official endpoint and fixture key")
	vault.erase(saved_id)
	panel.config["providers"] = [{"id": "fixture", "name": "Fixture", "issuer": "openai", "kind": "openai", "url": "https://example.test/v1", "models": [{"id": "fixture-code", "capabilities": {"tools": true}}]}]
	panel._refresh_profiles()
	var provider = Provider.new()
	panel.providers = provider
	panel.mode_picker.select(1)
	await panel._start_chat("Vreau să pregătim un joc 3D.")
	check(provider.contexts.size() == 1 and panel.history.size() == 2, "Complete and persist a chat turn without an open project")
	check("START SCREEN" in str(provider.contexts[0][0].get("content", "")), "Tell the model exactly which project capabilities are absent")
	check(not provider.catalogs[0].any(func(tool: Dictionary) -> bool: return str(tool["name"]).begins_with("godot_") or str(tool["name"]).begins_with("asset_") or tool["name"] == "blender_run"), "Model only receives start-screen tools")
	var registry = scripts["tool_registry"].new(panel._start_definitions(), true)
	check(registry.discover("tool_describe", {"name": "godot_write_file"}).get("code") == "tool_unavailable", "Deferred discovery cannot expose project editing")
	panel.active_definitions = panel._start_definitions()
	panel.full_control.button_pressed = true
	var requested = await panel._execute_call("project_dialog", {"action": "create"})
	await process_frame
	check(requested.get("ok", false) and not requested.get("result", {}).get("completed", true) and host.actions[-1] == "create", "Request a project dialog without falsely claiming creation")
	var target = OS.get_environment("GODOT_AI_QA_OUTPUT").path_join("new-project")
	check(panel.prepare_project_handoff(target), "Save a one-time conversation handoff before editor launch")
	var handoff = scripts["common"].read_json(panel._handoff_path(target), {})
	check(handoff.get("history", []).size() == 2 and handoff.get("selection", {}).get("model") == "fixture-code", "Handoff preserves chat and selected model")
	panel._render_history()
	await create_timer(0.2).timeout
	root.get_texture().get_image().save_png(OS.get_environment("GODOT_AI_QA_OUTPUT").path_join("start-chat.png"))
	panel.open_settings("providers")
	await create_timer(0.2).timeout
	check(panel.settings_navigation.item_count == 6, "Start settings retain assistant sections and runtime package updates without Ziva setup")
	check(not panel.forms.has("ziva") and not panel.section_tabs.has("ziva"), "Independent Ziva management does not depend on assistant settings")
	panel.open_settings("providers")
	panel.settings_window.get_texture().get_image().save_png(OS.get_environment("GODOT_AI_QA_OUTPUT").path_join("start-providers.png"))
	panel.settings_window.hide()
	_finish()

func _finish() -> void:
	var file = FileAccess.open(OS.get_environment("GODOT_AI_QA_OUTPUT").path_join("start-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
	file.close()
	quit(0 if failures.is_empty() else 1)
