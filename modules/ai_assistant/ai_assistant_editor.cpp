/**************************************************************************/
/*  ai_assistant_editor.cpp                                               */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "ai_assistant_editor.h"

#include "runtime.gen.h"

#include "core/config/project_settings.h"
#include "core/crypto/crypto.h"
#include "core/io/config_file.h"
#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/object/callable_mp.h"
#include "core/object/class_db.h"
#include "editor/asset_library/editor_asset_installer.h"
#include "editor/debugger/editor_debugger_node.h"
#include "editor/debugger/script_editor_debugger.h"
#include "editor/docks/editor_dock.h"
#include "editor/docks/editor_dock_manager.h"
#include "editor/editor_interface.h"
#include "editor/editor_log.h"
#include "editor/editor_main_screen.h"
#include "editor/editor_node.h"
#include "editor/file_system/editor_paths.h"
#include "editor/run/run_instances_dialog.h"
#include "editor/settings/editor_settings.h"
#include "editor/themes/editor_scale.h"
#include "scene/gui/box_container.h"
#include "scene/gui/button.h"
#include "servers/audio/audio_server.h"

#include "modules/gdscript/gdscript_cache.h"

#ifdef ANDROID_ENABLED
#include "platform/android/jni_utils.h"
#include "platform/android/thread_jandroid.h"

static String ai_android_vault(const char *p_method, const String &p_name, const String &p_value = String()) {
	JNIEnv *env = get_jni_env();
	jclass cls = jni_find_class(env, "org/godotengine/editor/AISecretVault");
	ERR_FAIL_NULL_V(cls, String());
	bool writing = String(p_method) == "store";
	jmethodID method = env->GetStaticMethodID(cls, p_method, writing ? "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;" : "(Ljava/lang/String;)Ljava/lang/String;");
	if (!method || env->ExceptionCheck()) {
		env->ExceptionClear();
		env->DeleteLocalRef(cls);
		return String();
	}
	jstring name = env->NewStringUTF(p_name.utf8().get_data());
	jstring value = nullptr;
	jstring result = nullptr;
	if (writing) {
		value = env->NewStringUTF(p_value.utf8().get_data());
		result = (jstring)env->CallStaticObjectMethod(cls, method, name, value);
	} else {
		result = (jstring)env->CallStaticObjectMethod(cls, method, name);
	}
	String output;
	if (env->ExceptionCheck()) {
		env->ExceptionClear();
	} else {
		output = jstring_to_string(result, env);
	}
	if (result) {
		env->DeleteLocalRef(result);
	}
	if (value) {
		env->DeleteLocalRef(value);
	}
	env->DeleteLocalRef(name);
	env->DeleteLocalRef(cls);
	return output;
}
#endif

void AIAssistantSecretStore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("store", "name", "value"), &AIAssistantSecretStore::store);
	ClassDB::bind_method(D_METHOD("read", "name"), &AIAssistantSecretStore::read);
	ClassDB::bind_method(D_METHOD("erase", "name"), &AIAssistantSecretStore::erase);
}

bool AIAssistantSecretStore::ensure_directory() {
	if (!master_key.is_empty()) {
		return true;
	}
	directory = EditorPaths::get_singleton()->get_config_dir().path_join("ai_assistant_secrets");
	if (DirAccess::make_dir_recursive_absolute(directory) != OK) {
		return false;
	}
	const String key_path = directory.path_join("master.key");
	if (FileAccess::exists(key_path)) {
		master_key = FileAccess::get_file_as_bytes(key_path);
	} else {
		Ref<Crypto> crypto = Crypto::create();
		ERR_FAIL_COND_V(crypto.is_null(), false);
		master_key = crypto->generate_random_bytes(32);
		Ref<FileAccess> file = FileAccess::open(key_path, FileAccess::WRITE);
		ERR_FAIL_COND_V(file.is_null(), false);
		file->store_buffer(master_key);
		file.unref();
		FileAccess::set_unix_permissions(key_path, 0600);
	}
	return master_key.size() == 32;
}

bool AIAssistantSecretStore::store(const String &p_name, const String &p_value) {
#ifdef ANDROID_ENABLED
	return ai_android_vault("store", p_name, p_value) == "ok";
#else
	ERR_FAIL_COND_V(!ensure_directory(), false);
	Ref<ConfigFile> file;
	file.instantiate();
	file->set_value("secret", "value", p_value);
	String path = directory.path_join(p_name.sha256_text() + ".cfg");
	Error err = file->save_encrypted(path + ".tmp", master_key);
	if (err != OK) {
		return false;
	}
	FileAccess::set_unix_permissions(path + ".tmp", 0600);
	return DirAccess::rename_absolute(path + ".tmp", path) == OK;
#endif
}

String AIAssistantSecretStore::read(const String &p_name) {
#ifdef ANDROID_ENABLED
	return ai_android_vault("read", p_name);
#else
	ERR_FAIL_COND_V(!ensure_directory(), String());
	String path = directory.path_join(p_name.sha256_text() + ".cfg");
	if (!FileAccess::exists(path)) {
		return String();
	}
	Ref<ConfigFile> file;
	file.instantiate();
	if (file->load_encrypted(path, master_key) != OK) {
		return String();
	}
	return file->get_value("secret", "value", String());
#endif
}

