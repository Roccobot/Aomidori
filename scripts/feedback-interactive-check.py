#!/usr/bin/env python3
"""Validate and exercise the actual agent feedback page, including persistence and import."""
import base64
import colorsys
import functools
import http.server
import json
from pathlib import Path
import re
import shutil
import tempfile
import threading
import zipfile


def read_export(path):
    """The export ZIP -> (feedback.json as data, {name in the ZIP: bytes})."""
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None, 'CRC sbagliato nello ZIP esportato.'
        assert all(info.compress_type == zipfile.ZIP_STORED for info in archive.infolist()), 'ZIP compresso.'
        files = {name: archive.read(name) for name in archive.namelist()}
    return json.loads(files.pop('feedback.json')), files


def write_export(path, data, files, compression=zipfile.ZIP_STORED):
    with zipfile.ZipFile(path, 'w', compression) as archive:
        archive.writestr('feedback.json', json.dumps(data))
        for name, payload in files.items():
            archive.writestr(name, payload)


def to_legacy(data, files):
    """An export as the JSON of before 2026-10-03: every file inside, as base64 text."""
    legacy = json.loads(json.dumps(data))
    for value in [*legacy['entries'].values(), legacy['extra']]:
        for attached in value['images']:
            payload = files[attached.pop('file')]
            attached['data'] = 'data:' + attached['type'] + ';base64,' + base64.b64encode(payload).decode()
    return legacy


SYNTHETIC_TEST = '''
| 0.00-01 | prova di sintesi del controllo |

## 1. Prova di sintesi

Scheda generata dal controllo e mai pubblicata: serve a esercitare la pagina quando il giro non ha prove aperte.
'''


SYNTHETIC_BLOCKS = '''# Feedback Aomidori

Documento di sintesi, costruito dal controllo e mai pubblicato.

| Voce | Stato | Commento dell'utente | Azione successiva |
|---|---|---|---|
| 0.00-01 | Non provato | | Attendere il collaudo. |

## 1. Prova di sintesi

Scheda generata dal controllo.

## Domande

### d-sintesi · Domanda di sintesi

Quale strada si prende?

**A1**: la prima strada.

**A2**: la seconda strada.

Parere: **A1**, perché è la prima.

## Etichette testuali

### e-sintesi · Etichetta di sintesi
Testo proposto

## Prossimi passi

- **In collaudo**: la prova di sintesi.
'''


class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def check_attachment_buttons(path):
    """Rinomina and Elimina stay inside their attachment card at every width (his screenshot of
    2026-10-09: in the side column of Altro, on a desktop, the two rows ran out of their cards
    and over each other). Two images in Altro, measured at the widths of a desktop and a phone."""
    from playwright.sync_api import sync_playwright
    browser_path = shutil.which('chromium') or shutil.which('google-chrome')
    if not browser_path:
        raise AssertionError('Chromium non disponibile: tasti degli allegati non verificati.')
    # A 1x1 PNG, enough for a thumbnail with its card and its buttons.
    pixel = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==')
    with tempfile.TemporaryDirectory() as temporary:
        files = []
        for name in ['etichetta.png', 'pillola.png']:
            file = Path(temporary) / name
            file.write_bytes(pixel)
            files.append(str(file))
        with sync_playwright() as pw:
            engine = pw.chromium.launch(executable_path=browser_path, args=['--no-sandbox'])
            for width in [390, 800, 1024, 1280, 1440, 1920]:
                page = engine.new_page(viewport={'width': width, 'height': 900})
                page.goto(Path(path).resolve().as_uri())
                page.locator('#extra-section input.images').set_input_files(files)
                page.wait_for_function("document.querySelectorAll('#extra-section .image-list figure button').length >= 4")
                out = page.evaluate("""() => [...document.querySelectorAll('#extra-section .image-list figure')]
                    .flatMap((card) => { const r = card.getBoundingClientRect();
                        return [...card.querySelectorAll('button')].filter((b) => { const q = b.getBoundingClientRect();
                            return q.left < r.left - 0.5 || q.right > r.right + 0.5; }).map((b) => b.textContent.trim()); })""")
                assert not out, f'A {width}px escono dal riquadro dell\'allegato: {out}'
                page.close()
            engine.close()
    print('Allegati: Rinomina ed Elimina dentro il loro riquadro da 390 a 1920px verificati.')


def check_questions_and_labels(path):
    """The blocks after the tests (the user's rule of 2026-10-08), on a page built from a
    synthetic source with the real generator and template: the questions come after the tests and
    before the labels, carry no number, take one option at a time (a second tap clears it,
    Rimando is one more option), and their choice and comment survive a reload and reach the
    summary; a label revision is saved and reaches the summary too."""
    from playwright.sync_api import sync_playwright, expect
    import subprocess
    import sys
    browser_path = shutil.which('chromium') or shutil.which('google-chrome')
    if not browser_path:
        raise AssertionError('Chromium non disponibile: blocchi dopo le prove non verificati.')
    folder = Path(path).resolve().parent
    root = Path(__file__).resolve().parents[1]
    errors = []
    with tempfile.TemporaryDirectory() as temporary:
        stage = Path(temporary)
        for entry in folder.iterdir():
            if entry.name != Path(path).name:
                (stage / entry.name).symlink_to(entry)
        source = stage / 'Feedback.md'
        source.write_text(SYNTHETIC_BLOCKS)
        page_copy = stage / Path(path).name
        subprocess.run([sys.executable, str(root / 'scripts/feedback-build.py'),
                        '--source', str(source), '--output', str(page_copy)], check=True, stdout=subprocess.DEVNULL)
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Quiet, directory=str(stage)))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        url = f'http://127.0.0.1:{server.server_port}/{page_copy.name}'
        try:
            with sync_playwright() as pw:
                engine = pw.chromium.launch(executable_path=browser_path, args=['--no-sandbox'])
                page = engine.new_context(permissions=['clipboard-read', 'clipboard-write']).new_page()
                page.on('pageerror', lambda e: errors.append(str(e)))
                page.goto(url)
                expect(page.locator('#save')).to_be_enabled()
                # The copy mark (his request of 2026-10-09): one per card, test, question or
                # label, in the top right corner, and a tap copies the card's reference.
                cards = page.locator('.card.test, .card.question, .label-card')
                expect(cards).to_have_count(3)
                for index in range(3):
                    card = cards.nth(index)
                    mark = card.locator(':scope > .card-ref')
                    expect(mark).to_have_count(1)
                    card_box, mark_box = card.bounding_box(), mark.bounding_box()
                    assert card_box['x'] + card_box['width'] - (mark_box['x'] + mark_box['width']) < 48, (index, card_box, mark_box)
                    assert mark_box['y'] - card_box['y'] < 16, (index, card_box, mark_box)
                    mark.click()
                    # The rich copy is written asynchronously: the toast says when it is done.
                    expect(page.locator('.toast')).to_contain_text(card.get_attribute('data-id').lower())
                    copied = page.evaluate('navigator.clipboard.readText()')
                    assert copied == '`' + card.get_attribute('data-id').lower() + '`', (copied, card.get_attribute('data-id'))
                # Pasted in a comment, a reference between backticks is inline code (2026-10-09),
                # and a text with backticks inside it stays plain.
                field = page.locator('.test .rich-editor').first
                for pasted, code in [('`4.91-01`', '4.91-01'), ('vedi `a` e `b`', None)]:
                    field.evaluate('''(box, text) => { box.focus(); const data = new DataTransfer();
                        data.setData('text/plain', text);
                        box.dispatchEvent(new ClipboardEvent('paste', {bubbles: true, cancelable: true, clipboardData: data})); }''', pasted)
                    found = field.evaluate("(box) => [...box.querySelectorAll('code')].map((c) => c.textContent)")
                    assert found == ([code] if code else []), (pasted, found)
                    field.evaluate("(box) => { box.textContent = ''; box.dispatchEvent(new Event('input', {bubbles: true})); }")
                order = page.evaluate("""() => [...document.querySelectorAll('.test, #questions, #labels')]
                    .map((node) => node.classList.contains('test') ? 'prova' : node.id)""")
                assert order == ['prova', 'questions', 'labels'], 'Ordine dei blocchi: ' + str(order)
                question = page.locator('#questions .question')
                expect(question).to_have_count(1)
                assert question.locator('.check-position').count() == 0, 'Una domanda non è numerata.'
                expect(page.locator('.test .check-position')).to_have_text('Verifica 1/1')
                expect(question.locator('.choice[data-choice="A1"] .advised')).to_have_count(1)
                expect(question.locator('.advised')).to_have_count(1)
                first, second = question.locator('.choice[data-choice="A1"]'), question.locator('.choice[data-choice="A2"]')
                later = question.locator('.choice[data-choice="rimando"]')
                first.click()
                expect(first).to_have_attribute('aria-pressed', 'true')
                expect(question).to_have_class(re.compile(r'\bhas-response\b'))
                second.click()
                expect(second).to_have_attribute('aria-pressed', 'true')
                expect(first).to_have_attribute('aria-pressed', 'false')
                second.click()
                expect(second).to_have_attribute('aria-pressed', 'false')
                expect(question).not_to_have_class(re.compile(r'\bhas-response\b'))
                later.click()
                expect(later).to_have_attribute('aria-pressed', 'true')
                question.locator('.rich-editor').fill('Commento di sintesi')
                page.locator('#labels .label-card .rich-editor').fill('Testo riveduto')
                page.locator('#save').click()
                expect(page.locator('#saved')).to_contain_text('Salvato in questo browser')
                summary = page.evaluate('summary()')
                assert 'd-sintesi - Domanda di sintesi: rimando' in summary, summary
                assert 'Commento di sintesi' in summary, summary
                assert 'e-sintesi: Testo riveduto' in summary, summary
                assert summary.index('Domande') < summary.index('Etichette testuali'), summary
                page.reload()
                expect(page.locator('#save')).to_be_enabled()
                expect(later).to_have_attribute('aria-pressed', 'true')
                kept = page.evaluate('draft.decisions')
                assert kept == {'d-sintesi': {'choice': 'rimando', 'comment': 'Commento di sintesi'}}, str(kept)
                expect(question.locator('.rich-editor')).to_have_text('Commento di sintesi')
                for width in [320, 390, 800, 1280]:
                    page.set_viewport_size({'width': width, 'height': 900})
                    assert page.evaluate('document.documentElement.scrollWidth <= innerWidth'), f'Scorrimento orizzontale a {width}px.'
                engine.close()
        finally:
            server.shutdown()
            server.server_close()
    assert not errors, 'Errori nella pagina di sintesi: ' + str(errors)
    print('Domande ed etichette: ordine, opzioni, Rimando, commento, ricarica, riepilogo e copia dei riferimenti verificati.')


