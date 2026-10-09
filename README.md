# Aomidori

A minimal, fast EPUB reader for macOS (Apple Silicon, macOS 27 Golden Gate and later),
in the spirit of Murasaki: each chapter is one web page that scrolls vertically, `←`/`→`
move between chapters, and the reader's own CSS can replace the book's at any moment.

## Features (v0.1.0)

- One window per book (`NSDocument`); macOS window tabs work out of the box.
- Web-style reading: a chapter scrolls vertically as a single entity. No pages, no
  horizontal scrolling, a single view mode.
- Internal links between chapters, table of contents in a sidebar, history (`⌘[` / `⌘]`).
- Reading position remembered per book.
- Text size with `+` `-` `0` (or `⌘+` `⌘-` `⌘0`); pinch-to-zoom never scales the page.
- User styles: every `.css` in `~/Library/Application Support/Aomidori/Styles/`, edited live
  with any external editor. The book's CSS is used by default; *Sovrascrivi stile* (`⌘.`)
  replaces it with the selected user style.
- Day/Night with one click. Styles with `prefers-color-scheme` rules follow it natively; for CSS
  without them, Night applies only the colors of the default style's dark rules.
- Minimal mode: no toolbar, title or window buttons, only text.
- Book info window (`⌘I`): metadata and cover image.
- English and Italian interface, following the system language.

## Architecture

```
Sources/
  EPUBKit/        EPUB parsing, no UI. ZIP read lazily (ZIPFoundation), container.xml,
                  OPF (manifest, spine, linear="no"), EPUB 3 nav or NCX TOC, font
                  de-obfuscation (IDPF and Adobe), MIME types.
  AomidoriCore/   Reader logic without AppKit: style library, CSS analysis (color-scheme
                  detection, Night palette extraction), text scale, reading positions,
                  the configuration sent to the page.
  Aomidori/       The AppKit/WebKit app.
    App/          entry point, app delegate, menu bar, paths, localization helper.
    Document/     BookDocument (NSDocument, read-only).
    Reader/       window controller, TOC sidebar, book info window, reader view, and the rendering layer:
                  PageRenderer (one WKWebView), PageSchemeHandler, ReaderScript.
    Styles/       ReaderEnvironment (settings + styles folder), FSEvents watcher,
                  style menu, style picker HUD.
```

**Rendering.** Each window owns one `WKWebView`, reused for every chapter. Book resources
are served by a `WKURLSchemeHandler` at `aomidori://<random-host>/<path-in-zip>` with the
manifest's MIME type, read off the main thread straight from the archive (nothing is
extracted). Each spine item is loaded as a real document: no iframe, no blob. Book
JavaScript is disabled.

**Style layers.** `ReaderScript` runs at document start in an isolated content world
(`WKContentWorld.defaultClient`) and manages, in cascade order:

1. `#aomidori-base`: no horizontal overflow, media never wider than the window, single-image
   pages (covers) fit the window;
2. the book's `<link rel=stylesheet>` / `<style>` sheets and inline `style` attributes;
3. `#aomidori-user`: a `<link>` to the selected user style, served from
   `/.aomidori/Styles/<file>` so relative URLs inside it resolve next to it
   (`url("../Fonts/X.otf")` finds `~/Library/Application Support/Aomidori/Fonts/X.otf`);
4. `#aomidori-palette`: Night colors, only when the active CSS has no `prefers-color-scheme`;
5. `#aomidori-scale`: the text size multiplier.

With the override on, book sheets get `media="not all"` (original value kept in
`data-aomidori-media`) and inline `style` attributes move to `data-aomidori-style`, except on
`img`, `svg`, `video`, `canvas`, `object`, `embed`, `iframe`, `math` and inside SVG, where they
usually carry intrinsic sizing. Everything is reversible without reloading. Native code
updates the page with `Aomidori.apply(configuration)`; switching style swaps the `<link>` only
after the new sheet has loaded, so there is no unstyled flash.

**Text size** multiplies the root font size the active CSS sets (so rem-based designs keep
working) and exposes it as `--aomidori-scale` on `:root`. `0` removes the rule: 100% of the
style. It is never page zoom.

**Night.** The toolbar button sets the window appearance (`aqua`/`darkAqua`), so
`prefers-color-scheme` resolves in the page as in Safari. If the active CSS (the book's
sheets when the override is off, including `@import`s; the user style when it is on) has no
`prefers-color-scheme` rule, the page receives only the color declarations (`color`,
`*-color`, `fill`, `stroke`) of the default style's `@media (prefers-color-scheme: dark)` blocks,
with `!important`, plus `color-scheme: dark`. Day injects nothing.

**Styles folder.** Created on first launch with `ReadingRoccobot.css` (bundled, never
overwritten afterwards). The default style is the file named by the `AomidoriDefaultStyle`
setting (`defaults write com.roccobot.aomidori AomidoriDefaultStyle Other.css`). FSEvents
reload styles live when any app saves a file there.