bool AIAssistantSecretStore::erase(const String &p_name) {
#ifdef ANDROID_ENABLED
	return ai_android_vault("erase", p_name) == "ok";
#else
	ERR_FAIL_COND_V(!ensure_directory(), false);
	String path = directory.path_join(p_name.sha256_text() + ".cfg");
	return !FileAccess::exists(path) || DirAccess::remove_absolute(path) == OK;
#endif
}

bool AIAssistantSettingsInspector::can_handle(Object *p_object) {
	return Object::cast_to<EditorSettings>(p_object) != nullptr;
}

bool AIAssistantSettingsInspector::parse_property(Object *p_object, const Variant::Type p_type, const String &p_path, const PropertyHint p_hint, const String &p_hint_text, const BitField<PropertyUsageFlags> p_usage, const bool p_wide) {
	if (p_path.begins_with("ai_assistant/general/") && !p_path.ends_with("/configure")) {
		return true;
	}
	if (!p_path.begins_with("ai_assistant/") || !p_path.ends_with("/configure")) {
		return false;
	}
	Button *button = memnew(Button);
	button->set_text(TTR("Configure AI Assistant…"));
	button->connect(SceneStringName(pressed), callable_mp(plugin, &AIAssistantEditorPlugin::open_settings).bind(p_path.get_slice("/", 1)));
	add_custom_control(button);
	return true;
}

void AIAssistantEditorPlugin::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_chat_placement", "placement"), &AIAssistantEditorPlugin::set_chat_placement);
	ClassDB::bind_method(D_METHOD("get_chat_placement"), &AIAssistantEditorPlugin::get_chat_placement);
	ClassDB::bind_method(D_METHOD("runtime_request", "command", "arguments"), &AIAssistantEditorPlugin::runtime_request);
	ClassDB::bind_method(D_METHOD("runtime_poll", "id"), &AIAssistantEditorPlugin::runtime_poll);
	ClassDB::bind_method(D_METHOD("experiment_launch", "project", "scene"), &AIAssistantEditorPlugin::experiment_launch);
	ClassDB::bind_method(D_METHOD("experiment_stop"), &AIAssistantEditorPlugin::experiment_stop);
	ClassDB::bind_method(D_METHOD("speech_request", "action", "arguments"), &AIAssistantEditorPlugin::speech_request);
	ClassDB::bind_method(D_METHOD("linux_runtime_request", "action", "arguments"), &AIAssistantEditorPlugin::linux_runtime_request);
	ClassDB::bind_method(D_METHOD("termux_blender_request", "action", "arguments"), &AIAssistantEditorPlugin::termux_blender_request);
	ClassDB::bind_method(D_METHOD("script_diagnostics", "source", "path"), &AIAssistantEditorPlugin::script_diagnostics);
	ClassDB::bind_method(D_METHOD("diagnostics_snapshot"), &AIAssistantEditorPlugin::diagnostics_snapshot);
	ClassDB::bind_method(D_METHOD("debugger_snapshot"), &AIAssistantEditorPlugin::debugger_snapshot);
	ClassDB::bind_method(D_METHOD("debugger_status"), &AIAssistantEditorPlugin::debugger_status);
	ClassDB::bind_method(D_METHOD("open_debugger_errors"), &AIAssistantEditorPlugin::open_debugger_errors);
	ClassDB::bind_method(D_METHOD("panel_snapshot", "section", "session", "offset", "limit", "frame", "monitor"), &AIAssistantEditorPlugin::panel_snapshot, DEFVAL(String()));
	ClassDB::bind_method(D_METHOD("audio_bus_activity", "bus"), &AIAssistantEditorPlugin::audio_bus_activity);
	ClassDB::bind_method(D_METHOD("scene_is_unsaved", "path"), &AIAssistantEditorPlugin::scene_is_unsaved);
	ClassDB::bind_method(D_METHOD("create_scene_root", "node"), &AIAssistantEditorPlugin::create_scene_root);
	ClassDB::bind_method(D_METHOD("prepare_script_removal", "paths"), &AIAssistantEditorPlugin::prepare_script_removal);
	ClassDB::bind_method(D_METHOD("push_editor_input", "viewport", "event"), &AIAssistantEditorPlugin::push_editor_input);
	ClassDB::bind_method(D_METHOD("install_asset_archive", "path", "title"), &AIAssistantEditorPlugin::install_asset_archive);
	ClassDB::bind_method(D_METHOD("open_settings", "section"), &AIAssistantEditorPlugin::open_settings, DEFVAL(String()));
}

bool AIAssistantEditorPlugin::scene_is_unsaved(const String &p_path) {
	EditorData &editor_data = EditorNode::get_editor_data();
	for (int index = 0; index < editor_data.get_edited_scene_count(); index++) {
		if (editor_data.get_scene_path(index) == p_path) {
			return EditorNode::get_singleton()->is_scene_unsaved(index);
		}
	}
	return false;
}

