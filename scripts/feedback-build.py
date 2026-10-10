#!/usr/bin/env python3
"""Build the static feedback document from the canonical Markdown and app version."""
from pathlib import Path
import hashlib
import html
import json
import plistlib
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
# The project and the three outcomes are written here only: the page reads them from the
# embedded data, and the CSS colours an outcome through its kind, never through its label.
PROJECT = 'Aomidori'
OUTCOMES = [('Tutto OK', 'ok'), ('Accettabile', 'warn'), ('Non approvato', 'bad')]


def option(name, default):
    """`--source FILE` and `--output FILE` let `feedback-interactive-check.py` build a
    throwaway page from a synthetic source with the real generator and template, so a
    document with no open tests can still be exercised without a second copy of the markup."""
    if name in sys.argv:
        return Path(sys.argv[sys.argv.index(name) + 1])
    return default


md = option('--source', ROOT / 'docs/Feedback.md').read_text()
# The app's version has one source, CFBundleShortVersionString in Resources/Info.plist.
version = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())['CFBundleShortVersionString']
identifiers = re.findall(r'^\| (\d+\.\d+-\d+) \|', md, re.M)
items = []
def inline_md(text):
    """Render code, links, bold, italic used in Feedback.md paragraphs."""
    out = []
    i = 0
    n = len(text)
    while i < n:
        if text[i] == "`":
            j = text.find("`", i + 1)
            if j != -1:
                out.append("<code>" + html.escape(text[i + 1:j]) + "</code>")
                i = j + 1
                continue
        m = re.match(r"\[((?:\\.|[^\]\\])+)\]\((https?://[^\s)]+)\)", text[i:])
        if m:
            label = re.sub(r"\\([\\*`\[\]_])", r"\1", m.group(1))
            href = html.escape(m.group(2), quote=True)
            out.append(f'<a target="_blank" rel="noopener noreferrer" href="{href}">' + inline_md(label) + "</a>")
            i += m.end()
            continue
        matched = False
        for marker, open_t, close_t in (
            ("***", "<strong><em>", "</em></strong>"),
            ("**", "<strong>", "</strong>"),
            ("*", "<em>", "</em>"),
            ("_", "<em>", "</em>"),
        ):
            if not text.startswith(marker, i):
                continue
            end = i + len(marker)
            while end < n:
                if text[end] == "\\":
                    end += 2
                    continue
                if text.startswith(marker, end):
                    break
                end += 1
            if end >= n or end <= i + len(marker):
                continue
            body = text[i + len(marker):end]
            out.append(open_t + inline_md(body) + close_t)
            i = end + len(marker)
            matched = True
            break
        if matched:
            continue
        if text[i] == "\\" and i + 1 < n and text[i + 1] in "\\*`[]_":
            out.append(html.escape(text[i + 1]))
            i += 2
        else:
            out.append(html.escape(text[i]))
            i += 1
    return "".join(out)

for match in re.finditer(r'^## (\d+)\. ([^\n]+)\n(.*?)(?=^## |\Z)', md, re.M | re.S):
    number = int(match[1])
    identifier = identifiers[number - 1]
    paragraphs = []
    for p in match[3].strip().split('\n\n'):
        flat = re.sub(r'\s*\n\s*', ' ', p).strip()
        if flat:
            paragraphs.append(flat)
    items.append(dict(id=identifier, version=identifier.rsplit('-', 1)[0], title=match[2],
                      paragraphs=paragraphs))
