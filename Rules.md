# Rules.md: regole del progetto Aomidori

> **Cos'è questo file.** Le regole **specifiche** di `Roccobot/Aomidori`, il lettore EPUB per
> macOS. Tutto quello che vale per ogni progetto vive nelle regole universali,
> `rules/Roccobot.md` di `Roccobot/tools`, e qui non si duplica.
> Vale per **tutti gli agenti**: il nucleo, cioè ogni regola in una riga, vive in `AGENTS.md`,
> e questo file ne dà il perché. Come funziona il codice lo dicono il `README.md` e i commenti
> del sorgente: qui c'è solo quello che nel codice non c'è.

## 📖 Che cos'è Aomidori

- **Un lettore EPUB minimale, in stile web**: ogni capitolo è una sola pagina che scorre in
  verticale, `←` e `→` cambiano capitolo. Niente pagine, niente scorrimento orizzontale, una sola
  modalità di vista. La leggerezza e la prontezza vengono prima di ogni funzione.
- **E i fumetti, dalla 0.70**: un CBZ si apre come un libro di un capitolo solo, le tavole una
  sotto l'altra (sue scelte del 2026-10-10: solo scorrimento verticale, nessun verso di
  lettura, prima i CBZ e i CBR dopo, con libarchive e non unrar). Il documento che le contiene
  lo genera `EPUBKit` (`ComicArchive`), e il resto dell'app non sa la differenza. ⚠️ Il tipo
  dichiarato è `cx.c3.cbz-archive`, quello che usano di fatto le app di fumetti: un tipo nostro
  non veniva mai assegnato sui Mac dove un'altra app aveva già dichiarato il suo.
- **Piattaforma**: macOS 27 Golden Gate e successivi, **solo Apple Silicon** (`scripts/bundle.sh`
  si ferma su un'altra architettura), interfaccia Liquid Glass.
- **Murasaki** (chiuso) è il riferimento per barra degli strumenti, pannelli laterali e
  Inspector: si guarda, non si copia. Nessun asset e nessuna riga di codice vengono da lì.

## 🎯 Le decisioni di prodotto di Rocco

Decisioni sue, da non ridiscutere senza che sia lui a riaprirle:

- **Il CSS dell'utente deve poter scavalcare tutto** il CSS del libro: con *Override Book Style*
  attivo non sopravvive niente della tipografia del libro (fogli, `@font-face`, stili in linea,
  `<font face>`).
- **`+` `-` `0` vincono su qualunque limite del CSS**, anche su `min()`, `clamp()`, misure in px e
  `!important`. Le immagini non crescono col testo.
- **Il pizzico non ingrandisce mai il testo.**
- **Ogni funzione del lettore ha una scorciatoia e una voce di menu.** Una funzione raggiungibile
  solo col mouse è incompleta.
- **Meno opzioni possibile**: una preferenza nuova si propone solo quando un comportamento unico
  non basta.
- ⚠️⚠️ **`ReadingRoccobot.css` è lo stile personale di Rocco**: vive in `Resources/` come stile di
  fabbrica e nella sua cartella stili. Il suo **contenuto** non si modifica mai senza una sua
  richiesta esplicita, nemmeno per provare una funzione; un CSS consegnato a lui si chiama sempre
  `ReadingRoccobot.css`. Le prove usano copie in cartelle di prova.
- **Giorno e notte**: gli stili con regole `prefers-color-scheme` le seguono da sé; per un CSS che
  non le ha, la notte applica solo i colori delle regole scure dello stile di fabbrica.
- **La finestra vuota**, dall'alto: la zona di rilascio di Graphe, l'invito ad aprire un EPUB col
  pulsante Apri, la lista "File recenti" (solo il nome del file, mai il percorso), col titolo
  allineato esattamente ai nomi. La zona di rilascio cresce con la finestra, al massimo metà
  della larghezza e il 30% dell'altezza, nelle sue proporzioni. Appare
  all'avvio senza libro, dal Dock senza finestre e in una tab nuova. I libri si aprono come tab
  della finestra in primo piano.
- **Niente impaginazione e niente modalità di vista**: non si propongono come miglioramenti di
  passaggio.

## 🏛️ Com'è fatto, e che cosa è stato scartato

**Com'è fatto.** Tre target SwiftPM: `EPUBKit` (lettura dell'EPUB, senza interfaccia),
`AomidoriCore` (logica senza AppKit, quindi provabile ovunque) e `Aomidori` (l'app AppKit e
WebKit). Un `NSDocument` di sola lettura per libro, un `WKWebView` per finestra riusato per ogni
capitolo, le risorse servite da un `WKURLSchemeHandler` direttamente dallo ZIP, senza estrarre
niente. Lo script della pagina (`ReaderScript`) è **uno solo** e lo condividono il lettore e la
Playground CSS: un comportamento della pagina si cambia lì, una volta.

