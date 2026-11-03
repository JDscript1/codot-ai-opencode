#pragma once

#include "ai_runtime_bridge.h"

#include "core/error/error_macros.h"
#include "core/os/mutex.h"
#include "editor/inspector/editor_inspector.h"
#include "editor/plugins/editor_plugin.h"
#include "editor/run/editor_run.h"
#include "scene/gui/box_container.h"

#include "modules/gdscript/gdscript.h"

class AIAssistantSecretStore : public RefCounted {
	GDCLASS(AIAssistantSecretStore, RefCounted);
	String directory;
	Vector<uint8_t> master_key;
	bool ensure_directory();

protected:
	static void _bind_methods();

public:
	bool store(const String &p_name, const String &p_value);
	String read(const String &p_name);
	bool erase(const String &p_name);
};

class AIAssistantEditorPlugin;
class EditorDock;

class AIAssistantSettingsInspector : public EditorInspectorPlugin {
	GDCLASS(AIAssistantSettingsInspector, EditorInspectorPlugin);
	AIAssistantEditorPlugin *plugin = nullptr;

public:
	void set_plugin(AIAssistantEditorPlugin *p_plugin) { plugin = p_plugin; }
	bool can_handle(Object *p_object) override;
	bool parse_property(Object *p_object, const Variant::Type p_type, const String &p_path, const PropertyHint p_hint, const String &p_hint_text, const BitField<PropertyUsageFlags> p_usage, const bool p_wide = false) override;
};

class AIAssistantEditorPlugin : public EditorPlugin {
	GDCLASS(AIAssistantEditorPlugin, EditorPlugin);
public:
	static AIAssistantEditorPlugin *singleton;
private:
	Control *panel = nullptr;
	EditorDock *chat_dock = nullptr;
	int chat_placement = 0;
	String dock_workspace = "3D";
	Ref<AIAssistantSettingsInspector> settings_inspector;
	Ref<AIAssistantSecretStore> secrets;
	Ref<AIAssistantDebugger> runtime_debugger;
	EditorRun experiment_runner;
	Vector<Ref<GDScript>> scripts;
	ErrorHandlerList diagnostic_handler;
	Mutex diagnostic_mutex;
	Array diagnostic_events;
	int64_t diagnostic_sequence = 0;
	static void _capture_diagnostic(void *p_user, const char *p_function, const char *p_file, int p_line, const char *p_error, const char *p_description, bool p_notify, ErrorHandlerType p_type);

protected:
	static void _bind_methods();
	void _main_screen_changed(const String &p_name);

public:
	bool has_main_screen() const override { return true; }
	bool keeps_workspace_fixed() const override { return true; }
	String get_plugin_name() const override { return "AI Assistant"; }
	void make_visible(bool p_visible) override;
	void set_chat_placement(int p_placement);
	int get_chat_placement() const { return chat_placement; }
	int64_t runtime_request(const String &p_command, const Dictionary &p_arguments);
	Dictionary runtime_poll(int64_t p_id);
	Dictionary experiment_launch(const String &p_project, const String &p_scene);
	void experiment_stop();
	Dictionary speech_request(const String &p_action, const Dictionary &p_args);
	Dictionary linux_runtime_request(const String &p_action, const Dictionary &p_args);
	Dictionary termux_blender_request(const String &p_action, const Dictionary &p_args);
	Dictionary script_diagnostics(const String &p_source, const String &p_path);
	Dictionary diagnostics_snapshot();
	Dictionary debugger_snapshot();
	Dictionary debugger_status();
	void open_debugger_errors();
	Dictionary panel_snapshot(const String &p_section, int p_session, int p_offset, int p_limit, int p_frame, const String &p_monitor = String());
	Dictionary audio_bus_activity(int p_bus) const;
	bool scene_is_unsaved(const String &p_path);
	bool create_scene_root(Node *p_node);
	void prepare_script_removal(const PackedStringArray &p_paths);
	void push_editor_input(Viewport *p_viewport, const Ref<InputEvent> &p_event);
	void install_asset_archive(const String &p_path, const String &p_title);
	void open_settings(const String &p_section = String());
	AIAssistantEditorPlugin();
	~AIAssistantEditorPlugin();
};

// Independent host: loads only Ziva's two scripts, never the assistant panel.
class AIZivaPanel : public VBoxContainer {
	GDCLASS(AIZivaPanel, VBoxContainer);
	Ref<GDScript> model_script;
	Ref<GDScript> screen_script;
	Ref<RefCounted> model;

protected:
	static void _bind_methods();

public:
	Dictionary linux_runtime_request(const String &p_action, const Dictionary &p_args);
	void configure_project(const String &p_project);
	AIZivaPanel();
};

class AIZivaEditorPlugin : public EditorPlugin {
	GDCLASS(AIZivaEditorPlugin, EditorPlugin);
	Control *screen = nullptr;
	bool workspace_active = false;
	bool previous_workspace_expanded = false;
	void _expand_workspace();

protected:
	static void _bind_methods();

public:
	bool has_main_screen() const override { return true; }
	bool keeps_workspace_fixed() const override { return true; }
	String get_plugin_name() const override { return "Ziva"; }
	void make_visible(bool p_visible) override;
	AIZivaEditorPlugin();
	~AIZivaEditorPlugin();
};

// A host for the shared chat that does not construct an EditorPlugin or EditorNode.
class AIAssistantProjectManager : public VBoxContainer {
	GDCLASS(AIAssistantProjectManager, VBoxContainer);
	Control *panel = nullptr;
	Ref<AIAssistantSecretStore> secrets;
	Vector<Ref<GDScript>> scripts;

protected:
	static void _bind_methods();

public:
	void project_action(const String &p_action);
	void open_settings(const String &p_section = String());
	Dictionary speech_request(const String &p_action, const Dictionary &p_args);
	Dictionary linux_runtime_request(const String &p_action, const Dictionary &p_args);
	bool prepare_project(const String &p_path);
	AIAssistantProjectManager();
};
