@tool
extends VBoxContainer
## Hosts the unmodified official web frontend inside a native Android view.
## Shares only the Ziva process model, never the assistant's harness or credentials.
var bridge: Node
var backend: RefCounted
var management: Window
var version_label: Label
var update_button: Button
var updates_label: Label
var status: Label
var primary: Button
var actions: MenuButton
var hint: Label
var body: Control
var last_embed: Dictionary = {}
var embedded = false
var reload_requested = false
var error_text = ""
const MENU_RELOAD = 0
const MENU_SETTINGS = 1
const MENU_REFRESH = 2
const MENU_RESTART = 3

func configure(native_bridge: Node, model: RefCounted) -> void:
	bridge = native_bridge
	backend = model

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	var bar = HBoxContainer.new()
	bar.name = "ZivaToolbar"
	add_child(bar)
	status = Label.new()
	status.text = "Ziva"
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(status)
	primary = _button(bar, "Instalează Ziva", func() -> void: _action("install"))
	primary.disabled = true
	actions = MenuButton.new()
	actions.name = "ZivaActions"
	actions.text = "⋮"
	actions.tooltip_text = "Acțiuni Ziva"
	actions.custom_minimum_size.x = 32 * EditorInterface.get_editor_scale()
	bar.add_child(actions)
	var menu = actions.get_popup()
	menu.add_item("Reîncarcă interfața", MENU_RELOAD)
	menu.add_item("Instalare și actualizări", MENU_SETTINGS)
	menu.add_item("Verifică starea", MENU_REFRESH)
	menu.add_separator()
	menu.add_item("Repornește sesiunea", MENU_RESTART)
	menu.id_pressed.connect(_menu_action)
	hint = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.max_lines_visible = 3
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(hint)
	body = Control.new()
	body.name = "OfficialZivaUI"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	visibility_changed.connect(_visibility_changed)
	_build_management()
	_bind_backend()
	if backend != null: backend.request("attach")
	_refresh()

func _menu_action(id: int) -> void:
	match id:
		MENU_RELOAD: _sync_embed(true)
		MENU_SETTINGS: _settings()
		MENU_REFRESH:
			if backend != null: backend.refresh()
		MENU_RESTART: _action("restart")

func _bind_backend() -> void:
	if backend != null and not backend.changed.is_connected(_refresh):
		backend.changed.connect(_refresh)
		backend.refresh()

func _button(parent: Node, caption: String, action: Callable) -> Button:
	var button = Button.new()
	button.text = caption
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _action(action: String) -> void:
	if backend == null: return
	var result: Dictionary = backend.request(action, backend.project_directory)
	error_text = "" if result.get("ok", false) else str(result.get("error", "Operația Ziva nu a pornit."))
	_refresh()

func _build_management() -> void:
	management = Window.new()
	management.hide()
	management.title = "Ziva · Instalare și actualizări"
	management.transient = true
	management.exclusive = true
	management.min_size = Vector2i(240, 180)
	management.close_requested.connect(func() -> void: management.hide())
	add_child(management)
	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	management.add_child(scroll)
	var content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	version_label = Label.new()
	version_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(version_label)
	_button(content, "Repară instalarea", func() -> void: _action("install"))
	_button(content, "Verifică actualizări Ziva", func() -> void: _action("check_updates"))
	updates_label = Label.new()
	updates_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(updates_label)
	update_button = _button(content, "Actualizează Ziva", func() -> void: _action("update"))
	_button(content, "Instalare și condiții ↗", func() -> void: OS.shell_open("https://ziva.sh/docs/installation"))

func _settings() -> void:
	_hide_embed()
	var area = get_viewport().get_visible_rect().size
	management.popup_centered(Vector2i(minf(560, area.x * 0.9), minf(420, area.y * 0.85)))

