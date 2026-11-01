# Ziva independent în Godot AI — preview

> **Notă:** Integrarea Android descrisă aici este un proiect independent, fără
> afiliere cu Ziva.sh. Pluginul și runtime-ul Ziva sunt proprietare, se descarcă
> din release-ul oficial și nu sunt redistribuite în acest depozit.

## Delegare către agentul Ziva — 31.10.2026

Agentul nostru poate cere oficialului Ziva o sarcină de sine stătătoare, prin
procedurile RPC locale ale sidecarului (`/api/rpc/*`), nu prin WebView și nu
printr-o punte MCP proprie. Comenzile trec prin `AIZivaChat` în procesul
aplicației: sarcina rulează în fundal, iar harness-ul nostru o așteaptă prin
sonde (`poll`) și citește doar răspunsul final.

Uneltele expuse modelului nostru:

- `ziva_task` — risc „external”, deci cere aprobarea utilizatorului când YOLO
  este oprit și dispare în modurile doar-citire. Trimite promptul, creează sau
  refolosește o conversație dedicată intitulată **Godot AI** și așteaptă până
  la răspuns final, permisiune sau întrebare. Ziva nu vede conversația noastră:
  promptul trebuie să conțină singur căile, cerințele și criteriul de acceptare.
- `ziva_task_poll` — reia așteptarea unei sarcini după ce utilizatorul a
  aprobat o permisiune sau a răspuns unei întrebări în tabul Ziva.
- `ziva_task_result` — citește felii exacte (offset/limit) dintr-un răspuns lung;
  primul răspuns se taie la 6000 de caractere și indică `next_offset`.

Sarcina este acceptată numai când sesiunea Ziva rulează pe **același proiect**
ca editorul Android (identificatori de proiect SHA-256 comparați) și pornește
în conversația dedicată, cu selecția de model a conversației sau implicitul
furnizorului `zivacode`. Nicio permisiune și niciun răspuns la întrebări nu
sunt aprobate automat: starea `ziva_permission_required` /
`ziva_question_required` se întoarce cu `job_id`, iar sarcina continuă în
fundal. Limite: 30–1800 secunde per apel, maximum 4 sarcini simultane, jurnalul
în memorie ține 24 de sarcini și 30 de minute după terminare; o repornire a
aplicației pierde jocurile. După un răspuns Ziva cu unelte executate, harta
proiectului, diagnosticile și verificarea noastră sunt marcate învechite, fiindcă
Ziva editează aceleași fișiere prin uneltele ei.

Contractul RPC a fost stabilit pe pachetul v3.3.2 (`chats/create`,
`chats/sendPrompt`, `chats/snapshot`, `plugin/bootstrap`, anvelopa oRPC
`{"json": …}`), singura versiune probată cap-coadă pe dispozitiv; versiunea
fixată acum este v3.3.3, deci reutilizarea lui cere o nouă probă de delegare.
Contractul poate diferi între versiuni; erorile sunt raportate explicit,
fără reîncercări ascunse. Verificarea de până acum este statică (schema din
bundle-ul oficial), plus fixture-ul Godot cu un bridge simulat: 8 verificări
noi pentru delegare, tăierea răspunsului, permisiune și anulare. Pe dispozitiv,
cu APK-ul `ziva-preview` din `d5105508`, o sarcină reală a mers cap-coadă:
job `901939ee-c535-4606-8393-b1673f439c0c`, `completed`, răspuns „PONG” în
~3,4 s, fără unelte. Snapshotul sidecarului confirmă conversația dedicată
`chat_e6f8261c1ffel4nzFv4HtWuA8i` („Godot AI”) și legătura `parentId`
întrebare→răspuns; partea `<additional_context>` injectată de Ziva este
`synthetic`, deci potrivirea exactă a promptului din `findTurn` rămâne validă.
Fluxul permisiunii (întrebare în tabul Ziva → `ziva_task_poll`) rămâne de
probat separat pe dispozitiv.

## Conversație compactă, focus și addonuri — 30.10.2026

Implementare în surse pentru distribuția Ziva Preview. Frontend-ul oficial
rămâne separat de harness-ul agentului nostru. Un adaptor original al gazdei
(`assets/ai/ziva-mobile.js`) se aplică numai originii locale Ziva, fără bridge
JavaScript privilegiat și fără modificarea pachetului oficial.

