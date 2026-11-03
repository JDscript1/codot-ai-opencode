# Runtime Blender în aplicația Android

Ținta este un Blender CLI utilizabil de agent fără instalarea aplicației Termux și fără comenzi lipite de utilizator. Harness-ul AI rămâne în Godot; serviciul nativ este doar backend-ul opțional pentru modelare, export și randare.

## Starea curentă a surselor — 3.11.2026

Blender 4.3.2 ARM64 și dependențele Debian sunt acum în arhiva offline din APK,
nu într-un pas de descărcare. Backend-ul `AILinuxRuntimeFiles` rulează Blender
prin PRoot-ul aplicației, montează proiectul la `/workspace`, folosește
`--background --factory-startup --disable-autoexec` și impune
`GODOT_AI_OUTPUT_DIR`. Integrări → Blender extrage pachetele local prin
`packages_update`; `blender_status`, `blender_prepare` și `blender_run` sunt
expuse Agent AI prin MCP. Fluxul Termux rămâne doar fallback istoric pentru
APK-uri fără runtime-ul Linux împachetat.

Detaliile mediului sunt în [Runtime Linux integrat](AI_LINUX_RUNTIME.md).
Compilarea APK, instalarea fizică și proba de randare/import în aplicația
instalată rămân dovezi separate; sursele și testele statice nu sunt prezentate
ca probă runtime.

**Probă locală 3.11.2026.** Repository-ul Debian offline cu 377 pachete a fost
instalat prin PRoot fără rețea (`Need to get 0 B`). Blender 4.3.2 a randat
Cycles CPU 64×64, a exportat GLB și `.blend`, iar Godot 4.7.2 ARM64 headless a
importat GLB-ul cu un mesh. Detaliile și hash-urile sunt în
[Blender inclus în APK](BLENDER_BUNDLE.md). Proba nu acoperă APK-ul instalat,
Agent AI live, Eevee/GPU sau performanța pe telefon.

## Etapa 1: proba de executare

Editorul construiește un executabil PIE ARM64 foarte mic (`ai_runtime_probe.c`) cu NDK și îl include în APK sub `lib/arm64-v8a/libai_runtime_probe.so`. Android îl extrage în directorul bibliotecilor native. Serviciul neexportat `AIEmbeddedRuntimeService` rulează în procesul aplicației `:ai_runtime`, pornește numai acel fișier cunoscut, așteaptă cel mult opt secunde și întoarce rezultatul printr-un receiver neexportat. Puntea Godot acceptă intern `embedded_probe` și `embedded_status` pentru diagnostic. Aceasta verifică mecanismul de proces, izolare și executare; **nu instalează și nu pornește încă PRoot sau Blender**.

Proba nu cere acces la Termux, stocare partajată sau rețea. Modulul nu primește o comandă arbitrară de la model. CI a compilat un APK cu proba, dar pornirea ei din procesul separat din acel APK nu a fost încă verificată fizic. APK-ul existent din Downloads rămâne pe implementarea Termux până la o probă Android a noii căi.

