# CLAUDE.md: le regole di `Aomidori` per Claude

@AGENTS.md
@Rules.md

> Le regole di questo repo valgono per tutti gli agenti e vivono in `AGENTS.md` (il nucleo) e in
> `Rules.md` (il testo completo): Claude Code le carica tutte e due con le due righe qui sopra.
> Qui resta solo quello che vale per Claude.

- Il protocollo di avvio di Claude (permessi, hook, domande iniziali, brief) vive in `Rules.md`
  del repo `roccobot.github.io`, che è l'hub, § '🚀 Protocollo di avvio'.
- Questo repo non ha skill proprie né un `.claude/settings.json`: i controlli automatici li fa il
  dispatcher `hooks.py` dell'hub, quando è installato nelle impostazioni utente.