Pe ferestre înguste (≤760 px CSS) sau joase (≤500 px CSS), bara de sus rămâne
pe un rând cu derulare orizontală. Panourile suplimentare se restrâng sub
**Detalii**; composerul și zona cu notificări/todo au înălțimi limitate, iar
textul lung se derulează în câmp. Setările, selectorii, trimiterea și aprobările
rămân accesibile. Ecranele mai mari păstrează dispunerea oficială. Adaptorul
urmărește schimbările DOM din navigarea SPA; nu recreează conversația.

Focusul programatic pe câmpuri text nu mai este suficient pentru a cere
tastatura. Atingerea explicită a câmpului/etichetei, activarea accesibilă și
navigarea cu Tab permit editarea. Trimite, Setări și ascunderea tabului șterg
intenția de editare. Gazda Android ascunde IME după o atingere care nu a selectat
un câmp; evenimentele de atingere continuă către frontend. Aceste mecanisme
necesită și verificare fizică pe WebView/IME Android.

`AIZivaProjectContext` inventariază `plugin.cfg` și `.gdextension` din addonurile
proiectului salvat, inclusiv cele dezactivate. Datele separă **instalat**,
**activat în project.godot**, **bibliotecă Linux ARM64 prezentă** și **încărcare
verificată**; prezența unui `.so` nu confirmă încărcarea lui. Scanarea este
limitată și marchează rezultatele parțiale; legăturile din afara proiectului
nu sunt urmărite. Metadatele nu devin instrucțiuni executabile.

Inventarul se montează la `/root/.agents/godot-ai-addons.json`, iar un context
scurt în `/root/.agents/AGENTS.md`, descoperit de mecanismul oficial implicit
al Ziva. Instrucțiunile globale existente sunt păstrate înaintea contextului;
`AGENTS.md`, `project.godot` și addonurile proiectului nu sunt suprascrise.
Conținutul administrat este privat sesiunii și se actualizează la aproximativ
6 secunde, fără repornirea unui agent activ. Dacă utilizatorul a dezactivat
în Ziva descoperirea instrucțiunilor globale, acestea nu se forțează; inventarul
rămâne citibil explicit. O conversație veche poate necesita un tur nou pentru
recitirea contextului.

Terrain3D instalat pentru Android poate să nu includă biblioteca Linux ARM64
folosită de editorul separat. Inventarul permite recunoașterea addonului și
raportarea incompatibilității reale; nu compilează automat acea bibliotecă
și nu face API-ul nativ Terrain3D disponibil în Linux.

Probe și limite: `.ai-qa/ziva-mobile-20261030/`. Compilarea Kotlin focalizată și
suita companion au trecut; testele DOM simulează gesturile și focusul.
O probă MCP în backend-ul oficial Ziva v3.3.2/Godot Linux a citit inventarul,
instrucțiunile gazdei și originalul proiectului, inclusiv cu un addon fixture
Terrain3D și biblioteca lipsă. Actualizarea inventarului în același backend
a fost verificată după adăugarea unui addon. Nu este o probă de conversație/model real sau de tastatură
Android. Randarea nu a fost validată: Chromium și headless-shell se închid cu SIGTRAP
în PRoot. ADB nu are dispozitive conectate. Raportul complet este în
`.ai-qa/ziva-mobile-20261030/verification.json`.
Nu s-a recompilat, instalat sau înlocuit APK-ul; nu s-a făcut push.

## Adaptarea la telefon și la redimensionare — 29.10.2026

Tabul Ziva folosește automat zona de lucru extinsă, cu panourile Godot
restaurate la ieșire. Bara compactă păstrează numai starea, pornirea și meniul
`⋮` (Reîncarcă interfața, Configurare, Verifică starea, Oprește Ziva).
Instrucțiunile de instalare nu ocupă spațiul frontend-ului după pornire.
Meniurile native ascund temporar WebView-ul; o reîncărcare cerută din meniu
se aplică după închiderea lui. Interfața oficială nu este rescrisă. WebView-ul respectă viewport-ul mobil,
permite zoom prin gest fără controale suprapuse și păstrează navigările interne
în aceeași interfață. Dialogurile, istoricul și setările sunt cele oficiale,
nu replici native; verificarea fizică a tuturor fluxurilor rămâne separată.

