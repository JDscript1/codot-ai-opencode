# OpenCode TUI în Godot AI Android

Stare: **implementat în surse; instalarea npm a fost verificată manual pe
dispozitiv, corecțiile de instalare așteaptă un APK recompilat, iar TUI-ul
rămâne de probat**. Data ultimei revizuiri: 2 noiembrie 2026.

OpenCode este un runtime de agent opțional, separat de asistentul AI propriu.
Aplicația afișează interfața terminal OpenCode într-un tab principal dedicat
și îi expune uneltele Godot prin MCP. Asistentul cu furnizor direct rămâne
complet funcțional dacă OpenCode nu este instalat, nu pornește sau este oprit.

## Ce este și ce nu este

- **Este** un TUI OpenCode real, rulat în runtime-ul Debian al aplicației, pe
  proiectul Godot curent montat la `/workspace`.
- **Este** o integrare MCP locală: OpenCode descoperă și apelează uneltele
  editorului Godot, inclusiv scene, playtest, capturi, change sets, assets,
  skills și engineering.
- **Nu este** un al doilea asistent încorporat în chatul propriu. Conversația,
  aprobările și comanda `/connect` aparțin OpenCode.
- **CLI-ul nu este împachetat** în APK. Node.js, npm și CLI-ul OpenCode se
  descarcă la cerere în stocarea privată a aplicației; APK-ul crește doar cu
  ajutorul PTY nativ și cu activele terminalului (xterm.js).
- **Nu folosește** vault-ul de chei al asistentului. Furnizorii și modelele
  OpenCode se configurează prin `/connect` și `/models` în TUI.

## Fluxul utilizatorului

1. Tab-ul **OpenCode** verifică runtime-ul Linux comun cu Ziva. Dacă Debian-ul
   nu este pregătit, butonul rămâne dezactivat și explică starea.
2. **Instalează OpenCode** pornește un worker care:
   - verifică spațiul liber (minimum 900 MB în stocarea privată);
   - instalează `nodejs`, `npm`, `git` și `ripgrep` prin `apt-get`, dacă lipsesc;
   - fixează `registry.npmjs.org` în `/etc/hosts` din adresele rezolvate de
     Android, apoi rulează `npm install --prefix /root/.local --omit=optional
     @opencode/cli@2.2.5 @opencode/cli-linux-arm64@2.2.5`; sunt descărcate
     numai arhivele CLI și ARM64, nu toate variantele de platformă;
   - ține ecranul aprins în timpul descărcării și reia o dată instalarea dacă
     npm raportează un cache `_cacache` corupt;
   - verifică binarul și rulează `opencode --version`.
3. **Pornește OpenCode** creează configurația globală, pornește serverul MCP
   local, lansează PRoot + OpenCode sub PTY și încadrează terminalul peste
   suprafața Godot.
4. În terminal, utilizatorul rulează `/connect` pentru furnizor și `/models`
   pentru model. Cheia rămâne în configurația OpenCode din runtime.
5. Prima utilizare a uneltei `godot_call`, a editării sau a shell-ului cere
   aprobare în TUI. `godot_search` și `godot_describe` sunt permise direct.
6. **Oprește** trimite `Q` prin canalul de control, apoi închide procesul;
   **Repornește** așteaptă terminarea procesului vechi înainte de a porni altul.

Instalarea poate fi anulată din meniu. Ea nu modifică proiectul Godot și nu
șterge runtime-ul Linux sau instalările Ziva.

## Arhitectură

### 1. Tab-ul Godot — `opencode_screen.gd`

Ecranul principal este un `VBoxContainer` cu bară de stare, buton principal și
meniu. El nu desenează terminalul: calculează dreptunghiul normalizat al
zonei `OpenCodeTerminal` și îl trimite prin `opencode.embed()` către suprafața
WebView nativă. Terminalul este ascuns când tab-ul nu este vizibil, când un
popup este deschis sau când aplicația intră în fundal.

Ecranul reîncearcă încadrarea la fiecare 3 secunde dacă prima încercare a
eșuat, păstrează placeholder-ul vizibil cu eroarea și reîmprospătează starea
la 1,2 secunde. Repornirea este amânată până când procesul vechi a murit.

Fișier: `modules/ai_assistant/runtime/opencode_screen.gd`.

### 2. Modelul Godot — `opencode.gd`

`opencode.gd` este o punte subțire către `AIOpenCodePanel.opencode_request()`.
Acțiunile permise sunt `status`, `install`, `cancel`, `start`, `stop` și
`embed`; orice altă acțiune este respinsă în C++. Modelul nu are acces la
chei, la shell sau la procese.

