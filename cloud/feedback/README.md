# Salvataggio cloud del documento di feedback

La soluzione scelta usa **Supabase Free** per database e allegati e **Cloudflare Workers
Free** per pagina e accesso GitHub. R2 non va attivato. Cloudflare è un servizio statunitense,
già usato per il Worker delle regole; questo servizio è separato e non modifica `rules-proxy`.
Il codice vive su GitHub, che non conserva le risposte private.

Il servizio usa il database PostgreSQL e il bucket privato Supabase: nessun binding R2.
Prima di distribuire, il workflow verifica SQL, privilegi, due sessioni del browser,
credenziali dell'app GitHub e salvataggio/conflitti/allegati sul progetto Supabase reale.
La pagina GitHub conserva la bozza locale finché il proprietario non la trasferisce nel
cloud e ne conferma il recupero su un secondo dispositivo.

Supabase richiede un dominio personalizzato a pagamento per servire HTML dalle funzioni:
vedi [limiti delle funzioni](https://supabase.com/docs/guides/functions/limits) e
[domini personalizzati](https://supabase.com/docs/guides/platform/custom-domains).
Il Worker gratuito permette pagina e API sulla stessa origine, con cookie riservati al
server e senza problemi di cookie tra siti su Safari. Supabase rimane l'archivio dei dati.

L'accesso GitHub ammette soltanto l'ID pubblico `10722164` (Roccobot). Non chiede accesso ai
repository: serve solo a riconoscere il proprietario. Il cookie di sessione è Secure,
HttpOnly, SameSite=Lax, scade dopo sette giorni. Token e secret rimangono sul server;
nessuna credenziale di GitHub o Cloudflare entra nei file pubblicati o nella memoria
persistente del browser. Le scritture richiedono l'origine corretta e una versione ETag.

Il documento sul Worker usa il cloud come unica memoria persistente. La copia su GitHub Pages
non è più pubblicata dal 2026-10-03: una vecchia bozza locale, se mai servisse, si recupera
aprendo in locale la pagina presa dalla storia git, esportando il JSON e importandolo sul Worker.
Il JSON di esportazione conserva il formato originale con allegati completi. Non trasferire
mai feedback personali o allegati nei commit del repository pubblico.

## Preparazione

Il servizio è pubblicato su
[Documento di feedback di Aomidori](https://aomidori-feedback.roccobot-b90.workers.dev/feedback).
È una copia di quello di AIV (scelta M1 di Rocco, 2026-10-10), e usa **lo stesso progetto
Supabase** di AIV (scelta N1), con tabelle, funzioni e bucket che cominciano con
`aomidori_` e `aomidori-`: i dati dei due documenti restano separati per nome, e lo script
di Aomidori non tocca niente di AIV. Il workflow verifica l'archivio remoto e l'accesso
anonimo negato prima di confermare la pubblicazione. I valori segreti vanno inseriti nei
campi riservati, mai in chat o nel repository.

1. Nel progetto Supabase di AIV, in Storage, crea il bucket privato `aomidori-feedback`.
2. Apri [supabase-setup.sql](supabase-setup.sql), copia tutto il contenuto e incollalo in
   SQL Editor, New query. Premi Run e verifica che l'esecuzione sia riuscita.
   Lo script crea la bozza corrente, la storia delle revisioni e il salvataggio atomico;
   configura anche il bucket privato. Si può rieseguire senza cancellare le risposte.
   Solo il ruolo server `service_role` ha accesso: nessuna chiave va nella pagina pubblica.
3. Registra su GitHub una OAuth App chiamata `Aomidori Feedback`, senza permessi sui
   repository, sullo stesso account di `AIV Feedback`: homepage
   `https://aomidori-feedback.roccobot-b90.workers.dev/feedback` e indirizzo di ritorno
   `https://aomidori-feedback.roccobot-b90.workers.dev/auth/callback`. Un'app OAuth ammette
   un solo indirizzo di ritorno, per questo serve un'app sua e non quella di AIV.
4. Il token Cloudflare di AIV vale anche qui (Workers Scripts: Edit e Account Settings: Read
   sullo stesso account); se preferisci, creane uno nuovo con gli stessi permessi.
5. In [Actions di Aomidori](https://github.com/Roccobot/Aomidori/settings/secrets/actions)
   configura:

   | Tipo | Nome | Contenuto |
   |---|---|---|
   | Secret | `CLOUDFLARE_API_TOKEN` | Token Cloudflare limitato all'account |
   | Secret | `FEEDBACK_GITHUB_CLIENT_SECRET` | Client secret dell'app `Aomidori Feedback` |
   | Secret | `FEEDBACK_SUPABASE_SECRET_KEY` | Secret key Supabase del progetto di AIV, con prefisso sb_secret_ |
   | Variable | `CLOUDFLARE_ACCOUNT_ID` | ID pubblico dell'account Cloudflare |
   | Variable | `FEEDBACK_GITHUB_CLIENT_ID` | Client ID pubblico dell'app `Aomidori Feedback` |

   La chiave Supabase rimane sul Worker. Il solo URL pubblico del progetto vive in
   `wrangler.toml`; non occorre una chiave pubblicabile nel browser.
6. Esegui [Feedback cloud](https://github.com/Roccobot/Aomidori/actions/workflows/feedback-cloud.yml).
   I controlli sul progetto reale usano il proprietario sintetico 0, separato dall'ID
   GitHub 10722164: non leggono né alterano il feedback del proprietario. Conservano poche
   revisioni sintetiche, eliminando il file di prova appena verificato. Il workflow genera
   la chiave di sessione al primo deploy e la conserva nei successivi. Il riepilogo mostra
   l'indirizzo effettivo, verificando pagina disponibile e lettura anonima negata.
7. Accedi all'indirizzo con GitHub, scrivi un commento di prova e attendi `Salvato nel
   cloud`; poi apri lo stesso indirizzo in un altro browser e controlla che il commento ci sia.

La pausa di Supabase non equivale a cancellazione. La
[guida attuale al recupero](https://github.com/supabase/supabase/blob/master/apps/docs/content/troubleshooting/restore-project-after-90-days-pause.mdx)
indica che oltre un anno di pausa serve scaricare database e oggetti Storage e migrarli in
un nuovo progetto. Una cancellazione elimina anche i backup. Non è una garanzia di
conservazione illimitata. Le revisioni nello stesso database aiutano a recuperare modifiche
precedenti, ma non costituiscono una copia indipendente dal progetto.

## Comportamento

- Salvataggio automatico dopo la scrittura, dischetto e Cmd/Ctrl+S. Il testo e i riferimenti
  viaggiano separati dagli allegati; gli originali sono caricati una volta, identificati da
  SHA-256 e verificati al recupero. Tre trasferimenti paralleli al massimo.
- Aggiornamento all'ingresso nella scheda e ogni 15 secondi quando non ci sono modifiche
  locali. Se due dispositivi modificano la stessa versione, il secondo salvataggio riceve
  un conflitto: il server conserva la nuova bozza e il campo conserva il testo locale.
  Esporta quest'ultimo prima di ricaricare; nessuna sovrascrittura silenziosa.
- Connessione necessaria per salvare. Un errore o una sessione scaduta non vengono indicati
  come salvataggio riuscito. Esporta il JSON per conservare le modifiche prima di chiudere.
- Il salvataggio cloud conserva la bozza, senza consegnare automaticamente il giro all'agente.
  `Invia` rende leggibile il giro, senza avviare letture o lavori. Dopo il via in chat,
  l'agente lo recupera con `scripts/feedback-read.mjs`, tramite workflow manuale e trasferimento
  cifrato. Il proprietario può modificare e inviare di nuovo fino alla presa in carico;
  il JSON manuale rimane una copia facoltativa. Vedi la
  [guida comune](../../docs/Feedback-maintenance.md#invio-e-presa-in-carico-due-fasi).
- Stessi limiti: 8 MB per file, 20 MB di allegati nella bozza, 30 file per riquadro. Reset con
  conferma riguarda la bozza su tutti i dispositivi. Gli oggetti originali scollegati restano
  privati nel bucket: non vengono cancellati in modo concorrente a un altro salvataggio.
  Lo spazio fisico può quindi superare i 20 MB della bozza; va monitorato nel servizio attivo.
- Ogni salvataggio mantiene una revisione del testo e dei riferimenti agli allegati nel
  database. Lo spazio di revisione si aggiunge alla bozza corrente; non viene cancellato
  automaticamente. Il recupero delle revisioni si effettua dal database, non dall'editor.
  Le revisioni nello stesso progetto non sostituiscono un backup indipendente.
- Nessuna misurazione di latenza o prova di accesso su un servizio pubblico è dichiarata
  finché il proprietario non ha configurato i campi necessari e il deploy è verificato.

## Verifica locale riproducibile

Dalla radice di Aomidori, Node 24 e Python con Playwright/Chromium:

```sh
npm ci --prefix cloud/feedback
npm --prefix cloud/feedback test
node cloud/feedback/supabase-test-server.mjs 8790
```

In un secondo terminale, dalla radice di Aomidori:

```sh
cloud/feedback/node_modules/.bin/wrangler dev --config cloud/feedback/wrangler.toml --local --port 8787 --var SUPABASE_URL:http://127.0.0.1:8790 --var SUPABASE_SECRET_KEY:development-supabase-test-key --var GITHUB_CLIENT_ID:local-test-id --var GITHUB_CLIENT_SECRET:local-test-secret --var SESSION_SECRET:development-test-secret
```

In un terzo terminale:

```sh
python3 scripts/feedback-cloud-check.py
python3 scripts/feedback-check.py publish/feedback.html
```

Il controllo cloud accetta solo localhost, firma una sessione di prova con la chiave
fittizia della riga sopra e usa il servizio HTTP locale con PostgreSQL reale e archivio di file fittizio. Non avvia OAuth di produzione e non tocca
risposte del proprietario. Non configurare mai la chiave di prova su un servizio pubblico.
