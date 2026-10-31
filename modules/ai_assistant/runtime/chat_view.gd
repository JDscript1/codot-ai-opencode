@tool
extends HBoxContainer
static var Common: GDScript
static var Providers: GDScript
static var ModelPricing: GDScript
static var Icons: GDScript
static var Markdown: GDScript
static var Diagram: GDScript
var file_registry: RefCounted
var file_scope = ""
signal action(name: String, args: Dictionary)
var sidebar: VBoxContainer
var chats: ItemList
var search: LineEdit
var archived: CheckBox
var history_buttons: Dictionary = {}
var navigation_buttons: Dictionary = {}
var history_requested = -1
var history_active = false
var history_working = false
var title: Label
var thread: VBoxContainer
var scroll: ScrollContainer
var composer: TextEdit
var provider_picker: OptionButton
var model_picker: OptionButton
var mode_picker: OptionButton
var effort_picker: OptionButton
var mode_buttons: Array = []
var plan_cards: Dictionary = {}
var live_plan_card = ""
var question_cards: Dictionary = {}
var playtest_cards: Dictionary = {}
var question_touch_targets: Array = []
var change_cards: Dictionary = {}
var send_button: Button
var status: Label
var context_label: Label
var context_indicator: HBoxContainer
var context_gauge: Control
var context_ratio = -1.0
var context_key = ""
var context_detail = "Context necunoscut"
var diff_expanded: Dictionary = {}
var model_button: Button
var picker: Control
var drawer: PanelContainer
var drawer_title: Label
var drawer_hint: Label
var drawer_step: Label
var drawer_icon: TextureRect
var drawer_back: Button
var drawer_refresh: Button
var catalog_loading = ""
var drawer_stage = "providers"
var drawer_profile = ""
var pending_selection: Dictionary = {}
var drawer_return_focus: Control
var drawer_layout_pending = false
var picker_search: LineEdit
var picker_list: ItemList
var picker_models: Tree
var reasoning_button: Button
var selection_row: HBoxContainer
var composer_controls: HBoxContainer
var compose_column: VBoxContainer
var input_row: HBoxContainer
var controls_spacer: Control
var voice_button: Button
var voice_strip: HBoxContainer
var voice_state: Label
var voice_wave: Control
var voice_finish: Button
var voice_level = 0.0
var catalog: Array = []
var follow_bottom = true
var latest_button: Button
var keyboard_spacer: Control
var following_scroll = false
var last_scroll_value = 0.0
var loaded = 50
var backdrop: GradientTexture2D
var runtime_options: PopupPanel
var options_button: Button
var stop_button: Button
var root_column: VBoxContainer
var compose_panel: PanelContainer
var attachment_chips: HFlowContainer
var expand_button: Button
var error_button: Button
var error_count = 0
var error_seen = 0
var workspace_expanded = false
var message_records: Array = []
var response_groups: Array = []
var response_epoch = 0
var operation_cards: Dictionary = {}
var unseen_updates = 0
var restoring = false
var motion_enabled = true
var icon_cache = {}
var status_revision = 0
var streaming_dirty: Array = []
var stream_clock = 0.0
var attachment_signature = ""
var activity_panel: PanelContainer
var activity_toggle: Button
var activity_counter: Label
var activity_chevron: Label
var activity_indicator: Control
var activity_details: ScrollContainer
var activity_rows: VBoxContainer
var activity_expanded = false
var work_turn = ""
var work_plan: Dictionary = {}
var work_jobs: Array = []
var work_outcome = ""
var work_live = false
var work_message = ""
var work_notice_running = false
var activity_clock = 0.0
var activity_dirty = true
var running_tools: Label
var touch_scroll: Dictionary = {}
var touch_suppress_until = 0
var queue_panel: VBoxContainer
var queue_scroll: ScrollContainer
var queue_rows: VBoxContainer
var stall_label: Label
var find_panel: HBoxContainer
var find_input: LineEdit
var find_count: Label
var find_matches: Array = []
var find_index = -1
var generating = false
var last_output_msec = 0
var stall_clock = 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_apply_theme()
	var gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color("17191f"), Color("17191f")])
	backdrop = GradientTexture2D.new()
	backdrop.gradient = gradient
	backdrop.fill_from = Vector2.ZERO
	backdrop.fill_to = Vector2(1, 1)
	resized.connect(queue_redraw)

	sidebar = VBoxContainer.new()
	sidebar.custom_minimum_size.x = 220 * EditorInterface.get_editor_scale()
	add_child(sidebar)
	var history_header = HBoxContainer.new()
	sidebar.add_child(history_header)
	_compact_button(icon_button(history_header, "Back", "Înapoi la chat", func() -> void: show_history(false)))
	var new_history = button(history_header, "Conversație nouă", func() -> void: action.emit("new", {}))
	new_history.icon = _icon("Add")
	new_history.clip_text = true
	new_history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	navigation_buttons["new_history"] = new_history
	search = LineEdit.new()
	search.placeholder_text = "Caută conversații…"
	sidebar.add_child(search)
	search.text_changed.connect(func(_text: String) -> void: action.emit("history", {}))
	archived = CheckBox.new()
	archived.text = "Arhivate"
	sidebar.add_child(archived)
	archived.toggled.connect(func(_on: bool) -> void: action.emit("history", {}))
	chats = ItemList.new()
	chats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(chats)
	chats.item_selected.connect(func(index: int) -> void: action.emit("open", {"id": chats.get_item_metadata(index)}))
	var history_actions = HFlowContainer.new()
	sidebar.add_child(history_actions)
	for entry in [["Favorite", "Favorite", "favorite"], ["Rename", "Redenumește", "rename"], ["Archive", "Arhivează", "archive"], ["Export", "Exportă", "export"], ["Delete", "Șterge", "delete"]]:
		history_buttons[entry[2]] = icon_button(history_actions, entry[0], entry[1], func() -> void: action.emit(entry[2], {}))
	root_column = VBoxContainer.new()
	root_column.add_theme_constant_override("separation", int(6 * EditorInterface.get_editor_scale()))
	root_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(root_column)
	var header = HBoxContainer.new()
	root_column.add_child(header)
	var history_button = icon_button(header, "Menu", "Istoricul conversațiilor", func() -> void: show_history(not sidebar.visible))
	_compact_button(history_button)
	title = label(header, "Conversație nouă")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	error_button = button(header, "", _open_errors)
	error_button.name = "ErrorIndicator"
	error_button.visible = false
	error_button.focus_mode = Control.FOCUS_NONE
	error_button.tooltip_text = "Deschide erorile din Debugger"
	_compact_button(error_button)
	error_button.add_theme_font_size_override("font_size", int(11 * EditorInterface.get_editor_scale()))
	error_button.add_theme_stylebox_override("normal", _compact_style(Color.TRANSPARENT))
	error_button.add_theme_stylebox_override("hover", _compact_style(Color("2a2d36")))
	error_button.add_theme_stylebox_override("pressed", _compact_style(Color("353947")))
	navigation_buttons["new"] = icon_button(header, "Add", "Conversație nouă", func() -> void: action.emit("new", {}))
	_compact_button(navigation_buttons["new"])
	expand_button = icon_button(header, "Expand", "Extinde chatul și ascunde panourile", _toggle_expanded)
	expand_button.toggle_mode = true
	_compact_button(expand_button)
	navigation_buttons["find"] = icon_button(header, "Search", "Caută în conversație", func() -> void: _toggle_find())
	_compact_button(navigation_buttons["find"])
	navigation_buttons["settings"] = icon_button(header, "Settings", "Setări", func() -> void: action.emit("settings", {}))
	_compact_button(navigation_buttons["settings"])
	navigation_buttons["history"] = history_button
	find_panel = HBoxContainer.new()
	find_panel.name = "ChatFind"
	find_panel.add_theme_constant_override("separation", int(4 * EditorInterface.get_editor_scale()))
	find_panel.visible = false
	root_column.add_child(find_panel)
	find_input = LineEdit.new()
	find_input.placeholder_text = "Caută în conversație"
	find_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	find_input.clear_button_enabled = true
	find_panel.add_child(find_input)
	find_input.text_changed.connect(func(_text: String) -> void: _search_find())
	find_input.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
			find_input.accept_event()
			_step_find(-1 if event.shift_pressed else 1)
		elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			find_input.accept_event()
			_show_find(false))
	find_count = label(find_panel, "0/0")
	find_count.add_theme_font_size_override("font_size", int(11 * EditorInterface.get_editor_scale()))
	find_count.add_theme_color_override("font_color", Color("9aa5b9"))
	var find_prev = icon_button(find_panel, "Back", "Potrivirea anterioară", func() -> void: _step_find(-1))
	var find_next = icon_button(find_panel, "ArrowRight", "Potrivirea următoare", func() -> void: _step_find(1))
	var find_close = icon_button(find_panel, "Close", "Închide căutarea", func() -> void: _show_find(false))
	for control in [find_prev, find_next, find_close]: _compact_button(control)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var thread_area = Control.new()
	thread_area.name = "ConversationArea"
	thread_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thread_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_column.add_child(thread_area)
	thread_area.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.resized.connect(_size_messages)
	var center = HBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	thread = VBoxContainer.new()
	thread.add_theme_constant_override("separation", int(18 * EditorInterface.get_editor_scale()))
	thread.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(thread)
	latest_button = icon_button(thread_area, "ArrowDown", "Mergi la ultimul mesaj și urmărește conversația", _jump_to_latest)
	latest_button.name = "JumpToLatest"
	latest_button.add_theme_stylebox_override("normal", style(Color("293145"), 20))
	latest_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	latest_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	latest_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	latest_button.offset_left = -52 * EditorInterface.get_editor_scale()
	latest_button.offset_top = -52 * EditorInterface.get_editor_scale()
	latest_button.offset_right = -12 * EditorInterface.get_editor_scale()
	latest_button.offset_bottom = -12 * EditorInterface.get_editor_scale()
	latest_button.hide()
	scroll.get_v_scroll_bar().value_changed.connect(_scroll_changed)
	scroll.get_v_scroll_bar().changed.connect(func() -> void:
		if follow_bottom: _follow.call_deferred())
	_build_activity_panel()
	running_tools = label(root_column, "")
	running_tools.hide()
	root_column.move_child(running_tools, activity_panel.get_index())
	running_tools.name = "RunningTools"
	running_tools.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	running_tools.add_theme_font_size_override("font_size", int(11 * EditorInterface.get_editor_scale()))
	stall_label = label(root_column, "")
	stall_label.name = "StallWarning"
	stall_label.visible = false
	stall_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stall_label.add_theme_font_size_override("font_size", int(11 * EditorInterface.get_editor_scale()))
	stall_label.add_theme_color_override("font_color", Color("e0b56a"))
	queue_panel = VBoxContainer.new()
	queue_panel.name = "QueuedMessages"
	queue_panel.add_theme_constant_override("separation", int(6 * EditorInterface.get_editor_scale()))
	queue_panel.visible = false
	root_column.add_child(queue_panel)
	compose_panel = PanelContainer.new()
	var compose_style = style(Color("1e2026"), 22)
	compose_style.set_content_margin_all(10 * EditorInterface.get_editor_scale())
	compose_panel.add_theme_stylebox_override("panel", compose_style)
	root_column.add_child(compose_panel)
	compose_panel.minimum_size_changed.connect(func() -> void: _layout_queue.call_deferred())
	compose_column = VBoxContainer.new()
	compose_panel.add_child(compose_column)
	attachment_chips = HFlowContainer.new()
	attachment_chips.hide()
	compose_column.add_child(attachment_chips)
	input_row = HBoxContainer.new()
	input_row.add_theme_constant_override("separation", int(4 * EditorInterface.get_editor_scale()))
	compose_column.add_child(input_row)
	var attach_button = icon_button(input_row, "Attach", "Atașează o imagine sau un fișier", func() -> void: action.emit("attach", {}))
	composer = TextEdit.new()
	composer.placeholder_text = "Scrie un mesaj…"
	composer.tooltip_text = "@ fișiere · $ noduri · / comenzi"
	composer.custom_minimum_size.y = 32 * EditorInterface.get_editor_scale()
	composer.custom_maximum_size.y = 112 * EditorInterface.get_editor_scale()
	composer.scroll_fit_content_height = true
	composer.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	var input_style = style(Color.TRANSPARENT, 8)
	input_style.set_content_margin_all(3 * EditorInterface.get_editor_scale())
	composer.add_theme_stylebox_override("normal", input_style)
	composer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_row.add_child(composer)
	voice_button = icon_button(input_row, "Microphone", "Dictare", func() -> void: action.emit("voice", {}))
	send_button = icon_button(input_row, "ArrowUp", "Trimite mesajul", func() -> void: action.emit("send", {}))
	stop_button = icon_button(input_row, "Stop", "Oprește agentul", func() -> void: action.emit("stop", {}))
	stop_button.hide()
	composer.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER and not event.shift_pressed and not OS.has_feature("android"):
			composer.accept_event()
			action.emit("steer" if event.ctrl_pressed or event.meta_pressed else "send", {}))
	composer_controls = HBoxContainer.new()
	composer_controls.add_theme_constant_override("separation", int(4 * EditorInterface.get_editor_scale()))
	compose_column.add_child(composer_controls)
	selection_row = HBoxContainer.new()
	selection_row.add_theme_constant_override("separation", int(4 * EditorInterface.get_editor_scale()))
	composer_controls.add_child(selection_row)
	model_button = button(selection_row, "Alege un model", _open_picker)
	model_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	model_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	model_button.clip_text = true
	model_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	model_button.icon = _icon("Models")
	model_button.tooltip_text = "Alege furnizorul și modelul"
	model_button.add_theme_constant_override("icon_max_width", int(20 * EditorInterface.get_editor_scale()))
	reasoning_button = button(selection_row, "Auto", _open_reasoning)
	reasoning_button.icon = _icon("Reasoning")
	reasoning_button.clip_text = true
	reasoning_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	reasoning_button.custom_maximum_size.x = 150 * EditorInterface.get_editor_scale()
	reasoning_button.tooltip_text = "Nivel de raționament"
	reasoning_button.add_theme_constant_override("icon_max_width", int(20 * EditorInterface.get_editor_scale()))
	options_button = button(composer_controls, "Auto", _open_options)
	options_button.icon = _icon("Agent")
	options_button.tooltip_text = "Mod de lucru"
	options_button.add_theme_constant_override("icon_max_width", int(20 * EditorInterface.get_editor_scale()))
	options_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	options_button.clip_text = false
	controls_spacer = Control.new()
	controls_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	composer_controls.add_child(controls_spacer)
	context_indicator = HBoxContainer.new()
	context_indicator.name = "ContextFilling"
	context_indicator.alignment = BoxContainer.ALIGNMENT_CENTER
	composer_controls.add_child(context_indicator)
	context_gauge = Control.new()
	context_gauge.custom_minimum_size = Vector2(18, 18) * EditorInterface.get_editor_scale()
	context_gauge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	context_indicator.add_child(context_gauge)
	context_gauge.draw.connect(func() -> void:
		var scale = EditorInterface.get_editor_scale()
		var gauge_center = context_gauge.size / 2
		context_gauge.draw_arc(gauge_center, 6 * scale, -PI / 2, 3 * PI / 2, 40, Color("41485c"), 2 * scale, true)
		if context_ratio > 0:
			context_gauge.draw_arc(gauge_center, 6 * scale, -PI / 2, -PI / 2 + TAU * context_ratio, 40, Color("edb56b") if context_ratio >= 0.8 else Color("aa8be8"), 2 * scale, true))
	context_label = label(context_indicator, "—")
	context_indicator.gui_input.connect(func(event: InputEvent) -> void:
		if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
			var info = AcceptDialog.new()
			info.title = "Contextul modelului"
			info.dialog_text = context_detail
			add_child(info)
			info.confirmed.connect(info.queue_free)
			info.canceled.connect(info.queue_free)
			info.popup_centered_clamped(Vector2i(420, 220) * EditorInterface.get_editor_scale(), 0.9)
			context_indicator.accept_event())
	context_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	context_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	context_label.add_theme_font_size_override("font_size", int(11 * EditorInterface.get_editor_scale()))
	set_context(0, 0)
	_build_voice_strip()
	send_button.add_theme_stylebox_override("normal", style(Color("7650c5")))
	for control in [model_button, reasoning_button, options_button, voice_button, send_button, stop_button, attach_button]:
		_compact_button(control)
	for control in [attach_button, voice_button, send_button, stop_button]: control.size_flags_vertical = Control.SIZE_SHRINK_END
	for control in [model_button, reasoning_button, options_button]:
		control.add_theme_stylebox_override("normal", _compact_style(Color.TRANSPARENT))
		control.add_theme_stylebox_override("hover", _compact_style(Color("2a2d36")))
		control.add_theme_stylebox_override("pressed", _compact_style(Color("333743")))
		control.add_theme_color_override("font_color", Color("b9c0ce"))
		control.add_theme_color_override("font_hover_color", Color.WHITE)
	var send_surface = _compact_style(Color("7650c5"))
	var send_hover = _compact_style(Color("8662d9"))
	var send_pressed = _compact_style(Color("6846b5"))
	for surface in [send_surface, send_hover, send_pressed]: surface.set_corner_radius_all(int(16 * EditorInterface.get_editor_scale()))
	send_button.custom_minimum_size = Vector2(32, 32) * EditorInterface.get_editor_scale()
	send_button.add_theme_stylebox_override("normal", send_surface)
	send_button.add_theme_stylebox_override("hover", send_hover)
	send_button.add_theme_stylebox_override("pressed", send_pressed)
	provider_picker = OptionButton.new()
	model_picker = OptionButton.new()
	effort_picker = OptionButton.new()
	for hidden in [provider_picker, model_picker, effort_picker]:
		hidden.hide()
		add_child(hidden)
	runtime_options = PopupPanel.new()
	runtime_options.name = "OpțiuniAgent"
	runtime_options.theme = theme
	add_child(runtime_options)
	var options = VBoxContainer.new()
	options.add_theme_constant_override("separation", int(8 * EditorInterface.get_editor_scale()))
	runtime_options.add_child(options)
	label(options, "Mod de lucru")
	mode_picker = OptionButton.new()
	for index in range(Common.MODES.size()): mode_picker.add_icon_item(_icon(Common.MODE_ICONS[index]), Common.MODES[index], Common.MODE_IDS[index])
	mode_picker.hide()
	options.add_child(mode_picker)
	var choices = HBoxContainer.new()
	options.add_child(choices)
	for index in range(Common.MODES.size()):
		var choice = button(choices, Common.MODES[index], func() -> void:
			mode_picker.select(index)
			mode_picker.item_selected.emit(index)
			runtime_options.hide())
		choice.icon = _icon(Common.MODE_ICONS[index])
		choice.toggle_mode = true
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mode_buttons.append(choice)
	effort_picker.item_selected.connect(func(_index: int) -> void: sync_selection())
	_build_drawer()
	keyboard_spacer = Control.new()
	keyboard_spacer.name = "ChatKeyboardInset"
	keyboard_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	keyboard_spacer.hide()
	root_column.add_child(keyboard_spacer)
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree() and picker.visible: _close_drawer())
	root_column.resized.connect(func() -> void: _layout_composer.call_deferred())
	resized.connect(_resize)
	_resize()

