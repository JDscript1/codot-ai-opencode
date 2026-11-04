# Blender în Integrări, prin Termux

> **Legacy / fallback.** În sursele curente, Blender 4.3.2 este inclus în APK
> și rulează prin runtime-ul Linux al aplicației. Documentul de față descrie
> conectorul Termux păstrat numai pentru APK-uri fără backend-ul bundled. Vezi
> [Blender inclus în APK](BLENDER_BUNDLE.md) pentru fluxul curent.

Inclus în APK-ul Android ARM64 `5baf890`, livrat la 25 octombrie 2026.
Clasele Android, permisiunea, intrarea JNI, cele 27 scripturi și worker-ul inclus
au fost verificate în pachet. Harness-ul AI rulează în Godot; Termux și Python
sunt dependențe numai ale integrării opționale Blender. Legătura Android prin
Intent și configurarea inițială trebuie verificate din aplicația instalată
înainte ca funcția să fie declarată validată pe dispozitiv.

## Configurare simplificată — 25 octombrie 2026

Această interfață este inclusă în APK-ul `5baf890`, cu verificări în editor și
surse incluse în pachet identice cu snapshot-ul compilat. Fluxul fizic Android
rămâne de confirmat după instalare.

Panoul Android conține statusul și un singur buton pentru etapa curentă:

1. **Instalează Termux**, dacă aplicația lipsește, deschide
   [Termux în Play Store](https://play.google.com/store/apps/details?id=com.termux).
   Dacă magazinul nu poate fi deschis, se folosește pagina sa web.
2. La revenire apare **Instalează Blender**. Acesta reutilizează Blender existent
   sau instalează Blender CLI într-un mediu Debian dedicat, apoi verifică exportul
   GLB și importul real în Godot. Agentul primește acces după verificare.
3. Panoul afișează **Blender Active**, cu **Dezinstalează Blender** dedesubt.
   Dezinstalarea elimină numai pachetul Blender. Termux, containerele, dependențele
   și fișierele generate sunt păstrate. O instalare care nu este gestionată de
   apt/dpkg sau a cărei eliminare ar afecta alte pachete este refuzată cu diagnostic.

Nu există bifa de activare separată, butoane Conectează/Verifică/Recuperează,
controale de permisiuni, reparare sau consolă în card. Progresul folosește statusul
mic, iar diagnosticul și ieșirea Blender se găsesc în pagina principală **Jurnal**.

### Pornirea prin Termux

Distribuția Play Store verificată nu oferă serviciul extern `RUN_COMMAND`; vezi
[manifestul distribuției](https://github.com/termux-play-store/termux-apps/blob/main/termux-app/src/main/AndroidManifest.xml).
**Instalează Blender** copiază comanda privată și deschide Termux. La prima
pornire, așteaptă inițializarea Termux, lipește comanda și apasă Enter, apoi revino
în Godot. Instalarea și verificarea continuă automat. Acest pas manual nu poate
fi înlocuit cu o solicitare de permisiune absentă din distribuție.

După proba pe dispozitiv în care comanda veche nu s-a putut lipi, APK-ul `5baf890`
folosește o **comandă scurtă**. Godot servește o singură dată conectorul inclus
în aplicație pe `127.0.0.1`, pentru maximum zece minute, printr-un URL aleator;
Termux îl preia și îl pornește. Comanda nu conține conectorul codificat și nu
expune tokenul către GDScript sau agent. Dacă transferul expiră, repetarea
butonului pregătește un URL nou. Corecția este inclusă în APK-ul din Download
livrat la 25 octombrie 2026, 09:49 CET; lipirea și instalarea fizică rămân de
verificat pe dispozitiv.

La reinstalare, conectorul încearcă întâi containerul Debian în care a verificat
anterior Blender, după un plan apt care nu elimină alte pachete. Dacă nu există
un astfel de container cunoscut, folosește mediul dedicat. Pachetul Blender nu
este inclus integral în APK: binarul și dependențele Linux necesită instalare
în mediul Termux, iar memoria privată a aplicației Android nu este accesibilă
direct de Termux. Aceasta păstrează APK-ul compact și evită o a doua descărcare
de imagine Debian pe dispozitive care au deja mediul verificat.

Pentru variantele cu `RUN_COMMAND`, aceeași acțiune solicită permisiunea Android
când este necesar și continuă după acordare. Dacă serviciul există, dar refuză
execuția externă, se folosește aceeași pornire prin copiere/lipire. Nu se adaugă
controale tehnice în panou și nu se modifică automat proprietățile Termux.

Operația cerută este salvată înainte de deschiderea Termux și poate continua după
redeschiderea editorului. Dacă un job există deja, este recuperat cu același ID.
Verificarea periodică nu instalează pachete fără o cerere explicită. O instalare
verificată este reutilizată fără o nouă sarcină. Dacă procesul Termux a fost oprit,
același buton de instalare îl reconectează și reutilizează Blender existent.

Un conector rămas pornit din versiunea veche nu primește o cerere de dezinstalare
pe care nu o suportă. Același buton copiază conectorul nou și arată temporar:
Ctrl+C în vechea sesiune Termux, lipire, Enter, revenire în Godot. Operația continuă
după detectarea reviziei noi; o sarcină activă în conectorul vechi blochează această
actualizare. Protocolul și tokenul local rămân neschimbate.

Instalarea nouă necesită Android ARM64, PRoot-Distro 5.x și cel puțin 2 GB liberi.
Se pregătește `debian:13-slim`, fără upgrade general sau migrarea containerelor
existente. Reluarea instalării poate repara numai imaginea incompletă marcată ca
aparținând aplicației. Fișierele existente ale utilizatorului sunt păstrate.

Termux este detectat din nou la revenirea în panou. Versiunea, conexiunea și
verificarea sunt comune dispozitivului; activarea, operația cerută și sarcinile de recuperat
sunt asociate proiectului. Instalările Blender funcționale sunt reutilizate.
Detectarea verifică atât PATH, cât și containerele PRoot în structura actuală
și cea veche.

Protocolul de pornire urmează [RUN_COMMAND Intent](https://github.com/termux/termux-app/wiki/RUN_COMMAND-Intent).
Gestionarea mediului folosește [PRoot-Distro](https://github.com/termux/proot-distro),
iar profilul nou utilizează [Blender Debian ARM64](https://packages.debian.org/trixie/arm64/blender).

## Jurnal și diagnostic

În APK-ul `cd1acda`, validarea GLB acceptă atât
`MeshInstance3D`, cât și `ImporterMeshInstance3D`, folosit de Godot în editor.
Un GLB valid putea primi anterior `empty_mesh`, deși Blender terminase exportul
și randarea. Corecția verifică suprafețele reale, inclusiv geometria la rădăcină,
și permite recuperarea verificării deja terminate (în APK-ul `cd1acda`,
prin **Recuperează**; în APK-ul curent, prin acțiunea unică). Nu este necesară
o nouă instalare sau generare. Regresia rulează în editorul real, deoarece
probele în modul joc nu expun aceeași clasă de import.

APK-ul `2287ae5` înregistrează și pașii anteriori pornirii
unei sarcini: detectare Termux, permisiune, configurare inițială, pornire și
reconectare. **Activat** pentru agent și **Disponibil** sunt stări separate.
Agentul primește motivul indisponibilității și următoarea acțiune.

Jurnalul Blender este salvat în configurația privată a editorului, limitat la
100 evenimente și ultima parte a ieșirii worker-ului. Tokenul conexiunii și
cheile recunoscute sunt redactate înainte de salvare. Verificările periodice
identice nu produc intrări noi. Evenimentele apar și în **Jurnalul** general.
În APK-ul `cd1acda`, jurnalul separat se deschide la eroare. În APK-ul curent,
cardul arată numai o indicație scurtă, iar diagnosticul complet și ieșirea
worker-ului sunt în pagina **Jurnal**, cu filtrare și copiere. Închiderea editorului nu
șterge istoricul diagnosticelor.

## Rulare și fișiere

`blender_run` păstrează `script`, `blend` și `seconds`. Pe Android oferă și:

- `inputs`: fișiere suplimentare din proiect, copiate cu aceeași cale relativă;
- `output_directory`: directorul din proiect pentru rezultate, implicit
  `res://ai_assets/blender`;
- `seconds`: 120 implicit, între 1 și 600, pentru execuția Blender.

Scriptul primește `GODOT_AI_PROJECT_DIR` și `GODOT_AI_OUTPUT_DIR`.
Exemplu de script salvat în proiect:

```python
import os
import bpy

out = os.environ["GODOT_AI_OUTPUT_DIR"]
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.mesh.primitive_cube_add()
bpy.ops.export_scene.gltf(filepath=os.path.join(out, "cutie.glb"), export_format="GLB")
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, "cutie.blend"))
```

Fiecare sarcină are propriul spațiu de lucru. Rezultatele sunt transferate prin
streaming, verificate și importate într-un folder precum
`res://ai_assets/blender/create_box_<id>/`. Numele fișierelor sunt cele alese
de script pentru obiectul produs. Fișierele existente nu sunt suprascrise.

GLB, glTF și imaginile pot folosi preview-ul din chat. FBX, BLEND și celelalte
formate apar ca fișiere; agentul este instruit să producă și un GLB pentru
previzualizare. Fișierele `.blend` sunt păstrate cu `importer="keep"`, deoarece
importerul Android standard nu poate lansa executabilul din Termux.

Tool-ul apare numai după verificare și activare. Folosește aceleași reguli de
planificare și permisiuni ca celelalte operații externe: Plan nu execută,
iar YOLO dezactivat cere confirmarea operației. Agentul primește versiunea și
capacitățile detectate; nu primește tokenul conexiunii locale.

## Recuperare și limite

- Proces auxiliar inclus în APK, bibliotecă standard Python, conexiune limitată
  la `127.0.0.1`, token aleator de 256 biți păstrat în seiful Android.
- ID-uri persistente și manifest verificat: același ID nu execută comanda
  de două ori. La pierderea conexiunii, reluarea consultă sarcina existentă
  (în APK-ul curent, prin aceeași acțiune de instalare).
- O singură sarcină activă, două fire Blender, timeout, anularea grupului de
  procese propriu și limitarea logului. PRoot nu este un sandbox de securitate.
- Instalarea se oprește după încheierea tranzacției curente, inclusiv pregătirea
  imaginii Debian. Nu se șterg lock-uri și nu se execută actualizări generale.
- După o oprire forțată în timpul extragerii, reluarea instalării poate recrea
  exclusiv imaginea incompletă marcată ca aparținând aplicației. Mediile existente
  fără acest marcaj sunt refuzate, nu resetate.
- După confirmarea importului, copiile de lucru sunt eliberate; metadatele
  sarcinii rămân pentru prevenirea reexecutării. Rezultatele nerecuperate sunt
  păstrate. Procesul auxiliar se închide după zece minute fără activitate.
- O instalare deja verificată se poate reconecta automat, fără instalări de
  pachete sau repetarea probei. Schimbarea runtime-ului invalidează verificarea.
- Android poate opri procesele. O sarcină rămasă activă după dispariția procesului
  este raportată ca întreruptă; nu este prezentată drept finalizată.

## Verificare

```sh
python modules/ai_assistant/tests/test_termux_blender.py
python modules/ai_assistant/tests/run_termux_blender.py --godot /cale/catre/Godot_linux.arm64
python modules/ai_assistant/tests/render.py --godot /cale/catre/Godot_linux.arm64 --proot --scenario blender --output .ai-qa/blender-ui
```

Probele backend/HTTP folosesc directoare izolate. Testul real reutilizează Blender
existent din Termux, trece prin clientul Godot și verifică exporturi GLB, glTF cu
dependențe, FBX, BLEND, randare CPU, anulare și recuperarea unui transfer pierdut.
Înlocuiește numai frontiera Intent cu un adaptor de test, explicit marcat în raport.

Compilarea Kotlin cu SDK-ul Android, compilarea obiectului C++ și randarea
panoului nu dovedesc pornirea din APK. Instalarea pe Termux gol, fluxurile Android
de permisiuni și proba completă din APK rămân verificări fizice distincte.