bool AIAssistantEditorPlugin::create_scene_root(Node *p_node) {
	ERR_FAIL_NULL_V(p_node, false);
	ERR_FAIL_COND_V(p_node->get_parent() || p_node->is_inside_tree(), false);
	EditorNode::get_singleton()->new_scene();
	EditorInterface::get_singleton()->add_root_node(p_node);
	return EditorInterface::get_singleton()->get_edited_scene_root() == p_node;
}

void AIAssistantEditorPlugin::_capture_diagnostic(void *p_user, const char *p_function, const char *p_file, int p_line, const char *p_error, const char *p_description, bool p_notify, ErrorHandlerType p_type) {
	auto *self = static_cast<AIAssistantEditorPlugin *>(p_user);
	MutexLock lock(self->diagnostic_mutex);
	Dictionary event;
	event["sequence"] = ++self->diagnostic_sequence;
	event["path"] = String::utf8(p_file);
	event["line"] = p_line;
	event["function"] = String::utf8(p_function);
	event["severity"] = p_type == ERR_HANDLER_WARNING ? "warning" : "error";
	event["category"] = p_type == ERR_HANDLER_SHADER ? "shader" : (p_type == ERR_HANDLER_SCRIPT ? "script" : "engine");
	event["message"] = (String::utf8(p_error) + " " + String::utf8(p_description)).strip_edges().left(1200);
	if (self->diagnostic_events.size() >= 128) {
		self->diagnostic_events.pop_front();
	}
	self->diagnostic_events.append(event);
}

Dictionary AIAssistantEditorPlugin::diagnostics_snapshot() {
	MutexLock lock(diagnostic_mutex);
	Dictionary payload;
	payload["events"] = diagnostic_events.duplicate(true);
	payload["sequence"] = diagnostic_sequence;
	payload["truncated"] = diagnostic_sequence > diagnostic_events.size();
	Dictionary result;
	result["ok"] = true;
	result["result"] = payload;
	return result;
}

Dictionary AIAssistantEditorPlugin::debugger_snapshot() {
	Dictionary response;
	EditorDebuggerNode *node = EditorDebuggerNode::get_singleton();
	if (!node || runtime_debugger.is_null()) {
		response["ok"] = false;
		response["code"] = "debugger_unavailable";
		response["error"] = "Native editor debugger is unavailable.";
		return response;
	}
	Array sessions;
	Array events;
	int errors = 0;
	int warnings = 0;
	bool truncated = false;
	const Array registered = runtime_debugger->get_sessions();
	ScriptEditorDebugger *current = node->get_current_debugger();
	Vector<int> order;
	for (int i = 0; i < registered.size(); i++) {
		if (node->get_debugger(i) == current) {
			order.insert(0, i);
		} else {
			order.push_back(i);
		}
	}
	for (int index = 0; index < order.size(); index++) {
		const int i = order[index];
		ScriptEditorDebugger *debugger = node->get_debugger(i);
		if (!debugger) {
			continue;
		}
		Dictionary snapshot = debugger->get_error_snapshot();
		Array rows = snapshot["events"];
		for (int j = 0; j < rows.size(); j++) {
			Dictionary event = rows[j];
			event["session"] = i;
			event["generation"] = snapshot["generation"];
			event["active"] = snapshot["active"];
			if (events.size() < 512) {
				events.push_back(event);
			} else {
				truncated = true;
			}
		}
		errors += int(snapshot["errors"]);
		warnings += int(snapshot["warnings"]);
		truncated = truncated || bool(snapshot["truncated"]);
		snapshot.erase("events");
		snapshot["session"] = i;
		snapshot["current"] = debugger == current;
		sessions.push_back(snapshot);
	}
	Dictionary payload;
	payload["available"] = true;
	payload["sessions"] = sessions;
	payload["events"] = events;
	payload["errors"] = errors;
	payload["warnings"] = warnings;
	payload["truncated"] = truncated;
	response["ok"] = true;
	response["result"] = payload;
	return response;
}

Dictionary AIAssistantEditorPlugin::debugger_status() {
	Dictionary response;
	EditorDebuggerNode *node = EditorDebuggerNode::get_singleton();
	if (!node || runtime_debugger.is_null()) {
		response["ok"] = false;
		return response;
	}
	int errors = 0;
	int warnings = 0;
	const Array sessions = runtime_debugger->get_sessions();
	for (int i = 0; i < sessions.size(); i++) {
		ScriptEditorDebugger *debugger = node->get_debugger(i);
		if (!debugger) {
			continue;
		}
		errors += debugger->get_error_count();
		warnings += debugger->get_warning_count();
	}
	response["ok"] = true;
	response["errors"] = errors;
	response["warnings"] = warnings;
	return response;
}

