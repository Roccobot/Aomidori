import Foundation
import AomidoriCore

/// The page-side half of the rendering layer. It runs in an isolated content world
/// (`WKContentWorld.defaultClient`) at document start, before the book's markup is parsed,
/// so book scripts (disabled anyway) can never see or alter it.
///
/// Layers, in cascade order:
/// 1. `base`: no horizontal scrolling, media never wider than the window. Inserted first, so any
///    book or user rule wins over these. It also declares the `aomidori` cascade layer first,
///    which makes the `!important` rules placed in it beat every other author rule, whatever its
///    specificity or position (CSS Cascade 5); the image-page layout (covers whole and centred in
///    the window, in every mode) lives there.
/// 2. the book's own `<link>`/`<style>` sheets and inline styles, disabled when overriding;
/// 3. `user`: the selected user style (`<link>`, so its relative URLs resolve in the styles folder);
/// 4. `palette`: Night colors, only when the active CSS has no `prefers-color-scheme` rules;
/// 5. `scale` (layer `aomidori`): the text size, as CSS `zoom` on the body with images
///    counter-zoomed; see `refreshScale`.
/// 6. `font` (layer `aomidori`): the app's custom font, when on, for all text: family, and the
///    chosen weight (bold text relative to it), width, italic, features and variable axes.
///
/// Native code drives it with `Aomidori.apply(configuration)`; see `ReaderConfiguration`.
enum ReaderScript {
    static func source(configuration: ReaderConfiguration) -> String {
        body + "\nAomidori.apply(\(configuration.json()));\n"
    }

    static func applyCall(_ configuration: ReaderConfiguration) -> String {
        "window.Aomidori && Aomidori.apply(\(configuration.json()));"
    }

    static let messageHandlerName = "aomidori"

