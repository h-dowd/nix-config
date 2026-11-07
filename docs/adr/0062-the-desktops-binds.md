# 0062 — The laptop takes the desktop's binds

**Status:** Accepted (2026-11-06). Key names in earlier records are the old
`SUPER` scheme.

## Context

The CachyOS desktop (`henry/dotfiles`, `henry/migration` → Binds) left this
machine's binds on 2026-10-16 for a hybrid of the work Mac's AeroSpace config
and this one: a manual dwindle tree, ⌥ for the desktop, ⌘ for the window and
system. On 2026-10-19 it added Toshy, for Mac-style ⌘ shortcuts in apps. The
laptop stayed on `SUPER` and master-stack, so the same hands did different
things on the two machines, and the migration plan left "two configs, or move
the laptop" open.

## Decision

**mango here binds what the desktop's mango binds**, named by what mango
receives, not by the physical key:

| Mac | Physical | mango |
|---|---|---|
| ⌥ | Super | `ALT` |
| ⌘ | Alt | `SUPER+CTRL+ALT` (the ⌘ chord); ⌘Tab is `SUPER+CTRL` |
| ⌃⌘ | Ctrl+Alt | the chord + `SHIFT` |

The ⌘ set is the desktop's and stays small, since each ⌘ bind is a key apps
lose. Noctalia's actions map to this machine's: `shell.sh` for launcher,
clipboard, lock, notifications and panels, `screenshot-region.sh` for ⌘⇧4,
the bar's layout picker for ⌘,.

**Every tag is a dwindle tree with manual splits**, `circle_layout=dwindle,monocle`.
The master-stack and scroller keys go with that layout.

**Keys the desktop lacks stay, on ⌥ slots it leaves free:** brightness,
minimise (`⌥I`, `⌥⇧I`, `⌃⌥I`), monitors (`⌃⌥,` `⌃⌥.`), the rofi menus with no
Noctalia counterpart (`⌥Space` combi, `⌥W`, `⌥=`, `⌥;`, `⌥F1`, `⌥⇧E`), VPN
(`⌃⌥T`), weather (`⌃⌥W`), trackpad gestures.

**⌥[ and ⌥] are bound by keycode** (`code:34`, `code:35`), as on the desktop, so
⌥8 and ⌥9 keep their tags. `docs/gotchas.md` → Desktop.

**keyd sends those modifiers**, not Toshy. `modules/system/locale.nix`:
physical Super is `layer(alt)`; physical Alt is `layer(cmd)`, a `:C` layer, so
every ⌘ key is Ctrl for apps except the ones mango binds, which the layer and
its `cmd+shift`, `alt+cmd` and `control+cmd` composites map to the chord.
⌘Tab is `swapm(cmdtab, C-M-tab)` into a `[cmdtab:C-M]` layer, which holds
Super+Ctrl until ⌘ is released. Terminals take ⌘C, ⌘V and their other
shortcuts on Ctrl+Shift through `keyd-application-mapper` and
`~/.config/keyd/app.conf`; it reads the focused appid over
`zwlr_foreign_toplevel_manager_v1`, which mango advertises (v3 on 0.17.4 and
0.18.4).

Over the alternatives, all of which see the focused app on mango:

- Toshy is not in nixpkgs; its installer adds distro packages, a venv and a
  config directory it rewrites.
- xremap would be a second program grabbing the keyboard keyd already grabs,
  and its ⌘Tab needs press/release actions; keyd's swap layer is built for it.
- keymapper is a third syntax for the same result.

## Consequences

- Without keyd the keys fall back by position, as on the desktop without
  Toshy: physical Alt reaches the ⌥ level, and the ⌘ level needs
  Ctrl+Super+Alt.
- mango's switcher selects on any modifier release, so a ⌘Tab that tapped the
  extra modifiers around Tab would select at once (`henry/migration`,
  2026-10-19). The swap layer exists to prevent that.
- keyd works below the session: the TTY, the greeter and games get the
  positions too.
- ⌃ stays Ctrl, where Toshy makes it Super in GUI apps, so ⌃ and ⌘ reach a
  GUI app as the same Ctrl.
- Each ⌘ bind in mango needs its line in keyd; `checks/static.sh` pairs them.
- The mapper needs the `keyd` group, which the NixOS module does not create,
  and `CAP_SETGID` in keyd's unit. `docs/gotchas.md` → keyd.
- ⌘←/→ are Home/End (⌘⇧ selects), so zsh binds Home/End in vi mode. ⌘⌫
  deletes to line start: Shift+Home then Backspace, or Ctrl+U in terminals.
- ⌥ combos reach mango before apps: Alt+B/F word motion in readline and
  Alt-keyed app shortcuts are gone on the bound letters.
- Dropped with no replacement: floating-window nudges (resize mode and the ⌥
  mouse binds cover them), `togglegaps`, `focusstack`, `SUPER,Delete` lock and
  the `SUPER+CTRL` mouse binds.
- `checks/static.sh` keys its duplicate scan by `key_mode=`, because resize
  mode rebinds `ALT,r` on purpose.
- Ported to mango 0.18's spellings (`key_mode=`, `tag_rule=`) on 2026-11-07,
  when a re-lock moved mango from 0.17.4 to 0.18.4. `docs/gotchas.md` → mango.
