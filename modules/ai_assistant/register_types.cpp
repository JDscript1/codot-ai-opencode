#include "register_types.h"

#include "ai_assistant_editor.h"

#include "core/object/class_db.h"

void initialize_ai_assistant_module(ModuleInitializationLevel p_level) {
	if (p_level == MODULE_INITIALIZATION_LEVEL_SCENE) {
		GDREGISTER_INTERNAL_CLASS(AIRuntimeInputGuard);
		initialize_ai_runtime_capture();
	}
	if (p_level == MODULE_INITIALIZATION_LEVEL_EDITOR) {
		GDREGISTER_INTERNAL_CLASS(AIAssistantDebugger);
		GDREGISTER_INTERNAL_CLASS(AIAssistantSecretStore);
		GDREGISTER_INTERNAL_CLASS(AIAssistantSettingsInspector);
		GDREGISTER_INTERNAL_CLASS(AIAssistantEditorPlugin);
		GDREGISTER_INTERNAL_CLASS(AIZivaPanel);
		GDREGISTER_INTERNAL_CLASS(AIZivaEditorPlugin);
		GDREGISTER_INTERNAL_CLASS(AIAssistantProjectManager);
	}
}

void uninitialize_ai_assistant_module(ModuleInitializationLevel p_level) {
	if (p_level == MODULE_INITIALIZATION_LEVEL_SCENE) {
		uninitialize_ai_runtime_capture();
	}
}
