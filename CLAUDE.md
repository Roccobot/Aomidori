# CLAUDE.md: le regole di `Aomidori` per Claude

@AGENTS.md

> Le regole di questo repo valgono per tutti gli agenti e vivono in `AGENTS.md` (il nucleo) e in
> `Rules.md` (il testo completo). Claude Code carica da sé il solo `AGENTS.md`, con la riga qui
> sopra: `Rules.md` si legge per intero prima di lavorare su una cosa di cui parla, e i rimandi del
> nucleo dicono in quale sezione (scelta C1 dell'utente, 2026-10-10: prima lo caricava sempre, in
> ogni sessione che montava il repo, anche quando il lavoro era altrove).
> Qui resta solo quello che vale per Claude.

- Il protocollo di avvio di Claude (permessi, hook, domande iniziali, brief) vive in `Rules.md`
  del repo `roccobot.github.io`, che è l'hub, § '🚀 Protocollo di avvio'.
- Questo repo non ha skill proprie né un `.claude/settings.json`: i controlli automatici li fa il
  dispatcher `hooks.py` dell'hub, quando è installato nelle impostazioni utente.