def check_without_tests(path):
    """A round with every test closed publishes a page with no cards, and the exercise below
    needs at least one: it used to time out waiting for `.test`, so the check failed on a
    correct page. Two steps instead. The real page must start clean and draw no card; then
    the same generator and template build a throwaway copy with one synthetic test, served
    next to the real assets, and the whole exercise runs on it."""
    from playwright.sync_api import sync_playwright, expect
    browser = shutil.which('chromium') or shutil.which('google-chrome')
    if not browser:
        raise AssertionError('Chromium non disponibile: resa non verificata.')
    folder = Path(path).resolve().parent
    root = Path(__file__).resolve().parents[1]
    errors = []
    with sync_playwright() as pw:
        engine = pw.chromium.launch(executable_path=browser, args=['--no-sandbox'])
        page = engine.new_page()
        page.on('pageerror', lambda e: errors.append(str(e)))
        page.goto(Path(path).resolve().as_uri())
        expect(page.locator('#save')).to_be_enabled()
        assert page.locator('.test').count() == 0, 'Schede di prova disegnate senza prove nei dati.'
        for width in [320, 390, 800, 1280]:
            page.set_viewport_size({'width': width, 'height': 900})
            assert page.evaluate('document.documentElement.scrollWidth <= innerWidth'), f'Scorrimento orizzontale a {width}px.'
        engine.close()
    assert not errors, 'Errori nella pagina senza prove: ' + str(errors)
    print('Pagina senza prove: parte senza errori e non disegna schede.')
    with tempfile.TemporaryDirectory() as temporary:
        stage = Path(temporary)
        for entry in folder.iterdir():
            if entry.name != Path(path).name:
                (stage / entry.name).symlink_to(entry)
        source = stage / 'Feedback.md'
        source.write_text((root / 'docs/Feedback.md').read_text() + SYNTHETIC_TEST)
        page_copy = stage / Path(path).name
        import subprocess
        import sys
        subprocess.run([sys.executable, str(root / 'scripts/feedback-build.py'),
                        '--source', str(source), '--output', str(page_copy)], check=True, stdout=subprocess.DEVNULL)
        check(str(page_copy))


