# Suita completă Godot AI — inventar și plan pe etape

Ultima actualizare: **3 noiembrie 2026**.

Obiectivul este o suită locală, controlată de Agent AI prin harness-ul nativ, în
care Blender CLI, generatoarele de imagini/3D, Godot, Ziva, verificarea și
livrarea fac parte din aceeași aplicație. Pachetele necesare trebuie livrate în
APK, nu descărcate la fiecare utilizare.

Legendă: **D** = disponibil în surse, **T** = acoperit de teste/CI existente,
**P** = parțial, **L** = lipsește, **N** = următorul pas.

## 1. Inventarul uneltelor existente

### 1.1. Proiect, cod și schimbări

- `godot_project`, `godot_files`, `godot_scene_tree`
- `godot_read_file`, `godot_read_range`, `godot_search_code`, `godot_symbols`
- `godot_write_file`, `godot_apply_patch`, `godot_delete_file`,
  `godot_restore_file`
- `godot_script_diagnostics`
- `godot_changes_prepare`, `godot_changes_status`, `godot_changes_apply`,
  `godot_changes_rollback`
- `godot_impact`
- `file_catalog`, `file_show`, `file_observe`, `file_preview`,
  `storage_search`

### 1.2. Godot scene, resurse și editor

- `godot_create_scene`, `godot_open_scene`, `godot_save_scene`
- `godot_create_node`, `godot_remove_node`, `godot_attach_script`,
  `godot_connect_signal`
- `godot_load_resource`, `godot_create_resource`, `godot_save_resource`
- `godot_get`, `godot_set`, `godot_call`, `godot_describe`
- `godot_undo`, `godot_redo`, `godot_animation`
- `godot_settings`, `godot_set_setting`
- `godot_ui_tree`, `godot_ui_action`
- `godot_panels`, `godot_panel_read`, `godot_panel_data`
- `editor_capture`, `editor_input`

Accesul generic `godot_describe` + `godot_call` este expus acum și prin MCP, ca
agentul să poată inspecta și apela orice proprietate, semnal sau metodă
reflectată, nu doar uneltele cu nume fix.

### 1.3. Rulare, testare și diagnosticare

- `godot_run`, `godot_stop`, `godot_run_state`
- `godot_output`, `godot_debugger`, `godot_diagnostics`,
  `godot_project_map`
- `playtest_act`, `playtest_input`, `playtest_observe`, `playtest_state`,
  `playtest_watch`
- `qa_list`, `qa_save`, `qa_run`, `qa_report`
- `experiment_create`, `experiment_read`, `experiment_write`,
  `experiment_compare`, `experiment_stage`
- `profile_run`, `profile_compare`
- `task_recovery`, `task_reconcile`
- `repair_start`, `repair_check`

### 1.4. Generare de imagini și 3D

- `asset_generate`, `asset_status`, `asset_wait`
- `asset_import`, `asset_export`, `asset_remove_background`
- `asset_audit`, `asset_prepare`
- Furnizori/protocoale: Runware, ComfyUI local, Meshy, Tripo, OpenAI Images.
- Tipuri de imagine: generic, referință 3D, sprite, textură, fundal; suport
  pentru transparență și referință.

### 1.5. Store, pluginuri și integrări

- `store_search`, `store_describe`, `store_install`, `store_remove`
- `plugin_enable`
- `github_read`, `github_create_issue`
- `linux_status`, `linux_execute`, `linux_install_tool`

### 1.6. Agent, planificare și memorie

- `tool_search`, `tool_describe`
- `task_update`, `task_check`, `plan_ask`
- `agent_spawn`, `agent_wait`, `agent_cancel`, `agent_profiles`,
  `agent_profile_save`
- `memory_write`, `memory_search`, `memory_remember`, `memory_forget`
- `skill_list`, `skill_read`, `skill_save`
- `engineering_status`

### 1.7. Ziva

Existente anterior:

- `ziva_task`, `ziva_task_poll`, `ziva_task_result`

Adăugate în surse pentru control complet:

- `ziva_status`, `ziva_start`, `ziva_stop`, `ziva_restart`
- `ziva_install`, `ziva_update`
- `ziva_task_cancel`
- `ziva_permission_reply` (`once`, `always`, `reject`)
- `ziva_question_reply`, `ziva_question_reject`

Acestea folosesc RPC-ul oficial `permissions/reply`, `questions/reply` și
`questions/reject`; aprobarea rămâne o acțiune externă a Agent AI, supusă
regulilor de aprobare ale aplicației. Testarea pe APK și pe Ziva live este
încă necesară.

### 1.8. Blender

Existente:

- `blender_status` — backend-ul `app-linux`, versiunea reală, starea pachetelor
  Debian și absența dependenței de Termux;
- `blender_prepare` — pregătește pachetele Blender din repository-ul offline
  semnat în APK, cu job anulabil și fără descărcare;
- `blender_run` — script Python din proiect, cu `/workspace` montat, API complet
  Blender și fișiere de ieșire limitate la proiect; poate genera GLB/FBX/OBJ/BLEND
  și randări;
- pe desktop și pe APK-urile vechi rămâne conectorul Termux/desktop existent.

Lipsește:

- `blender_cli` pentru argumente arbitrare, dacă va fi necesar peste `blender_run`;
- `blender_render`, `blender_inspect`, `blender_export`, `blender_bake`,
  `blender_validate` ca unelte dedicate peste același backend;
- profiluri de scene, unități, color management, render engine și GPU/CPU;
- pipeline direct imagine → Blender → Godot, fără transfer prin Termux.

## 2. Ce înseamnă „toate capacitățile Godot”

Suita trebuie să acopere, prin unelte dedicate sau reflecție:

- proiect, fișiere, script, scene, noduri, resurse, import, semnale și Undo;
- animații, materiale, shadere, texturi, lumină, camere, fizică, audio,
  particule, navigație, tilemap, terrain și UI;
- debugger, Output, profiler, monitoare, memorie video, thread-uri, variabile,
  breakpoint-uri, stack și capturi;
- testare reproductibilă, experimente, acceptanță și performanță;
- export/import și pipeline de build Godot.

Uneltele generice sunt ultima linie de acces, nu înlocuiesc uneltele dedicate
pentru operații sigure și reversibile. Orice modificare generică rămâne supusă
aprobării și verificării reale.

## 3. Planul de construcție pe etape

### Etapa 0 — identitate și control total (în surse)

Status: **D/P**.

- Agent AI nu se prezintă drept harness-ul care îl execută.
- Promptul de sistem propriu înlocuiește identitatea implicită a runtime-ului.
- Godot reflection (`godot_describe`, `godot_call`) este expus prin MCP.
- Ziva primește control de ciclu de viață, conversație, permisiuni și întrebări.
- Rebuild APK și probă pe dispozitiv: **încă necesare**.

### Etapa 1 — Blender CLI în APK, nativ aplicației

Status: **D/T — implementat, testat local și verificat pe telefon prin PRoot-ul APK-ului**.

- `blender` 4.3.2+dfsg-2 este în lista Debian a repository-ului offline din APK.
  Buildul local selectează 377 de pachete; `debian-offline.zip` are
  291.488.170 bytes, iar instalarea adaugă ~800 MB. Amprenta APK finală se
  verifică în CI.
- Blender 4.3.2 din Debian trixie este candidatul reproductibil; alternativa
  este un build oficial ARM64 dacă aparține versiunii pe care o fixăm.
- Funcția principală nu mai consultă Termux. Conectorul vechi rămâne fallback
  numai pentru APK-uri fără backend-ul Linux.
- `blender_run` rulează prin Linux runtime-ul aplicației, cu proiectul montat
  direct la `/workspace`; scriptul, `.blend` și ieșirile sunt limitate la proiect.
- `blender_status`, `blender_prepare` și `blender_run` sunt expuse Agent AI prin
  MCP. `blender_run` oferă API-ul Python complet; uneltele specializate
  `blender_render`, `blender_inspect`, `blender_export`, `blender_bake` și
  `blender_validate` rămân pasul următor peste același backend.
