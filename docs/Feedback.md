# Feedback Aomidori

Versione **1.10**: il primo giro del documento di feedback di Aomidori, con tutto quello che dalla 0.61 alla 1.10 è uscito senza collaudo.
[il DF](https://aomidori-feedback.roccobot-b90.workers.dev/feedback).
La Release 1.10 è pubblicata: [v1.10](https://github.com/Roccobot/Aomidori/releases/tag/v1.10), con lo ZIP
[Aomidori-1.10.zip](https://github.com/Roccobot/Aomidori/releases/download/v1.10/Aomidori-1.10.zip).
Commit prodotto su `main`: `4f3eb5f`, release dal commit `4f3eb5f` (SlimVer 1.10 / build 22; ZIP 3.563.349 byte).

Questo è il documento condiviso da tutti gli agenti e le piattaforme.
La [guida di manutenzione](Feedback-maintenance.md) spiega come prenderlo in carico e aggiornarlo.
Giro **1.10**: undici prove, quattro domande e sette gruppi di testi. Le prove sono tante perché raccolgono nove versioni.

Nel documento interattivo scegli **Tutto OK**, **Accettabile** o **Non approvato**;
nessuna scelta significa **Non provato**. Un secondo clic sulla scelta la cancella.
Nei commenti: Grassetto, Corsivo, Codice inline (`` ` `` / ⌘M) e Link (Cmd+B/I/M/K).
Su desktop: Altro in colonna laterale, coi conteggi in cima. Sotto il campo di Altro ci sono allegati e
formattazione, e sotto ancora i sei comandi: Azzera tutto, Copia il riepilogo (negli
appunti), Esporta e Importa (uno ZIP con risposte e allegati), Salva, Invia. **Etichette testuali** (se presenti) vanno prima dell'archivio.
Il campo Mac è già compilato col tuo MacBook Pro e resta al cambio versione; Altro e allegati liberi si azzerano, e le risposte alle prove chiuse escono dalla bozza.
`Invia` rende leggibile il giro senza avviare lavori.

I libri di prova sono in `~/Developer/aomidori-test`: `Alice.epub`, `Pinocchio.epub` (coi disegni in bianco e nero), `Pinocchio-prova.cbz` (un fumetto fatto con quei disegni) e `Una-descrizione-di-Terramare.epub`. Il CBR è il tuo `Foto & Arte.cbr`.

Le verifiche automatiche della 1.10 sono superate: 157 prove unitarie, le prove del lettore, dell'avvio, della Playground e dell'icona sul Mac.

| Voce | Stato | Commento dell'utente | Azione successiva |
|---|---|---|---|
| 1.10-01 | Non provato | | Attendere il collaudo. |
| 1.10-02 | Non provato | | Attendere il collaudo. |
| 1.10-03 | Non provato | | Attendere il collaudo. |
| 1.10-04 | Non provato | | Attendere il collaudo. |
| 1.10-05 | Non provato | | Attendere il collaudo. |
| 1.10-06 | Non provato | | Attendere il collaudo. |
| 1.10-07 | Non provato | | Attendere il collaudo. |
| 1.10-08 | Non provato | | Attendere il collaudo. |
| 1.10-09 | Non provato | | Attendere il collaudo. |
| 1.10-10 | Non provato | | Attendere il collaudo. |
| 1.10-11 | Non provato | | Attendere il collaudo. |

## 1. La fusione delle illustrazioni in bianco e nero

Apri `Pinocchio.epub` e vai a un capitolo con un disegno. In chiaro il bianco del disegno diventa il colore della pagina (*Moltiplica*); in scuro il disegno diventa chiaro su fondo scuro (*Dividi*). Le quattro tavole a mezzetinta, quelle con le sfumature grigie come una fotografia, restano come sono.

Premi `⌘L`: le illustrazioni tornano come sono, in tutte le finestre; il pulsante `Fondi` nella barra e la voce `Fondi le illustrazioni in bianco e nero` del menu Stile si spengono. Premi di nuovo `⌘L`, poi prova pulsante e voce di menu. Chiudi e riapri l'app: la scelta è ricordata.

Apri `Pinocchio-prova.cbz`, fatto con gli stessi disegni: le tavole di un fumetto non si fondono mai, in chiaro e in scuro (tua scelta L1).

## 2. Testo a bandiera, giustificato e sillabazione

Apri `Alice.epub`: il testo corrente è a bandiera a sinistra, qualunque sia lo stile, e a bandiera nessuna parola è spezzata a fine riga (restano i trattini morbidi che il libro ha già).

Premi `⌘J`: il testo diventa giustificato, in tutte le finestre, e la sillabazione si accende per tenere uniformi gli spazi. Di nuovo `⌘J` per tornare a bandiera; prova anche il pulsante `Giustifica` e la voce `Testo giustificato` del menu Stile. I titoli centrati restano centrati.

Con lo stile `ReadingRoccobot.css` il testo non supera i 22 px anche a finestra larga (era 26), e `+` `-` `0` vincono comunque su quel limite.

## 3. La vista divisa

Apri `Alice.epub` in una scheda sola e premi `⌘S`: a destra appare una seconda vista dello stesso libro, allo stesso punto. `⌘S` di nuovo: la seconda vista si chiude.

Apri una seconda scheda con un altro libro e premi `⌘S`: la scheda attiva va a sinistra con la barra laterale, l'altra a destra. Con tre o più schede appare la lista `Quale scheda affiancare?`, numerata da 1 a 0: prova un numero, Invio su una voce scelta con le frecce, un clic, ed Esc che annulla.

Dentro la vista divisa, `←` `→` e `⌘←` `⌘→` agiscono sulla metà in cui hai cliccato per ultima. Uscendo dalla vista divisa ogni scheda torna al suo posto nella barra delle schede. Prova anche il pulsante `Dividi` e la voce `Vista divisa` del menu Vista.

Nella Playground CSS (`⇧⌘P`), `⌘S` resta Salva e scrive il file.

## 4. Impostazioni e link in schede nuove

Premi `⌘;` (o `⌘,`): si apre la finestra delle Impostazioni, con le sezioni `Funzionalità` e `Aggiornamenti`.

Con `Apri i link in nuove schede` spenta (il predefinito), in un libro con un indice, come `Alice.epub`: un clic su un link lo segue nella stessa scheda; `⇧`-clic apre una scheda nuova davanti, `⌥`-clic una scheda nuova dietro. Accendi l'opzione: ogni clic apre una scheda nuova, e `⌥` la apre sempre dietro.

Con `Apri ogni link accanto alla scheda di origine` accesa la scheda nuova appare accanto a quella da cui parte il link; spenta, in fondo alla fila. Le due opzioni sono indipendenti: la seconda vale anche con la prima spenta. Un link verso il web si apre sempre nel browser.

Clic destro su un link del libro: c'è `Apri il link in una nuova scheda`, e apre una scheda di Aomidori. Clic destro su un'immagine: nessuna voce che non faccia niente (prima c'erano `Apri in una nuova finestra` e lo scaricamento).

## 5. `T` in ogni finestra

Nella finestra vuota, senza libri aperti, premi `T`: l'app passa all'altro aspetto, chiaro o scuro. Di nuovo `T` per tornare. Prova poi con un libro aperto e nella Playground fuori dall'editor.

`T` non cambia aspetto mentre scrivi: nel campo di ricerca e nell'editor della Playground scrive la lettera.

## 6. I fumetti, CBZ e CBR

Apri `Pinocchio-prova.cbz`, poi il tuo `Foto & Arte.cbr`: le tavole sono una sotto l'altra, in un capitolo solo, e scorrono in verticale. Chiudi il CBR e riaprilo un paio di volte: si apre sempre, e alla seconda volta non è più lento della prima.

Se hai un archivio protetto da password, o un file rinominato in `.cbz` che non è un archivio, aprilo: appare un messaggio d'errore leggibile (i testi sono fra le etichette qui sotto).

## 7. La finestra vuota e il pulsante Apri

All'avvio senza libri, la finestra vuota mostra `Apri un documento o trascinalo qui`. Passa sopra il pulsante Apri: l'aiuto dice `Scegli un libro o un fumetto da leggere (⌘O)`.

Ridimensiona la finestra: la zona di rilascio cresce e cala nelle sue proporzioni, al massimo metà della larghezza e il 30% dell'altezza. Trascina un EPUB sul riquadro, poi un CBZ: si aprono come schede della finestra.

## 8. Cronologia dei link e scorciatoie della 0.60

In `Alice.epub` segui un link dell'indice, poi una nota o un'ancora se il libro ne ha: `⌘←` torna indietro alla posizione esatta, `⌘→` torna avanti. Gli alias `⌘[` e `⌘]` fanno lo stesso. `←` e `→` da soli cambiano capitolo.

`⌘Y` passa dal font del libro al font personalizzato e ritorno, in tutte le finestre.

Nella Playground CSS, nell'editor: `⌘F` apre la ricerca, `⌘G` passa al risultato successivo, e `⌘←` `⌘→` muovono il cursore a inizio e fine riga, senza toccare la cronologia.

## 9. Pannello Tipografia e angoli della scheda

Apri il pannello font dal menu Stile, scegli Baskerville, e nella sezione Tipografia del pannello attiva il maiuscoletto: il testo del libro lo mostra. Con Hoefler Text, Georgia od Optima macOS non offre il maiuscoletto Apple, e non è un difetto di Aomidori.

Con due o più schede aperte, guarda gli angoli della scheda attiva nella barra delle schede, in chiaro e in scuro: in una cattura della 0.5.0 c'erano due angoli neri. Se li vedi ancora, allega una schermata.

## 10. Aggiornamenti dalle Impostazioni

Nelle Impostazioni, sezione `Aggiornamenti`: la riga `Versione installata: 1.10`, la casella `Controlla automaticamente gli aggiornamenti` e il pulsante `Controlla ora`, che risponde che la 1.10 è l'ultima. Se sei passato alla 1.10 con l'aggiornamento automatico, scrivilo nel commento: è la prima prova di Sparkle su una versione già installata.

## 11. Il sito, le note di rilascio e i testi inglesi

Apri [il sito](https://roccobot.github.io/Aomidori/), in chiaro e in scuro, in italiano e in inglese: la schermata verticale è allineata alle schede, la scheda `Anche i fumetti` ha il fumetto 💬 e nomina CBZ e CBR, e il sottotitolo è *Lettore di eBook e fumetti per macOS*. Non c'è più il link al codice sorgente. Controlla anche i passi d'installazione e la riga per chi non usa un Mac.

Leggi le note delle [release dalla 0.61 alla 1.10](https://github.com/Roccobot/Aomidori/releases), in inglese.

Per i testi inglesi dell'app: in Impostazioni di Sistema, `Generali` > `Lingua e regione` > `Applicazioni`, scegli Aomidori e la lingua inglese, poi riapri l'app. Guarda i menu Stile e Vista, le Impostazioni, la barra degli strumenti e la finestra vuota. Alla fine rimetti l'italiano.

## Domande

### d-tre-punti · I tre punti nei testi dell'app

Diciotto testi di Aomidori, come `Apri…` e `Impostazioni…`, hanno i tre punti come carattere unico, che è la convenzione dei menu di macOS: segnano una voce che apre una finestra prima di agire. Le regole vogliono tre punti separati, e per il codice e i testi di interfaccia non c'è una deroga scritta.

**C1**: Teniamo il carattere unico nei testi dell'app, come macOS, e lo scrivo come deroga nelle regole di Aomidori.

**C2**: Passiamo a tre punti separati in tutti i diciotto testi, in italiano e in inglese.

Parere: **C1**. Nei menu il carattere unico è quello di tutte le app di sistema, e a schermo i tre punti separati sono più larghi e si vedono diversi accanto alle voci di macOS.

### d-pulizia-recenti · I libri di prova nei tuoi file recenti

`Prova-link.epub` e `Una-descrizione-di-Terramare.epub` sono rimasti fra i file recenti e nelle posizioni salvate (`Positions.json`) della tua copia di Aomidori, dalle prove della 0.60.

**C1**: Li tolgo io, con l'app chiusa, e solo quelle due voci.

**C2**: Li lascio: li togli tu quando capita.

Parere: **C1**. Sono due voci di prove, e toglierle non tocca nient'altro delle tue impostazioni.

### d-branch-tools · I branch di altre sessioni in `Roccobot/tools`

Su GitHub `Roccobot/tools` ha tredici branch `claude/...` lasciati da altre sessioni, e nel clone del Mac c'è un file `.DS_Store` non tracciato. Li ho visti durante la pulizia di Aomidori e non li ho toccati.

**C1**: Li controllo uno per uno: cancello quelli già mergiati o vuoti, e per gli altri ti dico che cosa contengono.

**C2**: Cancellali tutti.

**C3**: Lasciali dove sono.

Parere: **C1**. Un branch con lavoro non mergiato potrebbe essere di una sessione ancora aperta.

### d-repo-inizio · Nessun repository nella cartella Inizio

Oggi è stato trovato un repository git nella tua cartella Inizio (`~/.git`), che faceva vedere tutti i tuoi file come modifiche; l'abbiamo cancellato con la tua scelta H1.

**C1**: Aggiungo alle regole universali il divieto di creare un repository nella cartella Inizio, con un controllo automatico all'avvio delle sessioni.

**C2**: Basta la cancellazione di oggi.

Parere: **C1**. Il controllo costa una riga e avvisa prima che il problema si ripresenti.

## Etichette testuali

### e-menu.style.blendInk · La fusione delle illustrazioni

Menu Stile: Fondi le illustrazioni in bianco e nero
Pulsante: Fondi
Aiuto del pulsante: Fonde con la pagina le illustrazioni in bianco e nero, o le lascia come sono (⌘L)
Per chi usa VoiceOver, accesa: Illustrazioni fuse con la pagina
Per chi usa VoiceOver, spenta: Illustrazioni come sono

<!-- chiavi: toolbar.blendInk toolbar.blendInk.help a11y.blendInk.on a11y.blendInk.off -->

### e-menu.style.justify · L'allineamento

Menu Stile: Testo giustificato
Pulsante: Giustifica
Aiuto del pulsante: Passa da bandiera a sinistra a giustificato, e viceversa (⌘J)
Per chi usa VoiceOver: Bandiera a sinistra, Giustificato

<!-- chiavi: toolbar.justify toolbar.justify.help a11y.flushLeft a11y.justified -->

### e-menu.view.split · La vista divisa

Menu Vista: Vista divisa
Pulsante: Dividi
Aiuto del pulsante: Affianca un'altra scheda, o un'altra vista del libro (⌘S)
Per chi usa VoiceOver: Vista divisa attiva, Vista singola
Titolo della lista: Quale scheda affiancare?
Sotto la lista: Digita il numero, oppure scegli e premi Invio. Esc annulla.

<!-- chiavi: toolbar.split toolbar.split.help a11y.split.on a11y.split.off split.chooser.heading split.chooser.hint -->

### e-settings.features · Le Impostazioni e i link

Menu Aomidori: Impostazioni (con i tre punti, vedi la domanda `d-tre-punti`)
Sezione: Funzionalità
Prima opzione: Apri i link in nuove schede
Seconda opzione: Apri ogni link accanto alla scheda di origine
Nota: I link verso il web si aprono sempre nel browser. Anche con la prima opzione disattivata, un clic con ⇧ apre il link in una nuova scheda in primo piano, un clic con ⌥ in una nuova scheda dietro.
Menu contestuale di un link: Apri il link in una nuova scheda

<!-- chiavi: menu.app.settings settings.features.newTabs settings.features.nextToSource settings.features.note menu.context.openLinkInNewTab -->

### e-settings.updates · Gli aggiornamenti

Sezione: Aggiornamenti
Casella: Controlla automaticamente gli aggiornamenti
Pulsante: Controlla ora
Riga della versione: Versione installata: 1.10
In una copia senza Sparkle: Gli aggiornamenti automatici non sono attivi in questa copia di Aomidori.

<!-- chiavi: settings.updates.automatic settings.updates.checkNow settings.updates.off settings.updates.version -->

### e-empty.message · La finestra vuota

Invito: Apri un documento o trascinalo qui
Aiuto del pulsante Apri: Scegli un libro o un fumetto da leggere (⌘O)

<!-- chiavi: empty.open.help -->

### e-error.unreadableComic · I messaggi d'errore

Fumetto illeggibile: Il file non è un fumetto valido: l'archivio non si può leggere.
Fumetto con password: Il fumetto è protetto da una password e Aomidori non può aprirlo.
Archivio senza immagini: L'archivio non contiene immagini.
File troppo grande in un libro: Il file 'nome' è troppo grande per un libro: l'archivio sembra danneggiato.

<!-- chiavi: error.passwordProtected error.noPages error.oversizedResource -->

## Prossimi passi

- **In collaudo**: il residuo dalla 0.61 alla 1.10, nelle undici prove di questo giro.
- **Prossimo lavoro**: la vista di un'immagine sola come il tuo *Decent Image Viewer*, per un'immagine aperta in una scheda nuova e per un capitolo fatto di una sola immagine, come la copertina.
- **Dopo**: eBook e fumetti come due modi d'uso distinti, con lo spunto del lettore di Mihon; le pagine sfogliabili per ora no.
- **Da decidere dopo un prototipo**: le miniature nel Finder e l'anteprima Quick Look con la copertina degli EPUB.