func _resize() -> void:
	if sidebar == null: return
	var scale = EditorInterface.get_editor_scale()
	var wide = size.x / scale >= 900
	sidebar.visible = wide if history_requested < 0 else history_requested == 1
	sidebar.custom_minimum_size.x = minf(220 * scale, size.x)
	sidebar.size_flags_horizontal = Control.SIZE_FILL if wide else Control.SIZE_EXPAND_FILL
	root_column.visible = wide or not sidebar.visible
	_size_messages.call_deferred()
	_layout_composer.call_deferred()
	_layout_drawer.call_deferred()

func show_history(visible: bool) -> void:
	history_requested = 1 if visible else 0
	_close_drawer()
	_resize()

func close_mobile_history() -> void:
	if size.x / EditorInterface.get_editor_scale() < 900: show_history(false)

func _layout_composer() -> void:
	if selection_row == null: return
	var scale = EditorInterface.get_editor_scale()
	var compact_height = root_column.size.y < 360 * scale
	var gap = int((3 if compact_height else 6) * scale)
	if root_column.get_theme_constant("separation") != gap: root_column.add_theme_constant_override("separation", gap)
	var queue_gap = int((4 if compact_height else 6) * scale)
	if queue_panel.get_theme_constant("separation") != queue_gap: queue_panel.add_theme_constant_override("separation", queue_gap)
	var compose_surface = compose_panel.get_theme_stylebox("panel")
	var compose_padding = (4 if compact_height else 8) * scale
	if compose_surface.get_content_margin(SIDE_TOP) != compose_padding: compose_surface.set_content_margin_all(compose_padding)
	composer.placeholder_text = "Mesaj…" if root_column.size.x < 280 * EditorInterface.get_editor_scale() else "Scrie un mesaj…"
	voice_button.visible = not stop_button.visible
	_size_selection_chips()
	_layout_drawer()
	_layout_activity.call_deferred()
	_layout_queue.call_deferred()

func _build_voice_strip() -> void:
	var scale = EditorInterface.get_editor_scale()
	voice_strip = HBoxContainer.new()
	voice_strip.name = "VoiceRecording"
	voice_strip.hide()
	compose_column.add_child(voice_strip)
	compose_column.move_child(voice_strip, 0)
	voice_state = label(voice_strip, "")
	voice_state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	voice_state.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	voice_wave = Control.new()
	voice_wave.custom_minimum_size = Vector2(48, 24) * scale
	voice_wave.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	voice_strip.add_child(voice_wave)
	voice_wave.draw.connect(func() -> void:
		for index in 9:
			var height = (3 + voice_level * (18 - abs(index - 4) * 2)) * scale
			voice_wave.draw_rect(Rect2(index * 5 * scale, (voice_wave.size.y - height) / 2, 3 * scale, height), Color("aa8be8")))
	voice_finish = icon_button(voice_strip, "Stop", "Oprește înregistrarea și transcrie", func() -> void: action.emit("voice", {}))
	_compact_button(voice_finish)
	_compact_button(icon_button(voice_strip, "Close", "Anulează înregistrarea sau transcrierea", func() -> void: action.emit("voice_cancel", {})))

func set_voice(phase: String, seconds: int = 0, level: float = 0.0) -> void:
	if voice_strip == null: return
	var active = phase != "idle"
	voice_strip.visible = active
	input_row.visible = not active
	composer_controls.visible = not active
	voice_finish.visible = phase == "recording"
	voice_wave.visible = phase == "recording"
	voice_state.text = ("Înregistrez %02d:%02d / 01:00" % [seconds / 60, seconds % 60]) if phase == "recording" else ("Transcriu…" if phase == "transcribing" else ("Pregătesc microfonul…" if phase == "starting" else "Permite accesul la microfon…"))
	if voice_level != level:
		voice_level = level
		voice_wave.queue_redraw()

func _build_activity_panel() -> void:
	var scale = EditorInterface.get_editor_scale()
	activity_panel = PanelContainer.new()
	activity_panel.name = "AgentActivity"
	var surface = style(Color.TRANSPARENT, 0)
	surface.set_content_margin_all(0)
	activity_panel.add_theme_stylebox_override("panel", surface)
	root_column.add_child(activity_panel)
	var body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	activity_panel.add_child(body)
	activity_toggle = button(body, "", _toggle_activity)
	activity_toggle.name = "ActivityToggle"
	activity_toggle.toggle_mode = true
	activity_toggle.custom_minimum_size.y = 34 * scale
	activity_toggle.add_theme_stylebox_override("normal", _compact_style(Color.TRANSPARENT))
	activity_toggle.add_theme_stylebox_override("pressed", _compact_style(Color("252536")))
	activity_toggle.add_theme_stylebox_override("hover", _compact_style(Color("29283b")))
	var inset = MarginContainer.new()
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	activity_toggle.add_child(inset)
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inset.offset_left = 10 * scale
	inset.offset_right = -10 * scale
	var header = HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", int(8 * scale))
	inset.add_child(header)
	activity_indicator = Control.new()
	activity_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	activity_indicator.custom_minimum_size = Vector2(14, 14) * scale
	activity_indicator.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(activity_indicator)
	activity_indicator.draw.connect(func() -> void:
		var center = activity_indicator.size / 2
		var running = _work_running()
		var ink = Color("b29ae9") if running else (Color("98c9a8") if work_outcome == "completed" else Color("9ba7bf"))
		if work_outcome in ["failed", "limited"]: ink = Color("e4979f")
		elif work_outcome in ["blocked", "cancelled"] or work_plan.get("phase") in ["paused", "blocked"]: ink = Color("d8b47a")
		if running:
			var angle = float(Time.get_ticks_msec()) / 700.0 if motion_enabled else -PI / 2
			activity_indicator.draw_arc(center, 4.5 * scale, angle, angle + PI * 1.4, 20, ink, 1.7 * scale, true)
		else: activity_indicator.draw_circle(center, 3 * scale, ink, true, -1, true))
	status = label(header, "")
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.add_theme_font_size_override("font_size", int(12 * scale))
	status.add_theme_color_override("font_color", Color("c5cbda"))
	activity_counter = label(header, "")
	activity_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	activity_counter.add_theme_font_size_override("font_size", int(11 * scale))
	activity_counter.add_theme_color_override("font_color", Color("bda6e9"))
	activity_chevron = label(header, "▾")
	activity_chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	activity_chevron.add_theme_font_size_override("font_size", int(12 * scale))
	activity_details = ScrollContainer.new()
	activity_details.name = "ActivityDetails"
	activity_details.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	activity_details.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	body.add_child(activity_details)
	activity_rows = VBoxContainer.new()
	activity_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	activity_rows.add_theme_constant_override("separation", int(6 * scale))
	var details_inset = MarginContainer.new()
	details_inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for edge in ["left", "right"]: details_inset.add_theme_constant_override("margin_" + edge, int(10 * scale))
	details_inset.add_theme_constant_override("margin_bottom", int(8 * scale))
	activity_details.add_child(details_inset)
	details_inset.add_child(activity_rows)
	activity_rows.resized.connect(func() -> void: _layout_activity.call_deferred())
	activity_toggle.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and activity_expanded:
			_toggle_activity()
			activity_toggle.accept_event())
	activity_panel.hide()
	activity_details.hide()
	status.hide()

func _toggle_activity() -> void:
	activity_expanded = not activity_expanded
	activity_toggle.set_pressed_no_signal(activity_expanded)
	_refresh_activity()

func reset_work() -> void:
	show_running_tool()
	live_plan_card = ""
	status_revision += 1
	work_turn = ""
	work_plan = {}
	work_jobs = []
	work_outcome = ""
	work_message = ""
	work_live = false
	work_notice_running = false
	activity_expanded = false
	if activity_toggle != null: activity_toggle.set_pressed_no_signal(false)
	_refresh_activity()

func begin_work(turn: String, snapshot: Dictionary = {}, resuming: bool = false) -> void:
	if not resuming or work_turn != turn: reset_work()
	work_turn = turn
	work_live = true
	work_outcome = ""
	work_plan = snapshot.duplicate(true)
	for group in response_groups:
		if group["turn"] == turn:
			group["outcome"] = ""
			_sync_response(group)
	_refresh_activity(true)

func finish_work(turn: String, outcome: String) -> void:
	if work_turn != turn: return
	show_running_tool()
	if live_plan_card == turn: live_plan_card = ""
	work_live = false
	work_notice_running = false
	work_outcome = outcome
	work_message = ""
	for group in response_groups:
		if group["turn"] == turn:
			group["outcome"] = outcome
			for operation in group["operations"]:
				if operation["state"] == "running": operation["state"] = "cancelled"
			if group.has("operations_toggle"): _refresh_operations(group)
			_sync_response(group)
	_refresh_activity(true)

func show_work_plan(snapshot: Dictionary) -> void:
	var turn = str(snapshot.get("turn", ""))
	if not work_turn.is_empty() and work_turn != turn: return
	work_turn = turn
	work_plan = snapshot.duplicate(true)
	_refresh_activity(true)

func show_work_jobs(jobs: Array) -> void:
	if work_jobs == jobs: return
	work_jobs = jobs.duplicate(true)
	_refresh_activity(true)

func restore_work(turn: String, snapshot: Dictionary, outcome: String, running: bool = false) -> void:
	reset_work()
	work_turn = turn
	work_plan = snapshot.duplicate(true)
	work_outcome = outcome
	work_live = running
	if not running and work_plan.get("phase") in ["planning", "executing", "verifying"]:
		work_plan["phase"] = "paused"
	_refresh_activity(true)

func _work_running() -> bool:
	return work_live or work_notice_running or work_jobs.any(func(job: Dictionary) -> bool: return job.get("status") == "running")

func _refresh_activity(rebuild: bool = false) -> void:
	if activity_panel == null: return
	var steps: Array = work_plan.get("steps", [])
	var details = not steps.is_empty() or not work_jobs.is_empty() or work_message.length() > 100
	activity_panel.visible = details or _work_running() or not work_message.is_empty()
	status.visible = activity_panel.visible
	var heading = work_message
	var active = steps.filter(func(step: Dictionary) -> bool: return step.get("status") == "in_progress")
	if heading.is_empty() or " · lucrează" in heading or " · continuă pașii" in heading:
		if work_outcome == "blocked" or work_plan.get("phase") == "blocked": heading = "Sarcină blocată"
		elif work_outcome in ["failed", "limited"]: heading = "Necesită verificare"
		elif work_outcome == "cancelled" or work_plan.get("phase") == "paused": heading = "Sarcină întreruptă"
		elif work_outcome == "completed": heading = "Plan pregătit" if work_plan.get("intent") == "propose" else "Finalizat"
		elif not active.is_empty(): heading = str(active[0].get("step", ""))
		else: heading = "Agentul lucrează…" if _work_running() else "Activitate"
	status.text = heading
	status.tooltip_text = heading
	var done = steps.filter(func(step: Dictionary) -> bool: return step.get("status") == "completed").size()
	activity_counter.text = "%s/%s" % [done, steps.size()] if not steps.is_empty() else ("%s sarcini" % work_jobs.size() if not work_jobs.is_empty() else "")
	activity_counter.visible = not activity_counter.text.is_empty()
	activity_counter.tooltip_text = "%s din %s pași finalizați" % [done, steps.size()] if not steps.is_empty() else "Sarcinile acestei cereri"
	activity_chevron.visible = details
	activity_chevron.text = "▴" if activity_expanded else "▾"
	activity_toggle.disabled = not details
	activity_toggle.tooltip_text = ("Restrânge activitatea" if activity_expanded else "Vezi pașii și sarcinile") if details else heading
	activity_toggle.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if details else Control.CURSOR_ARROW
	activity_details.visible = activity_expanded and details
	activity_indicator.queue_redraw()
	activity_dirty = activity_dirty or rebuild
	if activity_expanded and activity_dirty:
		_rebuild_activity()
		activity_dirty = false
	_layout_activity.call_deferred()
	_layout_queue.call_deferred()

func _activity_heading(text: String) -> void:
	var heading = label(activity_rows, text)
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.add_theme_font_size_override("font_size", int(11 * EditorInterface.get_editor_scale()))
	heading.add_theme_color_override("font_color", Color("9ca6bc"))

func _activity_row(title_text: String, state: String, detail: String = "") -> void:
	var scale = EditorInterface.get_editor_scale()
	var row = HBoxContainer.new()
	row.set_meta("state", state)
	row.add_theme_constant_override("separation", int(8 * scale))
	activity_rows.add_child(row)
	var mark = label(row, str({"completed": "✓", "in_progress": "›", "pending": "○", "blocked": "!", "failed": "!", "cancelled": "Ⅱ"}.get(state, "○")))
	mark.custom_minimum_size.x = 14 * scale
	mark.add_theme_color_override("font_color", Color("9dd0ad") if state == "completed" else (Color("dcb57d") if state in ["blocked", "failed", "cancelled"] else Color("bca1ed")))
	var body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	row.add_child(body)
	var title_text_label = label(body, title_text)
	title_text_label.add_theme_font_size_override("font_size", int(12 * scale))
	title_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_text_label.max_lines_visible = 2
	title_text_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_text_label.tooltip_text = title_text + ("\n" + detail if not detail.is_empty() else "")
	var state_text = str({"completed": "Finalizat", "in_progress": "În lucru", "pending": "De făcut", "blocked": "Blocat", "failed": "Eșuat", "cancelled": "Întrerupt"}.get(state, "De făcut"))
	var caption = label(body, state_text + (" · " + detail.get_slice("\n", 0).left(100) if not detail.is_empty() else ""))
	caption.add_theme_font_size_override("font_size", int(10 * scale))
	caption.add_theme_color_override("font_color", Color("96a2b9"))
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	caption.tooltip_text = state_text + ("\n" + detail if not detail.is_empty() else "")
	if detail.is_empty():
		body.remove_child(caption)
		row.add_child(caption)
		caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		caption.size_flags_horizontal = Control.SIZE_SHRINK_END
		caption.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	if state in ["failed", "blocked"] and "\n" in detail:
		var error = label(body, detail.substr(detail.find("\n") + 1))
		error.add_theme_font_size_override("font_size", int(11 * scale))
		error.add_theme_color_override("font_color", Color("d8b47a"))
		error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		error.max_lines_visible = 2
		error.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		error.tooltip_text = error.text

func _rebuild_activity() -> void:
	for child in activity_rows.get_children():
		activity_rows.remove_child(child)
		child.queue_free()
	var steps: Array = work_plan.get("steps", [])
	if not steps.is_empty():
		_activity_heading("Pași")
		for item in steps: _activity_row(str(item.get("step", "")), str(item.get("status", "pending")))
		if work_plan.get("phase") in ["blocked", "paused"] and not str(work_plan.get("explanation", "")).is_empty():
			var reason = label(activity_rows, str(work_plan["explanation"]))
			reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			reason.max_lines_visible = 3
			reason.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			reason.add_theme_font_size_override("font_size", int(11 * EditorInterface.get_editor_scale()))
			reason.tooltip_text = reason.text
	if not work_jobs.is_empty():
		_activity_heading("Sarcini secundare")
		for job in work_jobs: _activity_row(str(job.get("task", "Sarcină")), "in_progress" if job.get("status") == "running" else str(job.get("status", "pending")), str(job.get("kind", "")))
	if work_message.length() > 100:
		var notice = label(activity_rows, work_message)
		notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		notice.add_theme_font_size_override("font_size", int(12 * EditorInterface.get_editor_scale()))

func _layout_activity() -> void:
	if activity_details == null or not activity_details.visible: return
	var scale = EditorInterface.get_editor_scale()
	for row in activity_rows.get_children():
		if not row.has_meta("state"): continue
		var title_text_label: Label = row.get_child(1).get_child(0)
		var text_width = title_text_label.get_theme_font("font").get_string_size(title_text_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, title_text_label.get_theme_font_size("font_size")).x
		title_text_label.max_lines_visible = 2 if text_width > maxf(60 * scale, title_text_label.get_parent().size.x) else 1
	var cap = maxf(48 * scale, minf(200 * scale, root_column.size.y * 0.30))
	activity_details.custom_minimum_size.y = minf(cap, activity_rows.get_combined_minimum_size().y + 8 * scale)
	activity_details.custom_maximum_size.y = cap

func _compact_style(color: Color) -> StyleBoxFlat:
	var box = style(color, 8)
	var scale = EditorInterface.get_editor_scale()
	box.content_margin_left = 8 * scale
	box.content_margin_right = 8 * scale
	box.content_margin_top = 5 * scale
	box.content_margin_bottom = 5 * scale
	return box

func _compact_button(control: Button) -> void:
	var scale = EditorInterface.get_editor_scale()
	control.custom_minimum_size = Vector2(32 if control.text.is_empty() else 0, 32) * scale
	control.add_theme_font_size_override("font_size", int(12 * scale))
	control.add_theme_constant_override("icon_max_width", int(16 * scale))
	control.add_theme_constant_override("h_separation", int(4 * scale))
	control.add_theme_stylebox_override("normal", _compact_style(Color.TRANSPARENT if control.text.is_empty() else Color("252939")))
	control.add_theme_stylebox_override("hover", _compact_style(Color("2a2d36")))
	control.add_theme_stylebox_override("pressed", _compact_style(Color("353947")))

