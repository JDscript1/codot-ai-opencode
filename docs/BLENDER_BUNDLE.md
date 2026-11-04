# Blender CLI inclus în APK

Blender este o componentă a suitei, nu un utilitar descărcat la prima folosire.
Aplicația include pachetul Debian `blender 4.3.2+dfsg-2` pentru `arm64` și
dependențele lui în `assets/godot_ai/packages/debian-offline.zip`. Instalarea
citește numai arhivele semnate din APK și nu contactează Debian, npm sau Termux.

## Flux

1. **Setări → Actualizare pachete** sau **Integrări → Blender → Pregătește din
   APK** pornește un job Linux foreground, anulabil.
2. Jobul verifică hash-urile arhivei, extrage repository-ul apt local și
   instalează pachetele cu `apt-get` folosind exclusiv sursa `file:`.
3. `AILinuxRuntimeFiles.verify()` rulează `blender --background
   --factory-startup --version`; starea și versiunea sunt salvate în
   `state.json` numai după un exit code zero.
4. `blender_status` raportează backend-ul `app-linux`, versiunea măsurată și
   faptul că Termux nu este necesar.
5. `blender_run` primește un script `.py` și un `.blend` opțional, ambele din
   proiect. Proiectul este montat la `/workspace`; directorul de ieșire și
   fișierele returnate sunt verificate să rămână în proiect.

## Mediu de execuție

- `GODOT_AI_PROJECT_DIR=/workspace`
- `GODOT_AI_OUTPUT_DIR=/workspace/<output_directory>`
- `GODOT_AI_INPUTS` conține lista de intrări declarate, câte una pe linie
- `BLENDER_USER_CONFIG`, `BLENDER_USER_SCRIPTS`, `BLENDER_USER_DATAFILES` și
  `BLENDER_USER_EXTENSIONS` sunt în `/tmp/godot-ai-blender`
- `--background --factory-startup --disable-autoexec`
- `--python-exit-code 1 --python /workspace/<script>`

Scriptul are API-ul Python complet al Blender. Poate modela, face UV, materiale,
rigging, animație, bake și randare. Pentru un rezultat inspectabil în Godot,
scriptul trebuie să salveze și un GLB în directorul de ieșire. `blender_run`
întoarce `exit_code`, output-ul limitat, căile fișierelor generate și statusul
backend-ului.

## Dimensiune și durată

Rezolvarea Debian trixie arm64 din buildul de test selectează 377 de pachete,
inclusiv cele de bază. `debian-offline.zip` are 291.488.170 bytes; instalarea
adaugă aproximativ 800 MB și un total de circa 1 GB în runtime. `gnupg`,
codecuri media, biblioteci GUI și GDAL sunt dependențe tranzitive ale
pachetului Debian. Sunt incluse explicit și `python3-numpy`,
`python3-requests` și `python3-pil`, deoarece exportul GLTF are nevoie de numpy
și `--no-install-recommends` nu îl aduce altfel. Instalarea cere cel puțin
2,5 GB liberi, iar `blender_prepare` nu poate rula cât timp Agent AI sau Ziva au
o sesiune activă. Pregătirea se face o singură dată pentru versiunea de pachete
a APK-ului.

## Licență și surse

Blender este distribuit sub GPL. Copyright-ul și textul licenței pachetului
Debian rămân în runtime la `/usr/share/doc/blender/copyright`. Sursele
corespunzătoare pentru versiunea exactă sunt pachetele sursă Debian din
`https://deb.debian.org/debian/pool/main/b/blender/` (`.dsc`, `.orig.tar.xz` și
`.debian.tar.xz` pentru `4.3.2+dfsg-2`). Cine redistribuie APK-ul trebuie să
păstreze această ofertă și să pună la dispoziție sursele corespunzătoare, nu
doar binarul. Pachetul Ziva este proprietar și rămâne numit în distribuția
personală, necomercială.

## Limite

- PRoot nu este un sandbox de securitate; scriptul Blender are accesul
  utilizatorului aplicației și poate citi proiectul montat.
- Eevee/GPU și driverele grafice Android nu sunt încă dovedite. Randarea CPU
  Cycles trebuie măsurată; absența unei probe runtime nu se transformă în
  promisiune de performanță.
- Un APK construit nu dovedește singur că pachetele s-au instalat pe telefon.
  Sunt necesare probe pentru versiune, GLB, randare, import Godot și control
  prin Agent AI.