**⚠️ Trappole**
- La de-offuscazione dei font (IDPF e Adobe) è portata da foliate-js, licenza MIT: la nota vive in
  `THIRD_PARTY.md`, e chi porta altro codice di terzi aggiunge la sua nota nello stesso giro.
- Gli `!important` del primo livello di cascata dichiarato battono ogni altra regola d'autore
  (CSS Cascade 5): per questo il livello `aomidori` si dichiara prima di tutto. Solo un
  `!important` in linea vincerebbe ancora, e lo script lo mette da parte finché serve.
- Un font installato non si può usare **per nome** dentro il `WKWebView` in modo affidabile:
  il font personalizzato si carica dal file. I font che arrivano solo per nome (le collezioni
  `.ttc`) dipendono da WebKit.
- Le funzioni della sezione Tipografia del pannello font di macOS che non hanno un equivalente
  OpenType si perdono. ⚠️ macOS scarta da sé una funzione che il font non ha: un font creato
  col maiuscoletto da Hoefler Text, Georgia o Optima non porta nessuna impostazione. La prova
  del maiuscoletto Apple usa Baskerville, che ce l'ha (verificato il 2026-10-10, 0.61).
- **La pagina non esce mai dal libro**: una lista di regole di WebKit (`OfflineRules` in
  `PageRenderer.swift`) blocca ogni risorsa che non sia `aomidori:`, `data:`, `blob:` o
  `about:`, perché un EPUB che carica un'immagine dalla rete sa quando e dove viene letto. Vale
  anche per gli stili dell'utente: un font va nella cartella `Fonts`, non su un server. ⚠️ Le
  regole non ammettono l'alternativa `a|b` nei filtri: una regola per schema, o la lista non
  si compila e non blocca niente (successo nella prima stesura, fermato dalla prova del lettore).

**Tentativi scartati**, da non riproporre:
- **Readium** e l'**impaginatore di foliate-js**: pesanti e pensati per l'impaginazione, che
  questo lettore non fa.
- Per la dimensione del testo: moltiplicare la dimensione del font della radice (perde contro
  ogni misura in px e ogni `min()` o `clamp()`, come quelli di `ReadingRoccobot.css`); riscrivere
  in linea la dimensione calcolata di ogni elemento (salta gli pseudo-elementi e va rifatto a
  ogni cambio); `-webkit-text-size-adjust` (su macOS non fa niente); `pageZoom` o l'ingrandimento
  della vista (ingrandiscono anche le immagini). Resta lo `zoom` sul `body`.
- Un progetto `.xcodeproj`: non serve finché non servono firma con Developer ID, notarizzazione o
  sandbox. Quel giorno si propone a Rocco, non si crea da sé.

## ⌨️ Le scorciatoie

**Com'è fatto.** Tutte vivono nella tabella di `Sources/AomidoriCore/Shortcuts.swift`, con
l'ambito di ciascuna (ovunque, solo fuori dalla Playground, solo nella Playground);
`ShortcutsTests` fallisce se due comandi dello stesso ambito si scontrano. Il menu le legge da
lì. L'elenco completo è nel `README.md`: qui non si ricopia.

**Decisioni di Rocco** (non si cambiano senza chiederglielo):
- `⌘T` apre una tab nuova vuota, come in Safari e nel Finder.
- `⇧⌘T` apre la scelta del font personalizzato; il pannello font di sistema si apre dal suo
  pulsante e dal menu Stile.
- `⌘Y` passa dal font del libro o dello stile al font personalizzato e viceversa (in tutte le
  finestre; fino alla 0.52 era `⌘S`). `⌘S` resta libero nel lettore, per la vista divisa
  (Split) che verrà; nella Playground `⌘S` resta Salva, perché lì un file si scrive davvero.