    private static let body = #"""
    (() => {
      'use strict';
      if (window.Aomidori) return;

      const XHTML = 'http://www.w3.org/1999/xhtml';
      const SVG = 'http://www.w3.org/2000/svg';
      const OWN = 'data-aomidori';
      const MEDIA_STASH = 'data-aomidori-media';
      const STYLE_STASH = 'data-aomidori-style';
      const FONT_STASH = 'data-aomidori-font';
      const ATTR_STASH = 'data-aomidori-attrs';
      // Legacy presentational attributes that would keep the book's typography under an override.
      const PRESENTATIONAL = { font: ['face', 'size', 'color'], basefont: ['face', 'size', 'color'] };
      const NO_MEDIA = '-';
      // Inline styles on these elements usually carry intrinsic sizing: kept when overriding.
      const KEEP_INLINE = new Set(['img', 'svg', 'image', 'video', 'audio', 'canvas', 'picture', 'object', 'embed', 'iframe', 'math']);
      const IMAGE_PAGE = 'aomidori-image-page';
      // On an image page: the picture itself, and the elements around it (laid out as `contents`).
      const COVER = 'data-aomidori-cover';
      const COVER_WRAP = 'data-aomidori-cover-wrap';
      const OPS = 'http://www.idpf.org/2007/ops';
      // Text that keeps its own family under the custom font: code and formulas.
      const FONT_EXEMPT = 'code, pre, kbd, samp, tt, var, math, math *';
      // Replaced content that keeps its size when the text is scaled.
      const MEDIA = ':is(img, svg, video, canvas, iframe, object, embed):not(svg *)';
      // A page that is just one picture (a cover, a plate) is centred in the window, whole,
      // whatever the book or user CSS and the text size say: the body becomes a viewport-sized
      // flex box, the wrappers around the picture drop their boxes, anything else is hidden,
      // and nothing scrolls. In the `aomidori` layer, so no author rule can undo it.
      const PAGE = `html.${IMAGE_PAGE}`;
      const IMAGE_PAGE_CSS = [
        `${PAGE}, ${PAGE} body { overflow: hidden !important; }`,
        `${PAGE} body { display: flex !important; flex-direction: column !important; align-items: center !important;`,
        '  justify-content: center !important; box-sizing: border-box !important; width: auto !important;',
        '  max-width: none !important; min-width: 0 !important; height: 100vh !important; min-height: 0 !important;',
        '  max-height: none !important; margin: 0 !important; padding: 0 !important; border: 0 !important;',
        '  zoom: 1 !important; columns: auto !important; }',
        `${PAGE} body *:not([${COVER_WRAP}], [${COVER}], [${COVER}] *) { display: none !important; }`,
        `${PAGE} [${COVER_WRAP}] { display: contents !important; }`,
        `${PAGE} [${COVER}] { display: block !important; flex: none !important; box-sizing: border-box !important;`,
        '  margin: 0 !important; padding: 0 !important; border: 0 !important; float: none !important;',
        '  position: static !important; transform: none !important; zoom: 1 !important;',
        '  width: auto !important; height: auto !important; min-width: 0 !important; min-height: 0 !important;',
        '  max-width: 100vw !important; max-height: 100vh !important; object-fit: contain !important; }',
        // An SVG with a viewBox scales to the window and letterboxes itself (preserveAspectRatio).
        `${PAGE} svg[${COVER}="fit"] { width: 100vw !important; height: 100vh !important; }`,
      ];
      const BASE_CSS = [
        '@layer aomidori;',
        'html { overflow-x: hidden !important; }',
        'img, video, svg { max-width: 100% !important; }',
        'img, video { object-fit: contain; }',
        '@layer aomidori {',
        ...IMAGE_PAGE_CSS,
        '}',
      ].join('\n');

      const doc = document;
      let root = doc.documentElement;
      let mounted = false;
      let config = {
        overrideEnabled: false, styleHref: null, styleHandlesColorScheme: false, night: false,
        nightPaletteCSS: '', scale: 1, fontFamily: null, fontFaceCSS: '', justified: false,
      };
      let parsing = doc.readyState === 'loading';

      // The reader's own elements are known by identity, never by an attribute a book could
      // write too; book elements lose any `data-aomidori…` attribute the first time they are
      // seen, so a stash or a mark can only come from this script.
      const owned = new WeakSet();
      const seen = new WeakSet();
      const isOwn = (el) => owned.has(el);
      function dropForgedMarks(el) {
        if (seen.has(el) || owned.has(el)) return;
        seen.add(el);
        for (const name of el.getAttributeNames()) if (name.startsWith(OWN)) el.removeAttribute(name);
      }
      const ownElement = (name, role) => {
        const el = doc.createElementNS(XHTML, name);
        el.setAttribute(OWN, role);
        el.id = `aomidori-${role}`;
        owned.add(el);
        return el;
      };
      const base = ownElement('style', 'base');
      base.textContent = BASE_CSS;
      let user = ownElement('link', 'user');
      user.setAttribute('rel', 'stylesheet');
      const palette = ownElement('style', 'palette');
      const scale = ownElement('style', 'scale');
      const font = ownElement('style', 'font');
      const align = ownElement('style', 'align');
      const container = () => doc.head || root;

      // MARK: Book styles

      const isBookSheet = (el) => !isOwn(el) && el.namespaceURI !== SVG && (
        el.localName === 'style' ||
        (el.localName === 'link' && /(^|\s)stylesheet(\s|$)/i.test(el.getAttribute('rel') || '')));

      function setSheetEnabled(el, enabled) {
        if (!enabled && !el.hasAttribute(MEDIA_STASH)) {
          el.setAttribute(MEDIA_STASH, el.getAttribute('media') ?? NO_MEDIA);
          el.setAttribute('media', 'not all');
        } else if (enabled && el.hasAttribute(MEDIA_STASH)) {
          const media = el.getAttribute(MEDIA_STASH);
          el.removeAttribute(MEDIA_STASH);
          if (media === NO_MEDIA) el.removeAttribute('media'); else el.setAttribute('media', media);
        }
      }

      function setInlineEnabled(el, enabled) {
        if (!enabled && el.hasAttribute('style')) {
          el.setAttribute(STYLE_STASH, el.getAttribute('style'));
          el.removeAttribute('style');
        } else if (enabled && el.hasAttribute(STYLE_STASH)) {
          el.setAttribute('style', el.getAttribute(STYLE_STASH));
          el.removeAttribute(STYLE_STASH);
        }
        const names = PRESENTATIONAL[el.localName];
        if (!names) return;
        if (!enabled && !el.hasAttribute(ATTR_STASH)) {
          const saved = {};
          for (const name of names) {
            if (el.hasAttribute(name)) { saved[name] = el.getAttribute(name); el.removeAttribute(name); }
          }
          el.setAttribute(ATTR_STASH, JSON.stringify(saved));
        } else if (enabled && el.hasAttribute(ATTR_STASH)) {
          let saved = {};
          try { saved = JSON.parse(el.getAttribute(ATTR_STASH)); } catch (_) { /* unreadable: nothing to put back */ }
          for (const name in saved) el.setAttribute(name, saved[name]);
          el.removeAttribute(ATTR_STASH);
        }
      }

      // An inline `font-family` (even `!important`) beats any rule, layered or not, so the custom
      // font removes it from the element and puts it back when turned off.
      function setInlineFontEnabled(el, enabled) {
        if (!enabled) {
          const value = el.style && el.style.getPropertyValue('font-family');
          if (!value) return;
          const priority = el.style.getPropertyPriority('font-family');
          el.setAttribute(FONT_STASH, priority ? `${value} !${priority}` : value);
          el.style.removeProperty('font-family');
          if (!el.getAttribute('style')) el.removeAttribute('style');
        } else if (el.hasAttribute(FONT_STASH)) {
          const value = el.getAttribute(FONT_STASH);
          el.removeAttribute(FONT_STASH);
          // Under an override the inline style itself is stashed: the family goes back in there.
          if (el.hasAttribute(STYLE_STASH)) {
            el.setAttribute(STYLE_STASH, `${el.getAttribute(STYLE_STASH)}; font-family: ${value}`);
          } else {
            const important = / !important$/.test(value);
            el.style.setProperty('font-family', value.replace(/ !important$/, ''), important ? 'important' : '');
          }
        }
      }

      function applyBookStyles(node) {
        if (!node || node.nodeType !== Node.ELEMENT_NODE) return;
        const enabled = !config.overrideEnabled;
        const fontEnabled = !config.fontFamily;
        const visit = (el) => {
          dropForgedMarks(el);
          if (isBookSheet(el)) { setSheetEnabled(el, enabled); return; }
          if (isOwn(el) || el.namespaceURI === SVG) return;
          if (!KEEP_INLINE.has(el.localName)) setInlineEnabled(el, enabled);
          setInlineFontEnabled(el, fontEnabled);
        };
        visit(node);
        const walker = doc.createTreeWalker(node, NodeFilter.SHOW_ELEMENT);
        while (walker.nextNode()) visit(walker.currentNode);
      }

      // While the parser runs, new nodes are handled before the first style recalculation.
      const observer = new MutationObserver((records) => {
        for (const record of records) for (const node of record.addedNodes) applyBookStyles(node);
      });

      // WebKit runs document-start scripts once the root element exists; other engines may run
      // them earlier, so mounting waits for it if needed.
      function mount() {
        if (mounted) return true;
        root = doc.documentElement;
        if (!root) return false;
        root.insertBefore(base, root.firstChild);
        root.appendChild(palette);
        root.appendChild(scale);
        root.appendChild(font);
        root.appendChild(align);
        if (parsing) observer.observe(root, { childList: true, subtree: true });
        mounted = true;
        return true;
      }

      // MARK: User style

      let pendingUser = null;

      function applyUserStyle() {
        const href = config.overrideEnabled ? config.styleHref : null;
        if (pendingUser) {
          if (pendingUser.getAttribute('href') === href) return;
          pendingUser.remove();
          pendingUser = null;
        }
        if (!href) {
          user.remove();
          user.removeAttribute('href');
          return;
        }
        if (user.isConnected && user.getAttribute('href') === href) return;
        if (user.isConnected && user.sheet) {
          // Load the new sheet (another style, or the same file edited) next to the old one and
          // drop the old one once it has loaded: no unstyled flash. The line being read is noted
          // now and restored in the load handler, which runs before the new layout is painted.
          const next = user.cloneNode(false);
          owned.add(next);
          next.setAttribute('href', href);
          const anchor = captureAnchor();
          const swap = () => {
            if (pendingUser !== next) return;
            pendingUser = null;
            user.remove();
            user = next;
            refreshPalette();
            refreshFont();
            refreshAlign();
            restoreAnchor(anchor);
          };
          next.addEventListener('load', swap, { once: true });
          next.addEventListener('error', swap, { once: true });
          pendingUser = next;
          user.after(next);
        } else {
          user.setAttribute('href', href);
          user.addEventListener('load', () => { refreshFont(); refreshAlign(); }, { once: true });
          if (!user.isConnected) container().insertBefore(user, palette.parentNode === container() ? palette : null);
        }
      }

      // MARK: Night palette

      function sheetHandlesColorScheme(sheet, seen) {
        if (!sheet || seen.has(sheet)) return false;
        seen.add(sheet);
        if (sheet.media && /prefers-color-scheme/i.test(sheet.media.mediaText)) return true;
        let rules;
        try { rules = sheet.cssRules; } catch (_) { return false; }
        return rulesHandleColorScheme(rules, seen);
      }

      function rulesHandleColorScheme(rules, seen) {
        for (const rule of rules) {
          if (rule.styleSheet && sheetHandlesColorScheme(rule.styleSheet, seen)) return true;
          const condition = rule.conditionText ?? (rule.media && rule.media.mediaText) ?? '';
          if (/prefers-color-scheme/i.test(condition)) return true;
          if (rule.cssRules && rulesHandleColorScheme(rule.cssRules, seen)) return true;
        }
        return false;
      }

      function bookHandlesColorScheme() {
        const seen = new Set();
        for (const sheet of doc.styleSheets) {
          const owner = sheet.ownerNode;
          if (owner && isOwn(owner)) continue;
          if (sheetHandlesColorScheme(sheet, seen)) return true;
        }
        return false;
      }

      function refreshPalette() {
        // Until the book's sheets have loaded, Night assumes they have no dark rules.
        const handled = config.overrideEnabled ? config.styleHandlesColorScheme : bookHandlesColorScheme();
        const css = config.night && !handled ? config.nightPaletteCSS : '';
        if (palette.textContent !== css) palette.textContent = css;
      }

      // MARK: Text size

      // The text size must win over whatever the CSS says: px sizes, `min()`/`clamp()` caps,
      // `!important`. Resizing fonts cannot guarantee that (caps are re-applied to any root size),
      // so the body is zoomed: every length inside it, text, line spacing, margins, line length
      // in em, grows by the same factor, while the text still wraps to the window. Pictures are
      // zoomed back by the inverse factor and keep their size. This is CSS `zoom` in the page, not
      // the web view's page zoom or magnification. The rules sit in the `aomidori` layer, so no
      // book or user rule can undo them.
      function refreshScale() {
        const factor = Number(config.scale) || 1;
        let css = `:root { --aomidori-scale: ${factor}; }`;
        if (factor !== 1) {
          css += `\n@layer aomidori {\n  body { zoom: ${factor} !important; }\n` +
            `  body ${MEDIA} { zoom: ${1 / factor} !important; }\n}`;
        }
        if (scale.textContent !== css) scale.textContent = css;
      }

      // MARK: Custom font

      // The chosen face's weight and width go on all text; text the CSS makes bold (600 or
      // more) gets the bold weight instead, so bold keeps its contrast with any chosen weight.
      // Which text is bold (or italic, for an italic choice) is read from the cascade without
      // these rules, and marked on the elements; re-read whenever styles may have changed.
      const BOLD_MARK = 'data-aomidori-bold';
      const ITALIC_MARK = 'data-aomidori-italic';
      const numberOrNull = (value) =>
        value === null || value === undefined || value === '' || !Number.isFinite(Number(value)) ? null : Number(value);

      function clearEmphasisMarks() {
        for (const el of doc.querySelectorAll(`[${BOLD_MARK}], [${ITALIC_MARK}]`)) {
          el.removeAttribute(BOLD_MARK);
          el.removeAttribute(ITALIC_MARK);
        }
      }

      function markEmphasis() {
        clearEmphasisMarks();
        if (!doc.body) return;
        const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_ELEMENT);
        for (let el = doc.body; el; el = walker.nextNode()) {
          if (el.namespaceURI === SVG) continue;
          const style = getComputedStyle(el);
          if (parseFloat(style.fontWeight) >= 600) el.setAttribute(BOLD_MARK, '');
          if (style.fontStyle !== 'normal') el.setAttribute(ITALIC_MARK, '');
        }
      }

      function refreshFont() {
        if (!config.fontFamily) {
          if (font.textContent !== '') font.textContent = '';
          clearEmphasisMarks();
          return;
        }
        const text = `:where(body, body *:not(${FONT_EXEMPT}))`;
        const all = (selector) => `${selector}, ${selector}::before, ${selector}::after`;
        const declarations = [`font-family: ${config.fontFamily} !important;`];
        const stretch = numberOrNull(config.fontStretch);
        if (stretch !== null) declarations.push(`font-stretch: ${stretch}% !important;`);
        if (config.fontFeatureSettings) declarations.push(`font-feature-settings: ${config.fontFeatureSettings} !important;`);
        if (config.fontVariationSettings) declarations.push(`font-variation-settings: ${config.fontVariationSettings} !important;`);
        // Code and formulas keep their own family; the custom font's width, features and axes
        // would only be inherited by them, so they are reset (weight and style still follow
        // the text around them, as CSS has it).
        const exempt = declarations.length > 1
          ? `\n  :where(body) :is(${FONT_EXEMPT}) { font-stretch: normal; font-feature-settings: normal; font-variation-settings: normal; }`
          : '';
        const familyRule = `  ${all(text)} { ${declarations.join(' ')} }${exempt}`;
        const emphasisRules = [];
        const weight = numberOrNull(config.fontWeight);
        if (weight !== null) {
          const bold = numberOrNull(config.fontBoldWeight) ?? Math.max(weight, Math.min(weight + 300, 900));
          emphasisRules.push(`  ${all(text)} { font-weight: ${weight} !important; }`,
            `  ${all(`${text}[${BOLD_MARK}]`)} { font-weight: ${bold} !important; }`);
        }
        if (config.fontItalic) {
          emphasisRules.push(`  ${all(text)} { font-style: italic !important; }`,
            `  ${all(`${text}[${ITALIC_MARK}]`)} { font-style: normal !important; }`);
        }
        const sheet = (rules) => `${config.fontFaceCSS || ''}\n@layer aomidori {\n${rules.join('\n')}\n}`;
        if (emphasisRules.length && doc.body) {
          font.textContent = sheet([familyRule]);
          markEmphasis();
        } else {
          clearEmphasisMarks();
        }
        const css = sheet([familyRule, ...emphasisRules]);
        if (font.textContent !== css) font.textContent = css;
      }

      // MARK: Alignment

      // Running text is flush left, whatever the book or the user style says, or justified when
      // the reader asks for it (⌘J). Which text runs is read from the cascade without this rule:
      // text aligned to the left, to the start or justified; centred and right-aligned text keeps
      // its alignment. Marked on the elements, re-read whenever styles may have changed.
      const ALIGN_MARK = 'data-aomidori-align';
      const RUNNING = new Set(['left', 'start', 'justify', '-webkit-left', '-webkit-auto']);

      function refreshAlign() {
        if (!doc.body) return;
        if (align.textContent !== '') align.textContent = '';
        for (const el of doc.querySelectorAll(`[${ALIGN_MARK}]`)) el.removeAttribute(ALIGN_MARK);
        const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_ELEMENT);
        for (let el = doc.body; el; el = walker.nextNode()) {
          if (el.namespaceURI === SVG || isOwn(el)) continue;
          if (RUNNING.has(getComputedStyle(el).textAlign)) el.setAttribute(ALIGN_MARK, '');
        }
        const value = config.justified ? 'justify' : 'left';
        align.textContent = `@layer aomidori {\n  [${ALIGN_MARK}] { text-align: ${value} !important; }\n}`;
      }