func _size_selection_chips() -> void:
	if reasoning_button == null: return
	var scale = EditorInterface.get_editor_scale()
	var width = minf(size.x, root_column.size.x) / scale - 20.0
	var very_narrow = width < 230.0
	var compact_reasoning = width < 340.0
	reasoning_button.visible = not very_narrow and not reasoning_button.disabled
	var effort = str(_current_selection().get("effort", ""))
	reasoning_button.text = "" if compact_reasoning else ("Implicit" if effort.is_empty() else effort_label(effort))
	reasoning_button.tooltip_text = "Raționament · " + effort_label(str(_current_selection().get("effort", ""))) + " · schimbă nivelul"
	var effort_width = (32.0 if compact_reasoning else minf(104.0, 34.0 + reasoning_button.get_theme_font("font").get_string_size(reasoning_button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, reasoning_button.get_theme_font_size("font_size")).x)) if reasoning_button.visible else 0.0
	reasoning_button.custom_minimum_size.x = effort_width * scale
	reasoning_button.custom_maximum_size.x = effort_width * scale
	var reserved = options_button.get_combined_minimum_size().x / scale + context_indicator.get_combined_minimum_size().x / scale + 16.0 + (effort_width + 4.0 if reasoning_button.visible else 0.0)
	var model_width = clampf(width - reserved, 62.0, 150.0) * scale
	model_button.custom_minimum_size.x = model_width
	model_button.custom_maximum_size.x = model_width

func _size_messages() -> void:
	if thread == null or scroll == null: return
	var scale = EditorInterface.get_editor_scale()
	thread.custom_minimum_size.x = minf(760 * scale, maxf(180, scroll.size.x - 24 * scale))
	for record in message_records:
		if is_instance_valid(record["card"]) and record["role"] == "user": _size_user(record)
		for block in record["blocks"]:
			if block["kind"] == "diagram": _size_diagram(block)
	for card in plan_cards.values() + question_cards.values():
		var width = minf(440 * scale, maxf(0, scroll.size.x - 36 * scale))
		card["node"].custom_minimum_size.x = 0
		card["node"].custom_maximum_size.x = width
	for card in playtest_cards.values():
		card["node"].custom_minimum_size.x = 0
		card["node"].custom_maximum_size.x = minf(560 * scale, maxf(0, scroll.size.x - 36 * scale))

func style(color: Color, radius: int = 12) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(int(radius * EditorInterface.get_editor_scale()))
	box.content_margin_left = 14 * EditorInterface.get_editor_scale()
	box.content_margin_right = 14 * EditorInterface.get_editor_scale()
	box.content_margin_top = 10 * EditorInterface.get_editor_scale()
	box.content_margin_bottom = 10 * EditorInterface.get_editor_scale()
	return box

func _apply_theme() -> void:
	var skin = Theme.new()
	for type in ["Label", "Button", "LineEdit", "TextEdit", "CodeEdit", "OptionButton", "CheckBox", "RichTextLabel", "ItemList", "PopupMenu"]:
		skin.set_color("font_color", type, Color("e7eaf4"))
		skin.set_color("font_hover_color", type, Color.WHITE)
		skin.set_color("font_selected_color", type, Color.WHITE)
		skin.set_color("font_disabled_color", type, Color("9aa4b4"))
	for type in ["Button", "OptionButton"]:
		skin.set_stylebox("normal", type, style(Color("252939")))
		skin.set_stylebox("hover", type, style(Color("393456")))
		skin.set_stylebox("pressed", type, style(Color("59458c")))
	for type in ["LineEdit", "TextEdit", "ItemList"]:
		var field = style(Color("0d1320"))
		field.border_color = Color("30394e")
		field.set_border_width_all(1)
		skin.set_stylebox("panel" if type == "ItemList" else "normal", type, field)
		skin.set_color("caret_color", type, Color("a78bfa"))
	skin.set_stylebox("panel", "AcceptDialog", style(Color("131723"), 16))
	skin.set_stylebox("panel", "PopupPanel", style(Color("191e2c"), 16))
	skin.set_stylebox("panel", "PopupMenu", style(Color("191e2c"), 12))
	skin.set_stylebox("hover", "PopupMenu", style(Color("393150"), 8))
	skin.set_color("font_separator_color", "PopupMenu", Color("a9b5cb"))
	skin.set_stylebox("selected", "ItemList", style(Color("393150"), 8))
	var plain = StyleBoxEmpty.new()
	var focus = style(Color.TRANSPARENT, 8)
	focus.border_color = Color("9b80d1")
	focus.set_border_width_all(1)
	for type in ["Button", "OptionButton", "LineEdit", "ItemList"]: skin.set_stylebox("focus", type, focus)
	skin.set_stylebox("normal", "RichTextLabel", plain)
	skin.set_stylebox("focus", "RichTextLabel", plain)
	skin.set_stylebox("normal", "CodeEdit", style(Color("0d1320"), 8))
	skin.set_color("background_color", "CodeEdit", Color("0d1320"))
	theme = skin

func button(parent: Node, text: String, callback: Callable) -> Button:
	var control = Button.new()
	control.text = text
	control.custom_minimum_size.y = 44 * EditorInterface.get_editor_scale()
	control.pressed.connect(callback)
	parent.add_child(control)
	return control

func label(parent: Node, text: String) -> Label:
	var control = Label.new()
	control.text = text
	parent.add_child(control)
	return control

func _open_picker() -> void:
	pending_selection.clear()
	drawer_profile = ""
	_show_drawer("providers")

func _build_drawer() -> void:
	# A native control overlay stays inside the chat, including embedded Android editors.
	picker = Control.new()
	picker.name = "ModelDrawer"
	picker.set_as_top_level(true)
	picker.z_index = 10
	add_child(picker)
	picker.hide()
	var scrim = ColorRect.new()
	scrim.color = Color(0.025, 0.035, 0.06, 0.72)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picker.add_child(scrim)
	scrim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: _close_drawer())
	drawer = PanelContainer.new()
	var surface = style(Color("1b2030"), 20)
	surface.border_color = Color("514369")
	surface.set_border_width_all(1)
	drawer.add_theme_stylebox_override("panel", surface)
	picker.add_child(drawer)
	drawer.minimum_size_changed.connect(_queue_drawer_layout)
	var body = VBoxContainer.new()
	body.add_theme_constant_override("separation", int(8 * EditorInterface.get_editor_scale()))
	drawer.add_child(body)
	var handle = ColorRect.new()
	handle.color = Color("625771")
	handle.custom_minimum_size = Vector2(32, 3) * EditorInterface.get_editor_scale()
	handle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(handle)
	var header = HBoxContainer.new()
	body.add_child(header)
	drawer_icon = TextureRect.new()
	drawer_icon.custom_minimum_size = Vector2(24, 24) * EditorInterface.get_editor_scale()
	drawer_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	drawer_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(drawer_icon)
	drawer_title = label(header, "Furnizori")
	drawer_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drawer_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	drawer_title.add_theme_font_size_override("font_size", int(18 * EditorInterface.get_editor_scale()))
	_compact_button(icon_button(header, "Close", "Închide fără a schimba modelul", _close_drawer))
	drawer_step = label(body, "")
	drawer_step.add_theme_color_override("font_color", Color("b5a4d9"))
	picker_search = LineEdit.new()
	picker_search.custom_minimum_size.y = 44 * EditorInterface.get_editor_scale()
	picker_search.right_icon = _icon("Search")
	body.add_child(picker_search)
	picker_search.text_changed.connect(func(_text: String) -> void: _filter_models())
	drawer_hint = label(body, "")
	drawer_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	drawer_hint.add_theme_color_override("font_color", Color("aab5cb"))
	picker_list = ItemList.new()
	picker_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picker_list.custom_minimum_size.y = 88 * EditorInterface.get_editor_scale()
	picker_list.fixed_icon_size = Vector2i(24, 24) * EditorInterface.get_editor_scale()
	picker_list.add_theme_constant_override("icon_margin", int(12 * EditorInterface.get_editor_scale()))
	picker_list.add_theme_constant_override("v_separation", int(20 * EditorInterface.get_editor_scale()))
	body.add_child(picker_list)
	# One tap advances. No double-click/confirmation is needed on touchscreens.
	picker_list.item_selected.connect(_pick_model)
	picker_models = Tree.new()
	picker_models.columns = 2
	picker_models.hide_root = true
	picker_models.column_titles_visible = true
	picker_models.set_column_title(0, "Model")
	picker_models.set_column_title(1, "Intrare / ieșire · 1M")
	picker_models.set_column_expand_ratio(0, 3)
	picker_models.set_column_expand_ratio(1, 2)
	picker_models.add_theme_constant_override("v_separation", int(8 * EditorInterface.get_editor_scale()))
	var model_surface = style(Color("0d1320"))
	model_surface.border_color = Color("30394e")
	model_surface.set_border_width_all(1)
	# Leave room for a complete selectable row below the title on short screens.
	model_surface.content_margin_top = 4 * EditorInterface.get_editor_scale()
	model_surface.content_margin_bottom = 4 * EditorInterface.get_editor_scale()
	picker_models.add_theme_stylebox_override("panel", model_surface)
	picker_models.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picker_models.custom_minimum_size.y = 88 * EditorInterface.get_editor_scale()
	body.add_child(picker_models)
	picker_models.item_selected.connect(func() -> void:
		var item = picker_models.get_selected()
		if item != null: _pick_priced_model.call_deferred(int(item.get_metadata(0)), drawer_profile))
	picker_models.hide()
	var footer = HBoxContainer.new()
	body.add_child(footer)
	drawer_back = button(footer, "Înapoi", _drawer_back)
	drawer_back.icon = _icon("Back")
	drawer_refresh = button(footer, "Actualizează", func() -> void: action.emit("models_refresh", {"profile": drawer_profile}))
	drawer_refresh.icon = _icon("Retry")
	drawer_refresh.tooltip_text = "Actualizează modelele și tarifele folosind conexiunea salvată"
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var manage = button(footer, "Furnizori", func() -> void:
		_close_drawer()
		action.emit("settings", {"section": "providers"}))
	manage.icon = _icon("Settings")
	manage.tooltip_text = "Adaugă un furnizor sau actualizează modelele"
	for control in [drawer_back, drawer_refresh, manage]: _compact_button(control)

func _show_drawer(stage: String) -> void:
	runtime_options.hide()
	if not picker.visible:
		drawer_return_focus = get_viewport().gui_get_focus_owner()
		picker.show()
	drawer_stage = stage
	picker_search.text = ""
	picker_search.visible = stage != "reasoning"
	drawer_back.visible = stage != "providers"
	drawer_step.text = {"providers": "1 / 3 · Furnizor", "models": "2 / 3 · Model", "reasoning": "3 / 3 · Reasoning"}[stage]
	var profile = _drawer_profile_data()
	drawer_refresh.visible = stage == "models" and profile.get("kind") not in ["siwc", "companion"]
	drawer_title.text = {"providers": "Alege furnizorul", "models": str(profile.get("name", "Modele")), "reasoning": "Nivel de raționament"}[stage]
	drawer_icon.texture = _icon("Providers") if stage == "providers" else (provider_icon(profile) if stage == "models" else _icon("Reasoning"))
	picker_search.placeholder_text = "Caută un furnizor sau profil…" if stage == "providers" else "Caută un model la acest furnizor…"
	var model = _model_data(profile, str(pending_selection.get("model", "")))
	drawer_hint.text = "API, abonamente și modele locale, în grupuri separate." if stage == "providers" else ("Alege modelul, apoi nivelul de reasoning." if stage == "models" else str(profile.get("name", "")) + " · " + str(model.get("name", model.get("id", ""))))
	_filter_models()
	_layout_drawer()
	_queue_drawer_layout()
	if stage == "models": picker_models.grab_focus()
	else: picker_list.grab_focus()

func _queue_drawer_layout() -> void:
	if drawer_layout_pending: return
	drawer_layout_pending = true
	_layout_drawer.call_deferred()

func _layout_drawer() -> void:
	drawer_layout_pending = false
	if picker == null or not picker.visible: return
	var scale = EditorInterface.get_editor_scale()
	picker.global_position = root_column.global_position
	picker.size = root_column.size
	var compact = picker.size.y < 340 * scale
	drawer_step.visible = not compact
	drawer_hint.visible = picker.size.y >= 360 * scale
	picker_list.custom_minimum_size.y = (44 if compact else 88) * scale
	picker_models.custom_minimum_size.y = picker_list.custom_minimum_size.y
	var body: VBoxContainer = drawer.get_child(0)
	var separation = int((4 if compact else 8) * scale)
	if body.get_theme_constant("separation") != separation: body.add_theme_constant_override("separation", separation)
	body.get_child(0).visible = not compact
	var list_padding = picker_list.get_theme_stylebox("panel").get_minimum_size().y
	var font_height = picker_list.get_theme_font("font").get_height(picker_list.get_theme_font_size("font_size"))
	var row_height = ceilf(maxf(picker_list.fixed_icon_size.y, font_height)) + picker_list.get_theme_constant("v_separation") + 1
	if drawer_stage == "models":
		font_height = picker_models.get_theme_font("font").get_height(picker_models.get_theme_font_size("font_size"))
		row_height = font_height + 2 * picker_models.get_theme_constant("v_separation") + 1
		list_padding = picker_models.get_theme_stylebox("panel").get_minimum_size().y + font_height + picker_models.get_theme_stylebox("title_button_normal").get_minimum_size().y + 4 * scale
	var content_height = drawer.get_combined_minimum_size().y + maxf(0, mini(picker_list.item_count, 7) * row_height + list_padding - picker_list.custom_minimum_size.y)
	var wanted = Vector2(minf(560 * scale, picker.size.x - 16 * scale), minf(minf(510 * scale, content_height), picker.size.y - 16 * scale))
	drawer.size = wanted
	drawer.position = Vector2((picker.size.x - drawer.size.x) / 2, picker.size.y - drawer.size.y - 8 * scale)

func _close_drawer() -> void:
	if picker == null or not picker.visible: return
	picker.hide()
	pending_selection.clear()
	if is_instance_valid(drawer_return_focus) and drawer_return_focus.is_visible_in_tree(): drawer_return_focus.grab_focus()

func _input(event: InputEvent) -> void:
	if is_visible_in_tree() and scroll != null and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP and scroll.get_global_rect().has_point(event.position):
		follow_bottom = false
		_update_latest_button()
	if _chat_touch(event):
		get_viewport().set_input_as_handled()
		return
	if picker != null and picker.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close_drawer()
		get_viewport().set_input_as_handled()

func _drawer_back() -> void:
	_show_drawer("models" if drawer_stage == "reasoning" else "providers")

func _drawer_profile_data() -> Dictionary:
	for profile in catalog:
		if str(profile["id"]) == drawer_profile: return profile
	return {}

func _model_data(profile: Dictionary, id: String) -> Dictionary:
	for model in profile.get("models", []):
		if str(model["id"]) == id: return model
	return {}

func _current_selection() -> Dictionary:
	return {"profile": provider_picker.get_item_metadata(provider_picker.selected) if provider_picker.selected >= 0 else "", "model": model_picker.get_item_metadata(model_picker.selected) if model_picker.selected >= 0 else "", "effort": effort_picker.get_item_metadata(effort_picker.selected) if effort_picker.selected >= 0 else ""}

func _open_reasoning() -> void:
	pending_selection = _current_selection()
	if str(pending_selection["model"]).is_empty():
		_open_picker()
		return
	drawer_profile = str(pending_selection["profile"])
	_show_drawer("reasoning")

func sync_selection() -> void:
	var key = str(provider_picker.get_selected_metadata()) + ":" + str(model_picker.get_selected_metadata()) if provider_picker.selected >= 0 and model_picker.selected >= 0 else ""
	if key != context_key:
		context_key = key
		set_context(0, 0)
	var selection = _current_selection()
	var profile: Dictionary = {}
	for entry in catalog:
		if entry["id"] == selection["profile"]: profile = entry
	var model = _model_data(profile, str(selection["model"]))
	model_button.text = str(model.get("name", model.get("id", "Alege un model"))) + "  ▾"
	model_button.icon = provider_icon(profile)
	model_button.tooltip_text = (str(profile.get("name", "Furnizor")) + " · " + str(selection["model"]) + "\nSchimbă furnizorul sau modelul") if not model.is_empty() else "Adaugă un furnizor și alege un model"
	reasoning_button.text = effort_label(str(selection["effort"]))
	reasoning_button.disabled = model.is_empty()
	_size_selection_chips()
	if not model.is_empty(): model_button.tooltip_text += "\nRaționament: " + effort_label(str(selection["effort"])) + "\n" + ModelPricing.detail(model.get("pricing", {}))

func effort_label(effort: String) -> String:
	return str({"": "Auto", "none": "Fără", "minimal": "Minim", "low": "Redus", "medium": "Mediu", "high": "Ridicat", "xhigh": "Foarte ridicat", "max": "Maxim"}.get(effort, effort))