- `⌘←` / `⌘→` vanno indietro e avanti nella cronologia dei link seguiti (note, capitoli,
  ancore), alla posizione esatta; `⌘[` / `⌘]` restano come alias. Spenti mentre si scrive in
  un campo di testo o nell'editor della Playground, dove muovono il cursore. `←` / `→` da soli
  restano i capitoli.
- `⌘G` / `⇧⌘G`: risultato di ricerca successivo e precedente, anche in altri capitoli; senza
  una ricerca, `⌘G` apre la ricerca.
- Chiaro e scuro seguono l'aspetto di macOS. `⇧⌘N`, il sole nella barra e `T` da solo nel
  lettore passano all'altro aspetto, per l'app e per il testo insieme; quando la scelta coincide
  con quello di sistema, si torna a seguire macOS. `T` non vale in un campo di testo, nel campo
  di ricerca e nell'editor della Playground.
- `⌘R` ricarica capitolo, immagini, font e stile, e lascia il lettore nel punto in cui era.
- **Il testo corrente è a bandiera a sinistra**, sopra qualunque CSS, del libro e degli stili
  suoi (`ReadingRoccobot.css` giustifica, e resta intatto: lo scavalca lo strato del lettore);
  `⌘J`, la voce del menu Stile e il pulsante nella barra **passano al giustificato e
  ritornano**, per tutte le finestre, e la scelta è ricordata. Centrati e allineati a destra non
  si toccano (sue scelte del 2026-10-10: P1, e *è un commutatore sinistra ↔ giustificato*).
- **La sillabazione segue l'allineamento**, sopra qualunque CSS: spenta a bandiera, dove ogni
  trattino sporge dal margine irregolare (restano i trattini morbidi del libro), accesa col
  giustificato, dove serve a tenere uniformi gli spazi (sua scelta A1 del 2026-10-10, nella
  0.71, e sua precisazione: col giustificato *può andare (e in un certo senso deve)*). ⚠️ La
  0.70 non spezzava più parole della 0.62: lo stesso capitolo in WebKit ne spezza tante
  giustificato quante a bandiera, e a bandiera si notano di più.

## 🖌️ Icona e decorazione: sono di Graphe

- L'icona (in `Resources/Icon/`) e la decorazione della finestra vuota (in
  `Resources/EmptyState/`) sono disegni di **Graphe**, l'agente grafico di Rocco, approvati da
  lui. Valgono le regole universali sulla grafica: niente ritagli, niente pixel spostati, niente
  colori cambiati nei file.
