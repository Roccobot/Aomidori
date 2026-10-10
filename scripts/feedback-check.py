#!/usr/bin/env python3
"""Il documento di feedback prima di pubblicarlo: parte, e disegna quello che porta dentro.

⚠️⚠️ **NASCE DAL DIFETTO DEL GIRO DELLA `2.67`, ED È ARRIVATO A LUI**: la sezione del giro era
stata composta senza il campo `sotto`, la pagina ha letto `undefined.length` e si è spenta
**intera**, cioè il documento è comparso con la sola testata e nessuna voce. Non lo poteva vedere
nessuna rilettura del codice, perché il codice era valido: il campo mancava nei **dati**, e a
dirlo è soltanto aprire la pagina.

⚠️⚠️ **MISURA IL FILE CHE SI STA PER PUBBLICARE, e non lo script che lo compone**: gli script che
compongono un giro vivono nello scratchpad di una sessione e spariscono con lei, mentre il file
HTML è la cosa che arriva a lui. Così il presidio vale comunque sia stato costruito il documento.

⚠️ **I due controlli sono di specie diversa, e vanno tutti e due**: la **forma** dei dati si legge
dal file senza aprire niente (un campo che manca), e la **resa** vuole Chromium (la pagina che si
spegne). Senza browser lo strumento **dichiara** che la seconda metà non è stata provata, invece
di tacere: è lo stesso patto di `icon-check.py` con le misure di resa.

Uso:
    python3 scripts/feedback-check.py <documento.html>
"""
import json
import os
import re
import sys


def valore(testo, nome):
    """I confini del valore di `var NOME = [...]`, bilanciando le parentesi quadre.

    ⚠️ Si conta a mano invece di cercare la parentesi di chiusura: dentro i testi delle voci
    le parentesi quadre ci sono (un rimando, un elenco), e una regex le prenderebbe per la
    fine dell'elenco.
    """
    marca = 'var %s = ' % nome
    inizio = testo.rindex(marca) + len(marca)
    if testo[inizio] != '[':
        return None
    liv = 0
    dentro = None
    i = inizio
    while i < len(testo):
        c = testo[i]
        if dentro:
            if c == '\\':
                i += 2
                continue
            if c == dentro:
                dentro = None
        elif c in '"\'':
            dentro = c
        elif c == '[':
            liv += 1
        elif c == ']':
            liv -= 1
            if liv == 0:
                return json.loads(testo[inizio:i + 1])
        i += 1
    return None


def piena(x):
    return isinstance(x, str) and x.strip() != ''


def forma(sezioni, domande, testi, aperto):
    """I campi che il disegno legge: quali mancano.

    ⚠️ La pagina regge un campo assente dal giro della `2.67`, ma reggerlo vuol dire
    disegnarne uno in meno. A dire che manca è questo controllo.
    """
    guai = []
    for n, s in enumerate(sezioni):
        dove = 'sezione %d' % (n + 1)
        for campo in ('nome', 'sotto'):
            if not piena(s.get(campo)):
                guai.append('%s: manca il campo %r' % (dove, campo))
        if not s.get('voci'):
            guai.append('%s: nessuna voce' % dove)
        for v in s.get('voci', []):
            if len(v) != 4 or not all(piena(c) for c in v):
                guai.append('%s, voce %r: servono quattro campi pieni' % (dove, v[:1]))
    for d in domande:
        if len(d) < 4 or not all(piena(c) for c in d[:3]) or not d[3]:
            guai.append('domanda %r: servono chiave, titolo, spiegazione e le scelte' % d[:1])
            continue
        for o in d[3]:
            if len(o) < 3 or not all(piena(c) for c in o[:3]):
                guai.append('domanda %r, scelta %r: servono tre campi pieni' % (d[0], o[:1]))
    for t in testi:
        if len(t) != 5 or not all(piena(c) for c in t):
            guai.append('testo %r: servono cinque campi pieni' % t[:1])
    for n, g in enumerate(aperto):
        if not piena(g.get('nome')):
            guai.append('promemoria %d: manca il nome' % (n + 1))
        for v in g.get('voci', []):
            if len(v) != 2 or not all(piena(c) for c in v):
                guai.append('promemoria %r: servono due campi pieni' % v[:1])
    return guai


def eseguibile():
    """Il browser, cercato per percorso quando Playwright ne chiede una build che non c'è.

    ⚠️ L'ambiente ne porta una sola, e scaricarne un'altra è vietato: quindi si guarda che
    cosa c'è sotto `PLAYWRIGHT_BROWSERS_PATH` invece di lasciar decidere la libreria.
    """
    radice = os.environ.get('PLAYWRIGHT_BROWSERS_PATH') or '/opt/pw-browsers'
    if not os.path.isdir(radice):
        return None
    for nome in sorted(os.listdir(radice), reverse=True):
        if not nome.startswith('chromium-'):
            continue
        via = os.path.join(radice, nome, 'chrome-linux', 'chrome')
        if os.path.exists(via):
            return via
    return None