func _filter_models() -> void:
	picker_list.clear()
	picker_models.clear()
	var model_root = picker_models.create_item()
	picker_list.visible = drawer_stage != "models"
	picker_models.visible = drawer_stage == "models"
	var query = picker_search.text.to_lower()
	if drawer_stage == "providers":
		for group in ["API cloud", "Abonamente", "Modele locale"]:
			var heading = false
			for profile in catalog:
				var category = "Abonamente" if profile.get("kind") in ["siwc", "companion"] else ("Modele locale" if Providers.hosting(profile) == "local" else "API cloud")
				if category != group or (not query.is_empty() and not query in (str(profile["name"]) + " " + str(profile.get("issuer", ""))).to_lower()): continue
				if not heading:
					label_once(group)
					picker_list.set_item_icon(picker_list.item_count - 1, _icon({"API cloud": "Cloud", "Abonamente": "Accounts", "Modele locale": "Local"}[group]))
					heading = true
				var count = profile.get("models", []).size()
				picker_list.add_item(str(profile["name"]) + " · %s %s" % [count, "model" if count == 1 else "modele"], provider_icon(profile))
				picker_list.set_item_metadata(picker_list.item_count - 1, {"profile": profile["id"]})
	elif drawer_stage == "models":
		var current = _current_selection()
		var profile = _drawer_profile_data()
		if catalog_loading == drawer_profile: drawer_hint.text = "Se încarcă modelele…"
		elif not str(profile.get("model_catalog_error", "")).is_empty(): drawer_hint.text = str(profile["model_catalog_error"])
		else: drawer_hint.text = "Intrare / ieșire per 1M tokeni · tarife actualizate automat."
		for model in profile.get("models", []):
			var text = str(model.get("name", model["id"]))
			if not query.is_empty() and not query in (text + " " + str(model["id"])).to_lower(): continue
			var active = current["profile"] == drawer_profile and current["model"] == model["id"]
			# Keep the same indexed selection metadata across all drawer stages.
			picker_list.add_item(text, _icon("Check" if active else "Models"))
			var item = picker_models.create_item(model_root)
			item.set_text(0, text)
			item.set_text_overrun_behavior(0, TextServer.OVERRUN_TRIM_ELLIPSIS)
			item.set_text(1, ModelPricing.rate_label(model.get("pricing", {})))
			item.set_text_overrun_behavior(1, TextServer.OVERRUN_TRIM_ELLIPSIS)
			item.set_custom_color(1, Color("c1b2e3") if not model.get("pricing", {}).get("stale", false) else Color("d6b380"))
			item.set_metadata(0, picker_list.item_count - 1)
			for column in range(2): item.set_tooltip_text(column, str(model["id"]) + "\n" + ModelPricing.detail(model.get("pricing", {})))
			picker_list.set_item_tooltip(picker_list.item_count - 1, str(model["id"]) + "\n" + ModelPricing.detail(model.get("pricing", {})))
			picker_list.set_item_metadata(picker_list.item_count - 1, {"profile": drawer_profile, "model": model["id"]})
	else:
		var efforts: Array = _model_data(_drawer_profile_data(), str(pending_selection.get("model", ""))).get("efforts", [])
		var current = _current_selection()
		var selected_effort = str(current["effort"]) if current["profile"] == pending_selection.get("profile") and current["model"] == pending_selection.get("model") else ""
		picker_list.add_item("Automat · lasă furnizorul să decidă", _icon("Check" if selected_effort.is_empty() else "Auto"))
		picker_list.set_item_metadata(0, {"effort": ""})
		for effort in efforts:
			if str(effort).is_empty(): continue
			picker_list.add_item(effort_label(str(effort)), _icon("Check" if selected_effort == str(effort) else "Reasoning"))
			picker_list.set_item_metadata(picker_list.item_count - 1, {"effort": str(effort)})
		if efforts.is_empty(): drawer_hint.text += "\nNu sunt disponibile niveluri configurabile pentru acest model."
	if picker_list.item_count == 0:
		if drawer_stage == "models" and query.is_empty():
			label_once("Se încarcă modelele…" if catalog_loading == drawer_profile else "Lista este goală. Apasă Actualizează pentru a căuta modelele.")
		else: label_once("Niciun rezultat pentru căutarea ta.")
		if drawer_stage == "models":
			var empty = picker_models.create_item(model_root)
			empty.set_text(0, picker_list.get_item_text(0))
			empty.set_selectable(0, false)
			empty.set_selectable(1, false)

func label_once(text: String) -> void:
	picker_list.add_item(text)
	picker_list.set_item_disabled(picker_list.item_count - 1, true)

func _pick_priced_model(index: int, profile: String) -> void:
	# Rebuild the next stage after Tree finishes dispatching its selection event.
	if picker.visible and drawer_stage == "models" and drawer_profile == profile: _pick_model(index)

func _pick_model(index: int) -> void:
	if index < 0 or index >= picker_list.item_count: return
	var selected: Variant = picker_list.get_item_metadata(index)
	if not selected is Dictionary: return
	if drawer_stage == "providers":
		drawer_profile = str(selected["profile"])
		_show_drawer("models")
		var profile = _drawer_profile_data()
		if profile.get("models", []).is_empty() and profile.get("kind") not in ["siwc", "companion"]: action.emit("models_refresh", {"profile": drawer_profile})
		else: action.emit("prices_refresh", {"profile": drawer_profile})
	elif drawer_stage == "models":
		pending_selection = selected.duplicate()
		_show_drawer("reasoning")
	else:
		pending_selection["effort"] = selected["effort"]
		action.emit("model", pending_selection.duplicate())
		_close_drawer()

func refresh_history(entries: Array, active: String) -> void:
	chats.clear()
	history_active = false
	for entry in entries:
		chats.add_item(("★ " if entry.get("favorite", false) else "") + str(entry["title"]))
		chats.set_item_metadata(chats.item_count - 1, entry["id"])
		if entry["id"] == active:
			chats.select(chats.item_count - 1)
			history_active = true
			history_buttons["favorite"].tooltip_text = "Elimină din favorite" if entry.get("favorite", false) else "Adaugă la favorite"
			history_buttons["archive"].tooltip_text = "Dezarhivează conversația" if entry.get("archived", false) else "Arhivează conversația"
	history_buttons["export"].tooltip_text = "Exportă conversația în Markdown…"
	_update_history_controls()

func _update_history_controls() -> void:
	for control in history_buttons.values(): control.disabled = history_working or not history_active
	for key in ["new", "new_history"]: navigation_buttons[key].disabled = history_working

func clear_messages() -> void:
	follow_bottom = true
	thread.alignment = BoxContainer.ALIGNMENT_BEGIN
	last_scroll_value = 0.0
	if latest_button != null: latest_button.hide()
	reset_work()
	change_cards.clear()
	diff_expanded.clear()
	plan_cards.clear()
	question_cards.clear()
	playtest_cards.clear()
	question_touch_targets.clear()
	message_records.clear()
	response_groups.clear()
	operation_cards.clear()
	response_epoch = 0
	unseen_updates = 0
	find_matches.clear()
	find_index = -1
	if find_count != null: find_count.text = "0/0"
	streaming_dirty.clear()
	touch_scroll.clear()
	for child in thread.get_children():
		thread.remove_child(child)
		child.queue_free()

func show_questions(record: Dictionary, editable: bool, resumable: bool = false) -> void:
	var id = str(record.get("id", ""))
	if id.is_empty(): return
	var previous = question_cards.get(id, {})
	var position = -1
	if is_instance_valid(previous.get("node")):
		position = previous["node"].get_index()
		thread.remove_child(previous["node"])
		previous["node"].queue_free()
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var surface = style(Color("1c2030"), 12)
	surface.border_color = Color("756397")
	surface.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", surface)
	thread.add_child(panel)
	if position >= 0: thread.move_child(panel, position)
	var body = VBoxContainer.new()
	body.add_theme_constant_override("separation", int(8 * EditorInterface.get_editor_scale()))
	panel.add_child(body)
	var answered = record.get("status") == "answered"
	label(body, "Răspunsuri trimise" if answered else "Clarifică planul").add_theme_color_override("font_color", Color("d5c4f5"))
	var controls = {}
	var card = {"node": panel, "controls": controls, "editing": editable and not answered, "changing": false, "record": record.duplicate(true)}
	question_cards[id] = card
	for question in record.get("questions", []):
		var heading = label(body, str(question["title"]))
		heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var qid = str(question["id"])
		if answered:
			var answer: Dictionary = record.get("answers", {}).get(qid, {})
			var parts: Array = answer.get("labels", []).duplicate()
			if not str(answer.get("text", "")).is_empty(): parts.append(answer["text"])
			var summary = label(body, " · ".join(parts))
			summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			summary.add_theme_color_override("font_color", Color("aab5c9"))
			continue
		var draft: Dictionary = record.get("draft", {}).get(qid, {})
		var choices = {}
		for option in question["options"]:
			var row = HBoxContainer.new()
			row.custom_minimum_size.y = 40 * EditorInterface.get_editor_scale()
			body.add_child(row)
			var check = CheckBox.new()
			check.tooltip_text = str(option["label"])
			check.disabled = not editable
			check.button_pressed = option["id"] in draft.get("selected", [])
			row.add_child(check)
			choices[str(option["id"])] = check
			if editable: question_touch_targets.append({"row": weakref(row), "check": weakref(check)})
			var text = label(row, str(option["label"]) + ("\n" + str(option["description"]) if not str(option.get("description", "")).is_empty() else ""))
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			text.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.gui_input.connect(func(event: InputEvent) -> void:
				if check.disabled: return
				if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
					check.button_pressed = not check.button_pressed
					row.accept_event())
			check.toggled.connect(func(on: bool) -> void:
				if card["changing"]: return
				card["changing"] = true
				if on and not question.get("multiple", false):
					for other in choices.values():
						if other != check: other.set_pressed_no_signal(false)
				card["changing"] = false
				_question_edited(id))
		var custom = TextEdit.new()
		custom.placeholder_text = "Răspuns propriu (opțional)"
		custom.tooltip_text = "Maximum 2000 de caractere"
		custom.editable = editable
		custom.custom_minimum_size.y = 44 * EditorInterface.get_editor_scale()
		custom.custom_maximum_size.y = 90 * EditorInterface.get_editor_scale()
		custom.scroll_fit_content_height = true
		custom.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		custom.text = str(draft.get("text", ""))
		body.add_child(custom)
		controls[qid] = {"choices": choices, "text": custom}
		custom.text_changed.connect(func() -> void: _question_edited(id))
	if not answered:
		var hint = label(body, "Selectează variantele potrivite sau scrie răspunsul propriu.")
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_color_override("font_color", Color("aab5c9"))
		card["hint"] = hint
		var submit = button(body, "Trimite răspunsurile" if record.get("status") == "waiting" else "Trimite și continuă planul", func() -> void: action.emit("plan_answer", {"id": id, "answers": _question_values(id)}))
		submit.clip_text = true
		card["submit"] = submit
		_question_edited(id, false)
		if not editable: hint.text = "Întrebări încheiate fără răspuns."
	elif resumable:
		var resume = button(body, "Continuă planul", func() -> void: action.emit("plan_continue", {"id": id}))
		resume.clip_text = true
		card["resume"] = resume
	_size_messages.call_deferred()
	if previous.is_empty(): _follow.call_deferred()

func _question_values(id: String) -> Dictionary:
	var values = {}
	for qid in question_cards.get(id, {}).get("controls", {}):
		var control: Dictionary = question_cards[id]["controls"][qid]
		var selected = []
		for option in control["choices"]:
			if control["choices"][option].button_pressed: selected.append(option)
		values[qid] = {"selected": selected, "text": control["text"].text}
	return values

func _question_edited(id: String, notify: bool = true) -> void:
	var card: Dictionary = question_cards.get(id, {})
	if card.is_empty() or not card.has("submit"): return
	var values = _question_values(id)
	var complete = values.values().all(func(answer: Dictionary) -> bool: return (not answer["selected"].is_empty() or not answer["text"].strip_edges().is_empty()) and answer["text"].length() <= 2000)
	card["submit"].disabled = not card["editing"] or not complete
	if card["editing"] and card.has("hint"): card["hint"].text = "Răspunsul propriu poate avea cel mult 2000 de caractere." if values.values().any(func(answer: Dictionary) -> bool: return answer["text"].length() > 2000) else "Selectează variantele potrivite sau scrie răspunsul propriu."
	if notify and card["editing"]: action.emit("plan_answer_draft", {"id": id, "answers": values})

func show_plan(snapshot: Dictionary) -> void:
	var id = str(snapshot.get("turn", ""))
	var phase = str(snapshot.get("phase", "planning"))
	var proposal = snapshot.get("intent") == "propose"
	var entries: Array = snapshot.get("steps", [])
	if entries.is_empty(): return
	if not restoring: show_work_plan(snapshot)
	if not plan_cards.has(id) or not is_instance_valid(plan_cards[id]["node"]):
		var panel = PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var surface = style(Color("1c2030"), 12)
		surface.border_color = Color("49415d")
		surface.set_border_width_all(1)
		panel.add_theme_stylebox_override("panel", surface)
		thread.add_child(panel)
		var body = VBoxContainer.new()
		panel.add_child(body)
		var rows = VBoxContainer.new()
		var summary = Label.new()
		var toggle = button(body, "", func() -> void:
			rows.visible = not rows.visible
			summary.visible = not rows.visible and panel.get_meta("phase", "") != "completed" and not summary.text.is_empty()
			panel.set_meta("expanded_by_user", rows.visible))
		toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
		toggle.clip_text = true
		toggle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		toggle.icon = _icon("Plan")
		_compact_button(toggle)
		var reason = label(body, "")
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reason.max_lines_visible = 2
		reason.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		reason.add_theme_color_override("font_color", Color("aab5c9"))
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary.max_lines_visible = 2
		summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		summary.add_theme_font_size_override("font_size", int(13 * EditorInterface.get_editor_scale()))
		body.add_child(summary)
		body.add_child(rows)
		var actions = HBoxContainer.new()
		actions.add_theme_constant_override("separation", int(6 * EditorInterface.get_editor_scale()))
		body.add_child(actions)
		var implement = button(actions, "Implementează planul", func() -> void: action.emit("implement_plan", {"turn": id}))
		implement.icon = _icon("Play")
		implement.tooltip_text = "Pornește execuția cu pașii propuși, trecând în Auto."
		_compact_button(implement)
		var adjust = button(actions, "Ajustează", func() -> void: action.emit("adjust_plan", {"turn": id}))
		adjust.tooltip_text = "Deschide planul în Plan mode pentru modificarea pașilor."
		_compact_button(adjust)
		plan_cards[id] = {"node": panel, "toggle": toggle, "rows": rows, "reason": reason, "summary": summary, "actions": actions}
	var card: Dictionary = plan_cards[id]
	card["actions"].visible = proposal and phase == "completed"
	card["node"].set_meta("phase", phase)
	for row in card["rows"].get_children():
		card["rows"].remove_child(row)
		row.queue_free()
	var done = 0
	for index in range(entries.size()):
		var item: Dictionary = entries[index]
		var state = str(item.get("status", "pending"))
		if state == "completed": done += 1
		var row = HBoxContainer.new()
		card["rows"].add_child(row)
		var mark = label(row, "✓" if state == "completed" else ("›" if state == "in_progress" else str(index + 1) + "."))
		mark.custom_minimum_size.x = 20 * EditorInterface.get_editor_scale()
		mark.add_theme_color_override("font_color", Color("9cd2ad") if state == "completed" else Color("c1a8f2"))
		var text = label(row, str(item.get("step", "")))
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if state == "pending": text.add_theme_color_override("font_color", Color("aab5c9"))
	var heading = {"planning": "Pregătește planul", "executing": "Plan în lucru", "verifying": "Verifică rezultatele", "completed": "Plan propus" if proposal else "Plan finalizat", "paused": "Plan întrerupt", "blocked": "Plan blocat"}.get(phase, "Plan")
	card["toggle"].text = str(heading) + (" · %s pași" % entries.size() if proposal else " · %s/%s" % [done, entries.size()])
	card["reason"].text = str(snapshot.get("explanation", ""))
	card["reason"].tooltip_text = card["reason"].text
	card["reason"].visible = not card["reason"].text.is_empty()
	card["rows"].visible = card["node"].get_meta("expanded_by_user", proposal or phase in ["planning", "blocked"])
	var active_step = ""
	for item in entries:
		if item.get("status") == "in_progress": active_step = str(item.get("step", "")); break
	if active_step.is_empty():
		for item in entries:
			if item.get("status") == "pending": active_step = str(item.get("step", "")); break
	card["summary"].text = active_step
	card["summary"].tooltip_text = active_step
	card["summary"].visible = not card["rows"].visible and phase != "completed" and not active_step.is_empty()
	if not restoring:
		if phase in ["planning", "executing", "verifying"]: live_plan_card = id
		elif live_plan_card == id: live_plan_card = ""
	_follow.call_deferred()
	_size_messages.call_deferred()

func playtest_note(turn: String, markdown: String, verdict: String = "") -> void:
	if turn.is_empty() or (markdown.strip_edges().is_empty() and verdict.is_empty()): return
	var card = playtest_cards.get(turn, {})
	if card.is_empty() or not is_instance_valid(card["node"]):
		card = _playtest_card(turn)
	if not verdict.is_empty() and verdict != card["verdict"]:
		card["verdict"] = verdict
		card["toggle"].add_theme_color_override("font_color", {"pass": Color("9cd2ad"), "fail": Color("e69292"), "blocked": Color("d9b877")}.get(verdict, Color("e7eaf4")))
	if not markdown.strip_edges().is_empty():
		var entry = RichTextLabel.new()
		entry.fit_content = true
		entry.scroll_active = false
		entry.selection_enabled = true
		entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		entry.add_theme_constant_override("line_separation", int(4 * EditorInterface.get_editor_scale()))
		entry.add_theme_constant_override("table_h_separation", int(12 * EditorInterface.get_editor_scale()))
		entry.add_theme_constant_override("table_v_separation", int(7 * EditorInterface.get_editor_scale()))
		card["rows"].add_child(entry)
		Markdown.render(entry, markdown, EditorInterface.get_editor_scale())
		card["entries"] += 1
		if card["rows"].get_child_count() > 30:
			var oldest = card["rows"].get_child(0)
			card["rows"].remove_child(oldest)
			oldest.queue_free()
	var badge = {"pass": " · verdict: pass", "fail": " · verdict: fail", "blocked": " · verdict: blocat"}.get(card["verdict"], "")
	card["toggle"].text = "Playtest · %d măsurători%s" % [card["entries"], badge]
	_follow.call_deferred()
	_size_messages.call_deferred()

func _playtest_card(turn: String) -> Dictionary:
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var surface = style(Color("141d1c"), 12)
	surface.border_color = Color("33514b")
	surface.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", surface)
	thread.add_child(panel)
	var body = VBoxContainer.new()
	panel.add_child(body)
	var rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", int(8 * EditorInterface.get_editor_scale()))
	var toggle = button(body, "", func() -> void: rows.visible = not rows.visible)
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.clip_text = true
	toggle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	toggle.icon = _icon("Play")
	toggle.tooltip_text = "Consola playtest: acțiuni, probe și evenimente măsurate în joc"
	_compact_button(toggle)
	body.add_child(rows)
	var card = {"node": panel, "toggle": toggle, "rows": rows, "entries": 0, "verdict": ""}
	playtest_cards[turn] = card
	return card

