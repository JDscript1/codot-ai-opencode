@tool
extends VBoxContainer
## Main screen for the optional OpenCode terminal. The native WebView shows the
## real OpenCode TUI; this script only owns lifecycle, status and its bounds.

var bridge: Node
var backend: RefCounted
var status: Label
var primary: Button
var actions: MenuButton
var hint: Label
var progress: ProgressBar
var placeholder: VBoxContainer
var body: Control
var confirmation: ConfirmationDialog
var last_embed: Dictionary = {}
var last_embed_attempt := 0
var embedded := false
var error_text := ""
var restart_pending := false
const MENU_START = 0
const MENU_STOP = 1
const MENU_RESTART = 2
const MENU_INSTALL = 3
const MENU_CANCEL = 4
const MENU_DOCS = 5

func configure(native_bridge: Node, model: RefCounted) -> void:
	bridge = native_bridge
	backend = model

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	var bar := HBoxContainer.new()
	bar.name = "OpenCodeToolbar"
	add_child(bar)
	status = Label.new()
	status.text = "OpenCode"
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(status)
	primary = _button(bar, "Pornește OpenCode", _primary_action)
	primary.disabled = true
	actions = MenuButton.new()
	actions.name = "OpenCodeActions"
	actions.text = "⋮"
	actions.tooltip_text = "Acțiuni OpenCode"
	actions.custom_minimum_size.x = 32 * EditorInterface.get_editor_scale()
	bar.add_child(actions)
	var menu := actions.get_popup()
	menu.add_item("Pornește OpenCode", MENU_START)
	menu.add_item("Oprește OpenCode", MENU_STOP)
	menu.add_item("Repornește OpenCode", MENU_RESTART)
	menu.add_item("Instalează / repune OpenCode", MENU_INSTALL)
	menu.add_item("Anulează instalarea", MENU_CANCEL)
	menu.add_separator()
	menu.add_item("Documentație OpenCode ↗", MENU_DOCS)
	menu.id_pressed.connect(_menu_action)
	body = Control.new()
	body.name = "OpenCodeTerminal"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	placeholder = VBoxContainer.new()
	placeholder.name = "OpenCodePlaceholder"
	placeholder.alignment = BoxContainer.ALIGNMENT_CENTER
	placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	placeholder.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_child(placeholder)
	var title := Label.new()
	title.text = "OpenCode · agent separat în runtime-ul Linux"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", int(16 * EditorInterface.get_editor_scale()))
	placeholder.add_child(title)
	hint = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.max_lines_visible = 5
	placeholder.add_child(hint)
	progress = ProgressBar.new()
	progress.min_value = 0
	progress.max_value = 100
	progress.show_percentage = true
	progress.custom_minimum_size = Vector2(240, 18) * EditorInterface.get_editor_scale()
	progress.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	placeholder.add_child(progress)
	confirmation = ConfirmationDialog.new()
	confirmation.title = "Instalează OpenCode"
	confirmation.dialog_text = "Se instalează Node.js/npm în runtime-ul Debian al aplicației, apoi @opencode/cli 2.2.5.\n\nDescărcare aproximativă: 250 MB. Spațiu necesar: circa 900 MB liberi în memoria privată a aplicației. Proiectul Godot nu este modificat.\n\nContinuă?"
	confirmation.confirmed.connect(func() -> void: _action("install"))
	add_child(confirmation)
	visibility_changed.connect(_visibility_changed)
	_bind_backend()
	_refresh()

