# 0060 — rofi draws the scheme's icon set

**Status:** Accepted (2026-08-29)

Extends [0052](0052-the-bar-draws-the-icon-theme.md) from the bar to rofi, and
corrects the icon clause of [0043](0043-the-launcher-is-rofis-drun.md).

## Context

0043 turned the launcher off with one line: drun icons "would resolve the icon
*set*, which is a `native = false` stand-in on this scheme and falls back
silently". Both halves were wrong, and each was wrong differently.

`native = false` does not mean absent. It marks a set that does not follow the
palette, and 0041 gives the reason it cannot: an icon set is mostly app **brand
colours**, which must not be recoloured. That applies to the bar too, and 0052
had already put Papirus on the bar through `-gtk-icontheme()` and in
`minimized-menu.sh`. The launcher was the only surface still refusing it.

The silence was real but came from somewhere else. **rofi does not read GTK's
icon theme.** `config.icon_theme` is its own setting, and unset the fetcher
falls back to `{"Adwaita", "gnome"}` plus hicolor
(`rofi-icon-fetcher.c:276`). So the first day drun had icons it drew Adwaita
art beside Papirus everywhere else, and resolved 90 of 97 desktop entries
rather than 96. An unresolved name draws a blank column, never an error.

Window mode has a second, unrelated gap. `wayland-window.c:610` queries the
icon theme with the **lowercase appid** and takes no desktop-file step, unlike
drun. An appid that is not itself an icon name draws nothing: `zen-beta`,
`dev.zed.Zed`, `yazi`, every Steam game. 44 of 97 candidate appids resolved
before the theme was named, 55 after.

## Decision

**rofi names the scheme's icon set, and the appid gap is closed with generated
aliases.**

- `modules/home/dotfiles.nix` generates `rofi/icons.rasi` from
  `p.packages.icons.name`; `config.rasi` `@import`s it beside `colors`. One
  owner for the name, so it cannot drift from what GTK wears. Scheme-level and
  not per mode — the icon set is an artefact and follows `scheme.nix`, not
  `modes.nix` (0034), which
  is why it is a second file rather than a line in `colors.rasi`.
- `-show-icons` at the **call site** for drun and window, not in `config.rasi`.
  The fourteen hand-built `-dmenu` menus carry nf-md glyphs in the entry string
  ([0057](0057-one-glyph-pack-was-never-enforced.md)); a global flag would buy
  them a per-row theme lookup that finds nothing.
- `modules/home/waybar.nix` builds `rofi-app-icon-aliases` from the `appIcons`
  map it already owns: one `hicolor/scalable/apps/<appid>.svg` symlink per
  appid the theme has no name for. Sourced from `themeIcons`, so an alias
  follows whichever scheme is selected rather than pinning Papirus art into a
  Nord session.

**A package, not an `xdg.dataFile`.** The profile's buildEnv then reports a name
another package already owns as a collision at `nix flake check`, rather than
one of the two silently winning. That is why `equibop` is not aliased: it ships
its own hicolor icon.

**Largest size wins.** The first build linked 16×16 art under `scalable/`.
Papirus draws its small sizes simplified, so rofi rendered that at menu size.

## Consequences

| | before | after |
|---|---|---|
| drun | 90/97 | 96/97 |
| window | 44/97 | 55/97, plus every curated appid |

- `checks/static.sh` asserts the **floor**, not the alias list: every appid in
  `app-icons.json` must resolve, however it resolves — by the theme, by the
  app's own hicolor icon, or by an alias. An appid added to `appIcons` and
  forgotten here fails the gate; an alias that stops being needed does not.
- Uncurated appids still draw a blank. Adding one to `appIcons` is the same act
  as curating it for the bar's window-title module, and the check names any that
  go missing.
- The alternative for window mode was a hand-built menu over `mmsg get
  all-clients` passing an absolute `.desktop` path per row, which the fetcher
  resolves (`rofi-icon-fetcher.c:575`, nested under `g_path_is_absolute`). It
  reaches everything with a desktop file, at the cost of reimplementing
  activation and losing rofi's `window-format`. Recorded in `docs/gotchas.md`
  rather than taken.
- Ten dead `.desktop` files were removed the same day — `/opt` and
  `~/Applications` carryover from Arch. They were three of drun's misses.
