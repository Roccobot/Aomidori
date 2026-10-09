# Aomidori

A minimal, fast EPUB reader for macOS (Apple Silicon, macOS 27 Golden Gate and later),
in the spirit of Murasaki: each chapter is one web page that scrolls vertically, `←`/`→`
move between chapters, and the reader's own CSS can replace the book's at any moment.

## Features (v0.2.0)

- One window per book (`NSDocument`); macOS window tabs work out of the box.
- Web-style reading: a chapter scrolls vertically as a single entity. No pages, no
  horizontal scrolling, a single view mode.
- Internal links between chapters, history (`⌘[` / `⌘]`).
- One sidebar (`⌘\`, one toolbar button) with a Liquid Glass pane selector: **Chapters**
  (table of contents), **Bookmarks** (`⌘D` adds one, named after the chapter by default;
  Delete removes it) and **Search** (`⌘F`; case-, accent- and quote-insensitive, every
  occurrence with its context; picking one selects it in the page). The last pane is
  remembered per book.
- Reading position remembered per book (`Positions.json`); bookmarks and the last sidebar pane
  in `Books.json`, both in `~/Library/Application Support/Aomidori/`.
- Text size with `+` `-` `0` (or `⌘+` `⌘-` `⌘0`) that always wins over the CSS (px sizes,
  `min()`/`clamp()` caps, `!important`); pictures keep their size; pinch never scales the page.
- User styles: every `.css` in `~/Library/Application Support/Aomidori/Styles/`, edited live
  with any external editor: a save (in place or atomic, as BBEdit, VS Code and TextEdit do)
  shows up in about 0.1 s, keeping the reading position. *Reload Style* (`⌘R`) forces it.
  The book's CSS is used by default; *Override Book Style* (`⌘.`) replaces it with the
  selected user style, including its fonts: nothing of the book's typography survives
  (sheets, `@font-face`, inline styles, `<font face>`). The style choice is global.
- Custom font (`⇧⌘F`, chosen with `⌥⌘F`): any installed family, or TTF/OTF/WOFF files loaded
  into the `Fonts` folder, replaces the font of all text (book and style, override on or off;
  code and formulas excepted) without touching sizes or colors. Global and remembered.
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
    Sidebar/      pane selector, contents, bookmarks and search panes.
    Reader/       window controller, book info window, reader view, and the rendering layer:
                  PageRenderer (one WKWebView), PageSchemeHandler, ReaderScript.
    Styles/       ReaderEnvironment (settings + styles folder), FSEvents watcher,
                  style menu, style picker HUD, custom fonts and their panel.
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
5. `#aomidori-scale`: the text size (below);
6. `#aomidori-font`: the custom font, when on.

The base sheet declares the cascade layer `aomidori` before anything else. `!important` rules
in the first declared layer beat every other author rule, whatever its specificity or order
(CSS Cascade 5), so the text size and the custom font cannot be undone by a book or a style.
Only inline `!important` would still win: the script lifts inline `font-family` while the
custom font is on and puts it back afterwards.

With the override on, book sheets get `media="not all"` (original value kept in
`data-aomidori-media`; their `@font-face` rules stop applying too), legacy `<font face size
color>` attributes are set aside, and inline `style` attributes move to `data-aomidori-style`, except on
`img`, `svg`, `video`, `canvas`, `object`, `embed`, `iframe`, `math` and inside SVG, where they
usually carry intrinsic sizing. Everything is reversible without reloading. Native code
updates the page with `Aomidori.apply(configuration)`; switching or reloading a style swaps the
`<link>` only after the new sheet has loaded, so there is no unstyled flash, and the line being
read stays where it was.

**Live reload.** An FSEvents stream watches the `Styles` folder with file-level events and a
0.1 s latency: the kernel delivers each burst of changes once (a debounce with no polling and no
open file descriptors), and atomic saves, which rename a new file over the old one, look like
any other change. Each event bumps a revision that is part of the style's URL, so the page
fetches the file again even when only an `@import`ed file changed. `⌘R` does the same by hand.

**Text size** is CSS `zoom` on `<body>`, with pictures (`img`, `svg`, `video`, `canvas`,
`iframe`, `object`, `embed`) zoomed back by the inverse factor. The choice, because the size
must win over the CSS whatever it says:

- multiplying the root font size (v0.1) is defeated by any px size or `min()`/`clamp()` cap,
  as in `ReadingRoccobot.css` (`min(1.6em, 26px)`);
- rewriting each element's computed `font-size` inline from JavaScript misses pseudo-elements
  (drop caps, `::before`), leaves px line heights and margins behind, and must be redone after
  every style change or new node;
- `-webkit-text-size-adjust` does nothing on macOS, and `pageZoom` / magnification scale
  pictures and the whole view, which Aomidori never does.

`zoom` scales every length inside the body by the same factor: font sizes in any unit, caps
included, line spacing, margins, the line length in em. Text still wraps to the window, since
the body's available width is divided by the factor, and nothing scrolls sideways. The rules sit
in the `aomidori` layer with `!important`, so no stylesheet can undo them; `0` removes them
(100% of the active style). The factor is also exposed as `--aomidori-scale` on `:root`.

**Custom font.** The chosen family is declared under a private name (`aomidori-custom-font`)
with one `@font-face` per face: `local("<PostScript name>")` first, then the font file itself
served by the app (`/.aomidori/SystemFonts/…`, only the files of the chosen family, resolved
through Core Text), so fonts installed in `~/Library/Fonts` work even if the web view does not
see them by name. Fonts loaded with *Load Font…* are copied to the `Fonts` folder and served
from there. A book's own `@font-face` can never take the family over, because its name is
private. Code (`code`, `pre`, `kbd`, `samp`, `tt`, `var`) and MathML keep their fonts.

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
scripts/test.sh               # unit tests (Swift Testing; `swift test` plus the flags the
                              # Command Line Tools need to find the Testing framework)
scripts/bundle.sh             # build/Aomidori.app, ad-hoc signed, arm64 only
scripts/smoke.sh book.epub    # open a book and save a snapshot of the page to build/smoke.png
ditto -c -k --keepParent build/Aomidori.app Aomidori-0.2.0.zip   # release archive
```

`EPUBKit` and `AomidoriCore` also build and test on Linux (the app target is macOS-only);
IDPF font de-obfuscation needs CryptoKit and its test is skipped there.

The page-side script has its own WebKit tests (text size against px and `min()`/`clamp()` caps,
override and custom font against book fonts, live style reload keeping the position):

```sh
cd scripts/js-tests && npm install && npx playwright-core install webkit && node run.js
```

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
| Sidebar on/off | `⌘\` (and toolbar) | View |
| Sidebar: Chapters, Bookmarks, Search | `⌥⌘1`, `⌥⌘2`, `⌥⌘5` | View |
| Find in book | `⌘F` | Edit |
| Add bookmark | `⌘D` | Go |
| Minimal mode | `⌃⌘M` | View |
| Full screen | `⌃⌘F` | View |
| Override book style on/off | `⌘.` (and toolbar) | Style |
| Previous / next style | `⌘'` / `⌘ì` | Style |
| Style list | `⌘1` | Style |
| Reload style from disk | `⌘R` | Style |
| Custom font on/off | `⇧⌘F` | Style |
| Choose custom font | `⌥⌘F` | Style |
| Load font file | (menu) | Style |
| Book info (metadata, cover) | `⌘I` (and toolbar) | File |
| Open, close | `⌘O`, `⌘W` | File |

Style list: a quick press opens a list that closes when you pick a style (click, or `↑` `↓`
and `↩`; `esc` cancels). Holding `⌘` and pressing `1` again moves to the next style with a
live preview (`⇧` goes back); releasing `⌘` keeps it, like `⌘⇥`.
Choosing a style turns the override on.

## Known limits

- `←` always lands at the top of the previous chapter.
- The position is a scroll fraction of the chapter; after the chapter's layout changes a lot
  (another style, another width) it is approximate. Style and size changes keep the visible
  line in place.
- The text size zooms margins and fixed widths together with the text (the measure in em is
  kept); pictures do not grow.
- With the override off, the book's CSS is used as is: a book without margins touches the
  window edges.
- `←` / `→` are menu shortcuts too, so they change chapter even while a sidebar list has focus
  (not while typing in a text field).
- Search hits are found in the chapter text and then selected with WebKit's find; if the two
  count occurrences differently (hidden text, accents), the page scrolls to the approximate place.
- Not supported yet: fixed-layout EPUBs, vertical writing (it would scroll sideways),
  unpacked (folder) EPUBs, `xml-stylesheet` instructions, DRM-protected books (reported).
- A user style naming an installed font that the web view cannot see by name falls back; the
  `Fonts` folder next to `Styles` (with `@font-face`) or the custom font are the reliable ways.
- Font collections (`.ttc`) are offered to the page by name only.

## Next phases

1. **CSS Playground**: a window with a live preview (sample text or a real EPUB, left) and a
   minimal HTML/CSS editor with syntax highlighting (right), plus a style selector. Ready in
   the code: the preview is a `PageRenderer` driven by `ReaderConfiguration` with a different
   `PageResourceProvider`; *Save to Styles* uses `StyleLibrary.save(css:named:)` (UTF-8 without
   BOM, LF), so the style appears at once in the reader's style list through the folder watcher
   and can be tried live in any reader window; *Save As…* writes a `.css` anywhere with the same
   normalisation.
2. **Windows vs tabs**: test both and pick one.
3. **More sidebar panes**, slots and shortcuts already reserved: Thumbnails (`⌥⌘3`, the
   book's pages in miniature), Images (`⌥⌘4`, every picture in the book), Notes (`⌥⌘6`,
   footnotes and endnotes from `epub:type` / `role` markup). Bookmark renaming and notes.
4. Per-book style memory, precise positions (element anchors), landing at the end of the
   previous chapter, trackpad swipe between chapters, find next/previous (`⌘G`).

Murasaki (closed source) is a reference for the toolbar, sidebar panes and Inspector; no assets
or code are taken from it.

## Icon

The app icon (J3 *Tategaki*) is by Graphe; sources in `Resources/Icon/` (see its README):
`AppIcon.icns` and `AppIcon.iconset` (flat, with simplified 16 and 32 px sizes) are what the
app ships (`CFBundleIconFile`), the SVGs are the artwork, and `J3-layers/` holds the layers for
a Liquid Glass icon. **Future work:** build the layered `.icon` with Icon Composer and compile
it with Xcode's `actool` (not part of the Command Line Tools), then ship it as `Assets.car`
with `CFBundleIconName`, keeping the `.icns` as fallback.

## Licenses

See [THIRD_PARTY.md](THIRD_PARTY.md) (foliate-js font de-obfuscation, ZIPFoundation).
