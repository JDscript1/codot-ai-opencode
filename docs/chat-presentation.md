# Afișarea conversației în Godot AI

Implementare nativă GDScript, 30 octombrie 2026. Se aplică panoului agentului
Godot AI. Interfața oficială din tabul Ziva rămâne independentă.

## Mesaje și sarcini

Conversația este plată, fără carduri sau bule: mesajele utilizatorului sunt
text aliniat la dreapta, etichetat discret „Tu”, iar răspunsurile agentului
folosesc text liber, cu lățimea adaptată spațiului disponibil și un singur
antet pentru intervențiile consecutive ale aceleiași sarcini. Doar câmpul de
compunere păstrează o suprafață proprie, discretă.


O sarcină afișează, în ordine:

1. Identitatea agentului și starea răspunsului.
2. Actualizările anterioare în secțiunea extensibilă **Progres**.
3. Istoricul extensibil al operațiilor.
4. Răspunsul curent sau rezultatul final.
5. Cardurile fișierelor, fără duplicate în același grup.
6. Un singur set principal de acțiuni și metadatele de consum.

Intervenția utilizatorului întrerupe gruparea vizuală, chiar dacă este Steer
în aceeași sarcină. Mesajele vechi nu sunt mutate după intervenție. Consumul
cumulat apare pe ultimul segment al sarcinii. Istoricul original al mesajelor
și relațiile dintre apeluri și rezultate rămân păstrate.

Stările **Rezultat**, **Întrerupt**, **Blocat**, **Eșuat** și **Necesită verificare**
sunt distincte. „Rezultat” descrie încheierea rulării, fără să pretindă că
gameplay-ul a fost verificat; criteriile și dovezile existente rămân separate.

## Spațiu fix și erori

Chatul rămâne pe loc când o scenă pornește: ecranele principale AI Assistant
și Ziva nu lasă editorul să deschidă automat Output sau Debugger-ul la rulare.
Erorile raportate de Debugger apar ca un indicator compact în antet
(„1 eroare”/„N erori”); până la prima citire folosește culoarea de atenție.
Atingerea lui deschide Debugger-ul direct pe tabul **Errors**, la cerere, iar
indicatorul rămâne disponibil în stilul mut cât timp există erori în sesiune.
Dacă fila de chat extinsă este activă, atingerea restaurează mai întâi
panourile, apoi arată erorile.

## Streaming și formatare

Paragrafele și blocurile de cod sunt widgeturi separate. La primirea textului,
blocurile neschimbate nu sunt rerandate. Textul este livrat în loturi scurte,
fără animație artificială de tastare. Un fence incomplet nu apare temporar
drept cod sau text al răspunsului.

Parserul recunoaște fence-uri pe linii, inclusiv `~~~`, și păstrează backtick-urile
literale din interiorul codului. Markdown-ul rămâne sigur: textul modelului
nu este interpretat ca HTML sau BBCode executabil. Titlurile nu introduc
suplimentar rânduri goale față de sursă.

Codul de peste 18 linii arată inițial primele 12. **Arată tot codul** îl extinde
în conversație, iar **Copiază codul complet** păstrează toate liniile și când
previzualizarea este restrânsă. Evidențierea sintaxei ține cont de limbaj.

## Operații și fișiere

**Running Tools · Image Generator**, **Running Tools · 3D Generator** sau
numele operației active apare deasupra câmpului de scriere, numai în timpul
execuției. Această linie nu este un dropdown.

În răspuns, **Operații** păstrează starea, durata raportată, erorile și câteva
date relevante, precum calea fișierului sau rezultatul diagnosticului.
Argumentele arbitrare și payload-urile furnizorilor nu sunt copiate în fiecare
widget. Detaliile pot fi deschise, copiate sau urmărite în jurnalul existent.
Rezultatele reutilizate și trimiterile neconfirmate sunt marcate separat.
Duratele noi sunt salvate în
metadatele istoricului; pentru conversațiile vechi nu se inventează durate.

Lista restrânsă nu construiește widgeturi pentru fiecare operație. La deschidere
arată ultimele 20, cu încărcarea operațiilor anterioare la cerere.

Imaginile și modelele păstrează miniaturile existente și un buton explicit
**Deschide**. Fixarea rămâne disponibilă direct; menționarea, trimiterea și
compararea sunt în meniul cardului. Afișarea unui card nu deschide viewer-ul.
Planurile, întrebările interactive și cardurile de verificare sunt păstrate.

## Telefon și navigare

Modificările fișierelor sunt diffuri direct în conversație, fără carduri:
numele fișierului deasupra, ștergeri roșii (`-`), adăugări verzi (`+`) și context
neutru. Fragmentul inițial are cel mult 40 de linii; **Arată restul** extinde
conținutul, în loturi de maximum 500 de linii pentru diffuri foarte lungi.
Codul este literal, fără interpretarea BBCode. Derularea rămâne cea a
conversației; accesul existent la jurnal și restaurare este păstrat.

Indicatorul de context poate fi atins pentru consumul ultimei cereri, fereastra
modelului, rezerva pentru răspuns și pragul compactării. `≈` indică o estimare;
după un răspuns cu usage, estimarea următoare folosește măsurătoarea furnizorului
plus conținutul nou. Consumul cumulat al sarcinii este o metrică separată.
Rezervarea contextului tratează imaginile separat de codificarea lor Base64.

Glisarea pe mesaje navighează în conversație. Apăsarea lungă oferă copierea;
o atingere scurtă pe un link folosește hit-testing-ul nativ, fără selectarea
accidentală a textului. Linkurile HTTP(S) sunt validate; căile proiectului
folosesc navigarea nativă descrisă în
[Inspecții și diagrame](chat-inspections-and-diagrams.md).

Derularea în istoric oprește urmărirea automată. Săgeata în jos revine la
ultimul mesaj și reactivează urmărirea. Mesajele noi nu trag cititorul la
final; căutarea deschide progresul sau codul restrâns pentru a arăta rezultatul.
Adaptarea existentă la tastatură păstrează câmpul și cursorul deasupra ei.

## Inspecții și diagrame

Cardurile de citire/căutare arată fragmentele originale cu linii numerotate.
Căile din carduri și răspunsuri deschid explicit fișierele în Godot. Blocurile
Mermaid flowchart și state simple au randare nativă, sursă, zoom și deplasare.
Sintaxa avansată rămâne sursă; nu este motorul Mermaid complet. Limitele și
interacțiunile sunt documentate în
[Inspecții și diagrame](chat-inspections-and-diagrams.md).

## Verificare

Scenariul `presentation` din `tests/render.py` testează widgeturile reale,
streaming-ul, gruparea, operațiile, restaurarea istoricului, codul lung,
fișierele, indicatorul de erori, atingerea linkurilor și ciclul de
derulare/tastatură. Scenariul
`all` îl include, împreună cu scenariul `inspections`. Rezultatele etapei și limitele verificării sunt în
`PROGRES_SI_PLAN.md`, AG-64; dovezile locale sunt în
`.ai-qa/chat-presentation-20261030/`.

Aceste probe folosesc Godot Linux în PRoot și rezultate deterministe. Nu sunt
o probă fizică Android și nu confirmă un APK nou sau un furnizor live.
