# Agent AI pe Pi RPC

Stare: **implementat în surse, compilat în APK în CI; instalarea pe dispozitiv și proba live rămân separate.**

Agentul **Agent AI** folosește acum Pi ca harness propriu al aplicației. Nu există
tab Pi și nu este pornit un terminal: conversația, aprobările și cardurile de
unelte rămân în panoul AI Assistant. Ziva rămâne un tab separat și nu a fost
modificată de această migrare.

## Componență

| Zonă | Sursă | Rol |
|---|---|---|
| Runtime Android | `platform/android/java/editor/src/main/java/org/godotengine/editor/AIPiRuntime.kt` | Instalează Node.js și Pi în PRoot, scrie configurația privată, pornește RPC JSONL și transportă evenimentele către Godot. |
| Sesiune Godot | `modules/ai_assistant/runtime/pi_session.gd` | Materializează profilurile aplicației ca furnizori Pi, grupează modelele după protocol și expune `start`, `send`, `poll`, `abort`, `stop`. |
| Server MCP | `modules/ai_assistant/runtime/godot_mcp.gd` | Server loopback cu Bearer token care expune catalogul Godot ca unelte MCP native. Pi le descoperă cu `tool_search` și le apelează direct. |
| Panou | `modules/ai_assistant/runtime/panel.gd` | Pornește o singură sesiune Pi pe conversație, o refolosește cât timp ruta și modul rămân aceleași, randează streamingul, uneltele, întrebările și aprobările, apoi salvează rezultatele reale în istoric. |

Runtime-ul folosește versiunile fixate:

- Pi `1.5.0`, pachet `@earendil-works/pi-coding-agent`;
- Node.js `22.19.0`, instalat prin pachetul npm `node`;
- CLI: `/root/.local/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js`;
- Node: `/root/.local/node_modules/node/bin/node`;
- configurație: `/root/.pi/agent`;
- sesiuni: `/root/.pi/sessions`.

Instalarea este în filesystem-ul Debian deținut de aplicație. Node.js este
instalat cu lifecycle scripts pentru binarul ARM64; Pi este instalat cu
`--ignore-scripts`, fiind un bundle JavaScript revizuit. Sunt necesare
Android 10+, ARM64 și aproximativ 900 MB liberi. Instalarea este anulată, iar
ecranul rămâne aprins până la finalizare.

## Autentificare și rutare

Profilurile API și locale ale aplicației sunt sursa de autentificare. Cheia este
citită din seiful aplicației și este scrisă numai în `models.json`-ul privat al
runtime-ului Pi. Profilurile locale fără cheie primesc cheia dummy `pi-local`.

Sunt mapate protocoalele:

| Protocol aplicație | API Pi |
|---|---|
| chat completions | `openai-completions` |
| Responses | `openai-responses` |
| Anthropic messages | `anthropic-messages` |
| Gemini generate content | `google-generative-ai` |

Profilurile OpenCode Zen rămân profiluri API, cu transportul declarat per model.
Profilurile `siwc` (ChatGPT) și `companion` nu sunt materializate în Pi; pentru
ele se folosește în continuare harness-ul nativ. Aceeași revenire se aplică dacă
profilul curent nu are rută Pi, dacă serverul MCP nu este disponibil ori dacă Pi
nu pornește înainte de primul prompt.

Profilurile sunt reconstruite la fiecare tură. O cheie schimbată, un model nou
sau un profil șters nu pot reutiliza o rută veche din memoria procesului.

## Unelte și MCP

Pi păstrează uneltele native `read`, `bash`, `edit`, `write`, `grep`, `find` și
`ls`. Acestea execută direct în PRoot, fără dialogul de aprobare al aplicației,
conform deciziei de produs. Proiectul Godot este montat la `/workspace`.

Catalogul Godot este expus integral prin MCP. Serverul folosește
`"exposure": "deferred"` și Pi pornește cu `tool_search` activ. Modelul caută
unealta relevantă cu mecanismul nativ BM25 al Pi, primește schema exactă și o
apelează direct. Aplicația nu mai oferă un wrapper propriu
`search`/`describe`/`call` și nu mai impune modelului toate schemele deodată.
Timeout-ul MCP este mărit la o oră pentru ca o scriere să poată aștepta
aprobarea umană. `godot_describe` și `godot_call` sunt disponibile pentru
reflecția completă a claselor, obiectelor, proprietăților, semnalelor și
metodelor Godot. Sunt ascunse numai uneltele interne cu prefixul `tool_`, ca
agentul să nu poată ocoli catalogul și aprobările aplicației.

