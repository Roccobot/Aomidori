import Foundation
import AomidoriCore

/// The page-side half of the rendering layer. It runs in an isolated content world
/// (`WKContentWorld.defaultClient`) at document start, before the book's markup is parsed,
/// so book scripts (disabled anyway) can never see or alter it.
///
/// Layers, in cascade order:
/// 1. `base`: no horizontal scrolling, media never wider than the window, single-picture pages
///    (covers) fit the window. Inserted first, so any book or user rule wins over it. It also
///    declares the `aomidori` cascade layer first, which makes the `!important` rules placed in
///    it beat every other author rule, whatever its specificity or position (CSS Cascade 5).
/// 2. the book's own `<link>`/`<style>` sheets and inline styles, disabled when overriding;
/// 3. `user`: the selected user style (`<link>`, so its relative URLs resolve in the styles folder);
/// 4. `palette`: Night colors, only when the active CSS has no `prefers-color-scheme` rules;
/// 5. `scale` (layer `aomidori`): the text size, as CSS `zoom` on the body with images
///    counter-zoomed; see `refreshScale`.
/// 6. `font` (layer `aomidori`): the app's custom font, when on, for all text.
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
      // Text that keeps its own family under the custom font: code and formulas.
      const FONT_EXEMPT = 'code, pre, kbd, samp, tt, var, math, math *';
      // Replaced content that keeps its size when the text is scaled.
      const MEDIA = ':is(img, svg, video, canvas, iframe, object, embed):not(svg *)';
      const BASE_CSS = [
        '@layer aomidori;',
        'html { overflow-x: hidden !important; }',
        'img, video, svg { max-width: 100% !important; }',
        'img, video { object-fit: contain; }',
        // A page that is just one picture (a cover, a plate) fits the window, whole.
        `html.${IMAGE_PAGE} img, html.${IMAGE_PAGE} svg { max-height: 100vh !important; object-fit: contain; }`,
        // Centred on its own, since an override style may drop the book's centring rules.
        `html.${IMAGE_PAGE} img, html.${IMAGE_PAGE} svg { display: block; margin-inline: auto; }`,
      ].join('\n');

      const doc = document;
      let root = doc.documentElement;
      let mounted = false;
      let config = {
        overrideEnabled: false, styleHref: null, styleHandlesColorScheme: false, night: false,
        nightPaletteCSS: '', scale: 1, fontFamily: null, fontFaceCSS: '',
      };
      let parsing = doc.readyState === 'loading';

      const ownElement = (name, role) => {
        const el = doc.createElementNS(XHTML, name);
        el.setAttribute(OWN, role);
        el.id = `aomidori-${role}`;
        return el;
      };
      const base = ownElement('style', 'base');
      base.textContent = BASE_CSS;
      let user = ownElement('link', 'user');
      user.setAttribute('rel', 'stylesheet');
      const palette = ownElement('style', 'palette');
      const scale = ownElement('style', 'scale');
      const font = ownElement('style', 'font');
      const container = () => doc.head || root;

      // MARK: Book styles

      const isBookSheet = (el) => !el.hasAttribute(OWN) && el.namespaceURI !== SVG && (
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
          const saved = JSON.parse(el.getAttribute(ATTR_STASH));
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
          if (isBookSheet(el)) { setSheetEnabled(el, enabled); return; }
          if (el.hasAttribute(OWN) || el.namespaceURI === SVG) return;
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
          next.setAttribute('href', href);
          const anchor = captureAnchor();
          const swap = () => {
            if (pendingUser !== next) return;
            pendingUser = null;
            user.remove();
            user = next;
            refreshPalette();
            restoreAnchor(anchor);
          };
          next.addEventListener('load', swap, { once: true });
          next.addEventListener('error', swap, { once: true });
          pendingUser = next;
          user.after(next);
        } else {
          user.setAttribute('href', href);
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
          if (owner && owner.hasAttribute && owner.hasAttribute(OWN)) continue;
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

      function refreshFont() {
        let css = '';
        if (config.fontFamily) {
          const text = `:where(body, body *:not(${FONT_EXEMPT}))`;
          css = `${config.fontFaceCSS || ''}\n@layer aomidori {\n` +
            `  ${text}, ${text}::before, ${text}::after { font-family: ${config.fontFamily} !important; }\n}`;
        }
        if (font.textContent !== css) font.textContent = css;
      }

      function markImagePage() {
        const body = doc.body;
        const imageOnly = !!body && (body.textContent || '').trim() === '' &&
          body.querySelectorAll('img, svg').length === 1;
        root.classList.toggle(IMAGE_PAGE, imageOnly);
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
      const visualTop = (el) => {
        const factor = zoomFactor(el);
        const top = el.getBoundingClientRect().top;
        return factor === 1 ? top : (top + scrollY) * factor - scrollY;
      };

      // Keeps the line the reader is looking at in place while styles or size change.
      function captureAnchor() {
        const el = doc.elementFromPoint(innerWidth / 2, Math.round(innerHeight * 0.3));
        if (!el || el === root || el === doc.body) return { fraction: fraction() };
        return { el, top: visualTop(el), fraction: fraction() };
      }

      function restoreAnchor(anchor) {
        if (anchor.el && anchor.el.isConnected) scrollBy(0, visualTop(anchor.el) - anchor.top);
        else scrollToFraction(anchor.fraction);
      }

      let reportTimer = 0;
      const post = (message) => {
        try { webkit.messageHandlers.aomidori.postMessage(message); } catch (_) { /* not attached */ }
      };
      addEventListener('scroll', () => {
        clearTimeout(reportTimer);
        reportTimer = setTimeout(() => post({ type: 'position', fraction: fraction() }), 250);
      }, { passive: true });

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
        refreshPalette();
        refreshScale();
        refreshFont();
      }, { once: true });

      addEventListener('load', refreshPalette, { once: true });

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
          if (anchor) restoreAnchor(anchor);
        },
        fraction,
        scrollToFraction,
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
