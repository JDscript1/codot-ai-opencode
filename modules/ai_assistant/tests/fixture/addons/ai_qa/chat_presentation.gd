extends RefCounted
## Real native widgets and persisted messages, with deterministic tool results.
var host: EditorPlugin
var panel: Control
var chat: Control

func pause() -> void:
	await host.get_tree().create_timer(0.15).timeout

func check(value: bool, description: String) -> void:
	host._check(value, description)

func capture(name: String) -> void:
	host._workspace_capture(OS.get_environment("GODOT_AI_QA_OUTPUT"), name)

func tool(id: String, ok: bool = true) -> void:
	var origin = {"turn_id": "presentation", "origin_label": "Godot AI · probă de interfață"}
	panel._chat_tool_event({"kind": "tool_started", "id": id, "name": "godot_script_diagnostics", "arguments": {"key": "never-display-this-key"}}, origin)
	panel._chat_tool_event({"kind": "tool_result", "id": id, "name": "godot_script_diagnostics", "duration_ms": 145, "executed": true, "result": {"ok": ok, "code": "" if ok else "parse_error", "error": "" if ok else "Linia 12: tip incompatibil. Scriptul necesită corectare.", "result": {"path": "res://scripts/forest.gd", "valid": ok}}}, origin)

func run(qa: EditorPlugin, target: Control) -> void:
	host = qa
	panel = target
	chat = panel.chat
	chat.motion_enabled = false
	chat.clear_messages()
	chat.append_message("user", "Construiește o poiană cu o potecă și copaci.", {"id": "presentation-user", "turn_id": "presentation"})
	chat.begin_work("presentation")
	var origin = {"turn_id": "presentation", "origin_label": "Godot AI · probă de interfață"}
	chat.append_message("assistant", "Verific scena și resursele existente.", origin.merged({"id": "presentation-first"}))
	tool("inspect", false)
	tool("repair", true)
	var anchor = chat.append_message("assistant", "", origin)
	chat.stream_text(anchor, "## Poiana este pregătită\n\nAm așezat copacii în jurul potecii.\n\n")
	await pause()
	var record: Dictionary = anchor.get_meta("message")
	var first: Dictionary = record["blocks"][0]
	var first_id = first["node"].get_instance_id()
	var first_renders = first["renders"]
	chat.stream_text(anchor, "- **Teren:** dealuri joase.\n- **Potecă:** acces spre poiană.\n- **Copaci:** instanțe refolosite.")
	await pause()
	check(first["node"].get_instance_id() == first_id and first["renders"] == first_renders, "Streaming preserves completed Markdown widgets without re-rendering them")
	check(chat.response_groups.size() == 1, "Progress, tools and final text share one task response")
	var group: Dictionary = chat.response_groups[0]
	check(group["row"].find_children("ResponseIdentity", "HBoxContainer", true, false).size() == 1, "A task response has only one assistant identity")
	check(group["progress_toggle"].visible and not group["progress"].visible, "Earlier assistant updates collapse behind the progress control")
	check(not chat.message_records[1]["actions_row"].visible and record["actions_row"].visible, "Only the current response exposes message actions")
	group["progress_toggle"].pressed.emit()
	check(group["progress"].visible and chat.message_records[1]["row"].is_visible_in_tree(), "Progress expansion retains the original update text")
	group["progress_toggle"].pressed.emit()
	chat._show_find(true)
	chat.find_input.text = "resursele existente"
	chat._search_find()
	check(group["progress"].visible and chat.message_records[1]["row"].is_visible_in_tree(), "Searching an earlier update reveals its collapsed progress section")
	chat._show_find(false)
	group["progress_toggle"].pressed.emit()
	chat._jump_to_latest()
	check(group["operations"].size() == 2 and group["operations_toggle"].text.contains("1 cu erori"), "Tool starts and results form one entry each, with visible failure counts")
	check(not group["operations_rows"].visible, "Technical operation details are collapsed by default")
	group["operations_toggle"].pressed.emit()
	check(group["operations_rows"].get_child_count() == 2, "Operation history expands on demand")
	var operation = group["operations_rows"].get_child(0)
	operation.get_child(0).pressed.emit()
	var details = operation.get_child(1)
	var text = details.find_children("*", "RichTextLabel", true, false)[0].get_parsed_text()
	check(details.visible and text.contains("Linia 12") and text.contains("parse_error") and text.contains("res://scripts/forest.gd"), "Failed operations expose a readable error, code and relevant project path")
	check(not text.contains("never-display-this-key"), "Chat operation details exclude arbitrary tool arguments and credentials")
	details.find_children("*", "Button", true, false)[0].pressed.emit()
	check(DisplayServer.clipboard_get() == text, "Operation details can be copied without serialized provider payloads")
	chat.show_running_tool("asset_generate", "Running Image Generator Tool")
	check(chat.running_tools.text == "Running Tools · Image Generator" and chat.running_tools.visible, "The active tool row has a specific compact generator label")
	chat.show_running_tool()
	check(not chat.running_tools.visible, "Running Tools disappears between operations")
	chat.finish_stream(anchor, origin.merged({"id": "presentation-final", "content": record["text"]}))
	chat.set_turn_outcome("presentation", "completed")
	chat.set_turn_metrics("presentation", {"elapsed_ms": 12300, "output_tokens": 254, "cost_usd": 0.002})
	chat.finish_work("presentation", "completed")
	check(group["state"].text == "Rezultat" and not group["state"].text.contains("Verificat"), "Completion distinguishes a delivered result from verified gameplay")
	check(not chat.message_records[1]["metrics_label"].visible and record["metrics_label"].visible, "Usage and cost appear once for the task response")
	group["operations_toggle"].pressed.emit()
	await pause()
	check(group["row"].size.x <= chat.scroll.size.x + 1, "Grouped responses fit the actual narrow workspace")
	capture("chat-response-grouped")
	group["operations_toggle"].pressed.emit()
	await pause()
	capture("chat-response-operations")
	group["operations_toggle"].pressed.emit()
	# File cards attach to this response, with neither a second identity nor an auto-open.
	var image = Image.create(96, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color("456b51"))
	var path = panel.file_registry.directory.path_join("presentation-tree.png")
	panel.file_registry.permit(path)
	image.save_png(path)
	var registered: Dictionary = panel.file_registry.register_file(path, chat.file_scope)
	check(registered.get("ok", false), "Presentation fixture registers a real local image")
	if registered.get("ok", false):
		var id = str(registered["result"]["id"])
		chat.append_message("assistant", "", origin.merged({"id": "presentation-files", "files": [id]}))
		chat.append_message("assistant", "", origin.merged({"id": "presentation-files-again", "files": [id]}))
		await pause()
		check(group["files"].get_child_count() == 1 and group["files"].is_visible_in_tree(), "Repeated publication keeps one compact asset card within the response")
		check(panel.media_view == null or not panel.media_view.visible, "Publishing generated cards never opens the media viewer")
		check(group["progress"].get_child_count() == 1, "File-only results do not create empty progress messages or extra actions")
		capture("chat-response-assets")
		var second_path = panel.file_registry.directory.path_join("presentation-second.png")
		panel.file_registry.permit(second_path)
		image.save_png(second_path)
		var second: Dictionary = panel.file_registry.register_file(second_path, chat.file_scope)
		if second.get("ok", false):
			panel._show_files([id], "reused-provider-call", origin)
			panel._show_files([second["result"]["id"]], "reused-provider-call", origin)
			check(group["files"].get_child_count() == 2, "Reusing a provider call ID cannot hide a newly returned file card")
			panel._show_files([second["result"]["id"]], "reused-provider-call", origin)
			check(group["files"].get_child_count() == 2, "Repeated publication of the same call and file remains deduplicated")
	# Long code copies in full even while only its first lines are displayed.
	chat.append_message("user", "Arată scriptul.", {"id": "code-user", "turn_id": "code"})
	var source = "extends Node\n# A literal marker: ```\n" + "print(\"linie\")\n".repeat(35) + "print(\"ultima linie unică\")"
	var code_anchor = chat.append_message("assistant", "```gdscript\n" + source + "\n```", {"id": "code-answer", "turn_id": "code", "run_status": "completed"})
	var code: Dictionary = code_anchor.get_meta("message")["blocks"][0]
	check(code["source"] == source and code["editor"].get_line_count() == 12 and code["expand"].visible, "Long code folds without interpreting inline backticks as fences")
	code["copy"].pressed.emit()
	check(DisplayServer.clipboard_get() == source, "Copy includes the complete source while the code preview is folded")
	code["expand"].pressed.emit()
	check(code["editor"].text == source and code["expanded"], "Expanded code restores every original line")
	code["expand"].pressed.emit()
	chat._show_find(true)
	chat.find_input.text = "ultima linie unică"
	chat._search_find()
	check(code["expanded"] and code["editor"].text == source, "Searching hidden code automatically unfolds the matching source")
	chat._show_find(false)
	chat._jump_to_latest()
	await pause()
	capture("chat-response-code")
	# Native touch scrolling must not eat deliberate taps on Markdown links.
	var link_anchor = chat.append_message("assistant", "[Documentație](https://docs.godotengine.org/)", {"id": "touch-link", "turn_id": "links"})
	var link: RichTextLabel = link_anchor.get_meta("message")["blocks"][0]["node"]
	await pause()
	chat.follow_bottom = false
	chat.scroll.ensure_control_visible(link)
	await pause()
	var requested: Array = []
	var collect = func(name: String, args: Dictionary) -> void:
		if name == "open_url": requested.append(args.get("url", ""))
	chat.action.disconnect(panel._chat_action)
	chat.action.connect(collect)
	var point = link.get_global_rect().position + Vector2(6, 8) * EditorInterface.get_editor_scale()
	check(chat.scroll.get_global_rect().has_point(point), "Touch link is scrolled into the actual visible phone viewport before input")
	var touch = InputEventScreenTouch.new()
	touch.index = 8
	touch.position = point
	touch.pressed = true
	chat.get_viewport().push_input(touch, true)
	touch.pressed = false
	chat.get_viewport().push_input(touch, true)
	await pause()
	check(requested == ["https://docs.godotengine.org/"], "A touch tap activates the exact native Markdown link without selecting the message")
	check(link.get_selected_text().is_empty(), "Link activation does not leave an accidental text selection")
	touch.pressed = true
	chat.get_viewport().push_input(touch, true)
	var drag = InputEventScreenDrag.new()
	drag.index = 8
	drag.position = point - Vector2(0, 70)
	chat.get_viewport().push_input(drag, true)
	touch.pressed = false
	touch.position = drag.position
	chat.get_viewport().push_input(touch, true)
	check(requested.size() == 1, "Swiping over a Markdown link scrolls instead of opening its URL")
	chat.scroll.ensure_control_visible(link)
	await pause()
	touch.position = link.get_global_rect().position + Vector2(6, 8) * EditorInterface.get_editor_scale()
	touch.pressed = true
	chat.get_viewport().push_input(touch, true)
	await host.get_tree().create_timer(0.65).timeout
	var menus = chat.get_children().filter(func(node: Node) -> bool: return node is PopupMenu and node.visible)
	check(not menus.is_empty() and link.get_selected_text() == "Documentație", "A stationary long press offers copying instead of opening the link")
	if not menus.is_empty():
		menus[-1].id_pressed.emit(0)
		menus[-1].hide()
		check(DisplayServer.clipboard_get() == "Documentație", "The long-press copy action preserves the visible message text")
	touch.pressed = false
	chat.get_viewport().push_input(touch, true)
	check(requested.size() == 1, "Releasing a long press does not activate its underlying link")
	chat.action.disconnect(collect)
	chat.action.connect(panel._chat_action)
	chat._jump_to_latest()
	# A steering message is a chronology boundary, even inside the same task.
	chat.append_message("user", "Adaugă și pini.", {"id": "steer-user", "turn_id": "presentation", "steered": true})
	var continuation = chat.append_message("assistant", "Continui cu cerința nouă.", origin.merged({"id": "steer-answer"}))
	var next: Dictionary = chat.response_groups[-1]
	check(next["epoch"] != group["epoch"] and continuation.get_meta("message")["row"].is_visible_in_tree(), "Steering starts a new visible response segment without moving old text after the user")
	chat.set_turn_metrics("presentation", {"output_tokens": 300})
	check(not record["metrics_label"].visible, "Steering does not duplicate the cumulative task metrics on older response segments")
	# Restoring actual tool messages reconstructs operations, durations and failures.
	panel.history = [
		{"role": "user", "id": "restored-u", "turn_id": "restored", "content": "Corectează scena."},
		{"role": "assistant", "id": "restored-a", "turn_id": "restored", "content": "Verific scriptul.", "run_status": "failed"},
		{"role": "tool", "id": "restored-t", "turn_id": "restored", "tool_name": "godot_script_diagnostics", "tool_call_id": "restored-call", "activity": {"duration_ms": 420, "executed": true}, "content": JSON.stringify({"ok": false, "code": "parse_error", "error": "Tip incompatibil la linia 12."})},
		{"role": "assistant", "id": "restored-final", "turn_id": "restored", "content": "Verificarea nu a trecut; eroarea rămâne de corectat.", "run_status": "failed"}]
	panel._render_history()
	await pause()
	group = chat.response_groups[0]
	check(chat.response_groups.size() == 1 and group["operations"].size() == 1 and group["operations"][0]["duration_ms"] == 420, "Reload reconstructs a grouped response and real operation timing from history")
	check(group["operations"][0]["state"] == "failed" and group["state"].text == "Eșuat", "Reload preserves failed operations and the failed task outcome")
	# Large tool histories allocate rows only when opened, and paginate them.
	chat.clear_messages()
	for index in 37: tool("many-" + str(index))
	group = chat.response_groups[0]
	check(group["operations_rows"].get_child_count() == 0 and group["operations"].size() == 37, "Collapsed long tool histories create no per-operation widgets")
	group["operations_toggle"].pressed.emit()
	check(group["operations_rows"].get_child_count() == 21, "An expanded long tool history initially shows only the latest twenty operations")
	group["operations_rows"].get_child(0).pressed.emit()
	check(group["operations_rows"].get_child_count() == 37, "Earlier operations remain accessible through pagination")
	chat.show_tool_event({"id": "uncertain-job", "kind": "tool_result", "name": "asset_generate", "result": {"ok": false, "code": "submission_unknown", "error": "Sarcina poate exista la furnizor."}}, origin)
	check(group["operations"][-1]["state"] == "unknown" and group["operations_toggle"].text.contains("neconfirmate"), "An uncertain paid submission is distinguished from both confirmed success and definite failure")
	chat.finish_work("presentation", "cancelled")
	chat.clear_messages()
	check(chat.response_groups.is_empty() and chat.operation_cards.is_empty(), "Changing conversations releases response and operation presentation state")
	# Console errors stay out of the workspace until the user asks for them.
	chat.set_error_count(0)
	check(not chat.error_button.visible, "A clean Debugger leaves no error indicator in the header")
	chat.set_error_count(2)
	check(chat.error_button.visible and chat.error_button.text == "2 erori", "Debugger errors appear as one compact header indicator")
	check(chat.error_button.get_theme_color("font_color") == Color("d2b47f"), "Unseen errors use the attention color without moving the chat")
	await pause()
	capture("chat-error-indicator")
	var opened: Array = []
	var collect_errors = func(name: String, args: Dictionary) -> void:
		if name == "errors": opened.append(args)
	chat.action.disconnect(panel._chat_action)
	chat.action.connect(collect_errors)
	chat.error_button.pressed.emit()
	await pause()
	check(opened.size() == 1, "Tapping the error indicator opens the error view on demand")
	check(chat.error_button.get_theme_color("font_color") == Color("8f97a9"), "A viewed indicator stays available in the muted style")
	chat.action.disconnect(collect_errors)
	chat.action.connect(panel._chat_action)
	chat.set_error_count(0)
	check(not chat.error_button.visible, "The indicator hides when the Debugger no longer reports errors")

	await inline_diff_checks()