Controlul Ziva este expus prin `ziva_status`, `ziva_start`, `ziva_stop`,
`ziva_restart`, `ziva_install`, `ziva_update`, `ziva_task`,
`ziva_task_poll`, `ziva_task_cancel`, `ziva_task_result`,
`ziva_permission_reply`, `ziva_question_reply` și
`ziva_question_reject`. Rutele native pentru conversație sunt
`permissions/reply`, `questions/reply` și `questions/reject`. Acestea sunt
operații externe și păstrează regulile de aprobare ale aplicației.

Serverul ascultă exclusiv pe `127.0.0.1`, cere un token Bearer de 32 de octeți
și nu acceptă cereri fără autentificare. Capturile sunt trimise ca blocuri MCP
`image`, nu ca text base64 duplicat.

## Moduri și aprobări

| Mod | Pi | Unelte MCP ale aplicației |
|---|---|---|
| Plan | numai `read`, `grep`, `find`, `ls`, `tool_search` | catalogul MCP conține numai unelte read-only |
| Ask | numai citire, ca în Plan | catalogul MCP conține numai unelte read-only |
| Auto | unelte native complete; plan scurt înainte de operațiile aplicației | aprobare dacă Full control este oprit |
| Default | unelte native complete | aprobare dacă Full control este oprit |

Uneltele native Pi nu trec prin dialogul de aprobare al aplicației. Operațiile
aplicației cu efecte (`godot_write_file`, change sets, playtest, Linux, asseturi,
GitHub, Blender, Ziva) păstrează regulile existente de vizibilitate, plan și
aprobare. Modul Auto cere ca un `task_update` cu faza `executing` să fie publicat
înaintea unei mutații prin MCP; el nu poate intercepta o scriere făcută direct
cu `edit`, `write` sau `bash`. Această limitare este explicită în instrucțiunile
Pi.

## Context, istoric și verificare

Pi deține sesiunea, istoricul activ, compactarea automată și memoria de context.
Panoul păstrează procesul Pi viu între tururi cât timp conversația, providerul,
modelul, modul și configurația cheilor rămân aceleași. La schimbarea oricăreia
dintre ele, procesul este oprit și repornit cu `--session-id` pentru conversația
corectă. Sesiunile sunt persistate de Pi în `/root/.pi/sessions`.

Promptul per tur este redus la modul de lucru, modelul selectat, maparea
`/workspace` ↔ `res://`, fișierele și referințele active, imaginile și cererea
utilizatorului. Instrucțiunile stabile sunt scrise în
`/root/.pi/agent/SYSTEM.md`, care înlocuiește identitatea implicită a
harness-ului cu **Agent AI**; `/root/.pi/agent/APPEND_SYSTEM.md` păstrează
numai memento-ul de identitate. Rezumatul de compactare al aplicației, planul
intern și conținutul `AGENT.md` nu mai sunt injectate în fiecare prompt. Pi
citește `AGENTS.md`, `AGENT.md` sau `CLAUDE.md` din proiect când are nevoie de
ele, iar `AGENTS.md`/`CLAUDE.md` sunt descoperite nativ de Pi.

Compactarea automată a aplicației este dezactivată în tururile gestionate de Pi;
Pi folosește propriul prag, rezervă de output și istoric recent. Istoricul
aplicației rămâne jurnalul de UI, aprobări și audit; el nu mai este trimis ca
context paralel către Pi. Fallback-ul nativ păstrează compactarea proprie pentru
SIWC, companion și profilele fără rută Pi. Fișierele din afara proiectului rămân
accesibile prin `file_observe` după ID. Conținutul proiectului este tratat ca
date, nu ca permisiune de a schimba regulile.

Evenimentele RPC sunt mapate astfel:

- `message_update` → streaming text/thinking;
- `tool_execution_start` / `tool_execution_end` → carduri, jurnal și rezultate;
- `message_end` → textul autoritativ și erorile furnizorului;
- `response` → succesul comenzilor și refuzul promptului;
- `compaction_*`, `agent_settled`, erori și ieșirea procesului → stare UI.