func _response_group(metadata: Dictionary) -> Dictionary:
	var turn = str(metadata.get("turn_id", ""))
	if not turn.is_empty() and not response_groups.is_empty():
		var last: Dictionary = response_groups[-1]
		if last["turn"] == turn and last["epoch"] == response_epoch: return last
	var scale = EditorInterface.get_editor_scale()
	var row = HBoxContainer.new()
	row.name = "AssistantResponse"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thread.add_child(row)
	var card = VBoxContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_constant_override("separation", int(10 * scale))
	row.add_child(card)
	var identity = HBoxContainer.new()
	identity.name = "ResponseIdentity"
	identity.add_theme_constant_override("separation", int(6 * scale))
	card.add_child(identity)
	var mark = TextureRect.new()
	mark.custom_minimum_size = Vector2(14, 14) * scale
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.texture = _icon("Agent")
	for profile in catalog:
		if profile["id"] == metadata.get("profile_id"): mark.texture = provider_icon(profile)
	identity.add_child(mark)
	var heading = label(identity, str(metadata.get("origin_label", "Godot AI")))
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.add_theme_font_size_override("font_size", int(11 * scale))
	heading.add_theme_color_override("font_color", Color("8f97a9"))
	var state = label(identity, "")
	state.name = "ResponseState"
	state.add_theme_font_size_override("font_size", int(11 * scale))
	state.hide()
	var progress_toggle = button(card, "", func() -> void: pass)
	progress_toggle.name = "ResponseProgress"
	progress_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	progress_toggle.clip_text = true
	progress_toggle.add_theme_stylebox_override("normal", _compact_style(Color.TRANSPARENT))
	_compact_button(progress_toggle)
	progress_toggle.add_theme_color_override("font_color", Color("8f97a9"))
	progress_toggle.hide()
	var progress = VBoxContainer.new()
	progress.add_theme_constant_override("separation", int(12 * scale))
	progress.hide()
	card.add_child(progress)
	progress_toggle.pressed.connect(func() -> void:
		_preserve_reader()
		progress.visible = not progress.visible
		_refresh_progress_title(progress_toggle, progress))
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", int(8 * scale))
	card.add_child(content)
	var files = HFlowContainer.new()
	files.name = "ResponseFiles"
	files.add_theme_constant_override("h_separation", int(8 * scale))
	files.add_theme_constant_override("v_separation", int(8 * scale))
	files.hide()
	card.add_child(files)
	var footer = VBoxContainer.new()
	footer.add_theme_constant_override("separation", int(4 * scale))
	card.add_child(footer)
	var group = {"index": response_groups.size(), "row": row, "card": card, "state": state, "progress": progress, "progress_toggle": progress_toggle, "content": content, "files": files, "footer": footer, "records": [], "operations": [], "turn": turn, "epoch": response_epoch, "outcome": str(metadata.get("run_status", ""))}
	response_groups.append(group)
	for previous in response_groups.slice(0, -1):
		if not turn.is_empty() and previous["turn"] == turn: _sync_response(previous)
	return group

func _refresh_progress_title(toggle: Button, progress: VBoxContainer) -> void:
	var count = progress.get_child_count()
	toggle.text = ("▴" if progress.visible else "▸") + " Progres · %d " % count + ("actualizare" if count == 1 else "actualizări")

func _sync_response(group: Dictionary) -> void:
	var primary: Dictionary = {}
	var latest = true
	for other in response_groups.slice(int(group["index"]) + 1):
		if not str(group["turn"]).is_empty() and other["turn"] == group["turn"]: latest = false
	for record in group["records"]:
		if not str(record["text"]).strip_edges().is_empty() or record["streaming"]: primary = record
	for record in group["records"]:
		var main = not primary.is_empty() and is_same(record, primary)
		for key in ["actions_row", "metrics_label"]:
			if record.has(key) and record[key].get_parent() != group["footer"]: record[key].reparent(group["footer"])
		if record.has("actions_row"): record["actions_row"].visible = main and latest
		if record.has("metrics_label"): record["metrics_label"].visible = main and latest and not record["metrics_label"].text.is_empty()
		var parent: Node = group["content"] if main else group["progress"]
		if record["row"].get_parent() != parent:
			_preserve_reader()
			record["row"].reparent(parent)
		var empty = str(record["text"]).is_empty() and not record["streaming"] and record["metadata"].get("reasoning_content", "").is_empty()
		record["row"].visible = not empty
	var count = group["progress"].get_child_count()
	group["progress_toggle"].visible = count > 0
	_refresh_progress_title(group["progress_toggle"], group["progress"])
	var outcome = str(group.get("outcome", ""))
	var captions = {"completed": "Rezultat", "cancelled": "Întrerupt", "blocked": "Blocat", "failed": "Eșuat", "limited": "Necesită verificare"}
	group["state"].text = str(captions.get(outcome, "În lucru" if work_live and group["turn"] == work_turn else ""))
	group["state"].visible = not group["state"].text.is_empty()
	group["state"].add_theme_color_override("font_color", Color("8fbf9f") if outcome == "completed" else (Color("d2b47f") if not outcome.is_empty() else Color("9aa2b4")))
	if not primary.is_empty(): primary["column"].set_meta("response_outcome", outcome)

func _preserve_reader() -> void:
	if follow_bottom or restoring: return
	var value = scroll.scroll_vertical
	# Layout changes above the visible content must not pull a reader elsewhere.
	(func() -> void:
		if not follow_bottom: scroll.scroll_vertical = value).call_deferred()

func show_tool_event(event: Dictionary, metadata: Dictionary, caption: String = "") -> void:
	var group = _response_group(metadata)
	var key = str(group["epoch"]) + ":" + str(metadata.get("turn_id", "")) + ":" + str(event.get("id", ""))
	var operation: Dictionary = operation_cards.get(key, {})
	if event.get("kind") == "tool_started" or operation.is_empty() or operation.get("state") != "running":
		operation = {"name": str(event.get("name", "")), "title": caption.trim_prefix("Running ").replace(" Tool", ""), "state": "running", "detail": "", "expanded": false}
		if operation["title"].is_empty(): operation["title"] = operation["name"].replace("_", " ").capitalize()
		group["operations"].append(operation)
		operation_cards[key] = operation
	var result: Dictionary = event.get("result", {})
	if event.get("kind") != "tool_started":
		var code = str(result.get("code", ""))
		operation["state"] = "completed" if result.get("ok", false) else ("unknown" if code in ["submission_unknown", "execution_unknown"] else ("cancelled" if code in ["cancelled", "steered"] else "failed"))
		operation["duration_ms"] = int(event.get("duration_ms", 0))
		operation["replayed"] = bool(event.get("replayed", false))
		operation["executed"] = bool(event.get("executed", false))
		operation["detail"] = str(result.get("error", "")).left(2000)
		operation["code"] = code
		operation["preview"] = event.get("preview", {}).duplicate(true)
		# Only presentation data enters the widget. Provider bodies, bytes and
		# tool arguments remain in the redacted journal, not in every chat row.
		var data: Variant = result.get("result", {})
		if data is Dictionary:
			var facts: Array[String] = []
			for field in ["path", "status", "imported_path", "count", "valid"]:
				if data.has(field) and data[field] is not Dictionary and data[field] is not Array: facts.append(field + ": " + str(data[field]).left(220))
			operation["facts"] = "\n".join(facts)
	_refresh_operations(group)
	_sync_response(group)
	_follow.call_deferred()

func _refresh_operations(group: Dictionary) -> void:
	if not group.has("operations_toggle"):
		var toggle = button(group["card"], "", func() -> void: pass)
		toggle.name = "ResponseOperations"
		toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
		toggle.clip_text = true
		_compact_button(toggle)
		toggle.add_theme_stylebox_override("normal", _compact_style(Color.TRANSPARENT))
		toggle.add_theme_stylebox_override("hover", _compact_style(Color("262a33")))
		toggle.add_theme_stylebox_override("pressed", _compact_style(Color("30343f")))
		toggle.add_theme_color_override("font_color", Color("8f97a9"))
		var rows = VBoxContainer.new()
		rows.hide()
		group["card"].add_child(rows)
		group["card"].move_child(toggle, group["content"].get_index())
		group["card"].move_child(rows, group["content"].get_index())
		group["operations_toggle"] = toggle
		group["operations_rows"] = rows
		group["operations_visible"] = 20
		toggle.pressed.connect(func() -> void:
			_preserve_reader()
			rows.visible = not rows.visible
			_refresh_operations(group))
	var operations: Array = group["operations"]
	var failed = operations.filter(func(op: Dictionary) -> bool: return op["state"] == "failed").size()
	var unknown = operations.filter(func(op: Dictionary) -> bool: return op["state"] == "unknown").size()
	var running = operations.any(func(op: Dictionary) -> bool: return op["state"] == "running")
	group["operations_toggle"].text = ("▴" if group["operations_rows"].visible else "▸") + " Operații · %d" % operations.size() + (" · în lucru" if running else "") + (" · %d cu erori" % failed if failed else "") + (" · %d neconfirmate" % unknown if unknown else "")
	group["operations_toggle"].add_theme_color_override("font_color", Color("d2b47f") if failed or unknown else Color("8f97a9"))
	if not group["operations_rows"].visible: return
	_preserve_reader()
	for child in group["operations_rows"].get_children():
		group["operations_rows"].remove_child(child)
		child.queue_free()
	var hidden = maxi(0, operations.size() - int(group["operations_visible"]))
	if hidden:
		var more = button(group["operations_rows"], "Arată operațiile anterioare · %d" % hidden, func() -> void:
			group["operations_visible"] += 20
			_refresh_operations(group))
		_compact_button(more)
		more.add_theme_stylebox_override("normal", _compact_style(Color.TRANSPARENT))
		more.add_theme_color_override("font_color", Color("8f97a9"))
	for op in operations.slice(hidden):
		var column = VBoxContainer.new()
		group["operations_rows"].add_child(column)
		var heading = button(column, "", func() -> void: pass)
		heading.alignment = HORIZONTAL_ALIGNMENT_LEFT
		heading.clip_text = true
		heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		heading.text = str({"running": "◌ ", "completed": "✓ ", "failed": "! ", "unknown": "? ", "cancelled": "Ⅱ "}.get(op["state"], "")) + op["title"] + (" · " + _duration_label(int(op.get("duration_ms", 0))) if op.get("duration_ms", 0) > 0 else "")
		heading.tooltip_text = op["name"]
		_compact_button(heading)
		heading.add_theme_stylebox_override("normal", _compact_style(Color.TRANSPARENT))
		heading.add_theme_stylebox_override("hover", _compact_style(Color("262a33")))
		heading.add_theme_stylebox_override("pressed", _compact_style(Color("30343f")))
		heading.add_theme_color_override("font_color", Color("d2b47f") if op["state"] in ["failed", "unknown"] else Color("9aa2b4"))
		var details = VBoxContainer.new()
		details.visible = op["expanded"]
		column.add_child(details)
		if op["expanded"]: _operation_details(details, op)
		heading.pressed.connect(func() -> void:
			_preserve_reader()
			op["expanded"] = not op["expanded"]
			if op["expanded"] and details.get_child_count() == 0: _operation_details(details, op)
			details.visible = op["expanded"])

func _operation_details(details: VBoxContainer, op: Dictionary) -> void:
	var text = op["name"] + "\n" + str({"running": "În lucru", "completed": "Operație încheiată", "failed": "Operație eșuată", "unknown": "Rezultat neconfirmat · verifică operația existentă înainte de repetare", "cancelled": "Operație întreruptă"}.get(op["state"], ""))
	if op.get("replayed", false): text += " · rezultat reutilizat, fără execuție nouă"
	if not str(op.get("code", "")).is_empty(): text += "\nCod: " + str(op["code"])
	for field in ["detail", "facts"]:
		if not str(op.get(field, "")).is_empty(): text += "\n" + str(op[field])
	var rich = _text_block(details)["node"]
	rich.add_text(text)
	var preview: Dictionary = op.get("preview", {})
	if not preview.is_empty(): _inspection_preview(details, preview)
	var links = HFlowContainer.new()
	details.add_child(links)
	var copy = button(links, "Copiază detaliile", func() -> void: DisplayServer.clipboard_set(text))
	_compact_button(copy)
	copy.add_theme_stylebox_override("normal", _compact_style(Color.TRANSPARENT))
	var journal = button(links, "Jurnal", func() -> void: action.emit("settings", {"section": "journal"}))
	_compact_button(journal)
	journal.add_theme_stylebox_override("normal", _compact_style(Color.TRANSPARENT))
	for control in [copy, journal]: control.add_theme_color_override("font_color", Color("9aa2b4"))

func _inspection_preview(parent: Control, preview: Dictionary) -> void:
	var caption = str({"read": "Fragment citit", "search": "Rezultate căutare", "files": "Fișiere găsite"}.get(preview["kind"], "Inspecție"))
	if not str(preview.get("query", "")).is_empty(): caption += " · " + str(preview["query"])
	var heading = label(parent, caption)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_color_override("font_color", Color("aabbd3"))
	for item in preview.get("items", []):
		var link = Common.project_link(str(item["path"]) + ":%d:%d" % [int(item.get("line", 1)), int(item.get("column", 1))])
		if link.is_empty(): continue
		var path = _text_block(parent)["node"]
		path.name = "InspectionPath"
		path.push_meta(link, RichTextLabel.META_UNDERLINE_ALWAYS)
		path.push_color(Color("a7c6fa"))
		path.add_text(str(item["path"]) + (":%d" % int(item.get("line", 1)) if preview["kind"] != "files" else ""))
		path.pop(); path.pop()
		if not item.get("rows", []).is_empty():
			var block = _code_block(parent)
			block["language_id"] = str(item["path"]).get_extension()
			block["rows"] = item["rows"]
			var lines: Array[String] = []
			for row in item["rows"]: lines.append(str(row["text"]))
			block["source"] = "\n".join(lines)
			_update_code(block)
			if int(item.get("excerpt_column", 1)) > 1:
				var excerpt = label(parent, "Fragmentul potrivirii începe la coloana %d." % int(item["excerpt_column"]))
				excerpt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if preview.get("items", []).is_empty() or preview.get("empty", false): label(parent, "Fișier gol." if preview["kind"] == "read" else "Niciun rezultat.")
	if preview.get("partial", false):
		var note = label(parent, "Afișare parțială · deschide fișierul pentru conținutul actual complet.")
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_color_override("font_color", Color("dfb97d"))

func append_message(role: String, text: String, metadata: Dictionary = {}, rich: bool = true) -> RichTextLabel:
	_preserve_reader()
	var group = _response_group(metadata) if role == "assistant" else {}
	if role == "user": response_epoch += 1
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(thread if group.is_empty() else group["content"]).add_child(row)
	if role == "user":
		var spacer = Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_SHRINK_END if role == "user" else Control.SIZE_EXPAND_FILL
	var surface = style(Color.TRANSPARENT, 0)
	surface.set_content_margin_all(0)
	card.add_theme_stylebox_override("panel", surface)
	row.add_child(card)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", int(6 * EditorInterface.get_editor_scale()))
	card.add_child(column)
	if role == "user":
		var identity = HBoxContainer.new()
		identity.name = "UserIdentity"
		identity.alignment = BoxContainer.ALIGNMENT_END
		column.add_child(identity)
		var you = label(identity, "Tu")
		you.add_theme_font_size_override("font_size", int(11 * EditorInterface.get_editor_scale()))
		you.add_theme_color_override("font_color", Color("8f97a9"))
	var body = VBoxContainer.new()
	column.add_child(body)
	var anchor = RichTextLabel.new()
	anchor.hide()
	column.add_child(anchor)
	var record = {"role": role, "row": row, "card": card, "column": column, "body": body, "blocks": [], "text": text, "metadata": metadata.duplicate(true), "rich": rich, "streaming": role == "assistant" and not metadata.has("id"), "group_index": group.get("index", -1)}
	anchor.set_meta("message", record)
	message_records.append(record)
	_render_content(record)
	_render_reasoning(record)
	if role == "user": _size_user(record)
	for attachment in metadata.get("attachments", []):
		if attachment.has("data"):
			var preview = Image.new()
			if preview.load_png_from_buffer(Marshalls.base64_to_raw(str(attachment["data"]))) == OK:
				var picture = TextureRect.new()
				picture.texture = ImageTexture.create_from_image(preview)
				picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				picture.custom_minimum_size.y = 112 * EditorInterface.get_editor_scale()
				column.add_child(picture)
	for file_id in metadata.get("files", []):
		if group.is_empty(): _file_card(column, str(file_id))
		else:
			if group["files"].find_child("File_" + str(file_id), true, false) == null: _file_card(group["files"], str(file_id))
			group["files"].show()
	if role == "assistant":
		if not text.is_empty() or record["streaming"]:
			group["records"].append(record)
			_message_actions(record)
			_refresh_metrics(record)
		else: row.hide()
		_sync_response(group)
	else:
		for item in message_records: _refresh_message_controls(item)
	if motion_enabled and not restoring and is_visible_in_tree():
		row.modulate.a = 0.0
		create_tween().tween_property(row, "modulate:a", 1.0, 0.12)
	_follow.call_deferred()
	if not restoring and not follow_bottom:
		unseen_updates += 1
		_update_latest_button()
	return anchor

func _markdown(target: RichTextLabel, text: String) -> void:
	Markdown.render(target, text, EditorInterface.get_editor_scale())

func _size_user(record: Dictionary) -> void:
	var scale = EditorInterface.get_editor_scale()
	var available = maxf(thread.size.x, thread.custom_minimum_size.x)
	var font = get_theme_font("font", "Label")
	var width = 0.0
	for line in str(record["text"]).split("\n"):
		width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, get_theme_font_size("font_size", "Label")).x)
	var wanted = minf(maxf(64 * scale, width), available * 0.74)
	if not record["metadata"].get("attachments", []).is_empty() or not record["metadata"].get("files", []).is_empty(): wanted = minf(320 * scale, available * 0.74)
	record["card"].custom_minimum_size.x = wanted
	record["card"].custom_maximum_size.x = wanted

