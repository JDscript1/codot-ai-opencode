# Godot AI Android — implementări, verificări și plan

Ultima actualizare: **2 noiembrie 2026**.

Acesta este documentul de lucru al proiectului. Se actualizează după fiecare
etapă importantă: implementare, verificare, compilare sau livrare. „Implementat
în surse”, „testat în editor”, „compilat în APK” și „verificat pe dispozitiv”
sunt stări distincte. Un plan sau un test cu furnizor simulat nu este prezentat
drept funcție validată cu un serviciu real.

## AG-83 — OmniRoute self-hosted cu cheie API, Termux sau hotspot — 2.11.2026

**Cerință.** Utilizatorul rulează OmniRoute fie local în Termux, fie pe alt
dispozitiv din hotspot/LAN și are nevoie de un furnizor dedicat care să accepte
cheia API și să folosească adresa corectă în ambele situații.

**Implementat în surse.** Catalogul are acum `OmniRoute`, grupat la
`Local / self-hosted`, cu endpointul OpenAI-compatible implicit
`http://127.0.0.1:20128/v1`. O adresă simplă precum `192.168.1.50` sau
`192.168.1.50:20128` este normalizată automat la portul 20128 și `/v1`; URL-ul
complet și calea `/models` sunt acceptate. Câmpul de adresă rămâne vizibil
pentru profilurile salvate, iar HTTP este activat numai prin opțiunea locală
explicită. Cheia introdusă este păstrată în vault și trimisă ca
`Authorization: Bearer` atât la descoperirea modelelor, cât și la
`/chat/completions`. Eticheta `OMNIROUTE_API_KEY=...` selectează furnizorul;
o instalare OmniRoute fără autentificare poate păstra câmpul gol. Cheia nu este
inclusă în URL sau în jurnal. A fost adăugat un simbol `route` din Lucide,
înregistrat cu URL fix și SHA-256 în manifest, iar documentația descrie
loopback-ul Termux, adresa hotspot/LAN și cheia din dashboard. Scanarea LAN
rămâne limitată la Ollama/LM Studio/llama.cpp; OmniRoute configurat cu
autentificare se introduce manual, deoarece scanarea nu trimite chei.

**Verificat local.** Parserul GDScript a trecut pe fișierele modificate, iar
sintaxa Python a trecut pentru fixture și generatorul de icoane.
`test_delivery.py` a raportat 8/8, `test_termux_blender.py` 28/28,
`tools/embedded-runtime/test_build.py` 2/2 și `test_rootfs.py` 4/4. Fixture-ul
determinist acoperă 401 fără cheie, catalogul cu Bearer, excluderea modelelor de
embedding, contextul/capabilitățile, normalizarea adreselor Termux/hotspot și
finalizarea prin ruta chat. Prima rulare CI
[41416158417](https://github.com/JDscript1/godot-ai-android/actions/runs/41416158417)
a oprit runtime-ul pe o aserțiune de test care omitea opt-in-ul HTTP pentru
endpointul LAN; testul a fost corectat, fără modificarea codului de produs.

**Verificat în GitHub Actions.** Rularea Ziva
[41416394355](https://github.com/JDscript1/godot-ai-android/actions/runs/41416394355)
și rularea standard
[41417163039](https://github.com/JDscript1/godot-ai-android/actions/runs/41417163039)
au trecut toate joburile. Runtime-ul a raportat **988/0** aserțiuni, randarea
**958/0** în fiecare dintre cele cinci configurații, editorul nativ **989/0** în
fiecare configurație, scenariile dedicate 84/0–129/0, companionul **9/9**, iar
jobul Android a verificat semnătura persistentă, package-ul, ABI ARM64,
bibliotecile native și scripturile încorporate.

**Livrare Android.** APK-ul Ziva este în
`/storage/emulated/0/Download/Godot-AI-Ziva-arm64-debug.apk`: 112.596.562 bytes,
package `com.jdscript.godotai.ziva.debug`, SHA-256
`8a71e71c14f5f432df98bdd1880c3d028a36801078c5dd9b062920ca8df3d010`.
A fost instalat peste aplicația existentă la 10:05, iar `config.json` din datele
aplicației a rămas prezent. APK-ul standard este în
`/storage/emulated/0/Download/Godot-AI-Android-arm64-debug.apk`: 112.595.302
bytes, package `com.jdscript.godotai.debug`, SHA-256
`c85821ab74211df1e40a0db779c4875fc20948ed567cf1dc44fc028c8e36e58e`.
Ambele nume stabile și fișierele `.sha256` au înlocuit versiunile anterioare;
APK-ul standard nu a fost instalat în această etapă. Artefactele descărcate sunt
păstrate în `.ai-qa/omniroute-ziva/` și `.ai-qa/omniroute-standard/`.
Modificarea este propusă în
[PR #3](https://github.com/JDscript1/godot-ai-android/pull/3), cu baza pe
`fix/siwc-stream-terminal`.

**Limite.** Nu există încă o probă live: la verificare nu asculta niciun server
OmniRoute pe `127.0.0.1:20128`, iar cheia utilizatorului nu a fost disponibilă.
Testele folosesc fixture-ul HTTP determinist, deci confirmă contractul
adaptorului, nu modelele sau furnizorii upstream conectați în OmniRoute.
Utilizatorul trebuie să testeze separat `http://127.0.0.1:20128/v1` în Termux
sau `http://<IP-hotspot>:20128/v1` de pe celălalt dispozitiv. HTTP fără TLS
trebuie folosit numai în rețeaua de încredere; expunerea publică cere HTTPS.

Jurnal: 2.11.2026 — AG-83, OmniRoute adăugat cu cheie API, adrese Termux/LAN,
fixture-uri deterministe, ambele APK-uri recompilate și Ziva instalat.

## AG-82 — reconectarea ChatGPT folosește identitatea deja înregistrată — 2.11.2026

**Defect raportat pe dispozitiv.** După autentificarea în browser, pagina de
consimțământ OpenAI rămânea în spinner, apoi afișa „Sesiunea ta s-a încheiat”
sau „Invalid consent request”. Profilul ChatGPT exista deja, dar tokenul din
vault nu era actualizat; callback-ul nu ajungea în aplicație.

**Cauză.** Profilul avea `client_id` emis (`oaiapp_...`), însă fluxul de
reconectare nu trimitea `id_token_hint` și nici `login_hint`. Documentația SIWC
spune că o reconectare cu client emis și `id_token_hint` trebuie să sară peste
selectorul de cont/consent și să redirecționeze direct. Fără hint, OpenAI
redeschidea consentul, care expira sau eșua.

**Corectat în surse.** `Accounts.authorization_parameters` refolosește
`client_id`-ul emis din profil sau din vault, adaugă `id_token_hint` și
`login_hint` pentru contul salvat și include `agent_name_hint` numai la
înregistrarea dinamică inițială. Testele verifică ambele ramuri: reconectare
fără `agent_name_hint` și înregistrare nouă cu `dynamic_agent_client`.

**Verificat.** Parserul GDScript și testele OAuth au trecut local. În rularea
[41412371462](https://github.com/JDscript1/godot-ai-android/actions/runs/41412371462),
pasul runtime a trecut, iar jobul Android a produs APK-ul Ziva. APK-ul are
112.597.490 bytes, SHA-256
`d7c85175ec9a21f2b57c39be872943aac6410c432714ee1ff2ff17b006a7583d` și a fost
instalat peste aplicația existentă la 09:27, păstrând datele.

**Limite.** Reconectarea live după instalare nu a fost încă încheiată în
momentul acestei note. Callback-ul loopback și expirarea sesiunii OpenAI trebuie
confirmate pe dispozitiv.

Jurnal: 2.11.2026 — AG-82, hint-uri de reconectare ChatGPT și APK Ziva instalat.

## AG-81 — terminale ChatGPT/SIWC: `response.done`, JSON și diagnostic — 2.11.2026

**Defect raportat pe dispozitiv.** Modelele din abonamentul ChatGPT nu
răspundeau. `gpt-6-luna`, `gpt-6.1-sol` și `gpt-5.6-luna` se opreau cu
`incomplete_stream` după trei cereri și două retry-uri; `gpt-5.6-terra` a
rămas în așteptare peste 90 de secunde. Catalogul și autentificarea funcționau,
deci problema era în terminarea fluxului Responses/SIWC, nu în token.

**Corectat în surse.** `providers.gd` acceptă acum și evenimentul terminal
`response.done`, verifică `status` și `error`, păstrează continuarea pentru
`max_output_tokens` și tratează `failed`/`cancelled` ca erori. Dacă serverul
returnează un răspuns JSON complet în loc de SSE, adaptorul îl acceptă atât
pentru obiectul `Response`, cât și pentru erori. Când fluxul rămâne fără
terminal, mesajul include acum statusul HTTP, `Content-Type`, numărul de
evenimente și până la opt tipuri SSE, fără conținutul răspunsului. Astfel un
event terminal nou poate fi identificat în următorul test real.

**Verificat.** Parserul GDScript a trecut local pe `providers.gd` și pe
snippetul noilor teste. În rularea
[41408585327](https://github.com/JDscript1/godot-ai-android/actions/runs/41408585327),
pasul `Test embedded runtime with upstream Godot` a trecut, iar jobul Android a
produs APK-ul Ziva. Testele noi acoperă `response.done` completed/incomplete/
failed, fallback-ul JSON, eroarea JSON și diagnosticul cu tipuri SSE. Randarea
și editorul nativ erau încă în lucru la momentul acestei note.

APK-ul Ziva este în `/storage/emulated/0/Download/Godot-AI-Ziva-arm64-debug.apk`:
112.595.714 bytes, package `com.jdscript.godotai.ziva.debug`, SHA-256
`35048fc5f6878c0a82c0154e5532ae9ec32cde2f390a6d1019be4293160df190`.
ADB s-a deconectat înainte de instalare, deci nu a fost instalat automat.

**Limite.** Nu există încă o probă live după corecție. Dacă OpenAI închide
fluxul fără niciun eveniment terminal, mesajul de diagnostic va arăta tipurile
primite și va confirma dacă problema este upstream. OpenCode free-tier rămâne
restricționat la clientul oficial și nu este tratat de această corecție.

Jurnal: 2.11.2026 — AG-81, terminare SIWC robustă și diagnostic SSE; APK Ziva
compilat, testul live pe abonament rămâne de făcut.

## AG-80 — OpenCode Zen ca furnizor API cu rutare pe model — 1.11.2026

**Cerință.** Utilizatorul a cerut suport pentru cheia API OpenCode în lista de
furnizori a proiectului.

**Implementat în surse.** Catalogul are acum `OpenCode Zen`, cu endpointul
public `https://opencode.ai/zen/v1` și acceptarea etichetelor
`OPENCODE_API_KEY` și `OPENCODE_ZEN_API_KEY`; cheile brute `sk-...` rămân
ambigue și cer selectarea explicită a furnizorului. Catalogul oficial
`/zen/v1/models` descrie 78 de modele în patru protocoale: 24 prin
`chat/completions`, 31 prin `responses`, 17 prin endpointul Anthropic
`messages` și 6 prin `generateContent`. Fiecare model păstrează protocolul,
endpointul de inferență declarat, contextul, limita de ieșire, nivelurile de
reasoning, suportul pentru imagini și tarifele USD/1M tokeni din catalog.
Selectarea unui model rutează automat cererea și fluxul SSE către protocolul
lui nativ; autentificarea este `Authorization: Bearer`, iar
`anthropic-version: 2023-06-01` se adaugă numai pe ruta Anthropic. Modelele de
embedding și protocoalele necunoscute sunt excluse, iar un endpoint de
inferență care nu aparține domeniului HTTPS `opencode.ai` este refuzat înainte
de trimiterea cheii. Pentru cele 22 de modele chat care declară
`compatibility.reasoning_field=reasoning_content`, buclele cu unelte primesc
câmpul gol cerut de protocol, fără a reutiliza reasoning străin. Tarifele
inline din catalog sunt păstrate, nu înlocuite de un feed inexistent.

**Verificat în GitHub Actions.** Rularea
[41326923137](https://github.com/JDscript1/godot-ai-android/actions/runs/41326923137)
a trecut toate cele trei joburi. Suita runtime a raportat **970/0** aserțiuni,
inclusiv descoperirea modelelor, cele patru rute, Bearer, versiunea Anthropic,
tarifele și refuzul endpointului neîncrederii. Randările au trecut **955/0** în
fiecare dintre cele cinci configurații, scenariile dedicate au raportat
84/0–129/0, companionul are **9/9** teste, iar editorul nativ a trecut **986/0**
în fiecare configurație. Jobul Android a verificat semnătura persistentă
(`CN=Godot AI Android Debug, O=JDscript1`), package-ul
`com.jdscript.godotai.debug`, ABI ARM64, bibliotecile
native și scripturile încorporate. Verificarea statică locală a trecut pe
fișierele GDScript modificate și pe `run.py`; parserul GDToolkit nu acceptă o
construcție GDScript deja existentă din întregul `test_runtime.gd`, deci
fișierul complet a fost validat de Godot în CI. Catalogul public OpenCode a
fost citit separat, fără cheie și fără inferență.

**Limite.** Nu s-a făcut o cerere live cu o cheie OpenCode și nu s-a instalat
sau testat fizic APK-ul rezultat în această etapă. Testele folosesc fixture-ul
HTTP determinist; disponibilitatea modelelor pentru contul utilizatorului și
comportamentul fiecărui furnizor rămân de confirmat pe dispozitiv. OpenCode
limitează oficial modelele free-tier la clientul său, deci un client extern
poate primi HTTP 403 cu o cheie validă; modelele plătite nu au această
restricție. Build-ul standard din rularea de mai sus a trecut și a produs un
APK livrat ca `Godot-AI-Android-arm64-debug.apk` (build `9bd6188`), package
`com.jdscript.godotai.debug`, 112.597.054 bytes, SHA-256
`303e6acb661fe6dfc3cbb191bb2792903c624686a26ca6439059776299a5b092`.
Artefactul verificat este în
`/storage/emulated/0/Download/Godot-AI-Android-arm64-debug.apk`, cu checksum
alăturat; nu a fost instalat automat.

Rularea [41328657187](https://github.com/JDscript1/godot-ai-android/actions/runs/41328657187)
pentru distribuția `ziva-preview` a trecut de asemenea toate cele trei joburi.
A produs un APK livrat ca `Godot-AI-Ziva-arm64-debug.apk` (build `a89ed5c`),
package
`com.jdscript.godotai.ziva.debug`, 112.598.378 bytes, SHA-256
`813149eb95bd643dc48860b62722677a1af0c190fb8936dc3a2403a084681858`.
APK-ul Ziva verificat este în
`/storage/emulated/0/Download/Godot-AI-Ziva-arm64-debug.apk`, cu checksum
alăturat; nici acesta nu a fost instalat automat.

Jurnal: 1.11.2026 — AG-80, OpenCode Zen adăugat cu descoperirea catalogului,
rutare pe patru protocoale, tarife inline și replay pentru reasoning.

## AG-79 — săgeata „mergi la ultimul mesaj”: centrare și atingere — 1.11.2026

**Defect raportat pe dispozitiv.** Săgeata care apare când cititorul urcă în
istoric era ancorată în colțul din dreapta jos al zonei de conversație, nu
centrată deasupra composer-ului. În plus, `_chat_touch` consuma orice atingere
din dreptunghiul mesajelor înainte de GUI, iar butonul plutitor nu face parte
din arborele `scroll`, deci apăsarea nu ajungea la el.

**Corectat în surse.** `latest_button` folosește ancora
`PRESET_CENTER_BOTTOM`, cu jumătate de lățime simetrică și aceeași distanță de
12 px față de marginea de jos; creșterea pe orizontală este
`GROW_DIRECTION_BOTH`, ca lățimea minimă să rămână centrată. `_chat_touch`
ignoră atingerile din dreptunghiul butonului când acesta e vizibil, lăsând
GUI-ului să proceseze apăsarea. Fluxul rămâne cel cerut: derulare în sus →
săgeata apare; apăsare → salt la ultimul mesaj și urmărire; conținutul nou nu
mai mișcă cititorul până la o nouă derulare în sus, când săgeata reapare.

**Verificat local.** Fixture `chat_lifecycle`: 87/0 pe `phone_compact` și 87/0
pe `phone_landscape`; `chat` pe `narrow` 82/0; `presentation` pe `phone_compact`
139/0. Aserțiunile noi acoperă centrarea pe axa conversației, neconsumarea
atingerii de press/release și un clic sintetic trimis prin viewport, care ajunge
la buton, readuce `follow_bottom` și ascunde săgeata. Capturi:
`.ai-qa/chat-arrow-centered-20261101/phone_compact/chat-history-arrow.png`,
`.ai-qa/chat-arrow-click-20261101/` și
`.ai-qa/chat-arrow-landscape-20261101/`. **Nu este încă în APK-ul din
`Download`.**

Jurnal: 1.11.2026 — AG-79, săgeata de urmărire centrată și apăsată prin GUI;
comportamentul de blocare pe ultimele mesaje păstrat.

## AG-78 — sesiunea Ziva v3.3.3 pornește cu runtime-ul pregătit de gazdă — 31.10.2026

**Defect raportat pe dispozitiv.** După instalarea APK-ului AG-77, sesiunea
Ziva nu mai pornea: serviciul rămânea în „starting” până la limita de 180
secunde, apoi raporta că interfața nu a pornit. Jurnalul privat al proiectului
`Devonian Era` arăta reluări de descărcare, nu o eroare de încărcare a
extensiei.

**Cauză.** Extensia v3.3.3 nu citește runtime-ul CEF din overlay-ul instalat
lângă addon (`/opt/godot-tools/ziva/v3.3.3/addons/ziva_agent`). Ea verifică
exclusiv `user://ziva/runtime/<versiune>/` și fișierul de terminare `.ready`;
lipsa lor produce `not_installed`, apoi descarcă singură cele 224.410.556 bytes
ale arhivei runtime de la furnizor. Pe telefon descărcarea a mers cu aproximativ
28 MB/minut, adică peste 8 minute, în timp ce wrapper-ul oprește procesul după
180 secunde. Fișierele parțiale `v3.3.3.download.<pid>.zip-*` nu se reiau între
procese (63.631.360, 83.406.848 și 84.013.056 bytes în probe diferite), iar o
încercare a eșuat separat cu `offline: result 3, HTTP 0`. Endpoint-ul era viu
(302 către GitHub); problema era exclusiv locul în care pluginul caută runtime-ul.

**Corectat în surse.** `AIZivaPackage.seedRuntime` pregătește
`user://ziva/runtime/v3.3.3` din overlay-ul deja verificat înainte de lansarea
Godot-ului: conținutul `bin/`, `bin-deps/` și `zivacode/`, fără binarul
extensiei, plus `.ready` cu SHA-256-ul runtime-ului fixat
(`f485f3b0…2b39`, 64 bytes, fără newline). Copierea încearcă mai întâi
`Files.createLink`, apoi copiază cu atributele și drept de execuție păstrate;
drepturile sunt setate și când copierea nu poate păstra atributele. Seeding-ul
este atomic (staging + redenumire, instalarea veche păstrată până la succes),
idempotent când markerul și fișierele-cheie coincid, refuză legăturile
simbolice și căile invalide, șterge descărcările parțiale/deteriorate rămase și
cere spațiu suficient doar când trebuie să copieze efectiv. `AIZivaService`
apelează seeding-ul după ce creează directorul privat al proiectului și înainte
de `startProcess`; `AIZivaProjectContext.userDirectory` reproduce
`OS::get_user_data_dir()` (nume sigur, `godot/app_userdata` sau director
personalizat), ca ținta să fie exact `user://`-ul citit de Godot.

**Verificat pe dispozitiv (probe izolate).** Cu un proiect minimal sub PRoot,
runtime-ul copiat manual și `.ready` scris cu hash-ul runtime-ului, jurnalul nu
mai conține niciun `ZIVA_RUNTIME event=download_start`; BinDepsManager folosește
v3.3.3, iar sidecarul pornește și răspunde: `Sidecar: zivacode listening on port
7012`, `health check passed`, `Sidecar healthy on port 7012; opening webview`.
Dock-ul raportează apoi `webview_unavailable`, comportament nefatal cunoscut și
în v3.3.2 (wrapper-ul afișează interfața prin HTTP). Structura seed-ului a fost
confirmată identică: `bin/linux_arm64`, `bin-deps/linux_arm64`, `zivacode` și
`.ready` de 64 bytes. Proba nu a rulat serviciul Android, deci `runas_app` nu
avea rețea și nu putea monta `/storage`; ea validează formatul, nu înlocuiește
testul APK-ului.

**Verificat local.** Suitele Kotlin compilează și trec: dependențe 13, pachet
Ziva 58 (inclusiv seeding, marker, curățare, refuz de legătură), sesiune 26,
actualizări 18, context de proiect 34 (inclusiv derivarea directorului de date).
Dovezi: `.ai-qa/ziva-333-20261031/` și `.ai-qa/ziva-333-device-20261031/`.

**Compilat, livrat și verificat pe dispozitiv.** Snapshot-ul
`0fd54fbaa15d7ce720dc1a64a361fc8f4d9f6fad`, pe ramura
`build/ziva-333-runtime-seed-20261031T230816Z` (bază `f539d79a`), a trecut CI
[41251258293](https://github.com/JDscript1/godot-ai-android/actions/runs/41251258293):
`runtime`, `android` și `native-editor` — succes; 945 aserțiuni runtime / 0
eșecuri; 950 / 0 pe fiecare dintre cele cinci configurații upstream; 981 / 0 pe
fiecare configurație nativă; 9 teste companion; probele focalizate trec. APK-ul
`Godot-AI-Ziva-arm64-debug.apk` are 112.592.262 bytes, SHA-256
`5a27a85f013d7ce45e50db54a454cd05654140356b1de1d1d8b8e78f337d56c4` și semnătură
validă cu certificatul
`2e0a80969c099f7ff72bfe0c0cd33d98ebdd0e64bbf9729294df0b11665fcab5`; pachetul
`com.jdscript.godotai.ziva.debug`, exclusiv ARM64, 44 de scripturi GDScript
identice cu sursa, adaptorul Ziva identic, 2678 de fișiere Linux verificate, iar
DEX-ul conține `ziva/runtime`, `seedRuntime`, `userDirectory`, `.ready` și
mesajul de eroare al seeding-ului. Fișierul din `Download` și `.sha256` au fost
înlocuite și reverificate după copiere.

Pe dispozitiv, APK-ul a fost instalat cu `adb install -r` peste aplicația
existentă, păstrând datele; seed-ul manual folosit la diagnoză a fost șters
înainte de probă. Aplicația a recreat singură `user://ziva/runtime/v3.3.3`: 236
de fișiere și 534.671.202 bytes, plus `.ready` de 64 bytes cu `f485f3b0…2b39`,
suma fișierelor fiind exact conținutul arhivei runtime. Legătura dură a fost
refuzată (link count 1), deci s-a folosit copia de rezervă. Sesiunea a pornit
automat și a ajuns `running` pe portul 7012; interfața răspunde HTTP 200, tabul
Ziva este randat în editor, sidecarul raportează `listening on port 7012` și
`health check passed`, iar jurnalul gdext nu mai conține niciun
`ZIVA_RUNTIME event=download_start` după această pornire. Nu s-a trimis niciun
prompt de model. Dovezi: `.ai-qa/compile-ziva-333-runtime-seed-20261031T230816Z/`.

Jurnal: 31.10.2026 — AG-78, runtime-ul Ziva v3.3.3 pregătit de gazdă înainte de
pornire; descărcarea de 224 MB a extensiei eliminată din calea critică.
APK-ul a fost livrat în `Download` și verificat pe dispozitiv.

## AG-77 — actualizarea Ziva v3.3.3: release separat addon+runtime — 31.10.2026

**Defect raportat pe dispozitiv.** Utilizatorul a pornit actualizarea din
interfața oficială Ziva; descărcarea s-a încheiat, dar aplicarea nu. Capturile
`Screenshot_20261031_224710.jpg` și `Screenshot_20261031_224845.jpg` arată
„Ziva v3.3.3 is ready — Restart to apply” și, după repornire, „Unable to
Reconnect — Could not reach the plugin server”.

**Cauză.** Începând cu v3.3.3, furnizorul publică **două** arhive: addon-ul
GDExtension (2.944.465 bytes) și runtime-ul CEF separat (224.410.556 bytes),
înrădăcinat direct în directorul addon-ului (`bin/`, `bin-deps/`,
`zivacode/`). Updater-ul din editorul oficial nu poate reporni sesiunea
headless sub PRoot, deci nu aplică actualizarea; în plus, wrapper-ul nostru
fixa v3.3.2, cu un singur pachet combinat și `zivacode` în interiorul arhivei
addon-ului, deci nici calea `ziva_update` nu putea instala release-ul nou.

**Corectat în surse.** `AIZivaPackage` fixează v3.3.3 cu ambele arhive,
dimensiuni și SHA-256 (addon `1e06bcef…6027c4`, runtime `f485f3b0…2b39`,
`zivacode` 136.039.416 bytes, `db476a4b…5cb6`), descarcă și verifică ambele,
suprapune runtime-ul peste addon și activează atomic. `activeRelease` preferă
versiunea fixată când este mai nouă, astfel încât o instalare v3.3.2 existentă
migrează fără ștergerea prealabilă. `AIZivaUpdates` împerechează exact cele
două active ale unei versiuni, fiecare cu digest. Updater-ul oficial rulează
cu `ZIVA_AUTOUPDATE_DRY_RUN=1`: versiunea aparține wrapper-ului, iar
„Restart to apply” nu mai este oferit. Textele de instalare și documentația
indică v3.3.3 și ~305 MB descărcați (~1,1 GB la instalare).

**Verificat local.** Testele Kotlin compilează și trec fără eșecuri:
dependențe 13, pachet Ziva 49, sesiune 26, actualizări 18, context de proiect
26. Arhivele oficiale reale v3.3.3 au fost extrase prin clasele aplicației:
`version=v3.3.3`, binar 136.039.416 bytes cu hash-ul așteptat, 247 de fișiere,
545.460.656 bytes, executabil și extensia prezentă. Metadatele reale GitHub
(17 active) se împerechează exact cu perechea fixată. Binarul conține șirul
`v3.3.3`. Dovezi: `.ai-qa/ziva-333-20261031/`.

**Compilat și livrat.** Snapshot `5e0958330ada6527920a9050d246b279c6913254`,
ramura `build/ziva-333-20261031T220957Z`, bazată pe `f539d79a`; include AG-75 și
AG-77. CI 41246943858 s-a încheiat cu succes la `runtime`, `android` și
`native-editor`: **945 aserțiuni runtime / 0 eșecuri**, **950 verificări / 0
eșecuri** pe fiecare dintre cele cinci configurații upstream, **981 / 0** pe
fiecare configurație nativă; probele focalizate trec. APK-ul Ziva are
112.586.890 bytes, SHA-256 `3f0597fa2549ec35b77d91cfaa1b7a002584d8dfd24c6495131725a09583767a`,
semnătură validă și același certificat persistent, pachet
`com.jdscript.godotai.ziva.debug`, exclusiv ARM64; toate cele **44 de
scripturi** sunt identice cu sursa, adaptorul Ziva este identic, iar toate cele
**2678 de fișiere** Linux corespund manifestului. Constantele v3.3.3, URL-urile
celor două arhive, hash-urile și `ZIVA_AUTOUPDATE_DRY_RUN` sunt prezente în
DEX-ul compilat. Fișierul
`/storage/emulated/0/Download/Godot-AI-Ziva-arm64-debug.apk` și checksum-ul lui
au fost înlocuite și reverificate după copiere. Dovezi:
`.ai-qa/compile-ziva-333-20261031T220957Z/` (`verification.json`, jurnalele CI,
`apk-verification.json`).

**În așteptare:** instalarea noului APK pe telefon, peste versiunea curentă, și
proba fizică a actualizării Ziva și a panoului. ADB nu are dispozitive
conectate, deci instalarea se face manual din Download.

Jurnal: 31.10.2026 — AG-77, actualizarea Ziva v3.3.3 (addon+runtime separat)
corectată, compilată în APK și livrată în Download.

## AG-76 — ambele APK-uri cu AG-75 compilate și livrate — 31.10.2026

**Godot AI** și **Godot AI Ziva** au fost compilate din același snapshot
`989d2cb967d8aa2f27391112eb6ffb1cb84b20b6`, ramura separată
`build/context-inline-20261031T212617Z`, bazată pe `f539d79a`. Sunt incluse
compactarea calibrată după încărcarea contextului și diffurile direct în chat
din AG-75, împreună cu modificările anterioare din baza curentă. Checkout-ul
principal și proiectele utilizatorului au fost păstrate.

Ambele rulări CI s-au încheiat cu succes la `android`, `runtime` și
`native-editor`:

- Godot AI: https://github.com/JDscript1/godot-ai-android/actions/runs/41243609340
- Godot AI Ziva: https://github.com/JDscript1/godot-ai-android/actions/runs/41243616486

În fiecare rulare: **945 aserțiuni runtime / 0 eșecuri**, **950 verificări / 0
eșecuri** pe fiecare dintre cele cinci configurații ale editorului upstream și
**981 verificări / 0 eșecuri** pe fiecare configurație a editorului nativ
compilat. Probele focalizate și testele companion trec de asemenea. Rapoartele
au fost descărcate; capturile diffurilor au fost inspectate, inclusiv în
editorul nativ, configurația phone_landscape.

Verificare locală pentru fiecare APK: hash identic cu artefactul CI, semnătură
validă și același certificat persistent ca instalatoarele precedente,
pachet Android separat corect, exclusiv ARM64, toate cele **44 de scripturi
GDScript identice cu sursa compilată**, adaptorul Ziva identic și runtime-ul
Linux complet. Manifestele și bibliotecile native au fost verificate; toate
cele **2678 de fișiere** din baza Linux corespund manifestului și hashurilor.
Configurația de rețea specifică Ziva este verificată numai pentru distribuția
care o declară în overlay-ul Android.

Instalatoarele vechi `f539d79a` au fost înlocuite după verificare. În Download
rămâne câte un APK curent pentru fiecare distribuție, cu fișier `.sha256`:

- `/storage/emulated/0/Download/Godot-AI-Android-arm64-debug.apk` — 112584122 bytes.
- `/storage/emulated/0/Download/Godot-AI-Ziva-arm64-debug.apk` — 112587394 bytes.

Hashurile copiilor din Download au fost reverificate după copiere. Nu au fost
șterse alte descărcări. Dovezi complete, rapoarte, hashuri și snapshot:
`.ai-qa/compile-context-inline-20261031T212617Z/verification.json` și `report.md`;
indicatorul `.ai-qa/compile-both-current.json` indică această livrare.

**Limită de validare:** noile APK-uri nu au fost instalate sau testate pe
telefon în această etapă. O conversație reală aproape de 1M tokeni și
comportamentul Android fizic rămân probe separate de verificările automate.

Jurnal: 31.10.2026 — AG-76, ambele distribuții compilate, verificate și
înlocuite în Download cu AG-75 inclus.

## AG-75 — context calibrat și diffuri direct în conversație — 31.10.2026

Implementat în surse pentru agentul nativ. Estimarea anterioară putea număra
întregul JSON, inclusiv imaginile Base64, ca text. Harness-ul și panoul folosesc
acum același estimator pentru conținutul trimis: text, raționament păstrat,
apeluri, scheme și imagini separate. Dimensiunea codificării unei imagini nu
mai modifică estimarea; cei 2048 tokeni/imagine sunt explicit o aproximație,
nu o tokenizare exactă a modelului.

Fiecare răspuns principal măsurat calibrează următoarea estimare prin consumul
raportat plus diferența estimată a conținutului nou. Măsurătoarea aparține
conversației, profilului și modelului; rezumatele auxiliare nu o suprascriu.
Contoarele de cache Anthropic sunt incluse în intrare, fără dublarea tokenilor
cache deja incluși în `prompt_tokens` la furnizorii compatibili OpenAI.

Compactarea automată se recalculează la fiecare verificare: pragul este minimul
dintre **90% din fereastra publicată** și spațiul rămas după rezerva pentru
răspuns. Pentru DeepSeek se rezervă implicit 64K, respectiv 128K la efort `max`,
cu respectarea limitei de ieșire declarate; metadatele modelelor păstrează acum
și `max_output_tokens`. Pe o fereastră de 1048576 tokeni, pragul general este
943718, iar rezerva 128K îl coboară la 917504. Nu se limitează pașii agentului.

Marcajele vechi se șterg când presiunea scade sau se schimbă modelul; o depășire
reală rămâne motiv distinct de recuperare. Fără fereastră publicată nu se
inventează un prag. Istoricul original rămâne pe disc. Implicit, compactarea
păstrează aproximativ 55% din fereastră ca istoric recent, în loc să reducă
mereu o conversație mare la 20k. Jurnalul `compact_trigger` înregistrează
încărcarea, limita, rezerva, pragul și motivul; indicatorul poate fi atins
pentru detalii despre măsurare și estimare.

Diffurile fișierelor aplicate sau propuse apar direct în fluxul conversației,
fără carduri, editoare sau zone de scroll imbricate: nume de fișier, linii
șterse roșii cu `-`, adăugate verzi cu `+`, context neutru. Primul fragment
are cel mult 40 de linii, iar restul se extinde la cerere în loturi de maximum
500. Textul codului rămâne literal, inclusiv BBCode și diacritice. Poziția
cititorului este păstrată; restaurarea și jurnalul modificărilor rămân accesibile.

Verificări locale Godot Linux ARM64 4.7.2: **945 aserțiuni runtime / 0 eșecuri**,
**132 verificări compactare / 0 eșecuri**, **136 verificări prezentare / 0
eșecuri** pe fiecare dintre editorul îngust și configurația phone_landscape.
Capturile diffurilor au fost inspectate. Regresii noi: 50k + patru imagini mari
pe 1M nu compactează; consumul măsurat și diferența nouă au prioritate;
rezumatul nu alterează contorul; scăderea încărcării și schimbarea modelului
șterg declanșările vechi; diffurile se extind fără duplicate sau forțarea
urmăririi mesajelor recente.

Dovezi: `.ai-qa/context-inline-20261031/`. Suita completă pe sursele finale: **950 verificări / 0 eșecuri**, editor îngust.
Prima rulare extinsă a avut două aserțiuni eșuate pentru același tap pe link;
probele izolate trec atât pe bază, cât și pe codul nou (79/0 fiecare), iar
rularea finală completă trece fără modificarea logicii linkurilor.
La închiderea implementării sursă nu fuseseră recompilate sau înlocuite
APK-urile; compilarea și livrarea ulterioare sunt consemnate la AG-76.
Verificarea fizică Android și o conversație reală aproape de 1M tokeni
rămân probe distincte de fixture-urile locale.

Jurnal: 31.10.2026 — AG-75, compactare pe încărcarea contextului curent,
fără tokenizarea Base64 ca text, și diffuri colorate direct în chat.

## AG-74 — replay DeepSeek în modul thinking — 31.10.2026

Defect raportat din aplicația instalată: un tur cu unelte a eșuat cu
`HTTP 400: The reasoning_content in the thinking mode must be passed back to the
API`. Conform ghidului DeepSeek, când cererea oferă unelte, `reasoning_content`
trebuie retrimis pentru **fiecare** tur asistent anterior, nu doar pentru cele
cu `tool_calls`.

- `providers.gd` completează, după normalizarea contextului, câmpul
  `reasoning_content` pe fiecare mesaj asistent fără el, doar pentru profilurile
  DeepSeek (`issuer` sau `id`) și doar când se trimit unelte. Răspunsurile
  proprii păstrează raționamentul original; tururile străine sau vechi primesc
  șir gol, fără a inventa sau retrimite raționament privat.
- Fixture-ul HTTP are ruta `/replay/` care reproduce regula strictă, iar
  `test_runtime.gd` verifică o conversație cu un tur asistent străin fără
  raționament salvat.

Verificare: suita runtime locală, Godot 4.7.2 headless, 940 aserțiuni, 0
eșecuri. Compilarea CI și APK-ul nou sunt necesare pentru livrare.

## AG-73 — chat fix, erorile se deschid la cerere — 31.10.2026

Cerința utilizatorului: când apar erori în consolă, interfața de chat nu mai
trebuie să se ridice ca să facă loc ecranului de erori; chatul rămâne fix, iar
erorile se deschid doar la atingere.

- `EditorPlugin::keeps_workspace_fixed()` (nou, implicit `false`); ecranele
  principale **AI Assistant** și **Ziva** îl suprascriu. Când un astfel de ecran
  este selectat, `EditorNode::_project_run_started` nu mai deschide automat
  Output/Debugger-ul la pornirea scenei; modul distraction-free păstrează aceeași
  regulă. Panourile rămân deschizibile manual.
- `chat_view.gd` afișează un indicator plat în antet (`ErrorIndicator`) doar când
  Debugger-ul raportează erori: „1 eroare”/„N erori”, culoare de atenție până la
  prima deschidere, apoi mută. Atingerea emite acțiunea `errors`.
- `panel.gd` sondează `debugger_status` o dată pe secundă și tratează `errors`:
  iese din distraction-free dacă e necesar și deschide Debugger-ul pe tabul
  Errors. `AIAssistantEditorPlugin::debugger_status()` însumează contoarele
  sesiunilor native, iar `open_debugger_errors()` deschide docul și selectează
  tabul Errors.

Verificare: fixture-ul `presentation` are 6 aserțiuni noi (indicator ascuns fără
erori, text, culoare de atenție, acțiune la atingere, stil mut după deschidere,
ascundere la zero); 127/0 atât la `narrow`, cât și la `phone_landscape`, iar
`chat` 82/0, `chat_lifecycle` 83/0 și `compact` 122/0 pe `phone_landscape`.
Compilarea CI este verde pe `95744349` (standard `41209307182`, Ziva
`41209307079`); APK-urile arm64 `95744349` au fost puse în Download. Defectul
DeepSeek apărut apoi în aplicația instalată este tratat în AG-74.

## AG-72 — agentul nostru deleagă sarcini către Ziva — 31.10.2026

Cerința utilizatorului: în timp ce lucrăm cu agentul nostru, să putem folosi
direct agentul Ziva, printr-un mesaj injectat de agentul nostru. Implementat
în surse (necommis încă la data acestei însemnări):

- `AIZivaChat.kt` (nou) folosește RPC-ul local propriu al sidecarului oficial:
  rezolvă sau creează conversația dedicată **Godot AI** (`plugin/bootstrap`,
  `chats/create`), trimite promptul (`chats/sendPrompt`, selecție de model din
  conversație sau implicitul `zivacode`) și sondează `chats/snapshot` până la
  terminarea turului. Rezultatul final, eroarea de tur, permisiunile și
  întrebările în așteptare sunt raportate ca stare. Sarcinile trăiesc în memorie,
  maximum 4 simultane, păstrate 30 de minute după terminare.
- `AIZivaRuntime.kt` rutează `ziva_chat_send/poll/cancel`; trimiterea cere ca
  sesiunea să ruleze pe același proiect, iar citirea stării este pur locală, ca
  un răspuns terminat să nu se piardă dacă Ziva se oprește.
- `panel.gd` expune `ziva_task` (risc „external” — aprobare per apel, ascuns în
  modurile doar-citire), `ziva_task_poll` și `ziva_task_result`. Primul răspuns
  se limitează la 6000 de caractere cu `next_offset` explicit, restul se citește
  pe felii exacte; răspunsurile lungi nu mai depind de trunchierea harness-ului.
  Nicio permisiune Ziva nu este aprobată automat: ne întoarcem cu
  `ziva_permission_required` / `ziva_question_required` și `job_id`, iar după ce
  utilizatorul răspunde în tabul Ziva reluăm cu `ziva_task_poll`. Un tur Ziva
  care a executat unelte marchează harta proiectului, diagnosticile și
  verificarea ca învechite.

Verificare: `panel.gd` și fixture-ul parsează cu Godot 4.7.2 headless
(`--check-only`). Fixture-ul `ziva` are 8 aserțiuni noi: risc/vizibilitate,
prompt + proiect trimise, tăiere la 6000 cu `next_offset`, felie exactă,
permisiune întoarsă fără aprobare, reluare după răspuns și anulare care oprește
și sarcina Ziva. Compilarea Kotlin a fost dovedită de CI după commit/push
(`41170143305`, toate joburile verzi). Pe dispozitiv, cu APK-ul
`Godot-AI-Ziva-arm64-d5105508.apk` (112.586.234 octeți, sha256 `5bdfe443…`,
semnătură debug) instalat pe NX729J, proiectul devonian-era: sarcina
`901939ee-c535-4606-8393-b1673f439c0c` s-a terminat `completed` cu răspunsul
„PONG” (4 caractere, fără unelte) în ~3,4 s. Snapshotul independent al
sidecarului confirmă conversația dedicată `chat_e6f8261c1ffel4nzFv4HtWuA8i`
(`fallbackTitle` „Godot AI”, titlu automat „Răspunde cu PONG”), mesajul
utilizatorului cu partea `<additional_context>` marcată `synthetic` (ignorată
corect de potrivirea exactă din `findTurn`) și mesajul asistentului legat prin
`parentId`, cu `finish: "stop"`. Fluxul permisiunii rămâne de probat separat.

Contract RPC folosit: `chats/create`, `chats/sendPrompt`, `chats/snapshot`,
`chats/abort`, `plugin/bootstrap`, anvelopă oRPC `{"json": …}`. Este un contract
privat al pachetului v3.3.2 (analizat static din bundle-ul oficial, 30–31.10.2026)
și poate diferi între versiuni; eșecurile sunt raportate explicit, fără
reîncercări ascunse. Detalii: `docs/AI_ZIVA.md`.

## AG-71 — recuperare după compactarea nereușită a agentului nativ — 31.10.2026

Jurnalul citit prin ADB din panoul agentului nostru, în distribuția Ziva de pe
NX729J, confirmă trei opriri înainte de cererea principală (`requests: 0`).
Primele două au `incomplete_summary`; ultima are `empty_summary`, cu **4096
tokeni de ieșire, toți raportați ca reasoning**, fără rezumat final. APK-ul
instalat este construit din `37a3bf4`. Raportul „niciun fișier confirmat” privește
încercarea întreruptă, nu dovedește absența schimbărilor din sarcinile anterioare.

Corecții în surse:

- Compactarea auxiliară folosește un efort redus numai dacă modelul îl declară;
  selecția de efort a agentului principal rămâne separată.
- Un răspuns gol sau tăiat de limita de ieșire permite o singură reîncercare
  pe segment, cu buget suplimentar pentru generare, rezervat în fereastra
  modelului. Limita textului rezumat și cursorul sursei rămân controlate;
  segmentele intermediare nu înlocuiesc rezumatul durabil.
- Dacă rezumatul rămâne indisponibil, sarcina continuă cu contextul existent.
  Harness-ul poate reduce rezultatele vechi ale tool-urilor în copia destinată
  furnizorului. Istoricul integral, cererile utilizatorului, planul, dovezile și
  identificatorii apelurilor rămân păstrate; reluarea nu este blocată de un
  eșec auxiliar memorat. Nu se reexecută operații ca parte a recuperării.
- Stop, schimbarea contextului și eșecul salvării rezumatului rămân erori
  explicite. Jurnalul compactării include tentativa, bugetul, motivul încheierii,
  dimensiunea textului și consumul, fără conținutul raționamentului.

Verificare locală cu Godot Linux ARM64 4.7.2: **939 aserțiuni runtime / 0 eșecuri**
și **120 verificări în editor îngust / 0 eșecuri**. Proba folosește harness-ul
real și hook-ul real de pregătire din panou, cu furnizor simulat: două rezumate
goale sunt urmate de cererea principală și finalizare; sunt verificate păstrarea
contextului durabil, a ultimului lot de tool-uri, oprirea și salvarea eșuată.
Regresiile existente acoperă și Unicode, segmente lungi și reducerea intrării
după depășirea ferestrei.

Dovezi: `.ai-qa/compaction-20261031/device-diagnosis.json`, `runtime.log`,
`compact-final.log`, `final-rendered/narrow/editor-report.json`.
Citirea jurnalului fizic confirmă cauza versiunii instalate; nu constituie o
probă live a corecției. **APK-urile din Download nu au fost recompilate sau
înlocuite în această etapă**; aplicarea pe telefon și reluarea reală cu DeepSeek
rămân de verificat după compilare.

Fără plafoane euristice de context (aceeași etapă, 31.10.2026): agentul primește
tot istoricul păstrat de la granița rezumatului, nu doar ultimele 24 de mesaje —
preferința `history_messages` a fost eliminată. Pentru un model fără fereastră
publicată nu se mai presupune 8192 de tokeni: tăierea preventivă din harness și
compactarea nu mai pornesc din presupuneri, ci doar din depășirea raportată de
furnizor, iar limita nu se mai moștenește de la modelul selectat anterior.
Bugetele de rezultate ale tool-urilor cresc cu fereastra modelului (24000 și
48000 de caractere rămân pragurile pentru ferestre mici sau necunoscute).
Rezumatul auxiliar are acum un plafon de ieșire de 8192 de tokeni, cu o singură
reîncercare la 16384 la tăiere, iar continuările după un răspuns tăiat urcă de
la 2 la 5.

Verificare locală: **939 aserțiuni runtime / 0 eșecuri** și **917 verificări în
editorul îngust / 0 eșecuri** (`.ai-qa/limits-20261031-runtime.log`,
`.ai-qa/limits-20261031-narrow/narrow/editor-report.json`). Compilarea unui APK
nou și proba pe dispozitiv rămân necesare.

Jurnal: 31.10.2026 — AG-71, compactarea auxiliară nu mai oprește automat
sarcina nativă; recuperarea și conservarea contextului sunt testate local.
Agentul nu mai are plafoane euristice de context; istoricul complet este trimis
modelului și compactarea urmează doar semnalul real al furnizorului.

## AG-70 — tastare WebView și proprietarul capturii audio — 31.10.2026

Pe telefonul NX729J / Android 15, cu Gboard și WebView 156.0.8078.47, captura
și jurnalul cursorului confirmă reordonarea literelor. Proba de inserare în
WebView-ul instalat reproduce `verifica` → `acifirve`: după a doua literă,
selecția DOM și selecția Lexical ajung la zero. Dezactivarea corectării automate
nu rezolvă problema și nu este păstrată ca remediu.

Protecția nouă observă `beforeinput`/`input` doar în composerul Ziva. Repară
selecția întoarsă la zero numai când textul rezultat corespunde exact inserării
native în același nod; nu rescrie textul și nu mută un cursor valid. Respectă
compoziția IME, selecțiile inverse, intervalele de înlocuire și editarea în
mijlocul ciornei. Aceleași surse, aplicate temporar în WebView prin CDP, produc
`verifica`, cursor/model 1…8, cu șapte selecții invalide reparate. Teste DOM:
**46/0**, inclusiv regresia reală și protecțiile de selecție.

Încă șase probe în WebView-ul fizic trec: inserare în mijloc/la început,
înlocuire de selecție normală/inversă, diacritice și navigare intenționată.

Eroarea vocală este `NotReadableError: Could not start audio source`, reprodusă
cu trei configurații de captură. Permisiunea Android este acordată. Politica
audio arată o captură MIC 44100 Hz rămasă activă pentru UID-ul aplicației.
`GodotLib.requestPermissionResult` pornește intrarea AudioDriver la un grant
audio, iar rezultatul permisiunii proprii ajungea mai întâi la acest dispatcher.
Acum BaseGodotEditor consumă cererile coordonatorului AI/WebView înainte de
delegarea către Godot; celelalte cereri păstrează traseul existent.

Proba intermediară elimină captura Godot rămasă activă, dar WebView încă
respinge sursa audio. Manifestul nu declara `MODIFY_AUDIO_SETTINGS`, necesară
împreună cu `RECORD_AUDIO` pentru selecția dispozitivului de captură Chromium.
Este adăugată permisiunea normală; accesul la înregistrare rămâne controlat de
dialogul Android. Remediul se verifică din nou pe APK, nu doar în surse.

La repornirea APK-ului intermediar s-a identificat și un fișier global
`/root/.agents/AGENTS.md` gol, cu permisiuni 000, care bloca pregătirea
contextului. Conținutul unui fișier gol nu mai este citit inutil; overlay-ul
sesiunii este creat fără modificarea originalului ori a permisiunilor lui.
Regresia folosește un fișier real gol cu permisiuni 000: **26/0** probe de
context; suita Kotlin completă **145/0**.

Dovezi: `.ai-qa/ziva-input-20261031/` — capturi originale păstrate, metadate IME,
jurnale de selecție, politica audio și probe CDP înainte/după. Backend-ul local
Ziva a fost accesat prin MCP pentru inspecție; nu s-au trimis mesaje către model
și nu s-au modificat fișierele proiectului. Au fost golite numai cuvintele de test.

**Stare:** ambele APK-uri finale sunt compilate din
`37a3bf46204d0ac5aca5b98eb499370fe4f6e3f0` și înlocuite în Download după verificarea
semnăturii persistente, a pachetelor distincte, ARM64, celor 44 de scripturi,
adaptorului Ziva exact, ambelor permisiuni audio și celor 2678 de fișiere Linux.
CI [standard](https://github.com/JDscript1/godot-ai-android/actions/runs/41146838067)
și [Ziva](https://github.com/JDscript1/godot-ai-android/actions/runs/41146846768)
sunt `completed/success`: runtime **939/0**, cinci configurații upstream
**901/0** fiecare și native **932/0** fiecare, probe focalizate fără erori.

- `Godot-AI-Android-arm64-debug.apk` — **112566130 bytes**;
- `Godot-AI-Ziva-arm64-debug.apk` — **112568402 bytes**.

Ziva final este instalat pe NX729J fără ștergerea datelor; hash-ul APK-ului
instalat corespunde artefactului verificat. Apăsările reale pe tastele Gboard
produc `Verifica`, cu cursorul 1…8 și focus păstrat. În WebView-ul APK-ului final,
fără protecție temporară injectată, trec **7/0** probe de inserare/selecție.
După revocarea controlată a permisiunii pentru probă, cererea de captură
declanșează acordarea Android și se rezolvă cu succes; permisiunea rămâne acordată.
Cele trei configurații de captură trec **3/3**, mono 48 kHz. MediaRecorder
produce **4508 bytes** WebM/Opus în proba de 0,5 s și oprește track-ul (`ended`).
Politica audio confirmă captura inactivă după oprire. Sunetul de probă nu a fost
salvat sau încărcat către un furnizor.

Fișierul global gol a fost făcut temporar accesibil doar pentru izolarea
defectului în APK-ul intermediar; permisiunile 000 au fost restaurate înainte de
instalarea finală. Sesiunea finală pornește cu acel fișier încă gol și cu
permisiunile originale 000, fără reparație manuală.

Dovezi compilare/livrare:
`.ai-qa/compile-ime-audio-final-20261030T234822Z/verification.json` și `report.md`.
Rundele intermediare nu sunt livrate în Download; checkout-ul principal și
modificările existente sunt păstrate. **Limite:** transcrierea prin furnizorul
cloud nu a fost apelată; distribuția standard este verificată ca APK, fără
instalare pe telefon în această etapă.

Jurnal: 31.10.2026 — AG-70, tastare Gboard și captură WebView verificate pe
telefon; ambele APK-uri compilate, verificate și înlocuite în Download.

## AG-69 — microfon comun și corecția tastaturii Ziva — 30.10.2026

În surse, WebView Ziva tratează explicit cererile de microfon: numai audio,
numai originea locală și portul sesiunii active, după permisiunea Android.
Același coordonator de permisiuni este folosit de dictarea nativă. Cererile
anulate nu sunt reluate după ascundere/navigare, iar un refuz permanent oferă
acces la Setări Android. Fluxul oficial Ziva și autentificarea sa rămân intacte.

Adaptoarea nu mai înlocuiește `HTMLElement.focus` și nu mai ascunde IME printr-un
temporizator după atingere. Intenția de editare aparține sesiunii, nu unui nod
Lexical care poate fi înlocuit. Compoziția IME și focusul repetat nu modifică
textul. Trimite, Setări și ascunderea tabului pot încheia explicit editarea.

Agentul propriu are serviciul vocal legat de activitatea Android, înregistrare
nativă mono WAV 16 kHz limitată la 60 s și flux înregistrare → oprire → transcriere
→ adăugare în ciorna actuală, fără trimitere/focus automat. Înregistrarea afișează
un singur rând cu timp, nivel audio, Stop și Anulare. Sunt păstrate serviciul
Android și endpointul compatibil Whisper configurat separat; serviciul/cheile
Ziva nu sunt preluate de agentul nativ. Pe Android, endpointul folosește captura
nativă, fără a depinde de activarea intrării audio la pornirea proiectului Godot.
Rezultatele întârziate sau anulate au identitate de sesiune și nu schimbă o
ciornă nouă. Ascunderea panoului sau trecerea în fundal oprește captura; pauza
provocată de dialogul Android nu anulează automat cererea încă nehotărâtă.

Probe locale: compilare Kotlin reușită, **140/0** verificări Kotlin (dintre care
**29/0** pentru permisiuni/origini/WAV), **25/0** teste DOM cu compoziție simulată,
regresii runtime **939/0** și interfață vocală randată **83/0** în configurația
`phone_compact`. Dovezi: `.ai-qa/microphone-20261030/`. Captura vocală randată a
fost inspectată; starea audio este simulată în acea probă, nu înregistrare reală.
Ambele distribuții sunt compilate din snapshot-ul
`0b6e7a22ca9b94f9cec78cfeeeefbb5cc713a74a`, pe ramura izolată
`build/microphone-20261030T191856Z`. CI
[Godot AI](https://github.com/JDscript1/godot-ai-android/actions/runs/41116309094)
și [Godot AI Ziva](https://github.com/JDscript1/godot-ai-android/actions/runs/41116329482)
au finalizat `completed/success`: runtime **939/0**, cinci configurații randate
**901/0** fiecare, editor nativ **932/0** fiecare, probe focalizate fără erori
(inclusiv voce/chat **83/0**, respectiv **84/0** în editorul nativ), companion **9/0**.
Proba vocală folosește acum un timp de pornire pozitiv și verifică formatul
temporizatorului viu; nu scade 12 secunde dintr-un editor abia pornit.

APK-urile și checksum-urile din Download au fost înlocuite după verificarea
semnăturii persistente, a pachetelor separate, ARM64, a celor **44** scripturi
exacte, adaptorului Ziva, claselor vocale Android, permisiunii audio și celor
**2678** fișiere Linux:

- `Godot-AI-Android-arm64-debug.apk` — **112565686 bytes**;
- `Godot-AI-Ziva-arm64-debug.apk` — **112567026 bytes**.

Dovezi ale compilării/livrării:
`.ai-qa/compile-microphone-20261030T193351Z/verification.json` și `report.md`.
Rundele intermediare rămân în directoarele anterioare, fără livrare; checkout-ul
principal și modificările existente sunt păstrate.

**Limite:** WebView/IME Android, dialogul și microfonul fizic, recunoașterea
Android și transcrierea cu un furnizor real nu sunt încă verificate pe telefon.
APK-urile AG-69 sunt verificate ca pachete, fără instalare în această etapă.

Jurnal: 30.10.2026 — AG-69, corecții microfon/tastatură implementate, ambele
APK-uri compilate și înlocuite în Download; validarea Android fizică rămâne
distinctă de probele automate.

## AG-68 — ambele APK-uri compilate și livrate — 30.10.2026

**Godot AI** și **Godot AI Ziva** sunt compilate din snapshot-ul comun
`27d2909d2a4dfa7081c847d88b09cf9a9f98f729`, pe ramura izolată
`build/both-20261030T133124Z`. APK-urile și checksum-urile din Download au fost
înlocuite după verificare, păstrând pachetele/datele Android separate:

- `/storage/emulated/0/Download/Godot-AI-Android-arm64-debug.apk` — 112555958 bytes;
- `/storage/emulated/0/Download/Godot-AI-Ziva-arm64-debug.apk` — 112557166 bytes.

Sunt incluse AG-66/AG-67 și corecțiile de geometrie identificate la compilare:
selectorul permite accesul la ultimul model, coada rezervă corect conversația,
spațierile și composerul se compactează pe ferestre joase. Proba focalizată
la 363 px trece **106/0**, cu captură inspectată. Testele vechi pentru Running
Tools, ordinea mesajelor cu părinți diferiți și selectarea blocului de cod au
fost actualizate; proba tactilă completă trece **129/0**, fără întreruperea
verificărilor de text/cod/imagine.

CI standard ([41102313115](https://github.com/JDscript1/godot-ai-android/actions/runs/41102313115)):
workflow reușit; runtime **922/0**, cinci configurații randate **895/0** fiecare,
editorul nativ compilat **926/0** fiecare, probe focalizate fără erori și
companion **9/0**. CI Ziva
([41102315042](https://github.com/JDscript1/godot-ai-android/actions/runs/41102315042)):
toate cele trei joburi `runtime`, `android`, `native-editor` au încheiat cu
`success`, pentru același commit și aceeași încercare. Ambele workflow-uri au
finalizat ulterior `completed/success`. Agregatul Ziva întârziase la livrare;
utilitarul acceptă această situație numai când toate
cele trei joburi exacte au trecut. Lipsa unui job, alt commit/run/attempt,
statusul neterminat, eșuat sau anulat blochează livrarea. Protecția are **8/0**
teste locale. Modificarea utilitarului de livrare nu schimbă codul aplicației.

Ambele APK-uri au trecut verificarea semnăturii persistente, identificatorului,
ABI-ului ARM64, a celor **44** de scripturi exacte, a adaptorului Ziva, a celor
**2678** fișiere Linux și a executabilelor PRoot/loader/probe. Hash-urile din
Download corespund artefactelor și fișierelor `.sha256` după înlocuire.

Dovezi complete: `.ai-qa/compile-both-20261030T133124Z/verification.json` și
`report.md`; rundele intermediare rămân în directoarele `attempt1`–`attempt4`.
Checkout-ul principal și modificările anterioare ale utilizatorului sunt
păstrate; snapshot-ul de compilare este separat.

**Limite:** APK-urile nu au fost instalate în această etapă. WebView Ziva,
tastatura, gesturile Android fizice și fluxurile cu modele/furnizori reali
rămân de verificat pe telefon. Randarea Linux nu înlocuiește aceste probe.

Jurnal: 30.10.2026 — AG-68, ambele distribuții compilate, verificate și
înlocuite separat în Download.

## AG-67 — panoul Ziva: conversație, tastatură și addonuri — 30.10.2026

Sunt implementate în surse trei corecții pentru **Ziva Preview**, independent
de harness-ul agentului nativ. Adaptorul original al gazdei compactează bara
și composerul pe ferestre mici, păstrează panourile suplimentare sub **Detalii**
și limitează zona cu notificări/todo, pentru a lăsa loc conversației. Textul
lung rămâne derulabil; controalele oficiale și paginile de setări sunt păstrate.
Pachetul oficial Ziva nu a fost modificat sau copiat în sursele aplicației.

Focusul programatic după Trimite, deschiderea/închiderea Setărilor sau
schimbarea conversației nu mai autorizează singur tastatura. Atingerea unui
câmp, activarea accesibilă și Tab permit editarea. Ascunderea tabului și
setările native șterg intenția veche de editare; WebView transmite în continuare
evenimentele paginii și gazda ascunde IME după atingeri fără câmp selectat.

Backend-ul separat primește un inventar actualizat al addonurilor salvate,
inclusiv cele dezactivate și extensiile native. **Instalarea**, **activarea**,
**prezența bibliotecii Linux ARM64** și **încărcarea verificată** sunt distincte.
Contextul global al gazdei cere citirea inventarului înainte de concluzii;
nu înlocuiește `AGENTS.md` din proiect și nu repornește o conversație activă.
Actualizarea fișierelor este atomică; o probă PRoot a confirmat vizibilitatea
înlocuirii atomice prin legătura de fișier. Lipsa unei biblioteci Terrain3D
pentru Linux nu este declarată addon absent și nu este reparată prin ștergerea
instalării Android. Biblioteca lipsă nu este compilată automat de această etapă.

Probe: `.ai-qa/ziva-mobile-20261030/`. Compilarea Kotlin focalizată a trecut,
cu **111/0** verificări companion (21 noi pentru inventar), iar proba DOM are
**20/0**, cu focusul și gesturile simulate. Backend-ul oficial Ziva v3.3.2 în
Godot Linux a trecut **7/0** citiri MCP pe un proiect izolat, cu un addon fixture
Terrain3D și bibliotecă lipsă: contextul și inventarul sunt accesibile, originalul
proiectului este păstrat. Un addon adăugat în timpul sesiunii devine citibil
în inventar și context prin același backend. Raport: `.ai-qa/ziva-mobile-20261030/verification.json`.
Aceasta nu confirmă răspunsul unui model real.

Randarea nu este validată: Chromium și headless-shell se închid cu SIGTRAP în
PRoot, inclusiv după completarea datelor ICU. Testul browser pregătit rămâne
local, neexecutat cu succes. ADB nu are dispozitive conectate. Tastatura,
spațiul efectiv al conversației și fluxul Ziva cu model real necesită proba
următorului APK pe telefon. Nu s-a recompilat/înlocuit/instalat APK-ul și nu
s-a făcut push. Detalii: [docs/AI_ZIVA.md](docs/AI_ZIVA.md).

Jurnal: 30.10.2026 — AG-67, adaptare Ziva în surse, inventar addonuri și probe
Kotlin/DOM/MCP; randarea și WebView/IME Android rămân nevalidate.

## AG-66 — dezvoltare verificată, recuperare și experimente — 30.10.2026

Sunt implementate în surse toate cele opt direcții acceptate: reparații cu
baseline și regresii, relații scene/noduri/scripturi/semnale și impact
tranzitiv, jurnal durabil al efectelor și cozii, scenarii de gameplay salvate,
copii independente cu integrare verificată, pregătirea asseturilor, metrici
native din joc și memorie/specialiști configurabili. Instrumentele sunt
înregistrate în harness-ul propriu Godot; nu cer Termux, PRoot sau Ziva.

`engineering_store.gd` persistă intenția înaintea efectelor și rezultatul
înaintea confirmării. Un apel plătit cu rezultat incert nu poate fi repetat
prin simpla schimbare a ID-ului apelului. Reconcilierea verifică jobul original;
fără ID confirmat nu inventează o asociere. Chitanțele finalizate sunt arhivate
individual pentru a evita un plafon de pași productivi. Coada se restaurează
pe pauză, iar copiii întrerupți nu se relansează automat.

Scenariile au condiții măsurate, versiuni și amprente ale proiectului.
Reparația cere un defect observat și reluarea nemodificată a scenariilor
inițiale pe sursele curente. O ipoteză, absența observațiilor sau erorile
istorice din sesiuni oprite nu devin dovadă de reparație. Datele native sunt
legate de sesiunea/generația debuggerului și de directorul/scena jocului;
un proces vechi în curs de oprire nu poate fi acceptat drept o probă nouă.
Inputul este eliberat și numai procesul propriu este închis.

Experimentele sunt copii de fișiere cu hash-uri, nu sandbox-uri de securitate.
Lansatorul nativ evită autosalvarea proiectului original. Integrarea cere o
probă trecută pe copia actuală, verifică editările manuale ulterioare și
pregătește un lot recuperabil; un subset netestat nu este certificat implicit.
`asset_prepare` produce un prefab nou cu scară/pivot, LOD-uri native și
coliziuni, păstrează GLB-ul și înregistrează prefab-ul în jurnalul restaurării.

Profilarea colectează intervalele reale ale cadrelor și monitoarele jocului,
cu warmup și condiții comparabile. Nu reprezintă FPS-ul editorului, timing
GPU sau RAM total Android. Memoria explicită poate fi inspectată/uitată în
**Setări → Dezvoltare verificată**; specialiștii au allowlist verificat și în
dispatcher, rămân fără drept de editare directă și folosesc profilele salvate.

Dovezi: `.ai-qa/engineering-20261030/`. Suita runtime finală are **922/0**;
fișierele, copia proiectului, GLB-ul și prefab-ul sunt reale, însă diagnosticul
și peer-ul de gameplay din testele noi sunt simulate. Proba grafică completă
`full-traced` a trecut **895/0**; secțiunea nouă la scară de telefon a trecut
**65/0**, cu randarea inspectată. Cele două unități C++ modificate se compilează
local ca obiecte ARM64 cu definițiile editorului și calea generică; aceasta
nu este o legare a editorului, o compilare Android completă sau un APK. Sunt
verificate **44 de scripturi încorporate**, identice octet cu octet cu sursele.
Proba finală focalizată a harness-ului a trecut **78/0**, iar pagina nouă
la scară de telefon **65/0**. Raport: `.ai-qa/engineering-20261030/verification.json`.

A fost reprodusă și o cădere nativă intermitentă în rulările complete,
însoțită de erori X11 și fără eroare GDScript. O rulare ulterioară trecută nu
stabilește cauza și nu dovedește remedierea ei. Testele focalizate ale
harness-ului au executat inclusiv 36 cereri părinte și 106 cereri copil.
Lansarea copiilor, profilarea, oprirea/recuperarea proceselor pe Android și
furnizorii reali cer următorul APK și probe pe dispozitiv. Nu s-a recompilat,
înlocuit sau instalat APK-ul; nu s-a făcut push. Detalii și exemple:
[docs/engineering-workflows.md](docs/engineering-workflows.md).

Jurnal: 30.10.2026 — AG-66, toate cele opt direcții în surse, instrumente native
și probe separate pentru stocare/asseturi, peer simulat și interfață.

## AG-65 — citiri vizibile, navigare la sursă și diagrame native — 30.10.2026

Cardurile de operații afișează acum rezultatul original al citirii/căutării,
cu numerele liniilor, contextul potrivirilor și căi accesibile prin atingere.
Restaurarea conversației asociază fiecare rezultat apelului precedent, inclusiv
peste granița paginării și când furnizorul reutilizează ID-ul; nu citește din
nou discul pentru a fabrica un rezultat vechi. Conținutul este construit la
deschiderea operației, limitat și trecut prin redactorul existent înainte de
trunchiere. Sunt marcate afișările parțiale. Payload-urile arbitrare nu intră
în widgeturile fragmentelor.

Linkurile `res://...:linie:coloană` / `#Llinie`, inclusiv Markdown și inline-code,
folosesc navigarea nativă, cu verificarea căii la atingere. Scripturile se
deschid la linia/coloana reală; scenele și resursele folosesc editorul lor.
Textul UTF-8 uzual și shaderele au o fereastră nativă doar pentru citire, cu
linii și cursor. Fișierele inexistente, traversările și căile interne sunt
respinse. Publicarea cardurilor nu deschide automat fișiere sau viewer-e.

Blocurile Mermaid încheiate au un renderer GDScript pentru flowchart și
stateDiagram-v2 plat: noduri, ramuri, legături etichetate și cicluri. Are
sursă/copiere, zoom, încadrare și deplasare explicită prin Explorează; glisarea
normală continuă să deruleze conversația. Înălțimea cadrului se adaptează
spațiului disponibil. Sursele incomplete sau nesuportate rămân vizibile cu
explicație. Acesta este un subset documentat, nu compatibilitate Mermaid
integrală. Nu necesită JavaScript, Termux, PRoot ori un serviciu extern pe
dispozitiv. Instrucțiunile agentului descriu exact sintaxa disponibilă.

Verificare efectuată cu Godot oficial 4.7.2 Linux ARM64 în Debian/PRoot:

- **822 aserțiuni runtime, 0 eșecuri**, pe sursele finale; parser, limite,
  mascarea datelor, adaptoare și regresiile existente.
- **74 verificări ale widgeturilor reale, 0 eșecuri**, în scenariul `inspections`
  la densitate de telefon: navigare script la linie/coloană, atingere nativă a
  linkurilor proiectului, fereastră text cu scalare/evidențiere, istoric paginat,
  diagrame, zoom/deplasare, fallback și încadrarea buclelor.
- Proba pe ecran lat a trecut **72/0** înaintea ultimelor ajustări mici pentru
  bucle și fontul ferestrei text; acele ajustări sunt acoperite de proba 74/0.
- **116 verificări de regresie `presentation`, 0 eșecuri**, pe sursele finale:
  gruparea mesajelor, streaming, operații, fișiere, cod lung, linkuri,
  derulare/tastatură și ciclul conversației.
- `git diff --check`, compilarea Python a builderului/runnerului și manifestul
  celor 39 de scripturi native au trecut.

Dovezi: `.ai-qa/chat-inspections-20261030/verified-runtime.log`,
`verified-phone/phone_compact/editor-report.json`, capturile inspectate și
`verification.json`. Evenimentele tactile sunt simulate în editorul real;
nu reprezintă atingeri pe un telefon fizic.

**Suita generală `all` nu este declarată trecută.** Două rulări au întâlnit
crash-uri native Godot/X11 (semnal 11), în puncte diferite, fără eroare GDScript
raportată. Sunt păstrate `full/narrow/editor.log` și
`full-retry/narrow/editor.log`. Încercarea de diagnostic cu un singur fir
llvmpipe a fost oprită după progres insuficient (`full-llvmpipe-single`), fără
raport final. Cauza nu este stabilită și necesită investigare separată; nu o
atribuim cu certitudine driverului sau codului aplicației.

Nu a fost compilat/livrat un APK și nu a fost modificat instalatorul din
Download. Nu sunt probe fizice Android sau cereri către furnizori reali.

Documentație: [Inspecții și diagrame](docs/chat-inspections-and-diagrams.md).
Memoria automată, subagenții configurabili și checkpoint-urile istorice ale
proiectului rămân lucrări viitoare distincte.

Jurnal: 30.10.2026 — AG-65: fragmente de citire/căutare, navigare la linie,
restaurare fidelă a rezultatelor și diagrame native cu fallback la sursă.

## AG-64 — prezentarea conversației și interacțiune tactilă — 30.10.2026

Panoul agentului Godot AI grupează intervențiile consecutive ale aceleiași
sarcini într-un răspuns cu un singur antet. Actualizările anterioare sunt în
„Progres”, iar rezultatul curent, cardurile fișierelor și un singur set de
acțiuni/metadate rămân la vedere. O intervenție a utilizatorului păstrează
ordinea cronologică, chiar când este Steer în același task. Consumul cumulat
nu se repetă pe segmentele vechi. Rezultat, întrerupere, blocaj, eșec și
verificare necesară au stări distincte, fără a inventa dovada gameplay-ului.

Streaming-ul păstrează widgeturile paragrafelor deja încheiate și actualizează
doar blocurile schimbate. Fence-urile de cod sunt recunoscute pe linii,
inclusiv cele parțiale și cele cu tilde; backtick-urile din cod nu mai rup
blocul. Codul lung se poate extinde, iar copierea păstrează sursa completă.
Căutarea deschide atât progresul restrâns, cât și codul care ascunde potrivirea.

„Running Tools · Image Generator / 3D Generator / …” apare numai în timpul
operației. Istoricul „Operații” păstrează rezultate, durate și erori, cu detalii
copiabile și acces la jurnal. Rezultatele reutilizate și trimiterile neconfirmate
sunt distincte. Datele arbitrare ale furnizorului nu sunt multiplicate în
widgeturi. Lista restrânsă nu construiește rândurile tuturor apelurilor;
deschiderea afișează ultimele 20, cu paginare pentru cele anterioare. Duratele
noi sunt păstrate în istoricul nativ; pentru istoricul vechi nu se inventează.

Fișierele au carduri compacte cu Deschide, fixare și meniu pentru restul
acțiunilor. Nu se deschide automat viewer-ul. Reutilizarea unui ID de apel
nu mai poate ascunde un fișier nou; republicarea aceluiași fișier rămâne
deduplicată în grup. Planurile interactive și ciclul existent de playtest
sunt păstrate. Tabul Ziva rămâne independent.

Glisarea navighează în chat, apăsarea lungă copiază textul, iar atingerea unui
link HTTP(S) folosește hit-testing-ul nativ fără selectare accidentală.
Derularea manuală dezactivează urmărirea; săgeata revine la ultimul mesaj.
Probele includ păstrarea poziției în timpul streaming-ului și un câmp de
scriere cu cursor vizibil deasupra tastaturii simulate.

Verificat pe sursele finale cu Godot 4.7.2 ARM64 în Debian/PRoot:
**791/0 aserțiuni runtime**, **854/0 verificări în suita completă a editorului**
și **114/0 verificări cu scalare de telefon**. Au fost inspectate capturile
înguste, cele largi și cele cu scalare de telefon. `git diff --check` trece.
Probele folosesc widgeturile reale, istoric restaurat, rezultate deterministe
și input tactil injectat în viewport-ul Godot, fără control global Android.

Dovezi: `.ai-qa/chat-presentation-20261030/runtime-verified.log`,
`verified-all/narrow/editor-report.json`, `verified-phone/phone_compact/editor-report.json`,
capturile asociate și `verification.json`. Scenariul nou `presentation` este
inclus în suita `all`.
[Comportamentul complet al chatului](docs/chat-presentation.md).

Limite: teste deterministe și editor Linux în Debian/PRoot, fără apeluri live
la furnizori și fără probă fizică Android. Nu s-a recompilat APK-ul, nu s-au
înlocuit instalatoare în Download și nu s-a făcut push.

Jurnal: 30.10.2026 — AG-64: răspunsuri grupate, streaming pe blocuri,
operații persistente, carduri și interacțiune tactilă; 791/0 runtime,
854/0 editor și 114/0 scalare de telefon, fără livrare APK.

## AG-63 — workflow nativ, Ask, Queue/Steer și compactare în sarcină — 30.10.2026

Workflow-ul descris după analiza Ziva este implementat în agentul propriu,
în GDScript. Modurile existente Auto, Default și Plan sunt păstrate, iar Ask
adaugă citire și explicații fără modificări, rulări, shell sau generări.
Catalogul și dispatcher-ul verifică separat această limită; Ask exclude și
polling-ul de asseturi care poate declanșa import automat. Se păstrează
migrarea selecțiilor Plan vechi, întrebările interactive, verificarea criteriilor,
permisiunile și separarea tabului Ziva.

Mesajele trimise în timpul lucrului intră în Queue fără să oprească sarcina.
`/steer`, Ctrl/Cmd+Enter și butonul „În task” livrează ajustări în sarcina
curentă, la limita dintre operații. Apelurile încă neexecutate sunt închise cu
`steered` înaintea mesajului nou; rezultatele deja confirmate sunt păstrate.
Intervențiile au același `turn_id`, păstrează fișierele/referințele și sunt
livrate în ordine. Sunt legate de task, model, mod și efort, ca să nu ajungă
într-o altă sarcină. O coadă pusă pe pauză nu repornește automat la începerea
sau terminarea altei sarcini. Pentru companion, Steer rămâne Queue.

Harness-ul poate compacta semantic contextul în interiorul unei sarcini.
Rezumatul este validat și salvat atomic; cererea inițială și intervențiile
rămân mesaje exacte ale utilizatorului, inclusiv când fereastra mesajelor
recente începe mai târziu. Tăierea păstrează perechile apel–rezultat și ultimul
lot. Istoricul integral, planul, dovezile și registrul efectelor sunt păstrate;
Stop, o eroare sau un context sursă schimbat nu pot confirma un rezumat parțial.
Consumul compactărilor automate intră în totalul sarcinii, estimat explicit
când furnizorul nu raportează tokenii. Schimbarea selecției de model nu mai
elimină consumul raportat de sarcina aflată încă în lucru.

Planurile neterminate primesc trei reamintiri cu starea reală înaintea opririi
pentru lipsă de progres. Rulările normale nu au o limită globală nouă de pași.
Implementarea nu instalează și nu copiază cod vendor Pi/Ziva și nu introduce
o dependență Linux pentru harness-ul direct.

Verificat pe sursele finale cu Godot 4.7.2 ARM64 în Debian/PRoot:
**785/0 aserțiuni runtime**, **778/0 verificări ale panoului în editor** și
**116/0 verificări workflow cu scalare de telefon**. Captura interfeței a fost
inspectată vizual. Probele acoperă integrarea reală panou–harness, generarea
simulată anulată înainte de execuție, Ask, persistența intervențiilor, ordinea
cozii, izolarea sarcinilor, Stop, contextul și verificările existente.
`git diff --check` trece.

Dovezi: `.ai-qa/native-workflow-20261030/runtime-verified.log`,
`all-final/narrow/editor-report.json`, `phone/phone_compact/editor-report.json`,
`phone/phone_compact/workflow-queue-steer.png` și `verification.json`.
[Documentația workflow-ului și comenzile disponibile](docs/agent-workflow.md).

Limite: furnizori simulați, editor Linux, fără probă live DeepSeek/Runware sau
Android fizic. Mesajele încă nelivrate din coadă sunt în memoria panoului și
nu sunt garantate după închiderea procesului. Nu s-a recompilat APK-ul,
nu s-au înlocuit instalatoarele din Download și nu s-a făcut push.

Jurnal: 30.10.2026 — AG-63: workflow nativ cu Ask, Queue/Steer și compactare
semantică în sarcină; 785/0 runtime, 778/0 editor și 116/0 layout de telefon;
implementat și verificat în surse, fără livrare APK.

## AG-62 — analiză statică Ziva și recuperarea harness-ului propriu — 30.10.2026

La cererea utilizatorului a fost extras bundle-ul Bun din `zivacode` oficial
v3.3.2 Linux ARM64: **194 de fișiere**, 26.450.119 bytes. Binarul original
a rămas identic, SHA-256
`7797be07153d515fb0a96a8438f811d633610e4e39caa582334e87cc5ef6c200`.
Sunt identificate componente Pi (`pi-agent-core`, `pi-ai`, `pi-coding-agent`),
sesiuni, compactare și recuperare overflow; acestea adaugă dovezi locale față
de cercetarea publică anterioară. Nu se declară versiunea exactă Pi, reconstrucția
proiectului original sau decompilarea bibliotecilor native. Codul vendor extras
rămâne numai în `.ai-qa/`, ignorat de Git.

Harness-ul nostru GDScript primește implementări originale: reducerea
rezultatelor vechi din context înaintea cererilor, o singură recuperare după
overflow confirmat, citiri proaspete la reutilizarea ID-urilor de apel și
detectarea aceleiași erori chiar dacă este intercalată cu citiri reușite.
Cererea, planul, ultimul lot de instrumente, istoricul integral și registrul
operațiilor rămân păstrate. Scrierile și joburile plătite nu se reexecută prin
recuperarea contextului. Stop, verificarea dovezilor și pașii nelimitați rămân
active. Tabul Ziva este independent; agentul nostru nu capătă o dependență Linux.

Verificat local cu Godot 4.7.2 ARM64 în Debian/PRoot: **770/0 aserțiuni runtime**
și **91/0 verificări în editor**, scenariul de compactare îngust.
Cele 19 probe noi includ overflow, Stop, autentificare, răspuns parțial,
identitatea artefactelor, deduplicarea operațiilor plătite și erori intercalate.
`git diff --check` trece. Estimarea de context rămâne euristică; compactarea
semantică în interiorul unui singur task lung este încă o direcție de lucru.

Nu s-au trimis cereri live către modele sau generatoare, nu s-a recompilat
APK-ul și nu s-au înlocuit instalatoarele din Download. Aceasta este o etapă
implementată și testată în surse, nu o probă fizică Android a noului cod.

[Analiza și comparația detaliată](docs/ziva-harness-review-20261030.md).
Dovezi: `.ai-qa/ziva-harness-analysis-20261030/`, în special `findings.json`,
`runtime.log` și `rendered/narrow/editor-report.json`.

Jurnal: 30.10.2026 — AG-62: componente Pi confirmate în bundle-ul Ziva;
recuperare context, citiri actualizate și protecție la erori intercalate în
harness-ul propriu, cu 770/0 runtime și 91/0 editor; fără livrare APK.

## AG-61 — pluginuri independente și recuperare Git Ziva — 29.10.2026

Jurnalul telefonului a identificat cauza noii opriri: Terrain3D nu livrează
`libterrain.linux.debug.arm64.so` în proiectul deschis. Verificarea de startup
trata orice `Error loading extension` drept eșec al pluginului Ziva și termina
editorul Linux înainte de încărcarea lui. Acum oprirea imediată se aplică doar
erorilor de încărcare care identifică explicit directorul oficial Ziva, pe
aceeași linie a erorii. Erorile altor pluginuri rămân în jurnal, iar verificările
reale de proprietate MCP și disponibilitate a interfeței continuă normal.
Nu se modifică pluginurile, bibliotecile sau setările proiectului utilizatorului.
Compatibilitatea binarelor native Android și Linux rămâne o cerință a pluginului;
această corecție nu transformă un binar Android într-unul Linux.

Kotlin Android compilează; testele locale trec **13/0** dependențe,
**38/0** pachet, **26/0** sesiuni și **13/0** metadate. Cele opt probe de încărcare acoperă
jurnalul real Terrain3D, erori mixte și eșecuri reale ale bibliotecii Ziva.
Sursa `8260efed` a trecut integral [CI 40949454959](https://github.com/JDscript1/godot-ai-android/actions/runs/40949454959):
**801/0 × 5** editor nativ și probele focalizate. APK-ul a fost verificat,
instalat și livrat separat în Download; Ziva a pornit efectiv în proiectul cu
Terrain3D, inclusiv după redeschidere, cu HTTP 200 și identitate MCP oficială.

Inspecția interfeței a expus și blocajul cererilor: istoricul Git local avea
legături PRoot către `tmp_objdir-bulk-fsync-*` deja mutat. Android a refuzat
proba de hardlink nativ; Git folosește acum `core.createObject=rename`, opțiunea
standard descrisă în [documentația Git](https://git-scm.com/docs/git-config.html#Documentation/git-config.txt-corecreateObject).
Pe telefon a fost configurată în runtime și în repository-ul privat de
checkpoint-uri. Copia originală a fost arhivată înainte de intervenție.
Toate cele **233 de bloburi** din index au fost recuperate din fișierele actuale,
cu SHA-1 identic; arborele rezultat este exact `464d283de16ae383ece05b42327ed77c32038cf6`.
S-a înlocuit numai depozitul privat de obiecte Git, păstrând originalul alături;
`git fsck --full` a trecut local și pe telefon. Un repository nou, cinci fișiere,
`git add` în modul bulk-fsync și `git commit` au trecut în PRoot cu setarea nouă.
Cererea „Continuă” lansată de utilizator a ajuns apoi la Beam Free și la rulare
de instrumente, cu un plan de opt sarcini. Acesta este un progres observat live,
nu dovada finalizării jocului sau a întregului plan al agentului.

Protecția este adăugată și mediului procesului Ziva, prin variabilele standard
`GIT_CONFIG_*`, pentru sesiuni și instalări noi fără modificarea configurației
Git a proiectului. Cele două probe suplimentare folosesc Git real și verifică
atât aplicarea setării în procesul copil, cât și păstrarea valorii existente în
repository. Kotlin compilează. Sursa finală **`947a7c64e8fa9def8eb1a15abc886e63a10ad52d`**
a trecut toate cele trei joburi în [CI 40955200110](https://github.com/JDscript1/godot-ai-android/actions/runs/40955200110).

APK-ul final a fost verificat și livrat în Download la **29.10.2026,
22:20:09 CET**: `Godot-AI-Ziva-arm64-debug.apk`, **112.485.144 bytes**,
SHA-256 `de839cddc8220ce186ffb518daf1e06f99fb86bf82915bdef761f6eed61ca57c`.
Pachet separat `com.jdscript.godotai.ziva.debug`, aceeași semnătură persistentă,
ARM64; **37 de scripturi** și **2.678 fișiere Linux** verificate. DEX conține
ambele verificări noi și variabilele Git de startup. Instalatorul standard și
checksum-ul lui au rămas identice, inclusiv data modificării.

Separarea dovezilor: pe telefon este instalat APK-ul `8260efed`, cu reparația
Git aplicată în datele runtime-ului și cu proba live descrisă mai sus. APK-ul
final `947a7c64` include și presetul Git automat pentru sesiuni/instalări noi,
dar **nu a fost instalat peste cererea activă a utilizatorului**. Nu se declară
proba fizică a acestui ultim binar sau finalizarea planului de opt sarcini.
Instalarea lui se poate face după încheierea lucrului agentului.

Dovezi: `.ai-qa/ziva-restart-failure-20261029T202612Z/physical-regression.json`,
`checkpoint-original.tar`, `checkpoint-device-fsck.log`, `git-bulk-probe.log`,
subdirectorul `git-compat-final/` și `.ai-qa/delivery-ziva-947a7c6.json`.

Jurnal: 29.10.2026 — AG-61: separarea erorilor de încărcare a pluginurilor
la pornirea backend-ului Ziva, recuperare checkpoint Git și probă live după
reluarea cererii utilizatorului; APK final livrat fără întreruperea cererii active.

## AG-60 — Ziva independent și sesiuni automate — 29.10.2026

Pe APK-ul instalat `0fc625a9`, ADB a confirmat eroarea veche „O altă sesiune
Ziva răspunde deja”, salvată după reboot, deși nu exista niciun proces Ziva.
Starea nouă verifică blocarea fișierului sesiunii de către serviciu, identificatorul
boot-ului și identitatea procesului; un JSON vechi nu mai poate bloca sesiunea.
Închiderea procesului editorului este observată prin Binder, iar închiderea
activității sau eliminarea aplicației oprește backend-ul și procesele proprii.
Trecerea în fundal și schimbarea tabului păstrează sesiunea. Schimbarea
proiectului înlocuiește sesiunea în ordine, fără cerere manuală de oprire.
Autopornirea folosește doar proiectul deschis și are trei încercări de recuperare
pentru o eroare repetată; nu limitează pașii agentului sau generările.

Tabul are propriul host nativ, model și panou de instalare/reparare/actualizare;
setările și construcția panoului asistentului nu mai inițializează Ziva.
Frontend-ul oficial este găzduit nemodificat. Verificarea actualizărilor citește
metadatele publice GitHub și acceptă doar arhiva oficială stabilă ARM64 cu
SHA-256. Actualizarea devine activă după verificarea executabilului și a
bibliotecilor; versiunea anterioară și istoricul rămân păstrate.

Verificat local: **751/0** aserțiuni runtime, Kotlin Android compilat,
**13/0** dependențe, **38/0** pachet/activare, **16/0** proprietate de sesiune
inclusiv moartea unui proces separat, **13/0** metadate de actualizare;
**69/0** randare Ziva îngustă, **61/0** manager upstream.
Prima rundă nativă a trecut **800/0 × 5**, dar proba focalizată de gesturi a
expus o fereastră Ziva exclusivă vizibilă la inițializare. Fereastra este ascunsă
explicit înainte de adăugare, iar verificarea de startup rulează acum în fiecare
scenariu nativ. APK-ul intermediar nu a fost livrat sau instalat.
Runda `f7eb9081` a trecut complet: **801/0 × 5** editor nativ și **125/0**
proba de gesturi. Pe telefon, backend-ul a pornit automat și vechea eroare de
sesiune a dispărut, dar fișierul temporar `.port` nu rămâne disponibil. Serverul
local răspundea efectiv HTTP 200 și MCP înainte ca aplicația să-l detecteze.
Identificarea folosește acum un director montat separat pentru fiecare proces,
cu un UUID citit prin instrumentul public MCP `read`. Astfel nu adoptă un alt
server Ziva sau un proces vechi al aceluiași proiect. Apelul public de citire a
fost verificat pe serverul real, fără model și fără modificarea proiectului.
Fișierele temporare de identificare sunt șterse după oprire.
Compilarea finală pentru sursa **`571ad569843b741710c45e515457cda532defcb8`**
a trecut integral în [CI 40933392621](https://github.com/JDscript1/godot-ai-android/actions/runs/40933392621):
toate cele trei joburi, **801/0 × 5** editor nativ, **125/0** TODO/gesturi,
**67/0** manager nativ și probele pentru panouri, generare, acces la panouri
și ciclul conversației. Cele 9 teste companion și build-ul lui au trecut.

Pe telefon, APK-ul final a pornit automat Ziva la deschiderea proiectului,
a afișat **„Ziva · Activ”** și frontend-ul oficial. Revenirea în AI Assistant
și trecerea aplicației în fundal au păstrat aceeași sesiune, același PID și
același port. Proba a terminat doar procesul Android principal al editorului:
serviciul a detectat moartea lui, a trecut în `stopped`, iar toate cele trei
procese native urmărite au dispărut. Redeschiderea completă a pornit automat
o sesiune nouă. Identitatea instalării Ziva și configurația proiectului
utilizatorului au rămas identice. Panoul propriu de instalare și actualizări
a fost inspectat pe telefon.

Limite ale probei fizice: primul intent VIEW după terminarea forțată a adus
înapoi activitatea Android păstrată în cache, fără să redeschidă proiectul.
O pornire completă cu task nou a reluat corect proiectul și Ziva; restaurarea
acelui task vechi nu este declarată validată. Nu s-a efectuat reboot fizic,
autentificare nouă sau sarcină plătită cu un model. Verificarea live a
actualizărilor din buton nu este declarată reușită: proba finală de apăsare
a fost întreruptă de o suprapunere a introducerii de text Android, fără
rezultat nou salvat. Metadatele și activarea versiunilor rămân acoperite de
testele automate descrise mai sus.

APK-ul final a fost verificat, instalat peste Ziva existent și livrat în
Download la **29.10.2026, 20:07:53 CET**: `Godot-AI-Ziva-arm64-debug.apk`,
**112.484.884 bytes**, pachet separat `com.jdscript.godotai.ziva.debug`, ARM64.
SHA-256: `51526eba2af3d44799355b8505e1f90bab98fb44dcb6f5fa6215d0581c8ccf77`.
Semnătura persistentă este păstrată; **37 de scripturi** coincid cu sursele,
iar agentul, Asset Store, managerul de proiecte și cele **2.678 fișiere Linux**
sunt prezente. Instalatorul Ziva și checksum-ul au fost înlocuite atomic.
APK-ul standard și checksum-ul lui sunt identice înainte și după livrare,
inclusiv data modificării.

Dovezi: `.ai-qa/ziva-lifecycle-20261029T174727Z/`,
`.ai-qa/compile-ziva-lifecycle-20261029T180532Z/physical-lifecycle.json`,
`native-reports.json`, `apk-verification.json`, `standard-after-delivery.json`
din același director și `.ai-qa/delivery-ziva-571ad56.json`.

Jurnal: 29.10.2026 — AG-60: înlocuirea controlului manual al sesiunii,
separarea tabului de asistent și administrarea versiunilor oficiale din Ziva;
APK final instalat și livrat, pornire/opriere și reluare completă probate pe telefon.

## AG-59 — Ziva adaptat la spațiul dispozitivului — 29.10.2026

Capturile utilizatorului arată acum autentificarea oficială Ziva pe telefon,
dar panourile laterale Godot consumau aproape jumătate din ecran. Tabul Ziva
intră automat în zona de lucru extinsă și restaurează configurația anterioară
la revenirea la alt tab, fără schimbarea preferințelor salvate scene/script.
WebView-ul respectă viewport-ul oficial și permite zoom prin gest, fără
controale suprapuse. Navigările interne rămân în interfață; linkurile externe
HTTPS se deschid în browser. Bara ocupă un singur rând: starea scurtă, pornirea când este necesară și meniul
`⋮` pentru reîncărcare, configurare, verificare și oprire. Instrucțiunile dispar
când interfața este disponibilă. Frontend-ul oficial rămâne nemodificat.

Rezolvarea depozitului Debian folosește rețeaua Android activă; adresele sunt
reînnoite într-un bloc propriu din `/etc/hosts`, păstrând intrările existente.
Aceasta recuperează instalarea pachetelor când DNS-ul brut din guest e refuzat.
Pe telefon, instalarea reală a celor 81 de pachete tranzitive a trecut (exit 0),
iar `ldd` nu mai raportează biblioteci lipsă. Proba de rețea nativă lansată prin
serviciu a expirat anterior; succesul instalării este proba separată din același
runtime al aplicației, cu rezolvarea gazdei Debian pregătită explicit.

Oprirea serviciului semnalizează întâi procesul Godot al sesiunii, verificat
prin PID-ul din cache-ul privat și executabilul exact, astfel încât PRoot să
poată închide și procesele secundare înainte de terminarea tracer-ului.
Proba fizică a expus un proces rămas în urma pornirilor vechi; nu se declară
corectarea lui validată pe telefon înainte de instalarea noului APK.

Verificări locale: Kotlin Android compilează; rețea/dependențe **13/0**;
runtime **751/0**; randare focalizată finală îngustă și telefon landscape
**72/0**, inclusiv meniul și reîncărcarea după închiderea lui. Configurația
telefon compact a trecut **70/0** înainte de proba suplimentară de meniu.
Prima regresie nativă (`797f4a71`) a expus un conflict: chatul lateral păstra
Ziva drept ultimul tab de lucru și revenea în el, unde panourile sunt ascunse.
Memoria chatului lateral exclude acum Ziva și păstrează ultimul editor normal.
Nu s-a livrat APK-ul rundei eșuate. Runda `b13705e1` a trecut comportamentul
panourilor, dar proba îngustă a expus o lățime moștenită prea mare. Tabul este
limitat acum independent la suprafața vizibilă, inclusiv meniul; coordonatele
WebView sunt intersectate cu viewport-ul și în timpul relayout-ului. ADB a fost
deconectat de utilizator; proba fizică a noii versiuni rămâne pentru după
instalare. Compilarea finală a trecut verificările descrise mai jos. Capturile primite dovedesc frontend-ul oficial la autentificare,
nu autentificarea efectivă sau executarea unei sarcini cu model real.
Runda finală [CI 40884020493](https://github.com/JDscript1/godot-ai-android/actions/runs/40884020493)
a trecut integral pentru sursa **`0fc625a9044624a277ec85aecc30192191e8ba02`**:
**751/0** runtime, **773/0 × 5** randări upstream, **803/0 × 5** editor nativ,
**72/0** Ziva focalizat, **68/0** manager nativ și probele native pentru TODO,
panouri, generare, acces la panouri și ciclul conversației. Cele 9 teste companion
și build-ul lui au trecut. Au fost inspectate și capturile native după revenirea
la chat. Rămâne verificarea noii versiuni pe telefon, inclusiv toate ecranele
Ziva, autentificarea, tastatura și zoomul; ADB este deconectat la cererea utilizatorului.

APK-ul **`0fc625a9`** este livrat în Download la **29.10.2026, 14:58 CET**:
`Godot-AI-Ziva-arm64-debug.apk`, **112.467.916 bytes**, pachet separat
`com.jdscript.godotai.ziva.debug`, ARM64. Semnătura persistentă și toate cele
**37 de scripturi** au fost verificate; pachetul include agentul, Asset Store,
managerul de proiecte, serviciile Ziva și cele **2.678 fișiere Linux** validate.
SHA-256: `61f76bb8c7d03d93a1c665471b0d3c2fce845aafce1808b26f86bac45b9a84d3`.
Instalatorul Ziva anterior a fost înlocuit atomic, cu checksum alăturat.
APK-ul standard și checksum-ul lui au rămas identice, inclusiv data modificării.
Noua versiune nu a fost instalată automat; ADB este deconectat.

Dovezi: `.ai-qa/compile-ziva-responsive-20261029T133949Z/`,
`.ai-qa/ziva-responsive-final-20261029/` și
`.ai-qa/ziva-device-review-20261029T122722Z/`.

Jurnal: 29.10.2026 — AG-59: aspect compact, spațiu extins pentru Ziva,
rezolvare Debian prin Android și oprire explicită a procesului headless.

## AG-58 — corecție Ziva pe runtime-ul instalat — 29.10.2026

Proba ADB pe telefon a infirmat pornirea funcțională a preview-ului `234893bf`:
tabul exista, dar interfața oficială nu se încărca. În baza Debian slim din APK
lipseau `libxcb`, fontconfig și alte biblioteci legate de extensia oficială/CEF.
Proba anterioară din Debian-ul de dezvoltare, mai complet, nu acoperea baza
livrată. Verificările CI și integritatea APK-ului nu dovedeau pornirea pe telefon.

`AIZivaDependencies` verifică legăturile reale cu `ldd`, instalează bibliotecile
Debian necesare, refuză actualizarea APT incompletă și reface proba după instalare.
Rulează atât la instalare, cât și la pornire, pentru repararea instalărilor vechi.
DNS-ul Linux urmărește conexiunea Android curentă și este actualizat atomic.
Jurnalul editorului se scrie și în timpul pornirii; o eroare de încărcare a
extensiei este raportată imediat, în locul așteptării complete de trei minute.

Pe telefon, probele brute de rețea au fost refuzate când aplicația era în fundal;
în prim-plan au funcționat. Instalarea bibliotecilor este testată prin serviciul
Android real, cu runtime-ul și datele aplicației instalate, fără furnizori AI.
Sursele Kotlin compilează, iar testele portabile noi trec **11/0**. Proba de
interfață pe telefon și recompilarea preview-ului sunt în curs.
Dovezi: `.ai-qa/ziva-device-review-20261029T122722Z/`.

## AG-57 — tab principal Ziva și interfață oficială — 29.10.2026

La cererea utilizatorului, Ziva primește un tab principal lângă AI Assistant,
în editor și în managerul de proiecte. Sunt păstrate modificările celuilalt
agent din `77bd5c0`: plugin oficial complet, Godot Linux ARM64 separat și
verificarea reală a backend-ului. Nu se reintroduce puntea MCP înlocuită.

Frontend-ul oficial se afișează într-un WebView ancorat în corpul tabului,
fără Dialog separat sau bridge JavaScript privilegiat. Ascunderea tabului
păstrează pagina și procesul; oprirea este explicită. Coordonatele normalizate
sunt raportate la suprafața Godot, se recalculează la schimbarea dimensiunilor
și se limitează la zona vizibilă a ferestrei Android. Ferestrele Godot ascund
temporar WebView-ul. Selectorul de fișiere este al sistemului Android.

APK-ul separat **`234893bf`** este compilat și livrat în Download:
`Godot-AI-Ziva-arm64-debug.apk`, **112.461.256 bytes**, pachet
`com.jdscript.godotai.ziva.debug`, ABI `arm64-v8a`. Runda
[CI 40870748187](https://github.com/JDscript1/godot-ai-android/actions/runs/40870748187)
a trecut integral: **751/0** runtime, **768/0 × 5** editor upstream și
**792/0 × 5** editorul nativ recompilat. Proba Ziva focalizată: **67/0**;
pornirea nativă, inclusiv tabul Ziva din manager: **68/0**. Cele 9 teste
companion și build-ul lui, livrarea 6/0 și controalele Linux/Blender au trecut.
Compilarea Kotlin locală a trecut; Gradle a compilat apoi activitatea reală.

Toate cele **37 de scripturi** coincid byte cu byte cu sursele compilate.
S-au verificat agentul, noul plugin `AIZivaEditorPlugin`, Asset Store, managerul
de proiecte, cele **2.678 fișiere Linux** și binarele ARM64 PRoot/loader.
SHA-256: `e5f2646b525bbaf5568729bfcb0c7bf501cc3cd654b0346fb28f4c77d7fb448a`.
Semnătura persistentă este păstrată. Copia Ziva `77bd5c0` a fost eliminată după
verificarea identității; instalatorul standard și checksum-ul lui au rămas
identice, inclusiv data modificării. Nu s-a instalat automat aplicația.

Prima probă locală a expus o problemă a fixture-ului: după ascunderea manuală
a chatului pentru tabul temporar, acesta nu era restaurat explicit. Fixture-ul
a fost corectat; CI final a trecut toate cele cinci configurații upstream și
native. O întrerupere de rețea la descărcarea artefactului a fost recuperată,
fără modificarea artefactului sau relansarea compilării.

Dovezi: `.ai-qa/compile-ziva-tab-20261029T115729Z/` — `context.json`,
`ci-all.log`, `ci-test-summary.txt`, `apk-verification.json`, `signature.txt`,
`standard-before-delivery.json`, `standard-after-delivery.json` și `report.md`.
Livrare: `.ai-qa/delivery-ziva-234893b.json`. Captura locală a tabului este
inspectată, cu backend simulat; frontend-ul proprietar nu a fost simulat.
Autentificarea oficială, selectorul de fișiere, tastatura WebView și un flux
Ziva real rămân de verificat pe telefon.

Jurnal: **29.10.2026 — AG-57, tab principal Ziva, backend oficial independent;
APK separat `234893bf` verificat și livrat, instalatorul standard păstrat.**

## AG-56 — Ziva independent, preview în surse — 29.10.2026

Compilarea și livrarea unui **APK separat** au fost solicitate explicit la
29.10.2026. Fluxul pornește pe o ramură izolată, cu distribuția `ziva-preview`.
Până la verificarea artefactului final, instalatorul standard `090b939` din
Download rămâne păstrat; acest paragraf nu confirmă încă o livrare nouă.

La cererea utilizatorului, integrarea nu mai folosește o punte proprie: se
folosesc **pluginul și interfața oficială Ziva** într-un editor Godot Linux
separat, headless, în paralel cu editorul Android și agentul nostru. Pluginul
oficial este GDExtension Linux ARM64 (glibc), deci nu poate fi încărcat în
editorul Android (Bionic); arhitectura aprobată descarcă arhiva oficială
completă v3.3.2 și Godot 4.7.2 Linux ARM64 și rulează ambele sub PRoot, cu
addon-ul montat în `/workspace/addons/ziva_agent`. Interfața oficială rămâne
în WebView-ul Android, pe `127.0.0.1`, portul descoperit în 7012–7041.

Instalatoarele (`AIZivaPackage`, `AIZivaGodot`) descarcă de la furnizor, verifică
dimensiunea și SHA-256 ale arhivelor, extrag numai conținutul necesar (addon-ul
complet de aproximativ 503 MB, respectiv executabilul Godot), refuză căile
nesigure, duplicatele, legăturile simbolice și depășirile de dimensiune/număr,
acordă drept de execuție și activează atomic, păstrând instalarea anterioară
până la validarea înlocuitorului. APK-ul nu redistribuie binare proprietare;
licența Ziva rămâne a furnizorului.

`AIZivaService` rulează într-un proces separat, verifică ambele pachete și
proiectul, refuză o sesiune deja activă, montează datele XDG și `.godot` privat
pe proiect, lansează Godot-ul oficial cu `--headless --editor` și declară
pornirea reușită numai după HTML 200, identitatea MCP `ziva-godot` v3.3.2 și un
apel `get_project_info` cu rezultat nevid. Portul este publicat abia atunci;
heartbeat-ul verifică interfața și oprește sesiunea după 30 de eșecuri.
La etapa AG-56, `AIZivaWindow` păstra fereastra ca Dialog în activitatea editorului (înlocuit în AG-57 cu tab principal), fără
bridge JavaScript privilegiat, și permite numai navigarea către același host și
port. `ziva.gd` face numai control de proces (install/start/stop/open), iar
`open` cere proiectul curent și un port valid.

Puntea anterioară `editor_mcp.gd` și configurația `AIZivaMcpConfig` cu token în
`.mcp.json` au fost eliminate, împreună cu testele, starea `editor_connected` și
fallback-ul «Copiază conexiunea»: interfața oficială își folosește propriile
unelte în editorul ei, deci un al doilea traseu de control nu era necesar.

Verificat local: runtime Godot **750/0**, regresie editor îngust
**756/0**, panou Ziva focalizat **55/0** (captură inspectată), pachet Ziva
**33/0**, Godot pentru Ziva **19/0**, arhivă Linux **6/0**, rootfs **4/0** și
livrare **5/0**. Instalatoarele au extras arhivele oficiale reale din cache:
`zivacode` 116.771.624 bytes și Godot 137.953.888 bytes, cu drept de execuție.
Proba separată în Debian/PRoot, cu aceleași montări, a confirmat interfața HTML
la `127.0.0.1:7012`, identitatea MCP `ziva-godot` v3.3.2 și `get_project_info`;
proiectul gazdă a rămas nemodificat. Gradle generase anterior BuildConfig pentru
ambele identificatoare, iar fuziunea manifestelor preview trecuse cu
identitatea, numele și politica loopback păstrate.

Jurnal: **29.10.2026 — AG-56, Ziva preview folosește pluginul și interfața
oficială într-un editor Godot Linux separat; instalatoarele, serviciul și
panoul sunt implementate și verificate în surse, fără APK, dispozitiv sau model
real.**

Dovezi: `.ai-qa/ziva-native/` (loguri Kotlin, `ZivaLiveInstallTest.kt`,
`runtime-final.log`), `.ai-qa/full-final/narrow/` (raport complet
`editor-report.json` și jurnal), `.ai-qa/ziva-final/narrow/` (raport și
captură focalizate) și `.ai-qa/ziva-native/full-final.log`. Instalatorul standard `090b939` din
Download rămâne păstrat; nu s-a compilat, publicat sau înlocuit un instalator
în această continuare. Detalii și pașii rămași în [AI_ZIVA.md](docs/AI_ZIVA.md).

## Publicare GitHub — 29.10.2026

Ramura principală `ai/android-assistant` primește istoricul surselor compilate și validate `090b939`, plus documentația finală de livrare. Cele 35 de surse runtime și fișierele native/testele coincid cu snapshot-ul verificat; diferențele ulterioare sunt numai documentare. Validarea asociată rămâne runda CI 40764656531, trecută integral. APK-ul din Download rămâne `090b939`; publicarea documentației nu reprezintă o nouă compilare sau instalare.

## APK recompilat și livrat — AG-53–AG-55, 28.10.2026

Versiunea **`090b939`** a înlocuit instalatorul anterior din Download, după toate verificările. Runda [CI 40764656531](https://github.com/JDscript1/godot-ai-android/actions/runs/40764656531) a trecut integral: runtime, editor nativ recompilat și Android ARM64. Snapshot-ul este pe ramura izolată `build/panels-chat-20261028T202655Z`; modificările locale și ramura de lucru a utilizatorului sunt păstrate.

Rezultate: **749 aserțiuni runtime**, **744 verificări × 5** în editorul upstream și **772 × 5** în editorul nativ, fără eșecuri. Probe native dedicate: todo **122/0**, panouri **63/0**, pornire **60/0**, generare **59/0**, acces panouri **64/0**, chat/playtest/capturi **68/0**. Cele 9 teste companion și build-ul lui au trecut, precum și testele de livrare și Linux/Blender. Citirea erorilor reale, cu Debugger ascuns, după Stop și într-o sesiune nouă, a rulat în editorul compilat.

Prima rundă a găsit o incompatibilitate a fixture-ului Plan cu noul contract de urmărire a chatului: navigarea programatică către o opțiune mai veche nu suspenda urmărirea. Fixture-ul declară acum explicit această navigare înainte de click/touch; proba focalizată peisaj a trecut **72/0**, iar regresia locală completă **744/0**. Toate cele cinci configurații au trecut apoi în runda finală upstream și nativă.

APK-ul are **112.416.402 bytes**, pachet `com.jdscript.godotai.debug`, ABI `arm64-v8a`, aceeași semnătură persistentă și SHA-256 `50fe77a2beae9c48fa9f5a0544826b77bd0fff918ecaf2009ca83f26a3edb728`. S-au verificat byte cu byte toate cele **35 de surse runtime**, prezența agentului, Asset Store-ului și managerului de proiecte, precum și cele **2.678 fișiere** ale bazei Linux și binarele ARM64 PRoot/loader.

Instalator: `/storage/emulated/0/Download/Godot-AI-Android-arm64-debug.apk`, cu checksum alăturat. Copia înlocuită este păstrată în `.ai-qa/compile-panels-chat-20261028T202655Z/previous-installer.apk`. Nu s-a instalat automat aplicația. Tastatura fizică Android, gesturile pe dispozitiv și comportamentul modelelor prin API rămân de acceptat; testele de furnizori sunt simulate.

Dovezi: `.ai-qa/compile-panels-chat-20261028T202655Z/` — `context.json`, `snapshot-files.json`, `ci-all.log`, `ci-test-summary.txt`, `apk-verification.json` și `report.md`; livrare: `.ai-qa/delivery-090b939.json`. Notele «în surse / fără APK nou» din etapele AG-53–AG-55 descriu starea anterioară acestei livrări.

## AG-55 — playtest temporar, capturi și navigare în chat, în surse

`godot_run` refolosește sesiunea scenei; repornirea și păstrarea jocului deschis sunt explicite. Sesiunile pornite pentru verificare sunt închise la final/Stop, inclusiv în cazul eșecului inițial al subagentului. Semnalele EditorRunBar protejează sesiunile pornite sau repornite manual.

Capturile automate noi au cache privat separat: deduplicare, maximum 64 capturi nefixate / 64 MiB / 24 ore, protecție prin fixare și eliberarea miniaturilor expirate din UI. Atașamentele originale, asseturile generate și vechile fișiere nu sunt șterse. Pixelii instrumentelor nu sunt copiați în atașamente permanente sau păstrați inutil în istoricul activ.

Chatul suspendă urmărirea la derularea în sus; săgeata în jos revine la final și reactivează urmărirea. Composerul rezervă spațiul ocupat de tastatura Android și păstrează cursorul accesibil în mesaje lungi.

Verificări: **749 aserțiuni runtime**, **744 verificări de regresie în editor**, fără eșecuri. **68 verificări focalizate în fiecare dintre configurațiile narrow și phone_compact**, pe sursele finale, fără eșecuri. Probele și limitele sunt consemnate în raportul `.ai-qa/chat-lifecycle-20261028/`. Cele **35 de surse încorporate** coincid cu fișierele runtime. Tastatura din probe este simulată; acceptarea fizică Android și verificarea alegerilor unui model real rămân necesare. Fără APK nou în această etapă.

[Contract, retenție și limite](docs/AI_CHAT_AND_PLAYTEST.md).

## AG-54 — citirea panourilor și a datelor interne, în surse

Adăugate `godot_panels`, `godot_panel_read` și `godot_panel_data`. Inventarul
include controale interne, dock-uri și file ascunse, ferestre și pluginuri;
poate fi restrâns la un subarbore. Cititorul citește Tree colapsat, liste,
meniuri, tab-uri, cod/text/tooltip, valori, culori, texturi și grafuri standard,
fără deschiderea sau modificarea UI. Snapshot-urile sunt paginate și au limite
și prospețime explicite. Scena editată nu consumă bugetul inventarului general.

Verificări locale: **746 aserțiuni runtime**, **742 verificări extinse în editor** și **64 verificări finale focalizate**, fără eșecuri. Au trecut și sintaxa/tipurile pentru **șapte unități C++**; cele **35 de scripturi** se încorporează identic cu sursele.

Surse dedicate: Output nativ, Profiler, Visual Profiler, Monitors și istoricul
lor, Video RAM, stack, variabile, fire oprite, breakpoint-uri, Inspector,
selecție, magistrale audio și animații/piste/chei. Variabilele încă în încărcare
și sursele fără eșantioane nu sunt tratate drept valori zero. Cache-urile VRAM
și Visual Profiler își păstrează generația, inclusiv după începerea unei alte
sesiuni. Citirea nu pornește colectarea, nu face Refresh și nu execută expresii.

Harness-ul păstrează cursorii când scurtează un rezultat și nu sare peste rânduri
sau caractere nelivrate. Datele vechi, opace sau incomplete nu emit dovezi noi de
citire completă. Contoarele de joc numite TokenCounter rămân lizibile; câmpurile
credentialelor și interfața internă a asistentului sunt excluse.

[Acoperire, contracte și limite](docs/AI_PANEL_ACCESS.md). Probele și hash-urile
sursei: `.ai-qa/panels-20261028/`. Cititoarele native C++ necesită recompilare;
verificarea statică nu este prezentată drept execuție pe Android. Datele private
ale unui plugin care desenează custom cer adaptor/API sau captură vizuală.
APK-ul livrat anterior rămâne separat de aceste modificări în surse.

Jurnal: 28.10.2026 — AG-54 implementat în surse; acces general la panouri și surse
native/publice dedicate, paginare și proveniență. Livrarea APK rămâne deschisă.

## AG-53 — acces direct la erorile Debuggerului, 28.10.2026

Auditul APK-ului `47cc26e` a confirmat că `godot_output` returna gol în prezența
unor erori: citea numai RichTextLabel vizibile, iar lista Debuggerului folosește
Tree. Erorile puteau fi primite parțial prin `playtest_observe` în timpul rulării.

Implementat în surse: captură structurată a mesajelor remote în Debugger,
independent de vizibilitate și de RPC-ul AI din joc; mesaj, severitate, sursă,
linie, funcție, stack și sesiune. După Stop lista rămâne accesibilă; o conexiune
nouă sau Clear Errors o resetează cu UI-ul. Buffer-ele au limite explicite și
contoare totale. Noul `godot_debugger` este conectat și la diagnosticul unificat,
Output și starea rulării. Agentul primește instrucțiuni pentru citirea listei și
verificarea unei sesiuni noi după corecții. Lipsa accesului, trunchierea sau
textul gol al consolei nu confirmă un proiect fără erori.

Probe și limite: `.ai-qa/debugger-20261028/report.md`. Au trecut local **716 aserțiuni runtime**, **722 verificări complete în editor narrow** și **47 verificări focalizate**, fără eșecuri; cele **34 de scripturi încorporate** corespund surselor byte cu byte. Testele locale ale
adaptorului folosesc fixture; validarea C++ este de sintaxă și tipuri. Scenariul
cu erori remote reale, panou ascuns, Stop și rulare curată este pregătit pentru
editorul recompilat. Această etapă nu recompilă sau înlocuiește APK-ul și nu
pretinde verificarea noului cod nativ pe dispozitiv. Proiectele utilizatorului și
instalarea Android au fost păstrate.

Jurnal: 28.10.2026 — AG-53 implementat în surse; conectare nativă la Debugger,
proveniență și verificări de regresie. Acceptarea APK/Android rămâne deschisă.

## Proiect și versiuni

- Repository: `JDscript1/godot-ai-android`, ramura `ai/android-assistant`.
- Bază: Godot **4.7.2-stable**; modul propriu `modules/ai_assistant`.
- APK-ul curent din Download este **`1c7c777`**
  (`1c7c777635507e36431a4e6951a376a46a763161`), livrat la
  **28.10.2026, 04:04:22 +02:00**, cu implementările AG-01–AG-33 și curățenia
  codului nefolosit. Instalarea acestei versiuni rămâne la utilizator.
  Include și eliminarea plafonului și aprobările încadrate, anterior numai în surse.
- APK-ul include **Auto / Default / Plan**, control YOLO, context, dock-uri,
  sunete, Integrări, Skills, Jurnal, AGENT.MD, generare Meshy/Tripo/OpenAI,
  fișiere în chat, preview imagini/GLB/glTF, control editor, Store și diff real.
  Include exporturi 3D extinse, GitHub cu token personal,
  separatoare Cloud/Local și căutare LAN explicită.
- Include și corecțiile harness-ului, conectarea locală simplificată, bara de
  activitate deasupra composer-ului, controlul rotirii 3D, regulile pentru
  imagini și jurnalul persistent. Include și asistentul din lista de proiecte,
  deschiderea nativă a asseturilor generate și descoperirea modelelor cloud
  după salvarea cheii. Integrarea veche Termux rămâne în cod pentru compatibilitate.
- PRoot propriu, loader-ul ARM64 și baza Debian sunt acum în APK. Panoul
  Runtime Linux oferă utilitare opționale, inclusiv Blender CLI, fără Termux.
- Livrat cu numele stabil `Godot-AI-Android-arm64-debug.apk`; versiunea
  `74887a1` a fost înlocuită atomic după verificare. În Download rămâne un
  singur APK al fork-ului, cu fișierul SHA-256 actualizat.
- Compilarea și testele automate au trecut. În runda de stabilitate, două scene
  și mecanicile unui mini-joc au trecut în APK cu DeepSeek real. Atingerea fizică,
  generarea completă și noul fix de reluare necesită acceptare separată.

APK-ul curent include și eliminarea cardului Servicii și a scurtăturilor
MCP / Generare 2D/3D din Integrări. Aceste servicii au paginile lor.

## APK recompilat și înlocuit în Download — AG-34–AG-52, 28.10.2026

Livrat **`47cc26e`** din snapshot-ul izolat al surselor, pe ramura de build
`build/harness-20261028T152416Z`. Ramura și modificările locale ale utilizatorului sunt păstrate;
nu s-a modificat ramura principală prin push. Toate cele trei joburi din
[runda CI 40715736021](https://github.com/JDscript1/godot-ai-android/actions/runs/40715736021) au trecut: runtime, editor nativ și Android ARM64.

Verificat în CI: **703 aserțiuni runtime / 0 eșecuri**, **716 verificări × 5**
în editorul upstream și **732 verificări × 5** în editorul nativ compilat. Probe
native dedicate: todo **121/0**, panouri **62/0**, pornire **59/0**, generare
**58/0**. Companionul a trecut testele și build-ul. Local au trecut și cele
3 teste de livrare, 28 Termux/Blender și proba timestamp. Sunt teste automate cu
furnizori simulați; nu probe live cu chei sau gesturi fizice pe Android.

APK-ul are **112,381,278 bytes**, pachetul `com.jdscript.godotai.debug`, ABI
`arm64-v8a` și SHA-256
`6cb38bcb4aa315a90fedcf8641d92af05d9c5741132739caec819a7abb051e44`.
Semnătura persistentă este aceeași ca la instalatorul anterior. Au fost verificate
byte cu byte toate cele **34 de scripturi**, inclusiv harta, diagnosticele,
criteriile și loturile de modificări; agentul, Asset Store și managerul de
proiecte sunt prezente în biblioteca nativă. Manifestele și cele **2.678 fișiere**
ale bazei Linux, serviciul Android și binarele ARM64 PRoot/loader au trecut
verificarea locală. Verificatorul suplimentar a fost aliniat la tipul ELF ET_EXEC
al loader-ului, prevăzut în build.py; proba și PRoot sunt ET_DYN. Nu a fost o
schimbare a pachetului sau a runtime-ului.

Instalatorul și checksum-ul au fost înlocuite atomic în
`/storage/emulated/0/Download/Godot-AI-Android-arm64-debug.apk`; hash-ul final
recitit coincide cu artefactul CI. În Download rămâne un singur instalator al
fork-ului; alte descărcări sunt păstrate. Copia APK-ului anterior este în
`.ai-qa/compile-harness-20261028/previous-installer.apk`. Dovezi: `apk-verification.json`,
`ci-all.log`, `ci-test-summary.txt`, `context.json` și raportul din același director,
plus `.ai-qa/delivery-47cc26e.json`.

Acesta este build-ul care include implementările și fix-urile AG-34–AG-52 descrise
mai jos. Notele lor «în surse / APK neschimbat» consemnează starea înaintea
acestei recompilări. Noul APK **nu a fost instalat automat**. Acceptarea pe
Android și utilizarea modelelor reale rămân separate.

Jurnal: 28.10.2026 — recompilat și livrat `47cc26e`, cu semnătură persistentă,
34 de surse exacte, regresie upstream/nativă și bază Linux verificată; înlocuire
atomică în Download, fără instalare automată.

## Etapa implementată — loturi de fișiere și rollback, 28.10.2026

**AG-49–AG-52, în surse:** agentul poate pregăti și examina împreună până la
16 fișiere dependente, cu hash-uri sau absență explicită, copii private și
manifest persistent. `godot_changes_apply` verifică întregul lot înaintea primei
scrieri și fiecare destinație înaintea commit-ului. Stop sau eroarea declanșează
rollback compensatoriu; editările ulterioare și copiile corupte rămân conflicte,
fără suprascriere forțată. Nu există o limită nouă de pași a agentului.

Aprobarea arată diff-urile concrete, Plan nu poate aplica lotul, iar istoricul
pe turn include membrii modificați. După întrerupere, un runtime nou poate
inspecta și restaura același manifest; operațiile nu sunt reaplicate automat.
Inclusiv o aplicare eșuată cu rollback invalidează dovezile anterioare. Scenele
deschise au verificare nativă pentru editări nesalvate; în editorul stock fără
punte, scrierea lor prin lot este blocată conservator.

Verificat pe sursele finale: **703 aserțiuni runtime / 0 eșecuri**,
**716/0** în regresia completă a editorului narrow și **60/0** în scenariul
changesets phone_compact. Capturile reale ale dialogului sunt inspectate în
ambele layouturi. C++ trece verificarea de sintaxă/tipuri pentru cele două unități,
iar toate cele **34 de scripturi încorporate** coincid exact cu sursele.
Dovezi: `.ai-qa/changesets-20261028/`, inclusiv raport, hash-uri și stările
loturilor. [Contracte și limite](docs/AI_CHANGE_SETS.md).
Rollback-ul nu este atomic global și nu acoperă obiectele din memorie,
instalările de pluginuri sau generările cloud. Simularea checkpoint-ului de
întrerupere nu demonstrează recuperare după crash Android sau pierdere de curent.
Nu s-a compilat, înlocuit, instalat sau publicat APK; Download rămâne **1c7c777**.
Nu au fost folosite chei reale ori credite de generare.

Jurnal: 28.10.2026 — adăugate pregătirea loturilor dependente, aplicarea cu
verificări de versiune, rollback compensatoriu și recuperarea din manifest,
cu integrare în aprobări, istoricul pe turn și invalidarea dovezilor.

## Etapa anterioară — cunoașterea proiectului, diagnostic și dovezi, 28.10.2026

Prima etapă a consolidării harness-ului este implementată în surse:

- **AG-45:** `godot_project_map` și cache privat persistent: referințe literale,
  dependențe inverse în scopul indexat, simboluri, hash-uri, fișiere lipsă și
  UID-uri rezolvate dinamic. Scanare globală sau pe fișier/folder; maximum 600 de
  fișiere, 4 MB de text și 4.000 de intrări pe scanare, cu acoperire și staleness
  explicite. Anularea păstrează harta anterioară. Lexerul maschează fragmente
  întregi prin căutări native, evitând copierea textului caracter cu caracter.
- **AG-46:** `godot_diagnostics` unește observațiile parserului nativ,
  referințele lipsă, Output-ul disponibil și diagnosticele editorului/jocului.
  Puntea C++ captează evenimente structurate într-un buffer de 128 de intrări,
  inclusiv erori de shader și avertismente. Cache-ul privat păstrează sursa,
  severitatea, localizarea disponibilă, repetițiile și starea învechită; lipsa
  punții sau o observație parțială nu înseamnă proiect fără erori.
- **AG-47:** rezultate cu indicații de recuperare pentru handle-uri învechite,
  conflicte de patch, tipuri/căi greșite, sintaxă invalidă și joburi externe
  neconfirmate. Trei citiri identice fără progres cer schimbarea strategiei;
  șase citiri identice încheie cu `no_progress`. Scrierile și generările nu
  sunt repetate automat. Munca progresivă păstrează pașii nelimitați.
- **AG-48:** criterii concrete în `task_update.criteria` și `task_check` pe ID-uri
  de dovezi emise de executor. Sunt verificate tipul observației, condiția
  măsurată, revizia și hash-urile fișierelor. Editările, Undo/Redo, schimbarea
  criteriilor și reluarea invalidează dovezile. Un read nu probează sintaxa,
  apăsarea unui buton nu probează mecanica, iar un draft sau patch neaplicat nu
  probează fișierul salvat. Finalizarea directă și continuarea companionului
  verifică starea criteriilor; omiterea ultimului `task_update` nu ocolește poarta.

Verificat: **654 aserțiuni runtime / 0 eșecuri**, regresie completă randată
narrow **697/0** și proba dedicată intelligence phone_compact **52/0**. Sunt
acoperite inclusiv cache-uri corupte, UID rezolvat ulterior, drafturi neaplicate,
editări externe și concurența dintre citire și emiterea dovezii. Codul C++ nou
trece `clang++ -fsyntax-only` cu define-uri de editor; scripturile încorporate
sunt acum **33**. Dovezi în
`.ai-qa/intelligence-20261028/`; contractele și limitele sunt în
[documentația etapei](docs/AI_HARNESS_INTELLIGENCE.md).

Acoperirea dinamică completă a proiectului, stack-uri structurate dintr-un joc
oprit în debugger, recuperarea după crash nativ, verificatorul independent și
evaluările cu modele reale rămân etape distincte. Criteriile și aserțiunile trebuie să descrie fidel cererea; un ID de
dovadă nu garantează că modelul a ales un test suficient.

Nu s-a compilat, înlocuit sau instalat APK-ul. Captura nativă necesită editor
recompilat; verificarea C++ de sintaxă nu reprezintă execuție pe Android. Download
rămâne **1c7c777**. Nu au fost folosite chei reale sau credite de generare.

Jurnal: 28.10.2026 — adăugate harta persistentă, diagnosticele unificate,
recuperarea adaptivă și verificarea criteriilor prin dovezi reale ale uneltelor,
cu invalidare după schimbări și probe de regresie.

## Corectarea celor patru probleme din audit, 28.10.2026

Corecțiile sunt în surse, peste modificările existente AG-34–AG-44:

- Aprobarea parțială modifică o copie privată a argumentelor. Cererea originală,
  istoricul și semnătura folosită la replay rămân identice; rezultatul raportează
  hunk-urile acceptate/refuzate și hash-uri separate pentru propunere și conținutul
  aprobat. Repetarea apelului și reluarea istoricului păstrează rezultatul fără
  o nouă scriere.
- Adaptorul Responses, inclusiv sesiunea de abonament care îl folosește, tratează
  `response.incomplete` / `max_output_tokens` ca răspuns trunchiat continuabil.
  Păstrează textul, consumul și elementele native de text/raționament; apelurile
  de funcție ale răspunsului incomplet nu sunt executate sau retrimise ca apeluri
  fără rezultat. Alte motive de întrerupere rămân erori.
- Bugetul comun este strict: maximum 48.000 de caractere pentru toate rezultatele
  dintr-un pas, inclusiv 64 de apeluri. Se rezervă 512 caractere pentru fiecare
  apel rămas; nu se mai adaugă automat un minim după epuizarea bugetului.
  Rezumatele rămân JSON valid; diagnosticele mari păstrează structurat verdictul
  de sintaxă și numărul de erori, iar aprobările mari păstrează selecția parțială
  și numărul hunk-urilor.
- `godot_symbols` maschează stringurile și comentariile înainte de identificarea
  declarațiilor, inclusiv ambele forme de ghilimele triple și delimitatorii
  escapați. Păstrează liniile și semnăturile reale.

Verificat: runtime **600 aserțiuni / 0 eșecuri** și suita completă randată
narrow **662/0**, inclusiv scriere și patch reale aprobate parțial. Scenariul
dedicat approval phone_compact trece **117/0**, cu verificări de geometrie și
captura completă a editorului inspectată. Proba inițială
a auditului măsoară acum **46.587** de caractere pentru 64 de rezultate, față de
**78.291** înainte, replay finalizat cu o singură execuție și numai declarațiile
reale din stringul de probă. Responses repetat trunchiat face cele două continuări
configurate și raportează `output_limit`; fixture-ul care apoi se încheie normal
este verificat separat în suita runtime. Dovezi în `.ai-qa/fixes-20261028/`.
Nu a fost compilat, înlocuit sau instalat un APK; Download rămâne **1c7c777**.
Nu s-au folosit chei reale sau credite de generare. Proba pe Android fizic și cu
un furnizor real rămâne separată.

Jurnal: 28.10.2026 — aplicate cele patru corecții reproduse în audit, cu regresii
pentru replay după aprobare parțială, Responses trunchiat, 64 de rezultate mari
și declarații false din stringuri. Plafonul de pași rămâne eliminat.

## Consolidări — verificare după scriere, context de căutare și buget pe rundă, 28.10.2026

Trei consolidări ale harness-ului, în surse (**AG-42–AG-44**).
`godot_search_code` și limita de 24.000 de caractere pe rezultat existau deja;
runda le completează, nu le dublează.

- **AG-42:** după `godot_write_file` sau `godot_apply_patch` pe un `.gd`,
  rezultatul include verdictul automat al parserului nativ: `valid`, erori cu
  linie, coloană și mesaj, plus `truncated`. Sunt păstrate maximum 20 de erori,
  fiecare mesaj limitat la 400 de caractere; avertismentele rămân în
  `godot_script_diagnostics`. Preview-ul unui patch validează textul propus, nu
  fișierul de pe disc. Fără puntea nativă câmpul `syntax` lipsește — unealta nu
  inventează un verdict.
- **AG-43:** `godot_search_code` acceptă `context` 0–4; fiecare potrivire poate
  include liniile dinainte și de după, fără repetarea liniilor deja afișate de o
  potrivire vecină. Extrasele sunt limitate la 24.000 de caractere pe rezultat,
  iar folderele și fișierele legate simbolic sunt sărite.
- **AG-44:** rezultatele uneltelor dintr-un pas împart un buget de 48.000 de
  caractere; minimul inițial de 2.000 pe rezultat a fost înlocuit cu rezervarea
  spațiului pentru apelurile rămase în corecția auditului de mai sus. Un rezultat tăiat păstrează, când există spațiu,
  începutul, coada (`tail`), contractul `ok`/`code`/`error`, identitatea
  artefactului și verdictul `syntax`. Listele `matches`, `symbols` și
  `diagnostics` păstrează numărul total și primele trei intrări compacte.

Verificat: **569 aserțiuni runtime / 0 eșecuri**, inclusiv verdictul de sintaxă
cu punte simulată, contextul de căutare cu suprapunere suprimată și bugetul pe
rundă cu un al patrulea rezultat redus; suita completă narrow **658/0**;
`--check-only` pe `editor_tools.gd` și `harness.gd`. Dovezi în
`.ai-qa/harness-20261028/`.

Limite: parserul nativ nu există în binarul stock folosit de probele locale, deci
verdictul real de sintaxă rulează doar în editorul recompilat; local s-a verificat
ramura fără punte, care nu inventează un verdict. Contextul și bugetul sunt
independente de motor și au fost probate local. Un APK nou și proba pe dispozitiv
rămân deschise; APK-ul din Download rămâne **1c7c777**.

Jurnal: 28.10.2026 — verdict de sintaxă după scriere, context la căutarea în cod
și buget comun pe rundă pentru rezultatele uneltelor.

## Etapa precedentă — continuare automată, harta simbolurilor și review pe hunk-uri, 28.10.2026

Trei capacități tehnice alese din comparația cu Ziva și rescrise independent în
surse (**AG-39–AG-41**). Nicio linie de cod Ziva nu a fost copiată.

- **AG-39:** un răspuns oprit la limita de ieșire a furnizorului (`length`,
  `MAX_TOKENS`, `max_tokens`) continuă automat de până la două ori. Instrucțiunea
  internă intră doar în contextul acelei cereri, nu în istoric; textul,
  raționamentul și apelurile de unelte se topesc într-un singur mesaj assistant și
  un singur balon. Fiecare încercare emite evenimentul `auto_continue` și este
  numărată în `continuations`; după buget, turul se încheie
  `limited`/`output_limit` cu textul complet. Panoul pasează două încercări;
  harness-ul implicit rămâne 0.
- **AG-40:** unealta `godot_symbols` citește declarațiile top-level dintr-un
  director de proiect: `class_name`, `class`, `func`/`static func`, `signal`,
  `const`, `enum`, `@export var` și `var`, cu cale, linie de la 1 și semnătură
  mărginită. Filtrează după nume (fără diferență de majuscule), tip și limită;
  scanarea este mărginită la 2000 de intrări, 4 MB și 600 de fișiere în cache, iar
  parsarea este cache-uită după hash-ul conținutului. Variabilele locale și
  liniile comentate sunt ignorate; rezultatul raportează `files_scanned`,
  `scanned_bytes` și `truncated`.
- **AG-41:** aprobarea scrierii peste un fișier existent arată diff-ul unificat și
  o bifă per hunk, cu +/− și linia de start. Toate bifele pornesc selectate; cele
  nebifate păstrează liniile originale, iar **Permite** și **Permite mereu** sunt
  dezactivate când nu e selectat niciun hunk. La `godot_write_file` selecția
  înlocuiește textul; la
  `godot_apply_patch` se aplică o singură înlocuire exactă peste original,
  păstrând verificarea hash-ului, copia de recuperare și jurnalul. Fișierele noi
  și diff-urile peste limite cad pe preview-ul textual anterior. Dacă dialogul
  nativ se ascunde deși OK e dezactivat, aprobarea este reafișată.

Verificat: **558 aserțiuni runtime / 0 eșecuri**; scenariul QA `approval`
**92/0** în cinci layout-uri, cu bife per hunk, blocare fără selecție, reafișare
și un `godot_apply_patch` real din care un hunk este respins; chat narrow
**68/0**; todo narrow **115/0**; suita completă narrow **657/0**;
`--check-only` pe `diff.gd`, `editor_tools.gd`, `harness.gd` și `panel.gd`.
Dovezi în `.ai-qa/continuare-simboluri-hunks-20261028/`.

Limite: testele dovedesc comportamentul în editorul headless și fixture-urile QA,
nu un furnizor live, un APK nou sau dispozitivul fizic. Continuarea automată a
fost probată cu răspunsuri fixture marcate `length`, nu cu un model real care
atinge limita. Harta simbolurilor acoperă numai declarațiile top-level ale
fișierelor `.gd`, nu simboluri din scene sau resurse. Review-ul pe hunk-uri se
aplică doar scrierilor aprobate manual; YOLO și „Permite mereu” rămân fără ecran
de review. AG-39–AG-41 sunt în surse; APK-ul din Download rămâne **1c7c777** și
nu le include.

Jurnal: 28.10.2026 — adăugate continuarea automată, `godot_symbols` și review-ul
pe hunk-uri înainte de scriere.

## Etapa precedentă — Plan, operații și navigare tactilă, 28.10.2026

Captura `Screenshot_20261028_041559.jpg` arată planul în poziția inițială și
`asset_wait` fără identificarea generatorului. Corecții în surse:

- **AG-35:** un singur card Plan activ urmărește capătul conversației. La
  finalizare rămâne în istoric; citirea mesajelor vechi nu forțează derularea
  la final. Stările pașilor rămân cele confirmate prin plan, fără completări
  inventate pe baza numelui uneltei.
- **AG-36:** operațiile au nume lizibile. Profilul sau jobul existent determină
  `Running Image Generator Tool` / `Running 3D Generator Tool`, inclusiv la
  așteptare și verificare. Un job necunoscut folosește denumirea generică.
  Identificatorul tehnic rămâne în tooltip și Jurnal.
- **AG-37:** preview-ul 3D acceptă gesturile native Android de mărire și pan,
  păstrând rotirea și pinch-ul brut. Butoanele **Zoom + / Zoom −** oferă control
  explicit; distanța camerei rămâne limitată la intervalul preview-ului.
- **AG-38:** derularea conversației acoperă textul, codul, cardurile media și
  marginile goale. Primul mouse emulat de Android este interceptat înainte
  să pornească selecția textului. Pan-ul nativ este acceptat; butoanele și
  câmpurile editabile păstrează interacțiunea lor. Glisarea orizontală a unui
  fișier îl menționează, tap-ul deschide preview-ul, apăsarea lungă păstrează
  meniul de acțiuni și eliberează gestul capturat.

Probele folosesc ferestre reale Godot, input trimis prin viewport și fișiere
fixture în proiecte temporare. Dovezi în `.ai-qa/navigation-20261028/`.
Regresia completă narrow trece **649 verificări / 0 eșecuri**; preview-ul 3D
phone_landscape trece **79/0**. Proba finală de navigare și operații trece **115/0**
phone_compact, inclusiv Plan după mesaje, carduri de modificări și rezultate
Store, gesturi pe margini/text/cod/media, mențiuni și meniul apăsării lungi.
Capturile preview-ului 3D și ale chatului au fost inspectate. Recalcularea
intervalului de scroll este urmărită pentru a păstra întregul card Plan deasupra
composer-ului după schimbarea înălțimii conținutului; proba finală verifică
explicit limita de jos a cardului, iar captura confirmă încadrarea completă.
Planul interactiv a fost repetat pe sursele finale la scalarea telefonului:
**67 verificări / 0 eșecuri**, cu selecții, câmpuri proprii, trimitere și reluare.
Prima probă simultană a expirat și a țintit o miniatură înaintea layoutului;
fixture-ul așteaptă acum încadrarea și verifică aria vizibilă înainte de input.
Probele reluate separat au trecut; limitele testelor nu schimbă pașii agentului.
APK-ul din Download rămâne **1c7c777**; AG-34–AG-38 nu sunt încă livrate în el.
ADB nu are un dispozitiv conectat, deci gesturile fizice Android nu sunt
prezentate drept verificate.

## Etapa precedentă — Running Tools numai pentru unelte active, 28.10.2026

Corectat în surse **AG-34**: rândul „Running Tools” pornește ascuns și apare
numai la începutul unui apel de unealtă, cu numele curent. Rezultatul apelului,
inclusiv un refuz sau o eroare, ascunde rândul și eliberează spațiul din chat.
Stop îl ascunde imediat; finalizarea cererii și schimbarea conversației îl
resetează. Nu mai rămâne eticheta goală „Running Tools · —”.

Proba dedicată pe scalarea telefonului a trecut **94 verificări / 0 eșecuri**,
inclusiv schimbarea uneltei, rezultat, refuz, Stop, finalizare și conversație nouă.
Regresia completă în editorul îngust a trecut **641 verificări / 0 eșecuri**.
Capturile cu unealta activă și cu planul încheiat au fost inspectate. Dovezi:
`.ai-qa/running-tools-20261028/`. Este o corecție în surse; APK-ul din Download
rămâne **1c7c777** și nu conține încă AG-34. Verificarea fizică Android rămâne
separată.

## Etapa precedentă — APK recompilat și înlocuit în Download, 28.10.2026

Utilizatorul a cerut recompilarea și înlocuirea instalatorului din Download.
Build-ul **`1c7c777`** include AG-21–AG-33: Plan interactiv, playtest măsurabil,
aprobări de sesiune, compactare tranzacțională adaptată modelului și recuperarea
chatului, inclusiv coada derulabilă. Toate cele trei joburi ale
[rundei CI 40617637786](https://github.com/JDscript1/godot-ai-android/actions/runs/40617637786)
au reușit: runtime, editor nativ compilat și Android ARM64.

Verificat: **537 aserțiuni runtime / 0 eșecuri**, **641 verificări × 5** în
editorul upstream și **654 verificări × 5** în editorul nativ compilat. Au trecut
și probele dedicate native: todo **90/0**, panouri **58/0**, generare **54/0**,
precum și cele **9 teste companion** și build-ul lui. Aceste probe folosesc
date și furnizori simulați; nu sunt generări plătite sau testare tactilă Android.

APK-ul are **112.345.138 bytes**, pachetul `com.jdscript.godotai.debug`, ABI
`arm64-v8a` și SHA-256
`a9ce6c7949b21ba45dbb067e6fe3e4037ab3ce129cae31096efbd7c5311c9236`.
Semnătura persistentă a fost verificată, toate cele **30 de scripturi runtime**
au fost comparate byte cu byte cu sursa exactă, iar manifestele, serviciul,
PRoot/loader-ul și cele **2.678 fișiere** ale bazei Linux au trecut verificarea.
Identitatea agentului, Asset Store și asistentului din lista de proiecte este
prezentă în biblioteca APK-ului.

Înlocuirea a fost atomică, cu checksum actualizat și hash final recitit din
`/storage/emulated/0/Download/Godot-AI-Android-arm64-debug.apk`. În Download
rămâne un singur instalator al fork-ului; celelalte descărcări sunt păstrate.
APK-ul anterior este păstrat privat în
`.ai-qa/recompile-20261028/previous-installer.apk`. Dovezi:
`.ai-qa/delivery-1c7c777.json`, `.ai-qa/recompile-20261028/ci-verification.json`,
`apk-verification.json`, `linux-verification.log` și rapoartele `*-evidence-latest`
din același director. Noul APK nu a fost instalat automat; acceptarea pe telefon,
playtest-ul condus de model și consumul real al furnizorilor rămân separate.

Prima rundă, `4addd41`, a compilat APK-ul Android, dar verificarea completă a
prins un test pe ecran lat care moștenea ascunderea explicită a istoricului din
proba Plan. Fixture-ul restaurează acum selecția barei laterale înainte de
verificarea regulii automate. Proba de salvare eșuată blochează doar destinația
rezumatului, păstrând jurnalul disponibil. Build-ul primei runde nu a fost livrat.
Proba locală completă pe ecran lat trece după izolarea fixture-urilor:
**641 verificări / 0 eșecuri**, fără mesajul de eroare din proba de jurnal.

## Etapa precedentă — corecțiile auditului de compactare și coadă, 28.10.2026

Implementat în surse **AG-33**, pentru cele trei regresii reproduse în auditul
`.ai-qa/review-20261028-followup/`. Rezumatele goale, invalide, întrerupte,
anulate sau prea mari sunt refuzate. Rezumatul și limita istoricului se schimbă
numai după finalizarea tuturor loturilor și salvarea reușită. Eșecul unui lot
sau al salvării păstrează contextul anterior în memorie și pe disc. La încărcare,
un rezumat gol salvat de versiunea veche nu mai ascunde istoricul original.

Rezumarea folosește fereastra modelului selectat, cu rezervă pentru răspuns și
mesaje de protocol. Istoricul, inclusiv rezumatul anterior, mesajele lungi și
argumentele uneltelor, este parcurs cronologic în loturi fără omiterea unor
intervale. Bugetul folosește o estimare conservatoare după UTF-8; o eroare de
overflow reduce lotul și reîncearcă același interval. Adaptoarele directe primesc
și limita de ieșire a rezumatului. Limita de pași a agentului nu este schimbată.

Coada are derulare proprie și înălțime limitată în funcție de spațiul disponibil.
Cu 20 de mesaje, conversația și composer-ul rămân accesibile; ultimul card poate
fi derulat și eliminat individual. Nu se schimbă mesajele sau atașamentele din
coadă.

Verificat: runtime **537 aserțiuni / 0 eșecuri**, inclusiv transmiterea limitei
de ieșire prin HTTP local; QA compact narrow **82/0**, chat narrow **67/0**.
Pentru fereastra de 8192 tokeni, cel mai mare buget estimat al probei este
**8182**, inclusiv rezerva de ieșire și protocol. Toate marcajele istoricului
au ajuns în loturi; istoricul complet și ultima cerere au fost păstrate.
Captura cu 20 de mesaje în coadă a fost inspectată: conversație de **501 px**,
coadă de **120 px**, composer complet vizibil. Suita completă pe copia finală
a surselor: **638/0** narrow; QA chat la scalarea telefonului: **68/0**. În
această randare, conversația are **188 px**, coada **155 px**, iar ultimul card
și composer-ul sunt complet accesibile. Înălțimea cozii este rotunjită la pixeli
întregi, iar cardurile propagă gesturile de derulare. Capturile au fost inspectate.
Dovezi și hash-uri ale surselor în `.ai-qa/fix-review-20261028/`. Aceste probe
folosesc furnizori simulați, nu chei
cloud. Nu a fost compilat sau înlocuit un APK; proba tactilă rămâne separată.

Jurnal: 28.10.2026 — corectate cele trei probleme din audit, cu regresii pentru
rezumate invalide, Stop, salvare eșuată, loturi lungi și coadă de 20 de mesaje.

## Etapa precedentă — experiența de chat după inventarul Ziva, 28.10.2026

Implementat în surse **AG-32**, cu doar elementele considerate utile din
inventarul comparativ Ziva–noi. **Undo** și **Regenerează răspunsul** sunt
disponibile pe ultimul răspuns încheiat: restaurează fișierele prin jurnalul
execuției, salvează rezumatul modificărilor, elimină răspunsul împreună cu
promptul lui și readuce promptul, fișierele și atașamentele în composer. Undo
readuce promptul fără să trimită; Regenerează îl retrimite. Pentru tururile mai
vechi acțiunea indică ramificarea, iar scena se refuză dacă istoricul nativ de
Undo al sesiunii s-a pierdut. Mesajele aflate în coadă apar ca un panou compact
deasupra composer-ului, cu număr, buton **Reia** când coada e oprită și câte un
card cu textul integral în tooltip, mutare înapoi în composer și scoatere.
Fiecare răspuns primește o linie de metrici pe tur: durata fără pauzele de
aprobare, tokenii de ieșire (marcați „≈” când lipsesc datele furnizorului),
intrarea cumulată în tooltip și costul estimat din tarifele salvate. Blocurile
**Gândire** apar pliate, numără cuvintele și se deschid la cerere; avertismentul
de blocare apare după 15 s fără ieșire în timpul generării. **Caută în
conversație** numără potrivirile fără diferență de majuscule și sare între ele,
cu încadrare în derulare, fără a încărca anticipat mesaje mai vechi.

Verificat: **531 aserțiuni runtime / 0 eșecuri**; scenariul QA nou `chat`, narrow
**62/0**, scenariul complet narrow **604/0** (include compactarea și aprobările),
todo **88/0**; `--check-only` pe `panel.gd`, `chat_view.gd` și `icons.gd` cu Godot
4.7.2 headless. Testele fixture acoperă gating-ul pe ultimul tur, restaurarea
reală a unui fișier scris de agent, trunchierea istoricului, coada cu
restore/remove/reia, metricile măsurate și estimate, blocurile Gândire, căutarea
cu wraparound și avertismentul de stagnare. Regenerează a fost verificat doar pe
calea de gardă, nu printr-o cerere live; APK-ul, build-ul nativ și proba pe
dispozitiv rămân deschise. Nu există un APK nou.

Jurnal: 28.10.2026 — adăugate Undo/Regenerează, coada vizibilă, metrici pe tur,
blocuri Gândire, căutare în conversație și avertismentul de stagnare.

## Etapa precedentă — compactare automată a contextului, 28.10.2026

Implementat în surse **AG-31**, pornind de la fluxul de autocompactare observat în
Ziva și rescris independent în harnesul nostru. Pragul este
`context_limit - reserve`; rezerva implicită este 16384 de tokeni, redusă la
jumătatea ferestrei mici, iar ferestrele sub 8192 de tokeni sunt ignorate, ca
modelele mici folosite în teste să nu declanșeze compactări repetate. Partea
recentă păstrată are până la 20000 de tokeni, limitată de prag. După o tură care depășește pragul, sau după o eroare de
tip overflow, panoul rezumă intervalul vechi și păstrează textual mesajele
recente. Tăierea cade pe un mesaj de utilizator și nu rezumă niciodată ultima
cerere. Rezumatul îl extinde pe cel anterior, este salvat în
`summary_<conversație>.json` și este trimis ca „Earlier conversation summary” în
cererea următoare; istoricul complet rămâne pe disc. Compactarea rulează în fundal,
cu mesaj de stare și butonul Stop obișnuit, iar un mesaj aflat în coadă așteaptă
încheierea ei. Un eșec păstrează istoricul neatins și nu se reîncearcă până la
următoarea cerere a utilizatorului. Comutatorul este în Setări → General, activ
implicit. Numărătorile folosesc usage-ul furnizorului când există și o estimare
după caractere altfel. Diferă de fluxul de referință printr-un singur punct: după
un overflow compactăm pentru cererea următoare, dar nu reluăm automat tura
eșuată, care poate să fi produs deja efecte.

Verificat: **531 aserțiuni runtime / 0 eșecuri**; scenariul QA editor nou
`compact`, narrow **54/0**; approval **84/0**, todo **88/0** și scenariul complet
narrow **580/0**; `--check-only` pe `panel.gd` cu Godot 4.7.2 headless. Testele fixture acoperă
comutatorul, pragul și rezerva, tăierea pe mesaj de utilizator, excluderea ultimei
cereri din rezumat, persistența și restaurarea, refuzul unei a doua compactări
fără interval nou, eșecul fără retry imediat și ferestrele mici ignorate. APK-ul,
proba pe dispozitiv și consumul real de tokeni rămân deschise. Nu există un APK
nou.

Jurnal: 28.10.2026 — compactare automată legată la harnes, cu prag, rezervă,
rezumat incremental și comutator în Setări → General.

## Etapa precedentă — aprobări de sesiune, predarea planului și corecțiile auditului, 28.10.2026

Implementat în surse **AG-30**. Dialogul de aprobare are un al treilea buton,
**Permite mereu**, care aprobă aceeași unealtă până la închiderea editorului.
Permisiunea se verifică după refuzul Plan și după YOLO, deci Plan rămâne doar
pentru citire; decizia se înregistrează ca `approved_always`. Setări → General
listează uneltele aprobate și le poate revoca pentru sesiune. Acordarea nu se
salvează în fișiere și dispare la închiderea editorului.

Cardul unui plan propus, complet, oferă **Implementează planul** și **Ajustează**.
Implementarea trece în Auto și trimite pașii propuși, cerând un `task_update` la
executing înainte de prima modificare. Ajustarea deschide Plan mode cu pașii în
composer. Acțiunea brută de pe mesaj a fost eliminată. Doar propunerea aceleiași
ture este acceptată; un card de execuție nu afișează aceste butoane.

Auditul independent din `.ai-qa/review-playtest-20261028/` a găsit șase probleme
în AG-29, corectate în aceeași etapă:

- puntea C++ compilează: antetul corect `core/os/time.h`, singletonii de scripting
  `CoreBind::Engine`/`CoreBind::OS` și `CLAMP` în locul lui `clampi`;
- probele rulează cu `const_calls_only`, deci un apel mutator este oprit de motor
  chiar dacă lipsește din lista euristică; `playtest_watch` rămâne sigur în Plan;
- Stop/anularea închide actul activ cu rezultat distinct `cancelled` și eliberează
  intrările, inclusiv servo înainte de alegerea direcției;
- garda de input rămâne în procesare după act, ca intrările reținute să fie
  eliberate la expirare sau la deconectarea debuggerului;
- expirarea de 75 s raportează `timed_out` și `until_met=false`, nu o dovadă falsă;
- refuzul repetării se bazează pe măsurători consecutive identice (probe, valori
  urmărite, evenimente fără numărul cadrului, servo, until), cu stare păstrată pe
  tura părinte și job, deci aceleași argumente care produc progres nu sunt oprite.

Verificat: **531 aserțiuni runtime / 0 eșecuri**; QA editor narrow approval
**84/0** și todo **88/0**; `--check-only` pe `panel.gd`, `chat_view.gd` și
`agent_jobs.gd`; `clang++ -fsyntax-only` pe puntea C++ cu define-urile de editor;
probă headless pe calea reală `execute` cu backend simulat: patru acte identice
cu progres trec, trei fără schimbare sunt permise, al patrulea primește
`no_progress`, atât pe copil, cât și pe părinte. Puntea nu a fost construită sau
linkată și nu există probă playtest pe dispozitiv; ambele rămân porți. Nu există
un APK nou.

Jurnal: 28.10.2026 — adăugate Permite mereu, Implementează/Ajustează planul și
corecțiile auditului AG-29; verificarea nativă și cea fizică rămân deschise.

## Etapa precedentă — probe de playtest în joc, 28.10.2026

Implementat în surse **AG-29**: subagentul Playtest poate măsura jocul care
rulează, nu doar îl fotografia. Puntea nativă de debugger răspunde la `eval`,
`watch`, `act`, `status` și `release` în procesul jocului; `playtest_watch` și
`playtest_act` înlocuiesc judecata pe capturi cu valori măsurate înainte și după
fiecare intrare.

`playtest_act` ține apăsat până la 8 intrări pe toată așteptarea și citește până
la 12 probe înainte și după, cu așteptare pe cadre (`advance_frames`) sau pe
condiție (`until`). Probele de după se evaluează înainte de eliberarea
intrărilor ne-reținute, ca mișcarea verificată să nu fie mascată de ridicarea
tastei. Servo-ul (maxim 3) duce o probă numerică la țintă cu intrări
increase/decrease, cu toleranță, wrap și cel mult 900 de cadre. `playtest_watch`
urmărește 4 expresii și 8 semnale, cu evenimentele atașate următorului răspuns.
Repetarea acelorași argumente este refuzată (`no_progress`) numai când ultimele
trei răspunsuri raportează măsurători identice; starea se păstrează pe tura
părinte și job, iar dovezile (maxim 40) se salvează în `jobs/<id>.json`.

Probele sunt expresii GDScript evaluate read-only în scena curentă:
identificatorii simpli se rezolvă ca noduri copil, iar `Engine`, `Input`, `OS`,
`Time` și `ProjectSettings` sunt legate. Atribuirile și `await` sunt respinse
textual, iar expresia rulează cu `const_calls_only`, deci un apel mutator este
oprit de motor chiar dacă nu apare în lista euristică. Un act se oprește după 75
de secunde și raportează `expired` și `timed_out`, cu `until_met=false` dacă
condiția nu a fost observată; Stop anulează actul activ cu un rezultat distinct
`cancelled`. Garda rămâne în procesare după act, ca intrările reținute să fie
eliberate la expirare sau la deconectarea debuggerului.

În chat apare o consolă Playtest pliabilă pe tura părinte: intrări, tabel
înainte/după, valori urmărite, semnale, servo și verdictul final
(`pass|fail|blocked`) parsat din JSON-ul de închidere al modelului. Consola
trăiește în tura activă; nu se reconstruiește la reîncărcarea istoricului.

Verificat local: **531 aserțiuni runtime / 0 eșecuri** și `--check-only` pe
Godot 4.7.2 headless pentru `chat_view.gd`, `agent_jobs.gd` și `panel.gd`;
corecțiile AG-30 adaugă verificarea `clang++ -fsyntax-only` a punții. Construirea
reală în CI și proba playtest pe dispozitiv rămân porți separate. Nu există un
APK nou pentru AG-29.

Jurnal: 28.10.2026 — adăugate probele de playtest, servo/until, urmărirea de
semnale și consola de dovezi; verificarea nativă și cea fizică sunt încă deschise.

## Etapa precedentă — Plan interactiv, 27.10.2026

Implementat în surse **AG-28**: agentul poate cere clarificări în chat prin
`plan_ask`, cu 1–3 întrebări, opțiuni simple/multiple și răspuns propriu. Nu este
preselectată nicio variantă. Harness-ul așteaptă „Trimite răspunsurile”, apoi
primește alegerile confirmate și continuă propunerea. Modul Plan rămâne numai
pentru citire, inclusiv cu YOLO activ.

Întrebările, ciornele și răspunsurile se salvează în conversație. Stop păstrează
cardul; trimiterea ulterioară reia aceeași sarcină. Recuperarea tratează și
întreruperea dintre salvarea răspunsului și încheierea apelului. Cardurile vechi
nu pot răspunde unei cereri noi sau altei conversații. Reluarea nu schimbă
implicit furnizorul dacă profilul inițial a dispărut. Cardurile au aceeași
limită adaptivă de lățime ca planul; glisarea peste opțiuni nu le selectează.

Verificat: **531 aserțiuni runtime / 0 eșecuri**, regresie editor narrow
**548 verificări / 0 eșecuri** și probe dedicate pentru selecție, răspuns
propriu, Stop și recuperare: **67 verificări × 5 configurații / 0 eșecuri**.
Randările au fost inspectate în chat îngust și la scara de telefon.
Dovezi și comenzi: [Plan interactiv](docs/AI_INTERACTIVE_PLAN.md).

Aceste schimbări **nu sunt încă în APK**. Instalatorul din Download este cel
livrat anterior. Compilarea, probele fizice Android și cererile către un
furnizor real pentru această funcție rămân de făcut.
Instrucțiunile cer clarificări numai când lipsesc decizii relevante;
comportamentul unui model real rămâne de evaluat după livrare.

Jurnal: 27.10.2026 — adăugat Plan interactiv, cu răspunsuri explicite,
persistență și continuare; validarea locală este separată de livrarea Android.

## Stabilitate și probe reale, 27.10.2026

APK-ul instalat a fost verificat prin ADB: **74887a1**, același SHA-256 ca
instalatorul din Download. Probele au folosit panoul și harness-ul nativ cu
DeepSeek `deepseek-flash`, într-un proiect nou separat; cheia a rămas în aplicație.
YOLO era deja activ și nu a fost activat de driver.

- Două scene în același director, salvate/redeschise corect: **21 cereri, 63,4 s**.
- Mini-joc cu 3 monede, victorie și restart prin input injectat în jocul Android:
  **46 cereri, 397,8 s**, plan încheiat, Output verificat. Peste plafonul vechi,
  fără scene sau foldere duplicate. Fișierele originale urmărite sunt identice.
- Capturile reale arată mecanicile, dar și margini gri; adaptarea la viewport
  este o sarcină separată. Stop după prima scriere reală a păstrat modificarea.
  Continue a reluat același turn, apoi DeepSeek a respins protocolul cu HTTP 400.
- După reconectare și încărcarea temporară a adaptorului corectat, Continue a
  trecut cu **58 cereri, 466,0 s**, pe același turn după repornirea editorului.
  Panoul/harness-ul/uneltele au rămas cele din APK; cheia nu a fost exportată.
- Agentul a reparat layoutul îngust după cinci eșecuri găsite independent:
  **59 cereri, 633,1 s**, probă nativă **492 / 0**, apoi verificare independentă
  **84 / 0** și randări inspectate la trei dimensiuni.
- Salvarea/încărcarea 1/3 și 3/3 după oprirea și pornirea procesului jocului:
  **62 cereri, 574,5 s**, probă nativă extinsă **938 / 0**. Testele independente
  au găsit apoi acceptarea greșită a unor metadate fracționare. Agentul a reparat
  validarea în **14 cereri, 85,2 s**: proba nativă **946 / 0**, independent
  **34 / 0** pentru persistență și **156 / 0** pentru geometria finală.

Corecții acum în surse: notificările locale separate de răspunsurile modelului
la reluare, păstrarea metadata confirmate la ramificare, rezultate mari cu `ok`
și ID-uri păstrate, limită JSON reală și inspectare Godot paginată. Node:
**48.786→7.342 caractere** pentru prima pagină; nu este o măsurare a facturii API.
Driverul respectă permisiunile existente, colectează jurnalul JSONL complet și
actualizează starea după Continue din UI. Sursele cer și plan actualizat la
schimbarea etapei, răspuns final scurt, apeluri grupate când sunt independente
și rezumate de teste care nu ascund eșecurile în sute de mesaje PASS. Aceste
instrucțiuni noi nu au acceptare comportamentală implicită într-un APK nou.

Validări: **518 aserțiuni runtime / 0 eșecuri**, **514 verificări editor / 0
eșecuri** în configurația narrow. Regresia la reluare a fost întâi reprodusă
(516 / 6 eșecuri), apoi cererea HTTP corectă a fost acceptată de fixture.
Parser Godot pentru driver și proba temporară de adaptor, plus compilare Python,
trecute. Randările cardurilor și ale sarcinii întrerupte au fost inspectate.

Fixurile noi nu sunt încă într-un APK. Corecția DeepSeek are acum acceptare API
reală cu adaptor temporar; livrarea în APK rămâne separată. Modificările jocului
și probele lui sunt salvate în proiectul izolat, nu în codul editorului.
Adaptorul original a fost restaurat și editorul repornit cu driverul normal;
scena mini_game este deschisă, jocul oprit și modul UI Default. Hash-ul APK-ului
instalat este același. Au trecut din nou **518 aserțiuni runtime** și parserul
driverului; ultima persistență a selecției restaurate din driver are numai
verificare de parser. Nu s-au făcut generări Runware, instalări sau o compilare
nouă. Nu este încă dovadă de pregătire pentru producție AAA.

[Raportul complet și pragurile ST-01–ST-12](docs/AI_AGENT_STABILITY_20261027.md),
cu priorități pentru continuitate, salvări, tranziții, regenerări evitate,
regresii, performanță și export. AG-21–AG-27 sunt în [TODO_AGENT.md](TODO_AGENT.md).
Dovezi: `.ai-qa/harness-stability-20261027/`, inclusiv loguri integrale,
checkpointuri, hash-uri înainte/după și capturi reale.

Jurnal: 27.10.2026 — Continue confirmat cu DeepSeek real/adaptor temporar;
agentul a reparat layoutul și persistența după eșecuri independente. Probele
finale trec, fixture-urile și logurile sunt păstrate, APK-ul rămâne nemodificat.

## Etapa precedentă — recompilare după curățenie și APK livrat, 27.10.2026

Recompilare autorizată pentru sursa
`74887a1fc49bc2a969ef33c9a9ac1d6f293f6d8e`. Au trecut toate cele trei joburi
din [build-ul 40521411236](https://github.com/JDscript1/godot-ai-android/actions/runs/40521411236):
runtime, Android și editor nativ.

Rezultate CI: **495 aserțiuni runtime**, **514 verificări × 5 configurații**
în editorul upstream și **527 × 5** în editorul nativ compilat. Scenariul TODO
a trecut cu **84**, respectiv **86** verificări; au trecut și probele dedicate
Blender, panouri, pornire și generare, testele Python și cele **9 teste companion**.
Compilarea Android a verificat semnătura persistentă, ABI-ul ARM64, cele 30 de
scripturi embedded și componentele PRoot/Linux incluse. Toate fără eșecuri.

Dovezi CI: `.ai-qa/74887a1-ci.log`, `.ai-qa/74887a1-ci-verification.json`.
APK **112,300,230 bytes**, SHA-256
`389b43bd9370d41ac23bb0ede3139fbc221b5a2f0ddaf215a57ec8da457f0890`.
Semnătura persistentă și pachetul `com.jdscript.godotai.debug` verificate local;
toate cele **30 de scripturi** comparate byte cu byte cu sursa exactă.
Verificate și manifestul runtime, cele trei componente ELF ARM64, serviciile
Android și baza Linux inclusă (**32,789,398 bytes**), cu hash-uri conforme.
Arhiva descărcată corespunde digestului publicat de GitHub; transferul lent a
fost reluat de la partea primită, fără a descărca din nou întregul fișier.

La **15:52:51 +01:00**, instalatorul stabil din
`/storage/emulated/0/Download/Godot-AI-Android-arm64-debug.apk` și fișierul
SHA-256 au fost înlocuite atomic, după verificări. În Download rămâne un
singur instalator al fork-ului. Dovezi locale:
`.ai-qa/delivery-74887a1.json`, `.ai-qa/74887a1-apk-verification.json`,
`.ai-qa/74887a1-transfer.json`.
Nu s-a instalat automat aplicația și nu s-au făcut probe noi pe dispozitiv
sau la furnizori reali în această etapă.

## Etapa precedentă — curățenie cod nefolosit, numai în surse, 27.10.2026

Eliminate **6 funcții, 8 câmpuri și 2 constante** din componentele proprii ale
agentului, după verificarea referințelor GDScript, native și de test:

- Vechiul registru de operații al chatului și reconstruirea lui din istoric.
  Running Tools folosește evenimentele harness-ului; planul și sarcinile
  secundare au propriile stări, iar rezultatele rămân în Jurnal.
- Cele două rânduri permanent ascunse pentru sarcini/referințe, copia
  nefolosită a pașilor planului și stările vechi fără cititori.
- Helperul Ollama fără apelanți și constantele nefolosite pentru calea
  scripturilor și vechea comandă de activare Termux.
- Calea duplicată de audit și serializarea rezultatelor pentru un UI eliminat.
  Mascarea cheilor și omiterea imaginilor/binarelor rămân centralizate în
  `_record_event` / `_journal_value`.

Testele runtime folosesc acum o copie temporară a proiectului fixture, fără
cache-ul `.godot` și fără rezultatele `ai_test_*` anterioare. Verificat că nu
apar fișiere noi sau modificări ale artefactelor existente în fixture;
editarea sursei testului UI este consemnată separat. Proiectele și asseturile
utilizatorului nu au fost atinse.

Păstrate apelurile dinamice native, callback-urile Godot și toate cele 30 de
scripturi embedded folosite. Runtime Linux, fallback-ul Termux, Blender,
MCP și companionul opțional nu sunt cod mort.

Validat local cu Godot ARM64 oficial prin Debian/PRoot: **495 aserțiuni runtime**,
**514 verificări editor în configurația narrow** și **84 verificări dedicate
în phone landscape**, toate fără eșecuri; **28 teste Python Blender/Termux**
trecute. Inspectate capturile panoului de progres expandat și cardului compact
cu Running Tools. Probele dedicate includ jurnal complet, mascarea datelor,
rotația/exportul logurilor, scroll tactil și selecție prin apăsare lungă.
Dovezi în `.ai-qa/dead-code-cleanup-20261027/`:
`audit.json`, `runtime-final.log`, `render-final/narrow/editor-report.json`,
`todo-final/phone_landscape/editor-report.json`, `fixture-isolation-final.json`.

La încheierea curățeniei, schimbările erau numai în surse și teste locale,
fără recompilare sau CI. APK-ul din Download era încă `7576033`.
Recompilarea solicitată ulterior este consemnată în etapa curentă de mai sus.

## Etapa precedentă — TODO aplicat și APK livrat, 27.10.2026

Utilizatorul a autorizat implementarea AG-01–AG-20 și o nouă compilare/livrare.
Detaliile implementărilor sunt în [TODO_AGENT.md](TODO_AGENT.md), în tabelul
livrării. Sunt incluse și sursele încă nelivrate pentru execuție fără plafon și
aprobări încadrate. Agentul rămâne în Godot, fără un harness extern obligatoriu.

Cod nou pentru scene în tab separat cu rădăcină confirmată, toleranță numerică,
setări tipizate, diagnostic de rulare/UID, scheme reutilizate la continuare,
captură/input/stare de joc pentru părinte, raport de întrerupere și verificări
necesare înainte de finalizarea planului. Schimbările shell sunt consemnate
separat, fără a pretinde recuperare nativă. Running Tools nu mai are dropdown;
planul și cardurile sunt compacte, viewer-ul agentului cere intenție explicită,
iar gesturile peste text/cod au rută de scroll și selecție prin apăsare lungă.

Jurnal complet JSONL cu rotație la 8 MiB și export automat într-un director ales.
Include model/effort/mod/build/YOLO și autorizările, exclude cheile și datele
binare/imaginile. Consola se reconstruiește când este afișată, cu actualizări
grupate. Recuperarea Runware validează același task și un artefact complet chiar
dacă transportul întoarce HTTP 500; o simplă confirmare incertă rămâne incertă.

Probe locale: **495 aserțiuni runtime / 0 eșecuri**, inclusiv HTTP fixture →
recuperare → descărcare fără generare duplicată; **84 verificări editor dedicate /
0 eșecuri** în phone landscape. Inspectate capturile centrale și dock stânga/dreapta.
Prima probă de captură folosea un helper de test greșit; corectat fără efect asupra
aplicației. Testul de apăsare lungă a fost corectat să atingă textul real la scara
telefonului. Regresia completă locală a depășit inițial bugetul de 180 s; după optimizarea
consolei și reluarea cu timp suficient a trecut: **514 verificări / 0 eșecuri**. Acest timeout aparține evaluatorului,
nu introduce o limită a agentului. Dovezi: `.ai-qa/todo-20261027/` și logurile
`todo-20261027-runtime-final.log`, `todo-20261027-full3.log`.

Au trecut și testele de livrare (3), conector (28), surse runtime (2) și rootfs (4).
Puntea C++ și întregul editor nativ au trecut verificările CI:
**527 verificări × 5 configurații**, plus **86** în scenariul TODO. Include
crearea scenei într-un tab separat și păstrarea scenei anterioare. Inspectate
și capturile editorului nativ pentru chat și dockuri. În editorul
upstream: **514 × 5**, plus **84** dedicate; runtime **495 / 0**, companion
și verificările Linux/Android trecute. Prima rundă nativă a identificat o
injecție greșită a fixture-ului pentru copilul cu 106 cereri; testul a fost
corectat să injecteze furnizorul în scriptul instanței native. Runda finală
nu folosește rezultatul jobului precedent eșuat/anulat ca dovadă de succes.

Build final: [40479134520](https://github.com/JDscript1/godot-ai-android/actions/runs/40479134520), sursă
`7576033582d9fac083376b478f9b70c531f356f4`. APK **112,304,546 bytes**,
`com.jdscript.godotai.debug`, ARM64; certificatul persistent verificat, toate
cele **30 de scripturi runtime** comparate byte cu byte cu sursa. Verificate
PRoot/loader/probă ARM64 și hash-ul bazei Linux încorporate.

Înlocuit atomic installerul și checksum-ul la **10:23:42 CET** în
`/storage/emulated/0/Download/Godot-AI-Android-arm64-debug.apk`. Un singur
installer al fork-ului în Download; celelalte descărcări sunt păstrate.
SHA-256: `b8ecf4134f362b9a190f90ce7ecda23fdcc6bc568af6c820d91446de72649cc6`.

Dovezi: `.ai-qa/delivery-7576033.json`, `7576033-apk-verification.json`,
`7576033-ci.log`, `7576033-native-ci/`, `todo-20261027/`.
APK-ul nu a fost instalat automat. Gesturile fizice, aprobarea/refuzul,
sarcinile reale peste plafonul vechi, comparația consumului cu același model
și workflow-ul Runware real până la mesh rămân confirmări separate.

Jurnal: 27.10.2026 — livrat **7576033**, TODO implementat, verificări runtime,
editor nativ și Android trecute; installerul c418f97 înlocuit în Download.

## Etapa precedentă — salvare/căi și probe native automate, 27.10.2026

Reprodus defectul din APK: salvarea scenei într-un director nou poate întoarce
`ok=true, saved=false`. Corectat în surse: creează părinții, respinge destinațiile
invalide/blocate, verifică fișierul și calea activă și raportează eșecul ca eroare.
`godot_project` include `project_path`, `scene_path` și ultimele căi existente
din istoricul persistent al proiectului. Instrucțiunile cer folosirea structurii
existente și a căilor confirmate, inclusiv la continuare; fără foldere alternative
sau copii de înlocuire când o scenă nu este găsită.

Verificare locală: proba de regresie a avut **45 verificări / 8 eșecuri** înainte
de corecție; versiunea finală are **50 / 0** în editor și **277 / 0** aserțiuni
runtime. Include salvare/reîncărcare reală, copii persistente, spații în cale,
salvare repetată fără duplicate, destinație blocată și context într-o conversație
nouă. Dovezi: `.ai-qa/scene-path-fix-20261027/green3/` și `runtime/`.
Editor local headless, separat de Android; erorile rendererului Dummy la
miniaturi nu sunt probe de randare. Nu s-a compilat, înlocuit sau instalat APK.

La cererea utilizatorului, testele următoare sunt trimise agentului nativ instalat
prin driverul de dezvoltare, cu DeepSeek `deepseek-flash`, effort medium și YOLO
deja activ, fără schimbarea permisiunilor. Proiect separat:
`Documents/GodotAI-Agent-Suite-20261027/project`. Scena principală și proiectul
Vampyr sunt păstrate. Logurile, checkpoint-urile, conversațiile și artefactele
se colectează pe turn; seiful API nu este citit. Funcțiile de calcul/date au
probe runtime trecute, dar două workflow-uri au atins plafonul vechi de 30 de
cereri. [Raportul rundei](docs/AI_AGENT_DEVICE_BATCH_20261027.md) documentează
și corecțiile procedurii evaluatorului, fără a atribui agentului erorile de setup.
AG-01/19 rămân deschise pentru livrare și confirmare fizică.

Evaluarea independentă a artefactelor UC-13/14/15 a trecut **17 verificări**,
plus trei comparații exacte pentru UC-16/17. UC-19 a identificat AG-20: creare
de scenă raportată ca reușită când rădăcina activă rămâne cea veche; agentul a
observat și a retras cele două noduri adăugate acolo. Defect consemnat, necorectat.
Runda așteaptă deblocarea dispozitivului și revenirea în Godot. Colectorul este
oprit cu cererea UC-19 păstrată pentru adoptare, fără retrimitere sau teste noi.

Jurnal: 27.10.2026 — corectate salvarea în directoare noi și contextul căilor;
50 verificări editor și 277 runtime trecute. Testele native continuă pe APK-ul
vechi; dovezile de sursă și dispozitiv sunt consemnate separat.

## Etapa precedentă — reconectare și audit UC-04, 27.10.2026

Conexiune ADB restabilită la adresa indicată de utilizator. Colectate 367 de
evenimente din jurnalul Vampyr: prefixul de 335 este identic, cu 32 noi, dintre
care 31 în turnul UC-04. Utilizatorul a trimis primul fișier integral, dar agentul
a executat numai prima cerință: **7 cereri / 26,37 s**, șase tool-uri executate,
o descoperire și un `tool_not_loaded`, recuperat după încărcarea schemei.

Fișierul permission_guard.txt a trecut de la ORIGINAL_TEST_04 la APPROVED_TEST_04;
KEEP și celelalte șase fișiere de control sunt identice. Diff-ul turnului confirmă
un singur fișier, +1/-1, cu recuperare. Agentul a raportat corect că testul de
refuz nu este demonstrat. Jurnalul nu confirmă modul YOLO sau decizia concretă
de autorizare; nu clasificăm acest rezultat ca ocolire de permisiuni sau UC-05
trecut. UC-04 este neconcludent și necesită repetare cu precondițiile corecte;
UC-05–UC-09 nu au rulat. În total, 47 de cazuri nevalidate, 46 neexecutate.

Actualizate catalogul, pachetul pentru dispozitiv și AG-09/12 din TODO. Dovezi:
`.ai-qa/manual-agent-part01-result-20261027T043339Z/`, cu jurnal, conversație,
checkpoint, manifestul schimbărilor, hash-uri și raport. Evaluatorul nu a resetat
proba, schimbat setări sau trimis cereri către agent. Fără schimbări runtime/APK.

## Etapa precedentă — toate cele 47 de probe rămase, 27.10.2026

Pregătit [pachetul complet UC-04–UC-50](docs/AI_AGENT_REMAINING_TESTS.md),
cu toate cerințele de copiat, moduri, pregătire și criterii de trecere. Mesajele
ulterioare pentru steering, restaurare și preview sunt separate de prima cerere.
Intervențiile pentru aprobări, Stop/Resume, background și rețea sunt explicite;
integrările lipsă și generările cu cost rămân condiționate de precondițiile probei.
Inclusă subproba fizică de scroll AG-16 în verificarea conversației UC-48.

Copie completă `Documents/Godot-AI-Agent-Tests/TESTE_RAMASE_47.md`, instrucțiuni
`INAINTE_DE_TESTE.txt` și șase părți TXT de maximum 7.013 caractere, pentru a evita
trunchierea atașamentelor text lungi în aplicație. Verificate cele 47 de ID-uri,
prezența cerințelor, criteriile și corespondența copiilor. Dovezi:
`.ai-qa/remaining-tests-handoff-20261027/validation.json`.
Nu s-au executat teste ale agentului, trimis cereri API sau schimbat fișiere ale
proiectului Vampyr. Runtime-ul și APK-ul sunt neschimbate; rămân 47 de probe de
executat și evaluat, fără închiderea punctelor din TODO.

## Etapa precedentă — UC-03 verificat și derulare tactilă în TODO, 26.10.2026

Adăugat AG-16 pentru problema raportată de utilizator: glisarea verticală peste
mesaje selectează text în loc să deruleze. Cerința este derulare normală peste
text/cod și selecție intenționată prin apăsare lungă, păstrând gesturile de
menționare și mouse-ul. Nu este o corecție implementată sau reprodusă fizic aici.

Colectate direct 108 evenimente noi din APK-ul c418f97. **UC-03 a trecut pentru
cerința de plan fără modificări:** 6 cereri, 25,9 s, doar inspecție și publicarea
planului. Prima publicare a eșuat deoarece un pas avea 604 caractere, peste
limita internă de 600 nedeclarată în schemă; agentul a scurtat pașii și a reluat.
Aceasta nu este proba respingerii unei scrieri forțate în modul UI Plan.

Utilizatorul a trimis apoi separat „continuă”. Implementarea autorizată a creat
șase fișiere mini_coins, a validat trei scripturi și a pornit/oprit scena:
17 cereri, 109,7 s, 20 operații și 4 descoperiri. Output-ul agentului verifică
`CONNECTED_COINS=3`; nu dovedește colectarea. Cele opt fișiere protejate sunt
identice. Agentul a declarat colectarea neverificată și nevoia de input manual,
dar a marcat planul și harness-ul completed fără să verifice ruta Playtest.
AG-17 urmărește finalizarea pe criterii, iar AG-18 contractul formatului de plan.

Proba independentă a evaluatorului, în Godot Linux ARM64, pe copia exactă a celor
șase fișiere: input de mișcare fără teleportare, contor 0/3→1/3→2/3→3/3, zero
monede rămase. Trecut; nu este playtest executat de agentul Android sau probă de
control tactil. Dovezi: `.ai-qa/manual-agent-uc03-result-20261026T215150Z/`.
Actualizate TODO-ul și catalogul/copia din Documents; 47 de scenarii rămân
neexecutate. Evaluatorul nu a modificat proiectul și nu a trimis cereri noi de
model/generare. Fără schimbări runtime sau APK nou.

## Etapa precedentă — suită de 50 de use case-uri, 26.10.2026

Creat [catalogul de teste](docs/AI_AGENT_USE_CASES.md), legat din README și TODO:
**50 de scenarii**, incluzând cubul parțial și depanarea trecută, plus **48 de
scenarii noi neexecutate**. Fiecare are cerință de trimis agentului, mod,
precondiții, cost de generare dacă se aplică și criteriu de verificare. Sunt
acoperite controlul/permisiunile, codul, scenele și jocul, media, integrările,
generarea, sarcinile extinse, interfața și conexiunile. Probele se rulează pe
rând; integrarea lipsă sau o funcție UI încă nelivrată se consemnează separat.

Copie standalone în `Documents/Godot-AI-Agent-Tests/SUITA_AGENT_50.md`. Pentru
UC-04 au fost create numai două fișiere noi în `vampyr/agent_tests/test_04/`,
fără suprascrieri. UC-03 Plan este următoarea probă. Salvate hash-urile a opt
fișiere de control și jurnalul inițial, 227 înregistrări. Dovezi:
`.ai-qa/agent-suite-20261026T214251Z/`, cu catalog structurat și manifest.
Verificate numărul unic de scenarii, secțiunile, precondițiile/costurile și
corespondența copiei de pe dispozitiv. Nu s-au executat cele 48 de scenarii,
nu s-au trimis cereri de model/generare și nu s-au schimbat runtime-ul sau APK-ul.

## Etapa precedentă — cerința de execuție până la rezultat, 26.10.2026

Întărită în [TODO_AGENT.md](TODO_AGENT.md) cerința utilizatorului: fără plafon
total de pași/cereri/runde, inclusiv subagenți și reluări; implementarea,
verificarea și corectarea continuă până la rezultatul cerut. Răspunsurile
intermediare nu încheie un plan nefinalizat. Stop, permisiunile și blocajele reale
rămân distincte de un plafon artificial. AG-03 urmărește livrarea corecției deja
în sursă și confirmarea rezultatului pe dispozitiv. APK-ul c418f97 păstrează încă
limita veche. Etapă de documentare, fără schimbări runtime sau APK nou.

## Etapa precedentă — cerințe UI adăugate în TODO, 26.10.2026

Adăugate în [TODO_AGENT.md](TODO_AGENT.md) punctele AG-13/14/15: eticheta exactă
Running Tools cu unealta activă actualizată dinamic, fără dropdown; imagini și
mesh-uri generate afișate compact în chat, cu viewer deschis la apăsare sau
cerere explicită; cadru TODO/plan mai îngust și adaptiv. Observarea în background
de către agent rămâne distinctă de deschiderea preview-ului pentru utilizator.
Sunt cerințe consemnate, încă neimplementate. Nu s-au schimbat sursele runtime,
nu s-au rulat probe de interfață și nu s-a recompilat APK-ul.

## Etapa precedentă — test 02 trecut pe Android, 26.10.2026

Utilizatorul a transmis cerința agentului instalat, în proiectul Vampyr, folosind
aceeași conversație ca la cub. Jurnalul, checkpoint-ul și istoricul au fost
colectate direct prin ADB. **Cerința de depanare a trecut în APK-ul c418f97**:
agentul a corectat exact două linii din counter.gd (colonul lipsă și acumularea
prin +=), a validat scriptul prin parserul nativ, a rulat numai scena test_02,
a citit `TEST_02_TOTAL=20`, a oprit rularea și a verificat `running=false`.
Răspunsul final are trei rânduri și este susținut de rezultate.

Runda: **48,8 s, 17 cereri, 13 operații executate, 3 descoperiri** și un apel
respins înainte de execuție (`godot_apply_patch / tool_not_loaded`). După
`tool_describe`, agentul a reluat corect. Diagnosticul inițial `valid=false`
arată detectarea reală a erorii introduse, nu un eșec al instrumentului.
La final, starea harness-ului este `completed`. Fișierul de control, markerul,
semnătura funcției, scena test_02, project.godot, icon.svg și scena test_01 sunt
păstrate identic. Diferența scriptului constă numai în cele două linii cerute.

Verificare independentă a rezultatului, în afara proiectului: **6 cazuri trecute**
în Godot 4.7.2 Linux ARM64, cu alte valori, array gol și numere negative. Copia
verificată are exact hash-ul scriptului reparat de agent. Evaluatorul nu a
modificat proiectul, nu a reparat scriptul și nu a trimis cereri noi de model.
Proba nu este izolată de istoricul testului 01 și nu dovedește o accelerare
comparativă. Cele 69 de evenimente noi sunt lizibile integral, fără trunchieri,
și continuă exact jurnalul inițial salvat. Dovezi:
`.ai-qa/manual-agent-test-02-result-20261026T212532Z/`, inclusiv raport,
conversație, checkpoint, snapshot și `independent-check/result.json`.
Actualizat [TODO_AGENT.md](TODO_AGENT.md), inclusiv AG-12 pentru descoperirea la
mesaje noi și Resume. Fără corecții runtime sau APK nou în această etapă.

## Etapa precedentă — test 02 pregătit pentru depanare, 26.10.2026

La cererea utilizatorului, pregătite trei fișiere noi în
`Documents/vampyr/agent_tests/test_02/`: script cu eroare de sintaxă și calcul,
scenă dedicată și fișier de control. Niciun fișier existent nu a fost suprascris.
Hash-urile configurației, icon.svg și scenei test_01 au rămas identice. ADB este
conectat, iar jurnalul inițial al proiectului a fost salvat direct, 158 intrări.

Pe o copie izolată, Godot 4.7.2 Linux a confirmat eroarea intenționată de parser.
Cazurile pentru verificarea logicii și snapshot-urile rămân în afara proiectului.
Utilizatorul va trimite cerința agentului prin conversație nouă; evaluatorul nu a
trimis cereri de model sau generare. **Proba agentului este în așteptare**, nu
este marcată trecută. Dovezi: `.ai-qa/manual-agent-test-02-20261026T205531Z/`;
stare și criterii în [TODO_AGENT.md](TODO_AGENT.md). Fără corecții runtime sau
APK nou în această etapă.

## Etapa precedentă — audit fizic test 01 și TODO agent, 26.10.2026

Reconectare ADB autorizată; citite direct jurnalele aplicației și salvate probele
fără copiere în conversație sau extragerea cheilor. Cerința a fost transmisă de
utilizator agentului instalat, în proiectul **Vampyr**. Citite jurnalul, istoricul,
checkpoint-ul, diff-ul, captura agentului și fișierul scenei. Build efectiv:
**c418f97**. Nu a fost transmisă o nouă cerere către model de către evaluator.

**Rezultat: scenă creată corect, workflow neterminat.** Există
`res://agent_tests/test_01.tscn`, cu Node3D, BoxMesh verde, cameră activă și
DirectionalLight3D. Agentul a salvat, a cerut deschiderea scenei și a pornit-o;
jurnalul confirmă `running=true`. Utilizatorul a precizat că a închis manual
preview-ul cubului înainte de captura editorului. Captura și starea ulterioară
`running=false` nu sunt atribuite unui eșec al agentului. Copia nemodificată a
scenei a fost încărcată și randată separat în Godot 4.7.2 Linux ARM64 / GL
compatibility: cub verde vizibil, 13.672 pixeli verzi la 960×640; imaginea a fost
inspectată. Aceasta este verificare independentă a artefactului, nu captură a
jocului Android produsă de agent. Proiectul utilizatorului nu a fost modificat.

Runda instalată: **137,3 s, 30 cereri, 39 operații executate și 4 descoperiri**,
două rezultate de tool raportate ca erori. Sfârșit `limited / step_limit`, plan
în `verifying`, fără răspuns final. Una dintre erori este fals pozitiv numeric:
rotația -50/-35 a fost recitită ca -49.999996/-34.999996. Cealaltă este o captură
`target=window` cerută fără handle, acceptată de schemă dar respinsă de execuție.
Două salvări au returnat `ok=true, saved=false` înainte de crearea folderului.
Agentul a recuperat prin salvare temporară în rădăcină, `mkdir` în Linux,
salvarea destinației și eliminarea copiei temporare prin `rm`.

Output-ul conține un UID nerecunoscut pentru scena principală. UID-ul exista
înaintea testului, când proiectul lista doar icon.svg și project.godot.
Configurația este identică cu citirea inițială a agentului; mesajul nu dovedește
modificarea scenei principale de către agent. Cauza declanșării după oprire
necesită o probă separată. Nu s-au instalat pluginuri sau generat asseturi cloud.

Creat [TODO_AGENT.md](TODO_AGENT.md), cu priorități, criterii și diferențierea
corecțiilor deja în sursă față de cele încă neimplementate. Dovezi locale:
`.ai-qa/manual-agent-test-result-20261026T200312Z/`, cu raport JSON/Markdown,
158 înregistrări de jurnal, 149 pentru turn, conversație, checkpoint, captură,
diff și randare de control. Toate rezultatele turnului colectat sunt JSON valid,
fără atingerea limitei de trunchiere. Evaluarea consumului este cumulată pe
cereri, nu dimensiunea unei singure ferestre de context. Niciun fix runtime,
APK nou sau înlocuire în Download în această etapă.

## Etapa precedentă — evaluare Claude Code 2.1.112, 26.10.2026

La propunerea utilizatorului, evaluată înlocuirea orchestrării agentului cu
Claude Code în Linuxul integrat. Confirmate local versiunea 2.1.112, pachetul
`cli.js` / Node >=18 și pornirea `--version` / `--help`; confirmate și
metadatele npm. Consultate documentația oficială pentru SDK/MCP, aprobări,
streaming și configurarea DeepSeek. Fără inferență plătită sau instalare nouă.

Recomandarea este un pilot care păstrează interfața și serviciile Godot, cu
protocol de sesiune bidirecțional și proces supravegheat. Runnerul de comenzi
actual are limită de 600 s și nu înlocuiește o asemenea gazdă de agent. CLI-ul
local Termux nu dovedește funcționarea în APK. Adaptorul companion existent,
pentru alte versiuni SDK/CLI, trebuie verificat înainte de reutilizare.
Claude Code nu este open source. Nu s-a înlocuit agentul și nu s-a modificat
APK-ul. [Evaluare, arhitectură și proba propusă](docs/AI_CLAUDE_HARNESS_EVALUATION.md).

## Etapa precedentă — aprobări accesibile pe ecran mobil, 26.10.2026

**Implementat în sursă; fără APK nou.** Verificate capturile utilizatorului
`Screenshot_20261026_144013.jpg` și `Screenshot_20261026_144350.jpg`, păstrate
în folderul original. În a doua, confirmarea `godot_write_file` afișa codul în
label-ul dialogului; înălțimea minimă depășea ecranul și ascundea butoanele.

Dialogul are acum acțiune și cale compacte, sursa completă într-un TextEdit
readonly cu derulare și butoane fixe «Permite» / «Refuză». Dimensiunea este
limitată la fereastra disponibilă și se recalculează la schimbarea viewportului.
Calea lungă are elipsă și tooltip complet. Rămâne mascarea secretelor. Aprobarea
folosește lanțul ferestrei de setări atunci când aceasta este deschisă.
Corectată și succesiunea după Cancel: ascunderea amânată a dialogului vechi nu
mai poate ascunde următoarea solicitare. Stop închide aprobarea fără a o acorda.

Instrucțiunile agentului precizează că acordul pentru operațiile deja cerute se
solicită prin panoul nativ; nu se mai cere încă un «da» în chat înaintea lui.
Aceasta este o modificare de instrucțiuni, nu comportament validat cu model live.
Nu s-a acordat nicio aprobare și nu s-a schimbat YOLO în aplicația utilizatorului.

Jurnalul trimis ulterior arată că la **13:40:16, ora din jurnal**, Runware a
recuperat și importat imaginea originală. Nu mai era blocată permanent acea
descărcare, dar `quality.ready_for_use=false`: imaginea nu avea transparență.
Scrierile scriptului au fost blocate întâi în faza planning, apoi au revenit cu
`permission_denied`, compatibil cu panoul inaccesibil din captură. Acest cod nu
dovedește că utilizatorul a putut vedea și refuza operația. Raportul vechi de la
10:59 rămâne valabil pentru proba anterioară; nu s-a efectuat o generare nouă.

Alte constatări din jurnal, necorectate în această etapă: `godot_set_setting` a
acceptat un descriptor `$type:PackedStringArray` ca dicționar și a raportat
succes; activarea addonului trebuie verificată separat. Agentul a făcut apeluri
de tool înainte de încărcarea schemelor și a repetat confirmări în text. Nu este
încă o probă de mini hartă finalizată sau de mesh generat.

Primele verificări: **492 aserțiuni runtime** și câte **65 verificări** pentru
dialog în editor narrow / phone_landscape, zero eșecuri. Runda completă a găsit
o problemă de sincronizare între două solicitări; corectată prin afișare amânată
fără amânarea așteptării deciziei. Proba finală separată phone_landscape:
**70 verificări, zero eșecuri**, inclusiv Cancel urmat imediat de o nouă cerere,
aprobări peste Setări, Stop și mascarea secretelor. Captura finală a fost
inspectată vizual. O rundă completă în paralel a expirat și nu este considerată
trecută. Repetarea secvențială a depășit și ea bugetul vechi după peste 400 de
verificări, fără eșecuri raportate până atunci. Runnerul de dezvoltare acceptă
acum `--timeout-seconds`; runda extinsă folosește 480 s, separat de execuția
agentului din produs. **Runda completă finală: 514 verificări editor narrow,
zero eșecuri și ieșire normală.** Include aprobări concurente și fluxurile
existente de chat, planificare, subagenți și unelte. Sunt verificări în editorul
Linux ARM64 upstream, nu o probă fizică a corecției în APK.
Dovezi: `.ai-qa/approval-runtime-20261026.log`,
`.ai-qa/approval-sequential-20261026/`, `.ai-qa/approval-full-extended-20261026/`.
APK-ul instalat și cel din Download sunt încă **c418f97**, cu panoul vechi.

## Etapa precedentă — execuție fără plafon total de pași, 26.10.2026

**Implementat în sursă; APK-ul instalat și cel din Download rămân c418f97.**
Eliminat plafonul implicit de 30 de cereri și clamp-ul ascuns de 100 din
harness-ul propriu Godot. Chatul nu mai transmite o limită din preferințe.
Subagenții Explore/General/Playtest nu mai sunt opriți după 12/30 de pași sau
după un timp total fix. Preferințele vechi sunt eliminate la încărcare.
Continuarea planurilor prin companionul opțional nu mai are plafon de cinci
runde; SDK-ul/serviciul extern poate avea propriile limite.

Agentul poate continua până la răspunsul final, Stop, blocaj real sau eroare.
Rămân verificările pentru repetiții fără progres, anulare între operații,
salvarea progresului, permisiuni, deduplicarea generărilor plătite și timeouturile
unei operații. Bucla cedează execuția editorului și pentru callbackuri sincrone.
O limită pozitivă explicită `max_steps` există numai pentru probe izolate;
producția o omite, iar zero înseamnă nelimitat. Fereastra de context și limitele
furnizorului rămân finite. Defectul Runware observat în proba anterioară este
separat și nu a fost reparat în această etapă.

Verificări runtime: **492 aserțiuni, zero eșecuri**, inclusiv finalizare după
136 de cereri / 135 operații, checkpoint complet și Stop înaintea cererii 112.
Probă separată cu buget explicit de 140 confirmă dispariția clamp-ului de 100.
Testele existente pentru bucle fără progres și deduplicare rămân active.
Editor upstream Godot 4.7.2 ARM64, configurație narrow: **482 verificări, zero
eșecuri**. Chatul finalizează 36 de cereri chiar cu preferința veche setată la
1; un subagent finalizează 106 cereri, ignorând și vechile limite de timp.
Companionul simulat continuă opt runde cu progres și raportează `limited` după
trei continuări cu plan neschimbat. Acestea sunt probe deterministe, fără API
plătit, nu o nouă validare fizică sau de abonament real.
Dovezi: `.ai-qa/unlimited-harness-runtime-20261026.log`,
`.ai-qa/unlimited-harness-editor-final-20261026/` și [contractul harness-ului](docs/AI_HARNESS.md).
Nu s-au făcut alte generări plătite sau modificări în proiectele utilizatorului.

## Etapa precedentă — test automat în aplicația Android instalată, 26.10.2026

**Proba fizică a APK-ului c418f97; fără recompilare.** La cererea utilizatorului,
am înlocuit operarea manuală a interfeței cu un plugin temporar într-un proiect
nou. Acesta identifică panoul nativ al aplicației, trimite cerința pe intrarea
normală a chatului și colectează evenimentele/jurnalul. Nu încarcă alte surse ale
agentului și nu extrage cheile. Asocierea ADB a fost autorizată de utilizator.
Adăugat controlerul reutilizabil `tests/device_workflow.py` și driverul Godot.

Pe NX729J / Android 15, hash-ul panoului încărcat corespunde sursei c418f97.
Agentul a folosit profilurile existente DeepSeek și Runware (Grok Imagine Image /
TRELLIS.2), Auto, reasoning medium; YOLO a fost activat doar în memorie pentru
proba autorizată și restaurat. Limita de 30 de pași a aplicației nu a fost mărită.

Runda: **243,8 secunde, 30 cereri, 39 rezultate de tool, 7 nereușite**.
Terrain3D v1.0.2 s-a instalat (163 fișiere); o probă rulată efectiv pe Android a
confirmat clasa nativă și instanțierea. Agentul nu a interogat separat starea
pluginului editor. Runware a raportat imaginea generată și 0,02 USD, dar răspunsul
recepționat avea HTTP 500 cu payload de succes: adaptorul a respins și recuperarea
aceluiași job. `asset_import` a eșuat, iar harness-ul a atins plafonul fix existent,
cu `limited / step_limit`. **Mesh-ul și mini harta nu au fost finalizate autonom.**
Nu am repetat generarea și nu am construit manual scena pentru a trece proba.

Originalul PNG a fost recuperat separat din URL-ul furnizorului, fără altă
generare; această intervenție nu este import autonom. Imaginea are fundal opac,
deci eliminarea fundalului mai trebuie exercitată după corectarea recuperării.
Costul Runware raportat nu include cererile DeepSeek. Markerul proiectului a
rămas intact. Proiectele existente nu au fost editate.

Constatări pentru corecții: recuperare strictă după HTTP contradictoriu, consum
excesiv de pași la descoperirea/verificarea tool-urilor, două editări respinse
ale setărilor prin unelte de fișiere și plan rămas în urmă față de operațiile
executate. Adaptoarele instalate nu au fost înlocuite pentru această probă.

Dovezi: [metodă și raport](docs/AI_DEVICE_WORKFLOW.md),
`.ai-qa/device-world-workflow-20261026/` și proiectul
`/storage/emulated/0/Documents/GodotAI-Workflow-Test-20261026/project`.
Controlerul status/collect a fost verificat pe dispozitiv; driverul final are
verificare de compilare separată. Nu este încă verificată o rundă cu corecții.

## Etapa precedentă — tarife automate pentru modelele agenților, 26.10.2026

**Implementat în sursă; APK-ul din Download rămâne c418f97.** Formularul
Furnizori AI verifică automat cheia lipită, după 800 ms, și afișează modelele
înainte de salvare. Tabelul căutabil arată separat intrarea/ieșirea per 1M tokeni;
selecția păstrează costul cache-ului, condițiile, sursa și data UTC. Modelul ales
se aplică la salvare, fără a repeta catalogul deja verificat. O cheie nouă
respinsă nu înlocuiește cheia validă. Schimbarea furnizorului anulează cererile
vechi și golește cheia temporară. Cheile nu intră în configurația JSON/jurnal.

Sertarul din chat afișează modelele și tarifele în coloane distincte; alegerea
continuă spre reasoning. Corectată și reinițializarea listei în timpul semnalului
Tree: tranziția este amânată până după încheierea evenimentului, evitând o
cădere nativă reprodusă în proba de interfață.

Tarifele publice se verifică la pornire, la deschiderea modelelor și periodic,
cu un cache de **6 ore**, pentru conexiunile configurate. Buton separat de
actualizare forțată. Sursele publice nu primesc secrete sau prompturi și nu
lansează inferențe plătite. Paginile mari sunt analizate pe un fir secundar.
Actualizarea păstrează selecția și căutarea. Eșecul păstrează ultimul tarif,
marcat «anterior», cu pauză de 5 minute între reluările automate. Un model fără
tarif verificabil nu apare gratuit. Ratele standard și variantele de context /
orar rămân distincte de batch/priority; OpenRouter se convertește din USD/token.
Modelele locale și abonamentele au etichete proprii. Endpointurile intermediare
nu moștenesc tariful unui furnizor direct.

Proba publică reală, numai citire prin transportul Godot: **12 furnizori** au
returnat date analizabile (OpenAI, Anthropic, DeepSeek, OpenRouter, Gemini,
Qwen International/China, Mistral, Groq, xAI, Z.AI, MiniMax). Nu este o probă de
cheie sau disponibilitate individuală a tuturor modelelor. Kimi/SiliconFlow nu
au expus tarife utilizabile în această probă; NVIDIA nu are un feed per-token
configurat. Aliasurile/tarifele ambigue nu sunt ghicite. Generarea 2D/3D rămâne
catalog separat; presetările Meshy/Tripo/OpenAI imagine nu sunt prezentate ca
actualizate de noul mecanism de tarife pentru agenți.

Verificări: **487 aserțiuni runtime**, **478 verificări complete în editor** pe
ecran îngust, **79 verificări furnizori** atât pe ecran îngust cât și pe tabletă și
**53 verificări** în managerul de proiecte, toate fără erori. Dovezi: [detalii și surse](docs/AI_MODEL_PRICING.md),
`.ai-qa/agent-pricing-runtime.log`, `.ai-qa/agent-pricing-ui-narrow/`,
`.ai-qa/agent-pricing-ui-tablet/`, `.ai-qa/agent-pricing-all/`,
`.ai-qa/agent-pricing-start/`, `.ai-qa/agent-pricing-live.log`.
Verificările autentificate pe dispozitiv și un APK nou nu sunt încă livrate.

## Etapa precedentă — Generare cu modele și tarife, 26.10.2026

**Compilat, verificat și livrat în APK-ul c418f97.** Utilizatorul
cere un flux simplu pentru furnizorii cloud: Imagini / Mesh-uri 3D, cheie API,
modele ale furnizorului și prețul în dreptul fiecărui model.

Formularul are selectoare compacte pentru rezultat și furnizor. Lipirea cheii
pornește verificarea după o scurtă pauză și încarcă lista căutabilă fără un
profil salvat anterior. Coloana de cost păstrează USD sau creditele originale;
selecția afișează condițiile, sursa și data tarifului. Profilurile pentru imagini
și 3D rămân distincte și reutilizează cheia furnizorului. Schimbarea serviciului
nu transportă cheia altui furnizor, iar o cheie invalidă nu înlocuiește cheia
validată. Salvarea nu golește selecția/catalogul. Profilurile vechi cu cheia
sub ID-ul propriu pot fi migrate fără reintroducerea ei.

Runware: index public și scheme de preț actualizate, patru cereri simultane,
încărcare progresivă și cache de 24h. Datele publice nu primesc cheia API.
Modelele retrase și SAM 3D, care necesită mască, sunt filtrate. Meshy/Tripo:
cataloage documentate și tarife în credite, verificate la 26.10.2026; verificarea
cheii prin sold nu dovedește accesul contului la fiecare model. OpenAI:
catalogul contului, doar modele de imagine neretrase; tarife orientative sau
variabile unde nu există un preț fix per imagine. Prețurile nepublicate nu sunt
prezentate ca zero. Estimările și prețurile de pornire sunt marcate distinct.

Adăugat adaptorul Meshy text-to-image, cu aceeași organizare/validare a
rezultatelor ca celelalte imagini. Modelele Smart Topology Meshy primesc
parametrul documentat. Profilul salvează metadatele publice ale modelului și
costului, iar agentul le primește în context. Modulele rămân native Godot,
fără runtime extern pentru cataloage și furnizori. Noua componentă
`generation_catalog.gd` este inclusă în cele **29 de scripturi înglobate**.

Probe: **465 aserțiuni runtime** cu HTTP local simulat; fluxul Meshy imagine,
salvarea, download-ul, validarea/importul PNG și GLB sunt incluse. Probe UI
dedicate pentru tabletă și ecran îngust, cu schimbare de rezultat/furnizor,
cheie invalidă, migrarea cheii și preț necunoscut. Fără cereri plătite în aceste
probe. Catalog Runware real prin transportul Godot: **106 modele de imagini,
6 de mesh și 2 scheme reale de preț**, fără cheie și fără generări.
Asistentul din meniul principal: **52 verificări** trecute. Proba generală
locală pe tabletă a depășit limita de 180s fără raport final; nu este contabilizată
ca reușită. Proba generală pe ecran îngust a trecut **466 de verificări**.
Probe dedicate finale: **53 × 2 dimensiuni**, inclusiv mascarea unei chei
repetate de furnizor în mesajul erorii. Pe fork-ul compilat au trecut ulterior
**480 verificări × 5 dimensiuni**, **53 pentru generare**, **57 pentru panouri**
și **54 în lista de proiecte**, fără eșecuri. Capturile compilate de generare
imagini și mesh-uri au fost inspectate vizual.

Dovezi: `.ai-qa/generation-catalog-runtime-final.log`,
`.ai-qa/generation-catalog-final-tablet/`, `.ai-qa/generation-catalog-final-narrow/`,
`.ai-qa/generation-catalog-final-privacy/`, `.ai-qa/generation-public-verification.json`,
`.ai-qa/generation-start-regression/`, `.ai-qa/generation-catalog-full-narrow/`
și `.ai-qa/generation-catalog-regression/`.
[Detalii și surse tarifare](docs/AI_GENERATION.md).

**APK livrat:** [workflow 40298487521](https://github.com/JDscript1/godot-ai-android/actions/runs/40298487521),
toate cele trei joburi reușite. **112.273.374 bytes**, SHA-256
`6727cd66b602d61da82b4922b1825ec72353e817f87530586de2a7fb547e6ed0`.
Verificate semnătura persistentă, pachetul aplicației, cele 29 de scripturi
exacte, pachetul Linux, clasele serviciului, agentul, Asset Store și păstrarea
minimizării panourilor. Înlocuit atomic APK-ul și checksum-ul la
**26.10.2026, 10:25 +01:00**; fără duplicate ale fork-ului în Download.
Dovezi de compilare/livrare: `.ai-qa/c418f97-native/`,
`.ai-qa/c418f97-ci.log`, `.ai-qa/artifacts/c418f97/panel-verification.json`,
`.ai-qa/artifacts/c418f97/linux-verification.json`,
`.ai-qa/delivery-c418f97.json` și `.ai-qa/generation-catalog-verification.json`.
Utilizarea fizică Android și generările reale cu cheile utilizatorului rămân
de verificat separat; citirea catalogului public nu este probă de generare plătită.

Jurnal: 26.10.2026 — implementat fluxul de selecție Imagini / Mesh-uri 3D cu
validarea cheii înainte de salvare, cataloage căutabile și tarife per model;
verificate datele publice Runware și protocoalele simulate; compilat și livrat
APK-ul c418f97 cu toate cele trei joburi de verificare reușite.

## Etapa precedentă — DeepSeek și denumire unitară, 26.10.2026

Utilizatorul a raportat „Adresa serverului nu este validă” la introducerea
cheii DeepSeek în interiorul proiectului și diferența Agent / AI Assistant
între lista de proiecte și editor. Reprodus în formularul real: ștergerea
conexiunii golește adresa ascunsă, dar păstrează selecția DeepSeek; o nouă
cheie fără schimbarea selectorului produce exact eroarea de URL.

Implementat în surse: adresa lipsă a unui furnizor cloud cunoscut se reface
din catalog la salvare, descoperirea modelelor și conversație. Pentru DeepSeek
este `https://api.deepseek.com`, conform [documentației oficiale](https://api-docs.deepseek.com/).
Adresele explicite și gateway-urile se păstrează; o adresă explicită invalidă
este afișată pentru corectare. Repararea unui profil vechi cu URL gol păstrează
cheia și modelele memorate. Schimbarea serverului real cere în continuare
introducerea cheii corespunzătoare. Serverele locale și furnizorii personalizați
cer adresă explicită. Numele filei principale devine **AI Assistant** și în
lista de proiecte, folosind același mesaj de traducere ca în editor.

Probe locale: **447 aserțiuni runtime**, **67 verificări UI furnizori** pe formatul
tabletei și **51 verificări în lista reală de proiecte** pe ecran îngust, fără
eșecuri. Proba de regresie înaintea corecției eșuează exact la readăugarea
cheii DeepSeek; aceeași probă trece după corecție, inclusiv păstrarea cheii și
modelelor, afișarea URL-ului invalid și protecția schimbării destinației.
Capturile au fost inspectate vizual. Testul global folosește panoul încorporat
atunci când rulează cu editorul fork compilat; cu binarul upstream montează
panoul partajat într-un ProjectManager real. CI rulează acum ambele variante.
Corectată ordinea argumentelor proot-distro 5 în lansatorul testului global.

Dovezi: `.ai-qa/deepseek-endpoint-before/`,
`.ai-qa/deepseek-endpoint-runtime.log`, `.ai-qa/deepseek-endpoint-fixed-tablet/`,
`.ai-qa/deepseek-endpoint-start/` și `.ai-qa/deepseek-endpoint-verification.json`.
Cheile probelor sunt fictive; nu reprezintă autentificare verificată cu cheia
utilizatorului.

**APK compilat și livrat:** [workflow 40276596026](https://github.com/JDscript1/godot-ai-android/actions/runs/40276596026),
toate cele trei joburi reușite. Pe fork-ul nativ compilat au trecut
**463 verificări × 5 dimensiuni**, **56 pentru panouri** și **53 în lista de
proiecte**, inclusiv folosirea panoului încorporat și a numelui AI Assistant.
Capturile ecranului principal compilat au fost inspectate vizual.
APK ARM64: **112.270.246 bytes**, SHA-256
`62e8ac1775d5c513f013d6ca01ceb9fbfb58b5a1d066bf5d3932dcfdb4a291ba`.
Verificate semnătura persistentă, pachetul aplicației, cele 28 de scripturi
exacte, minimizarea panourilor și întregul pachet Linux. Înlocuit atomic
installerul afcf2cb și checksum-ul la 26.10.2026 06:59 +01:00; un singur APK
al fork-ului în Download. Instalarea fizică și autentificarea cu cheia
utilizatorului rămân de verificat separat.
Dovezi: `.ai-qa/e401e8f-native/`, `.ai-qa/e401e8f-ci.log`,
`.ai-qa/artifacts/e401e8f/panel-verification.json`,
`.ai-qa/artifacts/e401e8f/linux-verification.json`,
`.ai-qa/delivery-e401e8f.json` și `.ai-qa/e401e8f-delivery.log`.

Jurnal: 26.10.2026 — reprodus și corectat URL-ul cloud gol după ștergerea unei
conexiuni DeepSeek; aliniată denumirea asistentului în cele două contexte;
compilat, verificat și livrat APK-ul e401e8f.

## Etapa precedentă — panouri minimizabile și chat extins, 25.10.2026

Inspectată captura fizică `Screenshot_20261025_203433.jpg`: Output ocupă o
parte mare din înălțime, iar Scene/Inspector limitează lățimea chatului.
Butonul de extindere folosea modul Godot fără distrageri, care ascundea doar
dock-urile laterale.

Corecție compilată în APK: buton dedicat de minimizare pentru panoul inferior nativ,
valabil pentru Output, Debugger și celelalte file. Extinderea din antetul
chatului ascunde și panoul inferior; revenirea restaurează fila deschisă și
poziția chatului, inclusiv stânga/dreapta. Textul din composer și mesajele
de diagnostic se păstrează. O filă aleasă manual între timp este respectată.
Panoul inferior restrâns păstrează filele accesibile pentru redeschidere.
Iconul de revenire este Lucide original, adăugat în catalogul local verificat.
Încadrarea pe lățimea disponibilă se aplică și chatului central extins.

Probe: scenariu UI dedicat cu panou diagnostic real, extindere/revenire,
minimizare nativă, controale accesibile, păstrarea textelor și poziții laterale.
Capturile și rapoartele sunt în `.ai-qa/chat-panels-*`; verificarea runtime
Godot a trecut **429 aserțiuni**. Pe editorul nativ compilat au trecut
**458 verificări × 5 dimensiuni**, plus **56 de verificări dedicate panourilor**
pe formatul tabletei. Scenariul focalizat pe ecran îngust a trecut 53 de verificări.
Capturile compilate cu panoul deschis, minimizat și chatul extins au fost
inspectate vizual. Captura utilizatorului dovedește problema din versiunea
anterioară; testele desktop nu sunt probă fizică a corecției Android.

**APK livrat:** [workflow 40228109943](https://github.com/JDscript1/godot-ai-android/actions/runs/40228109943),
toate cele trei joburi reușite; **112.271.390 bytes**, SHA-256
`4ba0cebd77acc315cc097cee715258cf9cfe00830214004b09f4f2bf8855bffc`.
Verificate semnătura persistentă, cele 28 de scripturi exacte, implementarea
nativă a butonului de minimizare și păstrarea pachetului Linux complet.
Installerul a fost înlocuit atomic, fără duplicate în Download.
Dovezi: `.ai-qa/delivery-afcf2cb.json`,
`.ai-qa/artifacts/afcf2cb/panel-verification.json`,
`.ai-qa/artifacts/afcf2cb/linux-verification.json`, `.ai-qa/afcf2cb-native/`
și `.ai-qa/chat-panels-verification.json`.

Jurnal: 25.10.2026 — adăugată minimizarea explicită a panourilor inferioare și
extinderea completă a chatului cu restaurarea layoutului și păstrarea mesajelor;
compilat și livrat APK-ul `afcf2cb`.

## Etapa precedentă — APK livrat cu Linux automat, 25.10.2026

Utilizatorul a cerut compilarea și înlocuirea APK-ului. Baza Linux este acum
pregătită automat la pornirea asistentului, inclusiv în lista de proiecte.
Eliminate acțiunile manuale Instalează/Dezinstalează Linux; rămân statusul,
Repară la eșec și instalarea utilitarelor opționale. Pregătirea bazei continuă
la trecerea din lista de proiecte în editor. Revalidarea păstrează pachetele.
Compilarea verifică și pachetul Debian, clasele serviciului Linux și conținutul
exact al scripturilor AI înglobate.

**Compilat și livrat:** [workflow 40224731049](https://github.com/JDscript1/godot-ai-android/actions/runs/40224731049),
toate cele trei joburi reușite. APK ARM64 de **112.268.670 bytes**,
SHA-256 `31593a24142a4f7be279057b127d01a0cba1e9e1ba639d2b8be1bf73f3912050`.
Verificate local semnătura persistentă, ID-ul aplicației, cele **28 de scripturi
AI exacte**, prezența agentului și Asset Store în biblioteca nativă, serviciul
Linux privat și hash-urile celor **2.678 fișiere regulate** din pachetul Debian.
Executabilele PRoot/loader nu depind de căi sau biblioteci din aplicația Termux.

Teste: **429 aserțiuni runtime**, **49 verificări Linux pe tabletă și 49 pe
ecran îngust**, plus **438 verificări × 5 dimensiuni** pe editorul nativ compilat,
fără eșecuri. Compilarea Kotlin și probele de livrare atomică au trecut.
Capturile panoului Linux au fost inspectate vizual.

Dovezi: `.ai-qa/delivery-8878801.json`,
`.ai-qa/artifacts/8878801/linux-verification.json`,
`.ai-qa/artifacts/8878801/sources/verification.json`, `.ai-qa/8878801-native/`,
`.ai-qa/linux-auto-ui/`, `.ai-qa/linux-auto-narrow/`,
`.ai-qa/linux-auto-verification.json` și `.ai-qa/8878801-delivery.log`.
Pornirea fizică a noului runtime în aplicația Godot, Blender complet și un
harness extern autentificat rămân de verificat separat. APK-ul a fost pus
pentru instalarea utilizatorului; aplicația instalată nu a fost modificată prin ADB.

Jurnal: 25.10.2026 — Linux obligatoriu pregătit automat, fără acțiuni manuale
pentru bază; compilat `8878801`, verificat și înlocuit installerul din Download.

## Etapa precedentă — runtime Linux persistent pentru utilitare, 25.10.2026

**Implementat în surse, fără recompilare APK:** un runtime comun în
**Integrări → Runtime Linux**, cu bază Debian ARM64 ambalată în build, instalare
nativă în stocarea privată, verificare, dezinstalare, jurnal și oprirea joburilor.
Nu cere aplicația Termux, comenzi lipite sau server companion. Harness-ul
direct-provider rămâne în Godot; Linux este backend-ul opțional pentru CLI-uri.

Utilitare instalabile separat: Python/venv/pip, Node.js/npm, Git, ripgrep și
Blender CLI. Agentul primește `linux_status`, iar după activarea verificată
`linux_execute` și `linux_install_tool`, cu permisiunile existente. Modul Plan
nu pornește comenzile. JNI injectează proiectul curent ca `/workspace`;
modelul nu alege directorul gazdă. Serviciul Android este neexportat, cu proces
separat și notificare foreground, joburi persistente, heartbeat și anulare.
O operație întreruptă nu este relansată automat.

Baza oficială Debian este fixată la commit și SHA-256; buildul verifică
arhiva, iar instalatorul Kotlin verifică fișierele și legăturile înaintea
activării. Pachet local: **32.789.398 bytes**, **104.455.032 bytes** de fișiere
regulate, **3.265 intrări**. Publicarea și sursele/licențele tuturor pachetelor
redistribuite se verifică înaintea livrării efective a unui APK cu noua bază.

**Probe reale de dezvoltare**, într-un filesystem nou al sarcinii, separat de
Debian-ul utilizatorului: instalate și pornite **Python 3.13.5**, **Node 20.19.2**,
**Git 2.47.3**, **ripgrep 14.1.1**. A trecut execuția prin directorul unui proiect
de probă, scrierea fișierului, limitarea ieșirii, timeout-ul, anularea și
ștergerea fără urmărirea unei legături spre un fișier exterior. PRoot-ul compilat
de noi a pornit aceleași utilitare cu loader-ul deja ambalat al Termux.
Aceasta nu dovedește încă loader-ul propriu și serviciul din APK-ul Godot.
Corectată o eroare APT din opțiunile PRoot ale probei; verificarea descărcării
și verificarea utilitarului au rămas etape distincte.

Validări locale: **429 aserțiuni runtime Godot**, **426 verificări UI complete
pe formatul tabletei**, **47 verificări UI focalizate × 2 dimensiuni**,
**4 teste Python pentru rootfs**, **6 probe Kotlin ale instalatorului**,
compilare Kotlin cu clase Android și verificare de sintaxă C++. Capturile
Runtime Linux au fost inspectate vizual. Puntea Android din fixture este simulată.
Dovezi: `.ai-qa/linux-runtime-package/`, `.ai-qa/linux-runtime-tools.log`,
`.ai-qa/linux-runtime-execute.log`, `.ai-qa/linux-runtime-custom-proot.log`,
`.ai-qa/linux-runtime-control/smoke-result.json`, `.ai-qa/linux-runtime-ui/`,
`.ai-qa/linux-runtime-narrow/`, `.ai-qa/linux-runtime-full/`,
`.ai-qa/linux-runtime-kotlin.log`, `.ai-qa/linux-runtime-cpp.log`,
`.ai-qa/linux-runtime-verification.json`.
Document complet: [AI_LINUX_RUNTIME.md](docs/AI_LINUX_RUNTIME.md).

**Rămâne proba fizică în APK** pentru propriul loader, foreground service,
instalare/anulare și revenirea din fundal. Blender complet și un harness extern
instalat, autentificat și conectat agentului nu sunt încă validate. Runtime-ul
le oferă o bază de execuție; fiecare harness are nevoie de adaptor și probe
proprii. APK-ul din Downloads nu a fost înlocuit și nu s-a făcut push.
Jurnal: 25.10.2026 — adăugat Debian persistent în aplicație, manager de utilitare,
punte de execuție și probe reale de dezvoltare pentru Python/Node/Git/ripgrep.

## Etapa precedentă — catalog DeepSeek după salvarea cheii, 25.10.2026

Inspectată captura fizică `Screenshot_20261025_183822.jpg`: sertarul DeepSeek
este deschis, dar nu are modele și afișează doar mesajul generic de lipsă
rezultate. Captura nu demonstrează că o cheie este invalidă. În fluxul anterior,
butonul de salvare interoga automat catalogul doar pentru conexiunile locale;
pentru cloud salva cheia și lăsa descoperirea modelelor la o verificare separată.

**Corectat în surse:** salvarea unei chei cloud interoghează și catalogul,
selectând un model întors de furnizor. Alegerea unei conexiuni cu lista goală
în chat pornește încărcarea; sertarul are și buton **Actualizează**. Lista se
actualizează în același sertar. Dacă verificarea eșuează, apare un mesaj
specific și se păstrează catalogul anterior și selecția utilizatorului.
Răspunsul gol nu este marcat drept verificare reușită. Erorile cloud sunt
separate de indicațiile pentru servere LAN. Activitatea se salvează în jurnal
fără cheia API. Modelele și nivelurile de reasoning provin din răspunsul API,
nu dintr-o listă DeepSeek inventată sau introdusă ca rezervă.

Confirmată ruta `GET /models` și structura metadatelor din
[documentația oficială DeepSeek](https://api-docs.deepseek.com/api/list-models/).
Probe deterministe pentru salvarea cheii cloud, încărcarea automată din sertar,
reasoning, eroare 401, răspuns gol, păstrarea modelului selectat și reîncercare.
**428 aserțiuni runtime**, **414 verificări UI pe formatul tabletei** și
**61 verificări UI pe ecran îngust**, fără eșecuri la verificarea finală.
Capturile finale ale sertarului pe ecran îngust au fost inspectate vizual.

Dovezi: `.ai-qa/deepseek-discovery-runtime.log`,
`.ai-qa/deepseek-discovery-full/phone_landscape/` și
`.ai-qa/deepseek-discovery/narrow/`. Acestea folosesc un server HTTP și un
catalog simulate. Cheia utilizatorului salvată în aplicația Android nu a fost
citită și nu a fost probată cu serviciul DeepSeek real.

**APK-ul nu a fost recompilat sau înlocuit; nu s-a făcut push.** În APK-ul
existent, selectarea conexiunii din Setări → Furnizori AI și apăsarea
**Verifică / modele** rămâne calea pentru încărcarea catalogului. Dacă ea
întoarce o eroare, aceea trebuie verificată separat de problema fluxului UI.
Jurnal: 25.10.2026 — descoperire automată a modelelor cloud după salvarea cheii,
actualizare direct din chat și diagnostic de catalog, verificări locale trecute.

## Etapa precedentă — Agent înainte de proiect și acces direct la rezultatul 3D, 25.10.2026

**Implementat în surse, fără recompilare APK.** Managerul de proiecte primește
un tab **Agent**, lângă **Projects / Asset Store**. Același chat, aceiași
furnizori salvați și același seif de chei sunt folosite înainte de selectarea
unui proiect. Gazda nativă este separată de `EditorPlugin`; nu construiește
un `EditorNode` și nu depinde de Termux. Scurtături compacte cer dialogul nativ
pentru proiect nou/import sau afișează lista proiectelor. Modelul poate cere
aceste dialoguri, fără să declare că proiectul a fost creat doar fiindcă s-a
deschis un dialog.

Conversațiile inițiale au stocare separată. La deschiderea individuală a unui
proiect, conversația activă, selecția modelului și referințele partajate sunt
transferate într-o conversație nouă a proiectului. Istoricul proiectului nu
este înlocuit; transferul consumat nu este importat din nou. Nu se transferă
în modul de recuperare sau la deschiderea mai multor proiecte simultan.
O sarcină AI activă trebuie încheiată/oprită înaintea transferului. Instrumentele
pentru scene, editări, generare, Blender și proiect nu sunt oferite în ecranul
inițial; apelurile directe de editare sunt refuzate. Setările de acolo includ
General, Furnizori AI, Abonamente, Jurnal și Voce.

Pentru rezultatele generării, descărcarea finalizată emite un eveniment către
chat. Aplicația înregistrează fișierul și păstrează cardul în conversație chiar
dacă modelul omite `file_show`. Se folosește numele fișierului importat în
proiect, cu copia descărcată ca rezervă. Comanda dedicată **`file_preview`**
deschide previzualizatorul Godot și confirmă încărcarea efectivă. Un format
nesuportat sau un fișier inexistent nu mai pot primi o confirmare falsă.
`file_observe` oferă în continuare inspecție în fundal. Instrucțiunile și
catalogul inițial al agentului separă vizualizarea nativă GLB/glTF de modelare
și conversie cu Blender. **Vizualizarea GLB/glTF nu cere Blender CLI.**
Această etapă nu adaugă un cititor nativ pentru FBX/BLEND; originalul GLB
rămâne previzualizarea disponibilă pentru aceste exporturi.

Verificări locale: **425 aserțiuni runtime**, **399 verificări ale editorului
pe formatul tabletei**, **48 verificări × 2 dimensiuni într-un manager de
proiecte real fără `EditorNode`**, **52 verificări focalizate pe transfer și pe
rezultatul generării la lățime mică**, fără eșecuri. Proba managerului folosește chatul din
surse montat de fixture în managerul Godot oficial; noua înregistrare C++ a
tabului a trecut verificarea de sintaxă, nu a fost încă executată într-un
binar recompilat. Furnizorul de chat din probe este simulat. Proba 3D folosește
un GLB real, verifică geometria, pixeli randați, cardul după reîncărcarea
conversației și deschiderea fără Blender. Capturile au fost inspectate vizual.

Dovezi: `.ai-qa/start-agent-runtime.log`, `.ai-qa/start-agent-cpp.log`,
`.ai-qa/start-agent/desktop/`, `.ai-qa/start-agent/narrow/`,
`.ai-qa/start-agent-full/phone_landscape/`, `.ai-qa/start-agent-narrow/narrow/`.
Testul nou se rulează cu `modules/ai_assistant/tests/start.py`; scenariul
`startup` al `tests/render.py` acoperă transferul și cardul generat.

**APK-ul din Download rămâne cel anterior.** Nu s-a făcut push și nu s-a
pornit o compilare Android. Comportamentul fizic Android, lansarea nativă a
noii gazde compilate și generarea cu un furnizor real se verifică separat.
Jurnal: 25.10.2026 — adăugată gazda agentului în managerul inițial, transferul
conversației și accesul persistent la previzualizarea rezultatelor generate.

## Etapa precedentă — Furnizori AI fără selectoare suprapuse, 25.10.2026

Pornind de la captura `Screenshot_20261025_174937.jpg`, simplificat panoul
**Furnizori AI** în surse. Eliminat dropdown-ul de profil care repeta
„Adaugă un furnizor”; selectorul catalogului se numește acum **Furnizor**, cu
aceleași grupuri Cloud și Local. Conexiunile configurate apar într-o listă
distinctă **Conexiuni salvate**, cu icon, tip Cloud/Local și buton de adăugare.
Lista și statusul nu apar când nu există conexiuni, iar Șterge este ascuns
pentru formularul nou. Căutarea LAN și explicația aferentă apar numai pentru
furnizori locali sau conexiuni personalizate.

Alegerea unei conexiuni salvate încarcă formularul și îl aduce în partea de
sus. Alegerea altui furnizor pregătește o conexiune nouă, păstrând conexiunea și
cheia precedente. Nu s-a schimbat schema de stocare sau accesul la furnizori
din chat. Testate cu chei simulate salvarea cloud/local, păstrarea secretului,
selecția rândului corect și ștergerea numai a conexiunii selectate.

Verificări locale: **425 aserțiuni runtime**, **384 verificări UI pe formatul
tabletei** și **48 verificări UI pe ecran îngust**, fără eșecuri de test.
Capturile randate au fost inspectate vizual, inclusiv formularul gol,
conexiunile cloud/local și lista salvată. Dovezi:
`.ai-qa/provider-settings-runtime.log`,
`.ai-qa/provider-settings-full/phone_landscape/editor-report.json`,
`.ai-qa/provider-settings-full/phone_landscape/settings-providers.png` și
`.ai-qa/provider-settings-narrow/narrow/`. Acestea sunt verificări locale în
Godot prin instrumentele de dezvoltare, nu probe fizice ale APK-ului sau
conexiuni cu furnizori reali. Captura utilizatorului confirmă acum accesul la
Agent → Setări în versiunea restaurată.

**Doar surse:** APK-ul din Download nu a fost recompilat sau înlocuit și nu
s-a pornit o compilare Android prin push. Verificarea PRoot din APK-ul
experimental rămâne o etapă separată. Jurnal: 25.10.2026 — separat alegerea
furnizorului de lista conexiunilor salvate și verificat vizual panoul simplificat.

## Etapa precedentă — captura arată managerul de proiecte, 25.10.2026

Inspectată captura fizică `Screenshot_20261025_171509.jpg` din
`/storage/emulated/0/Pictures/Screenshots/`. Ea arată **managerul de proiecte**,
lista goală și tabul **Asset Store vizibil sus**. Versiunea din colț este
`5baf89043`, deci captura este din APK-ul restaurat. Agentul este înregistrat
în editorul unui proiect (`editor/editor_node.cpp`), nu în managerul inițial.
Următorul pas este importarea fișierului `project.godot` și deschiderea
proiectului cu **Modificare**. Lista goală nu demonstrează că fișierele
proiectului au fost șterse.

Captura explică absența Agentului din ecranul prezentat și nu constituie
dovadă de regresie în editor pentru `644a3b0`. Nu am observat încă editorul
deschis în acel build și nu am validat proba PRoot din APK. Nu s-a schimbat
codul, nu s-a recompilat și nu s-a înlocuit din nou APK-ul din Download.
Jurnal: 25.10.2026 — clarificat prin captură ecranul afișat; verificarea
Agentului trebuie continuată într-un proiect deschis.

## Etapa precedentă — restaurare APK anterior după raport de interfață lipsă, 25.10.2026

Utilizatorul raportează că buildul experimental `644a3b0` nu mai afișează Agent,
Asset Store și alte elemente ale editorului. Verificarea locală a pachetului
confirmă prezența codului pentru Agent și Asset Store, toate cele 27 de
scripturi încorporate și niciun asset anterior eliminat sau schimbat. Diferența
de dimensiune provine din comprimare: biblioteca motorului are aproximativ
131 MB în ambele APK-uri, dar în `644a3b0` ocupă aproximativ 70 MB în ZIP.
Acestea sunt dovezi despre conținut, nu despre funcționarea fizică a interfeței.
Captura primită ulterior este analizată în etapa curentă de mai sus.

Readus în Download installerul anterior **`5baf890`**, 145.350.814 bytes,
SHA-256 `8982c87ce00193f70b4847a08431de26180aba0812b5808d1032a667c79d857e`.
Verificate din nou semnătura persistentă, identitatea aplicației și sursele
celor 27 de scripturi față de commit. Înlocuirea este atomică; instalarea din
Android și revenirea efectivă a interfeței nu au fost executate de agent.
Proiectele și setările utilizatorului nu au fost modificate. Sursele și
artefactul PRoot experimental sunt păstrate separat în proiect.

Dovezi: `.ai-qa/rollback-agent-20261025.json`,
`.ai-qa/agent-missing-apk-analysis-20261025.json` și
`.ai-qa/artifacts/5baf890/`. Nu s-a recompilat sau modificat cod pe baza unei
cauze presupuse. Jurnal: 25.10.2026 — retras din Download buildul experimental
și restaurat installerul anterior verificat; investigația UI rămâne deschisă.

## Etapa precedentă — PRoot propriu compilat în APK experimental, 25.10.2026

Adăugat buildul din surse pentru PRoot 5.1.107.101, talloc 2.5.0 și
libandroid-shmem 0.7, cu versiuni/hash-uri fixate și dependențe nesistem legate
static. Loader-ul și directorul temporar sunt configurate la pornire, fără
căi fixe către aplicația Termux. Gradle ambalează bibliotecile, o probă Linux
ARM64 minimală, hash-urile și licențele; CI păstrează și arhiva surselor exacte.
Serviciul separat verifică integritatea și încearcă automat proba Android și
proba Linux. Rezultatul ajunge în **Jurnal**, fără a declara Blender disponibil.

Verificări locale: **425 aserțiuni Godot**, zero eșecuri, inclusiv lipsa activării
false a Blender și jurnalizarea o singură dată a probei. Kotlin compilează cu
SDK 36. Buildul PRoot local produce un ELF ARM64 de 280.072 bytes și un loader
de 17.800 bytes; `DT_NEEDED` conține numai biblioteci Android. Încercarea de a
executa loader-ul din fișierele private a fost refuzată (`Permission denied`),
deci nu este prezentată ca probă Linux reușită. Urmează buildul NDK și
verificarea din APK, unde loader-ul este extras de Android în zona nativă.
Dovezi: `.ai-qa/embedded-proot-build.log`, `.ai-qa/embedded-proot-sources/build.log`,
`.ai-qa/embedded-proot-smoke/result.json`, `.ai-qa/embedded-runtime-godot-tests.log`
și `.ai-qa/embedded-runtime-kotlin-v2.log`. Instalarea Termux și containerul
Debian sunt păstrate. Blender nu este încă inclus.

Jurnal: 25.10.2026 — construit PRoot propriu din surse și pregătită proba Linux
din procesul Android separat, cu verificarea hash-urilor și diagnostic în Jurnal.
Prima rulare CI (`40190593253`) s-a oprit înaintea compilării PRoot din cauza
unui HTTP 503 de la sursa talloc. Adăugate reîncercări, mirror oficial Samba,
cache pentru arhive și teste pentru refuzul unui checksum modificat.
A doua rulare (`40190911801`) a trecut descărcările, compilarea talloc și
testele runtime/editor; NDK a identificat un include `string.h` lipsă în extensia
ashmem a PRoot. Include-ul este acum adăugat explicit de scriptul reproductibil.
Proba guest Linux a trecut separat cu PRoot-ul și loader-ul deja ambalate ale
Termux (`.ai-qa/embedded-proot-smoke/guest-control.json`), izolând refuzul local
la loader-ul nou din stocarea privată. Acesta este un control al probei, nu
dovada că runtime-ul nostru funcționează în APK.
Corectată și detectarea versiunii PRoot: generatorul upstream moștenea tag-ul
Godot din checkout-ul părinte. Buildul folosește acum versiunea din sursa fixată.

**Compilat și livrat:** [workflow `40193820909`](https://github.com/JDscript1/godot-ai-android/actions/runs/40193820909)
a trecut toate cele trei joburi pentru commitul `644a3b0`. APK-ul are
**80.199.176 bytes**, SHA-256
`8fddf9fabc6b1cbe8ec51b411b828ac3d27e5c8b2cf4246269e2a07777d353eb`.
Verificate local: semnătura persistentă, toate cele 27 de scripturi GD față de
commit, hash-urile runtime-ului și sursele corespunzătoare. PRoot are 280.376
bytes, loader-ul 17.800 bytes și proba Linux 1.136 bytes. Executabilul PRoot
extras din APK raportează corect versiunea 5.1.107.101; nu are RPATH către
Termux și depinde numai de biblioteci de sistem. Serviciul și receiver-ul sunt
neexportate, iar `extractNativeLibs=true` este prezent în manifestul compilat.

Înlocuit atomic APK-ul anterior din Download la **13:47:04 Europe/Rome**;
rămâne un singur installer al fork-ului. Rapoarte:
`.ai-qa/delivery-644a3b0.json` și
`.ai-qa/artifacts/644a3b0/embedded-verification.json`. Arhiva surselor exacte
este în același director și în artefactul CI `Godot-embedded-runtime-sources-644a3b0…`.
Urmează instalarea APK-ului și deschiderea unui proiect: proba pornește singură,
iar în **Agent → Setări → Jurnal** trebuie verificată linia runtime-ului.
**Pornirea din APK și Blender complet rămân nevalidate.** Nu s-a reinstalat
Blender în Termux și nu s-a modificat containerul Debian existent.

Jurnal: 25.10.2026 — verificat și livrat APK-ul `644a3b0` cu PRoot și proba
Linux automate; înlocuit `5baf890`, păstrând un singur APK în Downloads.

## Etapa precedentă — probă nativă de executare în APK, 25.10.2026

Am început [runtime-ul Blender integrat](docs/AI_EMBEDDED_BLENDER_RUNTIME.md) cu
o probă ARM64 reproductibilă: Gradle construiește un executabil PIE mic cu NDK,
îl ambalează ca bibliotecă nativă extrasă, iar un serviciu Android neexportat,
în procesul separat `:ai_runtime`, încearcă să îl ruleze cu limită de timp.
Puntea internă a agentului expune `embedded_probe` / `embedded_status` pentru
diagnostic. CI verifică ELF-ul ARM64 din APK. Această etapă este o probă de
execuție, **nu** un PRoot sau Blender funcțional și nu schimbă încă butonul
Blender din Integrări. APK-ul din Downloads nu a fost înlocuit în această etapă.

Verificare locală inițială: același cod C a fost compilat cu Clang Android pe
dispozitiv, a rulat și a raportat `arch=aarch64`; ELF este `ET_DYN`/AArch64.
Clasa Kotlin a serviciului a trecut compilarea locală cu Android SDK 36;
cele 28 de teste ale integrării Blender existente au trecut. Gradle local nu
poate rezolva offline pluginul Nexus al proiectului. [CI `40185968028`](https://github.com/JDscript1/godot-ai-android/actions/runs/40185968028)
a trecut toate cele trei joburi. APK-ul compilat (`db550ea`, SHA-256
`4c1763ece3d8b0c9170e17d1bfd76d3641184261bad584c72a4f0457652af07b`)
conține proba ELF AArch64/PIE, serviciul `:ai_runtime` neexportat și
`extractNativeLibs=true`; semnătura coincide cu APK-ul stabil. Binarul extras
din artefact a rulat în Termux pe dispozitiv, dar lansarea din procesul
aplicației Godot **nu este încă testată**. Artefactul verificat este în
`.ai-qa/artifacts/db550ea/`; versiunea stabilă din Downloads a fost păstrată.
Binarul PRoot existent în Termux are `RUNPATH` fix spre
`/data/data/com.termux/files/usr/lib`, căi fixe pentru loader și fișiere
temporare, plus dependențe `libtalloc` și `libandroid-shmem`; trebuie
reconstruit pentru aplicație, nu doar copiat sau repachetat.

## Etapa curentă — comandă scurtă pentru conectarea Termux, 25.10.2026

În proba fizică, comanda veche de conectare nu s-a lipit în Termux. Ea conținea
conectorul codificat, de zeci de mii de caractere. Sursele Android pregătesc
acum o comandă scurtă: aplicația păstrează conectorul și îl oferă o singură dată
prin `127.0.0.1`, cu un URL aleator valabil maximum zece minute. După lipire și
Enter, worker-ul preia operația de instalare fără alte comenzi manuale. La
reinstalare, încearcă mai întâi containerul Debian verificat anterior, evitând
descărcarea unei imagini noi; planul apt este verificat înainte de instalare și
este refuzat dacă ar elimina alte pachete.

**Verificat în surse:** 28 teste Python ale worker-ului/bootstrap-ului au trecut,
inclusiv reinstalarea în containerul anterior și refuzul unui plan ce elimină
alt pachet. Conectorul Kotlin și seiful compilează cu Android SDK 36; logul este
în `.ai-qa/blender-short-bootstrap-kotlin/compile.log`. Simularea apt în
containerul real `debian` ar instala numai pachetul `blender`.

**Compilat și livrat:** [workflow `40177136086`](https://github.com/JDscript1/godot-ai-android/actions/runs/40177136086)
are toate cele trei joburi reușite. APK-ul ARM64 de **145.350.814 bytes**, SHA-256
`8982c87ce00193f70b4847a08431de26180aba0812b5808d1032a667c79d857e`,
are semnătura persistentă și worker-ul Blender identic sursei. Toate cele **27**
scripturi GD incluse corespund commitului compilat; raportul de verificare este
`.ai-qa/artifacts/5baf890/extended-verification.json`. Înlocuirea atomică și
checksum-ul final sunt în `.ai-qa/delivery-5baf890.json`. Transferul local,
lipirea comenzii și instalarea efectivă din APK-ul nou rămân de confirmat pe
dispozitiv. Pachetul Blender complet nu este inclus în memoria privată a
aplicației: Termux nu o poate citi direct și, în varianta Play Store, nu acceptă
pornirea directă de comenzi din Godot. Conectorul din aplicație elimină comanda
lungă; prima lipire scurtă rămâne necesară pentru această variantă Termux.

Jurnal: 25.10.2026 — reprodusă cauza raportată de utilizator (comanda veche nu
s-a lipit), redus transferul inițial la o comandă locală scurtă și adăugată
reutilizarea containerului Debian anterior, cu verificarea planului apt. Compilat
și livrat APK-ul `5baf890`, înlocuind `a23d260` în Download.

## Etapa precedentă — dezinstalare reală Blender pentru testul instalării, 25.10.2026

La cererea utilizatorului, am eliminat **Blender CLI 4.3.2** din containerul
Termux PRoot `debian`, folosind chiar worker-ul inclus în APK-ul livrat
`a23d260`. Înainte de execuție, am verificat că nu existau procese Blender sau
sarcini Blender active și că simularea apt elimina numai pachetul `blender`.
Jobul real de dezinstalare a rulat într-un spațiu de verificare separat, fără a
rescrie istoricul sau configurația utilizatorului.

- Pachetul `blender` (`4.3.2+dfsg-2`) a fost eliminat. Inventarul containerului
  a trecut de la **478 la 477** pachete instalate: niciun alt pachet eliminat,
  adăugat sau actualizat. Nu s-a rulat `autoremove`.
- Detectarea ulterioară prin worker a întors `found: false`. Containerul Debian,
  Termux, dependențele și cele **12 fișiere** din sarcinile Blender ale
  utilizatorului au rămas intacte. Blender nu a fost reinstalat.
- Dovezi: `.ai-qa/blender-real-removal-20261025/report.json`,
  `packages-before.json`, `packages-after.json`, `uninstall-result.json` și
  jurnalul jobului din subdirectorul `worker/jobs/` al aceleiași probe.

Acesta este un test **real al comenzii CLI și al worker-ului**. Apăsarea
butonului în APK pe dispozitiv și instalarea Blender din starea „absent” rămân
de verificat de utilizator. APK-ul din Download nu a fost recompilat sau
înlocuit în această etapă.

Jurnal: 25.10.2026 — eliminat la cerere Blender CLI real prin worker-ul livrat;
inventarul arată exclusiv dispariția pachetului `blender`, iar descoperirea
confirmă starea absentă pentru testul instalării din interfață.

## Etapa precedentă — panou Blender simplificat, 25.10.2026

**Compilat, verificat și livrat în APK-ul `a23d260`.** Cardul Android
are status și un singur buton: **Instalează Termux** → **Instalează Blender** →
**Blender Active**, cu **Dezinstalează Blender** dedesubt. Instalarea Termux
deschide Play Store, cu pagina web a magazinului ca fallback. Eliminate din card
bifa separată de activare, controalele de permisiuni, conectare, verificare,
reparare, recuperare, oprire și consola. Diagnosticul și ieșirea completă Blender
sunt accesibile în **Jurnal**, inclusiv după redeschidere.

- Butonul de instalare salvează operația, caută/reutilizează Blender existent
  sau îl instalează, verifică exportul și importul GLB și activează accesul
  agentului. Repetarea acțiunii cu un runtime deja verificat nu trimite alt job.
  La reluare, jobul existent este recuperat cu același ID; rezultatele ajung în
  proiect și în registrul de fișiere, fără o generare duplicată.
- Pentru Termux Play Store, butonul copiază bootstrap-ul privat și deschide
  terminalul. Rămâne necesară lipirea comenzii și Enter; după revenirea în Godot,
  operația continuă automat. Intenția persistă și dacă editorul este redeschis.
  Verificarea periodică fără o cerere explicită nu instalează pachete.
- Variantele cu RUN_COMMAND folosesc permisiunea Android din aceeași acțiune.
  Dacă serviciul refuză comenzile externe, se trece la aceeași lipire, fără alte
  butoane sau modificarea automată a proprietăților Termux. În timpul operației,
  pornirile duplicate și sarcinile noi ale agentului sunt blocate.
- Dezinstalarea compară identitatea și amprenta executabilului, verifică planul
  apt și elimină numai pachetul `blender` prin dpkg, fără autoremove. Refuză un
  plan care ar elimina alte pachete, instalări nesuportate sau executabile
  schimbate. Nu șterge containere, dependențe, Termux sau fișiere generate.
  Succesul este confirmat numai după dispariția executabilului; readiness și
  accesul agentului sunt apoi eliminate. Și acest job poate fi recuperat.
- Worker-ul anunță revizia 2. Un proces vechi nu primește o cerere de dezinstalare
  nesuportată: același buton oferă comanda nouă și indicația temporară Ctrl+C,
  lipire, Enter, revenire. Actualizarea este refuzată cât procesul vechi are o
  sarcină activă. Nicio sesiune sau sarcină existentă nu este terminată de teste.

Verificări efectuate:

- **427 aserțiuni runtime**, zero eșecuri:
  `.ai-qa/blender-simple-runtime.log`.
- **26 teste backend/bootstrap**, zero eșecuri: eliminare strictă Blender,
  păstrarea fișierelor, refuz la dependențe/amprentă schimbată și idempotenta
  dezinstalării. `.ai-qa/blender-simple-backend.log`. Tranzacțiile de pachete
  au fost simulate în directoare temporare la momentul livrării; testul real
  ulterior este documentat în etapa curentă.
- **67 verificări în editor la scară de telefon și 67 pe desktop**, zero eșecuri: flux manual,
  intenție restaurată, instalare/verificare, activare, dezinstalare, permisiune,
  fallback RUN_COMMAND, conector vechi, Jurnal și indicația de lipire derulată
  complet în zona vizibilă. Capturi inspectate în
  `.ai-qa/blender-simple-ui/phone_compact/`; log în
  `.ai-qa/blender-simple-ui-phone.log`. Regresia desktop este consemnată în
  `.ai-qa/blender-simple-ui-desktop.log`.
- **22 aserțiuni Godot → HTTP → Blender 4.3.2 real**, zero eșecuri, prin noua
  acțiune unică: reutilizare fără instalare de pachete, verificare, exporturi,
  recuperare și anulare. `.ai-qa/blender-simple-connector/report.json`.
  Frontiera Android este substituită; `android_intent_tested=false`.
- Conectorul Kotlin și seiful au compilat cu SDK Android 36:
  `.ai-qa/blender-simple-kotlin.log`. Deschiderea Play Store, clipboard-ul,
  permisiunea și revenirea fizică în APK-ul nou rămân de verificat pe Android.

**Livrare verificată la 25.10.2026, 08:48:52 CET.**
[Workflow `40173817612`](https://github.com/JDscript1/godot-ai-android/actions/runs/40173817612):
toate cele trei job-uri trecute. **422 aserțiuni runtime CI**, **26 teste
backend/bootstrap**, **3 teste livrare**, editor upstream **371 × 5 configurații**,
editor nativ compilat **381 × 5**, plus **67 verificări UI Blender** pentru telefon;
zero eșecuri. Cele cinci probe Blender locale opționale explică diferența față
de cele 427 aserțiuni locale. Log: `.ai-qa/a23d260-ci.log`.

[Artifact `12591950511`](https://github.com/JDscript1/godot-ai-android/actions/runs/40173817612/artifacts/12591950511):
**145.350.402 bytes**, ARM64, pachet `com.jdscript.godotai.debug`;
SHA-256 `b230284b1bf6b07a998e540baebcb36c20cde68a8efe04cf816f808efe5e640f`.
Verificate semnătura persistentă, manifestul, clasele Android/JNI, destinațiile
Play Store și toate cele **27 scripturi GD**, identice cu snapshot-ul compilat.
Bootstrap-ul și worker-ul nou cu dezinstalare/revizia 2 sunt identice cu sursele.
Raport: `.ai-qa/artifacts/a23d260/extended-verification.json`.

Înlocuit atomic APK-ul `cd1acda` și checksum-ul din Download, cu numele stabil
`Godot-AI-Android-arm64-debug.apk`; data modificării a fost actualizată explicit.
Hash-ul copiei finale și checksum-ul au fost reverificate. În Download există
un singur instalator al fork-ului; alte descărcări sunt păstrate.
Raport: `.ai-qa/delivery-a23d260.json`.

Nu s-au apelat furnizori plătiți. La momentul livrării, instalarea/dezinstalarea
reală prin managerul de pachete nu fusese executată asupra mediului
utilizatorului; dezinstalarea reală ulterioară este documentată în etapa curentă.
Fluxul fizic din APK-ul nou rămâne de verificat. Descrierea fluxului și limitele sale:
[`docs/AI_TERMUX_BLENDER.md`](docs/AI_TERMUX_BLENDER.md).

Jurnal: 25.10.2026 — simplificat Blender la status și acțiunea etapei curente;
adăugate continuarea automată, activarea după verificare și dezinstalarea strictă
cu păstrarea mediului și fișierelor. Testat fluxul în editor și cu Blender real;
Compilat și verificat APK-ul `a23d260`, înlocuind instalatorul `cd1acda` din Download.

## Etapa precedentă — validare mesh Blender în editor, 24.10.2026

Jurnalul utilizatorului confirmă conectarea manuală Android → Termux,
descoperirea Blender **4.3.2**, exportul GLB și randarea CPU. Blocajul rămas era
`empty_mesh` în confirmarea Godot. Inspectat fără modificare GLB-ul real al
sarcinii `ed7bb244-bbd4-4047-961b-c54ec502a3f8`: **1.732 bytes**, un cub cu
geometrie, fără extensii Draco. SHA-256:
`26bebf89bbf4dcf598dd5ad1596865837e29c6c56b550e6eeb4f0d0028984b7f`.
Mesajul despre biblioteca Draco nu a împiedicat acest export necomprimat.

Cauza a fost reprodusă cu exact același fișier în Godot 4.7.2: în modul joc
este generat un `MeshInstance3D`, iar în editor un `ImporterMeshInstance3D`.
Validatorul căuta doar primul tip și întorcea incorect zero mesh-uri în editor.
Proba anterioară completă cu Blender rula în modul joc, deci nu acoperea această
diferență. Raport: `.ai-qa/blender-empty-mesh/report.json`, loguri înainte și
după corecție în același director. Copia QA este separată; sarcina reală și
fișierele utilizatorului nu au fost modificate sau confirmate prin `ack`.

- Validatorul parcurge scena, inclusiv rădăcina, și acceptă ambele tipuri de
  instanță numai dacă resursa mesh are suprafețe. Nodurile fără geometrie sunt
  refuzate. Jurnalul arată numărul de mesh-uri validate înainte de confirmare.
- Adăugate **7 verificări în editorul real**, rulate în toate scenariile UI și
  în fork-ul nativ CI: geometrie la rădăcină, resursă goală refuzată, GLB real,
  tipul de nod importat și recuperarea aceleiași sarcini terminate. Proba de
  recuperare apelează codul de producție, salvează readiness și face `ack`,
  fără altă cerere de execuție; numai transportul este fixture în această probă.
- **55 verificări UI desktop și 55 pentru telefon**, zero eșecuri;
  `.ai-qa/blender-editor-mesh-ui/` și logurile dedicate. **427 aserțiuni runtime**
  trecute, `.ai-qa/blender-editor-mesh-runtime.log`. Proba completă cu Blender
  real a trecut din nou **22 aserțiuni**,
  `.ai-qa/blender-editor-mesh-connector/report.json`; frontiera Android rămâne
  substituită în acea suită, conform raportului.

**APK `cd1acda` compilat, verificat și livrat.**
[Workflow `40134515233`](https://github.com/JDscript1/godot-ai-android/actions/runs/40134515233):
toate cele trei job-uri reușite. **422 aserțiuni runtime CI**, **20 teste
backend/bootstrap**, **3 teste livrare**, editor upstream **371 × 5 dimensiuni**,
fork nativ **381 × 5**, plus **55 verificări UI Blender** pentru telefon;
zero eșecuri. Cele cinci probe Blender locale opționale explică diferența față
de cele 427 aserțiuni locale. Log: `.ai-qa/cd1acda-ci.log`.

[Artifact `12575828367`](https://github.com/JDscript1/godot-ai-android/actions/runs/40134515233/artifacts/12575828367):
**145.349.474 bytes**, ARM64, pachet `com.jdscript.godotai.debug`;
SHA-256 `0f571b5f185fbd6b161637a31ff560cc7f48f474cf0eeefb38fc0157a21dce70`.
Verificate local semnătura persistentă, manifestul, clasele Android/JNI,
marcajele native pentru detectare și clipboard, toate cele **27 scripturi GD**
și ambele assets bootstrap/worker, identice cu snapshot-ul compilat.
Raport: `.ai-qa/artifacts/cd1acda/extended-verification.json`.

Înlocuit atomic instalatorul `4236902` și checksum-ul din Download, cu numele
stabil `Godot-AI-Android-arm64-debug.apk`, la **24.10.2026, 23:40:34 CEST**.
Un singur instalator al fork-ului; alte descărcări păstrate. Hash-ul copiei finale
și checksum-ul au fost reverificate. Raport: `.ai-qa/delivery-cd1acda.json`.

După actualizare, sarcina de verificare deja terminată poate fi recuperată din
Integrări → Blender, fără reinstalarea Blender. Dacă procesul auxiliar a expirat,
se pornește din nou prin Termux înainte de recuperare. Validarea din APK-ul
corectat rămâne o probă fizică distinctă; jurnalul utilizatorului confirmă deja
conexiunea manuală și execuția Blender în versiunea precedentă. Nu s-au făcut
apeluri către furnizori plătiți și nu s-au modificat instalarea sau containerele.

Jurnal: 24.10.2026 — reprodus `empty_mesh` cu GLB-ul real al utilizatorului,
corectată validarea nodurilor de import ale editorului și adăugată regresie
pentru recuperarea verificării existente, fără reexecutare Blender. Compilat,
verificat și livrat `cd1acda`, înlocuind atomic APK-ul `4236902` din Download.

## Etapa precedentă — compatibilitate Termux Google Play, 24.10.2026

După jurnalul nou, utilizatorul a confirmat că butonul Permisiune nu deschide
dialog, iar setările aplicației nu afișează permisiunea Termux. Inspectat APK-ul
Termux instalat: **`googleplay.2026.10.09`, versionCode 142**, fără declarația
`com.termux.permission.RUN_COMMAND` și fără `RunCommandService`. Serviciul
Termux intern folosește o permisiune cu protecție de semnătură, care nu poate
fi acordată de utilizator aplicației Godot.
Verificarea anterioară bazată pe `versionCode >= 118` era insuficientă.
Activarea `allow-external-apps` nu adaugă un serviciu absent din această variantă.
Dovadă: `.ai-qa/installed-termux-manifest.txt`; sursa oficială:
[manifest Google Play](https://github.com/termux-play-store/termux-apps/blob/main/termux-app/src/main/AndroidManifest.xml).

- Conectorul inspectează declarațiile de permisiuni, protecția lor, serviciul
  exportat și versiunea înainte să aleagă pornirea directă. Variantele fără
  interfața externă primesc modul de pornire din terminal; nu se cere o
  permisiune nedefinită și nu se încearcă ocolirea permisiunii interne.
- Pentru Google Play, **Pornește în Termux** copiază comanda fixă de conectare,
  marcată privată în clipboard, și deschide Termux. Utilizatorul lipește comanda
  și apasă Enter. La revenire, Godot detectează procesul, caută Blender existent
  și verifică automat exportul/importul. Instalarea Blender rămâne acțiune separată
  numai după constatarea absenței sale. Instalarea Termux existentă este păstrată.
- Același script bootstrap inclus în APK este folosit și de pornirea directă.
  Worker-ul este transferat din assets, conexiunea rămâne pe loopback cu token
  de 256 biți, iar comanda privată nu este returnată modelului sau jurnalelor.
  Python este instalat numai dacă lipsește, la pregătirea explicită a utilizatorului.
- Pentru modul manual verificat și activat, un ping la 60 secunde păstrează
  procesul disponibil cât editorul rulează. După închiderea editorului rămâne
  valabilă expirarea de 10 minute fără activitate. După oprirea procesului de
  Android, utilizatorul pornește din nou conectorul din același panou.

Verificări locale:

- **427 aserțiuni runtime**, zero eșecuri: `.ai-qa/termux-play-runtime.log`.
- **20 teste backend/bootstrap**, zero eșecuri, inclusiv execuția comenzii reale
  prin Bash → Python, worker identic sursei cu mod 0600, health autentificat,
  refuz fără token, lipsă Python fără instalare și token absent din stdout/stderr:
  `.ai-qa/termux-play-bootstrap-unit.log`. Mediul de probă este izolat.
- **22 aserțiuni Godot → HTTP → Blender 4.3.2 real**, cu permisiune Android falsă
  și mod manual: verificare automată după revenire, zero apeluri `start` sau
  `permission`, exporturi, recuperare și anulare;
  `.ai-qa/termux-play-connector/report.json`.
- **48 verificări UI pentru telefon**, zero eșecuri; captură inspectată, butoanele
  de permisiune ascunse și instrucțiuni pentru pornirea din terminal:
  `.ai-qa/termux-play-ui/phone_compact/blender-manual.png`.
- Conectorul Kotlin și seiful au compilat cu SDK Android 36:
  `.ai-qa/termux-play-kotlin.log`. `git diff --check` trecut.

**APK `4236902` compilat, verificat și livrat.**
[Workflow `40106507842`](https://github.com/JDscript1/godot-ai-android/actions/runs/40106507842):
toate cele trei job-uri reușite. **422 aserțiuni runtime CI**, **20 teste
backend/bootstrap**, **3 teste livrare**, editor upstream **364 × 5 dimensiuni**,
fork nativ **374 × 5**, plus **48 verificări UI Blender** pentru telefon;
zero eșecuri. Cele cinci probe Blender locale opționale explică diferența față
de cele 427 aserțiuni locale. Log: `.ai-qa/4236902-ci.log`.

[Artifact `12565041849`](https://github.com/JDscript1/godot-ai-android/actions/runs/40106507842/artifacts/12565041849):
**145.349.474 bytes**, ARM64, pachet `com.jdscript.godotai.debug`;
SHA-256 `2d9a87f555658c21e7d8f4d5a51c69aabf646ae940bbcfe76dd75c030341f6c3`.
Verificate local semnătura persistentă, manifestul, clasele Android/JNI,
marcajele native pentru detectare și clipboard, toate cele **27 scripturi GD**
și ambele assets bootstrap/worker, identice cu snapshot-ul compilat.
Raport: `.ai-qa/artifacts/4236902/extended-verification.json`.

Înlocuit atomic instalatorul `2287ae5` și checksum-ul din Download, cu numele
stabil `Godot-AI-Android-arm64-debug.apk`, la **24.10.2026, 17:27:07 CEST**.
Un singur instalator al fork-ului, alte descărcări păstrate.
Raport: `.ai-qa/delivery-4236902.json`.

Nu sunt validate fizic butonul de clipboard, lansarea activității Termux și
revenirea în APK; clientul de probă substituie frontiera Android și păstrează
`android_intent_tested=false`. Nu s-a înlocuit Termux și nu s-au instalat pachete
sau modificat containerele Blender ale utilizatorului.

Jurnal: 24.10.2026 — identificată cauza reală a dialogului absent în Termux Google
Play, înlocuită verificarea numai după număr cu inspecția capabilităților și
adăugată pornirea explicită din terminal cu verificare Godot automată. Compilat
și livrat APK `4236902`, înlocuind `2287ae5` după verificare; fluxul Android
fizic rămâne de încercat din aplicația instalată.

## Etapa precedentă — jurnal Blender înainte de pornire, 24.10.2026

Utilizatorul a raportat un jurnal gol după răspunsul agentului cu Blender
activat, dar `ready=false`. Reprodusă cauza în surse: jurnalul integrării era
populat numai de o sarcină deja pornită, iar `ensure_ready()` ieșea fără
diagnostic la prima configurare. Evenimentele de setup nu ajungeau în Jurnalul
general și nu erau păstrate după redeschidere.

- Diagnostic pentru detectare Termux, versiune, permisiune, configurare inițială,
  pornire, reconectare și erorile native; mesajul include următoarea acțiune.
- Jurnal persistent, limitat, cu tokenul local și cheile recunoscute redactate.
  Ieșirea unei sarcini nu mai șterge pașii de conectare. Verificările periodice
  cu aceeași stare nu dublează intrările. Evenimentele ajung și în Jurnalul general.
- La conectare eșuată jurnalul se deschide, intră în zona vizibilă și arată
  ultima eroare; există buton de copiere. Actualizările păstrează poziția când
  utilizatorul citește intrări mai vechi.
- Contextul agentului include motivul concret al indisponibilității și cere
  explicație scurtă, fără căutări repetate pentru un tool exclus intenționat.
  Aceasta este o schimbare a instrucțiunilor, nu o probă nouă cu un model real.
- În Termux-ul acestui dispozitiv lipsea `allow-external-apps`; folderul
  worker-ului Android nu exista. Activată proprietatea și reîncărcate setările,
  cu cod de ieșire 0. Copia configurației anterioare este
  `.ai-qa/termux.properties-before-blender-20261024-164144`. Nu s-au instalat
  pachete sau schimbat containerele Blender existente.

Verificări locale: **423 aserțiuni runtime, zero eșecuri**, inclusiv 11 probe
noi pentru diagnostice timpurii, permisiuni, pornire respinsă, persistență,
redactare și deduplicarea jurnalelor; `.ai-qa/blender-diagnostics-runtime.log`.
Proba Godot → HTTP → Blender real a trecut din nou **21 aserțiuni**;
`.ai-qa/blender-diagnostics-connector/report.json`, cu
`android_intent_tested=false`. Proba UI a trecut **45 verificări desktop** și
**46 pentru telefon**, cu aserțiune suplimentară pentru ultima linie împărțită;
capturile de eroare au fost inspectate. Dovezi:
`.ai-qa/blender-diagnostics-ui-delivery/`. Scenariul telefonului este adăugat
în CI pentru a verifica permanent jurnalul și vizibilitatea erorii.

Snapshot compilat: `2287ae59bb048b3832907c493305477280e80192`.
[Workflow `40103875046`](https://github.com/JDscript1/godot-ai-android/actions/runs/40103875046):
**toate cele trei job-uri trecute**. CI: **418 aserțiuni runtime**, **18 teste
backend**, **3 teste livrare**, editor upstream **364 verificări × 5 dimensiuni**,
fork nativ **374 × 5**, plus **46 verificări** ale panoului Blender pentru telefon.
Zero eșecuri. Log: `.ai-qa/2287ae5-ci.log`. Cele cinci probe Blender locale
opționale explică diferența dintre cele 418 aserțiuni CI și 423 locale.
**APK `2287ae5` verificat și livrat** din
[artifact `12563079376`](https://github.com/JDscript1/godot-ai-android/actions/runs/40103875046/artifacts/12563079376).
Pachet `com.jdscript.godotai.debug`, ARM64, **145.348.880 bytes**;
SHA-256 `e9d6121fa803ffd8b440739770a171ff6a48f5d7b6941f99c0ec8ea721a1c003`.
Verificate semnătura persistentă, manifestul și clasele Termux/JNI, worker-ul
și toate cele **27 scripturi GD**, identice cu snapshot-ul compilat.
Rapoarte: `.ai-qa/artifacts/2287ae5/extended-verification.json` și
`.ai-qa/delivery-2287ae5.json`.

Înlocuit atomic instalatorul `45ea380` la
`/storage/emulated/0/Download/Godot-AI-Android-arm64-debug.apk`, împreună cu
checksum-ul. Timestamp **24.10.2026, 17:00:26 CEST**; un singur APK al fork-ului
în Download. O conexiune întreruptă la descărcarea artifactului a fost recuperată
pe ultimul fragment; verificările ZIP, SHA-256 și semnătură au trecut înaintea
înlocuirii. Alte descărcări nu au fost modificate.
Activarea proprietății Termux nu confirmă permisiunea Android acordată aplicației
sau executarea efectivă prin Intent; acestea necesită verificare din APK.
Nu există dispozitiv conectat prin ADB; noul APK nu a fost instalat sau pornit
fizic de agent. Nu s-au efectuat probe noi cu un furnizor AI real la această etapă.

Jurnal: 24.10.2026 — reprodus jurnalul gol înainte de prima conectare, adăugate
diagnostice persistente și corectată afișarea erorilor; activată proprietatea
Termux necesară conectorului, cu configurația anterioară păstrată. Compilat și
livrat APK `2287ae5`, înlocuind `45ea380` după verificare; validarea fizică a
conexiunii din aplicație rămâne separată.

## Etapa precedentă — APK compilat și livrat, 24.10.2026

**Livrat `45ea380`**, cu toate modificările AI acumulate după `36457dd`:
comportament, conectare locală, bara de activitate, control 3D, reguli pentru
imagini și integrarea Blender/Termux. Compilarea și înlocuirea au fost autorizate
explicit. S-a folosit workflow-ul existent al proiectului; compilarea locală a
întregului motor rămâne incompletă.

- [Workflow `40101377645`](https://github.com/JDscript1/godot-ai-android/actions/runs/40101377645):
  **toate cele trei job-uri reușite**. Runtime: **407 aserțiuni**, plus **18 teste
  backend Blender** și **3 teste livrare**; editor upstream: **364 verificări ×
  5 configurații**; fork nativ: **374 verificări × 5 configurații**. Zero eșecuri.
  Diferența față de cele 412 aserțiuni locale provine din cele cinci probe
  opționale ale Blender-ului local, absente pe runner. Log: `.ai-qa/45ea380-ci.log`.
- [Artifact ARM64 `12562872989`](https://github.com/JDscript1/godot-ai-android/actions/runs/40101377645/artifacts/12562872989):
  **145.332.496 bytes**, pachet `com.jdscript.godotai.debug`.
  SHA-256: `aeb303acc30c1fa22a0c3d78378d738fed33c240965c3139640b6415223c13bb`.
- Verificate local: SHA-256 identic artifactului, semnătură persistentă, ABI și
  ELF AArch64, toate cele **27 scripturi GD** identice cu snapshot-ul compilat,
  clasele Android, permisiunea și receiver-ul Termux, intrarea JNI și worker-ul
  Blender identic sursei. Raport:
  `.ai-qa/artifacts/45ea380/extended-verification.json`.
- Certificat SHA-256 păstrat pentru actualizarea aplicației existente:
  `2e0a80969c099f7ff72bfe0c0cd33d98ebdd0e64bbf9729294df0b11665fcab5`.
- Înlocuit atomic `/storage/emulated/0/Download/Godot-AI-Android-arm64-debug.apk`
  și checksum-ul aferent; timestamp **24.10.2026, 16:17:30 CEST**. În Download
  rămâne un singur instalator al fork-ului; alte descărcări nu au fost modificate.
  Raport: `.ai-qa/delivery-45ea380.json`.

**Limite:** nu există dispozitiv conectat prin ADB în această sesiune. APK-ul
nu a fost instalat sau pornit fizic de agent. Frontiera Android `RUN_COMMAND`,
dialogurile de permisiuni, un Termux gol și un Debian nou necesită probe din
aplicația instalată. Compilarea și verificarea conținutului nu le substituie.
Nu s-au efectuat probe noi cu furnizori plătiți la această livrare.

Jurnal: 24.10.2026 — compilat și verificat APK `45ea380`, toate job-urile CI
trecute, înlocuit instalatorul `36457dd` din Download cu semnătura păstrată și
checksum nou; documentația de livrare actualizată. Validarea fizică rămâne separată.

## Etapa precedentă — configurare Blender și conector Termux, 24.10.2026

**Implementat în surse; APK-ul livrat rămâne `36457dd`.** Card Blender pe
Android în Integrări: detectare Termux, instalare prin distribuția oficială,
permisiune Android, activare ghidată a comenzilor externe, conectare, instalare
Blender, verificare, recuperare, reparare și jurnal extensibil. Activarea pentru
agent este salvată separat pentru fiecare proiect, independent de GitHub.

- Conector Kotlin/JNI dedicat, `RUN_COMMAND` cu țintă explicită și callback
  neexportat, identificat prin nonce. Procesul auxiliar Python este inclus în
  assets; conexiunea rămâne pe loopback și folosește un token din seiful Android.
- Reutilizare a instalării existente, inclusiv Debian PRoot în structura nouă
  și veche. Instalarea nouă folosește PRoot-Distro 5.x și Debian 13 ARM64 într-un
  mediu propriu. Nu există upgrade general, migrare automată sau reset al
  mediilor utilizatorului. Repararea imaginii incomplete a aplicației cere un
  buton explicit; instalarea se poate opri după tranzacția curentă.
- `blender_run` pe Android, expus numai după verificare și activare. Fișierele de
  intrare sunt declarate explicit; scripturile folosesc `GODOT_AI_PROJECT_DIR`
  și `GODOT_AI_OUTPUT_DIR`. Transfer prin streaming, hash-uri, validare a
  modelelor/imaginilor/dependențelor și refuz al căilor externe sau simbolice.
- Rezultate importate într-un folder numit după script și ID, fără suprascrieri,
  apoi disponibile în chat. Sursa BLEND primește `importer="keep"`; GLB-ul
  furnizează scena și preview-ul, fără pornirea importerului desktop pe Android.
- O singură sarcină simultană, două fire Blender, timeout, anularea proceselor
  proprii, checkpoint și recuperare fără reexecutarea ID-ului. După importul
  confirmat se eliberează copiile temporare; metadatele rămân pentru deduplicare.
  Reconectarea unei instalări verificate nu reinstalează pachete. Modificarea
  executabilului invalidează capacitățile; procesul auxiliar expiră după repaus.
- Testele backend sunt incluse în workflow. Corectată și izolarea XDG a suitei
  generale în PRoot, care anterior putea refolosi cache-ul unei probe vechi.

Verificări locale încheiate:

| Nivel | Rezultat și dovezi |
| --- | --- |
| Backend, HTTP și instalator | **18 teste trecute**: validare, token, origini web, upload, hash, un singur proces, anulare, tranzacții, imagini incomplete și reparare explicită, protejarea mediilor existente, curățare, proces real și lock unic; `.ai-qa/blender-worker-unit.log`. Instalatorul nou este verificat aici prin comenzi simulate, nu prin instalarea unui Debian nou. |
| Godot → HTTP → Blender existent | **21 aserțiuni trecute** cu Blender **4.3.2** real: detectare/reutilizare, probă GLB și import Godot, randare CPU, transfer script/dependență Python, exporturi GLB, glTF + BIN, FBX și BLEND, recuperare după pierderea transferului și anulare. `.ai-qa/blender-connector-final/report.json`, `jobs.json`, `godot.log` și logurile sarcinilor. |
| Runtime general | **412 aserțiuni, 0 erori**; `.ai-qa/blender-runtime-final.log`. Serviciile cloud rămân fixtures locale în această suită. |
| Panou Blender redat | **41 verificări × 5 dimensiuni**, fără erori; `.ai-qa/blender-ui-final/`. Capturi desktop și telefon inspectate vizual. Frontiera Android este substituită pentru aceste stări UI. |
| Regresie editor desktop | **364 verificări, 0 erori**; `.ai-qa/blender-regression/desktop/editor-report.json`. |
| Surse native | Kotlin compilat cu SDK Android 36 și obiectul C++ compilat pentru Android ARM64; `.ai-qa/blender-kotlin.log`, `.ai-qa/blender-cpp-build.log`. Manifestul și includerea sursei worker în assets verificate separat. |
| Livrare | Cele **3 teste de livrare** trecute; nu s-a creat sau înlocuit vreun APK în această etapă. |

**Limite:** raportul probei reale păstrează `android_intent_tested=false`.
Nu au fost testate pornirea din APK prin `RUN_COMMAND`, instalarea pe Termux gol,
dialogurile Android de permisiuni, instalarea reală a unui mediu Debian nou sau
comportamentul producătorului la oprirea proceselor în fundal. Acestea necesită
un APK nou și probe fizice; compilarea obiectelor native nu le substituie.
Nu s-au rulat scripturile utilizatorului și nu s-au modificat modelele existente.

Documentație: [`docs/AI_TERMUX_BLENDER.md`](docs/AI_TERMUX_BLENDER.md).

Jurnal: 24.10.2026 — implementat setup Blender în Integrări, conectorul opțional
Android–Termux și transferul sarcinilor; exporturi reale GLB/glTF/FBX/BLEND,
randare CPU, recuperare și anulare verificate prin clientul Godot, cu frontiera
Intent substituită. Validarea din APK și instalarea pe un Termux gol rămân separate.

## Etapa precedentă — verificarea Blender existent în Termux, 24.10.2026

**Runtime verificat local; conectorul dintre APK și Termux nu este încă
implementat.** Blender **4.3.2** este instalat în containerul Debian PRoot,
la `/usr/bin/blender`. Containerul folosește structura actuală
`$PREFIX/var/lib/proot-distro/containers/debian/rootfs/`; căutarea anterioară
în PATH-ul Termux și în vechea structură `installed-rootfs/` a fost incompletă.

- Confirmată versiunea prin `proot-distro login debian -- /usr/bin/blender --version`.
- Rulată o probă separată în fundal cu pornire curată și script Python propriu:
  creat un cub cu material, salvate fișiere `.blend` și `.glb` într-un director QA
  unic. Nu au fost rulate scripturile care scriu peste modelele utilizatorului.
- Godot 4.7.2 a încărcat GLB-ul prin `GLTFDocument`, într-un proces headless:
  **1 mesh / 12 triunghiuri**, rezultat reușit. Blender a raportat 8 vârfuri
  și 6 fețe înainte de triangularea exportului. Hash-urile fișierelor sunt în raport.
- Adaptarea aplicației poate reutiliza acest runtime existent: lansator PRoot,
  transfer și mapare de fișiere, sarcini cu loguri și rezultate și import în Godot.
  Harness-ul nativ rămâne independent; Termux ar fi un backend opțional pentru unelte.

Dovezi: `.ai-qa/termux-blender-311jvngq/report.json`, `blender.log`, `godot.log`,
`probe.blend` și `probe.glb`; indexul ultimei probe este
`.ai-qa/termux-blender-probe-latest.json`. Aceste dovezi confirmă execuția prin
CLI în mediul local și importul headless, nu lansarea din aplicația Android.
Nu s-au instalat pachete, nu s-au modificat modelele existente și nu s-a
recompilat sau înlocuit APK-ul.

Jurnal: 24.10.2026 — găsit și verificat Blender 4.3.2 existent în Debian PRoot;
export GLB și import Godot reușite într-o probă izolată. Conectorul APK–Termux
rămâne de implementat.

## Etapa precedentă — control 3D și reguli pentru imagini, 24.10.2026

**Implementat în surse; APK-ul livrat rămâne `36457dd`.** Lucrul asupra rotirii
vizează previzualizarea GLB/glTF din chat și Generare; transformările mesh-ului
din scena proiectului nu se modifică. În Generare a fost găsit un viewport
static fără controale de rotire și a fost înlocuit cu viewer-ul comun.

- Previzualizarea are un strat GUI dedicat de navigare peste viewport, cu
  orbitare orizontală/verticală, zoom și deplasare cu două degete, roată mouse,
  săgeți din tastatură și Home pentru reset. Patru butoane compacte oferă
  rotire stânga/dreapta/sus/jos. Sensibilitatea ține cont de scalarea editorului;
  pierderea focusului și ascunderea ferestrei eliberează gesturile active.
- `asset_generate` și instrucțiunile agentului separă explicit referința pentru
  reconstrucție 3D, sprite-ul 2D, textura repetabilă, decorul și imaginea generică.
  Referințele 3D și sprite-urile cer implicit transparență; textura și decorul
  păstrează suprafețe opace. Alegerea explicită a utilizatorului are prioritate.
  Opțiunile sunt disponibile și în generarea manuală, numai pentru imagini.
- Se păstrează promptul original și separat cererea completată cu reguli.
  La descărcare se verifică alfa efectiv și conținutul vizibil: un PNG opac sau
  complet transparent nu este etichetat drept cutout utilizabil. Imaginea se
  păstrează, cu avertisment și starea vizuală „Necesită verificare”.
- Conversia 3D recitește referințele generate recunoscute și blochează trimiterea
  unui rezultat care nu respectă fundalul cerut. Fișierele utilizatorului nu
  primesc automat cerința de cutout. Verificarea alfa nu certifică încadrarea,
  perspectiva, identitatea obiectului sau calitatea segmentării.
- Tool nativ `asset_remove_background`, prin Runware RemBG: procesează imaginea
  existentă, păstrează originalul și salvează separat PNG-ul decupat. Are cost la
  furnizor, autorizare, checkpoint anterior POST-ului, UUID stabil, deduplicare
  în harness-ul principal și verificarea alfa la final. Nu regenerează imaginea
  și nu inventează parametri de transparență pentru furnizori incompatibili.
- Viewer-ul arată un fundal în carouri pentru imaginile cu alfa real, fără a-l
  scrie în imagine sau în export. Zona desenată este încadrată în canvas;
  previzualizarea imaginilor din Generare folosește același canvas.

**Verificări runtime finale:** **413 aserțiuni, zero eșecuri**, cu server HTTP local.
Proba include PNG opac păstrat și marcat necorespunzător, conversie 3D blocată
înainte de POST, eliminare de fundal pe aceeași imagine, alfa real verificat,
original păstrat după hash, reluare fără POST nou și conversie cu referința
corectată. Nu s-au folosit chei reale sau servicii plătite.

**Verificări în editor:** **363 verificări la fiecare dintre cele cinci
configurații**, fără eșecuri. Proba dedicată preview-ului a fost repetată pe
desktop: **60 verificări, zero eșecuri**. Sunt verificate gesturile touch/mouse,
zoom-ul cu două degete, resetarea, eliberarea focusului, butoanele de rotire,
preview-ul interactiv din Generare și păstrarea alfa în exportul imaginii.
Au fost inspectate capturile desktop, înguste și cu scalare pentru telefon.

Testul anterior al rotirii apela `_orbit()` direct; noile probe trimit input
prin fereastra reală și verifică transformarea camerei. Gestul touch a trecut
și în proba Linux a viewer-ului din chat dinaintea schimbării. Preview-ul separat
din Generare nu avea însă tratarea gesturilor; noua probă verifică rotirea pe
ambele axe prin fereastra reală a setărilor. În controlul randării au fost depistate și corectate
marginile temei care împingeau în afara ferestrei ultimul buton de rotire.

Detalii și limite: [Control 3D și reguli pentru imagini](docs/AI_ASSET_RULES.md).
Dovezi: `.ai-qa/mesh-input-before/`, `.ai-qa/mesh-input-after/`,
`.ai-qa/mesh-image-contract-runtime-final.log`, `.ai-qa/mesh-preview-capture/` și
`.ai-qa/mesh-image-contract-verified/`. Validarea touch pe Android fizic și
rezultatele serviciilor reale rămân distincte de aceste probe. APK-ul nu a fost
recompilat, iar installerul din Download nu a fost înlocuit.

Jurnal: 24.10.2026 — adăugate controalele explicite ale preview-ului 3D,
contracte separate pentru utilizarea imaginilor, verificarea alfa și eliminarea
fundalului existent prin Runware; 413 aserțiuni runtime și 363 verificări în
editor pentru fiecare dintre cele cinci dimensiuni trecute fără servicii
plătite. Modificări în surse.

## Etapa precedentă — bara de activitate deasupra mesajului, 24.10.2026

**Implementat în surse; APK-ul din Download rămâne `36457dd`.** Bara de status
este fixată imediat deasupra câmpului de mesaj, în afara istoricului derulabil.
Apăsarea ei deschide un sertar cu pașii planului, sarcinile secundare existente
și operațiile harness-ului nativ. Forma compactă arată activitatea curentă și
progresul real, de exemplu `2/5`.

- Stări distincte pentru finalizat, în lucru, de făcut, blocat, eșuat și
  întrerupt. Oprirea păstrează pașii rămași; refuzul unei permisiuni nu apare
  ca succes. După finalizare, lista rămâne disponibilă pentru consultare.
- Detaliile au derulare proprie și înălțime limitată; câmpul de mesaj rămâne
  accesibil. Sunt păstrate toate etapele și ultimele 24 de operații, cu numărul
  total indicat. Textele lungi se încadrează în lățimea disponibilă.
- Progresul se actualizează din evenimente, fără interogări suplimentare către
  furnizor. O cerere nouă curăță activitatea precedentă și ignoră notificările
  sarcinilor vechi. Ultimul plan și rezultatele se refac din conversația salvată,
  fără a executa tool-uri la încărcare.
- Indicator discret de lucru, preferința pentru mișcare redusă, focus din
  tastatură și widget-uri native pentru apăsare/derulare. Controlul capturilor
  a identificat etichete de stare comprimate; ele păstrează acum lățimea necesară.

**Verificări:** suita completă a editorului a trecut **353 verificări la fiecare
dintre cele cinci dimensiuni**, fără eșecuri, înaintea ajustării finale a
etichetelor de stare. După ajustare, scenariul dedicat a trecut **40 verificări
la fiecare dintre cele cinci dimensiuni**, fără eșecuri; au fost inspectate
capturile desktop, înguste și cu scalare pentru telefon. Suita completă desktop
a fost repetată pe sursele finale: **354 verificări, zero eșecuri**. Testele runtime au
trecut **398 aserțiuni, zero eșecuri**
în rularea izolată. O rulare concurentă cu randările a depășit termenul scurt
al probei de streaming; nu s-a modificat transportul sau pragul testului.
Rezultatele ajustării finale și capturile sunt detaliate în
[Bara de activitate](docs/AI_ACTIVITY_DRAWER.md).

Dovezi: `.ai-qa/activity-drawer-final/`, `.ai-qa/activity-drawer-verified/`,
`.ai-qa/activity-drawer-release-check/`,
`.ai-qa/activity-drawer-runtime-isolated.log` și
`.ai-qa/activity-drawer-runtime-final.log`. Probele folosesc editorul Linux ARM64
prin proot/Xvfb și fixturi locale. Nu s-au făcut apeluri API plătite, compilări
APK sau probe touch pe Android fizic în această etapă.

Jurnal: 24.10.2026 — mutată bara de activitate deasupra mesajului, adăugat
sertarul pentru pași/sarcini/operații, progres parțial și refacere din istoric;
verificate randările la cinci dimensiuni. Installerul nu a fost înlocuit.

## Etapa precedentă — probe reale DeepSeek și contractul tool-urilor, 23.10.2026

**Implementat și testat în surse; APK-ul din Download rămâne `36457dd`.**
Utilizatorul a ales explicit cheia din configurația locală DeepSeek și modelul
`deepseek-v4-flash`. Catalogul real oferă acum `deepseek-flash`; identificatorul
ales este acceptat ca alias pentru modelul Flash actual, conform documentației
furnizorului. Nu a fost folosită cheia din spațiul privat al APK-ului.

- Adăugat evaluatorul opțional `modules/ai_assistant/tests/evaluate.py`, separat
  de CI. Rulează panoul și contextul aplicației, harness-ul, API-ul real și
  tool-urile editorului într-un proiect temporar, cu setări izolate. Driverul
  și criteriile sunt în afara `res://`, inaccesibile tool-urilor de fișiere.
- Zece scenarii: identitate, citire, patch și recitire, depanare GDScript, scenă
  în Auto, propunere în Plan, refuz de permisiune, curățare, fișier lipsă și
  căutare Terrain3D în Asset Store. Hash-urile verifică păstrarea celorlalte
  fișiere; scena este verificată în editor și în conținutul salvat.
- Reprodus un defect real: setarea unui mesh cu Dictionary în loc de Object
  putea lăsa mesh-ul gol și raporta succes; apelul generic `set_mesh` putea
  raporta succes după o eroare de conversie Godot. Tool-urile returnează acum
  referințe explicite `{"$handle":"obj_..."}`, verifică referințele, tipurile
  și clasele Resource înainte de mutație și recitesc proprietatea după setare.
  Metadatele păstrează clasele și argumentele reflectate, inclusiv în JSON.
- Reprodusă o diferență între sfârșitul buclei și finalizarea sarcinii: un plan
  declarat blocat era etichetat `completed`. Hook-ul `blocked_reason` păstrează
  acum statusul `blocked` în harness, checkpoint și chat; reluarea rămâne
  disponibilă. Regresia este verificată automat cu un furnizor determinist.
- Jurnalul are acum ID-uri de apel, argumente, durate, execuție/reutilizare,
  coduri de eroare, cereri/răspunsuri, încercări și usage. Sunt înregistrate și
  apelurile blocate înainte de operație. Rapoartele API salvează jurnalul real
  al panoului și traseul evenimentelor; nu includ cheia sau raționamentul intern.
- Instrucțiunile cer folosirea căilor exacte `res://`, referințelor returnate
  de tool-uri și rezultate finale compacte, cu verificări și blocaje concrete.

**Rezultate live:** runda completă a încheiat **10 scenarii / 57 cereri reale**;
nouă au îndeplinit integral criteriile. Depanarea a reparat corect codul, dar
bridge-ul nativ indisponibil în editorul upstream a produs un plan blocat,
etichetat greșit ca finalizat. După corecții, **editarea, depanarea și scena au
fost repetate: 3/3 reușite, 26 cereri**, aproximativ 11,1 / 27,1 / 24,4 secunde.
Ultimul rezultat al fiecăruia dintre cele zece scenarii este reușit pe parcursul
acestor runde; aceasta nu este o singură rundă finală 10/10 sau un benchmark
statistic. În repetarea de scenă a existat BoxMesh real, transformarea cerută,
fișier salvat corect și plan finalizat. Căutarea publică Terrain3D a funcționat;
nu a fost cerută sau efectuată instalarea.

**Verificări finale ale surselor:** **398 aserțiuni runtime**, zero eșecuri,
și **340 verificări în editorul desktop**, zero eșecuri. Hash-urile celor 27 de
surse runtime din ultima probă live corespundeau surselor acestei etape; artefactele
evaluării au fost verificate pentru absența cheii API. Nu s-au modificat
proiectele utilizatorului și nu s-au trimis generări plătite.

**Limite:** probe Linux ARM64 prin proot/Xvfb, fără compilarea unui APK nou sau
test fizic Android. Diagnosticul structurat al bridge-ului nativ nu există în
acest editor upstream; scriptul reparat a trecut separat parserul GDScript.
Lipsa bridge-ului în evaluator nu dovedește lipsa lui din APK. Modelul încă
poate face apeluri redundante sau încerca o operație înaintea planului, pe care
host-ul o respinge; un singur model/nivel implicit nu validează toți furnizorii.
Jurnalul istoric al APK-ului este privat și nu a putut fi citit fără export;
nu există dispozitiv conectat prin ADB. S-a cerut utilizatorului textul jurnalului
pentru analiza încercărilor sale. Nu s-a integrat un harness extern.

Raport: [Evaluarea agentului cu API real](docs/AI_API_EVALUATION.md).
Dovezi: `.ai-qa/deepseek-api-review/REPORT.md`,
`.ai-qa/deepseek-api-review/report.json`, `.ai-qa/deepseek-api-verified/`,
`.ai-qa/deepseek-api-corrections/`, `.ai-qa/api-behavior-runtime-settled.log`
și `.ai-qa/api-behavior-editor-settled/`. Rulările inițiale de diagnostic și
runda întreruptă sunt identificate separat în raport.

Jurnal: 23.10.2026 — evaluate zece sarcini cu DeepSeek real, corectate rezultate
false de succes pentru mesh/apeluri reflectate și planuri blocate, completată
telemetria tool-urilor; trei scenarii repetate cu succes. Surse testate;
installerul din Download nu a fost înlocuit.

## Etapa precedentă — comportament și conectare locală simplificată, 23.10.2026

**Implementat și testat în surse, după APK-ul `36457dd`; această etapă nu a fost
compilată sau înlocuită în Download.** Raportul detaliat este în
[Evaluarea comportamentului agentului](docs/AI_BEHAVIOR_TESTS.md).

- Harness-ul recunoaște aceeași generare sau creare de issue GitHub după
  nume/argumente în același turn, chiar dacă modelul schimbă ID-ul apelului.
  Refolosește rezultatul și la reluare. O variantă suplimentară explicită are
  argumentul `variant`; o cerere nouă a utilizatorului rămâne distinctă.
- Refuzul unei permisiuni este păstrat pentru operația respectivă în acel turn.
  Cerințele remediabile, precum publicarea unui plan înaintea unei modificări,
  nu blochează definitiv operația. După trei continuări fără progres sau aceeași
  operație repetată fără progres, execuția se oprește și închide batch-ul rămas.
- Un mesaj nou în timpul lucrului oprește cererea depășită și pornește mesajul
  nou după încheierea operației curente. Stop explicit păstrează coada oprită.
  Reluarea folosește cererea și planul inițial, rezultatele confirmate și ID-ul
  turnului; nu adaugă mesaj artificial și nu șterge ciorna. Sarcinile încheiate
  nu pot fi executate încă o dată prin butonul de reluare.
- Sarcina de generare este salvată înainte de POST. Un răspuns pierdut sau o
  întrerupere înainte de confirmare păstrează starea „Trimitere neconfirmată”,
  inclusiv UUID-ul Runware. Fără ID de la furnizor nu se trimite automat din nou;
  stocarea indisponibilă împiedică trimiterea. Stop local nu anulează implicit
  o sarcină deja primită de furnizor.
- Chatul afișează planul în lucru compact, cu pasul activ și extindere la apăsare.
  Statusurile operațiilor au texte pentru utilizator. Reasoning-ul implicit
  este etichetat „Implicit”, separat de modul de lucru Auto/Default/Plan.
- LM Studio, Ollama și llama.cpp au conectare prin IP simplu sau URL complet.
  Butonul **Conectează** salvează, verifică serverul și selectează un model
  încărcat, unde este raportat. IP-ul simplu primește portul serviciului și `/v1`.
  Tokenul este opțional și vizibil direct; opțiunile avansate nu sunt necesare.
  Un URL HTTP explicit păstrează portul indicat sau portul standard 80.
- Catalogul LM Studio este completat cu metadatele modelelor; embeddings nu
  apar în chat, iar contextul folosește capacitatea efectiv încărcată. Ollama
  folosește `/api/tags` și `/api/ps`. Metadatele suplimentare sunt opționale.
  Conectarea, primul răspuns, inactivitatea streamului și durata totală au
  termene distincte; răspunsul lent nu este confundat cu serverul inaccesibil.
  Un timeout de inferență nu declanșează automat încă o cerere către model.

**Verificări automate:** patru probleme au fost reproduse înaintea corecțiilor.
Același set a trecut ulterior. Suita finală a încheiat **396 aserțiuni runtime**,
zero eșecuri, și **329 verificări randate × 5 configurații**, zero eșecuri.
Configurații: desktop, îngust, lat, telefon landscape și compact. Inspectate
vizual planul compact, bara chatului și formularul conectării locale pe desktop
și în configurația compactă. Serverele acestor teste sunt fixturi deterministe;
nu reprezintă inferență cu un model real sau test fizic Android.

**LM Studio live:** după identificarea IPv4-ului adaptorului Wi-Fi activ, accesul
a funcționat între dispozitivele conectate la hotspotul unui telefon. Adaptorul
nativ Godot a trecut **10 citiri consecutive** ale catalogului, între **95 și
368 ms**, mediană **164 ms**. A detectat `prism-ml/bonsai-27b` încărcat, context
activ **4.096 tokeni**, și a exclus modelul de embeddings. După repornirea Wi-Fi,
adresa a răspuns din nou în **0,24 secunde**. Acest rezultat confirmă conectarea
în timpul probelor; IP-ul se poate schimba la reconectarea la hotspot.

**Limite și probe rămase:** prima inferență a modelului mare nu s-a încheiat în
timpul probei, iar clientul nostru de test a fost oprit. O cerere scurtă separată
a expirat după 25 de secunde. Nu avem un benchmark finalizat al calității sau
tool use-ului acelui model. Ollama nu a răspuns pe portul 11434 al calculatorului;
proba sa live rămâne de efectuat când serverul este pornit și accesibil.
Nu s-au modificat serverul, modelul încărcat sau firewall-ul. Nu s-au folosit
chei plătite pentru generare. Compilarea noilor surse și testul fizic în APK
rămân separate de aceste rezultate.

Dovezi: `.ai-qa/behavior-before.log`, `.ai-qa/behavior-harness.log`,
`.ai-qa/local-connections-runtime.log`, `.ai-qa/local-connections-render-final/`,
`.ai-qa/live-lmstudio-connection.json`, `.ai-qa/lmstudio-after-wifi-restart.json`
și `.ai-qa/lmstudio-plain-chat.json`. Nu s-a adăugat niciun runtime extern;
Deep Agents rămâne un candidat pentru comparație, nu o integrare implementată.

Jurnal: 23.10.2026 — corectate reluarea, repetarea generărilor și schimbarea
cererii active; simplificată conectarea LM Studio/Ollama, separați timpii de
conectare și inferență; verificate sursele, cinci configurații randate și
10 conexiuni native consecutive la LM Studio. APK-ul livrat rămâne `36457dd`.

## Etapa precedentă — Store, rețea locală și generare, 23.10.2026

Implementat în surse, compilat și livrat în APK-ul **`36457dd`**:

- Integrarea GitHub a fost simplificată la token personal: câmp vizibil, salvare
  în vault, verificare cont/repository, alegere repository și deconectare.
  Fluxul OAuth/Device Flow și Client ID-ul au fost scoase din aplicație.
- `store_search` citește structura reală `hits` din API-ul nou și returnează
  `publisher/slug`; `store_describe` folosește această identitate și rutele
  publice corecte. Terrain3D a apărut în răspunsul live al căutării. Instalarea
  permite GDExtension numai când manifestul indică un binar Android ARM64 din
  arhivă, cu antet ELF AArch64 verificat. Arhiva oficială Terrain3D v1.0.2 a
  trecut verificarea ZIP și s-a instalat în proiectul editorului de test, cu
  29 verificări randate fără eșecuri. Activarea rămâne separată; aceasta nu
  dovedește că pluginul se încarcă pe telefon.
- Selectorul tuturor serviciilor Cloud/Local rămâne vizibil și la editarea unui
  profil. Adresa API/LAN este vizibilă pentru profilurile locale. Descoperirea
  probează întâi adresele Wi-Fi private, înaintea celor VPN/mobile, și are
  fallback de enumerare; mesajul explică activarea „Serve on Local Network” din LM Studio
  și introducerea manuală a URL-ului. Rețeaua utilizatorului nu a fost probată.
- Generare folosește o cheie comună per furnizor cloud pentru profilurile de
  imagini și 3D, cu credențiale ComfyUI separate. Butonul de test face ping
  autentificat Runware fără generare, apoi afișează catalogul. Configurarea are
  folder principal și format 3D preferat; comenzile manuale sunt într-un sertar.
  PNG/GLB se importă automat într-un folder propriu, numit după prompt și ID;
  exporturile finalizate se păstrează lângă original cu nume corespunzător.
  Scanarea incrementală a fișierelor evită suprapunerea importurilor editorului.
  Conversiile la furnizor nu pornesc doar prin alegerea formatului.
- Skills și Sarcini au pagini principale separate imediat sub Integrări. Baza
  rămâne Godot **4.7.2-stable**, identică cu ultima ediție oficială Android
  verificată; versiunea APK precedent era deja `4.7.2.stable`. Eșecul Store
  provenea din adaptor, nu din eticheta versiunii.

Verificări locale finale: **357 aserțiuni runtime**, zero eșecuri, cu arhiva oficială
Terrain3D furnizată testului; fixturile acoperă API-ul Store, GDExtension ELF
ARM64, cheia Runware, prioritatea Wi-Fi, importul și exportul în foldere.
Instalarea arhivei reale a trecut **29 verificări** într-un proiect temporar.
Randarea editorului a trecut **321 verificări × 5 configurații**, zero eșecuri;
capturile Furnizori, Generare, Skills, dockul îngust și GitHub cu token au fost inspectate.
CI a trecut integral: **350 aserțiuni runtime**, **321 verificări × 5** upstream
și **331 verificări × 5** în editorul nativ. Salvarea/deconectarea tokenului și
respingerea credențialelor lipsă sau invalide sunt acoperite de fixturi.
Dovezi: `.ai-qa/terrain-generation-runtime-final.log`,
`.ai-qa/terrain-real-install/`, `.ai-qa/terrain-generation-all-final/`,
`.ai-qa/token-only-render-final/` și `.ai-qa/36457dd-ci.log`.
APK-ul nou a înlocuit versiunea precedentă în Download la **18:00:16 CEST**.
Serviciile live cu cheile utilizatorului,
încărcarea Terrain3D pe Android fizic și rețeaua Wi-Fi a utilizatorului rămân
probe separate.

Jurnal: 23.10.2026 — corectat Store, păstrat selectorul Cloud/Local la vedere,
clarificată conexiunea LM Studio, organizată generarea per obiect/furnizor și
simplificat GitHub la token personal; compilat, verificat și livrat `36457dd`.

## Livrare Store, generare și token GitHub — 23.10.2026, 18:00 CEST

- Sursă **`36457dd4569ac787ad5888599e6ba2c1c573e095`**; [workflow-ul
  `39947703170`](https://github.com/JDscript1/godot-ai-android/actions/runs/39947703170)
  a trecut integral: runtime, native-editor și Android.
- APK **145.206.577 bytes**, `com.jdscript.godotai.debug`, numai ARM64.
  Certificatul persistent, checksum-ul și cele **26 de scripturi încorporate**
  au fost verificate înainte de livrare.
- SHA-256: `cda966c83f61dd836bd518b3f8b14a5b46eab2dd1e297a0e5fc4cd42b5b49616`.
- Înlocuit atomic `/storage/emulated/0/Download/Godot-AI-Android-arm64-debug.apk`
  și fișierul `.sha256` alăturat. În Download rămâne un singur APK al fork-ului;
  celelalte descărcări au fost păstrate. Nu s-a instalat automat pachetul.
- Dovezi: `.ai-qa/delivery-36457dd.json`, `.ai-qa/36457dd-artifact/`,
  `.ai-qa/36457dd-ci.log` și `.ai-qa/token-only-render-final/`.
- Tokenul GitHub real, furnizorii plătiți, conexiunea Wi-Fi între dispozitive și
  încărcarea Terrain3D pe Android fizic rămân de verificat separat.

## Etapa curentă — rafinare vizuală, livrată 23.10.2026

Implementată în surse și inclusă în APK-ul **`978a6d3`**:

- Bara de chat are câmpul de mesaj, atașarea, microfonul și Trimitere pe primul
  rând; modelul, reasoning-ul unde încape, modul Auto/Default/Plan și contextul
  sunt pe al doilea. În dockul foarte îngust, indiciul devine „Mesaj…”, iar
  butoanele nu se întind pe înălțimea textului. Nivelul de reasoning rămâne
  accesibil prin sertarul modelului și apare în tooltip când nu încape separat.
- Activitatea este un control compact; acțiunea Modificări apare numai când
  există modificări. Codul din răspunsuri se poate încadra în dockul îngust.
- În Furnizori, sigla nu se dublează, iar serviciul unui profil existent se
  schimbă din Opțiuni avansate; la profil nou selectorul rămâne la vedere.
  Meniurile furnizorilor folosesc aceeași paletă cu restul agentului.
- În Setări, acțiunile primare sunt evidențiate, ștergerea/deconectarea au
  culoare distinctă, controalele sunt mai compacte, iar subfilele Integrări
  folosesc paleta agentului. Cardul GitHub arată întâi starea și conectarea;
  Skills afișează descrierea, păstrând identificatorul în detalii.
- La Generare, rezultatul selectabil este înaintea formatelor de export;
  lista goală se ascunde, iar tipul și starea au etichete lizibile.

Verificări locale: **340 aserțiuni runtime**, fără eșecuri; **319 verificări × 5
configurații randate** (desktop, narrow, wide, phone_landscape, phone_compact),
fără eșecuri. Capturile pentru furnizori, Integrări, chat și dockul stâng/îngust
au fost inspectate în `.ai-qa/premium-ui-final-all/`. În CI, cele trei joburi
au trecut, iar editorul nativ compilat a trecut **329 verificări × 5 configurații**;
capturile sale compacte pentru chat, dockul îngust, Furnizori și Integrări au fost
inspectate. APK-ul a fost verificat și livrat. Atingerea și tastatura pe un
dispozitiv Android real rămân de validat separat.

Jurnal: 23.10.2026 — compactat chatul, îndreptat dockul foarte îngust,
unificate meniurile și ierarhia acțiunilor, simplificate Furnizori, Integrări,
Skills și rezultatele de generare; verificare randată în cinci configurații.

## Etapa anterioară — exporturi 3D, GitHub și LAN, 23.10.2026

Implementate și incluse în APK-ul `13456af`, care înlocuiește `2538551`:

- GLB original păstrat pentru preview/import; export glTF în ZIP cu dependențe,
  OBJ/STL/PLY native pentru geometrie statică și conversii FBX/USDZ/3MF prin
  Meshy/Tripo, plus BLEND prin Meshy. Formatele native nu includ materiale,
  rig sau animații; nu pretindem suport pentru toate formatele la fiecare API.
- Selector și buton de export pe rezultatul selectat, destinație aleasă de
  utilizator, fără suprascriere. Tool `asset_export` disponibil agentului.
  Cache după hash pentru exporturi locale; task ID persistent și reluare pentru
  conversii. Răspunsul pierdut la POST blochează retrimiterea plătită oarbă și
  permite recuperare după ID-ul sarcinii existente.
- Istoric, înlocuit ulterior: GitHub **Sign in**, Device Flow nativ, cod public/copiere/browser, validarea
  contului înainte de salvarea tokenului, selectare repository cu paginare și
  fallback manual. Client ID public comun editorului; repo/activare per proiect.
  Tokenurile rămân în vault, fără Client Secret sau credențiale externe împrumutate.
- **Istoric, nu mai este necesar:** nu avem o aplicație OAuth proprie înregistrată.
  Interfața explică înregistrarea și Device Flow; login real nu este încă validat.
- Separatoare vizuale Cloud / Local-self-hosted în serviciile/profilurile din
  Furnizori, selecție după ID stabil și clasificare unitară în sertarul din chat.
  Adresele LAN sunt recunoscute; domeniile proprii pot declara explicit găzduirea.
- Căutare LAN nativă pornită explicit, limitată la două segmente IPv4 private și
  porturile 11434/1234/8080, apoi verificare `/v1/models`, fără trimiterea cheilor.
  Alegerea rezultatului doar completează formularul; salvarea este explicită.
  IP/port/adresă HTTPS pot fi introduse manual, inclusiv când scanarea nu ajunge.
- Documentație: [generare/export](docs/AI_GENERATION.md),
  [autentificare/integrări](docs/AI_INTEGRATIONS.md),
  [conectare Wi-Fi](docs/AI_ASSISTANT.md#local-servers-over-wi-fi),
  [lista de priorități](docs/AI_ROADMAP.md).

Verificări locale: **340 aserțiuni**, fără eșecuri, prin Godot ARM64 în proot.
Acestea includ geometrie reală în OBJ/STL/PLY, glTF cu dependențe, original
nemodificat, conversii HTTP simulate FBX/USDZ/3MF/BLEND, cache/reluare/recuperare,
fără chei pe CDN, OAuth pending/slowdown/refuz/anulare/expirare și endpoint LAN
local izolat. Nu s-a scanat rețeaua utilizatorului. Verificarea randată a trecut: **314 verificări × 5 configurații**, fără eșecuri.
Capturile desktop, înguste și compacte au fost inspectate. Ultima extindere verifică
și exportul deschis chiar din fereastra modală Setări, cu dialog copil corect.
CI a trecut integral: **335 aserțiuni runtime**, **314 verificări × 5** upstream
și **324 verificări × 5** în editorul nativ, fără eșecuri. Capturile native compacte
pentru Furnizori, Integrări, export și dock stânga au fost inspectate.
Dovezi locale: `.ai-qa/new-integrations-unit-final.log`,
`.ai-qa/new-integrations-final-render/`, `.ai-qa/new-integrations-nested/`,
`.ai-qa/13456af-native-ci/`, `.ai-qa/13456af-runtime-ci.log`,
`.ai-qa/13456af-native-ci.log` și `.ai-qa/delivery-13456af.json`.
APK-ul nou a fost livrat în Download după verificarea locală; detalii la final.

Jurnal: 23.10.2026 — extinse exporturile 3D, pregătit GitHub Sign in și selectarea
repository-ului, separate găzduirile și adăugată căutarea LAN. Serviciile live și
validarea fizică Android rămân probe distincte.

## Implementări existente

### Integrarea în editor și interfața

- Tab principal **AI Assistant**, imediat după Asset Store; acces și din
  setările generale ale editorului.
- Interfață nativă de chat, temă graphite cu accente violet/albastru și gradient;
  coloană de lectură limitată, mesaje ale utilizatorului aliniate la dreapta.
- Istoric adaptiv, conversații noi, căutare, favorite, arhivare, redenumire,
  ramificare și export Markdown.
- Streaming cu actualizarea acelorași blocuri, cod evidențiat și copiere,
  activități grupate și detalii expandabile.
- Composer adaptiv, imagini și referințe la proiect, comenzi `/`, coadă de
  mesaje, Stop, Resume și Steer.
- Selectorul de model este în partea de jos, lângă câmpul de mesaj. Antetul
  afișează titlul conversației și acțiunile pentru istoric, conversație nouă,
  extindere și setări.
- Sertar nativ în interiorul chatului: **furnizor → modelele acelui profil →
  reasoning**. API cloud, abonamentele și modelele locale sunt grupate separat.
  Căutarea filtrează furnizorii sau modelele furnizorului ales.
- Alegerea devine activă numai după selectarea reasoning-ului. Înapoi permite
  corectarea alegerii; închiderea, apăsarea în exterior și Escape păstrează
  selecția anterioară. Butonul separat de reasoning deschide direct nivelurile
  modelului curent. Sunt oferite numai nivelurile declarate în catalog și Auto;
  un catalog fără niveluri configurabile oferă numai Auto.
- Pe lățimi mari, selectorul și reasoning-ul sunt pe rândul acțiunilor; pe
  lățimi mici au un rând propriu. Numele lungi sunt prescurtate vizual, cu
  detalii complete în tooltip. Listele sertarului se derulează separat.
- Controale compacte în composer: înălțime de 32 unități, iconuri de 16 unități,
  text de 12 unități și margini reduse. Selectorul ocupă lățimea textului, până
  la 150 unități; reasoning-ul până la 104. Valorile se adaptează scalei editorului.
- **76 SVG-uri preluate din surse upstream**: logo-uri de furnizori din Lobe
  Icons, logo llama.cpp din repository-ul ggml-org și acțiuni Lucide. Acestea
  înlocuiesc aproximările desenate anterior. Sunt încorporate local, fără acces
  la internet la afișare. Sursele, reviziile fixe, hash-urile și licențele sunt în
  `modules/ai_assistant/icons/`; cache-ul folosește scala editorului.
- La fiecare livrare se păstrează un singur installer al acestui fork în
  Download, cu numele stabil `Godot-AI-Android-arm64-debug.apk` și checksum-ul
  asociat. Installerul nou se verifică înainte de înlocuire; celelalte aplicații
  și fișiere ale utilizatorului nu sunt șterse. Regula este în `AGENTS.md`, iar
  livrarea verificată este automatizată în `misc/scripts/deliver_ai_android.py`.
- Setări pentru control, furnizori, abonamente, generare, MCP, Integrări,
  Jurnal, AGENT.MD, voce și testarea jocului. Navigarea se adaptează ferestrelor
  înguste. Există preferință pentru reducerea animațiilor.

### Furnizori, conturi și date

- Adaptoare HTTP proprii pentru Chat Completions compatibil, Responses,
  Anthropic și Gemini; catalog de profile inclusiv DeepSeek, OpenRouter,
  Ollama, LM Studio și llama.cpp.
- Detectarea cheilor distinctive; cheile ambigue cer alegerea furnizorului.
  Listarea modelelor este separată de verificarea efectivă a tool calling.
- Păstrarea contextului la schimbarea furnizorului și a blocurilor specifice
  doar pentru profilul/modelul de origine.
- Flux ChatGPT SIWC implementat nativ; Claude, Copilot și Kimi au integrări
  opționale prin companion. Autentificările reale se verifică separat.
- Android Keystore pentru credențiale; date publice separate de secrete,
  redactarea credențialelor din context și jurnale.
- Conversații, memorii, jurnale, copii de recuperare și artefacte separate per
  proiect. Scripturile agentului sunt interne editorului, nu addon copiat în joc.

### Harness propriu, în surse

- Nucleu `runtime/harness.gd`, folosit de chat și de subagenții cu furnizori
  direcți; rulează în Godot fără Termux, consolă sau SDK extern de agent.
- Buclă model → unelte → rezultate → model, streaming, anulare, limite de pași,
  retry limitat pentru cereri temporar eșuate și stări finale distincte.
- Registru de unelte permise, verificarea identificatorilor de apel și
  reutilizarea rezultatului unui apel deja înregistrat, fără repetarea operației.
- Salvarea progresului înainte de execuție și după rezultate; o eroare de
  salvare oprește operațiile următoare. Apelurile întrerupte sunt închise explicit
  în istoric, fără reluarea automată a unor modificări neconfirmate.
- Trei moduri vizibile: **Auto / Default / Plan**. Default este inițial pentru
  configurații noi; selecțiile vechi Plan sunt migrate fără a permite scrierea.
  Auto cere un plan scurt înaintea modificărilor/operațiilor externe, verificat
  și de dispatcher. Default permite lucrul direct pentru sarcini simple și
  planifică după complexitate. Plan rămâne doar pentru citire, indiferent de YOLO.
- YOLO este implicit oprit și controlează confirmările în Auto și Default.
  `task_update` publică pași și faze; planning și propunerile blochează scrierile,
  iar faza executing permite modificări. Ambele moduri de execuție continuă
  planurile neîncheiate în limitele harness-ului. Stop păstrează progresul.
- Planul se afișează într-un card pliabil din conversație, cu un singur pas în
  lucru, stări distincte și restaurare din istoric. Un plan propus complet oferă
  **Implementează planul** (trece în Auto și păstrează preferința YOLO) și
  **Ajustează** (redeschide Plan cu pașii propuși în composer).
- Textul conversației are titluri, liste, citate, cod inline, tabele și linkuri
  HTTP(S) validate, fără interpretarea HTML/BBCode din răspunsuri. Blocurile de
  cod și identitatea furnizorului au o prezentare compactă.

### Unelte și integrarea jocului

- Baza anterioară etapei curente: **43 unelte definite** — 31 pentru editor,
  4 pentru generare, 5 pentru sarcini/subagenți și 3 pentru Playtest.
- Citire/scriere/căutare fișiere, scene, noduri, semnale, scripturi, proprietăți,
  resurse, setări, animații, controale ale editorului și Output/Debugger.
- Descoperirea metodelor/proprietăților/semnalelor și apeluri prin handle-uri.
  Operațiile C++ private sau neexpuse necesită adaptoare dedicate.
- Explore și General returnează constatări/propuneri; părintele aplică scrierile.
  Limitele existente sunt doi copii pentru cloud și unul pentru local/companion.
- Playtest are capturi din joc, inspectarea stării și input limitat prin puntea
  debugger, plus eliberarea inputului și watchdog.
- MCP Streamable HTTP: inițializare, sesiuni, catalog paginat și apeluri.
  Serverele stdio arbitrare rămân găzduite separat.

### Generare, voce și automatizări

- Profile Runware, ComfyUI, Meshy, Tripo și OpenAI Images, joburi persistente, polling, descărcare și validare
  PNG/GLB, previzualizare și import fără suprascrierea fișierelor existente.
- Catalog public Runware verificat; acesta nu dovedește generare cu credite.
- Integrare de voce Android și endpoint compatibil Whisper. Verificarea completă
  a microfonului și a serviciilor instalate rămâne necesară pe dispozitiv.
- Automatizările sunt instrucțiuni salvate, lansate manual; nu există încă
  scheduler autonom sau serviciu permanent de fundal.

## Etapa încheiată la 22.10.2026: tool use și composer

Implementat în surse și inclus în APK-ul `588bef1`:

1. **`tool_search` și `tool_describe`**: registru separat per rulare, set inițial
   redus, căutare cu relevanță/paginare și încărcarea schemelor la cerere pentru
   următoarea cerere către model. Catalogul respectă permisiunile sesiunii.
2. **Validare comună a argumentelor**: obiecte și liste imbricate, câmpuri
   obligatorii, tipuri, limite, enum, pattern și referințe locale. Numerele
   fracționare nu sunt acceptate ca întregi. Schemele nesuportate sunt raportate
   explicit; acesta este un subset JSON Schema, nu implementarea întregului standard.
3. **`godot_apply_patch`**: înlocuiri exacte, hash de versiune, previzualizare
   implicită, refuzul contextului ambiguu sau al unui script deschis cu modificări
   nesalvate, copie de recuperare și înlocuire prin fișier temporar verificat.
4. **`godot_script_diagnostics`**: punte C++ către parserul/analyzer-ul GDScript,
   cu validitate, erori, avertismente, poziții și hash. Poate analiza un draft
   fără a-l salva. Codul C++ a trecut verificarea de sintaxă și tipuri; execuția
   punții necesită editorul nativ recompilat și nu este dovedită de testul upstream.
5. **`godot_read_range` și `godot_search_code`**: citire și căutare limitate, cu
   fișier, linie și coloană. Citirea returnează și hash-ul pentru pregătirea patch-urilor.
6. **Rezultate MCP normalizate**: text, date structurate, verificarea schemelor
   de rezultat suportate și `isError` propagat ca eșec. PNG/JPEG/WebP sunt trimise
   ca atașamente ale modelului; datele base64 nu umplu contextul text. Conținutul
   nesuportat, precum audio, este raportat explicit.
7. **Scanări de fișiere secvențiate**: schimbările apropiate folosesc cereri
   grupate de rescanare. Testul de editor salvează corect bufferul modificat
   intenționat înainte de ieșire.

Catalogul are acum **49 tipuri de unelte definite**: 35 pentru editor, 4 pentru
generare, 5 pentru sarcini/subagenți, 3 pentru Playtest și 2 pentru descoperire.
Uneltele MCP descoperite se adaugă dinamic; nu toate cele 49 sunt expuse simultan
în fiecare rol sau mod. Sursele curente încorporează **19 scripturi**, inclusiv
datele SVG pentru iconuri.

## Etapa control și Integrări — inclusă în APK `db5343b`

- Indicator separat de context în bara de jos: inel, procent și detalii la hover.
  Folosește consumul/capacitatea cunoscută a modelului ales; lipsa limitei arată
  „—”, fără procent inventat. Se resetează între modele și conversații.
- General conține YOLO, poziția chatului și sunetele. Preferințele se salvează
  imediat. Limitele tehnice și activarea asistentului au dispărut din interfață.
  Meniul Auto/Default/Plan nu mai conține permisiuni, context sau extindere duplicată.
- Poziție Centru / Stânga / Dreapta prin `EditorDock`; se mută același panel,
  cu aceeași conversație. Mutarea este refuzată în timpul lucrului sau dictării.
  Extinderea de sus mută temporar dock-ul în centru și îl restaurează la
  restrângere, fără schimbarea preferinței salvate.
- Sunet scurt original, sintetizat în PCM, cu volum moderat și previzualizare;
  opțiunea este implicit oprită. Nu sună pentru eșec, anulare sau plan neterminat.
- Integrări are Conexiuni, Skills și Sarcini. GitHub oferă citire repository,
  branches, issues, PR-uri și fișiere, plus creare issue la cererea utilizatorului.
  Tokenul rămâne în vault; repository-ul și activarea sunt salvate per proiect.
- Blender CLI este numai pentru Windows/Linux: executabil configurabil, test de
  versiune, script Python din proiect, fundal fără shell, ieșire limitată,
  anulare/timeout și coduri reale de eroare. Nu este instalat în APK/Android.
  MCP și generarea au pagini proprii; scurtăturile duplicate din Integrări au
  fost eliminate și sunt absente în APK-ul curent.
- Skills sunt fișiere `res://.godot_ai/skills/<id>/SKILL.md`, cu manager de creare,
  editare, activare/dezactivare și ștergere cu recuperare. Agentul are
  `skill_list`, `skill_read`, `skill_save`; actualizările verifică hash-ul,
  iar Plan/confirmările sunt respectate. Instrucțiunile nu se execută automat.
- AGENT.MD editează `res://AGENT.md`, inclus în context, cu migrare la salvare din
  memoria privată veche, reîncărcare și protecție împotriva suprascrierii unui
  fișier modificat între timp. `AGENTS.md` existent rămâne separat și păstrat.
- Jurnalul este consolă cronologică pentru cereri, unelte, rezultate și finalizare,
  cu filtru, Live și copiere. Datele sunt redactate; afișarea este limitată pentru
  a menține editorul responsiv.

Catalogul maxim ajunge la **55 tipuri de unelte** pe desktop (54 pe Android),
prin cele 3 unelte de skills și integrările opționale GitHub/Blender. Nu toate
sunt expuse simultan. Există 19 scripturi și 61 SVG-uri upstream în surse.

Verificări deja încheiate: 187 aserțiuni funcționale, fără erori, incluzând Blender
real 4.3.2 în Debian ARM64: script → GLB → import în Godot, erori Python, anulare
și timeout. Adaptorul nativ GitHub a citit efectiv repository-ul public
`godotengine/godot` fără autentificare; crearea issue a fost testată doar cu server
simulat, fără publicare reală. C++ a trecut verificarea de sintaxă și tipuri.
Regresia finală a trecut **172 verificări în fiecare dintre cinci configurații**
(desktop, narrow, wide, phone_landscape, phone_compact), fără erori și cu ieșire
normală. Capturile finale pentru General, Integrări, Skills, AGENT.MD, consola
de jurnal, context și dock-uri au fost inspectate vizual. Încorporarea celor
**19 scripturi** și hash-urile celor **61 SVG-uri** au fost verificate.

Prima iterație a fost păstrată numai în surse. Ulterior, APK-ul `db5343b` include
această etapă: puntea C++ a fost compilată și executată în editorul nativ
(188 verificări × 5 configurații, fără erori). Windows, Android fizic și
sunetul pe hardware rămân de validat.
Dovezi: `.ai-qa/control-settings-runtime-complete.log`,
`.ai-qa/control-settings-complete/`, `.ai-qa/github-read-live.json` și
`.ai-qa/control-settings-verification.json`.

## Etapa Auto/Plan și lizibilitate — livrată în APK `9a019f6`

Selectorul de model este redus la maximum 150 unități logice, reasoning la 104.
Auto planifică intern când modelul consideră necesar, apoi continuă execuția;
această fază internă nu schimbă selecția utilizatorului în modul Plan. Plan este
alegerea explicită pentru inspectare și propuneri. Nu există clasificator local
care să garanteze dificultatea sau calitatea deciziilor unui furnizor real.

Au trecut **167 verificări funcționale**, zero erori, și **3 teste de livrare**.
Regresia de editor a trecut **142 verificări în fiecare dintre cinci configurații**,
fără erori și cu ieșire normală. Au fost inspectate capturile de chat formatat,
plan și opțiuni Auto/Plan. Verificarea C++ și încorporarea celor 17 surse au trecut.
Editorul nativ recompilat a trecut **152 × 5 verificări**, fără erori. Cele trei
joburi ale [workflow-ului `39740297032`](https://github.com/JDscript1/godot-ai-android/actions/runs/39740297032) au reușit.
APK-ul `9a019f6` a fost verificat și livrat; toate cele 17 surse corespund byte
cu byte bibliotecii ARM64. Companionul a trecut 9 teste și build-ul TypeScript
local și în CI, cu runtimes simulate. Dovezi: `.ai-qa/auto-plan-final/`,
`.ai-qa/auto-plan-native-ci/.ai-qa/native-rendered/`,
`.ai-qa/auto-plan-verification.json` și `.ai-qa/delivery-9a019f6.json`.

## Dovezi de verificare

| Etapă | Dovezi | Limite |
| --- | --- | --- |
| APK `6539a44` — fișiere, preview și control vizual | [Workflow `39823384697`](https://github.com/JDscript1/godot-ai-android/actions/runs/39823384697) reușit; 295 aserțiuni locale / 290 CI, 233 × 5 verificări upstream și 243 × 5 native; 25 scripturi comparate exact cu APK-ul, 76 SVG-uri | Livrat atomic; modele/servicii simulate, testarea fizică Android și Store public rămân separate |
| APK `db5343b` — moduri, Integrări și generare (istoric) | [Workflow `39772723053`](https://github.com/JDscript1/godot-ai-android/actions/runs/39772723053) reușit; 237 aserțiuni locale / 232 în CI, 178 × 5 verificări upstream și 188 × 5 native, trei teste livrare, nouă teste companion + build; 19 scripturi comparate exact cu biblioteca APK, 65 SVG-uri | Livrat atomic în Download; fără teste fizice Android sau generare plătită reală |
| APK `9a019f6` — Auto/Plan și lizibilitate (istoric) | [Workflow `39740297032`](https://github.com/JDscript1/godot-ai-android/actions/runs/39740297032) reușit: 167 aserțiuni, 142 × 5 verificări upstream, 152 × 5 verificări native, 3 teste de livrare, 9 teste companion + build, C++ și 17 surse încorporate verificate | Livrat atomic în Download; fără teste fizice Android sau furnizori reali |
| APK `12794c4` (istoric) | [Workflow `39733876322`](https://github.com/JDscript1/godot-ai-android/actions/runs/39733876322): android, runtime și native-editor reușite; semnătură, pachet, ARM64 și hash verificate local; **15 surse comparate byte cu byte cu biblioteca din APK** | Teste fizice Android și servicii live neefectuate de agent; nume stabil în Download |
| APK `588bef1` (istoric) | Workflow `39725331751`: joburile android, runtime și native-editor încheiate cu succes; semnătură, pachet, ARM64 și SHA-256 verificate; cele 14 scripturi au trecut verificarea de încorporare byte cu byte | Fără teste fizice Android sau servicii live; semnătura de dezvoltare persistentă păstrată |
| APK `e98ddb7` (istoric) | Workflow `39707618934`; semnătură, pachet, ARM64 și surse încorporate verificate | Înlocuit la 22.10.2026 de APK-ul `588bef1` |
| Interfață și punte nativă anterioare | Rapoarte documentate în `docs/AI_ASSISTANT.md` | Randarea desktop nu dovedește comportamentul fizic Android |
| Harness propriu, prima etapă | 122 verificări funcționale, zero erori; 80 verificări în editor în fiecare dintre cinci configurații, zero erori; 13 surse încorporate verificate byte cu byte | Godot upstream ARM64, fixture izolat |
| Extinderi tool use | **149 verificări funcționale**, zero erori; **91 verificări în editor în fiecare dintre cinci configurații**, zero erori; 14 scripturi verificate byte cu byte | Puntea nativă a fost compilată și executată în jobul native-editor al workflow-ului `39725331751` (**139 verificări × 5**, zero erori) |
| Selector și sertare în composer | **149 verificări funcționale**, zero erori; **129 verificări în fiecare dintre cinci configurații de editor**, zero erori; 14 scripturi verificate byte cu byte | Randare cu Godot upstream ARM64 și date de probă; APK-ul include codul, dar testarea fizică rămâne separată |
| Controale compacte și artwork upstream | **150 verificări funcționale** și **132 × 5 verificări în editor**, fără erori; 15 surse încorporate verificate byte cu byte; 57 SVG-uri verificate față de hash-urile upstream | APK `12794c4` compilat și livrat; editorul nativ al fork-ului a trecut **142 × 5 verificări**, fără erori |

Rapoartele extinderilor tool use sunt în `.ai-qa/tool-use-final/`, pentru `desktop`,
`narrow`, `wide`, `phone_landscape` și `phone_compact`. Manifestul local
`.ai-qa/tool-use-verification.json` înregistrează hash-urile surselor, verificarea
C++ și limitele validării. Randarea telefonului landscape a fost inspectată vizual.

Jobul `native-editor` al workflow-ului `39725331751` a compilat editorul desktop
al fork-ului și a executat fixture-ul în cele cinci configurații: **139 de
verificări în fiecare**, zero erori și ieșire normală. Acesta este primul
rezultat care include execuția reală a punții `script_diagnostics`: script salvat
valid cu hash, draft invalid cu diagnosticare structurată și verificarea că
draftul nu este salvat. Execuția pe Android fizic rămâne separat de validat.

Rapoartele finale ale selectorului sunt în `.ai-qa/composer-drawer-complete/`,
pentru aceleași cinci configurații. Fiecare include `editor-report.json`,
`editor.log`, `composer-selector.png` și capturi `drawer-providers.png`,
`drawer-models.png`, `drawer-reasoning.png`. Au fost inspectate vizual chatul,
setările, lista de modele și sertarele, inclusiv configurațiile la 150%.
Manifestul `.ai-qa/composer-drawer-verification.json` înregistrează sursele și
dovezile finale; `.ai-qa/composer-drawer-runtime.log` păstrează regresia funcțională.
Testele verifică separarea listelor între furnizori, selecția aplicată după
reasoning, anularea, Înapoi/Escape, păstrarea selecției mesajelor în coadă,
iconurile și limitele geometrice ale sertarului/composerului. Dimensiunile
folosesc fontul și scalarea efective pentru a evita derularea inutilă la liste
scurte. Iterațiile inițiale cu erori de dimensionare nu sunt numărate în aceste
rezultate finale; toate cele cinci procese finale au ieșit normal.

În timpul dezvoltării, primul test de editor a căzut în timpul scanării fișierelor;
un test ulterior a trecut aserțiunile, dar nu a ieșit normal. Au fost corectate
secvențierea scanărilor și salvarea bufferului modificat de fixture. Aceste
încercări nu sunt numărate ca teste trecute. Regresia finală de mai sus a ieșit
normal în toate cele cinci configurații. Avertismente ale mediului virtual
Proot/X11 pot apărea în loguri; acestea nu constituie validare fizică Android.

Ultimul installer:
`/storage/emulated/0/Download/Godot-AI-Android-arm64-debug.apk`
(145.141.041 bytes, pachet `com.jdscript.godotai.debug`, numai `arm64-v8a`).
Fișierul `.sha256` este lângă APK. Versiunea `db5343b` a fost înlocuită atomic
la aceeași cale stabilă, după verificarea noii versiuni; în Download rămâne un
singur APK al fork-ului.

SHA-256:
`0cc48766d215068d5e914a7a65f56f5377c1ef7eb146ff3aa1451f0dadeae6ba`.

Certificatul de dezvoltare a rămas neschimbat:
`2e0a80969c099f7ff72bfe0c0cd33d98ebdd0e64bbf9729294df0b11665fcab5`.

## Ce rămâne de făcut sau de validat

- Teste fizice Android: swipe/preview/capturi, tastatură, atingere, rotație, suspendare/revenire,
  Keystore și microfon.
- Teste cu modele reale pentru coding și mai multe apeluri de unelte succesive;
  catalogul sau compatibilitatea API nu garantează calitatea modelului.
- Fluxuri reale de autentificare prin abonamente și tratarea reautentificării.
- Generare reală prompt → imagine/GLB → validare → import în Godot.
- Playtest condus efectiv de model, cu dovezi dintr-un joc real.
- Căutare în documentația API, unelte specializate suplimentare pentru scene,
  Git nativ printr-o bibliotecă integrată și integrări externe opționale.
- Compactare automată după bugetul de context, evaluări de fiabilitate și
  automatizări programate. Acestea nu sunt funcții finalizate.
- Catalog Store public și addon public real: verificarea locală a catalogului a primit HTTP 403; instalarea/activarea/dezinstalarea sunt probate cu un addon fixture în fork-ul nativ.
- MediaStore/URI SAF persistente, MediaProjection Android și preview pentru OBJ/FBX/.blend nu sunt implementate. GLB/glTF și accesul filesystem deja autorizat sunt disponibile.
- Inferența locală în interiorul APK-ului nu este implementată; profilele locale
  folosesc endpointuri de modele deja pornite.

## Jurnalul etapelor

- **30.10.2026:** AG-66 în surse: reparații cu dovezi, impact, recuperare, scenarii, experimente, asseturi, profilare și specialiști. Fără APK/push; verificări și limite în secțiunea AG-66.

- **29.10.2026:** AG-58, identificat pe telefon blocajul real al Ziva: biblioteci absente în Debian slim. Corecție de dependențe și DNS în surse, teste portabile 11/0; verificare pe dispozitiv în curs.

- **29.10.2026:** AG-57 livrat: tab principal Ziva în editor și manager; APK separat `234893bf`, runtime 751/0, upstream 768/0 × 5 și nativ 792/0 × 5; 37 de surse exacte. Instalatorul standard și checksum-ul lui sunt păstrate.

- **29.10.2026:** sincronizat istoricul validat AG-53–AG-55 și raportul final de livrare pe ramura GitHub principală `ai/android-assistant`; sursele aplicației coincid cu APK-ul `090b939`. Fără modificări ale APK-ului sau instalare automată.

- **28.10.2026:** recompilat și livrat `090b939` cu AG-53–AG-55; runtime 749/0, upstream 744/0 × 5, nativ 772/0 × 5 și 35 de surse exacte. Semnătura și Linux verificate; APK și checksum înlocuite atomic în Download, fără instalare automată.

- **28.10.2026:** AG-55 în surse: închiderea testelor temporare, cache de capturi cu retenție și pin, tastatură și revenire la finalul chatului. Runtime 749/0, regresie editor 744/0, probe finale 68/0 × 2; probele focalizate și randările sunt în `.ai-qa/chat-lifecycle-20261028/`. Fără recompilare APK.

- **28.10.2026:** livrat `47cc26e` cu AG-34–AG-52; runtime 703/0, upstream
  716/0 × 5, editor nativ 732/0 × 5 și 34 de surse exacte. APK-ul și checksum-ul
  au înlocuit atomic versiunea 1c7c777 din Download; instalarea rămâne manuală.

- **28.10.2026:** AG-49–AG-52 în surse: loturi dependente cu hash-uri, diff-uri
  pentru aprobare, rollback compensatoriu, recuperare după întrerupere simulată
  și invalidarea dovezilor inclusiv după aplicare eșuată. Probe finale: runtime
  703/0, editor narrow 716/0, phone_compact 60/0. Fără APK nou.

- **28.10.2026:** AG-35–AG-38 în surse: Plan la capătul conversației,
  denumiri specifice generatoarelor, zoom 3D nativ și prin butoane, glisare
  tactilă pe suprafețele conversației. Regresie narrow 649/0, preview 79/0,
  navigare phone_compact 115/0 și Plan interactiv final 67/0; fără generări
  plătite sau APK nou.
- **28.10.2026:** AG-34 corectat în surse: Running Tools apare numai pentru
  unelte active și dispare la rezultat, Stop sau finalizare. Proba dedicată
  phone_compact: 94/0; regresie completă narrow: 641/0. APK-ul din Download
  nu a fost schimbat.
- **28.10.2026:** recompilat și livrat **1c7c777**, cu AG-21–AG-33; 537 aserțiuni
  runtime, 641 × 5 verificări upstream și 654 × 5 native trecute. APK ARM64 de
  112.345.138 bytes, semnătura, cele 30 de scripturi și Linux verificate;
  instalatorul și checksum-ul din Download înlocuite atomic. Instalarea și
  acceptarea fizică a noilor funcții rămân la utilizator.
- **27.10.2026:** recompilat și livrat **74887a1**, cu curățenia codului inclusă;
  toate joburile CI trecute, 30 de scripturi și runtime-ul Linux verificate.
  APK-ul **112,300,230 bytes** înlocuiește `7576033` în Download, cu aceeași
  semnătură. Instalarea pe dispozitiv rămâne la utilizator.
- **27.10.2026:** curățenie în sursele agentului: eliminate 6 funcții, 8 câmpuri,
  2 constante și prelucrarea UI redundantă; teste runtime izolate în proiect
  temporar. 495 aserțiuni runtime, 514 + 84 verificări editor și 28 teste Python
  trecute. APK-ul livrat nu a fost schimbat.
- **27.10.2026:** livrat **7576033** cu TODO-ul implementat; 495 aserțiuni
  runtime, 527 × 5 în editorul nativ și 86 dedicate trecute. APK semnat și
  installer/checksum înlocuite în Download; testarea fizică rămâne separată.

- **27.10.2026:** AG-01/19 implementate în surse, 50 verificări editor și 277
  runtime trecute. Runda nativă UC-10–17 are rezultate și limite documentate;
  17 verificări independente și trei comparații de fișiere trecute. UC-19
  așteaptă deblocarea; AG-20 identificat. Fără APK nou.

- **27.10.2026:** reconectare ADB și audit UC-04: 7 cereri / 26,37 s, scriere
  confirmată cu KEEP păstrat, fără refuz demonstrat. Test neconcludent; UC-05–09
  neexecutate. AG-09/12 actualizate, fără intervenții în proiect sau APK nou.

- **27.10.2026:** predate toate cele 47 de teste rămase UC-04–UC-50, document
  complet și șase părți TXT în Documents, cu mesaje/intervenții distincte și
  subproba de scroll. Verificare a pachetului, fără execuții noi sau APK nou.

- **26.10.2026:** UC-03 plan-only trecut, apoi implementare autorizată separat
  de utilizator; colectarea 0→3 verificată ulterior pe copie, nu de agentul
  Android. Adăugate AG-16 pentru scroll tactil, AG-17 pentru finalizare verificată
  și AG-18 pentru limita de text a planului. Fără fix runtime sau APK nou.

- **26.10.2026:** catalog cu 50 de use case-uri, cerințe și criterii, inclusiv
  48 de probe noi neexecutate. Copie în Documents, UC-03 pregătit și fișierele
  UC-04 create separat; jurnal și hash-uri inițiale salvate. Fără execuții noi
  de agent, instalări, generări sau APK nou.

- **26.10.2026:** precizat în TODO că agentul continuă până la livrare și
  verificare, fără plafon total de pași. Eliminarea limitei există în sursă;
  AG-03 rămâne deschis pentru livrare și validare în APK.

- **26.10.2026:** adăugate în TODO cerințele Running Tools fără dropdown,
  generări compacte cu preview la cerere și card de plan mai îngust. Etapă de
  documentare; implementarea și verificarea rămân de făcut.

- **26.10.2026:** testul 02 trecut cu agentul real pe Android: reparate două
  linii, parser valid, Output=20, oprire confirmată și fișiere păstrate; 17
  cereri în 48,8 s. Șase intrări independente trecute ulterior. Notat apelul
  către un tool neîncărcat și recuperarea lui; fără schimbarea APK-ului.

- **26.10.2026:** pregătit testul manual 02 pentru depanare GDScript, acumulare,
  păstrarea fișierelor și verificarea Output-ului. Eroarea intenționată este
  confirmată pe copie izolată; execuția prin agent încă nu a avut loc.

- **26.10.2026:** audit direct prin ADB al probei manuale cu cub verde; scena și
  preview-ul confirmate, limită de 30 de pași reprodusă, salvare fals pozitivă și
  comparație numerică strictă identificate. Creat TODO cu criterii; randare de
  control separată, fără modificarea proiectului sau APK nou. Închiderea manuală
  a preview-ului de utilizator este consemnată și nu este tratată ca eșec al agentului.

- **26.10.2026:** evaluare Claude Code 2.1.112 ca motor alternativ în Linuxul
  aplicației; pornire CLI verificată local și propunere documentată, fără
  înlocuirea agentului sau probă de inferență în APK.

- **26.10.2026:** corectat dialogul de aprobare care ieșea din ecran la scrierea
  fișierelor lungi; butoane fixe, cod derulabil, mascarea secretelor și reluare
  după Cancel. 70 verificări dedicate și 514 verificări editor complete trecute;
  probe pe surse, fără aprobare automată sau APK nou.

- **26.10.2026:** eliminate plafoanele totale de pași din chat/subagenți și
  continuarea prin companion; 492 verificări runtime, inclusiv 136 de cereri și
  Stop după depășirea vechilor limite; 482 verificări editor. Sursă verificată
  separat de APK-ul vechi.

- **26.10.2026:** conector de test în APK-ul instalat; Terrain3D verificat pe
  Android, recuperare Runware eșuată la HTTP 500 cu rezultat de succes; probă
  încheiată limitat la 30 de pași, fără mini hartă sau regenerare dublă.

- **26.10.2026:** modele pentru agenți încărcate la lipirea cheii, tarife per 1M
  tokeni în setări/chat și actualizare publică la 6h; verificări separate pentru
  sursă, interfață și citiri publice, fără APK nou în această etapă.

- Fundație: modul C++/GDScript, furnizori direcți, secrete Android, MCP și generare.
- `91fc116`, `683c769`, `83f7c68`: ecran principal nativ, conversații/subagenți,
  Playtest/voce, restaurare cu verificarea conflictelor și confirmări serializate.
- `6efdea8`, `7a19230`, `66cd1fb`: scripturi interne la salvarea scenelor,
  context compactat la ramificare și comportamentul de urmărire a streamingului.
- `f89a0dc`, `2ae35f6`, `605654d`, `e98ddb7`: simplificarea interfeței mobile,
  separarea conturilor, navigare adaptivă și reproiectarea chatului/setărilor.
- **22.10.2026:** harness propriu extras și conectat, cu testele precizate mai sus.
- **22.10.2026:** extins tool use cu descoperire la cerere, validare comună,
  patch-uri, citire/căutare, punte de diagnosticare și rezultate MCP normalizate.
  Adăugat documentul de progres, legătura din README și instrucțiuni în `AGENTS.md`
  pentru actualizarea lui la etapele următoare. Etapa a încheiat 149 verificări
  funcționale și 91 × 5 verificări în editor, fără erori; puntea nativă rămâne
  verificată static până la recompilarea editorului.
- **22.10.2026:** selectorul de model mutat din antet în composer; adăugate
  sertare pentru furnizor, model și reasoning, aplicare atomică a selecției,
  anulare și acces direct la reasoning. Iconuri comune introduse în chat și
  setări, cu identități distincte pentru furnizori. Verificarea vizuală include
  capturi ale fiecărui sertar și ale selectorului din composer. Rezultat final:
  149 verificări funcționale și 129 × 5 verificări în editor, fără erori.
- **22.10.2026:** APK compilat din `588bef1` prin workflow-ul `39725331751`
  (joburile android, runtime și native-editor reușite). Installerul
  `Godot-AI-4.7.2-arm64-588bef1-debug.apk`, cu SHA-256 `e208b1e7…`, a fost
  instalat în Download, iar APK-ul `e98ddb7` a fost eliminat. Semnătura de
  dezvoltare persistentă a rămas aceeași. Jobul native-editor a executat
  fixture-ul pe editorul fork-ului: 139 × 5 verificări, zero erori.
- **22.10.2026:** controale de jos reduse de la 44 la 32 unități, cu lățimi
  limitate după text; înlocuite simbolurile aproximative cu 57 SVG-uri upstream
  Lobe Icons, Lucide și llama.cpp. Testele locale au încheiat 150 verificări
  funcționale și 132 × 5 verificări în editor, fără erori. Adăugate verificarea
  și înlocuirea atomică a installerului, cu nume stabil în Download.
- **22.10.2026:** compilare și livrare finală `12794c4`, workflow `39733876322`.
  Controalele compacte și logo-urile upstream sunt incluse în APK. Au trecut
  150 verificări funcționale, 3 teste de livrare, 132 × 5 verificări upstream
  și 142 × 5 verificări pe editorul nativ. Toate cele 15 surse au fost găsite
  identic în biblioteca ARM64 din APK; semnătura persistentă a fost verificată
  local. Înlocuire atomică în Download și eliminarea installerului `588bef1`.
  Dovezi: `.ai-qa/delivery-12794c4.json`, `.ai-qa/compact-authentic-icons-final/`
  și `.ai-qa/compact-icons-native-ci/.ai-qa/native-rendered/`.

- **22.10.2026:** implementate Auto/Plan, plan structurat cu faze și continuare
  limitată, migrarea preferințelor, selector mai scurt, Markdown nativ și carduri
  de progres. Verificare funcțională locală: 167 aserțiuni, zero erori; APK nou
  încă nelivrat la această etapă.

- **22.10.2026:** livrare finală Auto/Plan `9a019f6`, workflow `39740297032` reușit.
  167 aserțiuni, 142 × 5 verificări upstream și 152 × 5 verificări native, fără
  erori. Companion: 9 teste și TypeScript build trecute local și în CI. APK de
  144.960.817 bytes verificat: pachet, ARM64, certificat persistent, SHA-256 și
  toate cele 17 scripturi identice sursei. Versiunea anterioară a fost înlocuită
  atomic la numele stabil din Download; nu s-au creat installere duplicate.
  Testarea fizică Android și planificarea/coding cu modele reale rămân de validat.

- **22.10.2026, 09:50 CEST:** recopiat APK-ul `9a019f6` la calea stabilă din
  Download după semnalarea orei 08:34. Hash-ul corespundea deja versiunii noi;
  recopia a actualizat inode-ul și ora modificării, verificată prin `stat`.
  SHA-256 și unicul installer au fost reverificate; solicitată reindexarea
  Android, fără confirmarea vizibilității în managerul de fișiere. Nu este o
  recompilare. Dovezi: `.ai-qa/download-refresh-9a019f6.json`.

- **22.10.2026:** reorganizare control/Integrări/Skills/Jurnal/AGENT.MD,
  indicator permanent de context și dock-uri. Numai surse, fără recompilare APK,
  conform cererii utilizatorului. Final: 187 aserțiuni și 172 × 5 verificări
  upstream, fără erori; Blender real și citire GitHub public verificate. C++
  verificat static, 19 surse și 61 SVG-uri verificate. Commit păstrat local pentru
  a evita declanșarea workflow-ului Android; limitele sunt în etapa curentă.

Detalii: [configurare și verificări](docs/AI_ASSISTANT.md),
[contractul harness-ului](docs/AI_HARNESS.md).

## Etapa Auto / Default / Plan și generare directă — 22.10.2026

- Auto planifică proactiv și cere `task_update` înaintea primei modificări;
  Default este echilibrat, Plan este strict read-only. Selecția salvată are nume
  stabil; vechiul index Plan=1 este migrat la Plan=2, fără escaladare de acces.
- Promptul comun cere răspunsuri de una-două propoziții pentru saluturi,
  identitate și întrebări simple, fără liste de funcții sau planuri inutile.
- Adaptoare native REST: Meshy text→GLB preview și imagine→GLB texturat;
  Tripo v3 text/imagine→3D și text→PNG; OpenAI Images GPT Image text→PNG.
  Runware și ComfyUI sunt păstrate. Configurare separată, chei în vault,
  endpointuri cloud fixe HTTPS și logo-uri originale Meshy/Tripo/ComfyUI.
- Persistență, polling, upload multipart Tripo, validare PNG/GLB și import
  fără suprascriere; cheile API nu sunt trimise la CDN. Oprirea urmăririi nu
  anulează sarcina taxabilă deja acceptată de furnizor. Meshy din text oferă
  geometria inițială; rafinarea/texturarea în a doua etapă nu este automatizată.
- Verificări locale: **237 aserțiuni runtime** și **178 × 5 verificări în editor**
  fără erori; trei teste de livrare, C++ syntax/format, 19 scripturi încorporate
  exact și 65 SVG-uri cu hash valid. Inspectate capturile pentru cele trei moduri
  și formularele Meshy/Tripo/OpenAI. Workflow-ul `39772723053` a trecut, inclusiv
  188 × 5 verificări în fork-ul nativ și 232 aserțiuni în CI. APK verificat: semnătură
  persistentă, pachet, ARM64 și toate cele 19 surse identice cu biblioteca nativă.
- Documentație: `docs/AI_GENERATION.md`; dovezi în `.ai-qa/modes-generation-*`.
  Testele de generare folosesc fixture HTTP, nu chei plătite reale.

Jurnal: **22.10.2026** — adăugate cele trei moduri, politica Auto, răspunsuri
compacte și adaptoarele Meshy/Tripo/OpenAI; compilarea APK este autorizată din nou.

- **22.10.2026 — livrare:** APK `db5343b`, workflow `39772723053` reușit,
  înlocuire atomică la calea stabilă din Download, un singur installer și checksum
  valid. Dovezi: `.ai-qa/delivery-db5343b.json`, `.ai-qa/modes-generation-verification.json`,
  `.ai-qa/db5343b-native-ci/`, `.ai-qa/db5343b-runtime-ci.log`.
  Verificările cu chei plătite și Android fizic rămân distincte și neefectuate.

- **Livrare / metadate Android:** după înlocuirea atomică, stocarea partajată a
  păstrat timestamp-ul anterior, deși hash-ul și conținutul APK erau noi.
  Scriptul de livrare actualizează acum explicit data APK/checksum și o include
  în raport. Fișierul curent indică **22.10.2026, 13:53 CEST**. Trei teste
  existente de livrare și noua regresie de timestamp au trecut local
  (`python misc/scripts/tests/test_ai_delivery_timestamp.py`). Broadcast-ul de
  scanare media a fost trimis; afișarea în managerul Android de fișiere rămâne
  verificabilă pe dispozitiv. A fost schimbat doar ajutorul de livrare, fără
  schimbarea surselor încorporate în APK-ul deja verificat.

- **22.10.2026 — curățare Integrări:** eliminat cardul „Servicii”, inclusiv
  „Servere MCP” și „Generare 2D / 3D”. Integrări păstrează GitHub, Blender CLI pe
  desktop, Skills și Sarcini; MCP și Generare au paginile lor. Verificare în
  editor Godot upstream, configurația phone_landscape: **178 verificări, zero
  erori**, captură inspectată vizual. Dovezi: `.ai-qa/integrations-without-services/`
  și `.ai-qa/integrations-without-services.log`. Modificare numai în surse,
  fără recompilare sau înlocuire APK în această iterație.

- **22.10.2026 — specificație fișiere în chat și control vizual:** adăugat
  `docs/AI_CHAT_FILES_AND_EDITOR_CONTROL.md`, cu cerințe, îmbunătățiri, etape și
  criterii de acceptare pentru carduri locale, mențiuni prin swipe, imagini
  fullscreen, preview 3D comun, capturi/control editor, Asset Store și diff real.
  Baza existentă a fost verificată în cod; uneltele UI semantice există deja,
  dar preview-ul universal și statisticile reale +/− nu sunt implementate.
  Consultate documentațiile Android/Godot. Este o propunere documentată, fără
  schimbări de runtime, teste noi sau recompilare APK în această etapă.

## Fișiere în chat și control vizual — jurnalul implementării, inclusă în APK `6539a44`

- În surse: registru cu versiuni imutabile și acces separat pe conversație,
  căutare nativă în proiect/stocare autorizată, carduri cu miniaturi și mențiuni
  prin swipe, referințe în mesajele puse în coadă, viewer de imagini cu zoom,
  decupare și adnotări. Originalele sunt păstrate.
- Renderer GLB/glTF comun pentru viewer și inspecție în fundal; capturi și
  input în editor cu frame ID, limită de timp și eliberarea inputurilor la Stop.
  În curs de verificare randarea 3D și controlul efectiv al interfeței.
- Diff cu linii reale adăugate/șterse, hunks și carduri per execuție; ZIP Store
  pregătit separat, fără suprascriere, cu verificarea fișierelor instalate.
- Verificare intermediară: `.ai-qa/store-compile2.log`, 269 aserțiuni fără erori.
  Testele vizuale noi au expus un crash al editorului upstream la trecerea spre
  editorul scripturilor; investigația este în curs. Această etapă nu este încă
  declarată validată în editor sau inclusă într-un APK nou.
- Limite de platformă: capturile/controlul vizează Godot, nu alte aplicații;
  MediaProjection Android necesită integrare separată și acordul sistemului.
  Preview 3D v1: GLB/glTF. Addonurile cu binare native necesită verificare
  specifică platformei. Providerii fără vision primesc metadate, fără afirmații
  de analiză vizuală a imaginii.

Jurnal: 22.10.2026 — implementare autorizată pe etape; verificările runtime trec,
QA vizual și adaptorul Store sunt în lucru. APK-ul din Download rămâne db5343b.

- **22.10.2026 — consolidare în surse:** modulele noi sunt încorporate în
  runtime (25 scripturi). Referințele glTF includ hash-urile dependențelor;
  pin/catalog și ramurile păstrează izolarea conversațiilor. Viewerul permite
  comparație și eliberează scenele la închidere. Imaginile sunt trimise numai
  modelelor cu vision declarat, cu buget comun de patru imagini în context.
- Adăugate 11 SVG-uri Lucide originale pentru preview/crop/adnotare/comparație,
  total 76, cu surse fixate, hash-uri și licențe. Headerul și dock-ul au controale
  compacte; păstrat HBox în composer după izolarea crash-ului HFlow upstream.
- Captura solicită explicit randarea, inclusiv în low-processor mode. Puntea
  nativă rutează hover-ul după coordonatele capturate, fără a modifica semnătura
  publică `Viewport.push_input`. Click-ul din fixture upstream folosește touch;
  verificarea mouse-ului nativ necesită recompilarea fork-ului.
- Store urmărește fișierele proprii, refuză conflictele/editările nesalvate și
  detașează resursele cached la ștergere, conform fluxului nativ Godot. Catalogul
  public a răspuns HTTP 403 local; verificarea REST folosește fixture HTTP.
  Nu este declarată verificare cu un addon public sau cu un furnizor vision real.

- **Verificări înainte de compilare:** 290 aserțiuni runtime fără erori
  (`.ai-qa/files-frozen-runtime.log`); 223 verificări în editor upstream desktop
  fără erori (`.ai-qa/files-private-fixtures/desktop/`), cu imagini și GLB reale,
  comparație, input, capturi mascate și fluxul Store disponibil upstream.
  C++ syntax verificat pentru modul, Viewport și instalator; 25 scripturi
  încorporate și 76 hash-uri SVG, plus trei teste de livrare și regresia mtime.
  Verificările pe cinci dimensiuni continuă în `.ai-qa/files-release-render/`.
  Compilarea fork-ului și APK-ului urmează; nu sunt încă declarate livrate.

- **Fork compilat, etapă intermediară:** sursa `cdc6834`, workflow
  `39817624076`: compilarea Android a reușit; 234 verificări desktop în fork-ul
  nativ au trecut, inclusiv inputul real cu mouse și dezinstalarea addonului.
  Workflow-ul complet a eșuat la marginea dock-ului drept în configurația narrow;
  APK-ul intermediar nu a fost livrat în Download.
- Corectată adaptarea la lățimea viewport-ului: limitarea cadrului editorului,
  pliere temporară a panourilor secundare și restaurare când chatul revine în
  centru. Scenariul izolat narrow trece cu 36 verificări; captură inspectată în
  `.ai-qa/dock-viewport-fit/narrow/dock-right.png`. Reluăm suita completă înaintea
  unei noi compilări/livrări. Runnerul QA oprește grupul propriu de procese la
  timeout pentru a evita servere Xvfb rămase active.

- **Validare layout completă:** 228 verificări × 5 configurații locale fără
  eșecuri (`.ai-qa/files-responsive-final/`): desktop, narrow, wide,
  phone_landscape și phone_compact. Include limitele dock/Trimite și revenirea
  panourilor după chat central.
- **Capabilități imagini:** catalogul poate omite modalitățile de intrare. În
  opțiunile furnizorului există acum control salvat separat pentru fiecare
  model: Din catalog / Permite imagini / Doar text. Numele modelului nu este
  folosit pentru a presupune vision. 294 aserțiuni runtime fără eșecuri în
  `.ai-qa/files-capabilities-unit.log`; verificarea formularului este separată.

- **Formular și carduri:** 231 verificări în configurația phone_compact fără
  eșecuri (`.ai-qa/files-vision-ui/`), inclusiv persistența politicii de imagini
  pentru fiecare model. Fixarea/eliberarea unei referințe sincronizează toate
  cardurile aceluiași fișier; la eroare de salvare se păstrează starea anterioară.
  Scenariul izolat pentru fișiere: 39 verificări fără eșecuri
  (`.ai-qa/files-pin-sync/`).

- **Fișiere invalide:** metadatele glTF/GLB sunt validate înainte de parcurgerea
  dependențelor; preview-urile eșuate eliberează referințele de animație. Numărul
  de noduri glTF este verificat și înainte de generarea scenei. O copie schimbată
  în timpul citirii este eliminată din cache, fără atingerea sursei.
  295 aserțiuni runtime fără eșecuri (`.ai-qa/files-invalid-models.log`).


## Livrare finală — 22.10.2026, 19:50 CEST

- Sursă **6539a444278b828b35baa53e9df1f1d7f3e243ed**, workflow
  [39823384697](https://github.com/JDscript1/godot-ai-android/actions/runs/39823384697):
  android, runtime și native-editor încheiate cu succes.
- **290 aserțiuni CI**, **233 verificări × 5** în editor upstream și
  **243 verificări × 5** în fork-ul nativ, fără eșecuri. Local: 295 aserțiuni;
  diferența de cinci provine din probele Blender disponibile local. Au trecut
  și cele trei teste de livrare și nouă teste companion, cu build TypeScript.
- Probe reale în editor: miniaturi, swipe/mențiuni/coadă, crop/comparație,
  geometrie GLB și randare offscreen, click efectiv și capturi mascate,
  sincronizare Pin, politici imagini per model, ZIP/activare/dezinstalare,
  diff colorat și Undo. Aserțiunile nu sunt prezentate drept validare a unui
  model cloud, addon public sau dispozitiv Android fizic.
- Inspectate vizual capturile native pentru chat/referințe, imagini și 3D,
  dock drept îngust și diff. Dovezi: `.ai-qa/6539a44-native-ci/`,
  `.ai-qa/6539a44-ci.log`, `.ai-qa/delivery-6539a44.json`.
- APK: **145.141.041 bytes**, pachet `com.jdscript.godotai.debug`, numai ARM64;
  semnătura persistentă verificată. Toate **25 sursele încorporate** sunt identice
  byte cu byte cu commit-ul compilat. **76 SVG-uri** au hash-uri valide.
- Înlocuire atomică la `/storage/emulated/0/Download/Godot-AI-Android-arm64-debug.apk`,
  cu checksum-ul alăturat și mtime **22.10.2026, 19:50:44 CEST**. Verificată
  existența unui singur installer al acestui fork; alte descărcări sunt păstrate.
- SHA-256: `0cc48766d215068d5e914a7a65f56f5377c1ef7eb146ff3aa1451f0dadeae6ba`.

Jurnal: 22.10.2026 — pachetul de fișiere/preview/control/Store/diff este compilat,
verificat și livrat. Android fizic, providerii vision reali și catalogul Store
public rămân de verificat separat; limitele de format/platformă sunt în
`docs/AI_CHAT_FILES_AND_EDITOR_CONTROL.md`.


## Audit dock și butoane — 22.10.2026

- Analizată captura `Screenshot_20261022_200421.jpg`: control tăiat în dock-ul
  stâng. Corectate limitele reale ale tabului, înălțimea, coloana stângă și
  adaptarea barei la lățimi mici. Istoricul compact are pagină proprie.
- Ștergerea nu mai cere arhivare. Confirmarea numește conversația; anularea,
  erorile de salvare, ultima conversație și redeschiderea indexului au probe pe
  fișiere reale izolate. Exportul salvează Markdown prin dialog.
- Corectate favorite/arhivare/redenumire, ciorne pe conversații în sesiune,
  ramificarea unui mesaj expirat și alegerea planului. Controalele indisponibile
  sunt dezactivate explicit.
- Auditul și limitele sunt în [docs/AI_UI_AUDIT.md](docs/AI_UI_AUDIT.md).
  Runtime local: 302 aserțiuni fără eșecuri. Sintaxa C++ Android a trecut.
  279 verificări randate fără eșecuri pe desktop și îngust; 279 pe fereastra mare
  după corectarea înălțimii barei (`.ai-qa/dock-audit-wrap-height/`).
  Revalidarea dock-urilor pe cinci dimensiuni și noua compilare sunt în curs; APK-ul anterior
  nu dovedește aceste modificări. Android fizic și serviciile live rămân separate.

Jurnal: 22.10.2026 — corecții de încadrare și audit al efectelor butoanelor;
verificările exercită fișiere, indexuri, dialoguri și tranziții reale în editor.


### Extindere audit la acțiunile din setări

- Listele păstrează selecția prin ID la actualizare/reordonare, inclusiv
  rezultatele de generare. Rezultatul nou devine selecția curentă.
- Ștergere/testare profiluri, rezultate, skills și sarcini reflectă selecția
  disponibilă și execuția curentă. Preview și import sunt disponibile pentru
  fișiere finalizate descărcate, iar refresh cere profilul aferent.
- 286 verificări în editor upstream compact, fără eșecuri, inclusiv apăsarea
  butonului Preview și verificarea pixelilor reali; ștergerea unui profil
  păstrează fișierul generat. Dovezi: `.ai-qa/ui-settings-actions/`.
- Dock-uri: 64 verificări × 5 dimensiuni fără eșecuri
  (`.ai-qa/dock-audit-responsive/`). Baza auditului `db972be` a trecut complet
  workflow-ul 39832915947; nu a fost livrată ca versiune intermediară în Download.
  Extinderea pentru setări se compilează separat înaintea înlocuirii APK-ului.


### Inspecție nativă suplimentară

- Workflow-ul 39833659749 (`09103e8`) a trecut: 297 aserțiuni runtime,
  286 verificări × 5 upstream și 296 × 5 native. Captura nativă compactă
  a arătat însă coloana centrală peste chat; testele măsurau încadrarea
  controalelor, fără suprapunerea dintre coloane. APK-ul nu a fost livrat.
- Adăugată limitarea temporară a coloanei centrale la spațiul rămas și
  recalcularea după schimbarea coloanelor. Limita originală se restabilește
  la revenirea în centru. Verificările includ viewport-ul 3D, celelalte coloane,
  marginea stângă a ferestrei și geometria JSON; capturile forțează randarea.
- 82 verificări locale compacte fără eșecuri înaintea noului build;
  `.ai-qa/dock-center-bounds/`. Capturile native noi sunt obligatorii înainte
  de livrare. Download păstrează momentan versiunea 6539a44.


### Validare finală audit — sursă 2538551

- Workflow [39835516663](https://github.com/JDscript1/godot-ai-android/actions/runs/39835516663):
  toate cele trei etape încheiate cu succes. 297 aserțiuni runtime CI, 305
  verificări × 5 upstream și 315 × 5 native, fără eșecuri; local 302 aserțiuni
  și 83 verificări de dock × 5. Nouă teste companion și build TypeScript trecute.
- Capturile native compacte și landscape sunt inspectate: chat complet vizibil,
  cu Setări, Dictare și Trimite în interior, fără suprapunerea viewport-ului 3D.
- Dovezi: `.ai-qa/2538551-native-ci/`, `.ai-qa/2538551-runtime-ci.log`,
  `.ai-qa/2538551-native-ci.log`, `.ai-qa/dock-center-responsive/`.
- APK final compilat; descărcarea și verificarea locală sunt în curs. Niciunul
  dintre APK-urile intermediare nu a înlocuit pachetul din Download.


## Livrare audit interfață — 22.10.2026, 21:11:14 CEST

- Sursă **25385516d329a373d37196148e293ca7fa05733a**, workflow
  [39835516663](https://github.com/JDscript1/godot-ai-android/actions/runs/39835516663): runtime, native-editor și Android trecute.
- 297 aserțiuni CI; 305 verificări × 5 în editor upstream și 315 × 5 în editor
  nativ, fără eșecuri. Local: 302 aserțiuni și 83 verificări de dock × 5.
- Capturile native compacte și landscape confirmă chat complet vizibil,
  fără suprapunerea viewport-ului 3D. Auditul include efectele reale ale
  dialogurilor, fișierele/indexurile conversațiilor, export, ciorne, selecții
  stabile, preview și dezactivarea acțiunilor indisponibile.
- APK: **145,157,425 bytes**, `com.jdscript.godotai.debug`, numai ARM64.
  Semnătura persistentă și toate cele 25 de surse încorporate sunt verificate.
- Înlocuit atomic `/storage/emulated/0/Download/Godot-AI-Android-arm64-debug.apk`
  la **21:11:14 CEST**, cu checksum alăturat. Verificat un singur installer
  al fork-ului în Download; alte descărcări sunt păstrate.
- SHA-256: `f8d4d2d208d06655d2b731872423260b02fb2ccbcd7ba8485eaa3932c4bd8a52`.
- Dovezi: `.ai-qa/delivery-2538551.json`, `.ai-qa/ui-audit-verification.json`,
  `.ai-qa/2538551-native-ci/`, `.ai-qa/2538551-runtime-ci.log`,
  `.ai-qa/2538551-native-ci.log`.
- Validarea fizică Android, microfonul și serviciile live rămân separate.

Jurnal: 22.10.2026 — livrat auditul de încadrare și comportament al butoanelor;
versiunile intermediare nu au fost livrate. Documentația curentă indică sursa,
testele și APK-ul verificat.


## Livrare exporturi 3D, GitHub și LAN — 23.10.2026, 08:02:45 CEST

- Sursă **13456afe2ca741c5b658ae5df76d1f98b8c8d5d7**, workflow
  [39908354563](https://github.com/JDscript1/godot-ai-android/actions/runs/39908354563):
  runtime, native-editor și Android trecute.
- Local: **340 aserțiuni**, 3 teste de livrare, **314 verificări × 5** randate și
  repetare desktop pentru export din Setări. CI: **335 aserțiuni**, **314 × 5**
  upstream, **324 × 5** native, 3 teste de livrare, 9 teste companion + build TS.
- APK **145.190.193 bytes**, `com.jdscript.godotai.debug`, numai ARM64; certificatul
  persistent și toate cele **26 de surse încorporate** verificate byte cu byte.
- Înlocuit atomic `/storage/emulated/0/Download/Godot-AI-Android-arm64-debug.apk`
  la **08:02:45 CEST**, cu checksum alăturat. Verificat un singur APK al fork-ului;
  celelalte descărcări sunt păstrate. Pachetul nu a fost instalat automat.
- SHA-256: `6b1178452b49fff41309a75eefeb313ba237ab7584ae0e290144515f3f71b110`.
- Dovezi: `.ai-qa/delivery-13456af.json`, `.ai-qa/13456af-native-ci/`,
  `.ai-qa/13456af-runtime-ci.log`, `.ai-qa/13456af-native-ci.log`,
  `.ai-qa/new-integrations-unit-final.log`, `.ai-qa/new-integrations-final-render/`,
  `.ai-qa/new-integrations-nested/`.
- Această versiune istorică folosea OAuth; sursele curente folosesc doar token personal.
  Testele furnizorilor plătiți, rețeaua Wi-Fi între dispozitive și comportamentul
  fizic Android rămân de validat; testele simulate nu țin locul acestor probe.

Jurnal: 23.10.2026 — livrat `13456af`; exporturile, GitHub Sign in și căutarea LAN
sunt în APK. Actualizate documentația și lista priorităților. Rețeaua utilizatorului
nu a fost scanată, iar conturi/chei ale dezvoltatorului nu au fost împrumutate aplicației.

## Livrare rafinare vizuală — 23.10.2026, 11:40 CEST

- Sursă **`978a6d332edd1204baeb0f5fed0634345b16645d`**; [workflow-ul
  `39932275075`](https://github.com/JDscript1/godot-ai-android/actions/runs/39932275075)
  a încheiat cu succes joburile runtime, native-editor și android.
- Local: **340 aserțiuni runtime** și **319 verificări randate × 5 configurații**,
  fără eșecuri. CI nativ: **329 verificări × 5 configurații**, fără eșecuri;
  inspectate capturile compilate pentru chat, dock îngust și setări.
- APK **145.206.577 bytes**, `com.jdscript.godotai.debug`, numai ARM64;
  certificatul persistent și toate cele **26 de scripturi încorporate** au fost
  verificate. SHA-256:
  `2ed475190032e253ff8ce1fc7f6593774488e22ed80ed47cab0022f6bceae689`.
- Înlocuit atomic APK-ul vechi din
  `/storage/emulated/0/Download/Godot-AI-Android-arm64-debug.apk`, cu checksum
  alăturat. Verificat un singur installer al fork-ului în Download; celelalte
  descărcări au fost păstrate. Pachetul nu a fost instalat automat.
- Dovezi: `.ai-qa/delivery-978a6d3.json`, `.ai-qa/978a6d3-artifact/`,
  `.ai-qa/978a6d3-native-ci/`, `.ai-qa/premium-ui-final-all/`.
- Validarea pe un dispozitiv Android fizic, GitHub cu token personal real,
  furnizorii plătiți și rețeaua Wi-Fi reală rămân probe separate.