[Workflow-ul `40185968028`](https://github.com/JDscript1/godot-ai-android/actions/runs/40185968028) a trecut toate cele trei joburi. Artefactul `db550ea` conține proba ELF AArch64/PIE de 4.800 bytes; manifestul compilat declară `android:extractNativeLibs=true`, serviciul `:ai_runtime` și receiver-ul, ambele neexportate. APK-ul are aceeași semnătură de dezvoltare ca versiunea din Downloads. Binarul extras din artefact a fost executat separat în Termux pe dispozitiv, dar aceasta **nu** demonstrează încă executarea lui din directorul aplicației Godot.

## Următorii pași pentru un backend funcțional

1. Construim PRoot pentru ID-ul acestei aplicații și verificăm explicit că nu are `RUNPATH` sau prefix `com.termux`. Nu copiem binarul Termux: cel inspectat are `RUNPATH=/data/data/com.termux/files/usr/lib` și conține și căi fixe pentru `libproot-loader.so` și fișiere temporare. Depinde de `libtalloc.so.2` și `libandroid-shmem.so`. Doar schimbarea `RUNPATH` nu rezolvă aceste căi.
2. Pregătim un rootfs ARM64 reproducibil cu Blender CLI și dependențele sale, cu manifest de versiuni, hash-uri și licențe. PRoot-Distro poate ajuta la pregătirea imaginii, dar nu trebuie să fie un manager de pachete activ în fiecare pornire.
3. Împărțim pachetul în componente verificabile la instalare. Executabilul native rămâne în zona permisă pentru execuție; datele rootfs și proiectele stau în stocarea privată a aplicației. Verificăm spațiul necesar înainte de instalare și nu descărcăm sau extragem pachete în tăcere.
4. Pornim Blender din serviciul separat, cu joburi limitate, anulare, jurnal, import GLB în Godot și verificarea unui mesh real. Abia după o probă fizică în APK mutăm butonul **Instalează Blender** la noul backend și eliminăm fluxul Termux.

Licențele PRoot/PRoot-Distro și Blender, sursele corespunzătoare și notele de distribuție trebuie incluse/verificate înainte de livrarea unui APK care le conține. Dimensiunea finală a pachetului și compatibilitatea Blender pe Android rămân de măsurat.

## Etapa 2: PRoot propriu și probă Linux

`tools/embedded-runtime/build.py` construiește din surse verificate PRoot
5.1.107.101, talloc 2.5.0 și libandroid-shmem 0.7. Dependențele nesistem sunt
legate static în PRoot; loader-ul ARM64 este ambalat separat. Căile loader-ului
și fișierelor temporare sunt date la pornire, astfel încât același build poate
funcționa cu ID-ul debug sau release al aplicației. Nu instalăm Termux sau
PRoot-Distro în aplicație.

Gradle pregătește bibliotecile native, un program Linux minimal fără libc,
manifestul cu hash-uri și licențele. Sursele exacte și scriptul cu toate
modificările sunt păstrate în `corresponding-sources.tar.gz`. Serviciul verifică
hash-urile, extrage numai proba mică într-un director de cache propriu și rulează
mai întâi proba Android, apoi programul Linux prin PRoot. Nu acceptă comenzi sau
căi furnizate de model. La final, curăță doar directorul acelei probe.

Proba pornește automat la deschiderea procesului principal al editorului;
rezultatul este preluat în **Jurnal** la verificarea statusului din setări.
Rezultatele vechi sunt separate prin ID-ul probei, iar succesul Linux **nu**
activează uneltele Blender. În această etapă Blender nu este încă inclus.

Local: executabilul PRoot și loader-ul s-au compilat, cu numai biblioteci de
sistem în `DT_NEEDED`. Lansarea loader-ului din fișierele private a întors
`Permission denied`; SELinux etichetează acel fișier `app_data_file`, pe când
loader-ul ambalat al Termux este `apk_data_file`. Este necesară proba cu fișierul
nou ambalat efectiv în APK. Nici PRoot-ul instalat, nici containerul Debian al
utilizatorului nu au fost modificate.

**APK experimental:** `644a3b0`, [CI `40193820909`](https://github.com/JDscript1/godot-ai-android/actions/runs/40193820909),
toate joburile trecute. A fost retras din Downloads după raportul utilizatorului
că lipsesc Agent, Asset Store și alte elemente ale editorului. În Downloads
este restaurat `5baf890`; artefactul experimental rămâne în
`.ai-qa/artifacts/644a3b0/`. Hash-urile native, semnătura, scripturile încorporate și
arhiva surselor au fost verificate independent local. Acest APK rulează automat
proba la deschiderea editorului; deschide un proiect, apoi **Agent → Setări →
Jurnal** și verifică rezultatul după aproximativ 20 de secunde. Rezultatul
`Runtime integrat verificat: proces Android separat și program Linux ARM64.`
este următorul prag necesar înaintea pachetului Blender complet. Instalarea și
proba fizică nu au fost executate de agent.

Captura fizică primită ulterior (`Screenshot_20261025_171509.jpg`) prezintă
managerul de proiecte gol din `5baf890`, cu Asset Store vizibil. Agentul apare
în editor după deschiderea unui proiect; această captură nu dovedește o regresie
a editorului în buildul experimental. Verificarea PRoot rămâne în așteptare.