func _text_block(parent: Node) -> Dictionary:
	var text = RichTextLabel.new()
	text.fit_content = true
	text.scroll_active = false
	text.selection_enabled = true
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", int(14 * EditorInterface.get_editor_scale()))
	text.add_theme_constant_override("line_separation", int(4 * EditorInterface.get_editor_scale()))
	text.add_theme_constant_override("table_h_separation", int(12 * EditorInterface.get_editor_scale()))
	text.add_theme_constant_override("table_v_separation", int(7 * EditorInterface.get_editor_scale()))
	text.meta_clicked.connect(func(value: Variant) -> void:
		if value is Dictionary:
			var link = Common.project_link(str(value.get("path", "")) + ":%d:%d" % [int(value.get("line", 1)), int(value.get("column", 1))])
			if not link.is_empty(): action.emit("project_open", link)
		elif Common.parse_url(str(value), true).get("ok", false): action.emit("open_url", {"url": str(value)}))
	parent.add_child(text)
	return {"kind": "text", "node": text, "source": "", "renders": 0}

func _code_block(parent: Node) -> Dictionary:
	var scale = EditorInterface.get_editor_scale()
	var panel = PanelContainer.new()
	var surface = style(Color("0d1320"), 12)
	surface.set_content_margin_all(8 * scale)
	panel.add_theme_stylebox_override("panel", surface)
	parent.add_child(panel)
	var box = VBoxContainer.new()
	panel.add_child(box)
	var header = HBoxContainer.new()
	box.add_child(header)
	var language = label(header, "Cod")
	language.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	language.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	language.add_theme_color_override("font_color", Color("9faac0"))
	var editor = CodeEdit.new()
	editor.editable = false
	editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	editor.scroll_fit_content_height = true
	editor.custom_minimum_size.y = 38 * scale
	editor.custom_maximum_size.y = 360 * scale
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor.add_theme_font_size_override("font_size", int(13 * scale))
	var block = {"kind": "code", "node": panel, "editor": editor, "language": language, "source": "", "language_id": "", "expanded": false, "renders": 0}
	var copy = icon_button(header, "Copy", "Copiază codul complet", func() -> void: DisplayServer.clipboard_set(block["source"]))
	_compact_button(copy)
	block["copy"] = copy
	box.add_child(editor)
	var expand = button(box, "", func() -> void:
		_preserve_reader()
		block["expanded"] = not block["expanded"]
		_update_code(block, true))
	expand.alignment = HORIZONTAL_ALIGNMENT_LEFT
	expand.clip_text = true
	_compact_button(expand)
	expand.hide()
	block["expand"] = expand
	return block

func _update_code(block: Dictionary, force: bool = false) -> void:
	var source = str(block["source"])
	var lines = source.split("\n")
	var long_code = lines.size() > 18
	block["expand"].visible = long_code
	block["expand"].text = "Restrânge codul" if block["expanded"] else "Arată tot codul · %d linii" % lines.size()
	var preview = "\n".join(lines.slice(0, 12)) if long_code and not block["expanded"] else source
	block["editor"].custom_maximum_size.y = 0 if block["expanded"] else 360 * EditorInterface.get_editor_scale()
	if force or block["editor"].text != preview:
		var offset = block["editor"].scroll_vertical
		block["editor"].text = preview
		block["editor"].scroll_vertical = offset
	if block.has("rows"):
		var editor: CodeEdit = block["editor"]
		if not block.has("line_gutter"):
			block["line_gutter"] = editor.get_gutter_count()
			editor.add_gutter()
			editor.set_gutter_type(block["line_gutter"], TextEdit.GUTTER_TYPE_STRING)
			editor.set_gutter_width(block["line_gutter"], int(54 * EditorInterface.get_editor_scale()))
		for index in range(mini(editor.get_line_count(), block["rows"].size())):
			editor.set_line_gutter_text(index, block["line_gutter"], str(block["rows"][index]["line"]))
	var language = str(block["language_id"]).to_lower()
	block["language"].text = str({"gdscript": "GDScript", "gd": "GDScript", "python": "Python", "json": "JSON", "csharp": "C#", "bash": "Shell", "sh": "Shell", "": "Cod"}.get(language, language))
	if block.get("highlighted", "__unset__") == language: return
	block["highlighted"] = language
	var colors = CodeHighlighter.new()
	var words = ["true", "false", "null"]
	if language in ["gdscript", "gd", "python", "py", ""]: words += ["func", "var", "extends", "if", "else", "return", "class_name", "await", "for", "in", "const", "static", "signal", "def", "class", "import", "from", "True", "False", "None"]
	elif language in ["csharp", "c#", "cs"]: words += ["using", "class", "public", "private", "void", "return", "if", "else", "new", "static"]
	for word in words: colors.add_keyword_color(word, Color("c4a4fc"))
	colors.number_color = Color("91c9eb")
	colors.symbol_color = Color("b5bfd4")
	colors.function_color = Color("91c9eb")
	colors.add_color_region("\"", "\"", Color("b4d6a3"))
	if language != "json": colors.add_color_region("#", "", Color("7e8ba0"), true)
	block["editor"].syntax_highlighter = colors

func _diagram_block(parent: Node) -> Dictionary:
	var block = _code_block(parent)
	block["kind"] = "diagram"
	block["language_id"] = "mermaid"
	var box = block["editor"].get_parent()
	var tools = HFlowContainer.new()
	box.add_child(tools)
	box.move_child(tools, 1)
	var canvas = Diagram.new()
	canvas.name = "NativeDiagram"
	box.add_child(canvas)
	box.move_child(canvas, 2)
	var note = label(box, "")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color("aabbd3"))
	box.move_child(note, 3)
	var source = button(tools, "Sursă", func() -> void:
		_preserve_reader()
		block["source_visible"] = not block.get("source_visible", false)
		_diagram_visibility(block))
	_compact_button(source)
	var explore = button(tools, "Explorează", func() -> void: canvas.explore(not canvas.interactive))
	explore.toggle_mode = true
	_compact_button(explore)
	for entry in [["−", 1.0 / 1.3], ["+", 1.3]]:
		var factor = float(entry[1])
		_compact_button(button(tools, entry[0], func() -> void: canvas.magnify(factor)))
	_compact_button(button(tools, "Încadrează", func() -> void: canvas.fit()))
	block["canvas"] = canvas
	block["diagram_tools"] = tools
	block["diagram_note"] = note
	block["source_toggle"] = source
	block["source_visible"] = false
	return block

func _diagram_visibility(block: Dictionary) -> void:
	var valid = block.get("model", {}).get("ok", false)
	block["canvas"].visible = valid
	block["diagram_tools"].visible = valid
	block["editor"].visible = block.get("source_visible", false) or not valid
	block["expand"].visible = block["editor"].visible and str(block["source"]).split("\n").size() > 18
	block["source_toggle"].text = "Ascunde sursa" if block.get("source_visible", false) else "Sursă"

func _size_diagram(block: Dictionary) -> void:
	var scale = EditorInterface.get_editor_scale()
	block["canvas"].custom_minimum_size.y = minf(280 * scale, maxf(120 * scale, scroll.size.y * 0.55))

func _update_diagram(block: Dictionary, ready: bool) -> void:
	_update_code(block)
	block["language"].text = "Diagramă · Mermaid"
	if not ready:
		block["model"] = {}
		block["diagram_note"].text = "Diagrama se desenează după încheierea blocului."
	else:
		block["model"] = Diagram.parse(str(block["source"]))
		if block["model"].get("ok", false):
			block["canvas"].configure(block["model"], EditorInterface.get_editor_scale())
			_size_diagram(block)
			block["diagram_note"].text = "Zoom: + / − · Explorează activează deplasarea; altfel glisarea derulează conversația."
		else: block["diagram_note"].text = str(block["model"].get("error", "Diagrama nu a putut fi desenată.")) + " Sursa este păstrată."
	_diagram_visibility(block)

func _render_content(record: Dictionary) -> void:
	var pieces = Markdown.blocks(str(record["text"]), record["streaming"]) if record["rich"] else [{"kind": "text", "text": str(record["text"])}]
	var blocks: Array = record["blocks"]
	for index in range(pieces.size()):
		var piece: Dictionary = pieces[index]
		if piece["kind"] == "code" and str(piece.get("language", "")).to_lower() == "mermaid": piece["kind"] = "diagram"
		if index < blocks.size() and blocks[index]["kind"] != piece["kind"]:
			while blocks.size() > index:
				var stale = blocks.pop_back()["node"]
				record["body"].remove_child(stale)
				stale.queue_free()
		if index >= blocks.size(): blocks.append(_diagram_block(record["body"]) if piece["kind"] == "diagram" else (_code_block(record["body"]) if piece["kind"] == "code" else _text_block(record["body"])))
		var block: Dictionary = blocks[index]
		if block["source"] == piece["text"] and block.get("language_id", "") == piece.get("language", "") and (block.get("diagram_ready", false) == (piece.get("complete", false) or not record["streaming"]) if piece["kind"] == "diagram" else block.get("complete", false) == piece.get("complete", false)) and block["renders"] > 0: continue
		block["source"] = piece["text"]
		block["renders"] += 1
		block["complete"] = piece.get("complete", false)
		block["diagram_ready"] = piece.get("complete", false) or not record["streaming"]
		if piece["kind"] == "diagram": _update_diagram(block, piece.get("complete", false) or not record["streaming"])
		elif piece["kind"] == "code":
			block["language_id"] = piece.get("language", "")
			_update_code(block)
		else:
			_markdown(block["node"], piece["text"])
			block["node"].visible = not str(piece["text"]).strip_edges().is_empty()
	while blocks.size() > pieces.size():
		var stale = blocks.pop_back()["node"]
		record["body"].remove_child(stale)
		stale.queue_free()

func stream_text(anchor: RichTextLabel, piece: String) -> void:
	if not is_instance_valid(anchor) or not anchor.has_meta("message"): return
	var record: Dictionary = anchor.get_meta("message")
	record["text"] += piece
	last_output_msec = Time.get_ticks_msec()
	if stall_label != null and stall_label.visible: stall_label.visible = false
	if not streaming_dirty.has(anchor): streaming_dirty.append(anchor)

func finish_stream(anchor: RichTextLabel, metadata: Dictionary) -> void:
	if not is_instance_valid(anchor) or not anchor.has_meta("message"): return
	var record: Dictionary = anchor.get_meta("message")
	record["metadata"] = metadata.duplicate(true)
	record["streaming"] = false
	record["text"] = str(metadata.get("content", record["text"]))
	streaming_dirty.erase(anchor)
	_render_content(record)
	_render_reasoning(record)
	_refresh_message_controls(record)
	_refresh_metrics(record)
	if int(record.get("group_index", -1)) >= 0: _sync_response(response_groups[int(record["group_index"])])

func _process(delta: float) -> void:
	if OS.has_feature("android") and is_visible_in_tree(): _update_keyboard_inset(DisplayServer.virtual_keyboard_get_height())
	activity_clock += delta
	if activity_clock >= 0.08:
		activity_clock = 0.0
		if activity_indicator != null and motion_enabled and _work_running(): activity_indicator.queue_redraw()
	stall_clock += delta
	if stall_clock >= 1.0 and stall_label != null:
		stall_clock = 0.0
		var idle = int((Time.get_ticks_msec() - last_output_msec) / 1000.0)
		if generating and idle >= 15:
			stall_label.text = "Fără ieșire de %d s · modelul sau conexiunea poate fi blocată" % idle
			stall_label.visible = true
		elif stall_label.visible: stall_label.visible = false
	stream_clock += delta
	if stream_clock < 0.08 or streaming_dirty.is_empty(): return
	stream_clock = 0.0
	for anchor in streaming_dirty:
		if is_instance_valid(anchor): _render_content(anchor.get_meta("message"))
	streaming_dirty.clear()
	_follow.call_deferred()

func _message_actions(record: Dictionary) -> void:
	var actions = HBoxContainer.new()
	record["column"].add_child(actions)
	record["actions_row"] = actions
	record["actions"] = []
	for pair in [["Copy", "Copiază răspunsul", "copy"], ["Retry", "Reia sarcina întreruptă", "retry"], ["Undo", "Anulează răspunsul: restaurează fișierele și readuce promptul în composer", "undo"], ["Changes", "Modificări / Undo", "changes"]]:
		var control = icon_button(actions, pair[0], pair[1], func() -> void: _message_action(record, pair[2]))
		control.set_meta("message_action", pair[2])
		_compact_button(control)
		control.disabled = record["streaming"]
		record["actions"].append(control)
	var more = MenuButton.new()
	more.icon = _icon("More")
	more.tooltip_text = "Mai multe acțiuni"
	more.custom_minimum_size = Vector2(32, 32) * EditorInterface.get_editor_scale()
	more.add_theme_constant_override("icon_max_width", int(16 * EditorInterface.get_editor_scale()))
	more.get_popup().add_item("Ramifică de aici", 0)
	more.get_popup().add_item("Regenerează răspunsul", 1)
	more.get_popup().id_pressed.connect(func(id: int) -> void: _message_action(record, "resend" if id == 1 else "fork"))
	more.disabled = record["streaming"]
	more.set_meta("message_action", "more")
	record["actions"].append(more)
	actions.add_child(more)
	_refresh_message_controls(record)

func _latest_user_turn() -> String:
	for index in range(message_records.size() - 1, -1, -1):
		var record: Dictionary = message_records[index]
		if record["role"] == "user": return str(record["metadata"].get("turn_id", ""))
	return ""

func _refresh_message_controls(record: Dictionary) -> void:
	var metadata: Dictionary = record["metadata"]
	var turn = str(metadata.get("turn_id", ""))
	var is_latest = not turn.is_empty() and turn == _latest_user_turn()
	var completed = metadata.get("run_status") == "completed"
	for control in record.get("actions", []):
		var name = str(control.get_meta("message_action", ""))
		control.disabled = record["streaming"] or (name == "copy" and str(record["text"]).is_empty()) or (name == "changes" and not change_cards.has(turn) and metadata.get("changes", []).is_empty())
		if name == "changes": control.visible = not control.disabled
		if name == "retry":
			control.disabled = control.disabled or completed
			control.visible = metadata.get("run_status") != "completed"
		if name == "undo":
			control.disabled = control.disabled or not is_latest
			control.visible = is_latest and not record["streaming"]
		if name == "more":
			var popup = control.get_popup()
			popup.set_item_disabled(popup.get_item_index(1), record["streaming"] or not is_latest or not completed)

func set_turn_outcome(turn: String, status: String) -> void:
	for record in message_records:
		if record["metadata"].get("turn_id") != turn: continue
		record["metadata"]["run_status"] = status
		_refresh_message_controls(record)
	for group in response_groups:
		if group["turn"] == turn:
			group["outcome"] = status
			_sync_response(group)

func _message_action(record: Dictionary, name: String) -> void:
	var metadata: Dictionary = record["metadata"]
	if metadata.has("id"): action.emit(name, {"message": metadata["id"], "turn": metadata.get("turn_id", "")})

func set_generating(active: bool) -> void:
	generating = active
	last_output_msec = Time.get_ticks_msec()
	if stall_label != null and not active: stall_label.visible = false

func set_turn_metrics(turn: String, metrics: Dictionary) -> void:
	for record in message_records:
		if record["role"] != "assistant" or record["metadata"].get("turn_id") != turn: continue
		record["metadata"]["metrics"] = metrics.duplicate(true)
		_refresh_metrics(record)
	for group in response_groups:
		if group["turn"] == turn: _sync_response(group)

func _refresh_metrics(record: Dictionary) -> void:
	var metrics: Dictionary = record["metadata"].get("metrics", {})
	var existing: Label = record.get("metrics_label")
	if metrics.is_empty():
		if existing != null: existing.visible = false
		return
	if existing == null:
		existing = label(record["column"], "")
		existing.name = "MessageMetrics"
		existing.add_theme_font_size_override("font_size", int(11 * EditorInterface.get_editor_scale()))
		existing.add_theme_color_override("font_color", Color("7e8ba0"))
		record["metrics_label"] = existing
	var parts = []
	var elapsed = int(metrics.get("elapsed_ms", 0))
	if elapsed > 0: parts.append(_duration_label(elapsed))
	var output = int(metrics.get("output_tokens", 0))
	if output > 0: parts.append(("≈ " if metrics.get("estimated", false) else "") + str(output) + " tokeni")
	var cost = float(metrics.get("cost_usd", -1.0))
	if cost >= 0.0: parts.append(("$" + ModelPricing.number(cost).replace(",", ".")) if cost >= 0.0001 else "< $0,0001")
	existing.text = " · ".join(parts)
	existing.tooltip_text = "Timp scurs din trimitere, fără așteptarea aprobărilor.\nIeșire aproximativă: %d tokeni.\nIntrare cumulată: %d tokeni.%s" % [output, int(metrics.get("input_tokens", 0)), ("\nCost estimat din tarifele salvate." if cost >= 0.0 else "")]
	existing.visible = not existing.text.is_empty()

func _duration_label(ms: int) -> String:
	var seconds = ms / 1000.0
	if seconds < 60.0: return ((("%.1f" % seconds).replace(".", ",") + " s") if seconds < 10.0 else ("%d s" % roundi(seconds)))
	return "%d min %02d s" % [int(seconds / 60.0), int(seconds) % 60]

func _render_reasoning(record: Dictionary) -> void:
	if record["role"] != "assistant": return
	var text = str(record["metadata"].get("reasoning_content", "")).strip_edges()
	var block: Dictionary = record.get("reasoning", {})
	if text.is_empty():
		if not block.is_empty() and is_instance_valid(block.get("node")): block["node"].visible = false
		return
	if block.is_empty() or not is_instance_valid(block.get("node")):
		var scale = EditorInterface.get_editor_scale()
		var panel = PanelContainer.new()
		var surface = style(Color.TRANSPARENT, 0)
		surface.set_content_margin_all(0)
		panel.add_theme_stylebox_override("panel", surface)
		var column = VBoxContainer.new()
		column.add_theme_constant_override("separation", int(2 * scale))
		panel.add_child(column)
		var toggle = button(column, "", func() -> void: pass)
		toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
		toggle.icon = _icon("Reasoning")
		toggle.clip_text = true
		toggle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_compact_button(toggle)
		toggle.add_theme_color_override("font_color", Color("8f97a9"))
		var body = RichTextLabel.new()
		body.fit_content = true
		body.scroll_active = false
		body.selection_enabled = true
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_theme_font_size_override("font_size", int(12 * scale))
		body.add_theme_color_override("default_color", Color("a7b0c3"))
		body.visible = false
		column.add_child(body)
		toggle.pressed.connect(func() -> void: body.visible = not body.visible)
		record["column"].add_child(panel)
		if is_instance_valid(record.get("body")): record["column"].move_child(panel, record["body"].get_index())
		block = {"node": panel, "toggle": toggle, "body": body, "text": ""}
		record["reasoning"] = block
	if str(block["text"]) == text: return
	block["text"] = text
	block["toggle"].text = "Gândire · %d cuvinte" % text.split(" ", false).size()
	Markdown.render(block["body"], text, EditorInterface.get_editor_scale())

