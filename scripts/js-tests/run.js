// Tests the page-side script (ReaderScript.swift) in WebKit through Playwright:
//   cd scripts/js-tests && npm install && npx playwright-core install webkit && node run.js
const { webkit } = require('playwright-core');
const fs = require('fs');
const path = require('path');
const swift = fs.readFileSync(path.join(__dirname, '../../Sources/Aomidori/Reader/ReaderScript.swift'), 'utf8');
const script = swift.match(/#"""\n([\s\S]*?)\n\s*"""#/)[1];
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
  const base = { overrideEnabled: false, styleHref: '/.aomidori/Styles/u.css?v=1', styleHandlesColorScheme: false, night: false, nightPaletteCSS: '', scale: 1, fontFamily: null, fontFaceCSS: '' };
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
  await browser.close();
})();
