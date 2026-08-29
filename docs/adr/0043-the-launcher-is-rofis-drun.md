# 0043 — The launcher is rofi's drun mode

**Status:** Accepted (2026-08-21)

Completes the walker removal, which replaced the
menu layer with rofi and explicitly left `fsel` on `SUPER+space`. Follows
[0034](0034-colour-follows-the-mode-artefacts-do-not.md) — the half of the
system that can follow a mode switch.

## Context

`fsel` was the launcher: a TUI, launched as `foot -a fsel-launcher -e fsel
--detach`, floated by an appid-keyed window rule. It worked. Nothing in
`docs/gotchas.md` is about it.

What it cost was structural, and all of it was carried for one key:

- a **version override** in `pkgs/default.nix` with two hashes, pinning 3.6.0
  because nixpkgs has 3.1.0 and the generated config is written for 3.6.0 — a
  thing to re-check on every bump
- a generated `fsel/config.toml`, and a row in the palette table in
  `checks/static.sh` to prove it was still generated
- an appid-keyed float rule with a hand-tuned geometry, which is the shape that
  stops matching silently when an appid changes
- **a terminal in the launcher's path.** Two processes deep, and the outer one
  is the one that draws.

Against that, `rofi` was already drawing every other menu, and `drun,run` were
already in `config.rasi`'s `modes:` list, **reached by nothing** — which is the
exact state rofi itself was in before 0021.

The colour half decided it. rofi's `colors.rasi` is a runtime symlink
`apply_theme` re-points per desktop mode (0034); `fsel`'s colours were baked
from `scheme.nix` at rebuild and could not follow a mode switch. One key was
holding the launcher out of the arrangement every other menu is in.

## Decision

**`SUPER+space` is `rofi -show drun`. `fsel` is removed.**

```sh
fb_launcher() { rofi -show drun -matching fuzzy -sort -sorting-method fzf; }
```

**The flags are on the command line, not in `configuration {}`.** `matching`
and `sort` are global, and the nine hand-built `-dmenu` menus want rofi's
default matching over their short, hand-ordered entries. Verified with
`rofi -dump-config`: the command line wins for both — unlike `-l`, which the
theme overrides on rofi 2.0 (`docs/gotchas.md` → rofi).

**The window border becomes `@accent`.** The reasoning it replaces —
*"a saturated ring reads as an alert rather than an edge"* — was written when
rofi drew menus only, and the launcher was a separate window mango bordered
itself. Now the same surface is the launcher, and `@accent` **is** mango's
`focuscolor`: one ring, drawn by whichever of the two is in front. Measured
against `@base` across every scheme in service, not just the selected one:

| heartbox | gruvbox | nord | mocha | mocha-high-contrast |
|---|---|---|---|---|
| 3.87:1 | 5.94:1 | 5.99:1 | 8.07:1 | 9.23:1 |

`bg3` and `comment` remain unusable for this, both collapsing in nord at
1.69:1 — that is the border `@subtext` replaced in the first place.

## Consequences

- **Pinning is gone.** `pin_color`, `pin_icon` and `pinned_order` have no rofi
  equivalent. `ranking_mode = "frecency"` is roughly covered by rofi's own drun
  history. The pins were not used; that is the whole of why this is affordable.
- The sidebar geometry is gone with it — 420×1000 at x=98, against rofi's
  centred 40em. This is a look traded for one menu layer.
- Deleted: the package line, the overlay override and its two hashes, the
  generated `config.toml`, its palette-table row, and the window rule.
- **The mode switcher now draws.** `-dmenu` is single-mode, so no rofi window
  here had ever shown one; `-show drun` shows tabs for all four modes. It had
  no rule in `config.rasi` and would have rendered on rofi's own metrics the
  first time the launcher opened. Styled flat, with the selected tab underlined
  rather than blocked — `selected-normal-background` is already an accent block
  and two of those in one window compete.
- `run` stops being a mode nothing reaches: it is one tab from `drun`.
- **Icons stayed off until 2026-08-29, on a reason that was wrong.** The claim
  was that drun would resolve a `native = false` icon set and fall back
  silently. It does not: drun resolves the desktop file's own `Icon=`, and every
  visible entry has one — the only three that did not were dead Arch-carryover
  `.desktop` files pointing into `/opt` and `~/Applications`, removed the same
  day. **97 of 97 was measured against the wrong chain**, though, and corrected
  hours later: rofi does not read GTK's icon theme, so the real figure was 90 of
  97 against its `{Adwaita, gnome}` fallback. `rofi/icons.rasi` now names the
  scheme's icon set and it is 96. `native = false` marks a set that does not follow the
  palette, and [0041](0041-artefacts-are-generated-not-named.md) gives the
  reason it cannot: app icons are brand colours. That applies to the bar too,
  and [0052](0052-the-bar-draws-the-icon-theme.md) draws the same set there and
  in `minimized-menu.sh`. `-show-icons` is on `fb_launcher`, not in
  `config.rasi`, for the reason the other two flags are.
- The launcher's colours now follow the desktop mode, like every other menu.
- `checks/static.sh` needs no new assertion for the bind: its rofi-mode scan
  already reads `-show <mode>` out of the mango tree and asserts rofi has it,
  so a launcher pointed at a mode this rofi does not build fails the gate.
