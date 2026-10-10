# Manutenzione del documento di feedback di Aomidori

Questa guida vale per qualsiasi agente e piattaforma di sviluppo. Il documento condiviso
è [Feedback Aomidori](https://aomidori-feedback.roccobot-b90.workers.dev/feedback).
Il sistema è quello di AIV, dove il proprietario ne ha confermato il funzionamento completo il
1 ottobre 2026; per Aomidori il primo giro è quello della 1.10.
Gli agenti mantengono lo stesso codice e indirizzo; recuperano il giro completo soltanto
dopo il via esplicito del proprietario in chat.
Non occorre una sessione Claude autenticata per aggiornare questo documento.

## Prima di prendere in carico il lavoro

1. Leggi `AGENTS.md`, `Rules.md` e il brief unico `Roccobot/tools/.memo/LATEST.md`.
   Il brief contiene richieste ancora aperte, priorità e riscontri da elaborare.
2. Allinea `main` con `git fetch origin main` e confronta i ref prima di modificare file.
   Conserva le modifiche già presenti nella copia di lavoro.
3. Leggi questa guida e, se tocchi il servizio, [la guida cloud](../cloud/feedback/README.md).
4. Distingui la manutenzione del documento dal collaudo dell'app: approvare la pagina
   non approva automaticamente le funzioni dell'app. Elabora le risposte solo dopo la
   consegna del giro completo da parte del proprietario.

## Fonti e responsabilità

| File | Responsabilità |
|---|---|
| [Feedback.md](Feedback.md) | Prove, identificatori, passi e risultati attesi |
| [feedback-build.py](../scripts/feedback-build.py) | Generatore, struttura della pagina e dati incorporati |
| [feedback.html](../publish/feedback.html) | Documento generato da pubblicare, mai unica fonte di una modifica |
| [feedback-zip.js](../publish/feedback-zip.js) | Scrittura e lettura dello ZIP di `Esporta` e `Importa`, senza librerie |
| [feedback-data.js](../publish/feedback-data.js) | Dati della pagina, bozza, validazione JSON, riepilogo, coda dei salvataggi |
| [feedback-ui.js](../publish/feedback-ui.js) | Tema, messaggi, contatori, riquadri e allegati, Altro, i sei comandi di consegna |
| [feedback-nav.js](../publish/feedback-nav.js) | Striscia, spostamento fra i riquadri, pulsanti flottanti e pressione lunga |
| [feedback-start.js](../publish/feedback-start.js) | Avvio: caricamento della bozza e allineamento con gli altri dispositivi |
| [feedback-format.js](../publish/feedback-format.js) | Editor visivo, Markdown, icone e scorciatoie |
| [feedback.css](../publish/feedback.css) | Aspetto, esiti, evidenze e adattamento dello schermo |
| [feedback-cloud.js](../publish/feedback-cloud.js) | Bozza remota, originali, versioni e accesso lato pagina |
| [feedback-cloud-config.js](../publish/feedback-cloud-config.js) | Configurazione neutra per la pagina aperta fuori dal Worker (file locale, verifiche), sostituita dal Worker sul cloud |
| [worker.mjs](../cloud/feedback/worker.mjs) | Pagina, accesso GitHub, API private, controllo delle scritture e `Content-Security-Policy` della pagina |
| [supabase-store.mjs](../cloud/feedback/supabase-store.mjs) | Database e Storage Supabase, soltanto lato server |
| [supabase-setup.sql](../cloud/feedback/supabase-setup.sql) | Tabelle, revisioni, privilegi e bucket privato |
| [feedback-cloud.yml](../.github/workflows/feedback-cloud.yml) | Verifiche e distribuzione del servizio cloud |
| [pages.yml](../.github/workflows/pages.yml) | Paginetta di download su GitHub Pages; il DF ne è escluso |

- I quattro script della pagina (`feedback-data.js`, `feedback-ui.js`, `feedback-nav.js`,
  `feedback-start.js`) sono script classici che condividono le variabili globali, caricati
  in quest'ordine; durante il caricamento nessuno chiama le funzioni di un file successivo,
  e l'avvio vive nell'ultimo. Ognuno lo dichiara nell'intestazione. Moduli ES scartati: lo
  stato condiviso andrebbe riscritto, e non si caricano da una pagina aperta come file.
- Le versioni dei file nei link (`?v=`) le calcola `feedback-build.py` dal contenuto di
  ogni file: dopo una modifica a CSS o JS si rigenera la pagina, e `--check` lo ricorda.

La versione delle prove si ricava da `CFBundleShortVersionString` in `Resources/Info.plist`,
la fonte unica della versione di Aomidori.
Una modifica al documento non produce una nuova versione dell'app.

Il sistema è copiato da quello di AIV (scelta M1 di Rocco, 2026-10-10) e adattato: un solo
dispositivo, il Mac; lo ZIP della release al posto dell'APK; i testi italiani da
`Resources/it.lproj/Localizable.strings`. Le date e i giri citati in questa guida prima del
2026-10-10 sono quelli di AIV, dove le regole sono nate: valgono qui allo stesso modo. Una
miglioria al sistema fatta in uno dei due progetti va riportata a mano nell'altro.

## Convenzioni di contenuto e interfaccia

- Nome ufficiale: **documento di feedback** (DF). Titolo: **Feedback Aomidori**.
  Intestazione: `Aomidori · giro della X.XX`, terminata alla versione, senza nome dell'agente.
- ⚠️⚠️ **Il corpo del DF contiene solo feedback sull'app** (norma di Rocco, 2026-10-03).
  L'interfaccia del DF (striscia, Altro, overlay, shell, formattazione, Salva-only mobile,
  casella versione, PP, ...) si discute e si concorda **in chat**, e vive in codice, in questa
  guida e nel brief. **Non** compare nel documento: né come prova di collaudo, né come riga
  di `Aggiornamenti recenti`.
