# Architecture decision records

Numbered records of decisions that were **expensive to learn** and would be
expensive to re-litigate. Started 2026-07-30, after the Arch→NixOS migration,
by extracting decisions that already existed as prose.

`CLAUDE.md` remains the standing description of *how the system is now*. These
records explain *why it is that way*, and — more usefully — what happened when
it was the other way. Where the reasoning already lives in `CLAUDE.md` or
these link to the record rather than duplicating it, per
`docs/agents/domain.md`.

| # | Decision | Status |
|---|---|---|
| [0001](0001-flake-at-repo-root.md) | The flake lives at the repo root, dotfiles under `home/` | Accepted |
| [0002](0002-out-of-store-dotfiles.md) | Dotfiles a program rewrites stay out-of-store | Accepted (default superseded by [0009](0009-generated-config-over-linked-files.md)) |
| [0003](0003-state-outside-config-tree.md) | Runtime state and user data live outside the config tree | Accepted |
| [0004](0004-mode-scripts-own-theming.md) | Mode scripts own theming; no `active-theme` indirection | Accepted, **amended 2026-07-30 — Nix owns the GTK theme**; only that clause stands since [0061](0061-one-desktop-noctalia-and-wayle-removed.md) |
| [0005](0005-one-owner-per-daemon.md) | Exactly one owner per daemon | Accepted |
| [0006](0006-start-limits-on-remote-units.md) | Any unit touching a remote API needs a start limit | Accepted |
| [0007](0007-language-servers-declared.md) | Language servers are declared, not per-editor | Accepted |
| [0008](0008-arch-removed.md) | Arch removed outright; no dual boot | Accepted |
| [0009](0009-generated-config-over-linked-files.md) | Generate config from Nix where a module exists; link files only where one does not | Accepted |
| [0010](0010-flake-check-is-the-gate.md) | `nix flake check` is the gate; lints tuned to fire only on real findings | Accepted (retires `verify-packages.sh`) |
| [0011](0011-shell-is-gated-too.md) | Shell is gated too; static assertions run inside the build | Accepted (extends [0010](0010-flake-check-is-the-gate.md)) |
| [0012](0012-secrets-in-sops.md) | Secrets live in sops-nix; only what is read is declared | Accepted |
| [0013](0013-networkmanager-profiles-declared.md) | The nine credential-bearing NetworkManager profiles are declared | Accepted (follows [0012](0012-secrets-in-sops.md)) |
| [0014](0014-declare-the-namer-not-just-the-file.md) | Declaring a file is not declaring the config — declare what names it | Accepted (extends [0009](0009-generated-config-over-linked-files.md), [0011](0011-shell-is-gated-too.md)) |
| [0015](0015-hibernate-not-suspend-on-the-lid.md) | The lid hibernates; there is no suspend phase | Accepted (the lid half; amended by [0016](0016-idle-suspends-the-lid-hibernates.md)) |
| [0016](0016-idle-suspends-the-lid-hibernates.md) | The idle rung suspends; the lid still hibernates | Accepted (amends [0015](0015-hibernate-not-suspend-on-the-lid.md)) |
| [0017](0017-tlp-profiles-not-platform-profile.md) | Power modes are TLP profiles; `platform_profile` was a placebo | Accepted |
| [0018](0018-lock-background-is-a-pool.md) | The lock background is a pre-generated pool, picked per lock | Accepted |
| [0026](0026-serve-the-ppd-bus-name-from-tlp.md) | Serve the power-profiles-daemon bus name from TLP, rather than leave it unowned | Accepted (follows [0017](0017-tlp-profiles-not-platform-profile.md), [0005](0005-one-owner-per-daemon.md); closes an inert widget from 0020) |
| [0027](0027-one-editor-nvim.md) | One editor: nvim. Helix is removed | Accepted (amends [0009](0009-generated-config-over-linked-files.md), [0007](0007-language-servers-declared.md)) |
| [0028](0028-one-palette-reaches-every-config-it-can.md) | One palette reaches every config it can; six theme packages it cannot | Accepted (extends [0009](0009-generated-config-over-linked-files.md); follows [0027](0027-one-editor-nvim.md)) |
| [0029](0029-the-lock-ramp-asserts-hue-not-greyness.md) | The lock ramp asserts the palette's hue, not greyness | Accepted (amends [0018](0018-lock-background-is-a-pool.md); forced by the migration [0028](0028-one-palette-reaches-every-config-it-can.md) enabled) |
| [0030](0030-the-scheme-is-a-file-not-an-option.md) | The scheme is a file, not an option; and contrast is asserted | Accepted (follows [0028](0028-one-palette-reaches-every-config-it-can.md), [0029](0029-the-lock-ramp-asserts-hue-not-greyness.md)) |
| [0031](0031-the-idle-inhibitor-outlives-the-bar.md) | The idle inhibitor is a unit, not a bool in the bar | Accepted (extends 0023) |
| [0032](0032-the-theme-file-owns-its-artefacts.md) | The theme file owns its artefacts, and contrast is measured where it is drawn | Accepted (completes [0030](0030-the-scheme-is-a-file-not-an-option.md); amends [0029](0029-the-lock-ramp-asserts-hue-not-greyness.md)) |
| [0033](0033-the-control-centre-is-a-reader.md) | The control centre is a reader, not a second owner | Accepted (extends 0023; follows [0031](0031-the-idle-inhibitor-outlives-the-bar.md)) |
| [0038](0038-weather-is-a-bar-module-the-menu-reads.md) | Weather is a bar module the menu reads, and a stale reading says so | Accepted (applies [0033](0033-the-control-centre-is-a-reader.md) to a fact with no owner) |
| [0039](0039-the-gate-asserts-its-own-size.md) | The gate asserts its own size | Accepted (applies the floor discipline of [0011](0011-shell-is-gated-too.md) and [0014](0014-declare-the-namer-not-just-the-file.md) to the file that enforces it) |
| [0041](0041-artefacts-are-generated-not-named.md) | Artefacts are generated from the palette, not named | Accepted (amends [0032](0032-the-theme-file-owns-its-artefacts.md), 0034) |
| [0042](0042-separators-belong-to-the-layout.md) | Bar separators belong to the layout, not to the module | Accepted (extends [0009](0009-generated-config-over-linked-files.md)) |
| [0043](0043-the-launcher-is-rofis-drun.md) | The launcher is rofi's drun mode; fsel is removed | Accepted (completes 0021; follows 0034) |
| [0044](0044-one-request-carries-the-tooltip.md) | One request carries the tooltip, and the way past it is a link | Accepted, **amended 2026-08-24 — the control-centre row is two keys, not a picker** (extends [0038](0038-weather-is-a-bar-module-the-menu-reads.md)) |
| [0047](0047-a-retired-daemon-is-a-call-that-exits-0.md) | A retired daemon is a call that exits 0 | Accepted (finishes 0045; ends the swayosd trade in 0020); **amended by [0061](0061-one-desktop-noctalia-and-wayle-removed.md)** |
| [0048](0048-state-colour-rides-the-class-the-script-prints.md) | State colour rides the class the script prints | Accepted (amends the "one colour" clause of 0045; sources it from [0028](0028-one-palette-reaches-every-config-it-can.md)) |
| [0050](0050-the-weather-panel-is-rofis.md) | The weather panel is rofi's, because a dropdown answers no key | Accepted (reverses the click clause of 0046; keeps [0038](0038-weather-is-a-bar-module-the-menu-reads.md), [0044](0044-one-request-carries-the-tooltip.md); shares [0047](0047-a-retired-daemon-is-a-call-that-exits-0.md)'s finding that no dropdown opens from outside the bar) |
| [0051](0051-waybar-is-the-tiling-bar-again.md) | Waybar is the tiling bar again, and wayle is installed but unstarted | Accepted (reverses 0045 for tiling and the swaync/swayosd clauses of [0047](0047-a-retired-daemon-is-a-call-that-exits-0.md); follows [0050](0050-the-weather-panel-is-rofis.md); leaves 0020 alone); **wayle removed by [0061](0061-one-desktop-noctalia-and-wayle-removed.md)** |
| [0052](0052-the-bar-draws-the-icon-theme.md) | The bar draws the icon theme, and a minimized window can be picked | Accepted (supersedes the "not adopted" note in [0051](0051-waybar-is-the-tiling-bar-again.md); narrows [0033](0033-the-control-centre-is-a-reader.md)) |
| [0053](0053-the-bar-separates-selection-from-alarm-by-shape.md) | The bar separates selection from alarm by shape, not by hue | Accepted (amends the colour half of [0042](0042-separators-belong-to-the-layout.md) and [0051](0051-waybar-is-the-tiling-bar-again.md); applies [0032](0032-the-theme-file-owns-its-artefacts.md)'s measured-not-chosen rule to the stylesheet) |
| [0054](0054-a-module-reports-the-screen-not-its-schedule.md) | A module reports the screen, not its own schedule | Accepted (applies [0048](0048-state-colour-rides-the-class-the-script-prints.md)'s resting-state rule; closes a hole in [0051](0051-waybar-is-the-tiling-bar-again.md)'s one-glyph-pack check) |
| [0055](0055-night-light-has-a-manual-hold-not-only-a-schedule.md) | Night light has a manual hold, not only a schedule | Accepted (corrects [0054](0054-a-module-reports-the-screen-not-its-schedule.md), which made the module honest about a schedule nobody had chosen to be limited to) |
| [0056](0056-a-declared-refresh-signal-needs-a-sender.md) | A declared refresh signal needs a sender | Accepted (generalises the bar-push half of [0054](0054-a-module-reports-the-screen-not-its-schedule.md); repairs four modules left behind by [0051](0051-waybar-is-the-tiling-bar-again.md)) |
| [0057](0057-one-glyph-pack-was-never-enforced.md) | One glyph pack was never enforced | Accepted (the check [0051](0051-waybar-is-the-tiling-bar-again.md) and [0054](0054-a-module-reports-the-screen-not-its-schedule.md) relied on matched 12 of 51 escapes and passed; adds the third neutral tier [0053](0053-the-bar-separates-selection-from-alarm-by-shape.md) had in practice but not in writing) |
| [0058](0058-one-text-face-and-the-window-that-is-playing.md) | One text face, one calendar surface, and the window that is playing | Accepted (follows [0057](0057-one-glyph-pack-was-never-enforced.md); retires 0019, 0021, 0035, 0046 and trims 0045) |
| [0059](0059-the-bar-is-3270-body-text-is-hack.md) | The bar is 3270; body text is Hack | Accepted (reverses the font clause of [0058](0058-one-text-face-and-the-window-that-is-playing.md); its glyph unification stands) |
| [0060](0060-rofi-draws-the-schemes-icon-set.md) | rofi draws the scheme's icon set | Accepted (extends [0052](0052-the-bar-draws-the-icon-theme.md) to rofi; corrects the icon clause of [0043](0043-the-launcher-is-rofis-drun.md), which named the wrong cause) |
| [0061](0061-one-desktop-noctalia-and-wayle-removed.md) | One desktop: noctalia and wayle are removed | Accepted (retires 0020, 0022, 0023, 0024, 0025, 0034, 0036, 0037, 0040, 0045, 0049; amends [0004](0004-mode-scripts-own-theming.md), [0047](0047-a-retired-daemon-is-a-call-that-exits-0.md), [0051](0051-waybar-is-the-tiling-bar-again.md)) |

## Format

Each record: **Status**, **Context** (what was true, and what went wrong),
**Decision**, **Consequences** (including what it costs). Write the failure
mode down — a decision whose motivating bug is not recorded gets undone by the
next person who thinks it looks redundant.