      // MARK: Image pages

      const hasCoverMarker = (el) => !!el && (
        /(^|\s)cover(\s|$)/.test(el.getAttributeNS(OPS, 'type') || el.getAttribute('epub:type') || '') ||
        /(^|\s)cover(-page|-image)?(\s|$)/i.test(el.getAttribute('class') || ''));

      // Text outside SVG pictures (an SVG cover may carry its title as SVG text).
      function visibleText(node) {
        let text = '';
        const walker = doc.createTreeWalker(node, NodeFilter.SHOW_TEXT, {
          acceptNode: (n) => n.parentElement && n.parentElement.closest('svg, script, style, title')
            ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT,
        });
        while (walker.nextNode()) text += walker.currentNode.nodeValue;
        return text.trim();
      }

      // A spine item that shows a single picture: no text besides it, or an explicit cover
      // marker (`epub:type="cover"` on the page or a section, `html.cover-page`).
      function findImagePagePicture() {
        const body = doc.body;
        if (!body) return null;
        const pictures = [...body.querySelectorAll('img, svg')].filter((el) => !el.parentElement.closest('svg'));
        if (pictures.length !== 1) return null;
        const picture = pictures[0];
        if (visibleText(body) === '') return picture;
        for (let el = picture; el; el = el.parentElement) if (hasCoverMarker(el)) return picture;
        return null;
      }