Fișier: `modules/ai_assistant/runtime/opencode.gd`.

### 3. Panoul nativ — `AIOpenCodePanel`

Clasa C++ creează ecranul, încarcă scripturile încorporate `opencode.gd` și
`opencode_screen.gd`, expune `opencode_request()` și `mcp_info()`, și este
înregistrată ca plugin de editor separat. `AIOpenCodeEditorPlugin` are propriul
tab principal, numit **OpenCode**, fără să încarce chatul asistentului.

Fișiere: `modules/ai_assistant/ai_assistant_editor.h`,
`modules/ai_assistant/ai_assistant_editor.cpp`,
`modules/ai_assistant/register_types.cpp`, `editor/editor_node.cpp`.

### 4. Serverul MCP — `opencode_mcp.gd`

Serverul este pornit de panoul asistentului (`panel.gd`) când editorul este
disponibil. Ascultă exclusiv pe `127.0.0.1`, pe un port efemer, și cere un
token bearer aleatoriu, păstrat cu permisiuni `0600` în
`<config>/ai_assistant/opencode_mcp.json`. Tokenul este scris de partea
Android în configurația OpenCode.

Implementează Streamable HTTP cu răspunsuri JSON:

- `initialize` negociază `2025-11-25`, `2025-06-18`, `2025-03-26` sau
  `2024-11-05`; orice altă versiune primește revizia implicită;
- `ping`, `tools/list`, `tools/call`;
- `resources/list`, `resources/templates/list` și `prompts/list` întorc liste
  goale;
- notificările JSON-RPC primesc `202` fără corp;
- corpurile `Transfer-Encoding: chunked` sunt decodificate;
- limita este 32 KB pentru antet, 4 MB pentru corp, 12 conexiuni simultane și
  30 de secunde de inactivitate.

Catalogul complet al editorului **nu** este publicat în `tools/list`. Sunt
expuse doar trei meta-unelte, pentru a nu umple contextul modelului:

| Unealtă | Rol |
| --- | --- |
| `search` | Caută în catalogul editorului după nume/descriere, maximum 50 de rezultate. |
| `describe` | Întoarce descrierea și schema JSON exactă a unei unelte. |
| `call` | Execută unealta cu argumentele validate; capturile întorc conținut imagine MCP. |

OpenCode le vede prefixate cu numele serverului: `godot_search`,
`godot_describe`, `godot_call`. `_call_tool()` acceptă și forma prefixată, dar
`tools/list` publică numele scurte, conform contractului MCP.

Fișier: `modules/ai_assistant/runtime/opencode_mcp.gd`.

### 5. Filtrarea catalogului — `panel.gd`

`opencode_catalog()` pornește de la `_all_definitions()` și elimină:

- uneltele de harness, planificare, memorie, Ziva, MCP, Linux, GitHub,
  Blender, preview și management de unelte (`agent_`, `task_`, `plan_`,
  `memory_`, `ziva_`, `mcp_`, `linux_`, `github_`, `blender_`, `preview_`,
  `tool_`);
- reflexia brută și dialogurile de fișiere (`godot_call`, `godot_describe`,
  `project_dialog`, `file_catalog`, `file_show`, `file_observe`,
  `file_preview`).

Rămân uneltele Godot pentru scene, noduri, scripturi, playtest, capturi,
change sets, assets, skills, store, engineering, verificare și diagnostic.
Fiecare apel trece prin `_execute_call(..., true)`, deci folosește aprobările,
jurnalul și limitele editorului, nu o cale ocolitoare.

Un singur apel OpenCode poate rula odată (`opencode_busy`), iar asistentul
propriu și OpenCode nu pot executa simultan operații care modifică editorul.

### 6. Runtime-ul Android — `AIOpenCodeRuntime.kt`

Răspunde la acțiunile `opencode_*` primite prin `AILinuxRuntime`:

- **status** — versiune, instalare, stare Linux, proces, proiect, port MCP,
  spațiu liber și ultimele linii din terminal;
- **install / cancel** — worker npm cu progres și anulare;
- **start** — validează proiectul, portul și tokenul, scrie configurația,
  creează un FIFO de control și lansează PTY-ul;
- **stop** — `Q` prin FIFO, apoi `destroy()` și `destroyForcibly()` după 4 s;
- **embed / write / resize** — suprafața WebView, intrarea și dimensiunea.

