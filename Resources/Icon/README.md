# Aomidori app icon v2 (flat Tategaki), by Graphe

- `aomidori-v2.svg`, `aomidori-v2-dark.svg`: final artwork, Default and Dark (simulated look).
- `aomidori-v2-small16*.svg`: simplified artwork for the 16 px fallback sizes.
- `layers/`: Graphe's layers for Icon Composer (see `layers/README.md`), the source of the
  Liquid Glass icon. `00-background-reference.svg` is a reference only: the background is the
  canvas fill.
- `appearances/`: the six appearances, an approximate simulation.
- `AppIcon.iconset/` + `AppIcon.icns`: flat fallback PNGs (16 to 1024 px).
- `AppIcon.icon/`: the Liquid Glass icon (Icon Composer format) built from `layers/`, compiled
  by `scripts/bundle.sh` (see the Icon section of the main README).

The previous icon (J3) is in the git history (up to v0.4.1).
