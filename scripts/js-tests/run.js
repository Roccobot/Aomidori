// Tests the page-side script (ReaderScript.swift) in WebKit through Playwright:
//   cd scripts/js-tests && npm install && npx playwright-core install webkit && node run.js
const { webkit } = require('playwright-core');
const fs = require('fs');
const path = require('path');
const swift = fs.readFileSync(path.join(__dirname, '../../Sources/Aomidori/Reader/ReaderScript.swift'), 'utf8');
// The script names its message handler through Swift interpolation: the value comes from there too.
const handlerName = swift.match(/messageHandlerName = "([^"]+)"/)[1];
const script = swift.match(/#"""\n([\s\S]*?)\n\s*"""#/)[1].replaceAll('\\#(messageHandlerName)', handlerName);
const fixture = (name) => path.join(__dirname, 'fixtures', name);
let userCSS = 'body { font-family: "UserFam", serif; color: rgb(1, 2, 3); } .keep { font-family: monospace; }';
const assert = (cond, msg) => { console.log((cond ? 'PASS ' : 'FAIL ') + msg); if (!cond) process.exitCode = 1; };
(async () => {
  const browser = await webkit.launch();
  const page = await browser.newPage({ viewport: { width: 900, height: 700 } });
  await page.route('http://book/**', route => {
    const url = new URL(route.request().url());
    if (url.pathname.startsWith('/.aomidori/Styles/')) return route.fulfill({ body: userCSS, contentType: 'text/css' });
    const p = fixture(decodeURIComponent(url.pathname.slice(1)));
    const type = p.endsWith('.css') ? 'text/css' : p.endsWith('.jpg') ? 'image/jpeg' : p.endsWith('.ttf') ? 'font/ttf' : 'application/xhtml+xml';
    if (!fs.existsSync(p)) return route.fulfill({ status: 404, body: '' });
    route.fulfill({ body: fs.readFileSync(p), contentType: type });
  });
  page.on('pageerror', e => console.log('pageerror:', e.message));
  const base = { overrideEnabled: false, styleHref: '/.aomidori/Styles/u.css?v=1', styleHandlesColorScheme: false, night: false, nightPaletteCSS: '', scale: 1, fontFamily: null, fontFaceCSS: '',
    fontWeight: null, fontBoldWeight: null, fontItalic: false, fontStretch: null, fontFeatureSettings: '', fontVariationSettings: '' };
  await page.addInitScript(script + `\nAomidori.apply(${JSON.stringify(base)});`);
  await page.goto('http://book/c.html');
  await page.waitForTimeout(300);
  const apply = async (c) => { await page.evaluate(c => Aomidori.apply(c), c); await page.waitForTimeout(300); };
  const measure = () => page.evaluate(() => {
    // Visual size whatever the engine's zoom reporting (see zoomFactor in the script).
    const probe = document.createElement('div'); probe.style.cssText = 'position:absolute;zoom:2;height:10px';
    document.documentElement.appendChild(probe); const visual = probe.getBoundingClientRect().height > 15; probe.remove();
    const z = el => { let f = 1; if (!visual) for (let n = el; n && n.nodeType === 1; n = n.parentElement) f *= parseFloat(getComputedStyle(n).zoom) || 1; return f; };
    const r = id => { const el = document.getElementById(id), b = el.getBoundingClientRect(), f = z(el); return { width: b.width * f, height: b.height * f, top: f === 1 ? b.top : (b.top + scrollY) * f - scrollY }; };
    return { h: r('h').width, s: r('s').width, p: r('p5').height, img: r('img').width, imgH: r('img').height, docH: document.documentElement.scrollHeight, scrollW: document.documentElement.scrollWidth, innerW: innerWidth,
      fs: getComputedStyle(document.getElementById('s')).fontSize, p30: r('p30').top };
  });

  const anchorTop = (id) => page.evaluate((id) => {
    const probe = document.createElement('div'); probe.style.cssText = 'position:absolute;zoom:2;height:10px';
    document.documentElement.appendChild(probe); const visual = probe.getBoundingClientRect().height > 15; probe.remove();
    const el = id ? document.getElementById(id) : document.elementFromPoint(innerWidth / 2, Math.round(innerHeight * 0.3));
    let f = 1; if (!visual) for (let n = el; n && n.nodeType === 1; n = n.parentElement) f *= parseFloat(getComputedStyle(n).zoom) || 1;
    const t = el.getBoundingClientRect().top;
    return { id: el.id, top: f === 1 ? t : (t + scrollY) * f - scrollY };
  }, id);

  // 1. Text scale beats px, min() and clamp() !important; pictures keep their size.
  const m1 = await measure();
  await apply({ scale: 1.5 });
  const m2 = await measure();
  console.log(JSON.stringify({ m1, m2 }));
  assert(Math.abs(m2.h / m1.h - 1.5) < 0.05, `clamp()!important heading grows 1.5x (${(m2.h / m1.h).toFixed(3)})`);
  assert(Math.abs(m2.s / m1.s - 1.5) < 0.05, `px/!important text grows 1.5x (${(m2.s / m1.s).toFixed(3)})`);
  assert(m2.p > m1.p * 1.3, `paragraph block (line spacing) grows (${(m2.p / m1.p).toFixed(3)})`);
  assert(Math.abs(m2.img - m1.img) < 1, `image keeps its width (${m1.img} -> ${m2.img})`);
  assert(m2.scrollW <= m2.innerW, 'no horizontal overflow');
  assert(m2.docH > m1.docH * 1.3, `document grows (${(m2.docH / m1.docH).toFixed(3)})`);
  if (process.env.SHOT) await page.screenshot({ path: process.env.SHOT });
  await apply({ scale: 1 });
  const m3 = await measure();
  assert(Math.abs(m3.s - m1.s) < 0.5, '0 restores 100% of the style');

  // Anchor: the visible line stays while scaling.
  await page.evaluate(() => document.getElementById('p30').scrollIntoView());
  const a0 = await anchorTop();
  await apply({ scale: 2 });
  const a1 = await anchorTop(a0.id);
  const top0 = a0.top, top1 = a1.top;
  console.log('anchor tops', a0.id, top0, top1);
  assert(Math.abs(top1 - top0) < 10, 'reading line stays in place when scaling');
  await apply({ scale: 1 });

  // 2. Override ON: the user style's family wins over book fonts; user specificity respected.
  await apply({ overrideEnabled: true });
  await page.waitForTimeout(300);
  const o = await page.evaluate(() => {
    const cs = id => getComputedStyle(document.getElementById(id));
    document.querySelector('p').classList.add('keep');
    const keep = getComputedStyle(document.querySelector('p')).fontFamily;
    document.querySelector('p').classList.remove('keep');
    const faces = []; document.fonts.forEach(f => faces.push(f.family + ':' + f.status));
    return { s: cs('s').fontFamily, inline: cs('inline').fontFamily, f: cs('f').fontFamily, fColor: cs('f').color, keep, faces,
      bookActive: [...document.styleSheets].filter(s => s.ownerNode.id === '' && s.media.mediaText !== 'not all').length };
  });
  console.log(JSON.stringify(o));
  assert(/UserFam/.test(o.s) && !/BookFam/.test(o.s), 'override: book #x p.y !important family loses to the user family');
  assert(/UserFam/.test(o.inline), 'override: inline !important family loses');
  assert(/UserFam/.test(o.f) && o.fColor === 'rgb(1, 2, 3)', 'override: <font face color> loses');
  assert(o.keep === 'monospace', 'override: user CSS specificity is respected');
  assert(!o.faces.some(f => /BookFam|UserFam/.test(f)), 'override: book @font-face rules are not registered');
  assert(o.bookActive === 0, 'override: no book sheet active');

  // 3. Custom font: beats book and user CSS, !important and inline !important; code is exempt.
  const fontFaceCSS = '@font-face { font-family: "aomidori-custom-font"; src: local("Nope"); }';
  for (const override of [false, true]) {
    await apply({ overrideEnabled: override, fontFamily: '"aomidori-custom-font", "Zapfino"', fontFaceCSS });
    const c = await page.evaluate(() => {
      const cs = id => getComputedStyle(document.getElementById(id)).fontFamily;
      return { s: cs('s'), inline: cs('inline'), f: cs('f'), c: cs('c'), h: cs('h'), size: getComputedStyle(document.getElementById('s')).fontSize };
    });
    console.log(JSON.stringify(c));
    assert(['s', 'inline', 'f', 'h'].every(k => /aomidori-custom-font/.test(c[k])), `custom font wins everywhere (override ${override})`);
    assert(!/aomidori-custom-font/.test(c.c), `code keeps its family (override ${override})`);
  }
  await apply({ overrideEnabled: false, fontFamily: null, fontFaceCSS: '' });
  const r = await page.evaluate(() => ({ inline: document.getElementById('inline').getAttribute('style'), f: document.getElementById('f').getAttribute('face') }));
  assert(/InlineFam.*important/.test(r.inline || '') && r.f === 'FaceFam', `book inline styles and attributes restored (${r.inline}, ${r.f})`);

  // 4. Live reload: a new version of the same file swaps in without moving the reading line.
  await apply({ overrideEnabled: true });
  await page.evaluate(() => document.getElementById('p30').scrollIntoView());
  const a2 = await anchorTop();
  const before = a2.top;
  userCSS = 'body { font-family: serif; color: rgb(9, 8, 7); } p { margin: 3em 0; }';
  await apply({ styleHref: '/.aomidori/Styles/u.css?v=2' });
  await page.waitForTimeout(500);
  const after = await page.evaluate(() => ({ color: getComputedStyle(document.body).color,
    links: document.querySelectorAll('link[data-aomidori]').length }));
  after.top = (await anchorTop(a2.id)).top;
  console.log(JSON.stringify({ before, after }));
  assert(after.color === 'rgb(9, 8, 7)', 'reloaded style applied');
  assert(after.links === 1, 'one user link after the swap');
  assert(Math.abs(after.top - before) < 10, 'reading line kept across reload');

  // 6. Saved positions: the element anchor brings back the reading line after a reload with
  // another text size and style; the fraction is the fallback.
  await apply({ overrideEnabled: false, scale: 1 });
  await page.evaluate(() => { const el = document.getElementById('p30'); scrollTo(0, el.getBoundingClientRect().top + scrollY - innerHeight * 0.3 + 7); });
  await page.waitForTimeout(100);
  const saved = await page.evaluate(() => Aomidori.position());
  console.log('saved position', JSON.stringify(saved));
  assert(/^\d+(\.\d+)*@-?[\d.]+$/.test(saved.anchor || '') && saved.fraction > 0 && saved.fraction < 1, 'position has a fraction and an element anchor');
  const lineElement = () => page.evaluate(() => {
    const el = document.elementFromPoint(innerWidth / 2, Math.round(innerHeight * 0.3));
    return el && (el.id || (el.parentElement && el.parentElement.id));
  });
  const before6 = await lineElement();
  for (const mode of [{ scale: 1.8 }, { scale: 0.7, overrideEnabled: true }]) {
    await page.goto('http://book/c.html');
    await page.waitForTimeout(300);
    await apply(mode);
    await page.evaluate(p => Aomidori.restorePosition(p), saved);
    await page.waitForTimeout(100);
    assert(await lineElement() === before6, `restored to the same paragraph (${before6}) with ${JSON.stringify(mode)}`);
  }
  await page.evaluate(p => Aomidori.restorePosition(p), { fraction: 0.5, anchor: '999.3@0.5' });
  const fallback = await page.evaluate(() => Aomidori.fraction());
  assert(Math.abs(fallback - 0.5) < 0.01, `an anchor that no longer resolves falls back to the fraction (${fallback.toFixed(3)})`);
  await page.evaluate(p => Aomidori.restorePosition(p), { fraction: 0, anchor: null });
  assert(await page.evaluate(() => scrollY) === 0, 'fraction 0 is the top');
  await apply({ scale: 1, overrideEnabled: false });

  // 7. Edges and position reports, as native code receives them.
  {
    const p = await browser.newPage({ viewport: { width: 900, height: 700 } });
    await p.route('http://book/**', route => {
      const f = fixture(decodeURIComponent(new URL(route.request().url()).pathname.slice(1)));
      if (!fs.existsSync(f)) return route.fulfill({ status: 404, body: '' });
      route.fulfill({ body: fs.readFileSync(f), contentType: f.endsWith('.jpg') ? 'image/jpeg' : f.endsWith('.css') ? 'text/css' : 'application/xhtml+xml' });
    });
    await p.addInitScript((name) => { window.__messages = []; window.webkit = { messageHandlers: { [name]: { postMessage: (m) => window.__messages.push(m) } } }; }, handlerName);
    await p.addInitScript(script + `\nAomidori.apply(${JSON.stringify(base)});`);
    const edges = () => p.evaluate(() => window.__messages.filter(m => m.type === 'edges').map(m => `${m.atTop} ${m.atBottom}`));
    await p.goto('http://book/c.html');
    await p.waitForLoadState('load');
    await p.waitForTimeout(100);
    assert((await edges()).join('|') === 'true false', `a long chapter starts at the top edge only (${(await edges()).join('|')})`);
    await p.evaluate(() => scrollTo(0, 300));
    await p.waitForTimeout(100);
    await p.evaluate(() => scrollTo(0, document.documentElement.scrollHeight));
    await p.waitForTimeout(400);
    assert((await edges()).join('|') === 'true false|false false|false true', `edges follow scrolling, once per change (${(await edges()).join('|')})`);
    const report = await p.evaluate(() => window.__messages.filter(m => m.type === 'position').pop());
    assert(report && report.href === 'http://book/c.html' && report.fraction === 1, `position reports carry the document and fraction (${JSON.stringify(report)})`);
    await p.goto('http://book/cover-img.html');
    await p.waitForLoadState('load');
    await p.waitForTimeout(100);
    assert((await edges()).pop() === 'true true', 'an image page is at both edges');
    await p.close();
  }

  // 8. Custom font weight, width, italic and features: bold stays relative to the chosen weight.
  {
    const p = await browser.newPage({ viewport: { width: 900, height: 700 } });
    await p.route('http://book/**', route => {
      const url = new URL(route.request().url());
      if (url.pathname.startsWith('/.aomidori/Styles/')) return route.fulfill({ body: 'p { font-weight: 400; } h2 { font-weight: 700; }', contentType: 'text/css' });
      const f = fixture(decodeURIComponent(url.pathname.slice(1)));
      if (!fs.existsSync(f)) return route.fulfill({ status: 404, body: '' });
      route.fulfill({ body: fs.readFileSync(f), contentType: 'application/xhtml+xml' });
    });
    await p.addInitScript(script + `\nAomidori.apply(${JSON.stringify(base)});`);
    await p.goto('http://book/font.html');
    await p.waitForLoadState('load');
    const font = { fontFamily: '"aomidori-custom-font", "Georgia"', fontFaceCSS: '' };
    const read = () => p.evaluate(() => {
      const cs = (id) => getComputedStyle(document.getElementById(id));
      const out = {};
      for (const id of ['h2', 'p', 'b', 'strong', 'heavy', 'light', 'em', 'slanted', 'code']) {
        const s = cs(id); out[id] = { w: s.fontWeight, i: s.fontStyle, st: s.fontStretch, f: s.fontFeatureSettings, v: s.fontVariationSettings, fam: s.fontFamily };
      }
      return out;
    });
    const set = async (c) => { await p.evaluate(c => Aomidori.apply(c), c); await p.waitForTimeout(150); };

    await set(Object.assign({}, font, { fontWeight: null, fontBoldWeight: null }));
    let r = await read();
    assert(r.p.w === '400' && r.b.w === '700' && r.light.w === '300' && /aomidori-custom-font/.test(r.p.fam),
      `no chosen weight: the CSS weights stay (${r.p.w} ${r.b.w} ${r.light.w})`);

    await set(Object.assign({}, font, { fontWeight: 300, fontBoldWeight: 600, fontStretch: 75, fontFeatureSettings: '"smcp" 1, "onum" 1', fontVariationSettings: '"opsz" 20' }));
    r = await read();
    console.log(JSON.stringify(r));
    assert(r.p.w === '300' && r.light.w === '300' && r.em.w === '300', `light choice: regular text at 300 (${r.p.w} ${r.light.w} ${r.em.w})`);
    assert(['h2', 'b', 'strong', 'heavy'].every(k => r[k].w === '600'), `bold text at 600 (${['h2', 'b', 'strong', 'heavy'].map(k => r[k].w)})`);
    assert(r.p.st === '75%' && /smcp/.test(r.p.f) && /opsz/.test(r.p.v), `width, features and axes apply (${r.p.st} ${r.p.f} ${r.p.v})`);
    assert(!/aomidori/.test(r.code.fam) && r.code.st === '100%' && r.code.f === 'normal' && r.code.v === 'normal',
      `code keeps its own family, no width, features or axes (${r.code.fam} ${r.code.st} ${r.code.f})`);
    assert(r.em.i === 'italic' && r.p.i === 'normal', 'emphasis stays italic');

    await set(Object.assign({}, font, { fontWeight: 700, fontBoldWeight: 900, fontItalic: true, fontStretch: null, fontFeatureSettings: '', fontVariationSettings: '' }));
    r = await read();
    assert(r.p.w === '700' && r.b.w === '900', `heavy choice: 700 and bold 900 (${r.p.w} ${r.b.w})`);
    assert(r.p.i === 'italic' && r.em.i === 'normal' && r.slanted.i === 'normal', `italic choice: text italic, emphasis upright (${r.p.i} ${r.em.i} ${r.slanted.i})`);
    assert(r.p.st === '100%' && r.p.f === 'normal', `width and features reset (${r.p.st} ${r.p.f})`);

    // Under the override the user style decides what is bold: its h2 is 700, still bold.
    await set({ overrideEnabled: true, fontWeight: 350, fontBoldWeight: 650, fontItalic: false });
    await p.waitForTimeout(300);
    r = await read();
    assert(r.h2.w === '650' && r.p.w === '350' && r.b.w === '650', `override: bold from the user style maps to 650 (${r.h2.w} ${r.p.w} ${r.b.w})`);

    await set({ overrideEnabled: false, fontFamily: null, fontWeight: null, fontBoldWeight: null });
    r = await read();
    const marks = await p.evaluate(() => document.querySelectorAll('[data-aomidori-bold], [data-aomidori-italic]').length);
    assert(r.b.w === '700' && r.p.w === '400' && marks === 0, `custom font off: weights and marks gone (${r.b.w} ${marks})`);
    await p.close();
  }

  // 5. Image pages (covers): centred in the viewport, whole, not scrollable, in every mode.
  userCSS = 'body { max-width: 34em; margin: 0 auto; padding: 0 1.2em; } img { width: 50%; margin-top: 4em; } p { margin: 2em 0; }';
  const coverPages = ['cover-img.html', 'cover-svg.html', 'cover-marked.html', 'cover-small.html'];
  const modes = [
    { overrideEnabled: false, scale: 1, night: false },
    { overrideEnabled: true, scale: 1.6, night: false, styleHref: '/.aomidori/Styles/u.css?v=3' },
    { overrideEnabled: true, scale: 0.8, night: true, nightPaletteCSS: 'html, body { background: #222 !important; }', styleHref: '/.aomidori/Styles/u.css?v=3' },
  ];
  for (const [width, height] of [[480, 900], [1400, 600], [900, 700]]) {
    const p = await browser.newPage({ viewport: { width, height } });
    await p.route('http://book/**', route => {
      const url = new URL(route.request().url());
      if (url.pathname.startsWith('/.aomidori/Styles/')) return route.fulfill({ body: userCSS, contentType: 'text/css' });
      const f = fixture(decodeURIComponent(url.pathname.slice(1)));
      if (!fs.existsSync(f)) return route.fulfill({ status: 404, body: '' });
      route.fulfill({ body: fs.readFileSync(f), contentType: f.endsWith('.jpg') ? 'image/jpeg' : f.endsWith('.css') ? 'text/css' : 'application/xhtml+xml' });
    });
    p.on('pageerror', e => console.log('pageerror:', e.message));
    await p.addInitScript(script + `\nAomidori.apply(${JSON.stringify(base)});`);
    for (const name of coverPages) {
      await p.goto('http://book/' + name);
      await p.waitForLoadState('load');
      for (const mode of modes) {
        await p.evaluate(c => Aomidori.apply(c), mode);
        await p.waitForTimeout(150);
        const r = await p.evaluate(() => {
          const el = document.querySelector('[data-aomidori-cover]');
          if (!el) return null;
          // An SVG letterboxes its picture: measure the picture inside it.
          const target = el.localName === 'svg' ? el.querySelector('image') : el;
          const b = target.getBoundingClientRect();
          scrollBy(0, 400);
          return { marked: document.documentElement.classList.contains('aomidori-image-page'), left: b.left, right: innerWidth - b.right,
            top: b.top, bottom: innerHeight - b.bottom, w: b.width, h: b.height, scrollY, iw: innerWidth, ih: innerHeight };
        });
        const tag = `${name} ${width}x${height} override=${mode.overrideEnabled} scale=${mode.scale} night=${mode.night}`;
        if (!r) { assert(false, `${tag}: image page detected`); continue; }
        const centred = Math.abs(r.left - r.right) < 1.5 && Math.abs(r.top - r.bottom) < 1.5;
        const inside = r.left >= -0.5 && r.top >= -0.5 && r.right >= -0.5 && r.bottom >= -0.5;
        const fills = name === 'cover-small.html' || Math.min(r.left, r.right) < 1 || Math.min(r.top, r.bottom) < 1;
        assert(r.marked && centred && inside && fills && r.scrollY === 0,
          `${tag}: centred (${r.left.toFixed(1)}|${r.right.toFixed(1)} ${r.top.toFixed(1)}|${r.bottom.toFixed(1)} ${r.w.toFixed(0)}x${r.h.toFixed(0)}), whole, fits, no scroll (${r.scrollY})`);
      }
    }
    if (process.env.SHOT && width === 480) await p.screenshot({ path: process.env.SHOT.replace('.png', '-cover.png') });
    await p.goto('http://book/not-cover.html');
    await p.waitForLoadState('load');
    assert(!(await p.evaluate(() => document.documentElement.classList.contains('aomidori-image-page'))), `${width}x${height}: a page with text and a figure is not an image page`);
    await p.close();
  }
  await browser.close();
})();