Proiectul este montat de PRoot la `/workspace`, iar procesul este pornit în
`/workspace`. Argumentele PRoot sunt partajate cu restul runtime-ului prin
`AILinuxRuntimeFiles.prootArguments()`, iar mediul prin
`AILinuxRuntimeFiles.processEnvironment()`. Astfel OpenCode folosește
`libai_proot.so`, loader-ul și DNS-ul sincronizat ale aplicației, fără o a
doua configurare divergentă.

Calea binarului instalat:
`root/.local/node_modules/@opencode/cli/bin/opencode.exe`, cu shim-ul
`root/.local/node_modules/.bin/opencode`.

### 7. PTY nativ — `libai_pty.so`

Android nu oferă `openpty()` în Java, iar pipe-urile nu au terminal de control,
deci OpenCode nu ar putea intra în modul TUI. Ajutorul nativ
`platform/android/java/editor/src/main/native/ai_pty.c`:

- alocă un PTY și pornește comanda primită după `--`;
- copiază stdin/stdout între proces și PTY;
- citește comenzi de control dintr-un FIFO: `R <cols> <rows>` redimensionează,
  `Q` cere terminarea grațioasă;
- propaga `SIGTERM`/`SIGINT`, închide descriptorii și raportează codul de
  ieșire;
- este compilat ca PIE ARM64, cu aliniere pe pagini de 16 KB, și împachetat ca
  `libai_pty.so` în `nativeLibraryDir`.

Prima dimensiune este 100×30; xterm.js trimite apoi dimensiunea reală prin
`ResizeObserver`. FIFO-ul este recreat la fiecare pornire și șters la oprire.

### 8. Suprafața terminalului — `AIOpenCodeWindow.kt`

WebView-ul încarcă numai `file:///android_asset/ai/opencode/terminal.html`.
Sunt dezactivate accesul la fișiere largi, zoom-ul și navigarea către alte
origini; puntea `GodotTerminal` este disponibilă doar acestei pagini locale.

- Activele sunt xterm.js 6.0.0 și `@xterm/addon-fit` 0.11.0, incluse în
  `platform/android/java/editor/src/main/assets/ai/opencode/` împreună cu
  licența MIT.
- Ieșirea PTY este base64, acumulată și trimisă în loturi de maximum 2 MB.
  Dacă terminalul rămâne în urmă, coada este golită și pagina se
  resincronizează din scrollback-ul limitat la 512 KB al runtime-ului.
- Intrarea, paste-ul, redimensionarea și ascunderea tastaturii trec prin
  puntea JS; nu există acces la clipboard sau la fișiere din JavaScript.
- Dreptunghiul este normalizat față de suprafața de randare Godot, deci
  rotația, barele de sistem și tastatura Android sunt luate în calcul.
- La ascundere, WebView-ul este oprit și terminalul nu mai consumă resurse;
  la repornire, scrollback-ul este reafișat fără ștergerea conținutului.

Fișiere: `AIOpenCodeWindow.kt`,
`assets/ai/opencode/terminal.html`, `xterm.js`, `xterm.css`, `addon-fit.js`.

## Configurația OpenCode

