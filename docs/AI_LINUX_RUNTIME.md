# Runtime Linux integrat în aplicație

Stare: **compilat în APK și livrat, 25.10.2026**, sursa `8878801`.
Installerul din Downloads a fost înlocuit după verificarea semnăturii și a
conținutului. Pornirea fizică a serviciului din aplicația Godot instalată
rămâne de verificat; probele de dezvoltare nu o înlocuiesc.

## Funcționare

Linux este o componentă de bază: la pornirea asistentului, inclusiv în lista
de proiecte, aplicația pregătește automat în stocarea privată pachetul Debian
ARM64 inclus în build. După pornirea și verificarea shell-ului prin PRoot,
în **Integrări → Runtime Linux** apare **Linux activ**. Nu există butoane
pentru instalarea sau dezinstalarea manuală a bazei; **Repară** apare când
verificarea nu a reușit. Verificarea ulterioară păstrează pachetele instalate.
Nu sunt necesare Termux, copierea comenzilor sau o aplicație companion.

Utilitare opționale: **Python**, **Node.js și npm**, **Git** și **ripgrep**.
Ele se pregătesc din pachetele semnate din APK la acțiunea explicită; nu se
descarcă din depozite Debian. Python/Git/ripgrep vin din repository-ul Debian
offline, iar Node.js/npm din runtime-ul Node 22.19 inclus pentru Agent AI. Sunt
marcate pregătite după verificarea executabilului. Baza Linux este verificată
înaintea activării comenzilor agentului.

**Blender CLI 4.3.2** nu mai este un utilitar opțional descărcat: pachetele
Debian ARM64 și dependențele sale sunt în arhiva offline din APK. Integrări →
Blender sau `blender_prepare` le instalează local, fără Termux și fără rețea.
`blender_status` citește versiunea reală, iar `blender_run` execută un script
Python din proiect prin PRoot cu proiectul montat la `/workspace`. Pachetul este
mare (aproximativ 291 MB în arhiva de test și 800 MB adăugați la instalare),
astfel încât pregătirea inițială durează. Verificarea versiunii nu dovedește
singură randarea; probele GLB, render și import Godot sunt separate.

Probele locale din 3.11.2026 au instalat repository-ul offline cu `Need to get
0 B`, au randat Cycles CPU și au importat GLB-ul în Godot. Sunt dovezi pentru
lanțul Debian/PRoot/Blender, nu pentru APK-ul Android instalat.

Runtime-ul oferă o bază pentru CLI-uri și harness-uri bazate pe Node/Python.
Nu înlocuiește automat harness-ul existent al agentului. Autentificarea,
protocolul de mesaje/tool-uri și compatibilitatea fiecărui harness extern
necesită integrare și probe proprii. Nu există în această etapă un harness
extern instalat, autentificat și validat în Godot.

## Implementare

