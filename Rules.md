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
  pulsante Apri, la lista dei libri recenti (solo il nome del file, mai il percorso). Appare
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
  OpenType si perdono; il maiuscoletto dei vecchi font Apple non è verificato.

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
- `⌘S` passa dal font del libro o dello stile al font personalizzato e viceversa, perché un
  lettore non salva file. Solo nella Playground `⌘S` resta Salva, perché lì un file si scrive
  davvero.
- `⌘R` ricarica capitolo, immagini, font e stile, e lascia il lettore nel punto in cui era.

## 🖌️ Icona e decorazione: sono di Graphe

- L'icona (in `Resources/Icon/`) e la decorazione della finestra vuota (in
  `Resources/EmptyState/`) sono disegni di **Graphe**, l'agente grafico di Rocco, approvati da
  lui. Valgono le regole universali sulla grafica: niente ritagli, niente pixel spostati, niente
  colori cambiati nei file.
- Un ritocco al disegno si chiede a Graphe; qui si cambia solo come il disegno entra nell'app
  (`AppIcon.icon/icon.json`, i colori dell'interfaccia attorno).
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
  nelle schermate di prova), e si aspetta il via. Un via vale per la sessione annunciata.
- **Il lavoro si raggruppa** in poche sessioni: si scrive e si prova tutto il possibile sul box,
  e si va sul Mac per compilare, per le prove che solo macOS può fare e per lo ZIP.
- **Solo in background**: l'app di prova è la copia nella cartella di build, avviata con
  `open -g -n`, dietro le sue finestre. Una prova in primo piano si chiede a parte.
- ⚠️⚠️ **La copia installata in `~/Applications/Aomidori.app` non si tocca mai**: né sostituita,
  né chiusa, né avviata. Gli script di prova chiudono solo l'eseguibile della build.
- **Le sue impostazioni e la sua cartella stili non si toccano**: le prove tengono posizioni e
  stato nella cartella di uscita.
- **Lo ZIP si fa e si riporta nella stessa sessione** della prova, così il file pubblicato è
  quello provato.
- **⚠️ Trappole**: macOS non lascia premere tasti a un agente al posto di Rocco, quindi le prove
  di tastiera e di trackpad con l'app in primo piano le fa lui; una cattura fatta in background può
  mostrare difetti che a schermo non ci sono, quindi un difetto visto solo in una cattura si fa
  confermare a Rocco. Il minimo reale della finestra vuota include la barra degli strumenti, che AppKit
  aggiunge al contenuto.
- Alla fine si dice in chat **a che ora si è lasciato il Mac**.

## 🧰 Build e prove

- **Build**: `scripts/bundle.sh` costruisce in release e assembla `build/Aomidori.app`, firmata ad
  hoc. Con Xcode 27 compila anche l'icona Liquid Glass in `Assets.car`; con i soli Command Line
  Tools resta l'icona piatta di riserva.
- **Prove unitarie**: `scripts/test.sh`, che sulle Command Line Tools aggiunge i percorsi di Swift
  Testing; altrove `swift test`. `EPUBKit` e `AomidoriCore` si provano anche sul box Linux.
- **Prove della pagina**: `scripts/js-tests/` (`npm test`), lo script della pagina in WebKit con
  Playwright, sul box.
- **Prove sul Mac**: `smoke-launch.sh` (finestra vuota), `smoke-reader.sh` (copertina centrata,
  posizione per capitolo, avviso di fine capitolo), `smoke-playground.sh` e `check-icon.sh`
  (le sei rese dell'icona e il contenuto di `Assets.car`). Un difetto trovato da Rocco torna con la
  prova che lo avrebbe fermato.
- **Controlli delle regole**: in ogni clone si attivano gli hook con
  `git config core.hooksPath .githooks` (i due file sono quelli dell'hub e passano il lavoro a
  `githook.py` di `roccobot.github.io`, clonato accanto); l'Action `rules-check` rifà gli stessi
  controlli su GitHub a ogni push. La copia sul Mac di Rocco si aggiorna con un tarball di
  `git archive` e i commit si fanno dal box, quindi gli hook servono nel clone del box.
- **Il libro di prova** è *Una descrizione di Terramare*, e non entra nel repo.
- ⚠️ Nel repo non entrano libri, font coperti da diritti né percorsi del Mac di Rocco: il repo è
  pubblico.

## 🚀 Che cosa produce un rilascio

- **Versione**: SlimVer `x.xx`, come in ogni progetto di Rocco (sua decisione del 9 ottobre
  2026): +0,01 ritocco, +0,1 funzionalità, +1,00 release maggiore. Fino alla `0.5.0` le versioni
  erano in forma `X.Y.Z`; la numerazione prima dell'1.00 prosegue da `0.51`, che segue la `0.5.0`
  e la supera anche nel confronto numerico. `CFBundleShortVersionString` in
  `Resources/Info.plist` è la fonte unica; `CFBundleVersion` è il numero di build e sale di uno a
  ogni versione pubblicata. Il commit di versione è l'**ultimo** prima del rilascio.
- **Il file**: `Aomidori-x.xx.zip`, fatto con `ditto -c -k --keepParent` dalla build provata, mai
  da una build rifatta dopo la prova.
- **La release**: `gh release create vx.xx` con lo ZIP e le note in inglese. La release si
  verifica col suo tag e lo ZIP allegato; il sito la trova da sé (§ '🌐 Il sito').
- **L'app è firmata ad hoc**, non con Developer ID: alla prima apertura macOS la blocca, e si apre
  col clic destro e Apri (o da Impostazioni di Sistema, Privacy e sicurezza). Chi scrive note o
  pagine per altri lo dice.

## 🗣️ Commit e note di rilascio in inglese: deroga dichiarata

- Le regole universali vogliono i messaggi di commit in italiano. In questo repo Rocco ha
  dichiarato una **deroga** (9 ottobre 2026): messaggi di commit e note di rilascio sono in
  **inglese**, perché il repo, il `README.md` e il sito sono pubblici e in inglese. Tutto quello che
  Rocco legge in chat resta in italiano.
- I messaggi seguono **Conventional Commits** (`feat(reader): ...`, `fix(inspector): ...`,
  `chore: version 0.51 (build 8)`), con un corpo che dice il perché.
- **Autore** `Rocco Casadei <roccobot@gmail.com>`, e in fondo la riga **`Agent: Techne`**: Techne
  è l'agente di Grok Bot che sviluppa Aomidori, e la riga dice chi ha scritto il commit, come vuole
  la regola universale `Agent:`.
- Un commit per argomento: icona, menu, finestra, script e versione non si mescolano.

## ⚖️ Licenza

- **Nessuna licenza, per ora** (decisione di Rocco del 9 ottobre 2026): il codice è pubblico ma
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
- Nella pagina valgono le regole universali del web: mai `innerHTML`, testi con `textContent`.

## 🌿 Branch e tag

- Si lavora su `main`; un branch di lavoro locale si cancella quando il lavoro è entrato.
- ⚠️ **Mai un branch con lo stesso nome di un tag** (`v0.5.0`): git e GitHub li confondono nei
  comandi che accettano tutti e due.

## 🚧 Limiti noti e punti aperti

L'elenco aggiornato vive nel `README.md`, § 'Known limits'; qui restano solo quelli che decidono
il lavoro:

- La sezione Tipografia del pannello font di macOS va verificata a mano da Rocco.
- Le prove di barra spaziatrice, trackpad e scorciatoie con l'app in primo piano sono sue.
- La distribuzione firmata e notarizzata (Developer ID) non c'è: quando servirà, servirà anche il
  progetto Xcode.