La fiecare pornire, `AIOpenCodeRuntime.writeConfig()` citește configurația
existentă (`opencode.json` sau `opencode.jsonc`, păstrând fișierul folosit),
acceptă comentarii și virgule finale, apoi actualizează numai cheile gestionate:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "servers": {
      "godot": {
        "type": "remote",
        "url": "http://127.0.0.1:43123/mcp",
        "oauth": false,
        "codemode": false,
        "headers": { "Authorization": "Bearer <token>" }
      }
    }
  },
  "permissions": [
    { "action": "read", "resource": "*", "effect": "allow" },
    { "action": "edit", "resource": "*", "effect": "ask" },
    { "action": "shell", "resource": "*", "effect": "ask" },
    { "action": "godot_search", "resource": "*", "effect": "allow" },
    { "action": "godot_describe", "resource": "*", "effect": "allow" },
    { "action": "godot_call", "resource": "*", "effect": "ask" }
  ]
}
```

Regulile `permissions` sunt ordonate, iar ultima potrivire câștigă. Sunt
păstrate regulile utilizatorului pentru alte acțiuni; cele șase acțiuni
gestionate sunt înlocuite. `edit` și `shell` cer aprobare, iar `godot_call`
cere aprobare pentru fiecare apel; `read`, `godot_search` și `godot_describe`
sunt permise. Configurația este scrisă doar pentru utilizatorul aplicației.

Dacă fișierul existent nu poate fi citit ca JSON după eliminarea comentariilor,
pornirea este refuzată cu mesaj explicit, în loc să suprascrie configurația
utilizatorului.

## Date și ciclu de viață

- Instalarea și configurația stau în `noBackupFilesDir/ai-linux/rootfs` și
  `noBackupFilesDir/opencode`. Nu sunt incluse în backup și nu sunt vizibile
  altor aplicații.
- Tokenul MCP stă în configurația AI Assistant, cu permisiuni `0600`; este
  regenerat dacă lipsește sau nu este hexazecimal de 32 de bytes.
- `AIOpenCodeRuntime.initialize()` înregistrează WebView-ul; `release()` îl
  eliberează și oprește procesul la distrugerea activității.
- `onStop` pune WebView-ul pe pauză; `onResume` îl reia doar dacă era vizibil.
- O repornire a aplicației nu păstrează procesul OpenCode, dar păstrează
  instalarea, configurația, tokenul și proiectul.
- Ziva și OpenCode folosesc același runtime Debian, dar instalările npm sunt
  separate de addonul Ziva. O operație Ziva activă blochează instalarea
  OpenCode, iar una OpenCode activă blochează operațiile Linux concurente.

## Securitate

- Serverul MCP nu părăsește `127.0.0.1`; nu este accesibil din rețeaua locală.
- Fiecare cerere MCP cere token bearer; comparația folosește SHA-256, nu
  comparație directă de string.
- OpenCode nu primește unelte de shell prin MCP. Shell-ul și editarea rămân
  sub permisiunile și aprobările TUI, iar uneltele Godot trec prin filtrul
  panoului.
- `godot_call` nu poate apela `godot_call`/`godot_describe` recursive, unelte
  de harness, planificare, Ziva, MCP, Linux, GitHub sau Blender.
- WebView-ul acceptă numai pagina locală din `assets/ai/opencode/`; orice altă
  navigare este blocată.
- Terminalul nu este logat în clar în fișiere; `tail`-ul de stare este limitat
  și curățat de secvențe ANSI, dar poate conține text afișat de OpenCode.

## Verificări efectuate

Verificări statice/automate, rulate local pe surse:

- `gdparse` pe `opencode_mcp.gd`, `opencode.gd`, `opencode_screen.gd` și
  `panel.gd`;
- `node --check` pe JavaScript-ul inline din `terminal.html` și pe
  `addon-fit.js`;
- `py_compile` pe `runtime_builder.py` și verificarea că toate scripturile
  `runtime/*.gd` sunt incluse în build;
- parsarea YAML a workflow-ului `.github/workflows/ai-android.yml`;
- compilarea și linkarea `ai_pty.c` cu clang, `-O2 -Wall -Wextra -Werror`;
- `git diff --check`.

Teste Godot adăugate în `modules/ai_assistant/tests/test_runtime.gd`:

- respingerea cererilor MCP fără token;
- negocierea reviziei `2025-11-25`;
- publicarea celor trei meta-unelte, fără catalogul complet;
- delegarea căutării și a execuției către panou;
- un singur bloc imagine pentru capturi;
- decodificarea corpurilor chunked și așteptarea corpurilor incomplete;
- excluderea uneltelor de reflexie/harness/shell și includerea celor de editor,
  playtest și change sets.

Workflow-ul Android verifică suplimentar, în APK-ul construit:

- `lib/arm64-v8a/libai_pty.so` este ELF 64-bit, PIE și AArch64;
- există `terminal.html`, `xterm.js`, `addon-fit.js`, `xterm.css` și `LICENSE`;
- clasele `AIOpenCodeRuntime` și `AIOpenCodeWindow` sunt prezente în dex;
- `AIOpenCodeEditorPlugin` este în biblioteca nativă;
- fiecare script `modules/ai_assistant/runtime/*.gd` este încorporat byte cu
  byte în `libgodot_android.so`.

Compilarea verificată este workflow-ul
[41449899776](https://github.com/JDscript1/godot-ai-android/actions/runs/41449899776),
pe sursa `793a4152b3567e98506d3673dffbde13f41d542f`: joburile `runtime`,
`native-editor` și `android` au trecut. APK-ul are
`com.jdscript.godotai.debug`, numai ARM64, **112.790.988 bytes**, SHA-256
`78812b2dbdde1984b7779772aa61e46bfb137c20fac979830a0d643f4f7fc0fd`.
Artefactul este păstrat ca dovadă locală în
`~/godot-ai-artifacts/opencode-793a4152/` și a fost livrat în
`/storage/emulated/0/Download/Godot-AI-Android-arm64-debug.apk`, cu checksum
alăturat. Pachetul nu a fost instalat.

## Diagnostic pe dispozitiv — 2 noiembrie 2026

APK-ul `793a4152` a fost instalat pe dispozitivul NX729J-UN prin ADB
(`10.146.52.179:41687`). Instalarea OpenCode din UI a rămas afișată la 55% și
nu a ajuns la terminal. Jurnalul npm
`/root/.npm/_logs/2026-11-02T13_38_29_352Z-debug-0.log` a arătat
`ECONNABORTED`, `exit -103`, descărcări parțiale ale tuturor pachetelor de
platformă și un `@opencode/cli/bin/opencode.exe` de numai 229 bytes; scriptul
`postinstall.mjs` nu apucase să ruleze. UI-ul ascundea eroarea pentru că
`opencode_screen.gd` verifica „neinstalat” înaintea stării `error`.

Cauza dominantă a fost rețeaua în Doze: ecranul se stinge, Android intră în
`mWakefulness=Dozing` (`Device idle: true`), iar socketurile TCP ale UID-ului
aplicației expiră. În plus, resolverul guest primea `nameserver 10.146.52.7`,
dar `getent hosts registry.npmjs.org` întorcea `rc=2`; Android rezolva același
host la `104.16.8.34`, iar `curl` și `ping` funcționau din shell. După trezirea
dispozitivului, scoaterea aplicației din restricțiile de idle și adăugarea
adresei Android în `/etc/hosts`, toate cele trei conexiuni TCP de probă
(`registry.npmjs.org`, `deb.debian.org`, `1.1.1.1`) au reușit.

Reparația manuală, în runtime-ul privat al aplicației, a șters `_cacache` și a
rulat `npm install --prefix /root/.local --omit=optional --foreground-scripts
@opencode/cli@2.2.5 @opencode/cli-linux-arm64@2.2.5`. Au rezultat două pachete,
postinstall cu cod 0, un binar ARM64 de **248.433.656 bytes** și
`opencode v2.2.5`. Corecțiile din surse fac pașii repetabili din UI:
`synchronizeHosts` fixează și `registry.npmjs.org`, comanda npm este limitată
la ARM64, cache-ul corupt este curățat și reîncercat, timeout-ul de fetch este
mai mare, iar fereastra ține ecranul aprins în timpul instalării. Proba de mai
sus a folosit ADB/`run-as`; ea nu validează încă noul cod compilat.

## Limite și pași următori

- **Corecțiile nu sunt încă în APK.** Mediul local nu are Android SDK/NDK,
  Gradle, Kotlin sau un editor Godot precompilat; compilarea rulează în GitHub
  Actions. APK-ul `793a4152` este instalat pe dispozitiv, dar nu conține
  modificările de DNS, npm ARM64, cache, ecran aprins și ordine a erorii.
- **TUI-ul rămâne neprobat.** Instalarea npm a fost verificată manual, însă
  nu au fost rulate din aplicație: pornirea PTY, redimensionarea, tastatura,
  scrollback-ul, aprobările TUI și repornirea.
- **Furnizor live nevalidat.** `/connect` și `/models` depind de contul și
  rețeaua utilizatorului; nu există o probă cu un furnizor real în această
  etapă.
- **Contract MCP V2.** Configurația folosește `mcp.servers` și permisiunile
  ordonate din documentația V2. Versiunea CLI este fixată la `2.2.5`; o
  actualizare poate schimba numele acțiunilor sau formatul configurării și
  trebuie reverificată.
- **Spațiu și rețea.** Instalarea cere circa 900 MB liberi și acces la
  depozitele Debian/npm. `preparePackageNetwork` este apelat înaintea fiecărei
  instalări npm și fixează atât `deb.debian.org`, cât și
  `registry.npmjs.org`; o rețea captivă sau o schimbare de DNS între pregătire
  și descărcare poate cere totuși reîncercare. Ecranul rămâne aprins numai cât
  timp aplicația este în prim-plan; dacă utilizatorul blochează telefonul,
  Android poate intra în Doze și poate opri transferul.
- **O singură sesiune.** Un singur proces OpenCode rulează odată, pe un singur
  proiect. Schimbarea proiectului cere oprire și repornire; nu există încă
  migrare automată a sesiunii.
- **Fără verificare a semnăturii npm.** Instalarea folosește registrul npm
  configurat în runtime; integritatea este cea a pachetului public, nu o
  verificare proprie în aplicație.

Următorii pași sunt recompilarea APK-ului cu aceste corecții, instalarea lui
peste versiunea existentă și repetarea instalării din UI, cu ecranul aprins,
apoi proba cap-coadă: `/connect`, `/models`, un apel `godot_search` și un
`godot_call` cu aprobare.
