/**************************************************************************/
/*  ai_runtime_bridge.cpp                                                 */
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

#include "ai_runtime_bridge.h"

#include "core/config/engine.h"
#include "core/config/project_settings.h"
#include "core/core_bind.h"
#include "core/crypto/crypto_core.h"
#include "core/debugger/engine_debugger.h"
#include "core/error/error_macros.h"
#include "core/input/input.h"
#include "core/input/input_map.h"
#include "core/io/image.h"
#include "core/math/expression.h"
#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "core/os/mutex.h"
#include "core/os/os.h"
#include "core/os/time.h"
#include "editor/debugger/editor_debugger_node.h"
#include "editor/debugger/script_editor_debugger.h"
#include "main/performance.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"
#include "scene/resources/texture.h"

static Mutex error_mutex;
static PackedStringArray runtime_errors;
static Array runtime_diagnostics;
static int64_t runtime_diagnostic_sequence = 0;

bool AIAssistantDebugger::has_capture(const String &p_capture) const {
	return p_capture == "ai_assistant";
}
bool AIAssistantDebugger::capture(const String &p_message, const Array &p_data, int p_session) {
	if (p_message != "ai_assistant:response" || p_data.size() != 2) {
		return false;
	}
	int64_t id = p_data[0];
	if (pending.has(id) && int(Dictionary(pending[id])["session"]) == p_session) {
		Dictionary state = pending[id];
		ScriptEditorDebugger *debugger = EditorDebuggerNode::get_singleton()->get_debugger(p_session);
		if (debugger && int64_t(debugger->get_error_snapshot().get("generation", -1)) == int64_t(state["generation"])) {
			Dictionary response = p_data[1];
			response["runtime_session"] = p_session;
			response["runtime_generation"] = state["generation"];
			replies[id] = response;
		}
	}
	return true;
}
int64_t AIAssistantDebugger::request(const String &p_command, const Dictionary &p_arguments) {
	EditorDebuggerNode *node = EditorDebuggerNode::get_singleton();
	if (!node) {
		return -1;
	}
	Array session_list = get_sessions();
	int pinned = int(p_arguments.get("__session", -1));
	if (p_arguments.has("__session") && (pinned < 0 || pinned >= session_list.size())) {
		return -1;
	}
	ScriptEditorDebugger *current = pinned >= 0 ? node->get_debugger(pinned) : node->get_current_debugger();
	if (pinned < 0 && (!current || !current->is_session_active())) {
		// A selected stopped tab must not hide the only live game peer.
		current = nullptr;
		for (int i = 0; i < session_list.size(); i++) {
			ScriptEditorDebugger *candidate = node->get_debugger(i);
			if (candidate && candidate->is_session_active()) {
				if (current) {
					return -1; // Ambiguous: the caller must pin a session.
				}
				current = candidate;
			}
		}
	}
	if (!current || !current->is_session_active()) {
		return -1;
	}
	int64_t generation = current->get_error_snapshot().get("generation", -1);
	if (pinned >= 0 && generation != int64_t(p_arguments.get("__generation", -2))) {
		return -1;
	}
	int index = -1;
	for (int i = 0; i < session_list.size(); i++) {
		if (node->get_debugger(i) == current) {
			index = i;
			break;
		}
	}
	if (index < 0) {
		return -1;
	}
	Array keys = pending.keys();
	uint64_t now = OS::get_singleton()->get_ticks_msec();
	for (int i = 0; i < keys.size(); i++) {
		Dictionary state = pending[keys[i]];
		if (now - uint64_t(state["time"]) > uint64_t(state.get("ttl", 15000))) {
			pending.erase(keys[i]);
			replies.erase(keys[i]);
		}
	}
	if (pending.size() >= 64) {
		return -1;
	}
	int64_t id = next_id++;
	Dictionary state;
	state["session"] = index;
	state["generation"] = generation;
	state["time"] = now;
	state["ttl"] = p_command == "act" ? 90000 : 15000;
	pending[id] = state;
	Array data;
	data.append(id);
	data.append(p_command);
	Dictionary arguments = p_arguments.duplicate();
	arguments.erase("__session");
	arguments.erase("__generation");
	data.append(arguments);
	current->send_message("ai_assistant:request", data);
	return id;
}
Dictionary AIAssistantDebugger::poll(int64_t p_id) {
	if (!replies.has(p_id)) {
		return Dictionary();
	}
	Dictionary result = replies[p_id];
	replies.erase(p_id);
	pending.erase(p_id);
	return result;
}