Sursa `0fc625a9` a trecut CI 40884020493: 751/0 runtime, 773/0 × 5 upstream,
803/0 × 5 nativ, 72/0 Ziva focalizat, 68/0 manager nativ și cele 9 teste companion.
APK-ul separat verificat (112.467.916 bytes) este în Download; instalatorul standard
a rămas intact. Noua versiune nu s-a instalat automat.
Capturile fizice primite arată pagina oficială de autentificare în APK-ul
anterior, după instalarea bibliotecilor lipsă. ADB a fost deconectat de utilizator;
dispunerea nouă și oprirea completă a proceselor necesită proba noului APK. Nu s-a efectuat autentificarea
și nu s-a trimis niciun prompt către un furnizor plătit.

## Corecția runtime-ului minimal — 29.10.2026

Prima probă pe telefon a găsit biblioteci lipsă (`libxcb`, fontconfig și
bibliotecile CEF) în Debian slim. Serverul nu pornea, deci tabul rămânea gol.
Corecția verifică `ldd` pe extensia oficială și fontconfig, instalează pachetele
Debian necesare și verifică din nou încărcarea. Se aplică și la pornirea unei
instalări existente. Descărcarea suplimentară măsurată pe baza livrată este de
aproximativ 56 MB, cu aproximativ 245 MB ocupați după instalare.
Configurația DNS este actualizată când rețeaua Android se schimbă. Depozitul
Debian este rezolvat prin Android înainte de instalări; blocul administrat din
`/etc/hosts` se actualizează și păstrează celelalte intrări.
Proba din Debian-ul de dezvoltare nu înlocuiește verificarea acestei baze minimale.

## Tab principal Ziva — 29.10.2026

Ziva are propriul tab de sus, lângă **AI Assistant**, atât în editor, cât și
în managerul de proiecte. Tabul folosește interfața web oficială integrală,
fără rescrierea frontend-ului și fără acces la cheile, mesajele sau uneltele
agentului nostru. Backend-ul rămâne pluginul oficial într-un editor Godot Linux
ARM64 separat, sub PRoot, pe fișierele proiectului ales.

WebView-ul este atașat în interiorul tabului și se ascunde când tabul devine
invizibil sau apare o fereastră Godot. Starea frontend-ului se păstrează între
schimbările de tab; doar **Reîncarcă** reîncarcă pagina. Încadrarea se raportează
la suprafața Godot și se actualizează la redimensionare, rotație și tastatură.
Autentificarea HTTPS se deschide în browserul Android; selecția fișierelor
folosește selectorul sistemului. Nu se injectează un bridge JavaScript nativ.

**Configurare** deschide setările de instalare, reparare și Runtime Linux.
În lista de proiecte se poate instala Ziva; pornirea cere un proiect deschis.
Un backend asociat altui proiect nu poate fi afișat în tabul curent. Închiderea
tabului nu oprește backend-ul; **Oprește** îl oprește explicit.

Validarea Android a WebView-ului, autentificării, selectorului de fișiere,
tastaturii și unei sarcini Ziva reale rămâne necesară pe dispozitiv. Testele
Godot cu backend simulat verifică plasarea, ascunderea, reluarea și separarea
stării, nu frontend-ul proprietar sau un furnizor real.

Ziva are propria secțiune în setări, propria interfață web oficială, proces,
autentificare și date. Mesajele, cheile și modelul Ziva nu trec prin harness-ul
nostru. Varianta curentă rulează **pluginul oficial Ziva v3.3.3 într-un editor
Godot Linux separat, headless**, iar editorul Android și agentul nostru continuă
în paralel. Integrarea rămâne experimentală: verificarea pe dispozitiv și un tur complet
cu model real sunt încă necesare. Livrarea APK-ului este consemnată în
`PROGRES_SI_PLAN.md`.

## De ce un editor separat

Pluginul oficial este o extensie GDExtension Linux ARM64 (glibc), cu server,
interfață și CEF proprii. Editorul Android nu poate încărca o bibliotecă glibc
într-un proces Bionic și nu există un binar Android al pluginului. Fluxul ales:

1. La cerere, aplicația descarcă cele două arhive oficiale v3.3.3 — addon-ul
   GDExtension și runtime-ul CEF, publicate separat începând cu v3.3.3 — și
   Godot 4.7.2 Linux ARM64 din release-urile oficiale.