      function markImagePage() {
        for (const el of doc.querySelectorAll(`[${COVER}], [${COVER_WRAP}]`)) {
          el.removeAttribute(COVER);
          el.removeAttribute(COVER_WRAP);
        }
        const picture = findImagePagePicture();
        root.classList.toggle(IMAGE_PAGE, !!picture);
        if (!picture) return;
        const fits = picture.localName === 'svg' && picture.hasAttribute('viewBox');
        picture.setAttribute(COVER, fits ? 'fit' : 'intrinsic');
        for (let el = picture.parentElement; el && el !== doc.body; el = el.parentElement) el.setAttribute(COVER_WRAP, '');
      }

      // MARK: Position

      function fraction() {
        const scroller = doc.scrollingElement || root;
        const max = scroller.scrollHeight - innerHeight;
        return max > 0 ? Math.min(1, Math.max(0, scrollY / max)) : 0;
      }

      function scrollToFraction(value) {
        const scroller = doc.scrollingElement || root;
        const max = scroller.scrollHeight - innerHeight;
        scrollTo(0, max > 0 ? Math.round(max * Math.min(1, Math.max(0, value))) : 0);
      }

      // WebKit has long reported client rects inside a `zoom`ed element in that element's own,
      // unzoomed page coordinates (minus the unzoomed scroll offset); standard CSS zoom reports
      // what is on screen. Measured once, so anchoring works with either.
      let rectsAreVisual = null;
      function zoomFactor(el) {
        if (rectsAreVisual === null) {
          const probe = ownElement('div', 'probe');
          probe.style.cssText = 'position:absolute;visibility:hidden;zoom:2;height:10px;width:10px';
          root.appendChild(probe);
          rectsAreVisual = probe.getBoundingClientRect().height > 15;
          probe.remove();
        }
        if (rectsAreVisual) return 1;
        let factor = 1;
        for (let node = el; node && node.nodeType === Node.ELEMENT_NODE; node = node.parentElement) {
          factor *= parseFloat(getComputedStyle(node).zoom) || 1;
        }
        return factor;
      }
      const visualRect = (el) => {
        const factor = zoomFactor(el);
        const rect = el.getBoundingClientRect();
        const top = factor === 1 ? rect.top : (rect.top + scrollY) * factor - scrollY;
        return { top, height: rect.height * factor };
      };
      const visualTop = (el) => visualRect(el).top;
      // The line the reader is looking at, as a distance from the top of the window.
      const readingLine = () => Math.round(innerHeight * 0.3);