static Dictionary ai_error(const String &p_error) {
	Dictionary result;
	result["ok"] = false;
	result["error"] = p_error;
	return result;
}
static Dictionary ai_success(const Variant &p_value) {
	Dictionary result;
	result["ok"] = true;
	result["result"] = p_value;
	return result;
}
static void ai_send_reply(int64_t p_id, const Dictionary &p_response) {
	if (!EngineDebugger::is_active()) {
		return;
	}
	Array reply;
	reply.append(p_id);
	reply.append(p_response);
	EngineDebugger::get_singleton()->send_message("ai_assistant:response", reply);
}
static Variant ai_runtime_value(const Variant &p_value) {
	switch (p_value.get_type()) {
		case Variant::NIL:
		case Variant::BOOL:
		case Variant::INT:
		case Variant::FLOAT:
		case Variant::STRING:
			return p_value;
		case Variant::VECTOR2:
		case Variant::VECTOR3:
		case Variant::COLOR:
			return p_value.stringify();
		default:
			return String("[complex value]");
	}
}
static Variant ai_probe_value(const Variant &p_value, int p_depth = 0) {
	if (p_depth > 2) {
		return String("[deep]");
	}
	switch (p_value.get_type()) {
		case Variant::NIL:
		case Variant::BOOL:
		case Variant::INT:
		case Variant::FLOAT:
		case Variant::STRING:
			return p_value;
		case Variant::STRING_NAME:
		case Variant::NODE_PATH:
			return String(p_value);
		case Variant::OBJECT: {
			Object *object = p_value;
			Node *node = Object::cast_to<Node>(object);
			return node ? String(node->get_path()) : String("[Object]");
		}
		case Variant::ARRAY: {
			Array source = p_value;
			Array result;
			for (int i = 0; i < source.size() && i < 20; i++) {
				result.append(ai_probe_value(source[i], p_depth + 1));
			}
			if (source.size() > 20) {
				result.append("...");
			}
			return result;
		}
		case Variant::DICTIONARY: {
			Dictionary source = p_value;
			Dictionary result;
			int count = 0;
			for (const KeyValue<Variant, Variant> &entry : source) {
				if (count++ >= 20) {
					break;
				}
				result[ai_probe_value(entry.key, p_depth + 1)] = ai_probe_value(entry.value, p_depth + 1);
			}
			return result;
		}
		default:
			return p_value.stringify();
	}
}
static bool ai_identifier_start(char32_t p_char) {
	return (p_char >= 'A' && p_char <= 'Z') || (p_char >= 'a' && p_char <= 'z') || p_char == '_';
}
static bool ai_identifier_char(char32_t p_char) {
	return ai_identifier_start(p_char) || (p_char >= '0' && p_char <= '9');
}
static String ai_probe_code(const String &p_text) {
	String code;
	bool in_string = false;
	char32_t quote = 0;
	bool escape = false;
	for (int i = 0; i < p_text.length(); i++) {
		char32_t c = p_text[i];
		if (in_string) {
			if (escape) {
				escape = false;
			} else if (c == '\\') {
				escape = true;
			} else if (c == quote) {
				in_string = false;
			} else {
				code += ' ';
			}
			continue;
		}
		if (c == '"' || c == '\'') {
			in_string = true;
			quote = c;
			code += ' ';
			continue;
		}
		code += c;
	}
	return code;
}
static bool ai_mutating_call(const String &p_code) {
	static const char *mutators[] = {
		"set", "set_deferred", "set_owner", "set_script", "add_child", "remove_child", "reparent",
		"move_child", "add_sibling", "queue_free", "free", "emit_signal", "call", "callv",
		"call_deferred", "parse_input_event", "action_press", "action_release", "append",
		"append_array", "push_back", "push_front", "erase", "insert", "remove_at", "pop_back",
		"pop_front", "clear", "shuffle", "sort", "sort_custom", "resize", "fill", "store_var",
		"store_string", "store_buffer", "save", "write", "create_timer", "create_tween",
		"instantiate", "open", "request", "connect", "disconnect", "grab_focus", "release_focus",
		"show", "hide", "randomize", "seed"
	};
	int i = 0;
	while (i < p_code.length()) {
		if (!ai_identifier_start(p_code[i])) {
			i++;
			continue;
		}
		int start = i;
		while (i + 1 < p_code.length() && ai_identifier_char(p_code[i + 1])) {
			i++;
		}
		String name = p_code.substr(start, i - start + 1);
		int next = i + 1;
		while (next < p_code.length() && (p_code[next] == ' ' || p_code[next] == '\t')) {
			next++;
		}
		if (next < p_code.length() && p_code[next] == '(') {
			for (const char *mutator : mutators) {
				if (name == mutator) {
					return true;
				}
			}
		}
		i = next;
	}
	return false;
}
static bool ai_mutating_probe(const String &p_text) {
	String code = ai_probe_code(p_text);
	for (int i = 0; i < code.length(); i++) {
		if (code[i] != '=') {
			continue;
		}
		char32_t previous = i > 0 ? code[i - 1] : 0;
		char32_t next = i + 1 < code.length() ? code[i + 1] : 0;
		if (previous == '=' || previous == '!' || previous == '<' || previous == '>' || previous == '+' ||
				previous == '-' || previous == '*' || previous == '/' || previous == '%' || next == '=') {
			continue;
		}
		return true;
	}
	for (int i = 0; i < code.length(); i++) {
		if (!ai_identifier_start(code[i])) {
			continue;
		}
		int start = i;
		while (i + 1 < code.length() && ai_identifier_char(code[i + 1])) {
			i++;
		}
		if (code.substr(start, i - start + 1) == "await") {
			return true;
		}
	}
	return ai_mutating_call(code);
}
static Vector<String> ai_probe_identifiers(const String &p_text) {
	Vector<String> names;
	bool in_string = false;
	char32_t quote = 0;
	bool escape = false;
	for (int i = 0; i < p_text.length(); i++) {
		char32_t c = p_text[i];
		if (in_string) {
			if (escape) {
				escape = false;
			} else if (c == '\\') {
				escape = true;
			} else if (c == quote) {
				in_string = false;
			}
			continue;
		}
		if (c == '"' || c == '\'') {
			in_string = true;
			quote = c;
			continue;
		}
		if (!ai_identifier_start(c)) {
			continue;
		}
		int start = i;
		while (i + 1 < p_text.length() && ai_identifier_char(p_text[i + 1])) {
			i++;
		}
		if (start > 0 && p_text[start - 1] == '.') {
			continue;
		}
		int next = i + 1;
		while (next < p_text.length() && (p_text[next] == ' ' || p_text[next] == '\t')) {
			next++;
		}
		if (next < p_text.length() && p_text[next] == '(') {
			continue;
		}
		String name = p_text.substr(start, i - start + 1);
		static const char *keywords[] = { "null", "true", "false", "self", "PI", "TAU", "INF", "NAN",
			"and", "or", "not", "in", "await", "if", "else", "for", "while", "match", "return",
			"var", "const", "func", "class", "extends", "signal", "enum", "static" };
		bool skip = false;
		for (const char *keyword : keywords) {
			if (name == keyword) {
				skip = true;
				break;
			}
		}
		if (!skip && Variant::get_type_by_name(name) < Variant::VARIANT_MAX) {
			skip = true;
		}
		if (!skip && Variant::has_utility_function(name)) {
			skip = true;
		}
		if (skip || names.has(name)) {
			continue;
		}
		names.push_back(name);
	}
	return names;
}
static Object *ai_singleton(const String &p_name, bool &r_found) {
	r_found = true;
	if (p_name == "Engine") {
		return CoreBind::Engine::get_singleton();
	}
	if (p_name == "Input") {
		return Input::get_singleton();
	}
	if (p_name == "OS") {
		return CoreBind::OS::get_singleton();
	}
	if (p_name == "Time") {
		return Time::get_singleton();
	}
	if (p_name == "ProjectSettings") {
		return ProjectSettings::get_singleton();
	}
	r_found = false;
	return nullptr;
}
static Ref<InputEvent> ai_event_from_args(const Dictionary &p_args, bool p_pressed) {
	SceneTree *tree = SceneTree::get_singleton();
	Window *viewport = tree ? tree->get_root() : nullptr;
	if (!viewport) {
		return Ref<InputEvent>();
	}
	String kind = p_args.get("kind", "");
	Vector2 position(CLAMP(double(p_args.get("x", 0.5)), 0.0, 1.0) * viewport->get_visible_rect().size.x,
			CLAMP(double(p_args.get("y", 0.5)), 0.0, 1.0) * viewport->get_visible_rect().size.y);
	if (kind == "action") {
		StringName action = p_args.get("action", "");
		if (!InputMap::get_singleton()->has_action(action)) {
			return Ref<InputEvent>();
		}
		Ref<InputEventAction> event;
		event.instantiate();
		event->set_action(action);
		event->set_pressed(p_pressed);
		event->set_strength(p_pressed ? 1.0 : 0.0);
		return event;
	}
	if (kind == "key") {
		Ref<InputEventKey> event;
		event.instantiate();
		event->set_physical_keycode(Key(int64_t(p_args.get("key", 0))));
		event->set_pressed(p_pressed);
		return event;
	}
	if (kind == "mouse") {
		Ref<InputEventMouseButton> event;
		event.instantiate();
		event->set_position(position);
		event->set_global_position(position);
		event->set_button_index(MouseButton(CLAMP(int(p_args.get("button", 1)), 1, 9)));
		event->set_pressed(p_pressed);
		return event;
	}
	if (kind == "touch") {
		Ref<InputEventScreenTouch> event;
		event.instantiate();
		event->set_index(0);
		event->set_position(position);
		event->set_pressed(p_pressed);
		return event;
	}
	return Ref<InputEvent>();
}
static String ai_event_signature(const Dictionary &p_args) {
	String kind = p_args.get("kind", "");
	if (kind == "action") {
		return "action:" + String(p_args.get("action", ""));
	}
	if (kind == "key") {
		return "key:" + itos(int64_t(p_args.get("key", 0)));
	}
	if (kind == "mouse") {
		return "mouse:" + itos(CLAMP(int(p_args.get("button", 1)), 1, 9));
	}
	if (kind == "touch") {
		return "touch:0";
	}
	return "";
}