2. Serviciul Android pornește Godot-ul oficial headless pe proiect, sub PRoot,
   cu addon-ul montat în `/workspace/addons/ziva_agent`.
3. Pluginul își pornește serverul și interfața oficială pe `127.0.0.1`, în
   intervalul 7012–7041.
4. Fereastra WebView afișează interfața oficială; editorul Android rămâne activ
   și agentul nostru își păstrează executorul nativ.

Procesele, datele și autentificarea sunt separate. Ziva nu primește prompturi,
profiluri sau chei ale agentului nostru, iar harness-ul nostru nu primește
conversațiile sau cheile Ziva. Ziva lucrează cu propriile unelte în editorul ei
headless; nu controlează editorul Android și nu vede starea lui nesalvată.
Agentul nostru nu folosește furnizorul sau uneltele Ziva.

## Pachet Android separat

Utilizatorul a cerut compilarea ulterioară a unui pachet care păstrează aplicația
actuală. Se folosește proprietatea Gradle explicită:

```sh
cd platform/android/java
./gradlew :editor:assembleAndroidDebug -PgodotAiDistribution=ziva-preview
```

Compilarea bibliotecii Godot ARM64 și pregătirea SDK/NDK rămân cele din fluxul
normal al repository-ului. Proprietatea nu compilează singură motorul nativ.

| Distribuție | Application ID debug | Nume |
| --- | --- | --- |
| implicită / `standard` | `com.jdscript.godotai.debug` | Godot AI |
| `ziva-preview` | `com.jdscript.godotai.ziva.debug` | Godot AI Ziva |

Ambele se pot instala în paralel și au date Android separate. Furnizorii salvați
în aplicația existentă nu se migrează automat. Distribuția implicită nu permite
pornirea sau instalarea componentei Ziva. Workflow-ul Android are selectorul
`distribution`; push-ul păstrează implicit `standard`. Pentru livrare se
transmite `--distribution ziva-preview` către
`misc/scripts/deliver_ai_android.py`. Cele două distribuții nu își curăță
reciproc instalatoarele sau checksum-urile din Download.

## Instalarea la cerere

APK-ul nu include binare, CEF sau interfața proprietară Ziva; totul se descarcă
la instalare, direct de la furnizor. Ambele descărcări sunt opționale și sunt
verificate înainte de activare.

| Componentă | Arhivă | SHA-256 arhivă | Conținut verificat |
| --- | --- | --- | --- |
| Ziva v3.3.3 addon Linux ARM64 | 2.944.465 bytes | `1e06bcef313aa092393ea64e4a10202f3077ec5fba223dfd7d42525fec6027c4` | GDExtension, manifestul și licența |
| Ziva v3.3.3 runtime Linux ARM64 | 224.410.556 bytes | `f485f3b0f381fe4ec40b10788f0af62bea487c94ec6d830ec811c09f24f32b39` | `zivacode` 136.039.416 bytes, `db476a4bfe636760fe7838c5bea1f9ec421a23dfb4daa16c73a8494a17da5cb6`; CEF, locale, helper |
| Godot 4.7.2 Linux ARM64 | 77.008.699 bytes | `5dd0d86405cf7e8adf79fb6377b38ba682a2846cb378ffe5364f38c01ad29b9d` | executabil 137.953.888 bytes, `3fcb80f4fe794e3859360eb641d8c41d8ffe2c2e54ba1981e55a76851d5ed1f4` |

Din arhiva addon-ului se extrage numai subarborele `addons/ziva_agent/`;
arhiva runtime este înrădăcinată direct în acel director (`bin/`,
`bin-deps/`, `zivacode/`), deci cele două se suprapun în aceeași instalare.
Rezultatul verificat local are 247 de fișiere și 545.460.656 bytes.
Instalatorul verifică dimensiunea și SHA-256 pentru fiecare arhivă, limitează
fiecare fișier la 320 MiB, totalul la 768 MiB și numărul la 4000, refuză căile
`..`/absolute/duplicate și legăturile simbolice și acordă drept de execuție
pentru `bin/`, `bin-deps/` și `zivacode/`. Instalarea se face în staging, se
validează, apoi se activează printr-o redenumire atomică; instalarea anterioară
este păstrată până la succes, iar un eșec nu atinge datele Ziva.