      // Keeps the line the reader is looking at in place while styles or size change.
      function captureAnchor() {
        const el = doc.elementFromPoint(innerWidth / 2, readingLine());
        if (!el || el === root || el === doc.body) return { fraction: fraction() };
        return { el, top: visualTop(el), fraction: fraction() };
      }

      function restoreAnchor(anchor) {
        if (anchor.el && anchor.el.isConnected) scrollBy(0, visualTop(anchor.el) - anchor.top);
        else scrollToFraction(anchor.fraction);
      }

      // MARK: Saved positions

      // Child indices from the body down to `el`: stable across styles, text sizes and sessions.
      function elementPath(el) {
        const parts = [];
        let node = el;
        for (; node && node !== doc.body; node = node.parentElement) {
          const parent = node.parentElement;
          if (!parent) return null;
          parts.unshift(Array.prototype.indexOf.call(parent.children, node));
        }
        return node === doc.body && parts.length ? parts.join('.') : null;
      }

      function elementAt(path) {
        let node = doc.body;
        for (const part of path.split('.')) {
          node = node && node.children[Number(part)];
        }
        return node || null;
      }

      // `{ fraction, anchor }`, anchor being `"<element path>@<how far down it the reading line is>"`.
      function position() {
        const value = fraction();
        if (value <= 0 || value >= 1 || root.classList.contains(IMAGE_PAGE)) return { fraction: value, anchor: null };
        const line = readingLine();
        for (const y of [line, line + 16, line - 16, line + 40]) {
          let el = doc.elementFromPoint(innerWidth / 2, y);
          if (el && el.closest) el = el.closest('svg') ? el.closest('svg') : el;
          if (!el || el === root || el === doc.body || isOwn(el)) continue;
          const path = elementPath(el);
          if (!path) continue;
          const rect = visualRect(el);
          const offset = rect.height > 0 ? (line - rect.top) / rect.height : 0;
          return { fraction: value, anchor: `${path}@${Math.round(offset * 10000) / 10000}` };
        }
        return { fraction: value, anchor: null };
      }