def resa(percorso, quante, domande, promemoria):
    """La pagina aperta davvero: che parta, e che disegni quello che i dati portano.

    Risponde (guai, provata): `provata` falso vuol dire che il browser non c'era.
    """
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        return [], False
    via = eseguibile()
    if not via:
        return [], False

    guai = []
    errori = []
    with sync_playwright() as p:
        b = p.chromium.launch(executable_path=via, args=['--no-sandbox'])
        ctx = b.new_context()
        ctx.grant_permissions(['clipboard-read', 'clipboard-write'])
        pg = ctx.new_page()
        pg.on('pageerror', lambda e: errori.append(str(e)))
        pg.on('console',
              lambda m: errori.append(m.text) if m.type == 'error' else None)
        pg.goto('file://' + os.path.abspath(percorso))
        # ⚠️ La guardia a tempo della pagina scatta a 2,5 secondi: si aspetta oltre, o la
        # sua spia non avrebbe ancora avuto modo di accendersi.
        pg.wait_for_timeout(3200)

        spia = pg.locator('#spia-guasto')
        if spia.is_visible():
            guai.append('la spia del guasto è accesa: ' + spia.inner_text())
        viste = pg.locator('#elenco .voce').count()
        if viste != quante:
            guai.append('voci disegnate: %d, nei dati %d' % (viste, quante))
        somm = pg.locator('#elenco .sommario').count()
        sez = pg.locator('#elenco section').count()
        if somm != sez:
            guai.append('sommari: %d su %d sezioni' % (somm, sez))
        chieste = pg.locator('#domande-elenco .domanda').count()
        if chieste != domande:
            guai.append('domande disegnate: %d, nei dati %d' % (chieste, domande))
        # ⚠️ Doppi apici, e non è una svista: con quelli singoli il verificatore dei
        # caratteri legge la fine del selettore come un accento scritto con l'apostrofo.
        righe = pg.locator("#aperto-elenco li").count()
        if righe != promemoria:
            guai.append('promemoria disegnati: %d, nei dati %d' % (righe, promemoria))

        # ⚠️ Il riepilogo dichiara il giro, e il numero lo legge dall'occhiello: erano due
        # posti a dirlo, e uno è rimasto indietro senza che nessuno lo guardasse.
        # ⚠️⚠️ **SI CERCA L'ULTIMA VERSIONE E NON LA FORMULA 'GIRO DELLA X'**, perché un
        # giro ne copre spesso più di una ('giro dalla 2.71 alla 2.74') e là la formula non
        # c'è: il verificatore diceva che l'occhiello non dichiarava il giro mentre lo
        # dichiarava benissimo. Quello che conta è che il riepilogo porti lo stesso numero.
        capo = pg.locator('.occhiello').inner_text()
        versioni = re.findall(r'\d+\.\d+', capo)
        if not versioni:
            guai.append("l'occhiello non dichiara il giro: %r" % capo)
        else:
            pg.locator('#copia').click()
            pg.wait_for_timeout(300)
            testo = pg.evaluate('navigator.clipboard.readText()')
            if versioni[-1] not in testo.split('\n')[0]:
                guai.append('il riepilogo non dichiara il giro %s' % versioni[-1])
        b.close()

    for e in errori:
        guai.append('errore in pagina: ' + e)
    return guai, True


def main():
    if len(sys.argv) != 2:
        sys.exit('uso: python3 scripts/feedback-check.py <documento.html>')
    percorso = sys.argv[1]
    testo = open(percorso, encoding='utf-8').read()

    if 'data-feedback="agent"' in testo:
        import importlib.util
        from pathlib import Path
        module_spec = importlib.util.spec_from_file_location('agent_feedback_check', Path(__file__).with_name('feedback-interactive-check.py'))
        module = importlib.util.module_from_spec(module_spec)
        module_spec.loader.exec_module(module)
        module.check(percorso)
        return

    dati = {}
    for nome in ('SEZIONI', 'DOMANDE', 'TESTI', 'APERTO'):
        try:
            dati[nome] = valore(testo, nome)
        except ValueError:
            sys.exit('in %s non trovo %s: è un documento di feedback?' % (percorso, nome))
        if dati[nome] is None:
            sys.exit('non riesco a leggere %s da %s' % (nome, percorso))

    guai = forma(dati['SEZIONI'], dati['DOMANDE'], dati['TESTI'], dati['APERTO'])
    quante = sum(len(s.get('voci', [])) for s in dati['SEZIONI'])
    promemoria = sum(len(g.get('voci', [])) for g in dati['APERTO'])
    altri, provata = resa(percorso, quante, len(dati['DOMANDE']), promemoria)
    guai += altri

    print('%d voci, %d domande, %d testi, %d voci di promemoria'
          % (quante, len(dati['DOMANDE']), len(dati['TESTI']), promemoria))
    if not provata:
        print("la pagina NON è stata aperta: senza Chromium si controlla la sola forma")
    if guai:
        print('guai:')
        for g in guai:
            print(' -', g)
        sys.exit(1)
    print('forma a posto' + ('' if not provata else ', e la pagina parte e disegna tutto'))


if __name__ == '__main__':
    main()
