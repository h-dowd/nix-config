# CLAUDE.md

`~/src/nix-config` — the NixOS flake that builds this ThinkPad, plus the dotfiles
it installs. Arch is gone: no dual boot, no fallback.

**One desktop: mango, with waybar as the bar**, swaync for notifications,
swayosd for the OSD and awww for the wallpaper. noctalia and wayle are removed,
and with them the desktop-mode switch (`docs/adr/0061`).

```
flake.nix          at the ROOT — load-bearing (docs/adr/0001)
hosts/thinkpad/    host config + hardware-configuration.nix
modules/system/    boot, locale, networking, audio, desktop, fonts, power, …
modules/home/      home-manager: packages, shell, dotfiles, theme, programs, waybar
dotfiles/          hand-written app config (mango, nvim, zsh, swaync, scripts, …)
pkgs/              overlay for anything not in nixpkgs
checks/            assertions run by `nix flake check`
secrets/           sops-encrypted, tracked in git (docs/adr/0012)
```

`docs/ANATOMY.md` is the full map: every file, what it holds, and why the tree is
arranged this way.

## Most failures here are silent

Most of what has broken this machine broke without reporting anything: a waybar
module rendering empty instead of erroring, a script exiting 127, a `pkill`
matching nothing, a window rule whose appid never matches, an `mmsg` flag that
returns `{"error":…}` and exits 0, six absent language servers, a GTK `url()`
that fails without a log line. **A missing component and a broken one look
identical.** Exit status is not evidence.

Three habits follow, and they matter more than any single fact below.

- **Prefer generated config.** A typed home-manager option turns a typo into an
  evaluation error. See the tier rule.
- **Verify by output, not by exit status.** Run the command by hand and check
  that the output is non-empty: `rofi -no-config -h`,
  `nvim --headless '+checkhealth lsp' +qa`, the module's own `exec`.
- **Assert a floor.** A scan that stops matching passes by finding nothing, so
  `checks/static.sh` fails when a count drops below its floor.

**`docs/gotchas.md` is the catalogue.** Read the section for the area being
changed: Arch carryover, nixpkgs, desktop, waybar, power, editors,
theming, networking, secrets, scripts. It records what has already gone wrong,
including several theories that looked right and were not.

## Changing things

`rebuild` = `sudo nixos-rebuild switch --flake "$HOME/src/nix-config#thinkpad"`.

- **Gate first: `nix flake check`.** It builds the system *and* home closures, so
  a `buildEnv` collision surfaces there rather than halfway through a switch, and
  it runs statix, deadnix, shellcheck and `checks/static.sh`. An evaluate-only
  script catches neither failure; do not reintroduce one (`docs/adr/0010`).
- **`rebuild-test` for structural changes.** It applies without moving the boot
  default, so a mistake is one reboot from gone.
- **Except for `boot.kernelParams`, where `test` is wrong.** It writes no boot
  entry, so test-then-reboot lands back on the previous generation with the
  change reverted and nothing said. Use `switch` or `boot`. The tell is
  `/nix/var/nix/profiles/system` and `/run/current-system` pointing at different
  store paths.
- **Always quote a flake ref in zsh.** `EXTENDED_GLOB` makes `#` a pattern
  operator, so an unquoted `…#thinkpad` fails with `zsh: no matches found:`
  before `nixos-rebuild` runs, which looks like a broken path. Use `"$HOME/…"`;
  `~` does not expand inside double quotes.
- **Rebuild before reload.** Anything generated, and everything under
  `dotfiles/mango/` (a store path), needs a rebuild first. Reloading alone
  reloads what the last rebuild produced, which looks the same as the change
  having had no effect.