      function scrollToPosition(saved) {
        const value = Number(saved && saved.fraction) || 0;
        const match = saved && typeof saved.anchor === 'string' && /^([\d.]+)@(-?[\d.]+)$/.exec(saved.anchor);
        const el = match && value > 0 && value < 1 ? elementAt(match[1]) : null;
        if (el) {
          const rect = visualRect(el);
          scrollBy(0, rect.top + Number(match[2]) * rect.height - readingLine());
        } else {
          scrollToFraction(value);
        }
      }

      // Goes back to a saved position, and again once web fonts have loaded and changed the
      // layout, unless the reader has scrolled in the meantime.
      function restorePosition(saved) {
        scrollToPosition(saved);
        const landed = scrollY;
        if (doc.fonts && doc.fonts.status !== 'loaded') {
          doc.fonts.ready.then(() => { if (scrollY === landed) scrollToPosition(saved); });
        }
      }

      // MARK: Links

      // Where a link was clicked, read before the click's navigation: an anchor in the same
      // document scrolls before the native side can ask the page where it was.
      let linkDeparture = null;
      addEventListener('click', (event) => {
        const link = event.target && event.target.closest ? event.target.closest('a[href]') : null;
        if (link) linkDeparture = position();
      }, true);
      function takeLinkDeparture() {
        const value = linkDeparture;
        linkDeparture = null;
        return value;
      }

