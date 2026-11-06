# 0004 — Mode scripts own theming; no `active-theme` indirection

**Status:** Accepted (2026-07-30). The mode scripts are gone since
[0061](0061-one-desktop-noctalia-and-wayle-removed.md); the clause that stands is
the 2026-07-30 amendment: Nix owns the GTK theme.

## Context

Theming is driven by the Mangowm mode scripts in
`dotfiles/mango/scripts/modes/`. Terminals used to reach their palette through an
indirection: `kitty/active-theme.conf` and `foot/active-theme.ini` were symlinks
that each mode script rewrote on every switch.

The indirection **selected nothing**. Both `tiling.sh` and `hud.sh` pointed the
symlinks at the *same* gruvbox files, and `kitty.conf` was including its theme
twice as a result. It had been meaningful only while the removed `dms` mode
carried its own palette.

It also cost something concrete: a config directory containing a symlink that
gets rewritten at runtime must stay writable, and therefore out of the store.

Separately, home-manager's `gtk` block and `mango/scripts/system/gtk-apply.sh`
both write the same dconf keys, and home-manager reasserts its values on every
`nixos-rebuild switch` and at login — so declaring `gtk` in Nix silently reverts
whatever a mode switch just set.

## Decision

- Terminals name their theme directly. `kitty.conf` includes
  `gruvbox-orange.conf`; `foot.ini` includes `gruvbox-colors.ini`.
- ~~Mode switching is the point of the setup, so **the scripts win**: the `gtk`
  block stays out of `modules/home/theme.nix`.~~ **Amended 2026-07-30 — Nix
  owns GTK; see below.**

## Amendment (2026-07-30): Nix owns the GTK theme

The original decision rested on a premise that was never checked, and was
false. **GTK theming here is not mode-dependent.** Three facts:

- `gtk-apply.sh` took a `$MODE` argument and then ignored it — it copied the
  `-tiling` variants unconditionally.
- Both `tiling/autostart.conf` and `hud/autostart.conf` invoked it as
  `gtk-apply.sh tiling`. Even hud asked for tiling.
- `settings-tiling.ini` and `gtk-tiling.css` were byte-identical to the
  `settings.ini` / `gtk.css` they were copied over.

So the per-mode GTK machinery selected nothing — the same empty indirection as
the `active-theme.*` symlinks removed the same day, and for the same reason:
it was meaningful only while the `dms` mode had its own palette.

With no mode switch to fight, the conflict that motivated the original decision
cannot occur. `modules/home/theme.nix` now declares `gtk.*`, which generates
both `settings.ini` files, both `gtk.css` files and the Thunar bookmarks, and
writes the matching dconf keys — strictly more than the script did by hand.

Per the rule below, the `cp` and `gsettings` lines were removed from
`gtk-apply.sh` **in the same change**. What remains is the part home-manager
does not do: `GTK_THEME` in the systemd user environment, and restarting
`xdg-desktop-portal-gtk`, which caches the theme at startup.

## Consequences

- `kitty/` and `foot/` became store-based ([0002](0002-out-of-store-dotfiles.md)),
  and `gtk-3.0`/`gtk-4.0` are now generated outright.
- Do not reintroduce `active-theme.*`. Naming the theme directly is what keeps
  those directories in the store.
- **The rule still stands, in both directions**: never have `theme.nix` and
  `gtk-apply.sh` both setting the theme. One owner. Adding the `gsettings`
  lines back without removing the `gtk` block reintroduces exactly the silent
  revert this ADR was written about.
- If a future mode ever *does* need its own GTK palette, this amendment is what
  to reopen — the answer would be to drive it from the mode script again, and
  drop the `gtk` block in the same change.