func show_queue(items: Array, paused: bool = false, working: bool = false) -> void:
	if queue_panel == null: return
	for child in queue_panel.get_children():
		queue_panel.remove_child(child)
		child.queue_free()
	queue_scroll = null
	queue_rows = null
	queue_panel.visible = not items.is_empty()
	if items.is_empty(): return
	var scale = EditorInterface.get_editor_scale()
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", int(4 * scale))
	queue_panel.add_child(header)
	var heading = label(header, "Coadă · %d %s" % [items.size(), "mesaj" if items.size() == 1 else "mesaje"])
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.add_theme_font_size_override("font_size", int(11 * scale))
	heading.add_theme_color_override("font_color", Color("9aa5b9"))
	if paused:
		var resume = icon_button(header, "Play", "Reia coada de mesaje", func() -> void: action.emit("queue_resume", {}))
		resume.text = "Reia"
		_compact_button(resume)
		resume.disabled = working
	queue_scroll = ScrollContainer.new()
	queue_scroll.name = "QueueScroll"
	queue_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	queue_panel.add_child(queue_scroll)
	queue_rows = VBoxContainer.new()
	queue_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_rows.add_theme_constant_override("separation", int(6 * scale))
	queue_scroll.add_child(queue_rows)
	queue_rows.minimum_size_changed.connect(func() -> void: _layout_queue.call_deferred())
	for index in range(items.size()):
		var item: Dictionary = items[index]
		var card = PanelContainer.new()
		card.mouse_filter = Control.MOUSE_FILTER_PASS
		var surface = style(Color("161b28"), 10)
		surface.border_color = Color("2d3448")
		surface.set_border_width_all(1)
		surface.set_content_margin_all(6 * scale)
		card.add_theme_stylebox_override("panel", surface)
		queue_rows.add_child(card)
		var line = HBoxContainer.new()
		line.add_theme_constant_override("separation", int(2 * scale))
		card.add_child(line)
		var attachment_count = item.get("selection", {}).get("attachments", []).size() + item.get("selection", {}).get("files", []).size()
		var full_text = str(item.get("text", "")).replace("\n", " ").strip_edges()
		var steering = item.get("delivery") == "steer"
		var message = label(line, ("La pas · " if steering else "După task · ") + (full_text if not full_text.is_empty() else "Fișiere atașate"))
		message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		message.clip_text = true
		message.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		message.add_theme_font_size_override("font_size", int(12 * scale))
		message.tooltip_text = full_text + ("\n%d atașamente" % attachment_count if attachment_count > 0 else "")
		var delivery = icon_button(line, "ArrowRight", "Mută după sarcină" if steering else "Aplică în sarcina curentă, după pasul în desfășurare", func() -> void: action.emit("queue_delivery", {"index": index}))
		delivery.text = "În coadă" if steering else "În task"
		delivery.disabled = not working
		_compact_button(delivery)
		var restore = icon_button(line, "ArrowUp", "Mută mesajul înapoi în composer", func() -> void: action.emit("queue_restore", {"index": index}))
		var remove = icon_button(line, "Close", "Scoate din coadă", func() -> void: action.emit("queue_remove", {"index": index}))
		_compact_button(restore)
		_compact_button(remove)
	_layout_queue.call_deferred()

func _layout_queue() -> void:
	if queue_scroll == null or queue_rows == null or not queue_panel.visible: return
	var scale = EditorInterface.get_editor_scale()
	var fixed_height = queue_panel.get_child(0).get_combined_minimum_size().y
	var visible_children = 0
	for child in root_column.get_children():
		if not child.visible: continue
		visible_children += 1
		if child != scroll.get_parent() and child != queue_panel: fixed_height += child.get_combined_minimum_size().y
	fixed_height += maxi(0, visible_children - 1) * root_column.get_theme_constant("separation") + queue_panel.get_theme_constant("separation")
	var room = maxf(0, size.y - fixed_height - minf(80 * scale, size.y * 0.15))
	# Scroll offsets are integer pixels; a fractional page can clip the last row.
	var cap = floorf(minf(room, minf(160 * scale, size.y * 0.22)))
	var height = minf(cap, queue_rows.get_combined_minimum_size().y)
	queue_scroll.visible = height > 0
	if not is_equal_approx(queue_scroll.custom_minimum_size.y, height): queue_scroll.custom_minimum_size.y = height
	if not is_equal_approx(queue_scroll.custom_maximum_size.y, cap): queue_scroll.custom_maximum_size.y = cap

func _toggle_find() -> void:
	_show_find(not find_panel.visible)

func _show_find(show: bool) -> void:
	if find_panel == null: return
	find_panel.visible = show
	if show:
		find_input.grab_focus()
		find_input.select_all()
		_search_find()
	else:
		find_matches.clear()
		find_index = -1
		find_count.text = "0/0"

func _search_find() -> void:
	find_matches.clear()
	find_index = -1
	var query = find_input.text.strip_edges().to_lower()
	if not query.is_empty():
		for record in message_records:
			if record["role"] not in ["user", "assistant"]: continue
			if str(record["text"]).to_lower().contains(query): find_matches.append(record)
	if find_matches.is_empty():
		find_count.text = "0/0"
		return
	_show_find_match(0)

func _step_find(step: int) -> void:
	if find_matches.is_empty(): return
	_show_find_match(wrapi((find_index if find_index >= 0 else 0) + step, 0, find_matches.size()))

func _show_find_match(index: int) -> void:
	follow_bottom = false
	_update_latest_button()
	find_index = clampi(index, 0, find_matches.size() - 1)
	var record: Dictionary = find_matches[find_index]
	find_count.text = "%d/%d" % [find_index + 1, find_matches.size()]
	var group_index = int(record.get("group_index", -1))
	if group_index >= 0 and record["row"].get_parent() == response_groups[group_index]["progress"]:
		var group: Dictionary = response_groups[group_index]
		group["progress"].show()
		_refresh_progress_title(group["progress_toggle"], group["progress"])
	for block in record["blocks"]:
		if block["kind"] in ["code", "diagram"] and str(block["source"]).to_lower().contains(find_input.text.to_lower()):
			block["expanded"] = true
			_update_code(block, true)
			if block["kind"] == "diagram":
				block["source_visible"] = true
				_diagram_visibility(block)
	if is_instance_valid(record.get("row")): scroll.ensure_control_visible(record["row"])
	if is_instance_valid(record.get("row")): scroll.ensure_control_visible.call_deferred(record["row"])
	if is_instance_valid(record.get("card")) and motion_enabled:
		record["card"].self_modulate = Color("d7c6ff")
		create_tween().tween_property(record["card"], "self_modulate", Color.WHITE, 0.7)

func show_running_tool(name: String = "", description: String = "") -> void:
	if running_tools == null: return
	running_tools.visible = not name.is_empty()
	var caption = description.trim_prefix("Running ").replace(" Tool", "") if not description.is_empty() else name.replace("_", " ").capitalize()
	running_tools.text = "Running Tools · " + caption if not name.is_empty() else ""
	running_tools.tooltip_text = name

func _chat_control_at(control: Control, point: Vector2) -> Control:
	if not control.is_visible_in_tree() or not control.get_global_rect().has_point(point): return null
	var children = control.get_children()
	children.reverse()
	for child in children:
		if child is Control:
			var found = _chat_control_at(child, point)
			if found != null: return found
	return control if control.mouse_filter != Control.MOUSE_FILTER_IGNORE else null

func _native_touch_control(control: Control) -> bool:
	while control != null and control != scroll:
		if control.get_meta("chat_native_gesture", false): return true
		if control is BaseButton or control is LineEdit or control is ScrollBar or control is Slider or (control is TextEdit and control.editable): return true
		control = control.get_parent_control()
	return false

func _chat_touch(event: InputEvent) -> bool:
	if not is_visible_in_tree() or scroll == null or (picker != null and picker.visible): return false
	if event is InputEventMouse and event.device == -1:
		# Android dispatches the emulated mouse press BEFORE its native touch.
		# Block that first press over messages too, before text selection begins.
		if scroll.get_global_rect().has_point(event.position): return not _native_touch_control(_chat_control_at(scroll, event.position))
		return Time.get_ticks_msec() < touch_suppress_until
	if event is InputEventPanGesture:
		if not scroll.get_global_rect().has_point(event.position): return false
		if _native_touch_control(_chat_control_at(scroll, event.position)): return false
		if touch_scroll.is_empty():
			if event.delta.y < 0: follow_bottom = false
			scroll.scroll_vertical += int(event.delta.y * 40 * EditorInterface.get_editor_scale())
			_update_latest_button()
		return true
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag): return false
	if event is InputEventScreenTouch and event.pressed:
		if not scroll.get_global_rect().has_point(event.position): return false
		if not touch_scroll.is_empty(): return true
		question_touch_targets = question_touch_targets.filter(func(target: Dictionary) -> bool: return target["row"].get_ref() != null and target["check"].get_ref() != null)
		for target in question_touch_targets:
			var row = target["row"].get_ref()
			var check = target["check"].get_ref()
			if not check.disabled and row.is_visible_in_tree() and row.get_global_rect().has_point(event.position):
				touch_scroll = {"index": event.index, "start": event.position, "last": event.position, "scroll": scroll.scroll_vertical, "moved": false, "tap_check": target["check"]}
				touch_suppress_until = Time.get_ticks_msec() + 1000
				return true
		var control = _chat_control_at(scroll, event.position)
		if _native_touch_control(control): return false
		touch_scroll = {"index": event.index, "start": event.position, "last": event.position, "scroll": scroll.scroll_vertical, "moved": false, "token": Time.get_ticks_usec()}
		while control != null and control != scroll:
			if control.has_meta("chat_file_id"): touch_scroll["file"] = str(control.get_meta("chat_file_id")); break
			if control is RichTextLabel or control is TextEdit: touch_scroll["target"] = weakref(control)
			control = control.get_parent_control()
		touch_suppress_until = Time.get_ticks_msec() + 1000
		if touch_scroll.has("target") or touch_scroll.has("file"): _touch_selection_after(int(touch_scroll["token"]))
		return true
	if touch_scroll.is_empty() or event.index != touch_scroll.get("index"): return false
	touch_suppress_until = Time.get_ticks_msec() + 300
	if event is InputEventScreenDrag:
		touch_scroll["last"] = event.position
		var delta = event.position - Vector2(touch_scroll["start"])
		if delta.length() > 8 * EditorInterface.get_editor_scale(): touch_scroll["moved"] = true
		if touch_scroll.has("file") and not touch_scroll.get("vertical", false) and delta.x > 48 * EditorInterface.get_editor_scale() and delta.x > absf(delta.y) * 2:
			if not touch_scroll.get("mentioned", false): action.emit("file_mention", {"id": touch_scroll["file"]})
			touch_scroll["mentioned"] = true
		if not touch_scroll.get("mentioned", false) and absf(delta.y) > 8 * EditorInterface.get_editor_scale() and absf(delta.y) >= absf(delta.x): touch_scroll["vertical"] = true
		if touch_scroll.get("vertical", false):
			if delta.y > 0: follow_bottom = false
			scroll.scroll_vertical = int(touch_scroll["scroll"]) - int(delta.y)
			_update_latest_button()
	elif not event.pressed:
		if not event.canceled and not touch_scroll["moved"] and event.position.distance_to(touch_scroll["start"]) <= 8 * EditorInterface.get_editor_scale():
			if touch_scroll.has("tap_check"):
				var check = touch_scroll["tap_check"].get_ref()
				if check != null and not check.disabled: check.button_pressed = not check.button_pressed
			elif touch_scroll.has("file"): action.emit("file_open", {"id": touch_scroll["file"]})
			elif touch_scroll.has("target"):
				var target = touch_scroll["target"].get_ref()
				if target is RichTextLabel: _tap_chat_link(target, event.position)
		touch_scroll.clear()
	return true

func _tap_chat_link(target: RichTextLabel, point: Vector2) -> void:
	# Relay a completed, stationary tap inside this Godot viewport. Selection
	# stays off during native link hit-testing; drags and long presses never relay.
	if not target.is_visible_in_tree() or not target.get_global_rect().has_point(point): return
	var selection = target.selection_enabled
	target.selection_enabled = false
	var click = InputEventMouseButton.new()
	click.device = 41
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = point
	click.global_position = point
	click.pressed = true
	get_viewport().push_input(click, true)
	click = click.duplicate()
	click.pressed = false
	get_viewport().push_input(click, true)
	target.selection_enabled = selection

func _touch_selection_after(token: int) -> void:
	await get_tree().create_timer(0.55).timeout
	if touch_scroll.is_empty() or touch_scroll.get("token") != token or touch_scroll.get("moved", true): return
	if touch_scroll.has("file"):
		var id = str(touch_scroll["file"])
		var point = Vector2(touch_scroll["last"])
		touch_scroll.clear()
		_file_menu(id, point)
		return
	var control = touch_scroll["target"].get_ref()
	if control == null: return
	var point = Vector2(touch_scroll["last"])
	touch_scroll.clear()
	control.select_all()
	var menu = PopupMenu.new()
	add_child(menu)
	menu.add_item("Copiază", 0)
	menu.id_pressed.connect(func(_id: int) -> void:
		if is_instance_valid(control): DisplayServer.clipboard_set(control.get_selected_text()))
	menu.popup_hide.connect(menu.queue_free)
	menu.position = get_window().position + Vector2i(point)
	menu.popup()

func _follow() -> void:
	if not restoring and not live_plan_card.is_empty():
		var card = plan_cards.get(live_plan_card, {})
		if is_instance_valid(card.get("node")) and card["node"].get_index() != thread.get_child_count() - 1:
			thread.move_child(card["node"], thread.get_child_count() - 1)
	if follow_bottom and is_instance_valid(scroll):
		following_scroll = true
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		last_scroll_value = scroll.get_v_scroll_bar().value
		following_scroll = false
	_update_latest_button()

func _scroll_changed(value: float) -> void:
	# Geometry changes can clamp the bar too. Only pointer/key input detaches
	# following; content growth must never do so.
	if not following_scroll and value < last_scroll_value and (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_PAGEUP)):
		follow_bottom = false
	last_scroll_value = value
	_update_latest_button()

func _update_latest_button() -> void:
	if latest_button != null:
		latest_button.visible = not follow_bottom
		latest_button.tooltip_text = "Mergi la ultimul mesaj și urmărește conversația" + (" · %d mesaje noi" % unseen_updates if unseen_updates else "")

func _jump_to_latest() -> void:
	follow_bottom = true
	unseen_updates = 0
	_follow()
	_follow.call_deferred()

func _update_keyboard_inset(height_pixels: float) -> void:
	if keyboard_spacer == null or scroll == null: return
	# Godot's Android keyboard height is the remaining occlusion after native
	# window padding. Convert physical pixels to this viewport's coordinates.
	var scale_y = maxf(0.001, get_viewport().get_screen_transform().get_scale().y)
	var bottom = get_global_rect().end.y
	var free_below = maxf(0.0, get_viewport_rect().size.y - bottom)
	var overlap = maxf(0.0, height_pixels / scale_y - free_below)
	# Leave room for the composer to scroll its own long draft on short screens.
	var maximum = maxf(32.0, minf(112 * EditorInterface.get_editor_scale(), size.y - overlap - 120 * EditorInterface.get_editor_scale()))
	composer.custom_maximum_size.y = maximum
	if not is_equal_approx(keyboard_spacer.custom_minimum_size.y, overlap):
		keyboard_spacer.custom_minimum_size.y = overlap
		keyboard_spacer.visible = overlap > 0
		_layout_activity.call_deferred()
		_layout_queue.call_deferred()
		_follow.call_deferred()
		composer.adjust_viewport_to_caret.call_deferred()

func _draw() -> void:
	if backdrop != null: draw_texture_rect(backdrop, Rect2(Vector2.ZERO, size), false)

func icon_button(parent: Node, icon_name: String, hint: String, callback: Callable) -> Button:
	var control = button(parent, "", callback)
	control.icon = _icon(icon_name)
	control.add_theme_constant_override("icon_max_width", int(20 * EditorInterface.get_editor_scale()))
	control.tooltip_text = hint
	control.custom_minimum_size = Vector2(44, 44) * EditorInterface.get_editor_scale()
	control.add_theme_stylebox_override("normal", style(Color.TRANSPARENT, 10))
	return control

func _icon(name: String) -> Texture2D:
	if icon_cache.has(name): return icon_cache[name]
	if name == "ArrowDown":
		var pixels = _icon("ArrowUp").get_image()
		pixels.flip_y()
		icon_cache[name] = ImageTexture.create_from_image(pixels)
		return icon_cache[name]
	var svg = str(Icons.DATA.get(name, Icons.DATA["More"]))
	# Preserve upstream artwork and brand colors. Mono assets inherit the dark UI ink.
	svg = svg.replace("currentColor", "#dce1ef")
	var image = Image.new()
	if image.load_svg_from_string(svg, EditorInterface.get_editor_scale()) != OK: return null
	icon_cache[name] = ImageTexture.create_from_image(image)
	return icon_cache[name]

func provider_icon(profile: Dictionary) -> Texture2D:
	var issuer = str(profile.get("issuer", "custom"))
	if issuer == "qwen-cn": issuer = "qwen"
	if profile.get("kind") == "siwc": issuer = "openai"
	if profile.get("kind") == "companion":
		var service = (str(profile.get("account", "")) + " " + str(profile.get("name", ""))).to_lower()
		if "claude" in service: issuer = "anthropic"
		elif "gemini" in service: issuer = "gemini"
		elif "chatgpt" in service or "codex" in service: issuer = "openai"
		elif "kimi" in service: issuer = "kimi"
		elif "copilot" in service: return _icon("Provider_copilot")
		else: return _icon("Accounts")
	if not issuer in ["openai", "anthropic", "gemini", "deepseek", "openrouter", "qwen", "kimi", "mistral", "groq", "xai", "zai", "minimax", "nvidia", "siliconflow", "ollama", "lmstudio", "llamacpp"]: issuer = "custom"
	return _icon("Provider_" + issuer)