func inline_diff_checks() -> void:
	chat.clear_messages()
	chat.append_message("user", "Modifică viteza și păstrează originalele.")
	chat.append_message("assistant", "Am actualizat fișierele; modificările exacte sunt mai jos.")
	var source = "--- res://player.gd\n+++ res://player.gd\n@@ -1,1 +1,1 @@\n-speed = 5\n+speed = 12\n"
	for index in range(60): source += "-linie veche %s\n+linie nouă %s\n" % [index, index]
	var items = [{"path": "res://player.gd", "state": "Modificat", "exact": true, "added": 61, "removed": 61, "diff": source}, {"path": "res://nume_șir.gd", "state": "Modificat", "exact": true, "added": 1, "removed": 1, "diff": "--- res://nume_șir.gd\n+++ res://nume_șir.gd\n-eticheta = veche\n+eticheta = [url=unsafe]pădure[/url]\n"}]
	chat.show_changes("inline-fixture", items)
	await pause()
	var section: Control = chat.change_cards["inline-fixture"]
	var bodies = section.find_children("InlineDiffText", "RichTextLabel", true, false)
	check(bodies.size() == 2 and section.find_children("*", "PanelContainer", true, false).is_empty() and section.find_children("*", "CodeEdit", true, false).is_empty(), "Changed files render inline without cards, embedded editors or nested scroll containers")
	check(bodies[0].get_parsed_text().contains("-speed = 5") and bodies[0].get_parsed_text().contains("+speed = 12") and not bodies[0].get_parsed_text().contains("--- res://"), "Inline diffs show exact additions/deletions and keep filename headers separate")
	check(bodies[1].get_parsed_text().contains("[url=unsafe]pădure[/url]") and not bodies[1].bbcode_enabled, "Code markup is literal and Unicode remains intact in inline diffs")
	check(not bodies[0].scroll_active and bodies[0].fit_content and bodies[0].get_parsed_text().split("\n").size() <= 41, "Long diffs initially fit a bounded fragment in the conversation's own scroll")
	var more: Button = section.find_child("InlineDiffMore", true, false)
	check(more != null and more.text.contains("Arată restul"), "Long inline diffs offer an explicit expansion action")
	chat.follow_bottom = false
	more.pressed.emit()
	await pause()
	bodies = section.find_children("InlineDiffText", "RichTextLabel", true, false)
	check(bodies[0].get_parsed_text().contains("linie nouă 59") and not chat.follow_bottom, "Expanding the rest preserves all diff lines and the reader's manual scroll mode")
	chat.show_changes("inline-fixture", items)
	check(section.find_children("InlineDiffText", "RichTextLabel", true, false).size() == 2, "Repeated change updates never duplicate inline file diffs")
	chat.follow_bottom = true
	chat.scroll.scroll_vertical = 0
	await pause()
	capture("chat-inline-diff")
	chat.set_context(100000, 1048576, 2000, false, {"source": "provider", "reserve": 65536, "threshold": 943718})
	check(chat.context_detail.contains("100000 / 1048576") and chat.context_detail.contains("65536") and chat.context_detail.contains("furnizor"), "Context details distinguish measured request usage, model capacity and output reserve")
	chat.clear_messages()
	check(chat.diff_expanded.is_empty(), "Changing conversation releases expanded diff state")