# Optional "Etichette testuali" section: each `### id[ · title]` heading plus its body is the
# proposed Italian text. The string keys a label covers are its id without `e-` and the ones
# named in a `<!-- chiavi: a b c -->` comment, so one card can hold a family of short strings.
labels = []
label_keys = set()
labels_match = re.search(r'^## Etichette testuali\n(.*?)(?=^## |\Z)', md, re.M | re.S)
if labels_match:
    for lm in re.finditer(r'^### ([^\n]+)\n(.*?)(?=^### |\Z)', labels_match[1], re.M | re.S):
        head = lm[1].strip()
        if ' · ' in head:
            lid, ltitle = head.split(' · ', 1)
        else:
            lid, ltitle = head, head
        raw = lm[2]
        notes = ' '.join(re.findall(r'<!--(.*?)-->', raw, re.S))
        a11y = bool(re.search(r'contentdescription|talkback|screen reader|non visibile|solo lettore|\baria\b', notes + ' ' + head, re.I))
        proposal = re.sub(r'<!--.*?-->', '', raw, flags=re.S).strip()
        if not proposal:
            raise SystemExit(f'Etichetta {lid}: manca il testo ITA proposto')
        entry = dict(id=lid.strip(), title=ltitle.strip(), proposal=proposal)
        if a11y:
            entry['a11y'] = True
        labels.append(entry)
        label_keys.add(entry['id'][2:] if entry['id'].startswith('e-') else entry['id'])
        for comment in re.findall(r'<!--(.*?)-->', raw, re.S):
            named = re.match(r'\s*chiavi:(.*)', comment, re.S)
            if named:
                label_keys.update(named[1].replace(',', ' ').split())


# Optional "Domande" section, after the tests and before the labels (the user's rule of
# 2026-10-08: numbered blocks are tests of one feature each, and the questions taken from the
# brief live in a block of their own). Each `### d-key · title` holds the question; a paragraph
# that opens with `**C1**:` is an option, the one that opens with `Parere:` names the advised
# option in bold. The answer is saved under the draft's `decisions`, which schema 1 kept.
def parse_questions(text):
    found = []
    section = re.search(r'^## Domande\n(.*?)(?=^## |\Z)', text, re.M | re.S)
    if not section:
        return found
    for qm in re.finditer(r'^### ([^\n]+)\n(.*?)(?=^### |\Z)', section[1], re.M | re.S):
        head = qm[1].strip()
        if ' · ' not in head:
            raise SystemExit(f'Domanda {head}: il titolo vuole la forma `### d-chiave · titolo`')
        qid, qtitle = (part.strip() for part in head.split(' · ', 1))
        if not re.fullmatch(r'd-[a-z0-9-]+', qid):
            raise SystemExit(f'Domanda {qid}: la chiave deve essere `d-` seguito da minuscole, cifre e trattini')
        paragraphs, options, advice, advice_text = [], [], None, ''
        for p in qm[2].strip().split('\n\n'):
            flat = re.sub(r'\s*\n\s*', ' ', p).strip()
            if not flat:
                continue
            option_match = re.match(r'\*\*([A-Z][A-Za-z0-9]{0,5})\*\*:\s*(.+)', flat)
            if option_match:
                options.append(dict(key=option_match[1], text=option_match[2]))
            elif flat.startswith('Parere:'):
                advised = re.search(r'\*\*([A-Z][A-Za-z0-9]{0,5})\*\*', flat)
                advice, advice_text = (advised[1] if advised else None), flat
            else:
                paragraphs.append(flat)
        keys = [option['key'] for option in options]
        if len(set(keys)) != len(keys):
            raise SystemExit(f'Domanda {qid}: due opzioni con la stessa lettera')
        if options and advice not in keys:
            raise SystemExit(f'Domanda {qid}: il paragrafo `Parere:` deve nominare in grassetto una delle opzioni')
        if not paragraphs:
            raise SystemExit(f'Domanda {qid}: manca il testo della domanda')
        found.append(dict(id=qid, title=qtitle, paragraphs=paragraphs, options=options,
                          advice=advice, adviceText=advice_text))
    return found


questions = parse_questions(md)
if len({question['id'] for question in questions}) != len(questions):
    raise SystemExit('Due domande con la stessa chiave')


# Every Italian interface text that is new or changed since the user last approved it is listed
# under "Etichette testuali", the ones he picked himself included (his rule, restated on
# 2026-10-08 after the DFs from 4.02 to 4.64 showed none while 64 texts came in). The approved
# texts live in docs/Labels-approved.json; `--approve-labels` records the current text of every
# key the labels cover, once his answers to them are applied. A throwaway build (`--source`)
# skips the check: it exercises the page, it is not a document.
APPROVED = ROOT / 'docs/Labels-approved.json'