- `tools/embedded-runtime/rootfs.json` fixează sursa oficială
  [debuerreotype](https://github.com/debuerreotype/docker-debian-artifacts),
  commitul, arhitectura, dimensiunea și SHA-256 ale stratului Debian.
- `rootfs.py` produce ZIP-ul cu bytes regulați și un manifest pentru directoare,
  permisiuni și legături. Arhiva este verificată înainte de extracție; fiecare
  fișier este verificat individual. Nu se scrie prin legături create de arhivă.
- `AILinuxRuntimeFiles.kt` instalează în staging și publică directorul propriu,
  pornește executabilele PRoot/loader din `nativeLibraryDir`, apoi shell-ul și
  programele Linux. Nu folosește prefixul sau executabilele Termux.
- `AILinuxRuntimeService` este neexportat, în procesul `:ai_runtime`, cu serviciu
  Android foreground pentru operații lungi și buton de oprire în notificare.
- Joburile au stare atomică, jurnal limitat, heartbeat, timeout și anulare.
  O operație întreruptă nu este relansată automat. Instalările APT verifică
  rezultatul; o eroare nu devine succes doar fiindcă descărcarea s-a încheiat.
- JNI injectează proiectul real deschis; modelul nu alege directorul gazdă.
  Linux vede proiectul la `/workspace`. Comenzile primesc un mediu controlat,
  fără cheile furnizorilor AI copiate automat din seiful aplicației.
- `linux_status`, `linux_execute` și `linux_install_tool` folosesc catalogul și
  permisiunile existente. Execuția este o operație externă: modul Plan nu o
  autorizează. Instrumentele active sunt oferite numai după verificarea Linux.
- La trecerea din lista de proiecte în editor, pregătirea automată continuă
  în serviciu; noul panou urmărește jobul existent. Comenzile agentului nu
  sunt relansate automat. Dezinstalarea bazei rămâne doar o operație internă
  de dezvoltare; nu este expusă în interfață sau agentului.

PRoot este un mediu de compatibilitate, nu un sandbox de securitate sau o
mașină virtuală. Programele rulează cu permisiunile aplicației și kernelul
Android. Procesele daemon și CLI-urile interactive nu sunt transformate automat
în servicii MCP sau în adaptoare de agent prin această implementare.

## Pachetul de bază și build

Sursa: Debian trixie slim ARM64, commit
`9c4818e3bfd35139d3798b0420e9c46836658b2e`; strat gzip SHA-256
`ddc0c1e36a6793411b6c8d48e1ddad2987405d377da92bcf532ed3181c2e4d62`.
Pachetul rezultat are **32.789.398 bytes**, **104.455.032 bytes** de fișiere
regulate și **3.265 intrări**. Pachetele opționale ocupă spațiu suplimentar.

Gradle execută `rootfs.py` după buildul nativ PRoot. Sistemul de fișiere este
ambalat în assets, iar executabilele Android rămân în bibliotecile native
extrase de instalatorul Android. Rootfs-ul păstrează fișierele copyright ale
pachetelor. Livrarea efectivă a APK-ului și inventarul/sursele aferente
pachetelor distribuite trebuie verificate separat înaintea publicării.

## Dovezi și limite

- Kotlin: compilare reușită a managerului, serviciului și instalatorului cu
  clasele Android, urmată de compilarea completă APK/Gradle în workflow.
- C++: verificare de sintaxă pentru puntea JNI și înregistrarea modulului.
- Teste de arhivă: 4 teste Python, plus 6 cazuri executate împotriva
  instalatorului Kotlin, inclusiv traversări și legături nepermise.
- Godot: 429 aserțiuni runtime, 438 verificări pe editorul nativ compilat la
  fiecare dintre cinci dimensiuni și 49 verificări focalizate pe runtime la
  fiecare dintre două dimensiuni. Interfața a fost inspectată vizual;
  puntea Android este simulată în fixture.
- APK: verificată semnătura persistentă, cele 28 de scripturi AI exacte,
  clasele serviciului, ELF-urile native și toate cele 2.678 de fișiere regulate
  din baza Debian. Installer livrat: 112.268.670 bytes, SHA-256
  `31593a24142a4f7be279057b127d01a0cba1e9e1ba639d2b8be1bf73f3912050`.
- Probă reală de dezvoltare: instalarea pachetului de bază și a Python
  3.13.5, Node 20.19.2, Git 2.47.3, ripgrep 14.1.1 într-un filesystem nou,
  separat de containerul Debian existent al utilizatorului. Au trecut
  execuția prin directorul proiectului, fișierul scris, limitarea ieșirii,
  timeout-ul și anularea.
- PRoot-ul compilat din sursele noastre a pornit aceleași patru utilitare
  în proba de control. Pentru această probă a fost folosit loader-ul deja
  ambalat al Termux; nu este dovada loader-ului nou din APK-ul Godot.

Dovezi locale: `.ai-qa/linux-runtime-package/`,
`.ai-qa/linux-runtime-kotlin.log`, `.ai-qa/linux-runtime-cpp.log`,
`.ai-qa/linux-runtime-godot.log`, `.ai-qa/linux-runtime-ui/`,
`.ai-qa/linux-runtime-narrow/`, `.ai-qa/linux-runtime-full/`,
`.ai-qa/linux-runtime-tools.log`, `.ai-qa/linux-runtime-execute.log`,
`.ai-qa/linux-runtime-custom-proot.log`, `.ai-qa/linux-runtime-custom-execute.log`,
`.ai-qa/linux-runtime-verification.json` și
`.ai-qa/linux-runtime-control/smoke-result.json`.

Urmează proba fizică în APK cu propriul loader, foreground service, instalare,
oprire și reluare după trecerea aplicației în fundal. Blender complet și un
harness extern sunt probe distincte. Dovada primei livrări cu Linux automat este
`.ai-qa/delivery-8878801.json`; verificarea pachetului este în
`.ai-qa/artifacts/8878801/linux-verification.json`.