Godot se extrage dintr-un singur membru fix al arhivei oficiale, cu hash și
dimensiune verificate, apoi primește drept de execuție. Ambele instalatoare
refuză un root simbolic, o versiune care iese din director și spațiul insuficient.
Cerința de spațiu acoperă arhivele, conținutul dezarhivat, o eventuală instalare
veche păstrată temporar și o marjă; în practică sunt necesari aproximativ 1,1 GB
la instalare. Descărcările sunt de circa 305 MB.

După instalare, la fiecare proiect, serviciul copiază conținutul runtime-ului
verificat în directorul privat `user://ziva/runtime/v3.3.3` al proiectului, ca
extensia să nu îl descarce singură; hardlink-ul evită în mod normal spațiul
suplimentar, iar dacă sistemul îl refuză rămâne o copie de circa 535 MB.
Serviciul rulează `zivacode --version` și `godot --version` prin
PRoot; instalarea este confirmată numai pentru `v3.3.3`, respectiv
`4.7.2.stable`. Binarele ajung sub
`/opt/godot-tools/ziva/v3.3.3/addons/ziva_agent/` și
`/opt/godot-tools/godot/4.7.2/godot` în filesystem-ul Linux al aplicației.
Un `active.json` vechi (de exemplu v3.3.2) nu blochează migrarea: versiunea
fixată în aplicație are prioritate când este mai nouă, iar instalarea veche
rămâne neatinsă până la o activare reușită.

Licența Ziva este proprietară. Descărcarea opțională nu acordă drepturi de
redistribuire a binarului într-un APK; pentru o distribuție care îl include este
necesară autorizarea furnizorului.

## Pornirea editorului oficial

`AIZivaService` rulează într-un proces Android separat, cu notificare și oprire
explicită. La pornire:

- verifică ambele pachete și proiectul canonic (`project.godot`, cale absolută);
- refuză pornirea dacă un server Ziva răspunde deja pe unul dintre porturi;
- creează directoare private pe proiect pentru `local-share`, `cache`, `config`
  și pentru cache-ul Godot `.godot`, ca cele două editoare să nu împartă
  cache-ul de import;
- montează proiectul în `/workspace` și addon-ul în
  `/workspace/addons/ziva_agent`;
- pregătește `user://ziva/runtime/v3.3.3` direct din overlay-ul verificat al
  addon-ului, cu `.ready` egal cu SHA-256-ul arhivei runtime. Extensia v3.3.3
  nu citește runtime-ul din directorul addon-ului și ar descărca singură cele
  224 MB, imposibil de terminat în limita de pornire. Seeding-ul este atomic și
  idempotent; folosește hardlink când sistemul îl permite, altfel copie, și
  șterge descărcările parțiale rămase;
- lansează Godot-ul oficial cu `--headless --editor --path /workspace`, cu
  `ZIVA_ENABLE_HEADLESS=1` și `ZIVA_AUTOUPDATE_DRY_RUN=1` (updater-ul oficial
  raportează actualizările fără să modifice fișiere; versiunea o administrează
  wrapper-ul).

Pornirea este declarată reușită numai după trei probe: răspuns HTML 200 pentru
interfață, handshake MCP cu identitatea `ziva-godot` la versiunea pachetului
instalat (acum v3.3.3) și un apel de citire `tools/call get_project_info` cu
rezultat nevid. Abia atunci serviciul
publică portul în `state.json` și permite deschiderea ferestrei. Limita de
pornire este de 180 secunde; primul import poate fi lent, dar runtime-ul deja
pregătit nu mai consumă timpul cu o descărcare în fundal. Un heartbeat verifică
interfața la fiecare 2 secunde și oprește sesiunea după 30 de eșecuri
consecutive sau când editorul se închide. Ultimele 128 KB din ieșirea editorului
rămân în `ai-ziva/projects/<project-id>/godot.log`.

Oprirea din notificare sau din panou scrie un fișier privat de anulare, termină
întâi procesul Godot identificat din cache-ul privat al sesiunii; PRoot poate
închide apoi procesele secundare, iar datele proiectului se păstrează. Android poate opri serviciul
`dataSync`, inclusiv la limitele platformei; aplicația nu promite execuție
nelimitată și afișează starea întreruptă la următoarea citire.

## Interfața în WebView