ITALIAN = ROOT / 'Resources/it.lproj/Localizable.strings'


def italian_strings():
    """The Italian interface texts, `"key" = "text";` per line, with \\" and \\n unescaped."""
    texts = {}
    entry = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$')
    for line in ITALIAN.read_text().splitlines():
        match = entry.match(line)
        if match:
            texts[match[1]] = re.sub(r'\\(.)', lambda m: '\n' if m[1] == 'n' else m[1], match[2])
    return texts


if '--approve-labels' in sys.argv:
    current, approved = italian_strings(), json.loads(APPROVED.read_text())
    for key in sorted(label_keys):
        if key not in current:
            raise SystemExit(f'Etichetta {key}: la chiave non esiste in it.lproj/Localizable.strings')
        approved[key] = current[key]
        print(f'approvata {key}: {current[key]}')
    APPROVED.write_text(json.dumps(dict(sorted(approved.items())), ensure_ascii=False, indent=1) + '\n')
    sys.exit(0)
if '--source' not in sys.argv:
    approved = json.loads(APPROVED.read_text())
    unsubmitted = [key for key, text in italian_strings().items()
                   if approved.get(key) != text and key not in label_keys]
    if unsubmitted:
        raise SystemExit('Testi italiani nuovi o cambiati senza etichetta nel DF (' + str(len(unsubmitted)) +
                         '): ' + ', '.join(sorted(unsubmitted)) +
                         '. Mettili in "Etichette testuali" (docs/Feedback-maintenance.md).')
data = dict(project=PROJECT, version=version, items=items, questions=questions, labels=labels,
            outcomes=[dict(label=label, kind=kind) for label, kind in OUTCOMES])
next_match = re.search(r'^## Prossimi passi\n(.*?)(?=^## |\Z)', md, re.M | re.S)
if not next_match:
    raise SystemExit('docs/Feedback.md deve contenere la sezione Prossimi passi')
next_steps = []
for line in next_match[1].splitlines():
    if line.startswith('- '):
        next_steps.append(line[2:].strip())
if not next_steps:
    raise SystemExit('la sezione Prossimi passi deve contenere almeno una voce')
next_steps_html = '<section class=\"card next-steps\"><h2>Prossimi passi</h2><ul>'
next_steps_html += ''.join('<li>' + inline_md(step) + '</li>' for step in next_steps)
next_steps_html += '</ul></section>'
# The "Aggiornamenti recenti" card is built from the table in docs/Feedback.md, so the closed
# results live in one place. One sentence per round, newest first, e.g.
# "Giro 1.10: vista divisa 1.10-01 OK."; an empty table leaves the card out.
concluded = []
concluded_match = re.search(r'^## Aggiornamenti recenti\n(.*?)(?=^## |\Z)', md, re.M | re.S)
if concluded_match:
    for line in concluded_match[1].splitlines():
        cells = [c.strip() for c in line.strip().strip('|').split('|')]
        if len(cells) < 3 or not re.fullmatch(r'\d+\.\d+-\d+', cells[1]):
            continue
        concluded.append((cells[1], cells[0], cells[2]))
rounds = {}
for identifier, feature, status in concluded:
    rounds.setdefault(identifier.rsplit('-', 1)[0], []).append(
        (feature[:1].lower() + feature[1:]) + ' ' + identifier + ' ' + status)
concluded_html = ''
if rounds:
    ordered = sorted(rounds, key=lambda v: tuple(int(x) for x in v.split('.')), reverse=True)
    sentence = ' '.join('Giro ' + v + ': ' + ', '.join(rounds[v]) + '.' for v in ordered)
    concluded_html = ('<section class="card archive"><h2>Aggiornamenti recenti</h2><p>'
                      + inline_md(sentence) + '</p></section>')