      let reportTimer = 0;
      const post = (message) => {
        try { webkit.messageHandlers['\#(messageHandlerName)'].postMessage(message); } catch (_) { /* not attached */ }
      };
      const reportPosition = () => post(Object.assign({ type: 'position', href: location.href }, position()));
      addEventListener('scroll', () => {
        reportEdges();
        clearTimeout(reportTimer);
        reportTimer = setTimeout(reportPosition, 250);
      }, { passive: true });

      // MARK: Edges

      // Whether the page can scroll further, reported when it changes, so native code knows
      // when Space or a swipe pushes past the end of the chapter. Image pages never scroll.
      let lastEdges = '';
      function reportEdges() {
        const scroller = doc.scrollingElement || root;
        const max = scroller.scrollHeight - innerHeight;
        const still = max <= 1 || root.classList.contains(IMAGE_PAGE);
        const atTop = still || scrollY <= 1;
        const atBottom = still || scrollY >= max - 1;
        const key = `${atTop} ${atBottom}`;
        if (key === lastEdges) return;
        lastEdges = key;
        post({ type: 'edges', href: location.href, atTop, atBottom });
      }
      addEventListener('resize', reportEdges, { passive: true });
      const sizeObserver = new ResizeObserver(() => reportEdges());

      // MARK: Lifecycle

      doc.addEventListener('DOMContentLoaded', () => {
        parsing = false;
        observer.disconnect();
        applyBookStyles(root);
        markImagePage();
        // Late layers follow the book's sheets in document order, so cascade ties go to them.
        // The user <link> is not moved: re-inserting it would fetch the sheet again.
        const parent = container();
        parent.appendChild(palette);
        parent.appendChild(scale);
        parent.appendChild(font);
        parent.appendChild(align);
        refreshPalette();
        refreshScale();
        refreshFont();
        refreshAlign();
        sizeObserver.observe(root);
        if (doc.body) sizeObserver.observe(doc.body);
        reportEdges();
      }, { once: true });

      addEventListener('load', () => { refreshPalette(); refreshFont(); refreshAlign(); reportEdges(); }, { once: true });

      window.Aomidori = Object.freeze({
        apply(next) {
          config = Object.assign({}, config, next);
          if (!mounted) return;
          const anchor = parsing ? null : captureAnchor();
          applyBookStyles(root);
          applyUserStyle();
          refreshPalette();
          refreshScale();
          refreshFont();
          refreshAlign();
          if (anchor) restoreAnchor(anchor);
        },
        fraction,
        scrollToFraction,
        position,
        restorePosition,
        takeLinkDeparture,
      });

      if (!mount()) {
        const waiter = new MutationObserver(() => {
          if (!mount()) return;
          waiter.disconnect();
          window.Aomidori.apply({});
        });
        waiter.observe(doc, { childList: true });
      }
    })();
    """#
}