- Acceptare: Blender pornește offline, versiunea este reală, un script minim
  creează un GLB importabil, o randare produce o imagine, iar uneltele Pi pot
  executa fluxul fără Termux. Primele patru condiții au trecut local, iar
  APK-urile standard/Ziva au trecut build-ul și verificarea conținutului, iar
  randarea/GLB/importul au trecut pe telefon. Controlul prin chat-ul Agent AI
  rămâne de validat separat.

### Etapa 2 — pipeline unificat de asseturi

Status: **N**.

- Catalog comun pentru imagini, mesh-uri, materiale, texturi, animații și
  surse Blender, cu hash, proveniență, licență și stare de import.
- Lanț: prompt → imagine/referință → generator 3D sau Blender → curățare/retopo
  → materiale/PBR → LOD/collision → import Godot → audit.
- Operații: variante, upscale, tileable texture, normal/roughness/metalness,
  sprite sheet, background removal, multi-view, retopologie, UV, bake, rigging
  și animație.
- Acceptare: fiecare asset are sursă și hash, nu suprascrie originalul, iar
  uneltele `asset_audit` și `asset_prepare` verifică rezultatul în Godot.

### Etapa 3 — producție AAA

Status: **N**.

- Lume/terrain, streaming, cladiri, vegetație, materiale, iluminare, VFX,
  animație, rigging, audio, UI, localizare, salvare și input.
- Template-uri de proiect și pipeline-uri repetitive pentru niveluri,
  personaje, arme, obiecte și medii.
- Build/export Godot, profilare, bugete de performanță, QA replay și rapoarte
  de regresie.
- Acceptare: un nivel de test se construiește, rulează, se verifică și se
  exportă din aceleași unelte, cu dovezi runtime reale.

### Etapa 4 — Ziva complet integrată

Status: **P**.

- Model/provider selection și control complet al sesiunii; permisiunile și
  întrebările pot fi soluționate din Agent AI sau din tabul Ziva.
- Sincronizare de context și proiect între cei doi agenți fără a amesteca
  istoricul sau secretele.
- Acceptare: ciclu de viață, install/update, oprire, repornire, task, cancel,
  permission și question sunt probate live pe APK.

### Etapa 5 — QA, build și livrare continuă

Status: **D/P**.

- Extinde QA existent la scenarii AAA, capturi, input, replay, output,
  performanță și comparații între experimente.
- Build-uri Godot din aplicație, verificare de APK/export și livrare GitHub.

### Etapa 6 — curățarea Termux

Status: **N — numai după ce totul este app-native și verificat**.

- Inventar al fișierelor Termux: runtime-uri duplicate, Node/npm, cache-uri
  npm, proot-distro, Blender duplicat, descărcări vechi, loguri și temp.
- Șterge numai duplicatele și cache-urile dovedite inutile. Proiectele,
  capturile, documentele și datele utilizatorului rămân neatinse.
- Nu șterge Termux sau conectorul până când fiecare funcție migrată nu are o
  probă pe APK și nu mai depinde de el.
- Acceptare: raport înainte/după, spațiu eliberat, funcții re-verificate.

## 4. Ordinea practică imediată

1. Finalizează și compilează Etapa 0, apoi livrează un APK de test.
2. Adaugă Blender bundled și backend-ul direct, fără Termux.
3. Leagă Blender de `asset_generate` și de catalogul de asseturi.
4. Construiește pipeline-ul AAA și QA.
5. Abia după migrarea completă curăță Termux.

## 5. Reguli permanente

- Fiecare capabilitate are unealtă, schemă, aprobare, limită și dovadă reală.
- Un APK vechi nu dovedește cod nou; o simulare nu dovedește un furnizor live.
- Nu se șterg proiecte, credențiale, asseturi originale sau date de utilizator.
- Blender, Ziva și generatoarele primesc unelte proprii, dar Agent AI rămâne
  singurul orchestrator și singurul punct de aprobare.
- Pachetele offline se verifică prin hash; actualizarea nu depinde de rețea.