| Reload | How |
|---|---|
| zsh | new shell, or `source ~/.config/zsh/conf.d/<file>.zsh` |
| Mangowm | `~/.config/mango/scripts/reload.sh` — never under sudo |
| bar | `mango-reload`, which restarts the bar too, via the `exec=` line that `reload_config` re-fires. `scripts/waybar/waybar-restart.sh` is the bar alone (docs/adr/0051) |
| GTK theme | `~/.config/mango/scripts/system/gtk-apply.sh` |
| kitty | `kill -SIGUSR1 $KITTY_PID` |
| foot, zed, htop, imv, yazi | restart the app |
| ncspot | restart the app |
| nvim plugins | `:Lazy sync` |
| Equibop theme | rebuild (activation writes `enabledThemes`), then restart the app |

The bar's stylesheet is an exception: `reload_style_on_change` is on, so a
rebuild alone applies a CSS edit. The `.jsonc` still needs a restart.

**Two faces, by role.** 3270 Nerd Font is the bar's display face, at 13.5px and
bold — the size and the weight are one decision, because its regular goes thin
under 14px. Hack Nerd Font is body text: the rofi menus, wlogout, the terminal,
the editor and GTK. Symbols Nerd Font Mono leads the bar's stack, because 3270
patches icons in at its own narrow advance. `checks/static.sh` asserts all three.
"One font everywhere" is not the rule, and has been tried (`docs/adr/0059`).

Inputs are pinned by `flake.lock`. Re-lock deliberately with `nix flake update`,
never as a side effect of a build.

## Where configuration lives — three tiers

`~/.config/<app>` is produced by home-manager. **Edit under `dotfiles/`.**

| Tier | Mechanism | Use when | Declared in |
|---|---|---|---|
| 1 — generated | `programs.<app>` | a native module exists — **the default** | `modules/home/{programs,waybar,theme}.nix` |
| 2 — store-based | `source = ../../dotfiles/X` | no module, or generating would lose hand-tuned data | `modules/home/dotfiles.nix` |
| 3 — out-of-store | `mkOutOfStoreSymlink` | the app rewrites its own config from its GUI | `corectrl` only |

Tier 1 is worth its churn for three reasons: typos become build failures, one
option owns both the package and its config, and values can be shared between
consumers.

### One palette

`modules/home/palette.nix` re-exports whichever of `modules/home/themes/*.nix`
that `modules/home/scheme.nix` names. Switching schemes is that one string plus a
rebuild. Five ship: `heartbox`, `mocha`, `mocha-high-contrast`, `gruvbox`, `nord`
(`docs/adr/0030`).

It feeds swaylock, imv, nvim, swaync, the lock-background ramp, the bar's six
generated layouts, kitty, foot, rofi, ncspot, Equibop and mango.
The alternative is the same hex codes transcribed into four files with nothing
keeping them in step. A drifted palette looks like a deliberate choice, so it
gets a check rather than a convention: `checks/static.sh` asserts that every
generated colour is used and every reference resolves.

**Most of what the palette could not colour is generated from it**
(`docs/adr/0041`). `pkgs/default.nix` builds the GTK theme, the Kvantum theme and
the cursor set from the theme file's values; yazi's flavour and Zed's theme are
written from them. Only the **icon set** is still a name a program resolves
internally, along with nvim's. The bar draws individual names out
of that set — the window title's app icon, the minimized indicator, the battery
ladder — through `-gtk-icontheme()` in a generated `icons.css` (`docs/adr/0052`).

**rofi draws the same set, and does not read GTK's setting** (`docs/adr/0060`).
`rofi/icons.rasi` is generated with the name; without it rofi falls back to
Adwaita. Its window mode looks an icon up by the lowercase appid and never
consults a desktop file, so `modules/home/waybar.nix` aliases the appids the
theme has no name for into hicolor from the same `appIcons` map.

A theme file that names nothing buildable is still adoptable. `heartbox` is the
first: it exists as a colour scheme and nowhere else.

Those names are the half that fails silently — each falls back to its own default
and looks merely unstyled — so the check asserts that every one resolves and that
every generated artefact carries this palette's colours. `native = false` marks a
stand-in, reported on every run rather than left to be noticed; `heartbox`'s icon
set is the first.