void AIRuntimeInputGuard::hold(const Ref<InputEvent> &p_event) {
	pressed.append(p_event);
	expires = OS::get_singleton()->get_ticks_msec() + 2200;
	Input::get_singleton()->parse_input_event(p_event);
}
void AIRuntimeInputGuard::release() {
	for (int i = 0; i < pressed.size(); i++) {
		Ref<InputEvent> event = pressed[i];
		Ref<InputEvent> up = event->duplicate();
		up->set("pressed", false);
		Input::get_singleton()->parse_input_event(up);
	}
	pressed.clear();
}
void AIRuntimeInputGuard::_press_sustained(const Dictionary &p_input, String &r_signature) {
	r_signature = ai_event_signature(p_input);
	if (r_signature.is_empty()) {
		return;
	}
	for (int i = 0; i < sustained.size(); i++) {
		if (String(Dictionary(sustained[i])["signature"]) == r_signature) {
			return;
		}
	}
	Ref<InputEvent> event = ai_event_from_args(p_input, true);
	if (event.is_null()) {
		r_signature = "";
		return;
	}
	Input::get_singleton()->parse_input_event(event);
	Dictionary entry;
	entry["signature"] = r_signature;
	entry["event"] = event;
	sustained.append(entry);
}
void AIRuntimeInputGuard::_release_sustained(const String &p_signature) {
	if (p_signature.is_empty()) {
		return;
	}
	for (int i = 0; i < sustained.size(); i++) {
		Dictionary entry = sustained[i];
		if (String(entry["signature"]) != p_signature) {
			continue;
		}
		Ref<InputEvent> event = entry["event"];
		if (event.is_valid()) {
			Ref<InputEvent> up = event->duplicate();
			up->set("pressed", false);
			Input::get_singleton()->parse_input_event(up);
		}
		sustained.remove_at(i);
		return;
	}
}
void AIRuntimeInputGuard::_release_all_sustained() {
	for (int i = 0; i < sustained.size(); i++) {
		Ref<InputEvent> event = Dictionary(sustained[i])["event"];
		if (event.is_valid()) {
			Ref<InputEvent> up = event->duplicate();
			up->set("pressed", false);
			Input::get_singleton()->parse_input_event(up);
		}
	}
	sustained.clear();
}
void AIRuntimeInputGuard::release_all(bool p_cancel_act) {
	if (act_active) {
		if (p_cancel_act && EngineDebugger::is_active()) {
			act_args["__cancelled"] = true;
			_finish_act();
		} else {
			act_active = false;
			act_args = Dictionary();
			servo_state = Dictionary();
			act_release.clear();
		}
	}
	release();
	_release_all_sustained();
}
Variant AIRuntimeInputGuard::_evaluate(const String &p_expression, String &r_error) {
	SceneTree *tree = SceneTree::get_singleton();
	Node *scene = tree ? tree->get_current_scene() : nullptr;
	if (!scene) {
		r_error = "No running scene.";
		return Variant();
	}
	if (p_expression.strip_edges().is_empty()) {
		r_error = "Probe expression is empty.";
		return Variant();
	}
	if (p_expression.length() > 400) {
		r_error = "Probe exceeds 400 characters.";
		return Variant();
	}
	if (ai_mutating_probe(p_expression)) {
		r_error = "Probe is read-only; assignments and mutating calls are rejected.";
		return Variant();
	}
	Vector<String> input_names;
	Array input_values;
	input_names.push_back("scene");
	input_values.push_back(scene);
	Vector<String> names = ai_probe_identifiers(p_expression);
	for (int i = 0; i < names.size(); i++) {
		const String &name = names[i];
		bool is_singleton = false;
		Object *singleton = ai_singleton(name, is_singleton);
		if (is_singleton) {
			if (singleton) {
				input_names.push_back(name);
				input_values.push_back(singleton);
			}
			continue;
		}
		Node *node = scene->get_node_or_null(NodePath(name));
		if (node) {
			input_names.push_back(name);
			input_values.push_back(node);
		}
	}
	Ref<Expression> expression;
	expression.instantiate();
	Error parse_error = expression->parse(p_expression, input_names);
	if (parse_error != OK) {
		r_error = expression->get_error_text();
		return Variant();
	}
	Variant value = expression->execute(input_values, scene, false, true);
	if (expression->has_execute_failed()) {
		r_error = expression->get_error_text();
		return Variant();
	}
	return value;
}
Dictionary AIRuntimeInputGuard::_evaluate_probes(const Array &p_expressions) {
	Dictionary values;
	for (int i = 0; i < p_expressions.size() && i < 12; i++) {
		String text = String(p_expressions[i]);
		String error;
		Variant value = _evaluate(text, error);
		if (error.is_empty()) {
			values[text] = ai_probe_value(value);
		} else {
			Dictionary failure;
			failure["error"] = error;
			values[text] = failure;
		}
	}
	return values;
}
Dictionary AIRuntimeInputGuard::evaluate_command(const Array &p_expressions) {
	if (p_expressions.is_empty() || p_expressions.size() > 12) {
		return ai_error("Provide 1 to 12 probe expressions.");
	}
	Dictionary values = _evaluate_probes(p_expressions);
	Dictionary state;
	state["values"] = values;
	_drain_watch(state);
	return ai_success(state);
}
Dictionary AIRuntimeInputGuard::watch_command(const Dictionary &p_args) {
	Array expressions = p_args.get("expressions", Array());
	Array signals = p_args.get("signals", Array());
	if (expressions.size() > 4 || signals.size() > 8) {
		return ai_error("At most 4 expressions and 8 signals can be watched.");
	}
	SceneTree *tree = SceneTree::get_singleton();
	Node *scene = tree ? tree->get_current_scene() : nullptr;
	if (!scene) {
		return ai_error("No running scene.");
	}
	Array valid_expressions;
	for (int i = 0; i < expressions.size(); i++) {
		String text = String(expressions[i]);
		String error;
		_evaluate(text, error);
		if (!error.is_empty()) {
			return ai_error("Watch probe rejected: " + error);
		}
		valid_expressions.append(text);
	}
	Array valid_signals;
	for (int i = 0; i < signals.size(); i++) {
		Dictionary spec = signals[i];
		String path = String(spec.get("path", "."));
		String name = String(spec.get("name", ""));
		Node *target = path == "." ? scene : scene->get_node_or_null(NodePath(path));
		if (!target) {
			return ai_error("Signal target does not exist: " + path);
		}
		if (name.is_empty() || !target->has_signal(name)) {
			return ai_error("Unknown signal " + name + " on " + path + ".");
		}
		Dictionary entry;
		entry["path"] = path;
		entry["name"] = name;
		valid_signals.append(entry);
	}
	_disconnect_watches();
	watch_expressions = valid_expressions;
	watch_signals = valid_signals;
	signal_events.clear();
	_connect_watches();
	Dictionary state;
	state["expressions"] = watch_expressions;
	state["signals"] = watch_signals;
	return ai_success(state);
}
void AIRuntimeInputGuard::_connect_watches() {
	SceneTree *tree = SceneTree::get_singleton();
	Node *scene = tree ? tree->get_current_scene() : nullptr;
	if (!scene) {
		return;
	}
	watch_connections.clear();
	for (int i = 0; i < watch_signals.size(); i++) {
		Dictionary spec = watch_signals[i];
		String path = String(spec.get("path", "."));
		StringName name = String(spec.get("name", ""));
		Node *target = path == "." ? scene : scene->get_node_or_null(NodePath(path));
		if (!target || !target->has_signal(name)) {
			continue;
		}
		Callable callback = Callable(this, SNAME("_watch_signal")).bind(path, name);
		target->connect(name, callback);
		Dictionary entry;
		entry["object"] = target->get_instance_id();
		entry["signal"] = name;
		entry["callback"] = callback;
		watch_connections.append(entry);
	}
}
void AIRuntimeInputGuard::_disconnect_watches() {
	for (int i = 0; i < watch_connections.size(); i++) {
		Dictionary entry = watch_connections[i];
		Object *target = ObjectDB::get_instance(ObjectID(uint64_t(entry["object"])));
		if (target) {
			target->disconnect(StringName(entry["signal"]), Callable(entry["callback"]));
		}
	}
	watch_connections.clear();
}
void AIRuntimeInputGuard::_drain_watch(Dictionary &r_state) {
	if (!watch_expressions.is_empty()) {
		Dictionary watched = _evaluate_probes(watch_expressions);
		r_state["watched"] = watched;
	}
	if (!signal_events.is_empty()) {
		r_state["events"] = signal_events.duplicate(true);
		signal_events.clear();
	}
}
Variant AIRuntimeInputGuard::_watch_signal(const Variant **p_args, int p_argcount, Callable::CallError &r_error) {
	r_error.error = Callable::CallError::CALL_OK;
	if (p_argcount < 2) {
		return Variant();
	}
	// Bound arguments are appended after the signal's own arguments.
	Dictionary event;
	event["path"] = String(*p_args[p_argcount - 2]);
	event["signal"] = String(*p_args[p_argcount - 1]);
	event["frame"] = int64_t(Engine::get_singleton()->get_process_frames());
	Array arguments;
	for (int i = 0; i < p_argcount - 2 && i < 8; i++) {
		arguments.append(ai_probe_value(*p_args[i]));
	}
	event["args"] = arguments;
	if (signal_events.size() >= 32) {
		signal_events.remove_at(0);
	}
	signal_events.append(event);
	return Variant();
}
void AIRuntimeInputGuard::start_act(int64_t p_id, const Dictionary &p_args) {
	if (act_active) {
		ai_send_reply(p_id, ai_error("An act is already running."));
		return;
	}
	SceneTree *tree = SceneTree::get_singleton();
	Node *scene = tree ? tree->get_current_scene() : nullptr;
	if (!scene) {
		ai_send_reply(p_id, ai_error("No running scene."));
		return;
	}
	act_active = true;
	act_id = p_id;
	act_args = p_args.duplicate(true);
	act_release.clear();
	act_phase = 0;
	act_frame = 0;
	servo_index = 0;
	act_deadline = OS::get_singleton()->get_ticks_msec() + 75000;
	servo_state = Dictionary();
	act_args["__before"] = _evaluate_probes(p_args.get("probes", Array()));
	act_args["__servo_results"] = Array();
	Array inputs = p_args.get("inputs", Array());
	for (int i = 0; i < inputs.size() && i < 8; i++) {
		Dictionary input = inputs[i];
		if (bool(input.get("release", false))) {
			_release_sustained(ai_event_signature(input));
			continue;
		}
		String signature;
		_press_sustained(input, signature);
		if (!signature.is_empty() && !bool(input.get("sustain", false))) {
			act_release.append(signature);
		}
	}
	Array servo = p_args.get("servo", Array());
	if (servo.is_empty()) {
		act_phase = 1;
	}
	set_process(true);
}
void AIRuntimeInputGuard::_process_act() {
	if (!act_active) {
		return;
	}
	if (OS::get_singleton()->get_ticks_msec() >= act_deadline) {
		act_args["__expired"] = true;
		act_args["__timed_out"] = true;
		_finish_act();
		return;
	}
	Array servo = act_args.get("servo", Array());
	if (act_phase == 0) {
		if (servo_index >= servo.size()) {
			act_phase = 1;
			act_frame = 0;
			servo_state = Dictionary();
			return;
		}
		Dictionary item = servo[servo_index];
		String error;
		Variant value = _evaluate(String(item.get("probe", "")), error);
		if (!error.is_empty()) {
			_finish_act("Servo probe failed: " + error);
			return;
		}
		if (value.get_type() != Variant::INT && value.get_type() != Variant::FLOAT) {
			_finish_act("Servo probe must return a number.");
			return;
		}
		double numeric = value;
		double target = double(item.get("target", 0.0));
		double tolerance = MAX(0.0, double(item.get("tolerance", 0.01)));
		double wrap = MAX(0.0, double(item.get("wrap", 0.0)));
		double difference = numeric - target;
		if (wrap > 0.0) {
			difference = Math::fposmod(difference + wrap * 0.5, wrap) - wrap * 0.5;
		}
		int frames = int(servo_state.get("frames", 0)) + 1;
		servo_state["frames"] = frames;
		int max_frames = CLAMP(int(item.get("max_frames", 300)), 1, 900);
		bool reached = Math::abs(difference) <= tolerance;
		if (reached || frames >= max_frames) {
			_release_sustained(String(servo_state.get("increase_sig", "")));
			_release_sustained(String(servo_state.get("decrease_sig", "")));
			Dictionary record;
			record["probe"] = String(item.get("probe", ""));
			record["value"] = ai_probe_value(value);
			record["target"] = target;
			record["error"] = Math::abs(difference);
			record["reached"] = reached;
			record["frames"] = frames;
			Array results = act_args.get("__servo_results", Array());
			results.append(record);
			act_args["__servo_results"] = results;
			servo_index++;
			servo_state = Dictionary();
			return;
		}
		String direction = (wrap > 0.0 ? difference < 0.0 : numeric < target) ? "increase" : "decrease";
		String current = String(servo_state.get("direction", ""));
		if (current != direction) {
			if (!current.is_empty()) {
				_release_sustained(String(servo_state.get(current + "_sig", "")));
			}
			String signature;
			_press_sustained(item.get(direction, Dictionary()), signature);
			servo_state[direction + "_sig"] = signature;
			servo_state["direction"] = direction;
		}
		return;
	}
	Dictionary until = act_args.get("until", Dictionary());
	if (!until.is_empty()) {
		String error;
		Variant value = _evaluate(String(until.get("expression", "")), error);
		if (!error.is_empty()) {
			_finish_act("Until expression failed: " + error);
			return;
		}
		int limit = CLAMP(int(until.get("timeout_frames", 600)), 1, 1800);
		act_frame++;
		if (value.booleanize()) {
			_finish_act();
			return;
		}
		if (act_frame >= limit) {
			act_args["__timed_out"] = true;
			_finish_act();
			return;
		}
		return;
	}
	int advance = CLAMP(int(act_args.get("advance_frames", 30)), 1, 1200);
	act_frame++;
	if (act_frame >= advance) {
		_finish_act();
	}
}
void AIRuntimeInputGuard::_finish_act(const String &p_error) {
	if (!act_active) {
		return;
	}
	int64_t id = act_id;
	act_active = false;
	if (!p_error.is_empty()) {
		_release_sustained(String(servo_state.get("increase_sig", "")));
		_release_sustained(String(servo_state.get("decrease_sig", "")));
		for (int i = 0; i < act_release.size(); i++) {
			_release_sustained(String(act_release[i]));
		}
		act_release.clear();
		servo_state = Dictionary();
		act_args = Dictionary();
		ai_send_reply(id, ai_error(p_error));
		return;
	}
	bool cancelled = bool(act_args.get("__cancelled", false));
	bool timed_out = bool(act_args.get("__timed_out", false));
	Dictionary state;
	state["before"] = act_args.get("__before", Dictionary());
	state["after"] = _evaluate_probes(act_args.get("probes", Array()));
	state["frames"] = act_frame;
	Dictionary until = act_args.get("until", Dictionary());
	if (!until.is_empty()) {
		state["until_met"] = !timed_out && !cancelled;
	}
	state["timed_out"] = timed_out;
	state["cancelled"] = cancelled;
	state["servo"] = act_args.get("__servo_results", Array());
	state["expired"] = bool(act_args.get("__expired", false));
	_release_sustained(String(servo_state.get("increase_sig", "")));
	_release_sustained(String(servo_state.get("decrease_sig", "")));
	for (int i = 0; i < act_release.size(); i++) {
		_release_sustained(String(act_release[i]));
	}
	act_release.clear();
	servo_state = Dictionary();
	Array held;
	for (int i = 0; i < sustained.size(); i++) {
		held.append(String(Dictionary(sustained[i])["signature"]));
	}
	state["held"] = held;
	_drain_watch(state);
	act_args = Dictionary();
	if (cancelled) {
		Dictionary reply = ai_error("Act cancelled by Stop.");
		reply["code"] = "cancelled";
		reply["result"] = state;
		ai_send_reply(id, reply);
		return;
	}
	ai_send_reply(id, ai_success(state));
}
Dictionary AIRuntimeInputGuard::status_command() {
	SceneTree *tree = SceneTree::get_singleton();
	Node *scene = tree ? tree->get_current_scene() : nullptr;
	Dictionary state;
	state["running"] = scene != nullptr;
	state["scene"] = scene ? scene->get_scene_file_path() : String();
	state["project_root"] = ProjectSettings::get_singleton()->get_resource_path();
	Array actions;
	const HashMap<StringName, InputMap::Action> &map = InputMap::get_singleton()->get_action_map();
	for (const KeyValue<StringName, InputMap::Action> &entry : map) {
		actions.append(String(entry.key));
	}
	state["actions"] = actions;
	{
		MutexLock lock(error_mutex);
		state["errors"] = runtime_errors;
		state["diagnostics"] = runtime_diagnostics.duplicate(true);
		state["diagnostics_truncated"] = runtime_diagnostic_sequence > runtime_diagnostics.size();
	}
	Array held;
	for (int i = 0; i < sustained.size(); i++) {
		held.append(String(Dictionary(sustained[i])["signature"]));
	}
	state["held"] = held;
	Dictionary watching;
	watching["expressions"] = watch_expressions.size();
	watching["signals"] = watch_signals.size();
	watching["pending_events"] = signal_events.size();
	state["watching"] = watching;
	return ai_success(state);
}
Dictionary AIRuntimeInputGuard::performance_command(const Dictionary &p_args) {
	String action = p_args.get("action", "read");
	if (action == "reset") {
		performance_frames.clear();
		performance_recording = true;
		performance_last_usec = OS::get_singleton()->get_ticks_usec();
		performance_started_usec = performance_last_usec;
	} else if (action == "stop") {
		performance_recording = false;
	} else if (action != "read") {
		return ai_error("Performance action must be reset, read or stop.");
	}
	Dictionary state;
	SceneTree *tree = SceneTree::get_singleton();
	Node *scene = tree ? tree->get_current_scene() : nullptr;
	state["scene"] = scene ? scene->get_scene_file_path() : String();
	state["source"] = "running_game_native";
	Array viewport;
	if (tree && tree->get_root()) {
		viewport.append(tree->get_root()->get_size().x);
		viewport.append(tree->get_root()->get_size().y);
	}
	state["viewport"] = viewport;
	state["samples"] = performance_frames.size();
	state["recording"] = performance_recording;
	state["sample_limit"] = 2048;
	state["window_usec"] = performance_started_usec ? OS::get_singleton()->get_ticks_usec() - performance_started_usec : 0;
	if (!performance_frames.is_empty()) {
		Vector<double> sorted = performance_frames;
		sorted.sort();
		double sum = 0;
		for (double frame : performance_frames) {
			sum += frame;
		}
		state["average_frame_ms"] = sum / sorted.size();
		state["p95_frame_ms"] = sorted[CLAMP(int(Math::ceil(sorted.size() * 0.95)) - 1, 0, sorted.size() - 1)];
		state["max_frame_ms"] = sorted[sorted.size() - 1];
	}
	Performance *monitor = Performance::get_singleton();
	if (monitor) {
		state["fps"] = monitor->get_monitor(Performance::TIME_FPS);
		state["process_ms"] = monitor->get_monitor(Performance::TIME_PROCESS) * 1000.0;
		state["physics_ms"] = monitor->get_monitor(Performance::TIME_PHYSICS_PROCESS) * 1000.0;
		state["engine_static_memory_bytes"] = monitor->get_monitor(Performance::MEMORY_STATIC);
		state["draw_calls"] = monitor->get_monitor(Performance::RENDER_TOTAL_DRAW_CALLS_IN_FRAME);
		state["primitives"] = monitor->get_monitor(Performance::RENDER_TOTAL_PRIMITIVES_IN_FRAME);
		state["nodes"] = monitor->get_monitor(Performance::OBJECT_NODE_COUNT);
	}
	state["scope"] = "Native game frame intervals and engine monitors; not OS total RAM, GPU timing or a hardware-independent benchmark.";
	return ai_success(state);
}
void AIRuntimeInputGuard::_bind_methods() {
	ClassDB::bind_vararg_method(METHOD_FLAGS_DEFAULT, "_watch_signal", &AIRuntimeInputGuard::_watch_signal, MethodInfo("_watch_signal"));
}
void AIRuntimeInputGuard::_notification(int p_what) {
	if (p_what == NOTIFICATION_PROCESS) {
		if (performance_recording) {
			uint64_t now = OS::get_singleton()->get_ticks_usec();
			if (!EngineDebugger::is_active() || performance_frames.size() >= 2048 || now - performance_started_usec > 60000000) {
				performance_recording = false;
			} else if (performance_last_usec && now > performance_last_usec) {
				performance_frames.push_back(double(now - performance_last_usec) / 1000.0);
			}
			performance_last_usec = now;
		}
		if (!pressed.is_empty() && (!EngineDebugger::is_active() || OS::get_singleton()->get_ticks_msec() >= expires)) {
			release();
		}
		if (!EngineDebugger::is_active()) {
			if (!sustained.is_empty()) {
				_release_all_sustained();
			}
			if (act_active) {
				act_active = false;
				act_args = Dictionary();
				servo_state = Dictionary();
				act_release.clear();
			}
		} else if (act_active) {
			_process_act();
		}
	}
	if (p_what == NOTIFICATION_EXIT_TREE) {
		release_all(false);
	}
}