**Localization.** Exactly two languages: English (development language, `en.lproj`) and
Italian (`it.lproj`), as `Localizable.strings` with semantic keys (`menu.style.next`). Every UI
string goes through `L10n`; `scripts/bundle.sh` refuses to build if the two files' keys differ.
(`.strings` rather than a String Catalog: catalogs need Xcode's compiler, the project builds
with the Command Line Tools only.)

## Build

Requirements: Apple Silicon, macOS 27, Swift 6.4 Command Line Tools (Xcode not needed).

```sh
swift build -c release        # build
swift test                    # unit tests (Swift Testing)
scripts/bundle.sh             # build/Aomidori.app, ad-hoc signed, arm64 only
scripts/smoke.sh book.epub    # open a book and save a snapshot of the page to build/smoke.png
ditto -c -k --keepParent build/Aomidori.app Aomidori-0.1.0.zip   # release archive
```

`EPUBKit` and `AomidoriCore` also build and test on Linux (the app target is macOS-only);
IDPF font de-obfuscation needs CryptoKit and its test is skipped there.

The app is ad-hoc signed, not notarized: on another Mac, the first launch needs right-click
› Open (or removing the quarantine attribute).

**Continuous integration (not set up yet).** A GitHub Actions workflow on a `macos` runner
could run `swift test` and `scripts/bundle.sh` on each push and attach the zip to tagged
releases, once hosted runners offer macOS 27 and Swift 6.4.

## Keyboard shortcuts

Shortcuts are designed for the Italian keyboard layout (AppKit's automatic remapping is off).
Menu names are given in English; in Italian they are Archivio, Vista, Vai, Stile.

| Action | Shortcut | Menu |
| --- | --- | --- |
| Previous / next chapter | `←` / `→` | Go |
| Back / forward (history of jumps) | `⌘[` / `⌘]` | Go |
| Larger / smaller text | `+` / `-`, `⌘+` / `⌘-` | View |
| Text at 100% of the style | `0`, `⌘0` | View |
| Day ↔ Night | `⇧⌘N` (and toolbar) | View |
| Table of contents | `⌃⌘S` | View |
| Minimal mode | `⌃⌘M` | View |
| Full screen | `⌃⌘F` | View |
| Override book style on/off | `⌘.` (and toolbar) | Style |
| Previous / next style | `⌘'` / `⌘ì` | Style |
| Style list | `⌘1` or `⌃⇥` | Style |
| Book info (metadata, cover) | `⌘I` (and toolbar) | File |
| Open, close | `⌘O`, `⌘W` | File |

Style list: a quick press opens a list that closes when you pick a style (click, or `↑` `↓`
and `↩`; `esc` cancels). Holding `⌘` (or `⌃`) and pressing `1` (or `⇥`) again moves to the
next style with a live preview (`⇧` goes back); releasing the modifier keeps it, like `⌘⇥`.
Choosing a style turns the override on.

## Known limits

- `←` always lands at the top of the previous chapter.
- The position is a scroll fraction of the chapter; after the chapter's layout changes a lot
  (another style, another width) it is approximate. Style and size changes keep the visible
  line in place.
- `+` cannot go past a cap written in px in the active style: `ReadingRoccobot.css` sets
  `font-size: min(1.6em, 26px)`, so above about 102% its body text stops at 26px. A style can
  opt in to the reader's scale with `min(1.6em, calc(26px * var(--aomidori-scale, 1)))`.
- With the override off, the book's CSS is used as is: a book without margins touches the
  window edges.
- `⌃⇥` is also the system shortcut for the next window tab; Aomidori takes it for the style list.
- `←` / `→` are menu shortcuts too, so they change chapter even while the sidebar has focus.
- Not supported yet: fixed-layout EPUBs, vertical writing (it would scroll sideways),
  unpacked (folder) EPUBs, `xml-stylesheet` instructions, DRM-protected books (reported).
- Fonts installed in the system may or may not be visible to web content; the `Fonts`
  folder next to `Styles` is the reliable way for user styles.

## Next phases

1. **CSS Playground**: a window with a live preview (sample text or a real EPUB, left) and a
   minimal HTML/CSS editor with syntax highlighting (right), plus a style selector. Ready in
   the code: the preview is a `PageRenderer` driven by `ReaderConfiguration` with a different
   `PageResourceProvider`; *Save to Styles* uses `StyleLibrary.save(css:named:)` (UTF-8 without
   BOM, LF), so the style appears at once in the reader's style list through the folder watcher
   and can be tried live in any reader window; *Save As…* writes a `.css` anywhere with the same
   normalisation.
2. **Windows vs tabs**: test both and pick one.
3. **Bookmarks** (Murasaki-like): `⌘D` with a title sheet, a Bookmarks pane next to the TOC in
   the sidebar, stored per book next to the reading positions.
4. Search, per-book style memory, precise positions (element anchors), landing at the end of
   the previous chapter, trackpad swipe between chapters.

Murasaki (closed source) is a reference for the toolbar, sidebar panes and Inspector; no assets
or code are taken from it.

## Licenses

See [THIRD_PARTY.md](THIRD_PARTY.md) (foliate-js font de-obfuscation, ZIPFoundation).
