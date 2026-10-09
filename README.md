# Aomidori

A minimal, fast EPUB reader for macOS (Apple Silicon, macOS 27 Golden Gate and later),
in the spirit of Murasaki: each chapter is one web page that scrolls vertically, `←`/`→`
move between chapters, and the reader's own CSS can replace the book's at any moment.

## Features (v0.4.1)

- One window per book (`NSDocument`), as native tabs: books open as tabs of the front reader
  window (tabbing mode *preferred*), and `⌘T` (or the tab bar's `+`) adds an empty tab.
- The empty reader window, shown at launch with no book, when the Dock icon is clicked with no
  windows, and in a new tab, has the reader's toolbar and, from the top: Graphe's drop zone
  (drop an `.epub` on the window; it lights up), *Open an EPUB or drag it here* with an Open
  button (`⌘O`), and the recent books (file name; full path in the tooltip). A click, or
  `↑`/`↓` and Return, opens a recent book. The list follows the system's Recent Items count
  and leaves out files that are missing (they reappear when their volume is back). Whatever
  is opened from an empty window takes its place: same frame, same tab.
- Web-style reading: a chapter scrolls vertically as a single entity. No pages, no
  horizontal scrolling, a single view mode.
- Internal links between chapters, history (`⌘[` / `⌘]`).
- One sidebar (`⌘\`, one toolbar button) with a Liquid Glass pane selector: **Chapters**
  (table of contents), **Bookmarks** (`⌘D` adds one, named after the chapter by default;
  Delete removes it) and **Search** (`⌘F`; case-, accent- and quote-insensitive, every
  occurrence with its context; picking one selects it in the page). The last pane is
  remembered per book.
- Reading position remembered per book, and per chapter: `←` / `→`, the table of contents and
  links without a fragment land where each chapter was left (scroll fraction plus an element
  anchor, so text size and style changes do not move it). Kept in `Positions.json`; bookmarks
  and the last sidebar pane in `Books.json`, both in `~/Library/Application Support/Aomidori/`.
- Chapter edges: at the end of a chapter (or on a page that does not scroll, like the cover),
  Space, `↓`, Page Down or scrolling down shows a small toast, *Go to next chapter* (or *End of
  book*). Clicking it opens the next chapter at the top (or, at the end, the book's contents
  page, else its start); with the pointer on the toast, the same key or scroll again does too.
  At the top, Shift-Space, `↑`, Page Up or scrolling up offers *Go to previous chapter*, which
  lands where that chapter was left. On a trackpad only a deliberate push past the edge counts
  (momentum never does); the toast goes away after 3 s or when scrolling back.
- Covers and other single-picture pages are whole and centred in the window, whatever the
  window size, style, override, text size or Night.
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
  The chooser also picks the face (*Automatic* keeps the book's and the style's weights) and
  sets each axis of a variable face; the system **Font panel** (`⌥⌘T`) works too, with its
  Typography features (small caps, old-style figures, ligatures, stylistic sets…). With a
  chosen face, bold text is 300 heavier (at most 900: Light → Semibold, Regular → Bold), and
  an italic face makes italic text upright, as emphasis does in italic typesetting.
- Day/Night with one click. Styles with `prefers-color-scheme` rules follow it natively; for CSS
  without them, Night applies only the colors of the default style's dark rules.
- Minimal mode: no toolbar, title or window buttons, only text.
- Book info window (`⌘I`): metadata and cover image.
- **CSS Playground** (`⇧⌘P`): edit a style with a live preview on a sample chapter or a real
  book, then save it to the styles folder and try it in the reader at once (see below).
- English and Italian interface, following the system language.
- Liquid Glass app icon by Graphe, with light, dark, tinted and clear appearances.

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

Each face is declared with its exact weight and width, taken from Core Text's traits (so
Light, Book and Medium keep separate slots); a variable font is declared once per file with
its `wght`/`wdth` ranges, so CSS weights drive its axes. The choice is stored as a record
(family, face, weight, italic, width, other axes, features), and becomes `font-weight`,
`font-style`, `font-stretch`, `font-variation-settings` and `font-feature-settings`. Which text
is bold or italic is decided whenever the page or the font changes, from the cascade with only the family replaced
(`data-aomidori-bold`, `data-aomidori-italic`), and those elements get the bold weight or the
opposite style. Font panel features arrive either as OpenType tags or as Apple feature
type/selector pairs; the common pairs are translated to OpenType tags, the others are ignored.

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

Requirements: Apple Silicon, macOS 27, Swift 6.4 Command Line Tools. Xcode is optional: with
it, `scripts/bundle.sh` also compiles the Liquid Glass icon (see [Icon](#icon)).

```sh
swift build -c release        # build
scripts/test.sh               # unit tests (Swift Testing; `swift test` plus the flags the
                              # Command Line Tools need to find the Testing framework)
scripts/bundle.sh             # build/Aomidori.app, ad-hoc signed, arm64 only
scripts/smoke.sh book.epub    # open a book and save a snapshot of the page to build/smoke.png
scripts/smoke-playground.sh build/pg [book.epub]   # scripted Playground session: snapshots, report.json
scripts/smoke-reader.sh build/rd book.epub         # cover at 3 window sizes, chapter memory, edge toast
scripts/smoke-launch.sh build/ln book.epub         # launch with no book: empty window, open, new tab, Dock reopen
scripts/check-icon.sh build/icon                   # icon in its six appearances (ictool), Assets.car contents
ditto -c -k --keepParent build/Aomidori.app Aomidori-0.4.1.zip   # release archive
```

`EPUBKit` and `AomidoriCore` also build and test on Linux (the app target is macOS-only);
IDPF font de-obfuscation needs CryptoKit and its test is skipped there.

The page-side script has its own WebKit tests (text size against px and `min()`/`clamp()` caps,
override and custom font against book fonts, live style reload keeping the position, saved
positions, scroll edges, covers centred at three viewport sizes in every mode):

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
They are defined in one table, `Shortcuts.table` in AomidoriCore; a test fails if two commands
share a shortcut. `⌘T` opens a new tab, as in Safari and Finder, so the Font panel is on `⌥⌘T`
(Aomidori has no Show Toolbar command, which other apps put there).
Menu names are given in English; in Italian they are Archivio, Vista, Vai, Stile.

| Action | Shortcut | Menu |
| --- | --- | --- |
| Previous / next chapter (where it was left) | `←` / `→` | Go |
| At a chapter's end / start: offer the next / previous chapter | `Space`, `↓`, `PgDn` / `⇧Space`, `↑`, `PgUp`, or scroll | (toast) |
| Go there | click the toast, or the same key or scroll with the pointer on it | (toast) |
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
| Font panel (custom font) | `⌥⌘T` | Style |
| Load font file | (menu) | Style |
| Book info (metadata, cover) | `⌘I` (and toolbar) | File |
| New tab (empty window) | `⌘T` | File |
| Open, close | `⌘O`, `⌘W` | File |
| CSS Playground | `⇧⌘P` | Style |
| Playground: open a CSS file | `⇧⌘O` (and the Open button) | File |
| Playground: preview an EPUB / the sample text | `⌥⌘O` / `⇧⌘E` (and toolbar) | File |
| Playground: save to Styles / save CSS as | `⌘S` / `⇧⌘S` (and toolbar) | File |
| Playground: Day ↔ Night of the preview | `⇧⌘N` (and toolbar) | View |
| Playground: previous / next chapter of the book | `←` / `→` (outside the editor), toolbar | Go |
| Playground editor: undo / redo | `⌘Z` / `⇧⌘Z` | Edit |
| Playground editor: find, next, previous, use selection | `⌘F`, `⌘G`, `⇧⌘G`, `⌘E` | Edit |

Style list: a quick press opens a list that closes when you pick a style (click, or `↑` `↓`
and `↩`; `esc` cancels). Holding `⌘` and pressing `1` again moves to the next style with a
live preview (`⇧` goes back); releasing `⌘` keeps it, like `⌘⇥`.
Choosing a style turns the override on.

## CSS Playground

`⇧⌘P` (*Style → CSS Playground*) opens a window with the preview on the left (half the width,
full height) and the CSS on the right; below the editor, the styles folder's files.

- It starts with the default style (`ReadingRoccobot.css`). Double-click another style to load
  it; *Open…* (`⇧⌘O`) loads a `.css` from anywhere. The list always marks the style the editor
  holds; an outside file is named under the Open button.
- **Files are never modified by editing**: the editor works on a copy kept in memory, which the
  preview reads as if it were a file in the styles folder, so relative URLs (`../Fonts/…`,
  `@import`) resolve exactly as they will once saved. Every edit reaches the preview after a
  100 ms pause in typing, keeping the visible line in place.
- The preview is the reader itself (renderer, scheme handler, page script) with the override
  on: the book's CSS is removed and the edited CSS applied, with the reader's text size and Night
  palette, so what you see is what you get. The custom font is left out, so `font-family`
  edits show. Its own Day/Night (`⇧⌘N` while the Playground is in front, or the toolbar)
  previews `prefers-color-scheme` without changing the reader.
- The preview text is a bundled sample chapter (`Resources/Playground/sample.xhtml`, original
  Italian prose) with everything a book usually has: title page, epigraph, parts and chapters
  (`h1.up`, `h1.no`), `h2`/`h3`, `.titoletto`, centred, right-aligned and justified text, a
  blockquote, a poem in `.vv` lines, `.neg` and `.side` paragraphs, small caps, italics, bold,
  note references and a notes section, a picture (`img.partit`) with caption, a table, lists,
  a rule, a link and code, with the class names of `ReadingRoccobot.css`. *Load EPUB*
  (`⌥⌘O`) previews a real book instead, chapter by chapter with `←`/`→`; *Sample Text*
  (`⇧⌘E`) goes back.
- *Save to Styles* (`⌘S`) asks for a name and warns before replacing a file; the style appears
  at once in the reader's list (and reader windows using it reload it). *Save CSS As…* (`⇧⌘S`)
  writes anywhere. Either way the file is UTF-8 without BOM, with LF line endings and a final
  newline; non-ASCII characters stay UTF-8 and no `@charset` is added. After saving, the file
  is the selected style and the editor is no longer marked as edited.
- Closing the window, quitting, or loading another style with unsaved changes asks whether to
  save them to Styles, discard them or cancel.
- The editor: native text view, monospaced system font, line numbers, undo, find bar, two-space
  Tab (`⇧⇥` removes it), Return keeps the indentation (one level more after `{`). Syntax
  colouring for CSS (selectors, properties, values, numbers and units, colours, strings,
  comments, at-rules, `!important`) and basic HTML and JavaScript (chosen by file extension, or
  by content when pasted). After each edit the text is tokenized again (about 2 ms for 4,000
  lines) and only the span whose tokens changed is re-coloured.

## Known limits

- A saved position is found again by its element (paragraph); inside a very long paragraph
  the offset is proportional, so after a large layout change it is close, not exact. If the
  book changes, the scroll fraction is used.
- Single-picture pages are recognised by their markup (one picture and no other text, or an
  `epub:type="cover"` / `cover-page` marker); the manifest's cover properties are not consulted.
- The contents page for *End of book* is the EPUB 3 navigation document if it is in the reading
  order, else a spine item named `toc`, `contents`, `indice` or `sommario`.
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
- Font collections (`.ttc`) are offered to the page by name only, so their variable axes and
  exact weights depend on WebKit finding the face by name.
- Font panel: size and effects (color, shadow, underline) are not offered, the style and the
  text size own those. Apple features without an OpenType equivalent are ignored.
- Letter spacing is not part of the custom font.
- Playground: an outside CSS file's relative URLs resolve in the styles folder (where it
  would be saved), not next to the original file. HTML and JavaScript are only coloured: the
  preview applies the editor's text as CSS. Colours are not shown as swatches.

## Next phases

1. **More sidebar panes**, slots and shortcuts already reserved: Thumbnails (`⌥⌘3`, the
   book's pages in miniature), Images (`⌥⌘4`, every picture in the book), Notes (`⌥⌘6`,
   footnotes and endnotes from `epub:type` / `role` markup). Bookmark renaming and notes.
2. Per-book style memory, trackpad swipe between chapters, find next/previous in books (`⌘G`).

Murasaki (closed source) is a reference for the toolbar, sidebar panes and Inspector; no assets
or code are taken from it.

## Icon

The app icon (v2, flat *Tategaki*) is by Graphe; sources in `Resources/Icon/` (see its README).

- `AppIcon.icon` is the Liquid Glass icon (Icon Composer format: `icon.json` plus `Assets/`),
  built from Graphe's `layers/` SVGs, unaltered. With Xcode installed, `scripts/bundle.sh`
  compiles it with `actool` into `Contents/Resources/Assets.car`, found through
  `CFBundleIconName`. The system renders the light, dark, tinted and clear appearances from it.
- `AppIcon.icns` and `AppIcon.iconset` (flat, with a simplified 16 px size) ship as the
  fallback (`CFBundleIconFile`), and are the only icon in builds made with the Command Line
  Tools alone.

How `icon.json` maps Graphe's settings (check renders with Icon Composer's `ictool`, e.g.
`ictool AppIcon.icon --export-image --output-file x.png --platform macOS --rendition Dark
--width 512 --height 512 --scale 1`):

| Graphe | `icon.json` |
| --- | --- |
| Canvas gradient #5DCDB7 → #3ABCA3 around base #49C7AE (dark, near-uniform #24332F → #18221F) | document `fill-specializations` |
| `01-pages` white (dark #49C7AE, mono white), Liquid Glass, low or no specular, light neutral shadow, low translucency | group `Pages`: layer `glass: true`, `specular: false`, shadow neutral 0.3, translucency 0.2 |
| `02-lines` #49C7AE at about 85 % (dark #12302A, mono #8C8C8C), no glass, no specular | group `Lines` (drawn on top): layer `glass: false`, `opacity: 0.85`, `specular: false` |
| Artwork on a 1024 canvas with an 824-point tile | `position.scale` 1024 / 824 |

Notes from building it: in `groups` and `layers` the **first entry is drawn on top**; layer
colours come from `fill-specializations`, not from the SVGs (their colours were not honoured in
our renders); the gradient's slight diagonal cannot be expressed in `icon.json`, so it runs top
to bottom.

## Licenses

See [THIRD_PARTY.md](THIRD_PARTY.md) (foliate-js font de-obfuscation, ZIPFoundation).