Each theme declares its own `contrastFloor` and `ansiFloor`, measured rather than
chosen, and there is no global minimum under them. The assertion is only that a
theme is as legible as it claims, so it cannot fail a new scheme; it catches a
regression within one. Nord's comment colour is 1.69:1 and Heartbox's is 1.72:1.

### Where the colours land

kitty, foot and ncspot take theirs in `programs.<app>.settings`; rofi's
`colors.rasi`, mango's `universal/colors.conf` and Equibop's
`equibop/themes/palette.theme.css` are generated files. Equibop enables a theme
by filename from its own `settings.json`, which it rewrites, so a home-manager
activation step writes `enabledThemes` rather than an `xdg.configFile`.

### Not generated, deliberately

`nvim`, `mango`, `swaync`, `glow` and `nwg-look` stay hand-written, though all of
them now take their colours from the palette. The reasons are in
`docs/SYSTEM.md` §6 — read that before finishing the job. See `docs/adr/0009`.

### Two traps that destroy work

- **`recursive = true` writes through an existing out-of-store symlink, into the
  repo.** Converting `mango` this way replaced 65 tracked files with
  self-referential symlinks and broke the live config. Delete `~/.config/X`
  first, so home-manager builds a fresh directory. `nixos-rebuild test` makes it
  worse: it creates no profile generation, so the new store path has no GC root.
- **Two owners for one path is an activation failure, not a merge.** If anything
  writes a file at runtime, git must not track it and no `xdg.configFile` may
  claim it. Equibop's `settings.json` is the live case: an activation step
  edits it instead.

Two techniques to try before accepting a mutable directory: manage a *file*
rather than a directory (`xdg.configFile."Kvantum/kvantum.kvconfig".source`
leaves the parent writable), and check whether the module merges instead of
linking. `programs.zed-editor` merges Nix settings into the real writable
`settings.json`, so declarative does not have to mean read-only.

## Writing shell here

Shell is the layer that breaks here; most failures catalogued in this repo are
shell failures. shellcheck and `checks/static.sh` run under `nix flake check`
over git-tracked files only, so a new script is ungated until `git add`.
`dotfiles/zsh/conf.d/*.zsh` is ungated entirely — no shebang, and shellcheck does
not handle zsh. See `docs/adr/0011`.

- `#!/usr/bin/env bash` — there is no `/bin/bash`. The symptom is exit 127 and
  silence.
- `pkill -f 'bin/foo$'`, never `pkill -x foo`. nixpkgs wraps binaries, so `comm`
  is `.foo-wrapped`, truncated to 15 characters. Drop the `$` if the process
  takes arguments: `-f` matches the whole command line, so the anchor misses.
- **To test for a process, match `comm`: `pgrep '^\.?foo'`.** `-x` misses the
  wrapper as above, and `-f` matches the guard's own shell — the cmdline of
  `pgrep -f 'foo$' || foo` ends in `foo`, so the guard is always true and the
  daemon never starts. Bare-invoked processes (`mango`, `kdeconnectd`) carry no
  path in their cmdline either, so `bin/` anchors do not help.
- `mmsg` takes verbs (`get`, `dispatch`, `watch`). The dwl-era `-s -d` flags
  return an error object and exit 0.
- Runtime state is `${XDG_STATE_HOME:-$HOME/.local/state}/mango`. Every reader
  and writer must agree, or a toggle goes one-way with nothing logged.
- **Glyphs: literal UTF-8 in Nix, `$'\UXXXXXXXX'` escapes in shell.** Nix has no
  `\uXXXX` escape; shell has two forms, and `checks/static.sh` reads both, having
  once read only one and missed 39 glyphs from the wrong pack (`docs/adr/0057`).
  Verify with `jq -r` piped to a codepoint dump, never by eye.
- Run shellcheck as `nix shell nixpkgs#shellcheck -c …`. The
  `nix run … 2>/dev/null` form once swallowed all 24 findings and reported zero,
  which looks the same as a clean run.