void AIAssistantEditorPlugin::open_debugger_errors() {
	EditorDebuggerNode *node = EditorDebuggerNode::get_singleton();
	EditorDockManager *docks = EditorDockManager::get_singleton();
	ERR_FAIL_NULL(node);
	ERR_FAIL_NULL(docks);
	docks->open_dock(node, true);
	ScriptEditorDebugger *debugger = node->get_current_debugger();
	if (debugger) {
		debugger->switch_to_debugger(1);
	}
}

Dictionary AIAssistantEditorPlugin::panel_snapshot(const String &p_section, int p_session, int p_offset, int p_limit, int p_frame, const String &p_monitor) {
	Dictionary response;
	if (p_offset < 0 || p_limit < 1 || p_limit > 100 || p_session < -1 || p_frame < -1) {
		response["ok"] = false;
		response["code"] = "invalid_arguments";
		return response;
	}
	Dictionary payload;
	EditorDebuggerNode *node = EditorDebuggerNode::get_singleton();
	if (p_section == "output" && EditorNode::get_singleton() && EditorNode::get_log()) {
		payload = EditorNode::get_log()->get_message_snapshot(p_offset, p_limit);
	} else if (node && runtime_debugger.is_valid() && p_session < runtime_debugger->get_sessions().size()) {
		ScriptEditorDebugger *debugger = p_session < 0 ? node->get_current_debugger() : node->get_debugger(p_session);
		if (debugger) {
			payload = debugger->get_panel_snapshot(p_section, p_offset, p_limit, p_frame, p_monitor);
			const Array sessions = runtime_debugger->get_sessions();
			for (int i = 0; i < sessions.size(); i++) {
				if (node->get_debugger(i) == debugger) {
					payload["session"] = i;
					break;
				}
			}
		}
	}
	if (payload.is_empty() || bool(payload.get("unsupported", false))) {
		response["ok"] = false;
		response["code"] = "panel_data_unavailable";
		response["error"] = "Native panel source or session is unavailable.";
	} else {
		payload["available"] = true;
		payload["offset"] = p_offset;
		response["ok"] = true;
		response["result"] = payload;
	}
	return response;
}

Dictionary AIAssistantEditorPlugin::audio_bus_activity(int p_bus) const {
	Dictionary result;
	AudioServer *audio = AudioServer::get_singleton();
	if (!audio || p_bus < 0 || p_bus >= audio->get_bus_count()) {
		result["available"] = false;
		return result;
	}
	result["available"] = true;
	result["active"] = audio->is_bus_channel_active(p_bus, 0);
	return result;
}

Dictionary AIAssistantEditorPlugin::script_diagnostics(const String &p_source, const String &p_path) {
	Dictionary response;
	if (p_source.utf8().length() > 1024 * 1024 || !p_path.begins_with("res://") || p_path.get_extension() != "gd") {
		response["ok"] = false;
		response["code"] = "invalid_arguments";
		response["error"] = "Expected a project GDScript path and at most 1 MB of source.";
		return response;
	}
	List<ScriptLanguage::ScriptError> errors;
	List<ScriptLanguage::Warning> warnings;
	List<String> functions;
	const bool valid = GDScriptLanguage::get_singleton()->validate(p_source, p_path, &functions, &errors, &warnings);
	Array diagnostics;
	for (const ScriptLanguage::ScriptError &error : errors) {
		if (diagnostics.size() >= 200) {
			break;
		}
		Dictionary entry;
		entry["severity"] = "error";
		entry["path"] = error.path;
		entry["line"] = error.line;
		entry["column"] = error.column;
		entry["message"] = error.message;
		diagnostics.push_back(entry);
	}
	for (const ScriptLanguage::Warning &warning : warnings) {
		if (diagnostics.size() >= 200) {
			break;
		}
		Dictionary entry;
		entry["severity"] = "warning";
		entry["path"] = p_path;
		entry["line"] = warning.start_line;
		entry["end_line"] = warning.end_line;
		entry["code"] = warning.string_code;
		entry["message"] = warning.message;
		diagnostics.push_back(entry);
	}
	Array found_functions;
	for (const String &function : functions) {
		if (found_functions.size() >= 200) {
			break;
		}
		found_functions.push_back(function);
	}
	Dictionary result;
	result["path"] = p_path;
	result["valid"] = valid;
	result["diagnostics"] = diagnostics;
	result["functions"] = found_functions;
	result["truncated"] = errors.size() + warnings.size() > diagnostics.size() || functions.size() > found_functions.size();
	response["ok"] = true;
	response["result"] = result;
	return response;
}