- ⚠️⚠️ **L'introduzione tiene due righe sullo stato del giro e la riga di `Scarica e installa
  Aomidori`**, e nient'altro. Un link a un documento esterno (per esempio una proposta di interfaccia)
  va in testa, subito dopo quella riga, **finché serve**: chiusa la decisione che lo riguarda,
  si toglie.
- ⚠️⚠️ **La riga di download, dal 2026-10-06** (sue istruzioni): `Scarica e installa Aomidori x.yz`
  con accanto la casella sobria `installata`, che vale 'Sì, ho installato questa versione'; a
  destra, sulla stessa riga su desktop e sotto su mobile, `modifica` e il dispositivo
  (`**Mac**: ...`). `modifica` apre una modale con il suo campo,
  `Annulla` e `OK`: solo `OK` scrive la bozza. Il riquadro `I tuoi dispositivi` non c'è più, e
  nemmeno il titolo `Prove sui dispositivi` con la riga delle risposte: dopo la striscia cloud
  viene il primo riquadro delle prove.
  ⚠️ **Il titolo `Feedback Aomidori` comincia con l'icona dell'app, dal 2026-10-10** (sua richiesta,
  col mockup: distingue i due DF a colpo d'occhio). Le due icone del sito, `assets/icon.svg` e
  `assets/icon-dark.svg`, una per tema, si usano così come sono, e il tema le scambia come il resto
  della pagina, tasto `T` compreso. Misure del mockup, in em del titolo: squircle di 1,1167 em, 1,5
  px a sinistra delle righe sotto, 24,5 px dall'inchiostro della F, centrata sulle maiuscole, e la
  riga del titolo resta alta com'era. Il file ha il margine trasparente della griglia Apple (100 su
  1024 per lato), e `--df-icon-inset` lo toglie dal conto. Intorno all'icona un'ombra nera,
  larga, sfumata e tenue nel tema scuro (sua correzione: *più sfumata e più tenue*), leggera e discreta nel chiaro. Lo presidia
  `scripts/feedback-interactive-check.py`.
  - ⚠️ **Su mobile, dalla sera del 2026-10-06** (sua richiesta): testo dei dispositivi al 70%;
    icone da 20px al 22,5% dell'inchiostro attenuato, che sullo sfondo chiaro dà circa
    `#d4d8d2`; il bordo destro del **disegno** sulla verticale del lato destro della pillola di
    GitHub (ogni icona si sposta di quanto la sua tela lascia vuoto a destra, `--ink-gap`); il
    centro dell'icona sul centro di una maiuscola della riga (unità `cap`). Le icone non hanno
    gli angoli arrotondati dei pulsanti, che tagliavano ai lati il disegno (in AIV quello del
    tablet, che in Aomidori è l'icona del Mac, `changeMac.svg`).
  - ⚠️ **Su desktop, dalla stessa sera**: l'intestazione ha 26px di rientro per lato invece di
    24 (il blocco a sinistra va a destra di 2px, la pillola e i dispositivi a sinistra di 2px), e
    le schede cominciano 30px sotto la riga dei dispositivi.
- ⚠️⚠️ **`Aggiornamenti recenti` è un riepilogo degli ultimi due giri circa, non un changelog**:
  (si chiamava `Riscontri conclusi` fino al 2026-10-03, rinominata da Rocco)
  le righe dei giri più vecchi si tolgono quando entra un giro nuovo. La storia completa vive
  in git. La sezione della pagina la genera `scripts/feedback-build.py` dalla tabella
  `Aggiornamenti recenti` di `Feedback.md` (una frase per giro, il più recente prima): si
  aggiorna la tabella, mai il modello `scripts/feedback-page.html.in`.
- Sigle: **DF** = documento di feedback; **PP** = **Prossimi passi**.
- Ogni DF termina, prima della coda, con una sezione intitolata esattamente **Prossimi passi** (PP): un riepilogo breve e schematico di differiti, accorpati per dopo, voci da decidere e altre voci già nel brief. È una sorta di **mini-brief** per Rocco.
- Dopo aver letto un giro, la release successiva non deve comprendere tutto il backlog. L'agente sceglie liberamente il piano, ma lo comunica proattivamente a Rocco in chat, con ciò che entra e ciò che resta, senza aspettare che Rocco lo ricavi dal DF.
  Gli eventuali riferimenti all'autore nei testi visibili usano `l'agente`.
- ⚠️⚠️ **L'ordine dei blocchi del DF** (istruzione di Rocco, 2026-10-08: *gli unici blocchi
  numerati sono versioni atomiche di funzionalità precisa (1 blocco = 1 serie di controlli)*):
  1. le **prove**, `## N. Titolo`, le sole numerate: una funzione per blocco, con i suoi
     controlli;
  2. le **Domande**, `## Domande`, non numerate (voce qui sotto);
  3. le **Etichette testuali**, non numerate (voce più avanti);
  4. `Aggiornamenti recenti` e `Prossimi passi`.

  Una domanda o un testo da confermare non diventa mai una prova numerata: nel DF della 4.64
  le domande erano entrate come prove `4.64-03`...`4.64-12`, ed è la forma che questa voce
  sostituisce.
- ⚠️⚠️ **Le Domande: quelle ferme nel brief da più di dieci giri, e ogni scelta che spetta a
  Rocco** (regola completa in `Roccobot.md` § '⏳ Dopo dieci giri, una voce ferma nel brief
  torna nel documento di feedback'). Solo quelle di Aomidori, dei file di regole, delle convenzioni,
  delle impostazioni e del DF stesso: le voci di un altro progetto si ripropongono in chat (sua
  precisazione sul giro della 4.64). Nella fonte:
  - `### d-chiave · titolo`, con la chiave in minuscolo (la stessa con cui la risposta si cita
    nel brief, come `d-cestino-quando`);
  - il testo della domanda; un paragrafo per opzione, che comincia con `**C1**:`; un paragrafo
    che comincia con `Parere:` e nomina in grassetto l'opzione consigliata;
  - una domanda senza opzioni (una richiesta di dati) vive del solo commento.

  La pagina mostra le opzioni come tasti (uno alla volta, un secondo tocco lo toglie), segna
  quella del parere e aggiunge `Rimando`; la risposta si salva in `decisions` della bozza.
  Nessuna risposta vuol dire che la domanda resta aperta nel brief; `Rimando` riparte il conto
  dei dieci giri, col giro scritto accanto alla voce. Il generatore si ferma su una chiave
  doppia, su un parere che non nomina un'opzione, su una domanda senza testo.
- Scrivi testi italiani e prove eseguibili: comandi da raggiungere, azione e risultato
  atteso. Mantieni le prove aperte fra release; archivia soltanto quelle concluse dal
  giro consegnato. Non sostituire riscontri manuali con prove automatiche.
- ⚠️⚠️ **Ogni riquadro ha un riferimento, e un tasto che lo copia** (richiesta di Rocco del
  2026-10-09, col suo mockup e la sua icona: *ogni riquadro di esito abbia un simbolo in alto a
  destra, cliccabile, che copia il riferimento al riquadro stesso (es. `4.90-05`) da inserire in
  un altro commento che necessita una cross-reference*). I riferimenti sono tre famiglie, e sono
  le chiavi che già esistono: la prova `4.90-05`, la domanda `d-velo-pannello`, l'etichetta
  `e-draw_panel`. Il tasto lo aggiunge `refButton` in `publish/feedback-ui.js` a ogni riquadro
  di prova, domanda ed etichetta, e copia il riferimento in minuscolo **come codice in linea**
  (sua seconda richiesta dello stesso giorno: *formattato come codice in linea e che appaia come
  tale quando lo incollo*): fra apici inversi nel testo semplice, e come `<code>` nella copia
  formattata, per le app che la leggono. I campi di commento del DF incollano come codice un testo
  che è tutto fra apici inversi, come lo farebbe il tasto `Codice`. Lo presidia
  `scripts/feedback-interactive-check.py`. Nelle etichette con l'icona del lettore di schermo il
  tasto è alla sua sinistra.
- Conserva gli identificatori esistenti, come `3.13-01`.
  Per una prova nuova usa un identificatore nuovo: rinominare o riutilizzare una chiave
  può associare una risposta a una prova diversa.
- Ogni verifica mostra `Verifica X/Y`, con X in grassetto; il totale deriva dalle prove.
- Esiti: `Tutto OK`, `Accettabile`, `Non approvato`; nessuna scelta significa `Non provato`.
  Un secondo clic toglie l'esito. Verde, ambra e rosso seguono la scelta; commenti o allegati
  senza esito hanno evidenza neutra. Una risposta presente non equivale ad approvazione.
- Un campo solo per il Mac: modello e versione di macOS. Una bozza nuova, o azzerata, parte
  già col Mac di Rocco (`OWNER_MAC` in `feedback-data.js`), l'unico che ha (sua nota del
  2026-10-10): cambia di rado, e si modifica dalla modale.
- Editor con formattazione visibile, senza anteprima duplicata; icone grassetto, corsivo,
  link con nomi accessibili e suggerimenti. Cmd/Ctrl+B, I, K; Cmd/Ctrl+S salva.
  Il testo normale non è grassetto; da fuori si incolla testo semplice, nessun HTML interpretato.
- ⚠️⚠️ **Ogni stile si annulla, si copia e si salva** (richiesta di Rocco del 2026-10-10: *trasferibile,
  annullabile e persistente*), e lo presidia `scripts/feedback-interactive-check.py`:
  - **annullabile**: ogni campo ha una storia sua, fatta di istantanee del Markdown con la selezione
    prima e dopo ogni passo, e `⌘Z`, `⇧⌘Z`, `Ctrl+Y` e il menu Modifica la percorrono. La storia
    del browser conosceva solo quello che fa `execCommand`, quindi `⌘Z` dopo `Codice` annullava la
    digitazione di prima e lasciava il codice. La digitazione dello stesso tipo entro 1,2 secondi è
    un passo solo; un cambiamento che arriva da fuori (cloud, importazione, etichetta ripristinata)
    fa ripartire la storia;
  - **trasferibile**: copia e taglia da un campo scrivono negli appunti anche il Markdown della
    selezione, come tipo suo e come attributo `data-aomidori-markdown` della copia HTML, e incolla in un
    campo del DF lo rimette con gli stili. Da un'altra pagina o app si incolla testo semplice, e un
    testo tutto fra apici inversi diventa codice;
  - **persistente**: grassetto e corsivo sul codice, sopra di lui o dentro di lui, si scrivono
    `**`codice`**`. Fino al 2026-10-10 `markdown()` li perdeva, e al salvataggio il codice in
    grassetto tornava normale.
  - **Codice e mono sono la stessa cosa**: il tasto `Codice`, il riferimento copiato dal simbolo di
    un riquadro e il nome di un allegato inserito nel testo fanno tutti lo stesso `<code>`.
  Su viewport stretti (≤ 720px) i controlli stanno nell'angolo in basso a destra,
  dentro la cornice del testo, così la barra di selezione di sistema (Taglia/Copia/Incolla),
  che compare sopra il cursore, non li copre. Su desktop restano in riga sopra il campo.
- Navigazione flottante: **una pillola verticale** color accento, ancorata in basso a destra,
  con dall'alto primo non compilato, riquadro precedente, successivo e salvataggio col dischetto
  (richiesta dell'utente, 2026-10-03). Mostra solo i tasti che in quel momento possono agire,
  si allunga e si accorcia con loro, e con un tasto solo è un tondo. Il fondo è opaco al 25% nel tema scuro e al 70% nel chiaro,
  dove le icone bianche ne hanno bisogno per il contrasto 3:1 (sue scelte, con la sfocatura), le icone no, e sotto il fondo la pagina è sfocata come un
  vetro satinato (`backdrop-filter`, sua richiesta); dove il browser non la supporta resta il
  solo fondo. Commento o allegato
  contano come compilazione.
  ⚠️ Il tondo chiaro sotto un tasto della pillola vale solo dove c'è un puntatore vero
  (`@media (hover: hover)`, dal 2026-10-07): su un telefono lo stato `:hover` resta sull'ultimo
  tasto toccato, e l'utente lo leggeva come uno stato di `Salva`.
- ⚠️ **Il DF non ha un footer dal 2026-10-03** (*non serve a nulla*): lo spazio sotto l'ultima
  card, che la tiene libera dalla pillola, è del contenuto stesso (`main`).
- **Altro**: su desktop è una colonna laterale reale (preferibilmente a sinistra), sticky,
  sempre pronta, con toolbar di formattazione e allegati (`+` e trascinamento); la colonna
  è circa il 50% più larga del primo taglio laterale. ⚠️ **Su desktop, dal 2026-10-06, la
  striscia dei conteggi vive in cima ad Altro** (sua richiesta: *sparisce del tutto la striscia
  cloud, e il caricatore con le info va a vivere sopra 'Altro', nello stesso riquadro*): la sposta
  `feedback-nav.js`, senza bordo né ombra, e sopra la pagina non c'è più niente di fisso, quindi
  Altro sta a 18px dal bordo e una scheda raggiunta coi tasti di navigazione arriva lì. Sotto i
  1100px la striscia resta fissa in cima, come prima. Su mobile resta in
  fondo **prima** del PP; la striscia sticky mostra solo i chip semaforo centrati (niente
  hamburger né tasto Altro). Pressione prolungata sul FAB flottante ⇥ **o** su Salva
  (dischetto) apre Altro a pannello overlay (chiudi con `Chiudi` nella prima fila di tasti), sullo stesso campo `notes` del
  riquadro in fondo e con lo stesso salvataggio cloud; il tocco breve resta l'azione del FAB.
  Nell'overlay il campo comincia in cima al pannello, senza titolo né spazio sopra, ed è alto
  269 px, senza anello di selezione: con la tastiera alta dell'utente sopra restano circa
  368 px, e il campo e le due file di tasti entrano in quello spazio (sue scelte, 2026-10-04 e 2026-10-06). Con l'overlay aperto la pagina sotto non scorre.
  ⚠️⚠️ **L'overlay è alto quanto l'area che la tastiera lascia visibile** (`visualViewport`, dal
  2026-10-10, sua nota: con gli allegati non riusciva a scendere a vederli). Si apre col cursore nel
  campo, quindi su Android la tastiera si apre con lui, e lei riduce solo l'area visibile: un
  pannello alto quanto lo schermo teneva la sua fine sotto la tastiera, e misurato con quattro
  allegati scorreva di 213 px mentre loro erano circa 700 px più in basso. Il pannello scorre quando
  ha qualcosa da scorrere, e resta fermo quando non ce l'ha. Su mobile la riga di stato del salvataggio è a 12 px, centrata e al 70%. Al tocco Android non disegna nessun riquadro (`-webkit-tap-highlight-color`).
  ⚠️⚠️ **Su desktop la fine di Altro è sempre dentro la finestra** (dal 2026-10-10, sua nota con uno
  screenshot: con la pagina in cima non arrivava a `Rinomina` ed `Elimina` dell'ultimo allegato).
  Finché la pagina non lo porta a 18 px dal bordo, Altro comincia più in basso, e alto quanto la
  finestra meno 36 px finiva sotto il suo bordo: la rotella lo portava fino a una fine invisibile e
  poi si fermava. `feedback-ui.js` ne limita l'altezza (`--altro-max`) allo spazio fra la sua cima e
  il fondo della finestra meno 18 px, e `--df-tail` usa l'altezza che Altro ha quando è fermo in
  cima. Lo presidia `scripts/feedback-interactive-check.py`.
  Il titolo `Altro` è in grigio (`--muted`), non nel colore del testo. ⚠️ **Altro non prende i
  colori di una risposta** (`has-response`, sfondo e bordo grigio-azzurri) quando contiene testo:
  li aveva dal 2026-10-02 e lui l'ha visto diventare blu (2026-10-06); restano alle prove. Non usare un riquadro `position: fixed` staccato dal flusso come unica
  sede di Altro.
- ⚠️⚠️ **Etichette testuali: OGNI testo italiano nuovo o cambiato, anche quello scelto da
  Rocco** (sua istruzione, ribadita il 2026-10-08: *tutti i testi nuovi (anche quelli scelti da
  me) mi fossero sottoposti nel DF*). Dal DF 4.02 al 4.64 la sezione non è più comparsa mentre
  l'italiano dell'app riceveva 54 stringhe nuove e 10 cambiate: l'obbligo viveva solo qui, la
  frase si leggeva come rivolta ai testi proposti dall'agente, e una sezione assente non
  dava nessun allarme. Adesso c'è il presidio:
  - **`docs/Labels-approved.json`** è il registro dei testi italiani approvati, chiave per
    chiave (il punto di partenza è l'italiano della 0.60, l'ultima versione i cui testi Rocco ha
    visto prima di questo documento);
  - **`scripts/feedback-build.py` si ferma** se un testo di `Resources/it.lproj/Localizable.strings` è diverso dal
    registro e nessuna etichetta lo copre, e li elenca;
  - un'etichetta copre la chiave del suo id (`e-menu.view.split` copre `menu.view.split`) e
    quelle di un commento `<!-- chiavi: toolbar.split toolbar.split.help -->`, per raccogliere in una scheda le stringhe
    corte della stessa funzione;
  - letto il giro e applicate le sue riscritture, `python3 scripts/feedback-build.py
    --approve-labels` scrive nel registro il testo in vigore di ogni chiave coperta, e le
    etichette escono dal DF successivo.

  Quando una feature introduce o aggiorna copy italiano di
  interfaccia (paragrafi, pulsanti, toast, voci, ...), l'agente può redigere la proposta e
  far uscire la versione; il DF deve elencare **ogni** nuova stringa ITA in
  una sezione intitolata esattamente **Etichette testuali**, in basso, dopo le **Domande** e
  **prima** delle sezioni conclusive/archivio (`Aggiornamenti recenti`) e del PP. Ogni sotto-card mostra il
  testo ITA proposto per intero e un campo libero: ciò che l'utente scrive sostituisce la
  proposta al prossimo rilascio utile; campo vuoto = approvato. Non è una sezione di prove
  (niente esiti, fuori dai contatori). Assente o vuota → sezione nascosta.
  ⚠️⚠️ **Dopo la prima conferma un'etichetta esce dal DF**: è risolta (campo vuoto, o testo
  dell'utente applicato), oppure, se servono chiarimenti o modifiche, torna nel brief. Non
  resta in pagina per un secondo giro.
- ⚠️ **Sotto il campo di Altro, nella colonna della pagina, due righe** (istruzione
  dell'utente, 2026-10-03):
  1. la riga divisa **esattamente a metà**: a sinistra il `+` tratteggiato degli allegati, a
     destra i quattro tasti di formattazione, che si dividono la metà in parti uguali;
  2. i sei comandi di consegna come **icone con tooltip**, ognuno largo 1/6 della riga, in
     quest'ordine: `Azzera tutto`, `Copia il riepilogo`, `Esporta`, `Importa`,
     `Salva`, `Invia`. `Copia il riepilogo` copia negli appunti e basta: il testo non compare
     in nessun campo.
  ⚠️⚠️ **Nel pannello mobile le file sono due, sempre visibili, di sei tasti uguali su tutta la
  larghezza, alti 42 px** (sua istruzione del 2026-10-06), in quest'ordine: `Invia`, `Link`,
  `Codice`, `Grassetto`, `Corsivo`, `+`; poi `Azzera tutto`, `Copia il riepilogo`, `Esporta`,
  `Importa`, `Salva`, `Chiudi`. L'ordine lo dà il CSS: nella pagina i tasti restano dove sono. Dal 2026-10-04 era una fila sola a due stati, con
  `Consegna` e `Torna` per passare dall'uno all'altro (mockup `Altro_mobile`): i due commutatori
  non ci sono più. `Chiudi` ha preso il posto della × in alto e di quella in basso a destra.
  Sotto le file ci sono gli allegati di Altro (sua istruzione del 2026-10-06), che con la
  tastiera aperta restano sotto di lei.
  ⚠️ **L'overlay `Consegna e copie` non c'è più dal 2026-10-03**, e con lui la pressione lunga
  su Salva che lo apriva su desktop. I messaggi dei comandi compaiono nella striscia dei
  conteggi (su desktop in cima ad Altro),
  sotto lo stato del salvataggio (`#action-message`). Gli identificativi `#save`, `#copy`...
  sono sui pulsanti della pagina; la copia nel pannello mobile li riconosce da `data-command`.
- ⚠️ **Ritocchi del 2026-10-04 (sue richieste)**: l'introduzione dice soltanto *Giro x.yz:
  collaudo chiuso. Le migliorie e le scelte dei giri precedenti sono in archivio.*, su mobile
  non c'è, e dopo il titolo viene subito `Scarica Aomidori` (sua istruzione, 2026-10-04 sera); `Invia` risponde anche con un toast in basso; il campo in cui
  si scrive non ha il bordo colorato; le miniature degli allegati sono due per riga; il codice
  inline è reso nell'editor come grassetto, corsivo e link; su desktop `Prossimi passi` segue
  l'ultimo riquadro a 18 px e, a fine pagina, finisce dove finisce `Altro` (lo spazio in fondo lo
  calcola `feedback-ui.js`, variabile `--df-tail`); `Esci` ha 7 px a destra; `⌘↑` e `⌘↓`
  (`Ctrl` altrove) portano a inizio e fine pagina fuori dai campi.
- La **B** del grassetto è un tracciato SVG, non testo: ricavata dalla B di Arial Bold
  (Liberation Sans Bold, con le stesse misure), alla stessa dimensione e allo stesso tratto
  della lettera di prima, perché la sua resa non dipenda dai caratteri installati.
- Da scollegati, l'accesso è una pillola sola `Accedi con GitHub`, ancorata a destra della
  riga del titolo.
- La versione di Aomidori del giro nel DF è testo fisso (`spec.version`); la conferma avviene solo
  con la casella `installata` della riga di download (`installed` = versione del giro o vuoto).
- Allegati mediante selettore e trascinamento nelle verifiche e in Altro:
  PNG, JPG, WebP, GIF, SVG e ZIP. Originali interi, nomi conservati, ZIP scaricabili.
  Limiti attuali: 8 MB per file, 20 MB totali, 30 allegati per riquadro.
- ⚠️ **Un allegato si rinomina e si cita** (richiesta dell'utente, 2026-10-05):
  - `Rinomina` cambia il solo `name`, dentro la scheda: il campo contiene il nome senza
    estensione, l'estensione resta accanto e non si modifica, `Invio` o l'uscita dal campo
    confermano ed `Esc` annulla (sua istruzione del 2026-10-06); un nome scritto con
    l'estensione non ne prende una seconda; l'originale e il suo `storageKey` non cambiano;
  - mentre si scrive in un campo, un clic sull'allegato inserisce al cursore il suo nome con
    l'estensione **come codice inline**, formattato nell'editor (dal 2026-10-06; prima fra apici
    dritti); la pressione è trattenuta, così il campo tiene fuoco e cursore. Su desktop nome e
    miniatura mostrano la mano al passaggio;
  - **solo nell'overlay mobile**, se nessun campo ha il cursore (la tastiera chiusa può
    toglierlo), il tocco copia negli appunti il nome fra backtick (`` `nome.png` ``) e lo dice
    con un avviso (sua istruzione del 2026-10-06);
  - il nome è centrato, a 14px e staccato dalla miniatura e dai tasti; `Rinomina` ed `Elimina`
    (fino alla sera del 2026-10-06 `Rimuovi`) sono su una fila centrata, larghi uguali e alti
    40px. Su mobile sono due icone (matita e cestino), con lo stesso nome per il lettore di
    schermo; sul desktop l'icona viene prima della parola, perché le sole parole a colpo d'occhio
    si confondevano (sue istruzioni del 2026-10-06).
- Collegamenti esterni in nuova scheda con `noopener noreferrer`. Il DF e le sue pagine di
  supporto usano la favicon `assets/feedback-favicon.svg` (il blocco note col glifo), colore
  `#43B59E`, e alternativa PNG. ⚠️ La paginetta di download `index.html` **non** la usa: ha il
  glifo nudo dell'app, e non cambia (segnalazione dell'utente, 2026-10-03).
  - **In Aomidori** (sua richiesta, 2026-10-10) il blocco note è quello di AIV, e il glifo
    intagliato è il libro di Graphe, con le stesse forme della favicon del sito
    (`assets/favicon.svg`: le quattro colonne disegnate per le misure piccole), nello spazio che
    occupa il glifo di AIV; le colonne restano nel colore del blocco note. Il PNG da 32 px è
    reso da Chromium dallo stesso SVG, su fondo trasparente.
- `Azzera tutto` richiede conferma e riguarda la bozza su tutti i dispositivi.
  Un comando disabilitato non indica un caricamento: cursore normale e aspetto coerente,
  anche per il selettore di `Importa`.

## Dati, privacy e compatibilità

Il JSON usa `schema: 1`, `project: Aomidori`. La bozza contiene:

| Campo | Significato |
|---|---|
| `version`, `installed` | Versione del documento; `installed` vale la stessa stringa solo se Rocco ha spuntato 'Sì, ho installato questa versione', altrimenti stringa vuota (non è più un campo libero) |
| `device` | Il Mac: modello e versione di macOS, di partenza `OWNER_MAC` (il nome della chiave viene dallo schema di AIV) |
| `entries` | Risposte per ID: `status`, `comment`, `images` |
| `decisions` | Decisioni per ID: `choice`, `comment`. Dal 2026-10-08 contiene le risposte al blocco `Domande` (`choice` è la lettera, o `rimando`); dal 2026-10-03 a quel giorno la pagina non ne poneva, e la chiave resta comunque: il Worker la richiede, e una bozza vecchia la conserva intatta |
| `labels` | Etichette testuali per ID: `revision` (campo libero; assente nei JSON vecchi → `{}`) |
| `notes`, `extra.images` | Osservazioni libere e relativi allegati |
| `updated`, `completed` | Data del salvataggio e della preparazione del giro |

`images` è il nome storico anche per gli ZIP: non cambiarlo senza migrazione.
**Al cambio di giro la bozza si alleggerisce** (dal 2026-10-03, scelta dell'utente): restano
il Mac, le risposte alle prove ancora in pagina, le etichette ancora aperte e le
decisioni; escono `Altro` coi suoi allegati, la conferma della versione installata, e le risposte
alle prove chiuse coi loro allegati. Prima si accumulavano: un JSON del 3.42 conteneva 76 risposte
dal giro 3.13 in poi, e importato sembrava vuoto. L'importazione dice quante risposte riguardano
prove non più in pagina.
**Gli allegati sono file veri**, mai testo: nella pagina e nella bozza del browser un
allegato è `{name, type, size, blob}`, con i byte originali (dal 2026-10-03; prima erano testo
base64, un terzo più pesante e tenuto per intero nella memoria della pagina).

**`Esporta` scrive uno ZIP senza compressione** (`feedback-zip.js`, senza librerie):
`feedback.json` con le risposte, e accanto gli allegati coi nomi corti scelti
dall'utente, cioè la posizione della prova su due cifre più una lettera (`01a.png`, `01b.jpg`,
`02a.webp`), `00` per Altro (`00a.png`), e l'identificativo per le risposte a prove non più in
pagina (`3.40-02a.png`). Ogni allegato in `feedback.json` è `{name, type, size, file}`:
`name` è il nome originale, `file` quello nello ZIP. **`Importa` accetta lo ZIP** (anche
ricompresso da un altro programma) **e i JSON esportati prima del 2026-10-03**, con gli
allegati in base64 (`data`), che il controllo di validità trasforma in file veri.
Sul cloud il JSON contiene riferimenti SHA-256 `storageKey`; gli originali rimangono nel
bucket privato. Il caricamento verifica dimensione e hash prima di ricostruire il JSON
completo. Il servizio carica al massimo tre allegati in parallelo e riusa quelli già presenti.

Una nuova proprietà deve essere mantenuta da validazione, copia della bozza, recupero,
importazione/esportazione, riepilogo e validazione server. Verifica sempre i vecchi JSON
e le risposte già esistenti. Non resettare la bozza per facilitare un aggiornamento.

La pagina servita dal Worker ha una `Content-Security-Policy` (dal 2026-10-03): solo i suoi
script, stili, caratteri e API, e immagini solo da sé o dagli allegati in memoria (`blob:`).
Chi aggiunge una risorsa esterna o uno stile in linea allarga la regola nel Worker, o il browser
la blocca; il controllo cloud fallisce se il browser segnala un blocco.

Le risposte personali e gli allegati non entrano nei commit pubblici, nei log o nel brief.
L'accesso cloud è riservato al proprietario GitHub, ID `10722164`; gli agenti ricevono il
giro reso leggibile con Invio e richiesto esplicitamente in chat. Essere manutentore non autorizza a leggere il suo
database privato. `Invia` rende leggibile una copia del giro, senza avviare lettura o lavorazione.
Il salvataggio della bozza da solo non rende leggibili le nuove modifiche.

## Servizio e gestione degli errori

Cloudflare Workers Free serve pagina e API sulla stessa origine. Supabase Free conserva
PostgreSQL e bucket privato `aomidori-feedback`. GitHub conserva il codice. R2 non è utilizzato.
Credenziali e token rimangono sul server; la guida cloud descrive i cinque campi Actions,
OAuth, SQL e configurazione. Non chiedere segreti in chat e non metterli nella pagina.

Dal 2026-10-06 la pagina cloud tiene nel browser una **copia di sicurezza** della bozza (scelta
R2 del proprietario, dopo una bozza persa per una sessione scaduta): IndexedDB `aomidori-feedback-backup`,
scritta prima di ogni salvataggio nel cloud e segnata come arrivata quando il cloud conferma. Una
copia non arrivata e più recente di quella del cloud si offre al caricamento successivo; `Esci` la
cancella. Non è una seconda fonte: il cloud resta la bozza, e la copia serve solo a recuperarla.
Dalla stessa data la sessione si rinnova a ogni uso (un giorno dopo l'ultimo rinnovo, per altri 7
giorni), fino a 60 giorni dall'accesso con GitHub (R1, `worker.mjs`). La copia su
GitHub Pages, che conservava il vecchio salvataggio locale, non è più pubblicata dal
2026-10-03 (decisione del proprietario): `pages.yml` esclude dal sito la pagina del documento
e i suoi script, che restano in `publish/` perché il Worker serve quella cartella come asset. Se una vecchia
bozza servisse, la pagina si recupera dalla storia git e si apre in locale.

Il salvataggio usa una revisione UUID e un confronto atomico in PostgreSQL. Cloudflare
può trasformare `"revisione"` in `W/"revisione"` durante la compressione: client e server
rimuovono il prefisso W/ prima di confrontare la stessa revisione. Conserva questa gestione
sia sul caricamento/salvataggio sia sul controllo HEAD. Non aggirare un vero conflitto
ritentando con la revisione corrente: sovrascriverebbe un altro salvataggio.

La pagina si sincronizza al ritorno nella scheda e ogni 15 secondi, quando non ci sono
modifiche locali. Senza accesso i campi e l'importazione sono disabilitati con un messaggio
esplicito. Un errore o conflitto conserva le modifiche nella scheda e indica `Non salvato`:
esportare prima di chiudere o ricaricare. Attendere `Salvato nel cloud` prima di considerare
confermata la scrittura. La sessione dura sette giorni; la chiave di sessione viene
conservata dai deploy successivi.

Le revisioni precedenti sono conservate nel database, ma non costituiscono un backup
indipendente. Gli originali scollegati non vengono cancellati automaticamente: lo spazio
occupato può superare quello della bozza. La pausa del progetto Supabase non equivale a
cancellazione; limiti, recupero e precauzioni sono nella guida cloud. Non promettere
conservazione illimitata né considerare un dump SQL una copia degli allegati Storage.

## Aggiornare e pubblicare

1. Registra obiettivo e stato nel brief prima di un intervento su più passi.
2. ⚠️ **Prima la release**: il DF di collaudo di una versione esce **dopo** la GitHub Release pubblicata **con lo ZIP allegato** (`Aomidori-X.XX.zip`). Vale quando il DF introduce o aggiorna prove di collaudo per una **nuova versione app**. Un ritocco **solo UX/documentale** del DF (layout, Altro, controlli, copy di manutenzione) si pubblica subito su Feedback cloud **senza** una release nuova.
   Prima di pubblicare o aggiornare il DF per un collaudo `X.XX`, verifica che esista la GitHub Release pubblicata della
   stessa versione, non una bozza, col tag `vX.XX`. Il numero nella pagina, il collegamento allo ZIP o un tag senza
   release non sono prove sufficienti. Se la release manca, prepara soltanto una bozza locale.
3. Aggiorna le fonti corrette e conserva tutte le risposte aperte. Se il proprietario sta
   compilando, prepara una bozza senza ripubblicarla, salvo sua richiesta esplicita.
4. Rigenera e verifica dalla radice di Aomidori:

   ```sh
   python3 scripts/feedback-build.py
   python3 scripts/feedback-build.py --check
   python3 scripts/feedback-check.py publish/feedback.html
   ```

   Con un giro senza prove aperte il controllo verifica che la pagina parta senza errori e
   senza schede, poi genera una copia temporanea con una prova di sintesi (lo stesso
   generatore, con `--source` e `--output`) e la esercita per intero: la copia non tocca
   `publish/`.

5. Se cambi cloud, protocollo o salvataggio, esegui anche `npm --prefix cloud/feedback test`
   e la prova con due sessioni browser `scripts/feedback-cloud-check.py`, avviando i servizi
   locali come descritto nella guida cloud. Usa esclusivamente chiavi e dati fittizi.
   Il controllo remoto usa il proprietario sintetico `0`, mai la bozza personale.
6. Un difetto segnalato richiede la prova che lo riproduce prima del fix. Mantieni le
   verifiche di concorrenza, intestazioni W/, originali e recupero dopo errori.
7. Se cambi gli asset, aggiorna il parametro di versione dei relativi script/CSS nel
   generatore per evitare una pagina nuova con codice vecchio. Non forzare ricariche.
8. Esegui i controlli del diff e del messaggio con `refcheck.py`, poi commit e push su `main`
   secondo le regole del repository, incluso il footer `Agent` della piattaforma effettiva.
9. Attendi `Feedback cloud`: check e deploy devono riuscire. Controlla l'indirizzo nel
   riepilogo, pagina pubblica disponibile e API anonima 401. Il DF non fa parte del sito:
   `Pages` pubblica `publish/` senza i file del DF. Una modifica delle sole istruzioni agli
   agenti non richiede una release nuova.
10. Comunica a Rocco in chat il piano scelto per la release successiva e il riepilogo `Prossimi passi` del DF, poi comunica risultato, verifiche e collaudo da fare; aggiorna il brief con il residuo.
   Non chiudere il collaudo dell'app sulla sola riuscita del documento.

Un agente privo di credenziali cloud può aggiornare il repository e usare il workflow
già configurato. Se non può pubblicare, lascia una modifica concreta e verificata e indica
nel brief il passaggio mancante, senza creare un secondo documento o un nuovo indirizzo.

## Invio e presa in carico: due fasi

1. **Invia rende leggibile il giro**, solo dopo un salvataggio riuscito. Non esegue
   workflow di lettura, non avvisa un agente e non avvia lavori. Il proprietario può
   modificare, salvare e inviare di nuovo liberamente. Il nuovo invio sostituisce
   la versione proposta; le modifiche non ancora inviate restano nella bozza.
2. **La richiesta esplicita in chat autorizza la presa in carico**, per esempio
   `Leggi l'ultimo giro di feedback`. Solo allora l'agente esegue il recupero.
   Nessun monitoraggio automatico di salvataggi o invii, nessuna lettura preventiva.
3. ⚠️⚠️ **Subito dopo il recupero, e prima di qualsiasi lavoro prodotto**, si travasa
   **tutto** nel brief privato `Roccobot/tools/.memo/LATEST.md` (esiti, commenti,
   decisioni con chiave, note del campo libero, ordine di lavoro). Solo dopo si
   tocca il codice. Regola universale: `rules/Roccobot.md` § '📋 Prima cosa: tutto
   nel brief, prima del lavoro prodotto'. Allegati e JSON restano fuori dal repo.
   ⚠️ Le prove 'Tutto OK' non entrano, e quando la versione è pubblicata la sua voce si
   riscrive al solo residuo: `refcheck.py` blocca nel brief il segno ✅ e la formula
   'fatta e pubblicata'.

4. ⚠️⚠️ **Prima di chiudere l'elaborazione del giro: audit obbligatorio contro
   l'export precedente** (`rules/Roccobot.md` § '🔍 Audit obbligatorio').
   **Documento di feedback = sorgente del lavoro aperto; brief = piano d'azione
   documentato + backlog (non archivio/changelog). Una richiesta esce dal DF solo se è
   fatta nel prodotto o scritta nel brief; dal brief esce solo quando è fatta.** Si rilegge il JSON del
   giro **prima** (o l'allegato rimesso in chat) e si verifica che ogni Non
   approvato / Accettabile / nota del campo libero / decisione operativa sia
   *fatta con prova*, *nel brief e/o ancora nel documento*, oppure *cancellata
   esplicitamente*. Mai far sparire una richiesta. Differito resta in sospeso;
   parziale ≠ completo. Il nuovo documento non azzera quei debiti.

Per recuperare, con GitHub CLI autenticato come proprietario e Node 24, dalla radice di Aomidori:

```sh
node scripts/feedback-read.mjs --version 3.24 --output /tmp/aomidori-feedback-3.24.json
```

**Senza GitHub CLI** (le sessioni cloud di Claude Code, dal 2026-10-06), lo stesso recupero si fa in
due comandi, con il workflow avviato e l'artefatto scaricato dagli strumenti GitHub della sessione:

```sh
node scripts/feedback-read.mjs --prepare --dir /tmp/aomidori-chiave --version 4.33
node scripts/feedback-read.mjs --open feedback-envelope.zip --dir /tmp/aomidori-chiave --output /tmp/aomidori-giro/giro.json
```

Il primo crea la cartella privata con chiave e richiesta e stampa gli ingressi di `feedback-read.yml`
(`request_id`, `public_key`, `requested_at`, `version`, `verify_only`), da passare così come sono;
il secondo apre l'artefatto (ZIP o JSON), scrive il giro e gli allegati accanto (`allegato-1.svg`...),
e solo allora cancella la cartella con la chiave. Un'apertura fallita tiene la chiave, e si riprova
sullo stesso artefatto. Prima di questi due comandi ogni passo si scriveva a mano, ed è lì che i
recuperi del 2026-10-06 sono falliti tre volte. Lo prova `scripts/feedback-read-test.mjs`.

Ometti `--version` per l'ultimo giro inviato di qualsiasi versione. Lo strumento avvia
soltanto su comando il workflow `Leggi feedback inviato`, con chiave pubblica temporanea.
Il server recupera dalla storia l'ultima copia inviata entro la data di avvio della
richiesta: nuovi invii mentre il workflow gira non cambiano il giro preso in carico.
Il contenuto e gli originali vengono cifrati con AES-256-GCM; la chiave viene protetta
con RSA-OAEP. Nei log e negli artefatti GitHub non compare feedback in chiaro. La chiave
privata rimane in memoria nella sessione dell'agente. Il risultato decifrato viene scritto
fuori dal repository, con permessi privati; non commetterlo. L'artefatto cifrato viene
rimosso dopo il recupero o scade dopo un giorno. Nessuna chiave Supabase passa all'agente.

Il workflow ammette solo richieste avviate dal proprietario GitHub e non ha trigger su
push, salvataggio o Invio. L'accesso GitHub è necessario: non è una lettura pubblica.
Negli ambienti con rete limitata, il download degli artefatti GitHub richiede anche
`*.blob.core.windows.net`: GitHub usa più server Azure per gli allegati. Aggiungi il
dominio alla configurazione senza rimuovere quelli esistenti e verifica il download
con `--verify-only` prima di dichiarare pronto il collegamento.
Se una piattaforma non può eseguire il comando, lo dichiara; JSON/riepilogo manuali
restano disponibili come alternativa. Registra nel brief la revisione presa in carico
(`cloudRevision`) e il lavoro risultante, senza contenuti o allegati personali.

Per verificare il collegamento senza leggere feedback personali:

```sh
node scripts/feedback-read.mjs --verify-only --output /tmp/aomidori-feedback-transfer-test.json
```

La prova usa un proprietario sintetico con zero iniziale, dati e SVG fittizi. Verifica
Supabase, selezione della copia inviata, cifratura, artefatto e decifratura, senza aprire
il giro reale. La suite `feedback-transfer-test.mjs` verifica anche modifiche non inviate,
invii successivi, filtro temporale, originali, chiave errata e manomissioni.