- Un ritocco al disegno si chiede a Graphe; qui si cambia solo come il disegno entra nell'app
  (`Resources/Icon/AppIcon.icon/icon.json`, i colori dell'interfaccia attorno).
- La cornice tratteggiata della zona di rilascio si disegna nel codice, a ogni dimensione, con
  la regola di Graphe (`DashedFrame`): perimetro reale del rettangolo arrotondato, numero di
  trattini intero attorno a trattino 10 + spazio 12 con linea da 2 pt, trattino e spazio
  ricalcolati perché il motivo chiuda su se stesso, un trattino centrato in alto al centro
  (dove parte il tracciato), capi arrotondati compensati. Il libro è l'SVG di Graphe
  (`aomidori-dropzone-book.svg`), i PNG restano come riserva.
- **⚠️ Trappole**: in `icon.json` il primo elemento di `groups` e di `layers` è quello disegnato
  sopra; i colori dei livelli vengono da `fill-specializations` e non dagli SVG; la sfumatura
  diagonale non si può esprimere e scorre dall'alto in basso. Queste due differenze dal progetto di
  Graphe sono state dichiarate a Rocco.
- Le rese si fanno con l'`ictool` che vive dentro Icon Composer: quello che trova
  `xcrun --find ictool` non conosce `--export-image`.

## 💻 Il Mac di Rocco

Il Mac su cui si compila e si prova è il **computer personale di Rocco**, che lo usa mentre gli
agenti lavorano (sua richiesta: *avvisami quando lo fai, perché devo lasciarti i comandi*).

- **Prima di ogni sessione** si scrive in chat che cosa si farà, per quanto, e che cosa vedrà o
  sentirà (il processore sotto carico, un libro aggiunto ai recenti, i nomi dei suoi libri recenti
  nelle schermate di prova), e si aspetta il via. Un via vale per la sessione annunciata. Nella
  stessa domanda si chiede, se serve, di lanciare `caffeinate` (`Roccobot.md` § '☕ Le sessioni
  locali e `caffeinate`').
- **Due modi di lavorare.** Una sessione **remota** (Grok Bot, dal box) scrive e prova sul box
  tutto il possibile e va sul Mac solo per compilare, per le prove che solo macOS può fare e per lo
  ZIP: il lavoro si raggruppa in poche sessioni. Una sessione **locale** (Claude Code sul Mac)
  lavora nel clone `~/Developer/Aomidori`, con `tools` e l'hub clonati accanto, e compila e prova
  quando serve, in background.
- **Solo in background**: l'app di prova è la copia nella cartella di build, avviata con
  `open -g -n`, dietro le sue finestre. Rocco può usare il Mac mentre si lavora così; lo lascia
  solo per una prova in primo piano, che si annuncia e si chiede a parte.
- ⚠️⚠️ **La copia installata in `~/Applications/Aomidori.app` non si tocca mai**: né sostituita,
  né chiusa, né avviata. Gli script di prova chiudono solo l'eseguibile della build.
- **Le sue impostazioni e la sua cartella stili non si toccano**, e dalla 0.62 lo garantisce il
  codice: ogni sessione scriptata (prove e schermate) usa una cartella di supporto sua, `Support`
  dentro la cartella di uscita, e impostazioni sue, azzerate all'avvio (`AppPaths.smokeFolder`,
  `ReaderEnvironment.sessionSuite`). La copia di prova ha lo stesso identificativo della sua app,
  quindi senza questo leggerebbe e scriverebbe le sue preferenze.
- **Lo ZIP si fa e si riporta nella stessa sessione** della prova, così il file pubblicato è
  quello provato.
- **⚠️ Trappole**: macOS non lascia premere tasti a un agente al posto di Rocco, quindi le prove
  di tastiera e di trackpad con l'app in primo piano le fa lui; una cattura fatta in background può
  mostrare difetti che a schermo non ci sono, quindi un difetto visto solo in una cattura si fa
  confermare a Rocco. Il minimo reale della finestra vuota include la barra degli strumenti, che AppKit
  aggiunge al contenuto. Una cattura di finestra (`screencapture -l`) chiede il permesso di
  Registrazione schermo per Claude, dato da Rocco il 2026-10-10; e una finestra catturata quando
  non è attiva ha i pulsanti grigi e i testi spenti, quindi `scripts/screenshots.sh` la porta
  davanti con `open` e controlla la misura di ogni cattura.
- Alla fine si dice in chat **a che ora si è lasciato il Mac**.

## 🧰 Build e prove

- **Build**: `scripts/bundle.sh` costruisce in release e assembla `build/Aomidori.app`, firmata ad
  hoc. Con Xcode 27 compila anche l'icona Liquid Glass in `Assets.car`; con i soli Command Line
  Tools resta l'icona piatta di riserva.
- **Prove unitarie**: `scripts/test.sh`, che sulle Command Line Tools aggiunge i percorsi di Swift
  Testing; altrove `swift test`. `EPUBKit` e `AomidoriCore` si provano anche sul box Linux.
- **Prove della pagina**: `scripts/js-tests/` (`npm test`), lo script della pagina in WebKit con
  Playwright, che scarica il suo WebKit. ⚠️ Girano nel mondo principale con JavaScript attivo,
  non nel mondo isolato dell'app: per un comportamento dello script fa fede `smoke-reader.sh`.
- **Prove sul Mac**: `smoke-launch.sh` (finestra vuota, libro chiuso liberato dalla memoria),
  `smoke-reader.sh` (copertina centrata, posizione per capitolo, avviso di fine capitolo,
  cronologia anche coi link `target="_blank"`, pagina che non esce dal libro, marchi falsi del
  libro), `smoke-playground.sh` (di nuovo utilizzabile dalla 0.62, perché salva nella sua
  cartella di supporto) e `check-icon.sh` (le sei rese dell'icona e il contenuto di
  `Assets.car`). Un difetto trovato da Rocco torna con la prova che lo avrebbe fermato.
- **Controlli delle regole**: in ogni clone si attivano gli hook con
  `git config core.hooksPath .githooks` (i due file sono quelli dell'hub e passano il lavoro a
  `githook.py` di `roccobot.github.io`, clonato accanto); l'Action `rules-check` rifà gli stessi
  controlli su GitHub a ogni push. In una sessione remota la copia sul Mac si aggiorna con un
  tarball di `git archive` e i commit si fanno dal box, quindi gli hook servono nel clone del box;
  in una sessione locale servono nel clone del Mac.
- **Il libro di prova** è *Una descrizione di Terramare*, sul Mac in `~/Developer/aomidori-test/`,
  e non entra nel repo. Per le schermate del sito, che è pubblico, serve un libro di pubblico
  dominio.
- ⚠️ Nel repo non entrano libri, font coperti da diritti né percorsi del Mac di Rocco: il repo è
  pubblico.

## 🚀 Che cosa produce un rilascio

- **Versione**: SlimVer `x.xx`, come in ogni progetto di Rocco (sua decisione del 2026-10-09):
  +0,01 ritocco, +0,1 funzionalità, +1,00 release maggiore. Fino alla `0.5.0` le versioni
  erano in forma `X.Y.Z`; la numerazione prima dell'1.00 prosegue da `0.51`, che segue la `0.5.0`
  e la supera anche nel confronto numerico. `CFBundleShortVersionString` in
  `Resources/Info.plist` è la fonte unica; `CFBundleVersion` è il numero di build e sale di uno a
  ogni versione pubblicata. Il commit di versione è l'**ultimo** prima del rilascio.
- **Il file**: `Aomidori-x.xx.zip`, fatto da `scripts/release.sh` (`ditto -c -k --keepParent`)
  dalla build provata, mai da una build rifatta dopo la prova, e firmato per Sparkle nello stesso
  giro (§ '🔄 Aggiornamenti automatici').
- **La release**: `gh release create vx.xx` con lo ZIP e le note in inglese, **prima** di
  pubblicare l'appcast. La release si verifica col suo tag e lo ZIP allegato; il sito la trova da
  sé (§ '🌐 Il sito').
- **L'app è firmata ad hoc**, non con Developer ID: alla prima apertura macOS la blocca, e si apre
  da Impostazioni di Sistema, Privacy e sicurezza, *Apri comunque* (oppure togliendo la quarantena
  con `xattr -dr com.apple.quarantine` sull'app). Il clic destro e Apri non basta più sui macOS
  recenti. Chi scrive note o pagine per altri lo dice. Gli aggiornamenti installati da Sparkle non chiedono di nuovo.

## 🔄 Aggiornamenti automatici

- **Sparkle 2**, voluto da Rocco dalla `0.52` (2026-10-09), dal pacchetto binario ufficiale
  via SwiftPM, solo su macOS. `scripts/bundle.sh` mette `Sparkle.framework` (ridotto ad arm64) in
  `Contents/Frameworks`, dove punta l'rpath `@executable_path/../Frameworks` di `Package.swift`, e
  firma ad hoc dall'interno verso l'esterno: `Downloader.xpc` (con i suoi entitlement),
  `Installer.xpc`, `Autoupdate`, `Updater.app`, il framework, l'app. Mai `--deep` per firmare;
  `codesign --verify --deep --strict` solo per verificare.
- **Comportamento di Sparkle, non nostro**: al secondo avvio Sparkle chiede una volta se cercare
  da solo gli aggiornamenti, poi controlla una volta al giorno (`SUScheduledCheckInterval`).
  `SUEnableAutomaticChecks` resta assente apposta, perché metterlo salterebbe la domanda. La voce
  *Controlla aggiornamenti...* è nel menu dell'app, senza scorciatoia, come nelle altre app Mac.
- **L'appcast** è `publish/appcast.xml`, servito su <https://roccobot.github.io/Aomidori/appcast.xml>
  (`SUFeedURL`, e `UpdatePolicy.feedURL` che una prova confronta). Ogni voce punta allo ZIP della
  release su GitHub e alla pagina della release per le note.
- **Nelle prove l'updater è spento** (`UpdatePolicy`): le sessioni scriptate sul Mac di Rocco non
  devono parlare col feed né scrivere le impostazioni di Sparkle nelle sue preferenze. Resta spento
  anche senza una chiave pubblica valida.
- ⚠️⚠️ **La chiave privata EdDSA** firma ogni ZIP, e con un'app firmata ad hoc è l'**unica** prova
  che un aggiornamento viene da Rocco: Sparkle accetta l'aggiornamento se la firma EdDSA torna con
  `SUPublicEDKey` della copia installata e se la firma ad hoc del nuovo bundle è valida. La chiave
  vive nel Portachiavi del Mac di Rocco (`generate_keys --account aomidori`) e in una copia di
  riserva (`generate_keys -x`) che custodisce lui. Non entra mai nel repo né in chat, e non resta
  in un file, né sul box né sul Mac: se ci passa per arrivare a Rocco, si cancella appena lui
  l'ha. Persa la chiave, nessuna copia installata accetta più aggiornamenti: si rimette a mano una versione con
  una chiave nuova.
- **Quarantena e Gatekeeper**: l'installatore di Sparkle toglie la quarantena dal bundle nuovo
  prima di sostituire il vecchio, quindi un aggiornamento non riapre l'avviso di Gatekeeper.
  Lo si è letto nel sorgente di Sparkle (`SUPlainInstaller`); su macOS 27 lo conferma il primo
  aggiornamento vero.
- **La `0.52` si installa a mano una volta**: le versioni precedenti non hanno Sparkle. Gli
  aggiornamenti funzionano dalla `0.52` in poi, e le note della `0.52` lo dicono.
- **I passi del rilascio**: i primi due sul Mac, gli altri dal clone con la storia e `gh`. In una
  sessione remota è il box, e lo ZIP e `publish/appcast.xml` tornano dal Mac nella stessa
  sessione; in una sessione locale è lo stesso Mac:
  1. `scripts/bundle.sh`, poi le prove (§ '🧰 Build e prove').
  2. `scripts/release.sh`: verifica le firme, fa lo ZIP, lo firma con `sign_update` (dal
     Portachiavi, account `aomidori`, o da `ED_KEY_FILE`) e aggiunge la voce a
     `publish/appcast.xml` con `scripts/appcast.py`: `sparkle:version` (`CFBundleVersion`),
     `shortVersionString`, `length`, `edSignature` e `minimumSystemVersion` `27.0`. Rifiuta un
     tag che esiste già su GitHub, un `ED_KEY_FILE` dentro il repo e non ignorato, una firma che
     non si verifica con `SUPublicEDKey` (`scripts/verify-signature.swift`, con CryptoKit,
     qualunque chiave l'abbia fatta), e una build non più alta di quelle dell'appcast.
  3. `gh release create vx.xx` con lo ZIP: prima la release, così lo ZIP esiste già quando le copie
     installate vedono la voce.
  4. Commit di `publish/appcast.xml` (`chore(appcast): ...`) e push su `main`: GitHub Pages lo
     pubblica, e da lì Sparkle lo trova.
- La prima volta `sign_update` può far chiedere a macOS il permesso di usare la chiave del
  Portachiavi: è una finestra per Rocco, che risponde *Consenti sempre*.

## 🗣️ Commit e note di rilascio in inglese: deroga dichiarata

- Le regole universali vogliono i messaggi di commit in italiano. In questo repo Rocco ha
  dichiarato una **deroga** (2026-10-09): messaggi di commit e note di rilascio sono in
  **inglese**, perché il repo, il `README.md` e il sito sono pubblici e in inglese. Tutto quello che
  Rocco legge in chat resta in italiano.
- I messaggi seguono **Conventional Commits** (`feat(reader): ...`, `fix(inspector): ...`,
  `chore: version 0.51 (build 8)`), con un corpo che dice il perché.
- **Autore** `Rocco Casadei <roccobot@gmail.com>`, e in fondo la riga **`Agent:`** con chi ha
  scritto il commit, come vuole la regola universale: `Agent: Techne` per l'agente di Grok Bot che
  ha sviluppato Aomidori fino alla 0.60, `Agent: Claude Code` per Claude Code.
- Un commit per argomento: icona, menu, finestra, script e versione non si mescolano.

## ⚖️ Licenza

- **Nessuna licenza, per ora** (decisione di Rocco del 2026-10-09): il codice è pubblico ma
  con tutti i diritti riservati. Un file `LICENSE`, o una licenza nominata nel `README.md` o nel
  sito, entra solo con una sua decisione.
- `THIRD_PARTY.md` resta: la de-offuscazione dei font portata da foliate-js è sotto licenza MIT,
  che chiede di conservarne la nota, ed entra anche nell'app.

## 🌐 Il sito

- La pagina di download vive in `publish/` ed è servita da GitHub Pages su
  <https://roccobot.github.io/Aomidori/> con `.github/workflows/pages.yml`, che parte solo quando
  cambia `publish/`. Rocco l'ha approvata così com'è.
- **Un rilascio non chiede deploy**: la pagina chiede a `releases/latest` dell'API di GitHub il
  nome e la dimensione dello ZIP mentre si carica. Per questo una versione si pubblica come
  release normale, mai come pre-release o bozza, che `releases/latest` salta.
- **Le schermate** della pagina sono quattro file in `publish/assets/`, una per lingua e tema:
  `screenshot-it-light.png`, `screenshot-it-dark.png`, `screenshot-en-light.png`,
  `screenshot-en-dark.png`, verticali di 1600 x 1780 pixel e **senza barra laterale**. Le fa
  `scripts/screenshots.sh` sul Mac, in primo piano e con il via di Rocco, con un libro di
  pubblico dominio per lingua (*Le avventure di Pinocchio* e *Alice's Adventures in Wonderland*
  da Project Gutenberg, in `~/Developer/aomidori-test/`), al capitolo II. `assets/preview.png`
  (1200 x 630) è l'anteprima dei link condivisi: l'icona resa da Icon Composer e la schermata
  inglese chiara, intere. Finché una schermata manca il suo posto resta nascosto.
- **Dove cade la schermata** (richieste di Rocco del 2026-10-10, dopo un primo giro quadrato che
  aveva capito male): due colonne uguali nella larghezza normale del sito; la schermata è larga
  quanto la colonna destra, il bordo alto è sul riquadro dell'icona e il bordo basso alla fine
  dei passi d'installazione, prima della spaziatura delle schede. La proporzione viene da lì:
  428 x 476 px, misurata in italiano e in inglese col font della pagina. ⚠️ Un testo che allunga
  o accorcia la colonna sinistra (il claim, i passi) cambia la misura: si rimisura e si rifanno
  le schermate (`ScreenshotSession.contentSize`).
- **Come AIV**: la schermata ha un'ombra in chiaro e un bagliore verde in scuro, e si allinea
  con l'immagine, non con l'ombra.
- **Testi**: quelli inglesi sono scritti nella pagina, così si legge e si indicizza anche senza
  JavaScript; lo script passa all'italiano per un browser italiano, titolo e descrizione
  compresi. **Niente note di versione** nella pagina, come in AIV (scelta di Rocco del
  2026-10-10). La favicon è il glifo dell'icona nel suo colore istituzionale `#43B59E`.
- Nella pagina valgono le regole universali del web: mai `innerHTML`, testi con `textContent`.

## 🌿 Branch e tag

- Si lavora su `main`; un branch di lavoro locale si cancella quando il lavoro è entrato.
- ⚠️ **Mai un branch con lo stesso nome di un tag** (`v0.5.0`): git e GitHub li confondono nei
  comandi che accettano tutti e due.

## 🚧 Limiti noti e punti aperti

L'elenco aggiornato vive nella sezione *Known limits* del `README.md`; qui restano solo quelli
che decidono il lavoro:

- La sezione Tipografia del pannello font di macOS va verificata a mano da Rocco.
- I due angoli neri sulla scheda attiva, visti solo in una cattura della 0.5.0: da confermare a
  schermo da Rocco prima di cercarne la causa.
- Le prove di barra spaziatrice, trackpad e scorciatoie con l'app in primo piano sono sue.
- La distribuzione firmata e notarizzata (Developer ID) non c'è: quando servirà, servirà anche il
  progetto Xcode.