WebView-ul este un copil nativ al activității Android, ancorat exclusiv în corpul
tabului Ziva. Nu deschide o altă Activity și nu suspendă editorul Android.
Încarcă `http://127.0.0.1:<port>/` cu JavaScript și DOM storage; navigarea rămâne
pe același host și port, iar linkurile HTTPS externe și popup-urile cerute de
utilizator se deschid în browser. Nu se injectează un bridge JavaScript
privilegiat și nu se reproduce protocolul privat CEF. La schimbarea tabului,
WebView-ul se ascunde și păstrează pagina; **Reîncarcă** este explicit. La
schimbarea activității sau închiderea aplicației se eliberează vizualizarea.

Selectorul de fișiere folosește `onShowFileChooser` și rezultatul Android.
Încadrarea urmărește suprafața Godot și zona vizibilă, inclusiv tastatura;
aceste comportamente sunt implementate și compilate, dar necesită test fizic.

## Controalele din panoul nostru

`ziva.gd` face controlul `install`, `start`, `stop` și afișarea `embed`.
Butonul din setări deschide tabul principal; nu mai lansează un Dialog.
Panoul arată instalarea (`~305 MB` descărcați), spațiul total de aproximativ
1,1 GB și faptul că backend-ul rulează într-un editor separat. WebView-ul se afișează
numai când serviciul raportează un port valid pentru proiectul curent.
Oprirea readuce controlul de pornire, iar o eroare de pachet oferă repararea
fără ștergerea istoricului. Controalele Ziva nu modifică istoricul sau
profilurile agentului nostru.

## Ce s-a eliminat

Varianta anterioară încerca să conecteze Ziva la editorul Android printr-o
punte MCP proprie (`editor_mcp.gd`), cu token în `.mcp.json` și un fallback
«Copiază conexiunea». Soluția a fost eliminată, împreună cu
`AIZivaMcpConfig`, testele ei și starea `editor_connected`: interfața oficială
rulează acum în propriul editor și își folosește propriile unelte native, deci
puntea era un al doilea traseu de control, neverificat, fără beneficiu. Panoul
nu mai oferă «connect», token sau configurație MCP.

## Verificări și limite

Proba separată, în Debian/PRoot, a folosit exact montările serviciului: addon-ul
oficial complet montat peste `/workspace/addons/ziva_agent`, cache `.godot` și
directoare XDG private. A confirmat interfața HTML la `127.0.0.1:7012`,
identitatea MCP `ziva-godot` v3.3.2 (versiunea de atunci) și apelul de citire
`get_project_info` fără inițializare prealabilă. Proiectul gazdă a rămas
nemodificat, iar CEF nu a fost inițializat în modul headless. Această probă nu
este rularea din APK și nu acoperă v3.3.3. Proba AG-78, cu proiect minimal sub
PRoot pe telefon și runtime-ul pregătit manual, a eliminat descărcarea (niciun
`ZIVA_RUNTIME event=download_start`) și a adus sidecarul la `listening on port
7012`; nici ea nu a rulat serviciul Android.

APK-ul AG-78 (snapshot `0fd54fba`, CI 41251258293) a fost instalat cu
`adb install -r` peste aplicația existentă, cu datele păstrate, iar seed-ul
manual folosit la diagnoză a fost șters înainte de probă. Aplicația a recreat
singură `user://ziva/runtime/v3.3.3` cu 236 de fișiere și 534.671.202 bytes,
plus `.ready` de 64 bytes egal cu SHA-256-ul runtime-ului; hardlink-ul a fost
refuzat, deci s-a folosit copia de rezervă. Sesiunea a pornit automat și a ajuns
`running` pe portul 7012, cu interfața HTTP 200, tabul Ziva randat, sidecarul
`listening on port 7012` și `health check passed`, fără niciun
`ZIVA_RUNTIME event=download_start` nou. Nu s-a trimis niciun prompt de model.
Date: `.ai-qa/compile-ziva-333-runtime-seed-20261031T230816Z/`.