int64_t AIAssistantEditorPlugin::runtime_request(const String &p_command, const Dictionary &p_arguments) {
	return runtime_debugger.is_valid() ? runtime_debugger->request(p_command, p_arguments) : -1;
}
Dictionary AIAssistantEditorPlugin::runtime_poll(int64_t p_id) {
	return runtime_debugger->poll(p_id);
}
Dictionary AIAssistantEditorPlugin::experiment_launch(const String &p_project, const String &p_scene) {
	Dictionary response;
	response["ok"] = false;
	response["code"] = "invalid_experiment";
	String managed = panel ? String(panel->get("project_directory")).path_join("engineering/experiments").simplify_path() : String();
	String project = p_project.simplify_path();
	String relative_scene = p_scene.trim_prefix("res://");
	if (managed.is_empty() || !project.is_absolute_path() || !project.begins_with(managed + "/") || !project.ends_with("/project") ||
			!p_scene.begins_with("res://") || relative_scene.contains("..") || relative_scene.contains("\\") ||
			!FileAccess::exists(project.path_join("project.godot")) || !FileAccess::exists(project.path_join(relative_scene))) {
		response["error"] = "Only a managed project copy and an existing scene can be launched.";
		return response;
	}
	if (EditorInterface::get_singleton()->is_playing_scene() || experiment_runner.get_status() != EditorRun::STATUS_STOP) {
		response["code"] = "game_already_running";
		response["error"] = "Finish the existing game session before starting an experiment.";
		return response;
	}
	if (RunInstancesDialog::get_singleton()->get_instance_count() != 1) {
		response["error"] = "An isolated experiment requires exactly one configured run instance.";
		return response;
	}
	EditorDebuggerNode *debugger = EditorDebuggerNode::get_singleton();
	String uri = debugger->get_server_uri();
	debugger->start(uri.is_empty() ? String("tcp://") : uri);
	Vector<String> arguments;
	arguments.push_back("--path");
	arguments.push_back(project.replace(" ", "%20"));
	arguments.push_back("--ignore-error-breaks");
	// EditorRun supplies platform-native process dispatch, including Android.
	// This path deliberately avoids autosaving/building the original project.
	Error error = experiment_runner.run(project.path_join(relative_scene), "", arguments);
	if (error != OK) {
		experiment_runner.stop();
		response["error"] = "The native game process could not be started.";
		return response;
	}
	Dictionary result;
	result["project"] = project;
	result["scene"] = p_scene;
	result["requested"] = true;
	result["verified"] = false;
	response["ok"] = true;
	response["result"] = result;
	return response;
}
void AIAssistantEditorPlugin::experiment_stop() {
	experiment_runner.stop();
}
static Dictionary ai_speech_request(const String &p_action, const Dictionary &p_args) {
#ifdef ANDROID_ENABLED
	JNIEnv *env = get_jni_env();
	jclass cls = jni_find_class(env, "org/godotengine/editor/AIVoice");
	if (!cls) {
		return Dictionary();
	}
	jmethodID method = env->GetStaticMethodID(cls, "command", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
	if (!method) {
		env->ExceptionClear();
		env->DeleteLocalRef(cls);
		return Dictionary();
	}
	jstring action = env->NewStringUTF(p_action.utf8().get_data());
	jstring args = env->NewStringUTF(JSON::stringify(p_args).utf8().get_data());
	jstring result = (jstring)env->CallStaticObjectMethod(cls, method, action, args);
	String output;
	if (env->ExceptionCheck()) {
		env->ExceptionClear();
	} else if (result) {
		output = jstring_to_string(result, env);
	}
	if (result) {
		env->DeleteLocalRef(result);
	}
	env->DeleteLocalRef(action);
	env->DeleteLocalRef(args);
	env->DeleteLocalRef(cls);
	Variant parsed = JSON::parse_string(output);
	return parsed.get_type() == Variant::DICTIONARY ? Dictionary(parsed) : Dictionary();
#else
	Dictionary result;
	result["error"] = "Dictarea Android nu este disponibilă pe această platformă.";
	return result;
#endif
}

Dictionary AIAssistantEditorPlugin::speech_request(const String &p_action, const Dictionary &p_args) {
	return ai_speech_request(p_action, p_args);
}

Dictionary AIAssistantEditorPlugin::termux_blender_request(const String &p_action, const Dictionary &p_args) {
#ifdef ANDROID_ENABLED
	JNIEnv *env = get_jni_env();
	jclass cls = jni_find_class(env, "org/godotengine/editor/AITermuxBlender");
	if (!cls) {
		return Dictionary();
	}
	jmethodID method = env->GetStaticMethodID(cls, "command", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
	if (!method || env->ExceptionCheck()) {
		env->ExceptionClear();
		env->DeleteLocalRef(cls);
		return Dictionary();
	}
	jstring action = env->NewStringUTF(p_action.utf8().get_data());
	jstring args = env->NewStringUTF(JSON::stringify(p_args).utf8().get_data());
	jstring result = (jstring)env->CallStaticObjectMethod(cls, method, action, args);
	String output;
	if (env->ExceptionCheck()) {
		env->ExceptionClear();
	} else if (result) {
		output = jstring_to_string(result, env);
	}
	if (result) {
		env->DeleteLocalRef(result);
	}
	env->DeleteLocalRef(action);
	env->DeleteLocalRef(args);
	env->DeleteLocalRef(cls);
	Variant parsed = JSON::parse_string(output);
	return parsed.get_type() == Variant::DICTIONARY ? Dictionary(parsed) : Dictionary();
#else
	Dictionary result;
	result["ok"] = false;
	result["error"] = "Conectorul Termux necesită editorul Android.";
	return result;
#endif
}

static Dictionary ai_linux_runtime_request(const String &p_action, const Dictionary &p_args) {
#ifdef ANDROID_ENABLED
	JNIEnv *env = get_jni_env();
	jclass cls = jni_find_class(env, "org/godotengine/editor/AILinuxRuntime");
	if (!cls) {
		return Dictionary();
	}
	jmethodID method = env->GetStaticMethodID(cls, "command", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
	if (!method || env->ExceptionCheck()) {
		env->ExceptionClear();
		env->DeleteLocalRef(cls);
		return Dictionary();
	}
	jstring action = env->NewStringUTF(p_action.utf8().get_data());
	jstring args = env->NewStringUTF(JSON::stringify(p_args).utf8().get_data());
	jstring result = (jstring)env->CallStaticObjectMethod(cls, method, action, args);
	String output;
	if (env->ExceptionCheck()) {
		env->ExceptionClear();
	} else if (result) {
		output = jstring_to_string(result, env);
	}
	if (result) {
		env->DeleteLocalRef(result);
	}
	env->DeleteLocalRef(action);
	env->DeleteLocalRef(args);
	env->DeleteLocalRef(cls);
	Variant parsed = JSON::parse_string(output);
	return parsed.get_type() == Variant::DICTIONARY ? Dictionary(parsed) : Dictionary();
#else
	Dictionary result;
	result["ok"] = false;
	result["error"] = "Runtime Linux integrat necesită editorul Android.";
	return result;
#endif
}

Dictionary AIAssistantEditorPlugin::linux_runtime_request(const String &p_action, const Dictionary &p_args) {
	Dictionary args = p_args.duplicate(true);
	if (p_action == "execute") {
		args["project_directory"] = ProjectSettings::get_singleton()->globalize_path("res://");
	}
	return ai_linux_runtime_request(p_action, args);
}

Dictionary AIAssistantProjectManager::linux_runtime_request(const String &p_action, const Dictionary &p_args) {
	if (p_action == "execute") {
		Dictionary result;
		result["ok"] = false;
		result["error"] = "Deschide un proiect înainte de rularea comenzilor Linux.";
		return result;
	}
	return ai_linux_runtime_request(p_action, p_args);
}

void AIAssistantEditorPlugin::make_visible(bool p_visible) {
	if (chat_dock) {
		if (p_visible) {
			chat_dock->make_visible();
			callable_mp(EditorNode::get_singleton()->get_editor_main_screen(), &EditorMainScreen::select_by_name).call_deferred(dock_workspace);
		}
		return;
	}
	if (panel) {
		panel->set_visible(p_visible);
	}
}

void AIAssistantEditorPlugin::_main_screen_changed(const String &p_name) {
	// A side chat returns to an editing workspace. Ziva owns the full central
	// area and hides docks, so it must not become the side chat's fallback.
	if (p_name != get_plugin_name() && p_name != "Ziva") {
		dock_workspace = p_name;
	}
}

void AIAssistantEditorPlugin::set_chat_placement(int p_placement) {
	ERR_FAIL_COND(p_placement < 0 || p_placement > 2);
	if (!panel || chat_placement == p_placement) {
		return;
	}
	if (chat_dock) {
		chat_dock->remove_child(panel);
		remove_dock(chat_dock);
		chat_dock->queue_free();
		chat_dock = nullptr;
	} else if (panel->get_parent()) {
		panel->get_parent()->remove_child(panel);
	}
	chat_placement = p_placement;
	EditorMainScreen *main_screen = EditorNode::get_singleton()->get_editor_main_screen();
	if (p_placement == 0) {
		main_screen->get_control()->add_child(panel);
		panel->set_custom_minimum_size(Size2(0, 200) * EDSCALE);
		main_screen->select_by_name(get_plugin_name());
	} else {
		chat_dock = memnew(EditorDock);
		chat_dock->set_title("AI Assistant");
		chat_dock->set_layout_key("GodotAIAssistant");
		chat_dock->set_default_slot(p_placement == 1 ? EditorDock::DOCK_SLOT_LEFT_UL : EditorDock::DOCK_SLOT_RIGHT_UL);
		panel->set_custom_minimum_size(Size2(200, 200) * EDSCALE);
		chat_dock->add_child(panel);
		add_dock(chat_dock);
		chat_dock->make_visible();
		if (main_screen->get_selected_plugin() == this) {
			main_screen->select_by_name(dock_workspace);
		}
	}
	panel->show();
}

void AIAssistantEditorPlugin::open_settings(const String &p_section) {
	if (!panel) {
		return;
	}
	EditorMainScreen *main_screen = EditorNode::get_singleton()->get_editor_main_screen();
	if (chat_dock) {
		chat_dock->make_visible();
	} else if (main_screen) {
		main_screen->select_by_name(get_plugin_name());
	}
	panel->call("open_settings", p_section);
}

static bool ai_load_scripts(Vector<Ref<GDScript>> &scripts) {
	for (const AIScriptSource &source : ai_script_sources) {
		Ref<GDScript> script;
		script.instantiate();
		script->set_path(String("local://godot_ai/") + source.name + ".gd");
		script->set_source_code(String::utf8((const char *)source.data));
		if (script->reload() != OK) {
			ERR_PRINT(String("AI Assistant could not load embedded script: ") + source.name);
			return false;
		}
		for (int i = 0; i < scripts.size(); i++) {
			script->set(ai_script_sources[i].binding, scripts[i]);
		}
		script->set_edited(false);
		scripts.push_back(script);
	}
	return true;
}

void AIZivaPanel::_bind_methods() {
	ClassDB::bind_method(D_METHOD("linux_runtime_request", "action", "arguments"), &AIZivaPanel::linux_runtime_request);
}
Dictionary AIZivaPanel::linux_runtime_request(const String &p_action, const Dictionary &p_args) {
	ERR_FAIL_COND_V(!p_action.begins_with("ziva_"), Dictionary());
	return ai_linux_runtime_request(p_action, p_args);
}
void AIZivaPanel::configure_project(const String &p_project) {
	if (model.is_valid()) {
		model->set("project_directory", p_project);
	}
}
AIZivaPanel::AIZivaPanel() {
	set_name("ZivaMainScreen");
	set_h_size_flags(Control::SIZE_EXPAND_FILL);
	set_v_size_flags(Control::SIZE_EXPAND_FILL);
	for (const AIScriptSource &source : ai_script_sources) {
		String name = source.name;
		if (name != "ziva" && name != "ziva_screen") {
			continue;
		}
		Ref<GDScript> script;
		script.instantiate();
		script->set_path("local://godot_ziva/" + name + ".gd");
		script->set_source_code(String::utf8((const char *)source.data));
		ERR_FAIL_COND(script->reload() != OK);
		if (name == "ziva") {
			model_script = script;
		} else {
			screen_script = script;
		}
	}
	ERR_FAIL_COND(model_script.is_null() || screen_script.is_null());
	model.instantiate();
	model->set_script(model_script);
	model->set("bridge", this);
	set_script(screen_script);
	call("configure", this, model);
}
AIZivaEditorPlugin::AIZivaEditorPlugin() {
	AIZivaPanel *ziva = memnew(AIZivaPanel);
	ziva->configure_project(ProjectSettings::get_singleton()->globalize_path("res://").trim_suffix("/"));
	screen = ziva;
	screen->hide();
	EditorNode::get_singleton()->get_editor_main_screen()->get_control()->add_child(screen);
}
void AIZivaEditorPlugin::_bind_methods() {
	ClassDB::bind_method(D_METHOD("_expand_workspace"), &AIZivaEditorPlugin::_expand_workspace);
}
void AIZivaEditorPlugin::_expand_workspace() {
	// Main-screen selection restores the scene/script layout after make_visible().
	// Apply the tab's layout afterwards, without changing those saved preferences.
	if (workspace_active && screen && screen->is_visible_in_tree()) {
		EditorNode::get_singleton()->set_distraction_free_mode(true);
	}
}
void AIZivaEditorPlugin::make_visible(bool p_visible) {
	if (!screen) {
		return;
	}
	if (p_visible && !workspace_active) {
		previous_workspace_expanded = EditorNode::get_singleton()->is_distraction_free_mode_enabled();
		workspace_active = true;
		call_deferred(SNAME("_expand_workspace"));
	} else if (!p_visible && workspace_active) {
		workspace_active = false;
		EditorNode::get_singleton()->set_distraction_free_mode(previous_workspace_expanded);
	}
	screen->set_visible(p_visible);
}
AIZivaEditorPlugin::~AIZivaEditorPlugin() {
	if (screen) {
		make_visible(false);
		if (screen->get_parent()) {
			screen->get_parent()->remove_child(screen);
		}
		memdelete(screen);
	}
}

AIAssistantEditorPlugin *AIAssistantEditorPlugin::singleton = nullptr;

AIAssistantEditorPlugin::AIAssistantEditorPlugin() {
	singleton = this;
	diagnostic_handler.errfunc = _capture_diagnostic;
	diagnostic_handler.userdata = this;
	add_error_handler(&diagnostic_handler);
	connect("main_screen_changed", callable_mp(this, &AIAssistantEditorPlugin::_main_screen_changed));
	EDITOR_DEF("ai_assistant/general/configure", String());
	EDITOR_DEF("ai_assistant/providers/configure", String());
	EDITOR_DEF("ai_assistant/accounts/configure", String());
	EDITOR_DEF("ai_assistant/generation/configure", String());
	EDITOR_DEF("ai_assistant/mcp/configure", String());
	EDITOR_DEF("ai_assistant/integrations/configure", String());
	EDITOR_DEF("ai_assistant/journal/configure", String());
	EDITOR_DEF("ai_assistant/agent/configure", String());
	EDITOR_DEF("ai_assistant/companion/url", "http://127.0.0.1:7341");
	EDITOR_DEF("ai_assistant/generation/import_directory", "res://ai_assets");
	EDITOR_DEF("ai_assistant/connection/request_timeout_seconds", 180);
	secrets.instantiate();
	runtime_debugger.instantiate();
	add_debugger_plugin(runtime_debugger);

	if (!ai_load_scripts(scripts)) {
		return;
	}
	panel = memnew(VBoxContainer);
	panel->set_name("AIAssistantPanel");
	panel->set_script(scripts[scripts.size() - 1]);
	panel->call("configure", this, secrets);
	panel->set_h_size_flags(Control::SIZE_EXPAND_FILL);
	panel->set_v_size_flags(Control::SIZE_EXPAND_FILL);
	EditorNode::get_singleton()->get_editor_main_screen()->get_control()->add_child(panel);
	panel->hide();
	settings_inspector.instantiate();
	settings_inspector->set_plugin(this);
	add_inspector_plugin(settings_inspector);
}

AIAssistantEditorPlugin::~AIAssistantEditorPlugin() {
	if (singleton == this) {
		singleton = nullptr;
	}
	experiment_runner.stop();
	remove_error_handler(&diagnostic_handler);
	if (runtime_debugger.is_valid()) {
		remove_debugger_plugin(runtime_debugger);
	}
	if (settings_inspector.is_valid()) {
		remove_inspector_plugin(settings_inspector);
	}
	if (panel) {
		if (chat_dock) {
			chat_dock->remove_child(panel);
			remove_dock(chat_dock);
			memdelete(chat_dock);
			chat_dock = nullptr;
		}
		if (panel->get_parent()) {
			panel->get_parent()->remove_child(panel);
		}
		memdelete(panel);
	}
}

void AIAssistantEditorPlugin::install_asset_archive(const String &p_path, const String &p_title) {
	const String base = EditorPaths::get_singleton()->get_config_dir().path_join("ai_assistant/projects");
	ERR_FAIL_COND(!p_path.simplify_path().begins_with(base + "/") || p_path.get_extension() != "zip" || !FileAccess::exists(p_path));
	EditorAssetInstaller *installer = memnew(EditorAssetInstaller);
	panel->add_child(installer);
	installer->set_asset_name(p_title);
	installer->open_asset(p_path, false, false);
	installer->install_approved_asset();
	installer->queue_free();
}

void AIAssistantEditorPlugin::push_editor_input(Viewport *p_viewport, const Ref<InputEvent> &p_event) {
	ERR_FAIL_NULL(p_viewport);
	ERR_FAIL_COND(!p_viewport->is_inside_tree() || p_event.is_null());
	p_viewport->push_editor_input(p_event);
}

void AIAssistantEditorPlugin::prepare_script_removal(const PackedStringArray &p_paths) {
	for (const String &path : p_paths) {
		ERR_CONTINUE(!path.begins_with("res://addons/") || path.simplify_path() != path || path.get_extension() != "gd");
		Error error = OK;
		Ref<GDScript> script = GDScriptCache::get_full_script(path, error);
		GDScriptCache::remove_script(path);
		if (script.is_valid()) {
			script->set_path("");
		}
	}
}

void AIAssistantProjectManager::_bind_methods() {
	ClassDB::bind_method(D_METHOD("open_settings", "section"), &AIAssistantProjectManager::open_settings, DEFVAL(String()));
	ClassDB::bind_method(D_METHOD("project_action", "action"), &AIAssistantProjectManager::project_action);
	ClassDB::bind_method(D_METHOD("speech_request", "action", "arguments"), &AIAssistantProjectManager::speech_request);
	ClassDB::bind_method(D_METHOD("linux_runtime_request", "action", "arguments"), &AIAssistantProjectManager::linux_runtime_request);
	ADD_SIGNAL(MethodInfo("project_action_requested", PropertyInfo(Variant::STRING, "action")));
}

void AIAssistantProjectManager::open_settings(const String &p_section) {
	project_action("assistant");
	if (panel) {
		panel->call("open_settings", p_section);
	}
}

void AIAssistantProjectManager::project_action(const String &p_action) {
	if (p_action == "create" || p_action == "import" || p_action == "projects" || p_action == "assistant") {
		emit_signal("project_action_requested", p_action);
	}
}

Dictionary AIAssistantProjectManager::speech_request(const String &p_action, const Dictionary &p_args) {
	return ai_speech_request(p_action, p_args);
}

bool AIAssistantProjectManager::prepare_project(const String &p_path) {
	return panel && bool(panel->call("prepare_project_handoff", p_path));
}

AIAssistantProjectManager::AIAssistantProjectManager() {
	set_name("AIAssistantStart");
	set_h_size_flags(Control::SIZE_EXPAND_FILL);
	set_v_size_flags(Control::SIZE_EXPAND_FILL);
	secrets.instantiate();
	if (!ai_load_scripts(scripts)) {
		return;
	}
	panel = memnew(VBoxContainer);
	panel->set_name("AIAssistantStartPanel");
	panel->set_script(scripts[scripts.size() - 1]);
	panel->call("configure", this, secrets, true);
	panel->set_h_size_flags(Control::SIZE_EXPAND_FILL);
	panel->set_v_size_flags(Control::SIZE_EXPAND_FILL);
	add_child(panel);
}