- **Never run `dbus-update-activation-environment` or `systemctl --user
  import-environment` from a task shell.** Both overwrite the session's
  environment with the calling shell's. From inside this repo's devShell that
  injects `stdenv`, `IN_NIX_SHELL` and a scratchpad `XDG_CONFIG_HOME` into every
  user unit started afterwards, which left three applications reading and writing
  their config under `/tmp`. `docs/gotchas.md` → Session environment.

## This shell

zsh via `ZDOTDIR` (`dotfiles/zsh/conf.d/*.zsh`), with `EXTENDED_GLOB` on.
`cat`→`bat`, `ls`/`ll`/`la`→eza, `cd`→zoxide, `lf`→yazi, `zed`→`zeditor`.
**No package-manager alias** — packages go in `modules/home/packages.nix`,
followed by a rebuild. `$EDITOR` is `nvim`. Full inventory and keybinds:
`docs/SYSTEM.md` §7–8.

`ls` in `$HOME` with no arguments is a function that hides the clutter listed in
`_HOME_HIDE`; `ll` and `la` are the unfiltered escape hatches. That file opens
with `unalias ls l ll` because NixOS predefines those three, and an existing `ls`
alias makes `ls() { … }` a parse error that aborts the rest of the file, dropping
everything below it. Do not remove the `unalias`.

## Where to look

| When… | Read |
|---|---|
| asking what is in the repo, or why the tree is arranged this way | `docs/ANATOMY.md` — the flake, the lock, the file map |
| unsure how packages, profiles, wrappers or generated config work at all | `docs/NIX-PRIMER.md` — the mechanism under §6's tiers |
| about to change waybar, mango, the shell, editors, theming, secrets, or anything carried over from Arch | `docs/gotchas.md` — the failure catalogue, by area |
| chasing an app that lost its config, its login or its profile | `docs/gotchas.md` → Session environment, then Credentials and keyrings |
| asking how the machine is laid out, which keybind does what, or where a change belongs | `docs/SYSTEM.md` (§13 = known rough edges — check before reporting one as new) |
| about to undo something that looks redundant | `docs/adr/` — each record carries the failure that motivated it |
| changing the colour scheme, or any part of how the machine looks | `docs/THEME-MIGRATION.md` — the runbook; `docs/adr/0028` for why it splits in two, `docs/adr/0032` for what a theme file owns |
| hitting the GPU freeze, suspend drain or hibernation | `docs/gotchas.md` → Power, then `docs/SYSTEM.md` §9 |
| changing what a scheme reaches — cursor, Kvantum or GTK | `docs/adr/0041` |
| filing or triaging an issue | `docs/agents/issue-tracker.md`, `docs/agents/triage-labels.md` |

## Keeping this current

When a change alters what these files describe, update them in the same task,
unasked. Where this file and `docs/SYSTEM.md` disagree, this one wins — it is
kept current against failures.

Route new material by kind: a **decision** becomes an ADR, a **failure** goes in
`docs/gotchas.md`, the **file map** goes in `docs/ANATOMY.md`, and how to *use*
the machine goes in `docs/SYSTEM.md`. Keep none of it in a code comment. A
one-line reason plus a pointer is the target.

### Write it short

Documentation, comments and commit messages here are direct and concise. Say the
plain fact rather than the clever construction. The argument lives in one place —
the ADR or the gotchas entry — and everything else points at it. Writing it twice
creates two copies that drift.

- **Comments: a one-line reason plus a pointer.** `# <what and why>. docs/adr/00NN`
  A file past ~30% comment means text should move out. Never restate in a comment
  what the ADR beside it already argues. Every `docs/adr/NNNN` pointer is
  checked, so retire the citation with the record.
- **ADRs run ~100 lines.** Context, Decision, Consequences, and the failure that
  motivated it. Past 200 is worth trimming.
- **Prefer the assertion to the paragraph.** A check in `checks/static.sh` that
  fails when a fact stops being true is worth more than three sentences asking
  the reader to remember it, and it is shorter.
