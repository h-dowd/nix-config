# 0063 — kitty runs tmux; one table carries its ⌘ keys

**Status:** Accepted (2026-11-07). Builds on [0062](0062-the-desktops-binds.md).

## Context

The desktop (`henry/dotfiles`, from `henry/macdots`) runs tmux in every kitty
window and drives it with ⌘ keys: Toshy sends ⌘ to kitty as Super, kitty maps
each Super combo to `\e[<9000+n>~`, and tmux binds that as `User<n>`. foot is
the terminal without tmux. The laptop had tmux installed and unconfigured.

Three lists have to agree on every number: kitty's maps, tmux's `user-keys`,
and, here, keyd's `app.conf` lines that send ⌘ to kitty as Super (keyd sends ⌘
as Ctrl everywhere else, 0062). On the desktop the numbers are kept in sync by
a comment in two files. A key in one list and not another does nothing and
logs nothing.

## Decision

**kitty starts `tmux new-session` in every window; foot does not.** The tmux
config is the desktop's, in `modules/home/tmux.nix` through `programs.tmux`:
prefix C-s, splits on s/v in the pane's directory, AeroSpace's move, join and
flatten through `tree.py`, unnamed sessions ending with their window, and
resurrect plus continuum restoring named ones.

**One Nix table, `cmdKeys`, generates all three lists**: kitty's
`keybindings`, tmux's `user-keys`, and a second `[kitty]` section in
`keyd/app.conf` (merged with the one in `default.nix`). ⌘⇧ and ⌘⌃⇧ keys bind
into keyd's `cmd+shift` and `control+cmd+shift` composites, which
`default.conf` defines because `keyd bind` finds a layer by its exact name.

**The theme comes from the palette**, not the desktop's Catppuccin hexes. The
session block is the mode light (accent, warn for a pending prefix, info in
resize mode, brMagenta in copy mode), and the active pane border is `accent`,
mango's `focus_color`, so pane and window focus look the same.

**The nvim pass-through is dropped.** The desktop sends ⌘H/J/K/L on to nvim as
M-hjkl; this nvim maps none of them, so ⌘H/J/K/L always move between tmux
panes.

## Consequences

- ⌘T opens a tmux window and ⌘W closes a pane, not kitty tabs; kitty keeps ⌘N
  (new OS window) and ⌘⇧R (reload its config). ⌘C/⌘V still copy and paste.
- ⌘⇧3 and ⌘⇧4 are mango's screenshots, so the desktop's `User40`/`User41`
  (break or join to windows 3 and 4) are not bound.
- kitty's own scrollback is unused; tmux keeps 50,000 lines.
- `checks/static.sh` fails on a tmux `User<n>` bind with no `user-keys`
  entry, and runs `app.conf`'s composite-layer lines through `keyd check`.
- `tree.py` runs from tmux's `run-shell`, so it needs `python3` on the
  session's PATH.
