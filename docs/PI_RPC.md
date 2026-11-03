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
| Server MCP | `modules/ai_assistant/runtime/godot_mcp.gd` | Server loopback cu Bearer token și meta-uneltele `search`, `describe`, `call`. |
| Panou | `modules/ai_assistant/runtime/panel.gd` | Pornește Pi înainte de harness-ul nativ, randează streamingul, uneltele, întrebările și aprobările, apoi salvează rezultatele reale în istoric. |

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

Toate funcțiile aplicației sunt expuse prin MCP cu trei meta-unelte:

- `search` caută în catalogul de unelte;
- `describe` întoarce schema JSON exactă;
- `call` execută unealta reală.

Serverul folosește `"exposure": "direct"`, astfel încât Pi declară modelului
`mcp__godot__search`, `mcp__godot__describe` și `mcp__godot__call`. Timeout-ul
MCP este mărit la o oră pentru ca o scriere să poată aștepta aprobarea umană.
Sunt blocate numai meta-uneltele de reflecție recursivă (`godot_call`,
`godot_describe`, `godot_search` și prefixul `tool_`).

Serverul ascultă exclusiv pe `127.0.0.1`, cere un token Bearer de 32 de octeți
și nu acceptă cereri fără autentificare. Capturile sunt trimise ca blocuri MCP
`image`, nu ca text base64 duplicat.

## Moduri și aprobări

| Mod | Pi | Unelte MCP ale aplicației |
|---|---|---|
| Plan | numai `read`, `grep`, `find`, `ls`, `search`, `describe` | `call` este ascuns și refuzat |
| Ask | numai citire, ca în Plan | `call` este ascuns și refuzat |
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

Promptul trimis lui Pi conține instrucțiunile modului, maparea `/workspace` ↔
`res://`, fișierele selectate, referințele și imaginile active. Fișierele din
afara proiectului rămân accesibile prin `file_observe` după ID. Conținutul
proiectului este tratat ca date, nu ca permisiune de a schimba regulile.

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
- `test_pi_runtime.py`: cinci verificări statice pentru versiuni, `exposure`,
  timeout, modul read-only, calea normală de aprobare și absența suprafeței
  OpenCode;
- escapare `$`/`!` pentru `apiKey` a fost verificată direct cu resolverul Pi
  1.5.0: cheile literale nu mai pot declanșa expansiune de mediu sau comenzi
  shell prin sintaxa configurației;
- configurația `models.json` generată de aplicație a fost acceptată de Pi 1.5.0
  cu `--list-models` (inclusiv model fără câmp `cost`);
- pachetul `node-linux-arm64@22.19.0` conține un ELF 64-bit AArch64 (ET_EXEC)
  cu interpretor glibc `/lib/ld-linux-aarch64.so.1`, compatibil cu Debianul din
  PRoot;
- probă end-to-end locală cu Pi 1.5.0, un furnizor OpenAI-compatible simulat și
  un server MCP simulat: modelul a primit cele șapte unelte native plus
  `mcp__godot__search`, `mcp__godot__describe`, `mcp__godot__call`; apelul
  `search` a trecut prin transportul MCP și rezultatul a intrat în turul
  următor.

Aceste probe validează protocolul și configurația, **nu** un furnizor real, un
cont, instalarea Node.js ARM64 din APK sau interfața pe dispozitiv.

## Compilare CI

Ambele distribuții au fost compilate din sursa
`92b98d381932e2692e4ec9e5a82eb5e82f14ccef`:

- [standard](https://github.com/JDscript1/codot-ai-opencode/actions/runs/41606629516)
  (`com.jdscript.godotai.debug`) și
  [ziva-preview](https://github.com/JDscript1/codot-ai-opencode/actions/runs/41606640713)
  (`com.jdscript.godotai.ziva.debug`);
- runtime-ul a raportat **1015 aserțiuni, 0 eșecuri** în ambele rulări;
- editorul nativ compilat a trecut **991 de verificări, 0 eșecuri** în fiecare
  dintre cele cinci configurații, plus suitele focalizate 134/75/76/71/76/90;
- jobul Android a verificat semnătura v2, package-ul, ABI ARM64, clasele
  `AIPiRuntime` în dex, absența suprafeței OpenCode/PTY, runtime-ul încorporat și
  toate cele **46 de scripturi** `runtime/*.gd` byte cu byte.

Artefactele au fost descărcate și verificate local:

| Distribuție | Bytes | SHA-256 | Certificat SHA-256 |
|---|---:|---|---|
| standard | 112.627.098 | `599b0f0d2af894e874236cdb42375f46a244628a4077ba0dc1bc526c9bea0a35` | `891fadfa32ff0262ddf19b5db55e5308f16d1c5b77e1f308c9d9748d14e3aad4` |
| Ziva | 112.628.630 | `a78670f5315d9c8ab57eb99f571d81b83721f1976baf1735452d9c7cb54a547a` | `e12cc9609a9f636eb24b0a35f3be1136bb74a116dd6891b7189faf93641ee044` |

APK-urile vechi din Download folosesc certificatul persistent
`2e0a80969c099f7ff72bfe0c0cd33d98ebdd0e64bbf9729294df0b11665fcab5` din
repository-ul anterior. Noul repository nu are secretul
`GODOT_AI_DEBUG_KEYSTORE`, deci build-urile de aici folosesc chei debug
efemerale. Instalarea peste aplicația existentă cere fie aceeași cheie de
semnare, fie dezinstalare; APK-ul nu este instalat automat.

Copiile cu nume stabile din Download au fost înlocuite atomic la
**3.11.2026, 10:55 CET**: `Godot-AI-Android-arm64-debug.apk` și
`Godot-AI-Ziva-arm64-debug.apk`, fiecare cu checksum alăturat. Instalatoarele
anterioare sunt păstrate numai ca dovezi în
`~/godot-ai-artifacts/pi-rpc-92b98d3819/previous/`; în Download au rămas cele
două build-uri noi.

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
- În Plan și Ask, `call` este dezactivat, deci Pi nu poate publica `task_update`
  sau `plan_ask` în acele moduri. Planificarea structurată rămâne disponibilă
  în Auto/Default și pe harness-ul nativ.
- O singură sesiune Pi rulează pe un singur proiect. Versiunile Pi/Node sunt
  fixate și trebuie reverificate la fiecare actualizare.
- Identitatea de semnare nu este încă persistentă în acest repository. Pentru
  update-uri instalabile fără dezinstalare trebuie adăugat secretul keystore-ului
  existent sau configurată o cheie stabilă înaintea următorului build.
- Fallback-ul nativ rămâne necesar pentru ChatGPT SIWC, companion și orice
  profil fără rută Pi.