Testele Kotlin acoperă instalatoarele: 58/0 pentru pachetul Ziva (inclusiv
perechile addon+runtime din actualizări, 18/0, seeding-ul runtime-ului și
markerul de terminare) și 34/0 pentru contextul de proiect (inclusiv derivarea
directorului `user://`), plus 19/0 pentru Godot, cu refuzul
căilor nesigure, hash-urilor greșite, anulării și păstrarea instalării
anterioare. Clasele reale au extras arhivele oficiale v3.3.3: 247 de fișiere și
545.460.656 bytes pentru addon+runtime (`zivacode` 136.039.416 bytes, hash
`db476a4bfe636760fe7838c5bea1f9ec421a23dfb4daa16c73a8494a17da5cb6`) și Godot
137.953.888 bytes, ambele cu drept de execuție. Fixture-ul Godot verifică panoul și independența față de
istoricul/profilurile agentului: 55/0. Regresia runtime a trecut 750/0, iar
regresia completă a editorului pe aspectul îngust a trecut **756/0** (exit 0,
`editor-report.json`). Compilarea Kotlin împotriva SDK Android nu reprezintă o
compilare APK.

Dovezi locale: `.ai-qa/full-final/narrow/` (raportul regresiei complete),
`.ai-qa/ziva-final/narrow/` (captură și raport focalizat),
`.ai-qa/ziva-native/` (loguri Kotlin, `ZivaLiveInstallTest.kt`) și
`.ai-qa/ziva-native/runtime-final.log`.

Varianta separată `234893bf` a fost compilată și livrată în Download la
29.10.2026, după CI 40870748187: runtime 751/0, upstream 768/0 × 5,
nativ 792/0 × 5, Ziva focalizat 67/0 și manager nativ 68/0. S-au verificat
semnătura, identificatorul separat, toate cele 37 de scripturi și pachetul
Linux. Dovezi: `.ai-qa/compile-ziva-tab-20261029T115729Z/`.

Proba fizică din 29.10.2026 a găsit lipsuri în Debian slim. După instalarea
bibliotecilor, `ldd` nu mai raportează lipsuri, iar capturile utilizatorului arată
pagina oficială de autentificare. Instalarea prin serviciu a expirat la descărcare;
pachetele au fost finalizate în același runtime al aplicației cu rezolvarea
depozitului pregătită explicit. Sursele finale automatizează această rezolvare.
Rămân de verificat pe noul APK: toate ecranele și gesturile interfeței, autentificarea,
selectorul fișierelor, tastatura, descărcările, un tur complet prompt → răspuns →
unealtă cu un furnizor real și comportamentul serviciului sub politicile Android.
Ziva nu accesează imaginile sau mesh-urile private din chatul agentului nostru.

Limitări de proiectare: cele două editoare partajează fișierele proiectului,
deci editările simultane se pot suprascrie; Ziva vede propria stare de editor,
nu modificările nesalvate din editorul Android, și invers. PRoot nu constituie
o izolare de securitate. Instalarea consumă aproximativ 1,1 GB și necesită
rețea; Android poate opri serviciul în fundal. Actualizarea este controlată de
aplicație, nu de updater-ul din editorul oficial: acesta din urmă nu poate
reporni sesiunea headless sub PRoot, deci rulează în modul de probă fără
modificări de fișiere.

Surse: [instalare oficială](https://ziva.sh/docs/installation),
[release v3.3.3](https://github.com/ziva-sh/ziva-agent-plugin-godot/releases/tag/v3.3.3),
[Godot 4.7.2 Linux ARM64](https://github.com/godotengine/godot/releases/tag/4.7.2-stable),
[condiții Ziva](https://ziva.sh/terms).


### Microfon și tastatură Android (AG-69)

Gazda tratează `WebChromeClient.onPermissionRequest` prin permisiunea Android
comună cu dictarea nativă. Acordă exclusiv `RESOURCE_AUDIO_CAPTURE` originii
`http://127.0.0.1:<portul UI activ>` cât tabul propriu este vizibil; resursele
video sau alte origini nu primesc permisiune. Ascunderea, navigarea și fundalul
eliberează fluxurile audio, inclusiv cele care devin disponibile după anulare.
Transcrierea și cheile oficiale Ziva rămân în backend-ul său separat.

Adaptorul nu înlocuiește funcția DOM `focus()` și nu folosește ascundere IME
întârziată după orice atingere. Editarea poate supraviețui unei înlocuiri de
nod Lexical, iar compoziția nu schimbă textul prin codul gazdei. Inițializarea,
Trimite/Setări și ascunderea tabului nu autorizează singure tastatura.
Probele DOM sunt simulate; textul/cursorul și microfonul real necesită testul
APK-ului pe dispozitiv. Implementarea oficială Ziva nu este modificată.
