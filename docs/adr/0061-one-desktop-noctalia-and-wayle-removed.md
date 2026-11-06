# 0061 — One desktop: noctalia and wayle are removed

**Status:** Accepted (2026-11-06). Retires 0020, 0022, 0023, 0024, 0025, 0034,
0036, 0037, 0040, 0045 and 0049. Amends
[0004](0004-mode-scripts-own-theming.md) (only its GTK clause stands),
[0047](0047-a-retired-daemon-is-a-call-that-exits-0.md) and
[0051](0051-waybar-is-the-tiling-bar-again.md) (wayle is gone, not unstarted).

## Context

The machine had two desktop modes: `tiling` (waybar, swaync, swayosd, awww,
square and flat) and `noctalia` (noctalia-shell for all of those, rounded and
animated). wayle had been the tiling shell for three days and was then left
installed but unstarted (0051). Only `tiling` was in use.

What the second mode cost, measured on 2026-11-06 before removal:

- about 3,200 lines in files that existed only for it — `wayle.nix` (871),
  `mode-theme.nix`, the noctalia start and mode scripts, `dotfiles/wayle/`;
- 748 further lines naming noctalia, across 78 files;
- 26 of 57 ADRs and about 416 lines of `docs/gotchas.md`;
- two overlay overrides to keep noctalia building and talking to mango
  (breakpad dropped from `noctalia-qs`; `MangoService.qml` patched off dwl's
  flags), and a lock wrapper that asked noctalia first;
- a runtime mode switch that re-pointed five config paths as symlinks, so none
  of them could be generated, and the checks that guarded the two-owners
  failure that arrangement invited.

Most of that was not the second desktop itself but keeping the two consistent:
per-mode colour sidecars, a ceiling on how far `modes.nix` could diverge, the
idle-inhibitor handover, night light not crossing a switch, a router
(`menus/shell.sh`) that sent each key to whichever shell owned the job.

## Decision

**One desktop.** Removed:

- `noctalia-shell`, its unit, its overlay overrides, its mango conf, keys and
  seeded settings, and the lockscreen wrapper's noctalia branch;
- wayle, `wayle.nix`, `dotfiles/wayle/`, `scripts/wayle/`, and
  `adwaitaShellIcons`, which only wayle installed;
- the mode switch: `modes.nix`, `mode-theme.nix`, `mode.sh`, `desktop-mode.sh`
  (SUPER+CTRL+/), `scripts/modes/`, and `apply_mode` / `apply_theme` in
  `lib.sh`.

**`dotfiles/mango/config.conf` is tracked**, and is what `tiling/tiling.conf`
was. `tiling/autostart.conf` merged into `universal/autostart.conf`.

**Colours come from typed options where one exists.** kitty, foot and ncspot
take theirs in `programs.<app>.settings`; rofi's `colors.rasi`, mango's
`universal/colors.conf` and Equibop's `palette.theme.css` are generated files.
Equibop's `enabledThemes` is written by a home-manager activation step, because
Equibop rewrites its own `settings.json`.

**`menus/shell.sh` stays as the one action table** the binds call, without the
noctalia half. `phone-status.sh` loses its `bar` verb, which existed for wayle's
`hide-if-empty`.

**`checks/static.sh` audits one scheme**, the one `scheme.nix` names.

## Consequences

- A rebuild applies a colour change to kitty, foot, rofi, ncspot and Equibop.
  There is no runtime swap left to forget.
- `programs.ncspot.settings` may hold values now; nothing else owns
  `ncspot/config.toml`.
- A home-manager activation step removes the old runtime symlinks
  (`mango/config.conf`, the four colour links, `wayle/config.toml`) when they
  point outside the store, before `checkLinkTargets` would refuse them.
- `wlsunset`'s `Restart=always` outlived its reason (noctalia's `pkill`). It is
  kept; the check that asserted it is gone.
- Bringing a second desktop back means rebuilding the per-mode colour path.
  `git revert` of this change restores all of it, including the 11 records.