func _button(parent: Node, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _bind_backend() -> void:
	if backend != null and not backend.changed.is_connected(_refresh):
		backend.changed.connect(_refresh)
		backend.refresh()

func _primary_action() -> void:
	if backend == null:
		return
	if not backend.state.get("installed", false):
		confirmation.popup_centered(Vector2i(int(420 * EditorInterface.get_editor_scale()), 0))
		return
	_start()

func _start() -> void:
	if backend == null:
		return
	restart_pending = false
	error_text = ""
	var info: Dictionary = bridge.call("mcp_info") if bridge != null and bridge.has_method("mcp_info") else {}
	if not info.get("ok", false):
		error_text = "Serverul MCP nu a pornit: " + str(info.get("error", "necunoscut"))
		_refresh()
		return
	var result: Dictionary = backend.start(int(info.get("port", 0)), str(info.get("token", "")))
	if not result.get("ok", false):
		error_text = str(result.get("error", "OpenCode nu a pornit."))
	backend.refresh()

func _menu_action(id: int) -> void:
	if backend == null:
		return
	match id:
		MENU_START: _start()
		MENU_STOP: _action("stop")
		MENU_RESTART:
			# The native stop is asynchronous; start only after its watcher
			# reports that the previous PTY process is gone.
			restart_pending = true
			_action("stop")
		MENU_INSTALL: confirmation.popup_centered(Vector2i(int(420 * EditorInterface.get_editor_scale()), 0))
		MENU_CANCEL: _action("cancel")
		MENU_DOCS: OS.shell_open("https://opencode.ai/docs/")

func _action(action: String) -> void:
	if backend == null:
		return
	var result: Dictionary = backend.call(action)
	if not result.get("ok", false):
		error_text = str(result.get("error", "Operația OpenCode nu a pornit."))
	backend.refresh()

func _refresh() -> void:
	if status == null or backend == null:
		return
	var state: Dictionary = backend.state
	var running := bool(state.get("running", false))
	var installed := bool(state.get("installed", false))
	var working: bool = backend.busy()
	var linux_ready := bool(state.get("linux_ready", false))
	status.text = backend.caption()
	status.tooltip_text = str(state.get("message", ""))
	primary.visible = not running
	primary.text = "Pornește OpenCode" if installed else "Instalează OpenCode"
	primary.disabled = working or not linux_ready
	progress.visible = str(state.get("status", "")) == "installing"
	progress.value = int(state.get("progress", 0))
	placeholder.visible = not running or not error_text.is_empty()
	var menu := actions.get_popup()
	menu.set_item_disabled(menu.get_item_index(MENU_START), running or not installed or not linux_ready)
	menu.set_item_disabled(menu.get_item_index(MENU_STOP), not running)
	menu.set_item_disabled(menu.get_item_index(MENU_RESTART), not running)
	menu.set_item_disabled(menu.get_item_index(MENU_INSTALL), running or working)
	menu.set_item_disabled(menu.get_item_index(MENU_CANCEL), str(state.get("status", "")) != "installing")
	hint.text = ""
	if not linux_ready:
		hint.text = "Runtime-ul Linux nu este pregătit. Instalează-l din tabul Ziva; OpenCode folosește același Debian."
	elif not installed:
		hint.text = "Instalează Node.js și OpenCode în runtime-ul aplicației. Apoi pornește terminalul și autentifică-te cu /connect în OpenCode."
	elif str(state.get("status", "")) == "installing":
		hint.text = str(state.get("message", "Instalez OpenCode…"))
	elif str(state.get("status", "")) == "error":
		hint.text = str(state.get("message", "OpenCode s-a oprit. Verifică jurnalul terminalului."))
	elif running:
		hint.text = "Terminalul OpenCode rulează pe proiectul curent."
	else:
		hint.text = "Pornește OpenCode, apoi folosește /connect pentru furnizor și /models pentru model. Uneltele Godot apar prin MCP ca godot_search, godot_describe și godot_call."
	if not error_text.is_empty():
		hint.text = error_text
	hint.tooltip_text = hint.text
	_sync_embed()

func _bounds() -> Rect2:
	var viewport_rect := get_viewport().get_visible_rect()
	if viewport_rect.size.x <= 0 or viewport_rect.size.y <= 0:
		return Rect2()
	var rect := body.get_global_rect().intersection(viewport_rect)
	return Rect2((rect.position - viewport_rect.position) / viewport_rect.size, rect.size / viewport_rect.size)

func _has_popup() -> bool:
	if actions != null and actions.get_popup().visible:
		return true
	if confirmation != null and confirmation.visible:
		return true
	for window in get_viewport().get_embedded_subwindows():
		if window.visible:
			return true
	return false

func _process(_delta: float) -> void:
	if backend == null:
		_bind_backend()
	if backend == null or not is_visible_in_tree():
		return
	# Keep this tab inside narrow editor windows regardless of other toolbars.
	var available := maxf(1, get_viewport().get_visible_rect().end.x - global_position.x)
	if not is_equal_approx(custom_maximum_size.x, available):
		custom_maximum_size.x = available
	if Time.get_ticks_msec() - backend.last_refresh > 1200:
		backend.refresh()
	if restart_pending and not backend.busy() and not bool(backend.state.get("running", false)):
		_start()
	_sync_embed()

func _visibility_changed() -> void:
	if not is_visible_in_tree():
		_hide_embed()
	elif backend != null:
		backend.refresh()
	elif bridge != null:
		_bind_backend()

func _sync_embed() -> void:
	if body == null or not is_inside_tree() or backend == null:
		return
	var active := is_visible_in_tree() and bool(backend.state.get("running", false)) and not _has_popup()
	if not active:
		_hide_embed()
		return
	var rect := _bounds()
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	var key := {"bounds": rect, "pid": backend.state.get("pid", 0)}
	if key == last_embed:
		return
	if not embedded and Time.get_ticks_msec() - last_embed_attempt < 3000:
		return
	last_embed_attempt = Time.get_ticks_msec()
	var result: Dictionary = backend.embed(rect, true)
	embedded = bool(result.get("ok", false))
	last_embed = key if embedded else {}
	if embedded:
		error_text = ""
		placeholder.hide()
	else:
		error_text = str(result.get("error", "Terminalul OpenCode nu s-a deschis."))
		hint.text = error_text
		hint.show()
		placeholder.show()

func _hide_embed() -> void:
	if embedded and backend != null:
		backend.embed(Rect2(), false)
	embedded = false
	last_embed = {}
	last_embed_attempt = 0

func _exit_tree() -> void:
	_hide_embed()
	if backend != null and backend.changed.is_connected(_refresh):
		backend.changed.disconnect(_refresh)