def check(path):
    text = Path(path).read_text()
    match = re.search(r'<script id="feedback-data" type="application/json">(.*?)</script>', text, re.S)
    if not match:
        raise AssertionError('Mancano i dati del documento.')
    data = json.loads(match[1])
    assert data.get('project') == 'Aomidori' and data.get('version'), 'Progetto o versione mancanti.'
    ids = set()
    for item in data['items']:
        assert all(item.get(k) for k in ['id', 'version', 'title', 'paragraphs']), 'Voce incompleta.'
        assert isinstance(item['paragraphs'], list) and all(isinstance(p, str) and p.strip() for p in item['paragraphs']), 'Passi mancanti.'
        assert item['id'] not in ids, 'Identificatore duplicato.'
        ids.add(item['id'])
    assert isinstance(data.get('labels', []), list), 'labels deve essere una lista.'
    for label in data.get('labels', []):
        assert all(label.get(k) for k in ['id', 'title', 'proposal']), 'Etichetta incompleta.'
        assert label['id'].startswith('e-'), 'id etichetta deve iniziare con e-.'
    assert 'decisions' not in data, 'Le domande vivono in `questions`, le risposte in `decisions` della bozza.'
    for question in data.get('questions', []):
        assert re.fullmatch(r'd-[a-z0-9-]+', question.get('id', '')), 'Chiave di domanda non valida.'
        assert question.get('title') and question.get('paragraphs'), 'Domanda incompleta.'
    check_questions_and_labels(path)
    check_attachment_buttons(path)
    if not data['items']:
        check_without_tests(path)
        return
    browser = shutil.which('chromium') or shutil.which('google-chrome')
    if not browser:
        raise AssertionError('Chromium non disponibile: resa non verificata.')
    from playwright.sync_api import sync_playwright, expect

    handler = functools.partial(Quiet, directory=str(Path(path).resolve().parent))
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = f'http://127.0.0.1:{server.server_port}/{Path(path).name}'
    errors = []
    try:
        with tempfile.TemporaryDirectory() as temporary, sync_playwright() as pw:
            browser = pw.chromium.launch(executable_path=browser, args=['--no-sandbox'])
            context = browser.new_context(permissions=['clipboard-read', 'clipboard-write'])
            page = context.new_page()
            navigation_context = browser.new_context(locale='it-IT', viewport={'width':390,'height':844}, is_mobile=True, has_touch=True)
            navigation = navigation_context.new_page()
            navigation.on('pageerror', lambda e: errors.append(str(e)))
            navigation.goto(url)
            expect(navigation.locator('#save')).to_be_enabled()
            numbered = navigation.locator('.test .check-position')
            assert numbered.count() == len(data['items'])
            for index, counter in enumerate(numbered.all(), 1):
                expect(counter).to_have_text(f'Verifica {index}/{len(data["items"])}')
                expect(counter.locator('strong')).to_have_text(str(index))
                assert counter.evaluate('(el)=>getComputedStyle(el).fontWeight') == '400'
                assert int(counter.locator('strong').evaluate('(el)=>getComputedStyle(el).fontWeight')) >= 700
            def torna(posizione):
                # ⚠️ The page refreshes its keys on the frame after a scroll, so a check read at
                # once sees the keys of the position before (found on the DF of AIV 4.40).
                navigation.evaluate(f'window.scrollTo(0, {posizione})')
                navigation.evaluate('new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))')
            def aligned(card):
                box = card.bounding_box()
                # Since 2026-10-06 the desktop has no fixed strip (the counts live in Altro), so a
                # card lands 18px from the top, at Altro's height; elsewhere under the strip.
                if navigation.viewport_size['width'] >= 1100:
                    assert abs(box['y'] - 18) < 3, f"Card not at Altro's top: {box['y']}"
                    expect(navigation.locator('#extra-section .dashboard')).to_have_count(1)
                    return
                dashboard = navigation.locator('.dashboard').bounding_box()
                assert abs(box['y'] - dashboard['height'] - 12) < 3, 'Card hidden beneath the sticky dashboard.'
            for width in [320,390,800,1280]:
                navigation.set_viewport_size({'width':width,'height':900})
                navigation.evaluate('window.scrollTo(0,0)')
                expect(navigation.locator('#previous-card')).to_be_disabled()
                navigation.locator('#next-card').tap()
                aligned(navigation.locator('.test').nth(0))
                if navigation.locator('.test').count() > 1:
                    navigation.locator('#next-card').tap()
                    aligned(navigation.locator('.test').nth(1))
                    navigation.locator('#previous-card').tap()
                    aligned(navigation.locator('.test').nth(0))
                    navigation.locator('#next-card').tap()
                elif width <= 720:
                    # Una prova sola: su mobile Avanti arriva ad Altro, così ⇥ resta visibile.
                    navigation.locator('#next-card').tap()
                else:
                    # Su desktop, dal 2026-10-05, dopo l'ultima prova Avanti non c'è (sua
                    # richiesta: Altro è la colonna laterale, e andarci faceva oscillare la
                    # pagina). Allora ⇥ si rende visibile tornando in cima, fuori dalla prova.
                    expect(navigation.locator('#next-card')).to_be_hidden()
                    navigation.evaluate('window.scrollTo(0,0)')
                expect(navigation.locator('#first-empty')).to_be_visible()
                navigation.locator('#first-empty').tap()
                aligned(navigation.locator('.test').nth(0))
                # Mobile keeps ⇥ visible for long-press Altro; desktop hides when on the empty card.
                if width <= 720:
                    expect(navigation.locator('#first-empty')).to_be_visible()
                    expect(navigation.locator('#menu-toggle')).to_have_count(0)
                    expect(navigation.locator('#jump-altro')).to_have_count(0)
                else:
                    expect(navigation.locator('#first-empty')).to_be_hidden()
                expect(navigation.locator('#extra-section .altro-commands')).to_be_visible()
                save_box = navigation.locator('#floating-save').bounding_box()
                pill = navigation.locator('.floating-controls')
                pill_box = pill.bounding_box()
                for ident in ['first-empty','previous-card','next-card']:
                    button = navigation.locator('#'+ident)
                    if not button.is_visible():
                        continue
                    box = button.bounding_box()
                    assert box['y']+box['height'] <= save_box['y']+0.5
                    assert box['width'] >= 48 and box['height'] >= 48
                    # Every visible button lives inside the one pill.
                    assert box['x'] >= pill_box['x'] and box['x']+box['width'] <= pill_box['x']+pill_box['width']+0.5
                # A button that cannot act is not shown: at the first card there is no 'previous'.
                expect(navigation.locator('#previous-card')).to_be_hidden()
                assert pill.evaluate('(el)=>getComputedStyle(el).borderRadius') == '28px'
                # The fill is 70% opaque in the light theme, where white glyphs need it, and 25%
                # in the dark one; the glyphs are not faded with it.
                previous_theme = navigation.evaluate("document.documentElement.getAttribute('data-theme')")
                for theme, alpha in [('light', r'0?\.7'), ('dark', r'0?\.25')]:
                    navigation.evaluate(f"document.documentElement.dataset.theme = '{theme}'")
                    fill = pill.evaluate('(el)=>getComputedStyle(el).backgroundColor')
                    assert re.search(r'(?:/|,)\s*' + alpha + r'\)$', fill), (theme, fill)
                navigation.evaluate("(theme)=>theme ? document.documentElement.setAttribute('data-theme', theme) : document.documentElement.removeAttribute('data-theme')", previous_theme)
                assert navigation.locator('#floating-save').evaluate('(el)=>getComputedStyle(el).opacity') == '1'
                # Under the fill the page is blurred, like frosted glass (the user's request).
                frost = pill.evaluate('(el)=>getComputedStyle(el).backdropFilter')
                assert 'blur(8px)' in frost and 'saturate(' in frost, frost
                # The pill is anchored at the bottom and holds the save button last.
                assert abs((pill_box['y']+pill_box['height']) - (save_box['y']+save_box['height']) - 4) < 1
                # The footer is gone.
                expect(navigation.locator('footer')).to_have_count(0)
            navigation.evaluate('''() => {
                const previous = document.querySelector('#tests .test:last-child').getBoundingClientRect();
                // The next in-flow primary card, whichever block comes after the tests (the
                // questions, the labels or the archive, which a round may not have); .extra is a
                // side column on desktop.
                let nextNode = document.querySelector('.feedback-primary .tests').nextElementSibling;
                while (nextNode && !nextNode.getBoundingClientRect().height) nextNode = nextNode.nextElementSibling;
                const next = nextNode.getBoundingClientRect();
                const offset = document.querySelector('.dashboard').getBoundingClientRect().height + 12;
                window.scrollTo(0, window.scrollY + (previous.bottom + next.top)/2 - offset);
            }''')
            navigation.locator('#previous-card').tap()
            aligned(navigation.locator('.test').last)
            # Con 4 o più prove: 0 e l'ultima compilate, la 1 con esito, buco all'indice 2.
            # Con 2 o 3 prove non c'è quel buco: l'esito sulla 1 resta, e lo si toglie più sotto.
            # Con una prova sola esito e commento sono sulla stessa carta.
            outcome = 1 if len(data['items']) >= 2 else 0
            # ⚠️ `fill` and `click` scroll the field into view, which no navigation key did, so the
            # page goes back where the keys left it after each of them. The position is taken
            # right after the last key that moved the page: taken after a `fill` it is already
            # Playwright's (found on the DF of AIV 4.44, 12 px off; on the DF of AIV 4.41, 16 px).
            fermo = navigation.evaluate('scrollY')
            navigation.locator('.test').nth(0).locator('.rich-editor').fill('Solo commento')
            navigation.locator('.test').nth(outcome).locator('[data-status="Non approvato"]').click()
            torna(fermo)
            if len(data['items']) >= 4:
                navigation.locator('.test').nth(len(data['items']) - 1).locator('.rich-editor').fill('Più in basso')
                navigation.locator('#first-empty').tap()
                aligned(navigation.locator('.test').nth(2))
                fermo = navigation.evaluate('scrollY')
            # Fill through normal input handlers; navigation must update without a reload.
            for field in navigation.locator('.test .rich-editor').all():
                field.fill('Risposta di verifica')
            torna(fermo)
            # Desktop hides ⇥ when nothing is empty; mobile keeps it for long-press Altro.
            if navigation.viewport_size['width'] <= 720:
                expect(navigation.locator('#first-empty')).to_be_visible()
            else:
                expect(navigation.locator('#first-empty')).to_be_hidden()
            navigation.locator('.test').nth(outcome).locator('[data-status="Non approvato"]').click()
            navigation.locator('.test').nth(outcome).locator('.rich-editor').fill('')
            torna(fermo)
            # Con poche prove si è già sulla carta vuota: ⇥ è nascosto e Avanti è fermo.
            if navigation.locator('#next-card').is_enabled():
                navigation.locator('#next-card').tap()
            if navigation.locator('#first-empty').is_visible():
                navigation.locator('#first-empty').tap()
            aligned(navigation.locator('.test').nth(outcome))
            last = navigation.locator('.extra')
            last.scroll_into_view_if_needed()
            navigation.evaluate('window.scrollTo(0, document.body.scrollHeight)')
            expect(navigation.locator('#next-card')).to_be_disabled()
            navigation.locator('#previous-card').tap()
            # responseCards end at .extra, so previous from the bottom lands on the last test.
            aligned(navigation.locator('.test').last)
            # Desktop: past the last proof the next key leaves, and every press moves the page
            # down. It used to aim at the sticky Altro column and rock the page by 3px (2026-10-05).
            navigation.set_viewport_size({'width':1280,'height':900})
            navigation.evaluate('window.scrollTo(0,0)')
            # The page refreshes the keys on the next frame after a scroll: wait for it.
            expect(navigation.locator('#next-card')).to_be_visible()
            seen = [navigation.evaluate('scrollY')]
            for _ in range(len(data['items']) + 3):
                if navigation.locator('#next-card').is_hidden():
                    break
                navigation.locator('#next-card').tap()
                seen.append(navigation.evaluate('scrollY'))
            expect(navigation.locator('#next-card')).to_be_hidden()
            assert all(b > a for a, b in zip(seen, seen[1:])), seen
            navigation_context.close()
            formatting_context = browser.new_context(permissions=['clipboard-read','clipboard-write'])
            formatting = formatting_context.new_page()
            formatting.on('pageerror', lambda e: errors.append(str(e)))
            formatting.goto(url)
            expect(formatting.locator('#save')).to_be_enabled()
            card = formatting.locator('.test').first
            field = card.locator('.rich-editor')
            stored = card.locator('.comment')
            def fill_plain(field, text):
                # Clear first so a new scenario does not inherit the previous selection's style.
                field.fill('')
                field.fill(text)
            def select(field, start, end):
                field.evaluate("""(box, offsets) => {
                    box.focus();
                    const walker = document.createTreeWalker(box, NodeFilter.SHOW_TEXT);
                    const points = [];
                    let offset = 0, node;
                    while ((node = walker.nextNode())) {
                        for (const [index, target] of offsets.entries()) {
                            if (!points[index] && target <= offset + node.length)
                                points[index] = [node, target - offset];
                        }
                        offset += node.length;
                    }
                    const range = document.createRange();
                    range.setStart(...points[0]); range.setEnd(...points[1]);
                    getSelection().removeAllRanges(); getSelection().addRange(range);
                }""", [start,end])
            expect(formatting.locator('.markdown-preview,.preview-caption')).to_have_count(0)
            expect(stored).to_be_hidden()
            fill_plain(field, 'prima abc dopo')
            select(field,6,9)
            field.press('Meta+b')
            expect(stored).to_have_value('prima **abc** dopo')
            expect(field.locator('b,strong')).to_have_text('abc')
            field.press('Meta+i')
            expect(stored).to_have_value('prima ***abc*** dopo')
            expect(field.locator('i,em')).to_have_text('abc')
            field.press('Meta+i')
            expect(stored).to_have_value('prima **abc** dopo')
            field.press('Meta+b')
            expect(stored).to_have_value('prima abc dopo')
            fill_plain(field, 'abc')
            select(field,0,3)
            card.locator('[data-format="bold"]').click()
            expect(stored).to_have_value('**abc**')
            field.press('Control+z')
            expect(stored).to_have_value('abc')
            select(field,0,3)
            field.press('Control+b')
            expect(stored).to_have_value('**abc**')
            field.press('Control+b')
            expect(stored).to_have_value('abc')
            select(field,0,3)
            destination = url.rsplit('/',1)[0]+'/example.html'
            formatting.once('dialog',lambda dialog:dialog.accept(destination))
            field.press('Meta+k')
            expected_comment = '[abc]('+destination+')'
            expect(stored).to_have_value(expected_comment)
            link = field.locator('a')
            expect(link).to_have_text('abc')
            assert link.get_attribute('target')=='_blank' and 'noopener' in link.get_attribute('rel')
            with formatting.expect_popup() as pending:
                link.click()
            linked = pending.value
            linked.wait_for_load_state()
            assert linked.url==destination
            assert linked.evaluate('window.opener === null')
            linked.close()
            fill_plain(field, 'abc')
            select(field,0,3)
            formatting.once('dialog',lambda dialog:dialog.dismiss())
            field.press('Control+k')
            expect(stored).to_have_value('abc')
            formatting.once('dialog',lambda dialog:dialog.accept('javascript:alert(1)'))
            field.press('Control+k')
            expect(stored).to_have_value('abc')
            expect(formatting.locator('#action-message')).to_contain_text('http:// o https:// valido')
            # Literal typed text stays literal; imported Markdown restores visual formatting.
            literal = '**<img src=x onerror="window.injected=true">** [pericoloso](javascript:alert(1))'
            fill_plain(field, literal)
            expect(field.locator('img,script,a,b,strong')).to_have_count(0)
            assert formatting.evaluate('window.injected === undefined')
            fill_plain(field, 'abc')
            select(field,0,3)
            formatting.once('dialog',lambda dialog:dialog.accept(destination))
            card.locator('[data-format="link"]').click()
            expect(stored).to_have_value(expected_comment)
            notes_field = formatting.locator('.extra .rich-editor')
            fill_plain(notes_field, 'note')
            select(notes_field,0,4)
            formatting.locator('.extra [data-format="bold"]').click()
            expect(formatting.locator('#notes')).to_have_value('**note**')
            formatting.locator('.extra [data-format="bold"]').click()
            expect(formatting.locator('#notes')).to_have_value('note')
            formatting.locator('.extra [data-format="italic"]').click()
            expect(formatting.locator('#notes')).to_have_value('*note*')
            formatting.locator('#floating-save').click()
            expect(formatting.locator('#saved')).to_contain_text('Salvato in questo browser')
            formatting.reload()
            expect(formatting.locator('#save')).to_be_enabled()
            expect(stored).to_have_value(expected_comment)
            expect(field.locator('a')).to_have_text('abc')
            expect(notes_field.locator('em')).to_have_text('note')
            formatting.locator('#copy').click()
            expect(formatting.locator('#action-message')).to_contain_text('Riepilogo copiato')
            formatted_summary = formatting.evaluate('navigator.clipboard.readText()')
            expected_bits = [expected_comment, '*note*']
            assert all(value in formatted_summary for value in expected_bits)
            with formatting.expect_download() as pending:
                formatting.locator('#export').click()
            formatted_export=Path(temporary)/'formatted.zip'
            pending.value.save_as(str(formatted_export))
            formatted_data, formatted_files = read_export(formatted_export)
            assert formatted_data['entries'][data['items'][0]['id']]['comment']==expected_comment
            assert formatted_data['notes']=='*note*'
            # Old drafts containing formatted text, literal Markdown characters and line breaks.
            restored='**grassetto** e *corsivo*\n[link]('+destination+')\nPercorso C:\\foto, \\*letterale\\* <img src=x>'
            formatted_data['entries'][data['items'][0]['id']]['comment']=restored
            # Repacked with deflate, as another program or an agent would: the import still reads it.
            write_export(formatted_export, formatted_data, formatted_files, zipfile.ZIP_DEFLATED)
            formatting.locator('#import').set_input_files(str(formatted_export))
            expect(formatting.locator('#action-message')).to_contain_text('Risposte importate')
            expect(stored).to_have_value(restored)
            expect(field.locator('strong')).to_have_text('grassetto')
            expect(field.locator('em')).to_have_text('corsivo')
            expect(field.locator('a')).to_have_text('link')
            expect(field.locator('img')).to_have_count(0)
            expect(field).to_contain_text('*letterale* <img src=x>')
            expect(notes_field.locator('em')).to_have_text('note')
            # Editing after import, Enter, undo/redo and safe paste remain in the same visible field.
            fill_plain(field, 'riga uno')
            field.press('End')
            field.press('Enter')
            field.press('Space')
            field.press('Backspace')
            field.press('x')
            expect(stored).to_have_value('riga uno\nx')
            field.press('Control+z')
            field.press('Control+Shift+z')
            expect(stored).to_have_value('riga uno\nx')
            fill_plain(field, 'riga')
            field.press('End')
            field.press('Shift+Enter')
            expect(stored).to_have_value('riga\n')
            field.press('Shift+Enter')
            expect(stored).to_have_value('riga\n\n')
            field.press('x')
            expect(stored).to_have_value('riga\n\nx')
            fill_plain(field, 'prima')
            field.press('End')
            field.press('Enter')
            field.press('Enter')
            field.press('Enter')
            field.press('x')
            expect(stored).to_have_value('prima\n\n\nx')
            formatting.locator('#floating-save').click()
            expect(formatting.locator('#saved')).to_contain_text('Salvato in questo browser')
            formatting.reload()
            expect(stored).to_have_value('prima\n\n\nx')
            expect(field).to_have_text('prima\n\n\nx')
            fill_plain(field, 'abc')
            select(field,3,3)
            card.locator('[data-format="bold"]').click()
            field.press('x')
            expect(stored).to_have_value('abc**x**')
            card.locator('[data-format="bold"]').click()
            field.press('y')
            expect(stored).to_have_value('abc**x**y')
            fill_plain(field, 'abc ')
            select(field,4,4)
            formatting.once('dialog',lambda dialog:dialog.accept(destination))
            field.press('Meta+k')
            expect(stored).to_have_value('abc [testo del link]('+destination+')')
            expect(field.locator('a')).to_have_text('testo del link')
            fill_plain(field, 'inizio ')
            field.press('End')
            field.evaluate("""box => {
                const clipboard = new DataTransfer();
                clipboard.setData('text/plain', 'testo <img src=x> *semplice*');
                clipboard.setData('text/html', '<img src=x onerror="window.injected=true"><b>testo</b>');
                box.dispatchEvent(new ClipboardEvent('paste', {bubbles:true, cancelable:true, clipboardData:clipboard}));
            }""")
            expect(field).to_have_text('inizio testo <img src=x> *semplice*')
            expect(field.locator('img,b,strong')).to_have_count(0)
            formatting.locator('#floating-save').click()
            expect(formatting.locator('#saved')).to_contain_text('Salvato in questo browser')
            formatting.reload()
            expect(field).to_have_text('inizio testo <img src=x> *semplice*')
            # Every style is undone by ⌘Z, survives the save, and travels with copy and paste (his
            # note of 2026-10-10: ⌘Z after Codice undid the typing and left the code, and code with
            # bold lost the bold on the save and on a paste).
            fill_plain(field, 'prima abc dopo')
            select(field,6,9)
            field.press('Meta+m')
            expect(stored).to_have_value('prima `abc` dopo')
            field.press('Meta+z')
            expect(stored).to_have_value('prima abc dopo')
            expect(field.locator('code')).to_have_count(0)
            assert formatting.evaluate('getSelection().toString()') == 'abc', 'Annullato il codice, la selezione torna sul testo.'
            field.press('Meta+Shift+z')
            expect(stored).to_have_value('prima `abc` dopo')
            select(field,6,9)
            field.press('Meta+b')
            expect(stored).to_have_value('prima **`abc`** dopo')
            field.press('Meta+z')
            expect(stored).to_have_value('prima `abc` dopo')
            fill_plain(field, 'x abc y')
            select(field,2,5)
            field.press('Meta+b')
            select(field,2,5)
            field.press('Meta+m')
            expect(stored).to_have_value('x **`abc`** y')
            select(field,0,7)
            field.press('ControlOrMeta+c')
            fill_plain(notes_field, '')
            notes_field.click()
            notes_field.press('ControlOrMeta+v')
            expect(formatting.locator('#notes')).to_have_value('x **`abc`** y')
            expect(notes_field.locator('strong code')).to_have_text('abc')
            notes_field.press('Meta+z')
            expect(formatting.locator('#notes')).to_have_value('')
            formatting.locator('#floating-save').click()
            expect(formatting.locator('#saved')).to_contain_text('Salvato in questo browser')
            formatting.reload()
            expect(stored).to_have_value('x **`abc`** y')
            expect(field.locator('strong code')).to_have_text('abc')
            for width in [320,390,800,1280]:
                formatting.set_viewport_size({'width':width,'height':900})
                assert formatting.evaluate('document.documentElement.scrollWidth <= innerWidth')
                for editor in formatting.locator('.rich-editor').all():
                    box = editor.bounding_box()
                    if box is None:
                        continue  # editors in the hidden Altro overlay
                    assert box['height'] >= 200
                    assert editor.evaluate('(el)=>getComputedStyle(el).resize') == 'vertical'
                    # Format controls sit outside the field, bottom-right of its block, every width.
                    place = editor.evaluate('''(el) => {
                        const bar = el.parentElement.querySelector('.format-toolbar');
                        const eb = el.getBoundingClientRect();
                        const tb = bar.getBoundingClientRect();
                        const overlap = tb.top < eb.bottom - 1 && tb.bottom > eb.top + 1 && tb.left < eb.right - 1 && tb.right > eb.left + 1;
                        return {
                            below: tb.top >= eb.bottom - 1,
                            insetRight: Math.abs(eb.right - tb.right),
                            overlap,
                        };
                    }''')
                    assert place['below'] and not place['overlap'] and place['insetRight'] < 8, (width, place)
                if width in (390, 1280):
                    pressed = formatting.evaluate('''() => {
                      const root = document.documentElement;
                      const previous = root.getAttribute('data-theme');
                      const bold = document.querySelector('article.test [data-format="bold"]');
                      const italic = document.querySelector('article.test [data-format="italic"]');
                      bold.setAttribute('aria-pressed', 'true');
                      italic.setAttribute('aria-pressed', 'true');
                      const lum = (c) => {
                        const parts = c.match(/[\\d.]+/g).slice(0, 3).map(Number);
                        const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
                        const [r, g, b] = parts.map(f);
                        return 0.2126 * r + 0.7152 * g + 0.0722 * b;
                      };
                      const ratio = (a, b) => {
                        const hi = Math.max(lum(a), lum(b));
                        const lo = Math.min(lum(a), lum(b));
                        return (hi + 0.05) / (lo + 0.05);
                      };
                      const out = {};
                      for (const theme of ['light', 'dark']) {
                        root.setAttribute('data-theme', theme);
                        const bcs = getComputedStyle(bold);
                        const ics = getComputedStyle(italic);
                        out[theme] = {
                          bold: ratio(bcs.color, bcs.backgroundColor),
                          italic: ratio(ics.color, ics.backgroundColor),
                        };
                      }
                      if (previous) root.setAttribute('data-theme', previous);
                      bold.removeAttribute('aria-pressed');
                      italic.removeAttribute('aria-pressed');
                      return out;
                    }''')
                    for theme, ratios in pressed.items():
                        assert ratios['bold'] >= 4.5 and ratios['italic'] >= 4.5, (width, theme, ratios)
            touch_context = browser.new_context(is_mobile=True,has_touch=True,viewport={'width':390,'height':844})
            touch = touch_context.new_page()
            touch.on('pageerror', lambda e: errors.append(str(e)))
            touch.goto(url)
            expect(touch.locator('#save')).to_be_enabled()
            touch_field = touch.locator('.test .rich-editor').first
            touch_field.fill('mobile')
            select(touch_field,0,6)
            touch.locator('.test').first.locator('[data-format="bold"]').tap()
            expect(touch.locator('.comment').first).to_have_value('**mobile**')
            expect(touch_field.locator('b,strong')).to_have_text('mobile')
            touch_context.close()
            formatting_context.close()
            page.on('pageerror', lambda e: errors.append(str(e)))
            page.goto(url)
            expect(page.locator('#save')).to_be_enabled()
            # The intro says the round is closed and where the earlier ones are, in one generic
            # sentence; on mobile there is no summary line.
            intro = page.locator('.intro > .intro-summary')
            expect(intro).to_have_text(re.compile(r'^Giro [0-9.]+: collaudo chiuso\. Le migliorie e le scelte dei giri precedenti sono in archivio\.$'))
            expect(intro).to_be_visible()
            # No coloured ring around the field being written in.
            page.locator('#notes-editor').focus()
            assert page.locator('#notes-editor').evaluate('(el)=>getComputedStyle(el).outlineStyle') == 'none'
            # Inline code is rendered in the editor, like bold: a <code> node, and backticks in
            # what is saved.
            page.locator('#notes-editor').press('End')
            page.locator('#extra-section [data-format="code"]').click()
            expect(page.locator('#notes-editor code')).to_have_text('codice')
            assert page.locator('#notes').input_value().endswith('`codice`'), page.locator('#notes').input_value()
            # With the caret inside the code, the key takes it away again.
            page.evaluate("""() => { const code = document.querySelector('#notes-editor code');
                const range = document.createRange(); range.setStart(code.firstChild, 2); range.collapse(true);
                const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range); }""")
            page.locator('#extra-section [data-format="code"]').click()
            expect(page.locator('#notes-editor code')).to_have_count(0)
            page.evaluate("() => { const box = document.querySelector('#notes-editor'); box.replaceChildren(); box.dispatchEvent(new Event('input', {bubbles: true})); }")
            # Desktop: Prossimi passi follows the last card at the cards' own 18px, and at the
            # end of the page it ends where Altro ends.
            page.set_viewport_size({'width': 1280, 'height': 900})
            steps = page.locator('.feedback-columns > .next-steps')
            last_card = page.locator('.feedback-primary > section').last
            assert abs(steps.bounding_box()['y'] - (last_card.bounding_box()['y'] + last_card.bounding_box()['height']) - 18) < 1.5
            page.evaluate("window.scrollTo(0, document.documentElement.scrollHeight)")
            page.wait_for_timeout(200)
            altro_bottom = page.locator('#extra-section').evaluate('(el)=>el.getBoundingClientRect().bottom')
            steps_bottom = steps.evaluate('(el)=>el.getBoundingClientRect().bottom')
            assert abs(altro_bottom - steps_bottom) < 1.5, (altro_bottom, steps_bottom)
            # Cmd+Up and Cmd+Down go to the top and the bottom of the page, outside the fields.
            page.locator('h1').click()
            page.keyboard.press('Meta+ArrowUp')
            page.wait_for_function("window.scrollY === 0")
            page.keyboard.press('Meta+ArrowDown')
            page.wait_for_function("Math.abs(window.scrollY + innerHeight - document.documentElement.scrollHeight) < 2")
            page.keyboard.press('Control+ArrowUp')
            page.wait_for_function("window.scrollY === 0")
            page.set_viewport_size({'width': 390, 'height': 900})
            # Mobile: Scarica Aomidori follows the title, with no summary line in between.
            expect(page.locator('.intro > .intro-summary')).to_be_hidden()
            assert page.locator('.test').count() == len(data['items'])
            assert page.locator('.decision, #decisions').count() == 0
            # Consegna lives in the Altro row: no overlay, no opener, no summary field.
            assert page.locator('#delivery-overlay, #open-delivery, #summary').count() == 0
            assert page.locator('.browse-label').count() == 0
            expected = ['Azzera tutto', 'Copia il riepilogo', 'Esporta', 'Importa', 'Salva', 'Invia']
            near = lambda a, b: abs(a - b) < 1
            for width in [320, 390, 800, 1280]:
                page.set_viewport_size({'width': width, 'height': 900})
                row = page.locator('#extra-section .altro-commands')
                controls = row.locator(':scope > .command')
                assert [c.get_attribute('title') for c in controls.all()] == expected, width
                row_box = row.bounding_box()
                boxes = [c.bounding_box() for c in controls.all()]
                # Six equal buttons fill the row, on one line.
                assert near(boxes[0]['x'], row_box['x']) and near(boxes[-1]['x'] + boxes[-1]['width'], row_box['x'] + row_box['width']), width
                assert all(near(b['width'], boxes[0]['width']) and near(b['y'], boxes[0]['y']) for b in boxes), width
                # The format row splits exactly in half: attach left, the four format buttons right.
                halves = page.locator('#extra-section .altro-halves')
                cluster_box = halves.bounding_box()
                attach = halves.locator('.altro-attach').bounding_box()
                tools = halves.locator('.format-toolbar').bounding_box()
                assert near(attach['width'], tools['width']) and near(attach['x'], cluster_box['x']), (width, attach, tools)
                assert near(tools['x'] + tools['width'], cluster_box['x'] + cluster_box['width']), width
                formats = [b.bounding_box() for b in halves.locator('.format-toolbar button').all()]
                assert len(formats) == 4 and all(near(b['width'], formats[0]['width']) for b in formats), width
                assert near(formats[-1]['x'] + formats[-1]['width'], tools['x'] + tools['width']), width
                # Every format glyph keeps its 24px: on a phone the italic, code and link icons
                # shrank to 16px in 38px keys, and only bold looked right (2026-10-05).
                glyphs = [s.bounding_box()['width'] for s in halves.locator('.format-toolbar svg').all()]
                assert all(near(g, 24) for g in glyphs), (width, glyphs)
                assert near(cluster_box['width'], row_box['width']), width
            fab = page.locator('#floating-save')
            def hold(button):
                button.dispatch_event('pointerdown', {'button': 0})
                page.wait_for_timeout(600)
                button.dispatch_event('pointerup', {'button': 0})
                button.dispatch_event('click')
            # Desktop: a long press on Salva only saves; the Consegna overlay is gone.
            page.set_viewport_size({'width': 1280, 'height': 900})
            hold(fab)
            expect(page.locator('#altro-overlay')).to_be_hidden()
            # Mobile: a long press on Salva or on the arrow opens Altro, with the six commands.
            page.set_viewport_size({'width': 390, 'height': 900})
            for button in [fab, page.locator('#first-empty')]:
                hold(button)
                expect(page.locator('#altro-overlay')).to_be_visible()
                expect(page.locator('#altro-overlay .altro-commands > .command')).to_have_count(6)
                assert page.locator('#altro-overlay [id="save"], #altro-overlay [id="import"]').count() == 0
                page.locator('#altro-overlay-close').click()
                expect(page.locator('#altro-overlay')).to_be_hidden()
            # Measured on the user's phone with its tall keyboard: about 368px stay visible above
            # it. Since 2026-10-06 (his request) the field starts at the top of the panel, with
            # no title, and the field and both rows of keys fit in those 368px.
            page.set_viewport_size({'width': 412, 'height': 800})
            hold(fab)
            assert page.locator('#altro-overlay h2').count() == 0
            panel_box = page.locator('.altro-overlay-panel').bounding_box()
            field_box = page.locator('#notes-mobile-editor').bounding_box()
            assert abs(field_box['y'] - panel_box['y']) < 1, (field_box, panel_box)
            assert abs(field_box['height'] - 269) < 1, field_box
            format_box = page.locator('.altro-overlay-panel .format-actions').bounding_box()
            assert format_box['y'] + format_box['height'] <= 368, format_box
            # Two rows of six equal keys over the whole width, both visible, 42px each, in his
            # order (2026-10-06): Invia, Link, Codice, Grassetto, Corsivo, Allega; then Azzera
            # tutto, Copia, Esporta, Importa, Salva, Chiudi.
            row = page.locator('.altro-overlay-panel .format-actions')
            assert row.locator('.altro-row-delivery, .altro-row-back').count() == 0
            def keys(*selectors):
                boxes = [row.locator(selector).bounding_box() for selector in selectors]
                assert len(boxes) == 6 and all(boxes), boxes
                assert all(abs(b['y'] - boxes[0]['y']) < 1 and abs(b['width'] - boxes[0]['width']) < 1 and abs(b['height'] - 42) < 1 for b in boxes), boxes
                assert abs(boxes[0]['x'] - format_box['x']) < 1 and abs(boxes[-1]['x'] + boxes[-1]['width'] - format_box['x'] - format_box['width']) < 1, (boxes, format_box)
                assert all(boxes[i]['x'] < boxes[i + 1]['x'] for i in range(5)), boxes
                return boxes
            first_row = keys('[data-command="send"]', '[data-format="link"]', '[data-format="code"]', '[data-format="bold"]', '[data-format="italic"]', '.altro-attach')
            second_row = keys('[data-command="reset"]', '[data-command="copy"]', '[data-command="export"]', '[data-command="import"]', '[data-command="save"]', '.altro-row-close')
            assert second_row[0]['y'] > first_row[0]['y'] + 40, (first_row, second_row)
            # Chiudi in the row replaces the old bottom close key.
            assert page.locator('.altro-overlay-close-thumb').count() == 0
            row.locator('.altro-row-close').click()
            expect(page.locator('#altro-overlay')).to_be_hidden()
            hold(fab)
            # Dragging on the overlay does not scroll the page under it.
            page.evaluate("window.scrollTo(0, 300)")
            before = page.evaluate("window.scrollY")
            page.mouse.move(200, 150)
            page.mouse.wheel(0, 400)
            page.wait_for_timeout(300)
            assert page.evaluate("window.scrollY") == before, (before, page.evaluate("window.scrollY"))
            # No focus ring around the field in the overlay.
            page.locator('#notes-mobile-editor').focus()
            assert page.locator('#notes-mobile-editor').evaluate('(el)=>getComputedStyle(el).outlineStyle') == 'none'
            page.locator('#altro-overlay-close').click()
            page.set_viewport_size({'width': 390, 'height': 900})
            # The service line is discreet on mobile: 12px, centred, at 70%.
            saved_style = page.locator('#saved').evaluate('(el)=>{const c=getComputedStyle(el);return [c.fontSize,c.textAlign,c.opacity]}')
            assert saved_style == ['12px', 'center', '0.7'], saved_style
            # Android paints no tap rectangle over what the finger touches.
            assert page.evaluate("getComputedStyle(document.documentElement).webkitTapHighlightColor") == 'rgba(0, 0, 0, 0)'
            # The overlay's copy of the commands is wired: its Copia reports, from an empty message.
            hold(fab)
            page.evaluate("document.querySelector('#action-message').textContent = ''")
            page.locator('#altro-overlay [data-command="copy"]').click()
            expect(page.locator('#action-message')).to_have_text(re.compile('Riepilogo copiato|appunti'))
            # One keyboard handler: Escape closes Altro, T switches the theme outside the fields only.
            page.keyboard.press('Escape')
            expect(page.locator('#altro-overlay')).to_be_hidden()
            page.locator('h1').click()
            theme = page.evaluate("document.documentElement.dataset.theme")
            page.keyboard.press('t')
            assert page.evaluate("document.documentElement.dataset.theme") != theme, 'T non cambia il tema.'
            page.keyboard.press('t')
            assert page.evaluate("document.documentElement.dataset.theme") == theme
            # The Mac lives on the download row and changes in a modal (the user's request for
            # AIV, 2026-10-06): OK writes it, Annulla leaves it as it was.
            expect(page.locator('#device')).to_be_hidden()
            # On a phone (his mockup, 2026-10-06) no modifica line: the device row is half
            # transparent, fades out on the right, and has its own icon, which opens the modal
            # with the caret in the field.
            expect(page.locator('#devices-edit')).to_be_hidden()
            # Since his request of the same evening: the text at 70%, the icons smaller (20px) and at
            # 22.5% of the row's muted ink, which over the page gives about #d4d8d2, and not clipped
            # by the buttons' rounded corners.
            row_style = page.locator('.device-row').first.evaluate("""(el)=>{const t=getComputedStyle(el.querySelector('.device-shown')),
              b=getComputedStyle(el.querySelector('button.device-edit'));
              return [getComputedStyle(el).opacity,t.opacity,(t.maskImage||t.webkitMaskImage).includes('linear-gradient'),
                b.opacity,b.width,b.borderTopLeftRadius,b.backgroundColor===getComputedStyle(el).color]}""")
            assert row_style == ['1','0.7',True,'0.225','20px','0px',True], row_style
            # A long device name fades before the icon and never pushes the row off the screen.
            page.evaluate("document.querySelector('#device-shown').textContent='MacBook Pro 14 pollici con M4 Pro, macOS 27 Golden Gate e altro testo'")
            row_right = page.locator('.device-row').first.evaluate('(el)=>el.getBoundingClientRect().right')
            assert row_right <= 390 - 15, row_right
            page.evaluate("syncDevices()")
            # The icon moves right by the empty part of its canvas, so its ink ends where the row does.
            mac_icon = page.locator('.device-edit-mac').bounding_box()
            mac_row = page.locator('.device-row').first.bounding_box()
            assert abs(mac_icon['x'] + mac_icon['width'] - 0.0118 * 20 - (mac_row['x'] + mac_row['width'])) <= 0.5, (mac_icon, mac_row)
            page.locator('.device-edit-mac').click()
            expect(page.locator('#devices-dialog')).to_be_visible()
            expect(page.locator('#device')).to_be_focused()
            page.keyboard.press('t')
            assert page.evaluate("document.documentElement.dataset.theme") == theme, 'T cambia il tema mentre si scrive.'
            expect(page.locator('#device')).to_have_value(re.compile('t$'))
            page.locator('#device').fill('Mac del modale')
            page.locator('#devices-cancel').click()
            expect(page.locator('#devices-dialog')).to_be_hidden()
            # A new draft starts with the user's Mac, which Annulla leaves in place.
            owner_mac = page.evaluate('OWNER_MAC')
            assert owner_mac.startswith('MacBook Pro 16'), owner_mac
            expect(page.locator('#device-shown')).to_have_text(owner_mac)
            page.locator('.device-edit-mac').click()
            expect(page.locator('#device')).to_have_value(owner_mac)
            page.locator('#device').fill('Mac del modale')
            page.locator('#devices-ok').click()
            expect(page.locator('#devices-dialog')).to_be_hidden()
            expect(page.locator('#device-shown')).to_have_text('Mac del modale')
            assert page.evaluate('draft.device') == 'Mac del modale'
            page.locator('.device-edit-mac').click()
            page.locator('#device').fill('')
            page.locator('#devices-ok').click()
            # Desktop: Scarica e installa, the checkbox and the Mac share one row, the Mac on
            # the right; the page goes from the strip straight to the first test.
            page.set_viewport_size({'width': 1280, 'height': 900})
            # On a desktop the small modifica stays, and the row icons do not show.
            expect(page.locator('#devices-edit')).to_be_visible()
            expect(page.locator('.device-edit-mac')).to_be_hidden()
            # A wheel over Altro never scrolls the page (his request, 2026-10-06), not even
            # where Altro has nothing to scroll.
            page.evaluate('window.scrollTo(0, 300)')
            before = page.evaluate('window.scrollY')
            altro_box = page.locator('#extra-section').bounding_box()
            page.mouse.move(altro_box['x'] + altro_box['width'] / 2, altro_box['y'] + 40)
            page.mouse.wheel(0, 600)
            page.wait_for_timeout(300)
            assert page.evaluate('window.scrollY') == before, 'La rotella sopra Altro scorre la pagina.'
            page.evaluate('window.scrollTo(0, 0)')
            link = page.locator('.intro-actions a').bounding_box()
            devices = page.locator('.devices').bounding_box()
            assert abs(link['y'] + link['height'] / 2 - devices['y'] - devices['height'] / 2) < 4, (link, devices)
            assert devices['x'] + devices['width'] > 1280 - 30, devices
            expect(page.locator('.intro-actions a')).to_have_text('Scarica e installa Aomidori ' + data['version'])
            assert page.evaluate("document.querySelector('.feedback-primary').firstElementChild.firstElementChild.firstElementChild.classList.contains('test')")
            assert page.locator('text=Prove sui dispositivi').count() == 0 and page.locator('#answered').count() == 0
            # The title's F starts where the lines below start: its side bearing is taken back.
            bearing = page.evaluate("""async()=>{await document.fonts.ready;const h=document.querySelector('h1');const c=getComputedStyle(h);const x=document.createElement('canvas').getContext('2d');x.font=c.fontWeight+' '+c.fontSize+' '+c.fontFamily;return h.getBoundingClientRect().left-x.measureText('F').actualBoundingBoxLeft-document.querySelector('.intro-summary').getBoundingClientRect().left}""")
            assert abs(bearing) < 1, bearing
            # Altro keeps its own colours when it has text: the response colours are the tests'.
            page.locator('.extra .rich-editor').fill('Testo in Altro')
            expect(page.locator('#extra-section')).not_to_have_class(re.compile(r'\bhas-response\b'))
            page.locator('.extra .rich-editor').fill('')
            # Writing on mobile leaves only Salva: the pill becomes a circle.
            page.set_viewport_size({'width': 390, 'height': 800})
            first_test = page.locator('.test').first
            assert first_test.bounding_box()['y'] < page.locator('#extra-section').bounding_box()['y']
            page.locator('.test .rich-editor').first.focus()
            expect(page.locator('#previous-card')).to_be_hidden()
            pill = page.locator('.floating-controls').bounding_box()
            assert abs(pill['width'] - pill['height']) < 1 and abs(pill['width'] - 56) < 1, pill
            page.locator('h1').click()
            page.set_viewport_size({'width': 1280, 'height': 900})
            first = page.locator('.test').first
            first.locator('[data-status="Tutto OK"]').click()
            expect(first.locator('.item-state')).to_have_count(0)
            expect(first).to_have_class(re.compile(r'\bhas-response\b'))
            first.locator('[data-status="Tutto OK"]').click()
            expect(first.locator('.item-state')).to_have_count(0)
            expect(first).not_to_have_class(re.compile(r'\bhas-response\b'))
            first.locator('.rich-editor').fill('Risposta senza esito')
            expect(first).to_have_class(re.compile(r'\bhas-response\b'))
            first.locator('.rich-editor').fill('')
            expect(first).not_to_have_class(re.compile(r'\bhas-response\b'))
            for theme in ['light', 'dark']:
                page.emulate_media(color_scheme=theme)
                first.locator('.rich-editor').fill('Solo commento, senza approvazione')
                neutral = first.evaluate('(el)=>getComputedStyle(el).backgroundColor')
                backgrounds = []
                for status in ['Tutto OK', 'Accettabile', 'Non approvato']:
                    button = first.locator('[data-status="'+status+'"]')
                    button.click()
                    border = first.evaluate('(el)=>getComputedStyle(el).borderTopColor')
                    selected = button.evaluate('(el)=>getComputedStyle(el).backgroundColor')
                    def hue(rgb):
                        values = [int(value)/255 for value in re.findall(r'\d+', rgb)[:3]]
                        return colorsys.rgb_to_hsv(*values)[0]
                    difference = abs(hue(border)-hue(selected))
                    assert min(difference, 1-difference) < 0.07, 'The card color does not match its outcome.'
                    background = first.evaluate('(el)=>getComputedStyle(el).backgroundColor')
                    assert background != neutral
                    backgrounds.append(background)
                    button.click()
                    assert first.evaluate('(el)=>getComputedStyle(el).backgroundColor') == neutral
                assert len(set(backgrounds)) == 3, 'The three outcomes use the same card color.'
                first.locator('.rich-editor').fill('')
            page.emulate_media(color_scheme='light')
            for field in page.locator('.rich-editor,textarea:not([hidden]),input:not([type="file"])').all():
                assert field.evaluate('(el)=>getComputedStyle(el).fontWeight') == '400'
                assert field.evaluate('(el)=>parseFloat(getComputedStyle(el).fontSize)') >= 18
            for link in page.locator('a').all():
                assert link.get_attribute('target') == '_blank'
                assert 'noopener' in link.get_attribute('rel')

            first.locator('[data-status="Accettabile"]').click()
            first.locator('.rich-editor').fill('Commento di verifica: <script>test</script>')
            page.locator('.extra .rich-editor').fill('Osservazioni libere di verifica')
            page.locator('#devices-edit').click()
            page.locator('#device').fill('Dispositivo di verifica')
            page.locator('#devices-ok').click()
            image = Path(temporary) / 'feedback.png'
            # An original, complete PNG is attached without image transformations.
            image.write_bytes(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aP9sAAAAASUVORK5CYII='))
            if page.locator('.test').count() > 1:
                attachment_only = page.locator('.test').nth(1)
            else:
                attachment_only = first
                attachment_only.locator('[data-status="Accettabile"]').click()
                attachment_only.locator('.rich-editor').fill('')
            attachment_only.locator('.images').set_input_files(str(image))
            expect(attachment_only.locator('.image-list img')).to_have_count(1)
            expect(attachment_only).to_have_class(re.compile(r'\bhas-response\b'))
            attachment_only.get_by_role('button', name='Elimina', exact=True).click()
            expect(attachment_only).not_to_have_class(re.compile(r'\bhas-response\b'))
            if page.locator('.test').count() == 1:
                first.locator('[data-status="Accettabile"]').click()
                first.locator('.rich-editor').fill('Commento di verifica: <script>test</script>')
            first.locator('.images').set_input_files(str(image))
            expect(first.locator('.image-list img')).to_have_count(1)
            # SVG stays an image resource: scripts and external resources cannot execute.
            svg = Path(temporary) / 'original.svg'
            svg_bytes = b'<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><script>parent.svgExecuted=true</script><image href="https://example.invalid/forbidden.png"/><rect width="32" height="32" fill="#43B59E"/></svg>'
            svg.write_bytes(svg_bytes)
            external = []
            page.on('request', lambda request: external.append(request.url) if 'example.invalid' in request.url else None)
            first.locator('.images').set_input_files(str(svg))
            expect(first.locator('.image-list img')).to_have_count(2)
            transfer = page.evaluate_handle('''text => {
                const transfer = new DataTransfer();
                transfer.items.add(new File([text], 'dropped.svg', {type:'application/octet-stream'}));
                return transfer;
            }''', svg_bytes.decode())
            first.dispatch_event('dragenter', {'dataTransfer': transfer})
            expect(first).to_have_class(re.compile(r'\bdrop-active\b'))
            first.dispatch_event('drop', {'dataTransfer': transfer})
            expect(first.locator('.image-list img')).to_have_count(3)
            expect(first).not_to_have_class(re.compile(r'\bdrop-active\b'))
            assert page.evaluate('window.svgExecuted === undefined')
            assert not external, 'SVG fetched an external resource.'
            page.wait_for_function("Array.from(document.querySelectorAll('.test:first-child .image-list img')).every(image => image.complete && image.naturalWidth > 0)")
            bad_svg = Path(temporary) / 'invalid.svg'
            bad_svg.write_text('<html>not an SVG</html>')
            first.locator('.images').set_input_files(str(bad_svg))
            expect(page.locator('#action-message')).to_contain_text('SVG non è valido')
            expect(first.locator('.image-list img')).to_have_count(3)
            archive = Path(temporary) / 'sources.zip'
            with zipfile.ZipFile(archive, 'w') as zipped:
                zipped.writestr('original.svg', svg_bytes)
                zipped.writestr('original.png', image.read_bytes())
            first.locator('.images').set_input_files(str(archive))
            expect(first.locator('.zip-download')).to_have_count(1)
            notes_card = page.locator('.extra')
            notes_card.locator('.images').set_input_files(str(image))
            expect(notes_card.locator('img')).to_have_count(1)
            notes_card.dispatch_event('drop', {'dataTransfer': transfer})
            expect(notes_card.locator('img')).to_have_count(2)
            notes_card.locator('.images').set_input_files({'name': 'notes.zip', 'mimeType': 'application/x-zip-compressed', 'buffer': archive.read_bytes()})
            expect(notes_card.locator('.zip-download')).to_have_count(1)
            zip_transfer = page.evaluate_handle('''bytes => {
                const transfer = new DataTransfer();
                transfer.items.add(new File([new Uint8Array(bytes)], 'dropped.zip', {type:''}));
                return transfer;
            }''', list(archive.read_bytes()))
            first.dispatch_event('drop', {'dataTransfer': zip_transfer})
            expect(first.locator('.zip-download')).to_have_count(2)
            notes_card.dispatch_event('drop', {'dataTransfer': zip_transfer})
            expect(notes_card.locator('.zip-download')).to_have_count(2)
            bad_zip = Path(temporary) / 'invalid.zip'
            bad_zip.write_bytes(b'this is not a zip')
            notes_card.locator('.images').set_input_files(str(bad_zip))
            expect(page.locator('#action-message')).to_contain_text('ZIP non è riconosciuto')
            expect(notes_card.locator('.zip-download')).to_have_count(2)
            # Rename in place (the user's requests, 2026-10-05 and 2026-10-06): the field holds
            # the name alone, the extension stays beside it, Invio confirms and Esc cancels; a
            # name typed with the extension does not get a second one. Renamed back, so the
            # checks below keep their names.
            figura = first.locator('.image-list figure').first
            # The name is centred and shows the hand; the two buttons sit on one centred row.
            caption_style = figura.locator('figcaption').evaluate("(el)=>{const c=getComputedStyle(el);return [c.textAlign,c.cursor,c.fontSize]}")
            assert caption_style == ['center', 'pointer', '14px'], caption_style
            row = figura.locator('.attachment-actions').bounding_box()
            buttons = [figura.get_by_role('button', name=label, exact=True).bounding_box() for label in ['Rinomina', 'Elimina']]
            left_room = buttons[0]['x'] - row['x']
            right_room = row['x'] + row['width'] - (buttons[1]['x'] + buttons[1]['width'])
            assert abs(left_room - right_room) <= 1, (left_room, right_room)
            # Since the same evening: the icon before the words on a desktop, and the two buttons
            # of one size, 40px high as before (the user's request: hard to tell apart at a glance).
            assert abs(buttons[0]['width'] - buttons[1]['width']) <= 0.5 and buttons[0]['height'] == buttons[1]['height'] == 40, buttons
            for label in ['Rinomina', 'Elimina']:
                button = figura.get_by_role('button', name=label, exact=True)
                expect(button.locator('svg')).to_be_visible()
                expect(button.locator('.attachment-action-text')).to_be_visible()
                assert button.locator('svg').bounding_box()['x'] < button.locator('.attachment-action-text').bounding_box()['x'], label
            figura.get_by_role('button', name='Rinomina', exact=True).click()
            expect(figura.locator('.attachment-rename-name')).to_have_value('feedback')
            expect(figura.locator('.attachment-rename-extension')).to_have_text('.png')
            figura.locator('.attachment-rename-name').fill('schermata prova')
            figura.locator('.attachment-rename-name').press('Enter')
            expect(figura.locator('figcaption')).to_have_text('schermata prova.png')
            assert page.evaluate("draft.entries[spec.items[0].id].images[0].name") == 'schermata prova.png', 'Nome non scritto nella bozza.'
            figura.get_by_role('button', name='Rinomina', exact=True).click()
            figura.locator('.attachment-rename-name').fill('da non tenere')
            figura.locator('.attachment-rename-name').press('Escape')
            expect(figura.locator('figcaption')).to_have_text('schermata prova.png')
            figura.get_by_role('button', name='Rinomina', exact=True).click()
            figura.locator('.attachment-rename-name').fill('feedback.png')
            figura.locator('.attachment-rename-name').press('Enter')
            expect(figura.locator('figcaption')).to_have_text('feedback.png')
            # While writing in a field, a click on an attachment writes its name at the caret, as
            # inline code (since 2026-10-06; before, between quotes).
            if page.locator('.test').count() > 2:
                writing = page.locator('.test').nth(2)
                writing.locator('.rich-editor').click()
                page.keyboard.type('Vedi ')
                figura.locator('img').click()
                expect(writing.locator('.comment')).to_have_value("Vedi `feedback.png`")
                expect(writing.locator('.rich-editor code')).to_have_text('feedback.png')
                writing.locator('.rich-editor').fill('')
                expect(writing.locator('.comment')).to_have_value('')
            page.locator('#floating-save').click()
            expect(page.locator('#saved')).to_contain_text('Salvato in questo browser')
            page.reload()
            expect(page.locator('#save')).to_be_enabled()
            expect(first.locator('.item-state')).to_have_count(0)
            expect(first.locator('.comment')).to_have_value('Commento di verifica: <script>test</script>')
            expect(first.locator('.image-list img')).to_have_count(3)
            expect(page.locator('#notes')).to_have_value('Osservazioni libere di verifica')
            with page.expect_download() as pending:
                page.locator('#export').click()
            assert pending.value.suggested_filename == 'Aomidori-feedback-' + data['version'] + '.zip'
            export = Path(temporary) / 'export.zip'
            pending.value.save_as(str(export))
            exported, exported_files = read_export(export)
            first_images = exported['entries'][data['items'][0]['id']]['images']
            # Short names in one folder: the test's position plus a letter, 00 for Altro.
            assert [a['file'] for a in first_images] == ['01a.png', '01b.svg', '01c.svg', '01d.zip', '01e.zip'], first_images
            assert [a['file'] for a in exported['extra']['images']] == ['00a.png', '00b.svg', '00c.zip', '00d.zip']
            assert set(exported_files) == {a['file'] for a in first_images + exported['extra']['images']}
            assert first_images[0]['name'] == 'feedback.png', 'Nome originale perso.'
            assert all('data' not in a and 'blob' not in a for a in first_images), 'Allegato come testo nel JSON.'
            assert exported_files['01a.png'] == image.read_bytes(), 'Immagine modificata.'
            for attached in first_images[1:3]:
                assert attached['type'] == 'image/svg+xml'
                assert exported_files[attached['file']] == svg_bytes, 'SVG originale modificato.'
            for attached in first_images[3:]:
                assert attached['type'] == 'application/zip'
                assert exported_files[attached['file']] == archive.read_bytes()
            for attached, original in zip(exported['extra']['images'], [image.read_bytes(), svg_bytes, archive.read_bytes(), archive.read_bytes()]):
                assert exported_files[attached['file']] == original, 'Allegato delle osservazioni modificato.'
            expect(first).to_have_class(re.compile(r'\bhas-response\b'))

            second_context = browser.new_context(permissions=['clipboard-read', 'clipboard-write'])
            second = second_context.new_page()
            second.on('pageerror', lambda e: errors.append(str(e)))
            second.goto(url)
            expect(second.locator('#save')).to_be_enabled()
            with second.expect_file_chooser() as chooser:
                second.locator('#extra-section .file-button').click()
            chooser.value.set_files(str(export))
            expect(second.locator('#action-message')).to_contain_text('Risposte importate')
            expect(second.locator('.test').first.locator('.item-state')).to_have_count(0)
            expect(second.locator('.test').first.locator('.image-list img')).to_have_count(3)
            second.reload()
            expect(second.locator('#save')).to_be_enabled()
            expect(second.locator('.extra img')).to_have_count(2)
            expect(second.locator('.extra .zip-download')).to_have_count(2)
            expect(second.locator('.test').first.locator('.zip-download')).to_have_count(2)
            with second.expect_download() as pending_zip:
                second.locator('.extra .zip-download').first.click()
            zip_copy = Path(temporary) / 'downloaded.zip'
            pending_zip.value.save_as(str(zip_copy))
            assert zip_copy.read_bytes() == archive.read_bytes(), 'ZIP scaricato modificato.'
            expect(second.locator('.test').first.locator('.comment')).to_have_value('Commento di verifica: <script>test</script>')
            bad = Path(temporary) / 'invalid.zip'
            invalid = json.loads(json.dumps(exported))
            invalid['entries'][data['items'][0]['id']]['status'] = 'Esito inventato'
            write_export(bad, invalid, exported_files)
            second.locator('#import').set_input_files(str(bad))
            expect(second.locator('#action-message')).to_contain_text('Importazione annullata')
            missing = Path(temporary) / 'missing.zip'
            write_export(missing, exported, {k: v for k, v in exported_files.items() if k != '01a.png'})
            second.locator('#import').set_input_files(str(missing))
            expect(second.locator('#action-message')).to_contain_text('manca 01a.png')
            expect(second.locator('.test').first.locator('.item-state')).to_have_count(0)
            # A JSON exported before 2026-10-03, with the files inside as base64, still imports.
            old_json = Path(temporary) / 'old.json'
            old_draft = to_legacy(exported, exported_files)
            old_draft['entries']['3.13-01'] = {'status': 'Tutto OK', 'comment': 'Prova chiusa', 'images': []}
            old_json.write_text(json.dumps(old_draft))
            second.locator('#import').set_input_files(str(old_json))
            # The import says how many answers belong to tests no longer on the page.
            expect(second.locator('#action-message')).to_contain_text('1 sono di prove chiuse')
            expect(second.locator('.test').first.locator('.image-list img')).to_have_count(3)
            # Salva answers with a toast as Invia does (the user's request, 2026-10-05).
            second.locator('#save').click()
            expect(second.locator('.toast.is-visible')).to_contain_text('Salvato')
            second.locator('#send').click()
            expect(second.locator('#action-message')).to_contain_text('Risposte pronte')
            # Invia answers with a visible notice too (the user's request, 2026-10-04).
            expect(second.locator('.toast.is-visible')).to_contain_text('Risposte pronte')
            # Thumbnails two per row, on desktop and on mobile.
            thumbs = [f.bounding_box() for f in second.locator('.test').first.locator('.image-list figure').all()]
            assert abs(thumbs[0]['y'] - thumbs[1]['y']) < 1 and thumbs[2]['y'] > thumbs[0]['y'] + 1, thumbs
            assert second.evaluate('summary()').startswith('Feedback Aomidori '+data['version'])
            second.locator('#copy').click()
            expect(second.locator('#action-message')).to_contain_text('Riepilogo copiato')
            clipboard = second.evaluate('navigator.clipboard.readText()')
            assert all(name in clipboard for name in ['Osservazioni libere di verifica', 'feedback.png', 'notes.zip', 'sources.zip', 'dropped.zip'])
            # Altro's attachments show in the mobile overlay too, under the field, and there a tap
            # with no field being written in copies the quoted name (the user's request,
            # 2026-10-06). On a phone Rinomina and Elimina are icons, with the same names.
            size = second.viewport_size
            second.set_viewport_size({'width': 390, 'height': 900})
            page_figures = second.locator('.extra .image-list figure').count()
            assert page_figures > 0
            opener = second.locator('#floating-save')
            opener.dispatch_event('pointerdown', {'button': 0})
            second.wait_for_timeout(600)
            opener.dispatch_event('pointerup', {'button': 0})
            opener.dispatch_event('click')
            overlay_figures = second.locator('#altro-overlay .image-list figure')
            expect(overlay_figures).to_have_count(page_figures)
            list_box = second.locator('#altro-overlay .image-list').bounding_box()
            rows_box = second.locator('#altro-overlay .format-actions').bounding_box()
            assert list_box['y'] >= rows_box['y'] + rows_box['height'], (list_box, rows_box)
            # With the keyboard open the visible area is shorter than the screen, and the overlay
            # follows it, so the last attachment can be scrolled into view (his note of
            # 2026-10-10: before, the panel stayed as tall as the screen and its end was under the
            # keyboard). A page zoom shrinks visualViewport the way an open keyboard does.
            zoom = second_context.new_cdp_session(second)
            zoom.send('Emulation.setPageScaleFactor', {'pageScaleFactor': 900 / 368})
            second.wait_for_timeout(300)
            reach = second.evaluate("""() => {
                const view = visualViewport, panel = document.querySelector('.altro-overlay-panel');
                panel.scrollTop = panel.scrollHeight;
                const figures = document.querySelectorAll('#altro-overlay .image-list figure');
                const last = figures[figures.length - 1].getBoundingClientRect();
                return {overlay: document.querySelector('#altro-overlay').getBoundingClientRect().height,
                        view: view.height, bottom: last.bottom - view.offsetTop};
            }""")
            assert reach['view'] < 400, ('La pagina non si è ingrandita: la prova non misura niente.', reach)
            assert abs(reach['overlay'] - reach['view']) < 1 and reach['bottom'] <= reach['view'] + 1, reach
            zoom.send('Emulation.setPageScaleFactor', {'pageScaleFactor': 1})
            second.wait_for_timeout(300)
            second.evaluate('document.activeElement.blur()')
            caption = overlay_figures.first.locator('figcaption')
            shown = caption.inner_text()
            caption.click()
            expect(second.locator('.toast.is-visible')).to_contain_text(shown)
            assert second.evaluate('navigator.clipboard.readText()') == '`' + shown + '`'
            remove = overlay_figures.first.get_by_role('button', name='Elimina', exact=True)
            expect(remove.locator('svg')).to_be_visible()
            expect(remove.locator('.attachment-action-text')).to_be_hidden()
            expect(overlay_figures.first.get_by_role('button', name='Rinomina', exact=True).locator('svg')).to_be_visible()
            second.locator('#altro-overlay-close').click()
            second.set_viewport_size({'width': 1280, 'height': 900})
            page_remove = second.locator('.extra .image-list figure').first.get_by_role('button', name='Elimina', exact=True)
            expect(page_remove.locator('.attachment-action-text')).to_be_visible()
            # Since the evening of 2026-10-06 the icon shows on a desktop too, before the words.
            expect(page_remove.locator('svg')).to_be_visible()
            second.set_viewport_size(size)
            confirmations = []
            def cancel_reset(dialog):
                confirmations.append((dialog.type, dialog.message))
                dialog.dismiss()
            second.once('dialog', cancel_reset)
            second.locator('#reset').click()
            assert confirmations and confirmations[0][0] == 'confirm'
            assert 'Cancellare tutte le risposte' in confirmations[0][1]
            expect(second.locator('.test').first.locator('.item-state')).to_have_count(0)
            expect(second.locator('.test').first.locator('.image-list img')).to_have_count(3)
            second.on('dialog', lambda dialog: dialog.accept())
            second.locator('#reset').click()
            expect(second.locator('.test').first.locator('.item-state')).to_have_count(0)
            expect(second.locator('.test').first.locator('.image-list img')).to_have_count(0)
            expect(second.locator('.extra .image-list figure')).to_have_count(0)
            for width in [320, 390, 800, 1280]:
                second.set_viewport_size({'width': width, 'height': 900})
                assert second.evaluate('document.documentElement.scrollWidth <= innerWidth'), f'Scorrimento orizzontale a {width}px.'
            second.emulate_media(color_scheme='dark')
            second.locator('.test').first.locator('.rich-editor').fill('Solo commento')
            expect(second.locator('.test').first).to_have_class(re.compile(r'\bhas-response\b'))
            for field in second.locator('.rich-editor,textarea:not([hidden]),input:not([type="file"])').all():
                assert field.evaluate('(el)=>getComputedStyle(el).fontWeight') == '400'

            second.screenshot(path='/tmp/aomidori-feedback-dark.png', full_page=False)
            filled = second.locator('.test').first
            filled_bg = filled.evaluate('(el)=>getComputedStyle(el).backgroundColor')
            if second.locator('.test').count() > 1:
                assert filled_bg != second.locator('.test').nth(1).evaluate('(el)=>getComputedStyle(el).backgroundColor')
            else:
                filled.locator('.rich-editor').fill('')
                assert filled_bg != filled.evaluate('(el)=>getComputedStyle(el).backgroundColor')
                filled.locator('.rich-editor').fill('Solo commento')
            page.set_viewport_size({'width': 1100, 'height': 900})
            page.screenshot(path='/tmp/aomidori-feedback-light.png', full_page=False)
            # A previous release's saved draft must survive the cumulative document update.
            # A draft saved in the browser before 2026-10-03 holds its files as base64 text.
            legacy = to_legacy(exported, exported_files)
            legacy['version'] = legacy['installed'] = '3.14'
            legacy.pop('extra', None)
            # Earlier drafts contain images only and have no optional extra attachments.
            for value in legacy['entries'].values():
                value['images'] = [file for file in value['images'] if file['type'].startswith('image/')]

            # Keep the first current-card answer so migration still shows Accettabile + images;
            # orphaned 3.13/3.14 keys must not crash when those cards are no longer in the doc.
            first_id = data['items'][0]['id']
            kept = legacy['entries'].get(first_id)
            legacy['entries'] = {key: value for key, value in legacy['entries'].items()
                                 if key.startswith(('3.13-', '3.14-'))}
            if kept is not None:
                legacy['entries'][first_id] = kept
            legacy['entries']['3.14-03'] = {'status': 'Tutto OK', 'comment': 'Riscontro precedente conservato', 'images': []}
            legacy.setdefault('labels', {})['e-chiusa'] = {'revision': 'Etichetta di un giro chiuso'}
            legacy.setdefault('decisions', {})
            legacy['decisions']['d-settings-order'] = {
                'choice': 'Applica la proposta',
                'comment': 'Decisione precedente conservata',
            }
            migration_context = browser.new_context()
            migration = migration_context.new_page()
            migration.on('pageerror', lambda e: errors.append(str(e)))
            migration.goto(url)
            expect(migration.locator('#save')).to_be_enabled()
            migration.evaluate("""async draft => {
                const db = await new Promise((resolve, reject) => {
                    const request = indexedDB.open('aomidori-feedback', 1);
                    request.onsuccess = () => resolve(request.result);
                    request.onerror = () => reject(request.error);
                });
                await new Promise((resolve, reject) => {
                    const transaction = db.transaction('drafts', 'readwrite');
                    transaction.objectStore('drafts').put(draft, 'current');
                    transaction.oncomplete = resolve;
                    transaction.onerror = () => reject(transaction.error);
                });
                db.close();
            }""", legacy)
            migration.reload()
            expect(migration.locator('#save')).to_be_enabled()
            expect(migration.locator(f'[data-id="{first_id}"] .item-state')).to_have_count(0)
            expect(migration.locator('[data-id="3.14-03"]')).to_have_count(0)
            # The page asks no decisions, but an old draft's answers survive a save through the page.
            migration.keyboard.press('Control+s')
            expect(migration.locator('#saved')).to_contain_text('Salvato in questo browser')
            kept_decisions = migration.evaluate("""async () => {
                const db = await new Promise((resolve, reject) => {
                    const request = indexedDB.open('aomidori-feedback', 1);
                    request.onsuccess = () => resolve(request.result);
                    request.onerror = () => reject(request.error);
                });
                const draft = await new Promise((resolve, reject) => {
                    const request = db.transaction('drafts').objectStore('drafts').get('current');
                    request.onsuccess = () => resolve(request.result);
                    request.onerror = () => reject(request.error);
                });
                db.close();
                // The base64 of the old draft is now stored as real files, with their bytes.
                const files = Object.values(draft.entries).flatMap((value) => value.images);
                const sizes = await Promise.all(files.map((file) =>
                    file.blob instanceof Blob && !('data' in file) ? file.blob.size : -1));
                return {decisions: draft.decisions, sizes, expected: files.map((file) => file.size),
                        entries: Object.keys(draft.entries), labels: Object.keys(draft.labels)};
            }""")
            assert kept_decisions['decisions'] == legacy['decisions'], 'Decisioni della bozza precedente perse.'
            # A new round drops the answers and label revisions of tests no longer on the page.
            listed_ids = {item['id'] for item in data['items']}
            assert kept_decisions['entries'] and set(kept_decisions['entries']) <= listed_ids, 'Risposte di prove chiuse rimaste: ' + str(kept_decisions['entries'])
            assert 'e-chiusa' not in kept_decisions['labels'], 'Etichetta di un giro chiuso rimasta.'
            assert kept_decisions['sizes'] and kept_decisions['sizes'] == kept_decisions['expected'], 'Allegati salvati come testo: ' + str(kept_decisions)
            expect(migration.locator('#installed-confirm')).not_to_be_checked()
            expect(migration.locator('.intro-actions a')).to_contain_text(data['version'])
            expect(migration.locator('.test').first.locator('.image-list img')).to_have_count(3)
            for item in data['items']:
                if item['id'] == first_id:
                    continue
                if item['version'] == data['version']:
                    expect(migration.locator(f'[data-id="{item["id"]}"] .item-state')).to_have_count(0)
            migration_context.close()
            browser.close()
        assert not errors, 'Errori nella pagina: '+str(errors)
        print(f'{len(data["items"])} prove: forma, browser, salvataggio, immagini, SVG e ZIP originali nei riquadri e nelle osservazioni, trascinamento, download, nuove schede, campi, allineamento, numerazione e navigazione mobile, formattazione e scorciatoie, conferma, colori degli esiti, evidenze, JSON, clipboard e larghezze verificati.')
    finally:
        server.shutdown()
        server.server_close()


if __name__ == '__main__':
    import sys
    check(sys.argv[1])