esc = html.escape
cards = []
for index, item in enumerate(items, 1):
    cards.append(f'<article class="card test" id="{item["id"]}" data-id="{item["id"]}"><p class="check-position">Verifica <strong>{index}</strong>/{len(items)}</p><p class="eyebrow">{item["id"]} · Aomidori {item["version"]}</p><h3>{esc(item["title"])}</h3>')
    cards.extend('<p>' + inline_md(p) + '</p>' for p in item['paragraphs'])
    cards.append('<fieldset><legend>Esito della prova</legend>')
    for status, kind in OUTCOMES:
        cards.append(f'<button type="button" class="outcome" data-status="{status}" data-kind="{kind}" aria-pressed="false">{status}</button>')
    cards.append('</fieldset><label>Commento<textarea class="comment" rows="3"></textarea></label><label class="attachment" aria-label="Allega file o trascinali qui"><span class="attachment-plus" aria-hidden="true">+</span><input class="images" aria-label="Allega file o trascinali qui" type="file" accept="image/png,image/jpeg,image/webp,image/gif,image/svg+xml,.svg,application/zip,application/x-zip-compressed,.zip" multiple></label><div class="image-list"></div></article>')
# The questions: no number and no outcome. An option is a toggle (a second tap clears it), and
# `Rimando` keeps the question in the brief for ten more rounds.
questions_html = ''
if questions:
    parts = ['<section id="questions"><h2>Domande</h2><p>Domande del brief, da decidere. Tocca '
             'un\'opzione, o <strong>Rimando</strong> per lasciarla nel brief altri dieci giri; '
             'un secondo tocco la toglie. Non sono prove di collaudo.</p>']
    for question in questions:
        qid = esc(question['id'])
        parts.append(f'<article class="card question" id="{qid}" data-id="{qid}"><p class="question-id">{qid}</p><h3>{inline_md(question["title"])}</h3>')
        parts.extend('<p>' + inline_md(p) + '</p>' for p in question['paragraphs'])
        parts.append('<fieldset class="choices"><legend>Risposta</legend>')
        for choice in question['options']:
            tag = '<span class="advised">parere</span>' if choice['key'] == question['advice'] else ''
            parts.append(f'<button type="button" class="choice" data-choice="{esc(choice["key"])}" aria-pressed="false"><strong>{esc(choice["key"])}</strong> {inline_md(choice["text"])}{tag}</button>')
        parts.append('<button type="button" class="choice postpone" data-choice="rimando" aria-pressed="false">Rimando</button></fieldset>')
        if question['adviceText']:
            parts.append('<p class="advice">' + inline_md(question['adviceText']) + '</p>')
        parts.append('<label>Commento<textarea class="question-comment" rows="3"></textarea></label></article>')
    parts.append('</section>')
    questions_html = ''.join(parts)

tpl = (Path(__file__).resolve().parent / 'feedback-page.html.in').read_text()
page = (tpl
    .replace('__TOTAL__', str(len(items)))
    .replace('__VERSION__', version)
    .replace('__CARDS__', '\n'.join(cards))
    .replace('__QUESTIONS__', questions_html)
    .replace('__NEXT_STEPS__', next_steps_html)
    .replace('__CONCLUDED__', concluded_html)
    .replace('__DATA__', json.dumps(data, ensure_ascii=False).replace('<', '\\u003c')))
# Each local file the page loads carries `?v=` plus the start of its own SHA-256, so a
# browser fetches it again exactly when it changes; nobody bumps a number by hand.
def versioned(match):
    path = ROOT / 'publish' / match[1]
    if not path.is_file():
        raise SystemExit(f'Il modello carica {match[1]}, che non esiste in publish/.')
    return match[1] + '?v=' + hashlib.sha256(path.read_bytes()).hexdigest()[:10]


page = re.sub(r'([\w./-]+)\?v=__HASH__', versioned, page)
if '__HASH__' in page:
    raise SystemExit('Un segnaposto __HASH__ del modello non è stato sostituito.')
output = option('--output', ROOT / 'publish/feedback.html')
if '--check' in sys.argv:
    if not output.exists() or output.read_text() != page:
        sys.exit('Il documento HTML non corrisponde a docs/Feedback.md: esegui scripts/feedback-build.py.')
    print(f'Documento HTML allineato alle {len(items)} prove, {len(questions)} domande, {len(labels)} etichette e alla versione {version}')
else:
    output.write_text(page)
    print('Creato ' + str(output))