## Dovadă locală — 3 noiembrie 2026

Repository-ul offline a fost construit local pentru `standard`:

- 377 pachete selectate, inclusiv cele de bază;
- `debian-offline.zip` 291.488.170 bytes, SHA-256
  `6d3cbf835dfbab58e6a9f1b9add122995a473d9346fec8cfdaea96c4da1598ce`;
- `blender 4.3.2+dfsg-2`, `python3-numpy 1:2.2.4+ds-1`,
  `python3-requests 2.32.3+dfsg-5+deb13u1`, `python3-pil 11.1.0-5+deb13u4`.

Repository-ul a fost montat ca sursă APT `file:` și instalat prin PRoot cu
`--no-install-recommends`. Comanda a raportat `Need to get 0 B` pentru arhive,
deci nu a folosit rețeaua. Mediul reproduce `PATH`, `TMPDIR=/tmp`,
`GODOT_AI_*`, `XDG_*` și variabilele Blender folosite de backend.

Rezultate reale:

- `blender --background --factory-startup --version` → `Blender 4.3.2`;
- proba Python `import numpy, requests, PIL` → `GODOT_AI_BLENDER_PYTHON_OK`;
- scriptul de probă a randat Cycles CPU 8 samples, 64×64, PNG RGBA valid;
- a exportat `probe.glb` (1.972 bytes, magic `glTF`) și `probe.blend`
  (441.664 bytes);
- Godot 4.7.2 ARM64 headless a importat GLB-ul: `GODOT_GLB_IMPORT_OK meshes=1`;
- ieșirea Blender a fost 0. Avertismentul Draco este așteptat: biblioteca
  opțională de compresie Draco nu este în pachet, deci GLB-ul este necomprimat.

Aceasta dovedește lanțul Debian ARM64/PRoot/Blender/Godot în mediul de test.
Nu dovedește încă instalarea și execuția prin APK-ul Android instalat pe telefon.

## Livrare APK — 3 noiembrie 2026

CI-ul a construit ambele distribuții din `3d3a7992f1`. Joburile Android și
native-editor au trecut; la Ziva, primul job runtime a avut un segfault Godot
după 966 de verificări de randare, iar reluarea jobului a trecut.

| Distribuție | Bytes | SHA-256 | Pachete Debian |
|---|---:|---|---:|
| standard | 441.882.872 | `f0de6f42dd965ddf6a6b8187692548fb6c9876a7116fc84ad4b7546b7fb308ef` | 377 |
| Ziva | 747.086.184 | `1d72a814745c0811f39cafedeb94834418ed8f309adba68f6cb17f70510ea36d` | 387 |

Ambele APK-uri au semnătură v2 validă, package ID corect, Blender 4.3.2,
`python3-numpy`, repository offline și oferta de surse. Instalatoarele din
Download au fost înlocuite atomic; cele vechi sunt în
`~/godot-ai-artifacts/ag91-previous-download/`.

Cheile de semnare din acest build sunt debug efemere și diferă de aplicația
instalată anterior. Upgrade-ul in-place necesită keystore-ul persistent sau
dezinstalarea aplicației; nu s-a dezinstalat nimic. Instalarea pe telefon a fost
confirmată ulterior; controlul live prin Agent AI rămâne separat.

## Probă pe telefon — 4 noiembrie 2026

Distribuția Ziva este instalată pe `NX729J-UN` și folosește assetul Debian
`3106ed065b52ceba1f2aeba06827ef610f2d3eb6f3b13c9535e2ef0b6d8fc1cd`, identic cu
APK-ul AG-91. Starea runtime-ului raportează Blender 4.3.2 cu Python disponibil.

Prin PRoot-ul aplicației instalate:

- randarea Cycles CPU 8 samples a produs un PNG RGBA 64×64;
- exportul a produs GLB, `.blend` și metadate;
- Godot 4.7.2 Linux ARM64 din APK a importat GLB-ul cu un mesh;
- imaginea a fost extrasă din spațiul privat și inspectată vizual.

Comanda directă a folosit proiectul montat la `/workspace` și aceleași variabile
`GODOT_AI_*`, `XDG_*` și Blender ca backend-ul aplicației. Proba confirmă
lanțul complet pe Android; controlul prin chat-ul Agent AI rămâne separat.
