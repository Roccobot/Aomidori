import Foundation
import AomidoriCore

/// The page-side half of the rendering layer. It runs in an isolated content world
/// (`WKContentWorld.defaultClient`) at document start, before the book's markup is parsed,
/// so book scripts (disabled anyway) can never see or alter it.
///
/// Layers, in cascade order:
/// 1. `base`: no horizontal scrolling, media never wider than the window, single-picture pages
///    (covers) fit the window. Inserted first, so any book or user rule wins over it.
/// 2. the book's own `<link>`/`<style>` sheets and inline styles, disabled when overriding;
/// 3. `user`: the selected user style (`<link>`, so its relative URLs resolve in the styles folder);
/// 4. `palette`: Night colors, only when the active CSS has no `prefers-color-scheme` rules;
/// 5. `scale`: the text size multiplier on the root font size.
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
      const NO_MEDIA = '-';
      // Inline styles on these elements usually carry intrinsic sizing: kept when overriding.
      const KEEP_INLINE = new Set(['img', 'svg', 'image', 'video', 'audio', 'canvas', 'picture', 'object', 'embed', 'iframe', 'math']);
      const IMAGE_PAGE = 'aomidori-image-page';
      const BASE_CSS = [
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
      let config = { overrideEnabled: false, styleHref: null, styleHandlesColorScheme: false, night: false, nightPaletteCSS: '', scale: 1 };
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
      }

      function applyBookStyles(node) {
        if (!node || node.nodeType !== Node.ELEMENT_NODE) return;
        const enabled = !config.overrideEnabled;
        const visit = (el) => {
          if (isBookSheet(el)) setSheetEnabled(el, enabled);
          else if (!el.hasAttribute(OWN) && el.namespaceURI !== SVG && !KEEP_INLINE.has(el.localName)) setInlineEnabled(el, enabled);
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
        if (parsing) observer.observe(root, { childList: true, subtree: true });
        mounted = true;
        return true;
      }

      // MARK: User style

      function applyUserStyle() {
        const href = config.overrideEnabled ? config.styleHref : null;
        if (!href) {
          user.remove();
          user.removeAttribute('href');
          return;
        }
        if (user.isConnected && user.getAttribute('href') === href) return;
        if (user.isConnected && user.sheet) {
          // Load the new sheet next to the old one and swap when ready: no unstyled flash.
          const next = user.cloneNode(false);
          next.setAttribute('href', href);
          const swap = () => {
            if (user !== next) { user.remove(); user = next; }
            refreshPalette();
            refreshScale();
          };
          next.addEventListener('load', swap, { once: true });
          next.addEventListener('error', swap, { once: true });
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

      function refreshScale() {
        const factor = Number(config.scale) || 1;
        const neutral = ':root { --aomidori-scale: 1; }';
        if (scale.textContent !== neutral) scale.textContent = neutral;
        if (factor === 1) return;
        // Multiply the root size the active CSS sets (16px by default), so rem-based designs keep working.
        const rootSize = parseFloat(getComputedStyle(root).fontSize) || 16;
        scale.textContent = `:root { --aomidori-scale: ${factor}; font-size: ${rootSize * factor}px !important; }`;
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

      // Keeps the line the reader is looking at in place while styles or size change.
      function captureAnchor() {
        const el = doc.elementFromPoint(innerWidth / 2, Math.round(innerHeight * 0.3));
        if (!el || el === root || el === doc.body) return { fraction: fraction() };
        return { el, top: el.getBoundingClientRect().top, fraction: fraction() };
      }

      function restoreAnchor(anchor) {
        if (anchor.el && anchor.el.isConnected) scrollBy(0, anchor.el.getBoundingClientRect().top - anchor.top);
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
        refreshPalette();
        refreshScale();
      }, { once: true });

      addEventListener('load', () => {
        refreshPalette();
        refreshScale();
      }, { once: true });

      window.Aomidori = Object.freeze({
        apply(next) {
          config = Object.assign({}, config, next);
          if (!mounted) return;
          const anchor = parsing ? null : captureAnchor();
          applyBookStyles(root);
          applyUserStyle();
          refreshPalette();
          refreshScale();
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