static ObjectID input_guard_id;
static ErrorHandlerList runtime_error_handler;
static void ai_log_error(void *, const char *p_function, const char *p_file, int p_line, const char *p_error, const char *p_description, bool, ErrorHandlerType p_type) {
	if (!Engine::get_singleton() || Engine::get_singleton()->is_editor_hint()) {
		return;
	}
	MutexLock lock(error_mutex);
	Dictionary event;
	event["sequence"] = ++runtime_diagnostic_sequence;
	event["path"] = String::utf8(p_file);
	event["line"] = p_line;
	event["function"] = String::utf8(p_function);
	event["severity"] = p_type == ERR_HANDLER_WARNING ? "warning" : "error";
	event["category"] = p_type == ERR_HANDLER_SHADER ? "shader" : (p_type == ERR_HANDLER_SCRIPT ? "script" : "runtime");
	event["message"] = (String::utf8(p_error) + " " + String::utf8(p_description)).strip_edges().left(1200);
	if (runtime_diagnostics.size() >= 128) {
		runtime_diagnostics.pop_front();
	}
	runtime_diagnostics.append(event);
	if (p_type == ERR_HANDLER_WARNING) {
		return;
	}
	if (runtime_errors.size() >= 32) {
		runtime_errors.remove_at(0);
	}
	runtime_errors.append((String::utf8(p_file) + ":" + itos(p_line) + " " + String::utf8(p_error) + " " + String::utf8(p_description)).left(1200));
}
static Error ai_capture(void *p_user, const String &p_message, const Array &p_args, bool &r_captured) {
	r_captured = true;
	if (p_message != "request" || p_args.size() != 3 || Engine::get_singleton()->is_editor_hint()) {
		return ERR_INVALID_DATA;
	}
	SceneTree *tree = SceneTree::get_singleton();
	if (!tree || !tree->get_root()) {
		return ERR_UNCONFIGURED;
	}
	Window *viewport = tree->get_root();
	String command = p_args[1];
	Dictionary args = p_args[2];
	AIRuntimeInputGuard *guard = Object::cast_to<AIRuntimeInputGuard>(ObjectDB::get_instance(input_guard_id));
	if (!guard) {
		guard = memnew(AIRuntimeInputGuard);
		guard->set_name("__GodotAIInputGuard");
		guard->set_process_mode(Node::PROCESS_MODE_ALWAYS);
		viewport->add_child(guard);
		guard->set_process(true);
		input_guard_id = guard->get_instance_id();
	}
	if (command == "act") {
		guard->start_act(int64_t(p_args[0]), args);
		return OK;
	}
	Dictionary response;
	if (command == "release") {
		guard->release_all();
		response = ai_success(true);
	} else if (command == "status") {
		response = guard->status_command();
	} else if (command == "performance") {
		response = guard->performance_command(args);
	} else if (command == "eval") {
		response = guard->evaluate_command(args.get("expressions", Array()));
	} else if (command == "watch") {
		response = guard->watch_command(args);
	} else if (command == "inspect") {
		Node *root = tree->get_current_scene();
		String path = args.get("path", ".");
		Node *target = root ? root->get_node_or_null(NodePath(path)) : nullptr;
		if (!target || (target != root && !root->is_ancestor_of(target))) {
			response = ai_error("Runtime node does not exist in the current scene.");
		} else {
			Dictionary state;
			state["class"] = target->get_class();
			Array children;
			for (int i = 0; i < target->get_child_count() && i < 200; i++) {
				children.append(String(target->get_child(i)->get_name()));
			}
			state["children"] = children;
			Dictionary properties;
			Array requested = args.get("properties", Array());
			for (int i = 0; i < requested.size() && i < 40; i++) {
				String key = requested[i];
				if (key.begins_with("_") || key.contains("password") || key.contains("token") || key.contains("secret")) {
					continue;
				}
				bool valid = false;
				Variant value = target->get(key, &valid);
				if (valid) {
					properties[key] = ai_runtime_value(value);
				}
			}
			state["properties"] = properties;
			response = ai_success(state);
		}
	} else if (command == "screenshot") {
		Ref<ViewportTexture> texture = viewport->get_texture();
		Ref<Image> image = texture.is_valid() ? texture->get_image() : Ref<Image>();
		if (image.is_null() || image->is_empty()) {
			response = ai_error("The running game has no rendered viewport.");
		} else {
			image->convert(Image::FORMAT_RGBA8);
			while (image->get_width() > 1536 || image->get_height() > 1536) {
				image->resize(MAX(1, image->get_width() / 2), MAX(1, image->get_height() / 2));
			}
			Vector<uint8_t> bytes = image->save_png_to_buffer();
			while (bytes.size() > 2 * 1024 * 1024 && image->get_width() > 256) {
				image->resize(MAX(1, image->get_width() / 2), MAX(1, image->get_height() / 2));
				bytes = image->save_png_to_buffer();
			}
			Dictionary frame;
			frame["width"] = image->get_width();
			frame["height"] = image->get_height();
			frame["data"] = CryptoCore::b64_encode_str(bytes.ptr(), bytes.size());
			response = bytes.size() <= 2 * 1024 * 1024 ? ai_success(frame) : ai_error("Frame exceeds the screenshot limit.");
		}
	} else if (command == "input") {
		Ref<InputEvent> event = ai_event_from_args(args, true);
		if (event.is_null()) {
			response = ai_error("Unknown input kind or InputMap action.");
		} else {
			guard->hold(event);
			response = ai_success(true);
		}
	} else {
		response = ai_error("Unsupported playtest operation.");
	}
	ai_send_reply(int64_t(p_args[0]), response);
	return OK;
}
void initialize_ai_runtime_capture() {
	runtime_error_handler.errfunc = ai_log_error;
	add_error_handler(&runtime_error_handler);
	if (!EngineDebugger::has_capture("ai_assistant")) {
		EngineDebugger::register_message_capture("ai_assistant", EngineDebugger::Capture(nullptr, ai_capture));
	}
}
void uninitialize_ai_runtime_capture() {
	remove_error_handler(&runtime_error_handler);
	if (EngineDebugger::has_capture("ai_assistant")) {
		EngineDebugger::unregister_message_capture("ai_assistant");
	}
}