func _refresh() -> void:
	if status == null or backend == null: return
	var state: Dictionary = backend.state
	var enabled = state.get("ok", false) and state.get("enabled", false)
	var installed = bool(state.get("installed", false))
	var working = bool(state.get("busy", false))
	var project = not backend.project_directory.is_empty()
	var linux_ready = bool(state.get("linux_ready", false))
	var ready = _can_embed()
	status.text = "Ziva · Activ" if ready else "Ziva · Pregătire…" if working else "Ziva"
	status.tooltip_text = backend.caption()
	primary.text = "Instalează Ziva"
	primary.tooltip_text = "Instalează pluginul oficial și editorul Linux"
	primary.visible = enabled and not installed and not working
	primary.disabled = not enabled or not linux_ready or working
	var menu = actions.get_popup()
	menu.set_item_disabled(menu.get_item_index(MENU_RELOAD), not ready)
	menu.set_item_disabled(menu.get_item_index(MENU_RESTART), not enabled or not installed or not project)
	hint.text = ""
	if not enabled: hint.text = "Disponibil în aplicația separată Godot AI Ziva."
	elif not linux_ready: hint.text = "Runtime Linux se pregătește automat…"
	elif working and not state.get("running", false): hint.text = str(state.get("message", "Pregătesc Ziva…"))
	elif not installed: hint.text = "Instalează pluginul oficial și Godot Linux (~305 MB descărcați; aproximativ 1,1 GB necesari)."
	elif not project: hint.text = "Deschide un proiect pentru a folosi Ziva."
	elif state.get("running", false) and not state.get("same_project", false): hint.text = "Sesiunea Ziva se mută automat la proiectul curent…"
	elif state.get("status", "") in ["error", "interrupted"]: hint.text = str(state.get("message", "Reia pornirea Ziva."))
	if not error_text.is_empty(): hint.text = error_text
	version_label.text = "Ziva %s · Godot Linux separat\nSesiunea pornește automat cu proiectul și se închide împreună cu editorul." % state.get("version", "")
	var updates: Dictionary = state.get("updates", {})
	updates_label.text = str(updates.get("message", "Poți verifica versiunea oficială disponibilă aici."))
	update_button.visible = bool(updates.get("available", false))
	update_button.disabled = (working and not state.get("running", false)) or not enabled
	hint.tooltip_text = hint.text
	hint.visible = not hint.text.is_empty()

	_sync_embed()

func _can_embed() -> bool:
	return backend != null and not backend.project_directory.is_empty() and backend.state.get("enabled", false) and backend.state.get("running", false) and backend.state.get("same_project", false) and int(backend.state.get("ui_port", 0)) > 0

func _process(_delta: float) -> void:
	if backend == null: _bind_backend()
	if backend == null or not is_visible_in_tree(): return
	# Other native editor toolbars can keep their column wider than a narrow
	# window. Bound this tab independently, including its actions, to the surface.
	var available = maxf(1, get_viewport().get_visible_rect().end.x - global_position.x)
	if not is_equal_approx(custom_maximum_size.x, available): custom_maximum_size.x = available
	if Time.get_ticks_msec() - backend.last_refresh > 1500: backend.refresh()
	_sync_embed()

func _visibility_changed() -> void:
	if not is_visible_in_tree(): _hide_embed()
	elif backend != null: backend.refresh()

func _has_popup() -> bool:
	if actions != null and actions.get_popup().visible: return true
	for window in get_viewport().get_embedded_subwindows():
		if window.visible: return true
	# Desktop native dialogs are separate OS windows; Android uses embedded ones.
	if not get_viewport().gui_embed_subwindows:
		for window in get_tree().root.find_children("*", "Window", true, false):
			if window.visible: return true
	return false

func _bounds() -> Rect2:
	var viewport_rect = get_viewport().get_visible_rect()
	if viewport_rect.size.x <= 0 or viewport_rect.size.y <= 0: return Rect2()
	var rect = body.get_global_rect().intersection(viewport_rect)
	return Rect2((rect.position - viewport_rect.position) / viewport_rect.size, rect.size / viewport_rect.size)

func _sync_embed(force_reload: bool = false) -> void:
	if force_reload: reload_requested = true
	if body == null or not is_inside_tree(): return
	var blocked = management != null and management.visible
	var active = is_visible_in_tree() and _can_embed() and not blocked and not _has_popup()
	if not active:
		_hide_embed()
		return
	var rect = _bounds()
	if rect.size.x <= 0 or rect.size.y <= 0: return
	force_reload = reload_requested
	var key = {"bounds": rect, "port": backend.state.get("ui_port", 0)}
	if key == last_embed and not force_reload: return
	var result: Dictionary = backend.embed(rect, true, force_reload)
	reload_requested = false
	embedded = bool(result.get("ok", false))
	last_embed = key if embedded else {}
	if not embedded:
		# Keep a failed WebView attach visible instead of retrying every frame.
		error_text = str(result.get("error", "Interfața oficială nu s-a deschis."))
		hint.text = error_text
		hint.show()
		last_embed = key

func _hide_embed() -> void:
	if embedded and backend != null: backend.embed(Rect2(), false)
	embedded = false
	last_embed = {}

func _exit_tree() -> void:
	_hide_embed()
	if backend != null and backend.changed.is_connected(_refresh): backend.changed.disconnect(_refresh)