func section_icon(section: String) -> Texture2D:
	return _icon({"general": "Settings", "providers": "Providers", "accounts": "Accounts", "generation": "Generation", "mcp": "MCP", "integrations": "Integrations", "ziva": "Integrations", "skills": "Skills", "automations": "Plan", "journal": "Journal", "agent": "File", "voice": "Microphone", "playtesting": "Play"}.get(section, "Settings"))

func set_workspace_expanded(value: bool) -> void:
	workspace_expanded = value
	if expand_button == null: return
	expand_button.icon = _icon("Collapse" if value else "Expand")
	expand_button.tooltip_text = "Restaurează panourile" if value else "Extinde chatul și ascunde panourile"
	expand_button.set_pressed_no_signal(value)

func _toggle_expanded() -> void:
	action.emit("expand", {})

func set_error_count(count: int) -> void:
	count = maxi(count, 0)
	error_seen = 0 if count == 0 else mini(error_seen, count)
	if error_button == null or count == error_count: return
	error_count = count
	error_button.visible = count > 0
	if count > 0:
		error_button.text = "1 eroare" if count == 1 else "%d erori" % count
		error_button.add_theme_color_override("font_color", Color("8f97a9") if error_seen >= count else Color("d2b47f"))
	error_button.tooltip_text = "Deschide erorile din Debugger"

func _open_errors() -> void:
	error_seen = error_count
	if error_button != null: error_button.add_theme_color_override("font_color", Color("8f97a9"))
	action.emit("errors", {})

func show_status(message: String, working: bool = false) -> void:
	status_revision += 1
	var revision = status_revision
	var changed = work_message != message
	work_message = message
	work_notice_running = working
	_refresh_activity(changed)
	if working or message.is_empty(): return
	await get_tree().create_timer(4.0).timeout
	if revision == status_revision:
		work_message = ""
		_refresh_activity(true)

func show_attachments(images: Array, references: Array, file_ids: Array = []) -> void:
	var signature = JSON.stringify(images.map(func(item: Dictionary) -> String: return str(item.get("name", "")) + str(str(item.get("data", "")).length()))) + JSON.stringify(references) + JSON.stringify(file_ids) + file_scope
	if signature == attachment_signature: return
	attachment_signature = signature
	for child in attachment_chips.get_children():
		attachment_chips.remove_child(child)
		child.queue_free()
	for kind in ["image", "reference"]:
		var values = images if kind == "image" else references
		for index in range(values.size()):
			var item: Variant = values[index]
			var name = str(item.get("name", "Imagine")) if item is Dictionary else str(item).get_file()
			var chip = button(attachment_chips, name.left(22) + "  ×", func() -> void: action.emit("remove_attachment", {"kind": kind, "index": index}))
			chip.tooltip_text = name + " · elimină atașamentul"
			if item is Dictionary and item.has("data"):
				var preview = Image.new()
				if preview.load_png_from_buffer(Marshalls.base64_to_raw(item["data"])) == OK:
					chip.icon = ImageTexture.create_from_image(preview)
					chip.add_theme_constant_override("icon_max_width", int(28 * EditorInterface.get_editor_scale()))
	show_file_mentions(file_ids)
	attachment_chips.visible = attachment_chips.get_child_count() > 0

func set_context(used: int, limit: int, output: int = 0, estimated: bool = false, details: Dictionary = {}) -> void:
	context_ratio = clampf(float(used) / limit, 0, 1) if limit > 0 and used > 0 else -1.0
	context_label.text = ("≈" if estimated else "") + str(roundi(context_ratio * 100)) + "%" if context_ratio >= 0 else "—"
	var detail = "Context: " + (str(used) if used > 0 else "necunoscut") + (" / %s tokeni" % limit if limit > 0 else " · limită necunoscută")
	if output > 0: detail += "\nIeșire: %s tokeni" % output
	if estimated: detail += "\nValoare estimată"
	if int(details.get("reserve", 0)) > 0 and limit > 0: detail += "\nRezervă pentru răspuns: %s tokeni" % details["reserve"]
	if int(details.get("threshold", 0)) > 0 and limit > 0: detail += "\nCompactare în jurul a %s tokeni" % details["threshold"]
	if details.get("source") == "provider": detail += "\nSursă: consum raportat de furnizor pentru ultima cerere"
	elif details.get("source") == "provider+estimated_delta": detail += "\nSursă: furnizor + estimarea mesajelor noi"
	context_detail = detail
	for control in [context_indicator, context_label, context_gauge]: control.tooltip_text = detail
	context_gauge.queue_redraw()

func _open_options() -> void:
	_close_drawer()
	var wanted = Vector2i(310, 84) * EditorInterface.get_editor_scale()
	wanted.y = maxi(wanted.y, int(runtime_options.get_child(0).get_combined_minimum_size().y + 24 * EditorInterface.get_editor_scale()))
	var window = get_window()
	runtime_options.size = Vector2i(mini(wanted.x, window.size.x - 32), mini(wanted.y, window.size.y - 32))
	var origin = Vector2i(options_button.get_global_rect().position) + window.position
	runtime_options.position = Vector2i(clampi(origin.x, window.position.x + 12, window.position.x + window.size.x - runtime_options.size.x - 12), maxi(window.position.y + 12, origin.y - runtime_options.size.y - 8))
	runtime_options.popup()

func set_working(working: bool) -> void:
	if history_working != working:
		history_working = working
		_update_history_controls()
		if not working and not work_live: work_notice_running = false
		_refresh_activity()
	if stop_button != null and stop_button.visible != working:
		stop_button.visible = working
		_layout_composer()
	if options_button != null and mode_picker != null and mode_picker.selected >= 0:
		options_button.text = Common.MODES[mode_picker.selected]
		options_button.icon = _icon(Common.MODE_ICONS[mode_picker.selected])
		mode_picker.disabled = working
		for index in range(mode_buttons.size()):
			mode_buttons[index].disabled = working
			mode_buttons[index].set_pressed_no_signal(index == mode_picker.selected)

func show_welcome() -> void:
	thread.alignment = BoxContainer.ALIGNMENT_CENTER
	var heading = label(thread, "Ce construim astăzi?")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_font_size_override("font_size", int(24 * EditorInterface.get_editor_scale()))
	var hint = label(thread, "Trimite un mesaj sau atașează un fișier din proiect.")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color("abb5c9"))

func _file_card(parent: Node, id: String) -> Control:
	if file_registry == null: return null
	var item = file_registry.describe(id, file_scope)
	if item.is_empty(): return null
	var card = PanelContainer.new()
	card.name = "File_" + id
	card.set_meta("chat_file_id", id)
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	card.custom_maximum_size.x = 280 * EditorInterface.get_editor_scale()
	var surface = style(Color.TRANSPARENT, 0)
	surface.set_content_margin_all(0)
	card.add_theme_stylebox_override("panel", surface)
	parent.add_child(card)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", int(4 * EditorInterface.get_editor_scale()))
	card.add_child(column)
	if not str(item.get("preview", "")).is_empty() and FileAccess.file_exists(item["preview"]):
		var texture = ImageTexture.create_from_image(Image.load_from_file(item["preview"]))
		var picture = TextureRect.new()
		picture.texture = texture
		picture.name = "FileThumbnail"
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.custom_minimum_size.y = 88 * EditorInterface.get_editor_scale()
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(picture)
	var heading = label(column, str(item["name"]))
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.tooltip_text = str(item["source"])
	heading.add_theme_font_size_override("font_size", int(13 * EditorInterface.get_editor_scale()))
	var origin = label(column, "%s · %s · %s" % [str(item["kind"]).to_upper(), String.humanize_size(int(item["bytes"])), Time.get_datetime_string_from_unix_time(int(item["modified"])).replace("T", " ")])
	origin.add_theme_font_size_override("font_size", int(11 * EditorInterface.get_editor_scale()))
	origin.add_theme_color_override("font_color", Color("7e8ba0"))
	origin.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if item.get("temporary_capture", false):
		var retention = label(column, "Captură expirată · miniatura a fost curățată" if item.get("capture_expired", false) else ("Captură păstrată · fixată" if item.get("pinned", false) else "Captură temporară · 24 h · fixează pentru păstrare"))
		retention.name = "CaptureRetention"
		retention.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		retention.add_theme_font_size_override("font_size", int(11 * EditorInterface.get_editor_scale()))
	var actions = HBoxContainer.new()
	column.add_child(actions)
	for spec in [["Inspect", "Deschide", "file_open"], ["Pin", "Fixează / eliberează", "file_pin"]]:
		var entry = icon_button(actions, spec[0], spec[1], func() -> void: action.emit(spec[2], {"id": id}))
		if spec[2] == "file_open": entry.text = "Deschide"
		_compact_button(entry)
		entry.add_theme_stylebox_override("normal", _compact_style(Color.TRANSPARENT))
		entry.add_theme_color_override("font_color", Color("9aa2b4"))
		if item.get("capture_expired", false): entry.disabled = true
		if spec[2] == "file_pin":
			entry.toggle_mode = true
			entry.set_meta("file_pin_id", id)
			entry.set_pressed_no_signal(item.get("pinned", false))
	var more = icon_button(actions, "More", "Menționează, trimite sau compară", func() -> void: _file_menu(id, card.get_global_rect().end))
	_compact_button(more)
	more.disabled = item.get("capture_expired", false)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var gesture = {"pressed": false, "start": Vector2.ZERO, "delta": Vector2.ZERO, "mentioned": false, "started": 0}
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event.device == -1: return
		if event is InputEventScreenTouch or event is InputEventMouseButton:
			if event is InputEventMouseButton and event.button_index != MOUSE_BUTTON_LEFT: return
			if event.pressed:
				gesture["pressed"] = true
				gesture["start"] = event.position
				gesture["delta"] = Vector2.ZERO
				gesture["mentioned"] = false
				gesture["started"] = Time.get_ticks_msec()
				_file_long_press(card, id, gesture, gesture["started"])
			elif gesture["pressed"]:
				gesture["pressed"] = false
				if not gesture["mentioned"] and Vector2(gesture["delta"]).length() < 10: action.emit("file_open", {"id": id})
		elif gesture["pressed"] and (event is InputEventScreenDrag or event is InputEventMouseMotion):
			gesture["delta"] = event.position - Vector2(gesture["start"])
			var delta: Vector2 = gesture["delta"]
			if not gesture["mentioned"] and delta.x > 48 * EditorInterface.get_editor_scale() and delta.x > absf(delta.y) * 2:
				gesture["mentioned"] = true
				action.emit("file_mention", {"id": id})
				card.accept_event()
				card.self_modulate = Color("c1a8f2")
				card.create_tween().tween_property(card, "self_modulate", Color.WHITE, 0.25))
	return card

func expire_capture_cards(ids: Array) -> void:
	if thread == null: return
	for id in ids:
		for card in thread.find_children("File_" + str(id), "PanelContainer", true, false):
			var column = card.get_child(0)
			var picture = column.get_node_or_null("FileThumbnail")
			if picture != null:
				column.remove_child(picture)
				picture.queue_free()
			var retention = column.get_node_or_null("CaptureRetention")
			if retention != null: retention.text = "Captură expirată · miniatura a fost curățată"
			for button in column.find_children("*", "Button", true, false): button.disabled = true

func show_file_mentions(ids: Array) -> void:
	for id in ids:
		if file_registry == null: continue
		var item = file_registry.describe(str(id), file_scope)
		if item.is_empty(): continue
		var chip = button(attachment_chips, str(item["name"]).left(22) + " ×", func() -> void: action.emit("file_unmention", {"id": id}))
		_compact_button(chip)
		chip.tooltip_text = str(item["source"]) + " · referință trimisă la următorul mesaj"
		chip.icon = _icon("Models" if item["kind"] == "mesh" else ("Generation" if item["kind"] == "image" else "File"))
	attachment_chips.visible = attachment_chips.get_child_count() > 0

func show_changes(turn: String, changes: Array) -> void:
	if changes.is_empty(): return
	if not change_cards.has(turn) or not is_instance_valid(change_cards[turn]):
		var card = VBoxContainer.new()
		thread.add_child(card)
		change_cards[turn] = card
	var card: VBoxContainer = change_cards[turn]
	var signature = JSON.stringify(changes).sha256_text()
	if card.get_meta("diff_signature", "") == signature: return
	_preserve_reader()
	card.set_meta("diff_signature", signature)
	card.name = "InlineChanges_" + turn
	for child in card.get_children(): card.remove_child(child); child.queue_free()
	var heading = label(card, ("Propunere · " if turn.ends_with("-proposal") else "Modificări · ") + str(changes.size()))
	heading.add_theme_font_size_override("font_size", int(12 * EditorInterface.get_editor_scale()))
	for item in changes: _inline_diff(card, turn, item)
	for record in message_records:
		if record["metadata"].get("turn_id") == turn: _refresh_message_controls(record)
	_follow.call_deferred()

func _inline_diff(parent: Control, turn: String, item: Dictionary) -> void:
	var column = VBoxContainer.new()
	column.name = "InlineDiff"
	column.set_meta("path", str(item.get("path", "")))
	parent.add_child(column)
	var counts = " +%s  −%s" % [item.get("added", 0), item.get("removed", 0)] if item.get("exact", false) else ""
	var heading = label(column, str(item.get("path", "")).trim_prefix("res://") + counts + " · " + str(item.get("state", "")))
	heading.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	heading.add_theme_font_size_override("font_size", int(12 * EditorInterface.get_editor_scale()))
	heading.add_theme_color_override("font_color", Color("9aa2b4"))
	var source = str(item.get("diff", ""))
	var lines: Array = Array(source.split("\n"))
	if lines.size() >= 2 and str(lines[0]).begins_with("--- ") and str(lines[1]).begins_with("+++ "): lines = lines.slice(2)
	if not lines.is_empty() and lines[-1] == "": lines.pop_back()
	var key = turn + ":" + str(item.get("path", "")) + ":" + source.sha256_text()
	var shown = mini(int(diff_expanded.get(key, 40)), lines.size())
	var text = RichTextLabel.new()
	text.name = "InlineDiffText"
	text.fit_content = true
	text.scroll_active = false
	text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_override("normal_font", get_theme_font("font", "CodeEdit"))
	text.add_theme_font_size_override("normal_font_size", int(13 * EditorInterface.get_editor_scale()))
	column.add_child(text)
	for line in lines.slice(0, shown):
		var color = Color("aab3c5")
		if item.get("exact", false):
			if str(line).begins_with("+"): color = Color("86d99a")
			elif str(line).begins_with("-"): color = Color("f09098")
		text.push_color(color)
		text.add_text(str(line) + "\n")
		text.pop()
	if source.is_empty(): text.add_text("%s operații Undo" % item.get("operations", 0) if item.get("kind") == "scene" else "Diff textual indisponibil pentru această modificare.")
	if item.get("truncated", false): label(column, "Fragment salvat; diff-ul integral nu este disponibil.")
	if shown < lines.size():
		var more = button(column, "Arată restul · %s linii" % (lines.size() - shown) if lines.size() - shown <= 500 else "Arată încă 500 de linii", func() -> void:
			_preserve_reader()
			diff_expanded[key] = shown + 500
			var index = column.get_index()
			parent.remove_child(column)
			column.queue_free()
			_inline_diff(parent, turn, item)
			parent.move_child(parent.get_child(-1), index)
			_follow.call_deferred())
		more.name = "InlineDiffMore"
		_compact_button(more)
		more.add_theme_stylebox_override("normal", _compact_style(Color.TRANSPARENT))
		more.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

func show_store(items: Array) -> void:
	for item in items:
		var card = VBoxContainer.new()
		thread.add_child(card)
		var title = label(card, str(item.get("name", "Addon")))
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label(card, str(item.get("publisher", "")) + " · " + str(item.get("license", "")))
		var actions = HFlowContainer.new()
		card.add_child(actions)
		var id = str(item["id"])
		var inspect = button(actions, "Detalii", func() -> void: action.emit("store_request", {"text": "Inspectează addonul Store cu ID " + JSON.stringify(id) + " și arată versiunile compatibile."}))
		_compact_button(inspect)
		for release in item.get("releases", []).slice(0, 3):
			var version = str(release.get("version", ""))
			var install = button(actions, "Instalează " + version, func() -> void: action.emit("store_request", {"text": "Instalează addonul Store cu ID " + JSON.stringify(id) + " versiunea " + JSON.stringify(version) + ". Verifică rezultatul înainte de activare."}))
			_compact_button(install)
	_follow.call_deferred()

func _file_long_press(card: Control, id: String, gesture: Dictionary, started: int) -> void:
	await get_tree().create_timer(0.55).timeout
	if not is_instance_valid(card) or not gesture["pressed"] or gesture["started"] != started or Vector2(gesture["delta"]).length() > 10 or gesture["mentioned"]: return
	gesture["mentioned"] = true
	_file_menu(id, card.get_global_rect().position)

func _file_menu(id: String, point: Vector2) -> void:
	var popup = PopupMenu.new()
	popup.theme = theme
	add_child(popup)
	var entries = [["Deschide", "file_open"], ["Menționează", "file_mention"], ["Trimite referința", "file_send"], ["Fixează / eliberează", "file_pin"], ["Compară", "file_compare"]]
	for entry in entries: popup.add_item(entry[0])
	popup.id_pressed.connect(func(index: int) -> void: action.emit(entries[index][1], {"id": id}))
	popup.popup_hide.connect(popup.queue_free)
	var origin = point + Vector2(get_window().position)
	popup.position = Vector2i(origin)
	popup.popup()

func sync_file_pins(id: String) -> void:
	var item = file_registry.describe(id, file_scope)
	if item.get("temporary_capture", false) and not item.get("capture_expired", false):
		for card in thread.find_children("File_" + id, "PanelContainer", true, false):
			var caption = card.get_child(0).get_node_or_null("CaptureRetention")
			if caption != null: caption.text = "Captură păstrată · fixată" if item.get("pinned", false) else "Captură temporară · 24 h · fixează pentru păstrare"
	for button in thread.find_children("*", "Button", true, false):
		if button.get_meta("file_pin_id", "") == id: button.set_pressed_no_signal(item.get("pinned", false))