La final, apelurile și rezultatele reale sunt scrise în istoricul aplicației. Nu
mai sunt înlocuite cu rezultate sintetice „întrerupt” la reîncărcare. Dacă un
apel rămâne fără rezultat, repararea existentă a istoricului îl marchează
explicit.

Pentru `bash`, `edit` și `write`, aplicația ia un snapshot mărginit al
proiectului înainte și după unealtă și înregistrează schimbările externe fără a
promite rollback. Rezultatele uneltelor MCP sunt parsate înapoi în forma
structurată a aplicației. `plan_ask` creează un card de întrebări și în sesiunea
Pi, deoarece apelul Pi se execută înainte ca mesajul assistant să fie comis în
istoricul aplicației.

## Probă pe dispozitiv

1. Instalează APK-ul care conține `AIPiRuntime` și deschide un proiect Godot.
2. În **AI Assistant → Setări → Furnizori AI**, salvează un profil API cu cheie
   validă, apoi selectează un model din acel profil.
3. Trimite un mesaj simplu. La prima rulare, aplicația descarcă Node.js și Pi
   (aproximativ 250 MB) și afișează progresul. Ține aplicația în prim-plan până
   la finalul instalării.
4. În **Plan**, cere o analiză fără modificări. În **Default**, cere o editare
   mică și verifică rezultatul real în proiect.
5. Pentru o operație Godot prin MCP, verifică dialogul de aprobare când Full
   control este oprit. Pentru `bash`/`edit`/`write` native, verifică schimbarea
   în jurnalul de activitate și în fișiere.
6. Dacă Pi nu pornește, notează mesajul din chat și coada de eroare din jurnal;
   nu presupune că instalarea npm sau un furnizor live a funcționat fără aceste
   dovezi.

## Verificări efectuate în surse

- `gdparse` pe toate scripturile `modules/ai_assistant/runtime/*.gd` și pe
  `test_runtime.gd`;
- `py_compile` pe generatorul de runtime și pe runner-ele Python;
- `git diff --check`;
- `test_pi_runtime.py`: unsprezece verificări statice pentru versiuni,
  `exposure: deferred`, `tool_search`, `APPEND_SYSTEM.md`, modul read-only,
  reutilizarea sesiunii, compactarea Pi, calea normală de aprobare, identitatea
  Agent AI, accesul complet la reflecția Godot, uneltele de control Ziva și
  absența suprafeței OpenCode;
- `test_runtime.gd` verifică expunerea `godot_call`/`godot_describe`, uneltele
  Ziva și catalogul complet al aplicației;
- escapare `$`/`!` pentru `apiKey` a fost verificată direct cu resolverul Pi
  1.5.0: cheile literale nu mai pot declanșa expansiune de mediu sau comenzi
  shell prin sintaxa configurației;
- configurația `models.json` generată de aplicație a fost acceptată de Pi 1.5.0
  cu `--list-models` (inclusiv model fără câmp `cost`);
- pachetul `node-linux-arm64@22.19.0` conține un ELF 64-bit AArch64 (ET_EXEC)
  cu interpretor glibc `/lib/ld-linux-aarch64.so.1`, compatibil cu Debianul din
  PRoot;
- `test_runtime.gd` a validat catalogul MCP complet, apelurile directe și
  filtrarea read-only pentru Plan; joburile `runtime` au trecut în CI pe ambele
  distribuții. Proba end-to-end locală cu Pi rămâne istorică; noul catalog
  deferred nu a fost încă verificat cu un model live.

Aceste probe validează protocolul și configurația, **nu** un furnizor real, un
cont, instalarea Node.js ARM64 din APK sau interfața pe dispozitiv.

## Compilare CI

Ambele distribuții au fost compilate din sursa
`9fb15f9f166061130c88d16cb9e3866c5fa8c5b6`:

- [standard](https://github.com/JDscript1/codot-ai-opencode/actions/runs/41655561284)
  (`com.jdscript.godotai.debug`) și
  [ziva-preview](https://github.com/JDscript1/codot-ai-opencode/actions/runs/41655567953)
  (`com.jdscript.godotai.ziva.debug`);
- toate joburile `runtime`, `native-editor` și `android` au încheiat cu succes;
- jobul Android a verificat semnătura v2, package-ul, ABI ARM64, clasele
  `AIPiRuntime` în dex, absența suprafeței OpenCode/PTY, runtime-ul încorporat,
  `APPEND_SYSTEM.md`, `tool_search`, `deferred`, `compact` și toate cele **46 de
  scripturi** `runtime/*.gd` byte cu byte.

Artefactele au fost descărcate și verificate local:

| Distribuție | Bytes | SHA-256 | Certificat SHA-256 |
|---|---:|---|---|
| standard | 112.626.618 | `716620d34b90b468aeba18a1ddf3a7db5f120405a81cffe009184c9f153e1c91` | `c2bcbb05cdaaedb1f78f69b02d779a6c34edae5763c931caab8fe05cb56846c2` |
| Ziva | 112.629.250 | `bbbb66bdbc1da7d7a5ba65d1b8502761176644084ca2b0bb63f8d346f5146573` | `188a549174b80a2fc9a07f529605483e8e5678cf4e47a1309176d1cec6ea5d1e` |

APK-urile vechi din Download folosesc certificatul persistent
`2e0a80969c099f7ff72bfe0c0cd33d98ebdd0e64bbf9729294df0b11665fcab5` din
repository-ul anterior. Noul repository nu are secretul
`GODOT_AI_DEBUG_KEYSTORE`, deci build-urile de aici folosesc chei debug
efemerale. Instalarea peste aplicația existentă cere fie aceeași cheie de
semnare, fie dezinstalare; APK-ul nu este instalat automat.

Copiile cu nume stabile din Download au fost înlocuite atomic la
**3.11.2026, 16:19:16 CET**: `Godot-AI-Android-arm64-debug.apk` și
`Godot-AI-Ziva-arm64-debug.apk`, fiecare cu checksum alăturat. Instalatoarele
anterioare sunt păstrate numai ca dovezi în
`~/godot-ai-artifacts/pi-native-9fb15f9f16/previous/`; în Download au rămas cele
două build-uri noi.

Instalatoarele curente din Download au fost ulterior recompilate din
`87563a46cd` pentru corecția fluxului SIWC ChatGPT; arhitectura Pi descrisă aici
este neschimbată. Detaliile livrării SIWC sunt în AG-88 din
[jurnalul proiectului](../PROGRES_SI_PLAN.md).

## Limite

- Binarul Node.js ARM64 și instalarea Pi în PRoot nu au fost încă rulate pe
  dispozitiv.
- Nu există probă live cu un furnizor API real și nici validare vizuală Android.
- Uneltele native Pi ocolesc aprobările și planul aplicației; schimbările lor
  sunt observate mărginit, fără copie de recuperare exactă.
- PRoot nu este un sandbox de securitate. Procesul Pi poate citi configurația
  privată și cheile furnizorilor disponibile în runtime; prompt injection sau o
  comandă greșită le poate expune. Folosește chei cu drepturi minime și nu rula
  proiecte neîncrezute pe un dispozitiv partajat.
- `plan_ask` din Pi folosește un card detașat de apelul MCP; pentru istoricul
  nativ nu inventează un ID de apel provider.
- În Plan și Ask, catalogul MCP publică numai unelte `read`, deci Pi nu poate
  publica `task_update` sau `plan_ask` prin MCP în acele moduri. Planificarea
  structurată rămâne disponibilă în Auto/Default și pe harness-ul nativ.
- Conversațiile bifurcate sau importate pornesc o sesiune Pi nouă; istoricul
  aplicației rămâne în UI, dar nu este migrat automat în sesiunea Pi.
- O singură sesiune Pi rulează pe un singur proiect. Versiunile Pi/Node sunt
  fixate și trebuie reverificate la fiecare actualizare.
- Identitatea de semnare nu este încă persistentă în acest repository. Pentru
  update-uri instalabile fără dezinstalare trebuie adăugat secretul keystore-ului
  existent sau configurată o cheie stabilă înaintea următorului build.
- Fallback-ul nativ rămâne necesar pentru ChatGPT SIWC, companion și orice
  profil fără rută Pi.
