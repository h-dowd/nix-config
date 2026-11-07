# System guide

An operator's manual for this machine: what the pieces are, where each one
lives, and how to change them.

This is the *orientation* document. Two others sit alongside it and answer
different questions:

| Document | Answers |
|---|---|
| **`docs/SYSTEM.md`** (this file) | How is the system laid out, and how do I use it? |
| `docs/NIX-PRIMER.md` | How do packages and configs work at all? The mechanism under §6 |
| `CLAUDE.md` | What has bitten us, and what must not be undone? |
| `docs/adr/` | Why is it built this way rather than the obvious way? |

If something here contradicts `CLAUDE.md`, `CLAUDE.md` is the one kept current
against failures — trust it and fix this file.

---

## 1. The machine

| | |
|---|---|
| Hardware | ThinkPad L14 Gen 5, AMD CPU + integrated AMD GPU |
| OS | NixOS unstable (`26.11`), kernel `linuxPackages_latest` |
| Hostname | `thinkpad` |
| User | `henry` |
| Disk | `nvme0n1` — 476 GB, btrfs |
| RAM | 14 GiB. zram (zstd, 50%, priority 5) is the working swap; a 20 GiB btrfs swapfile on `@swap` exists only to hold a **hibernation** image |
| Display | eDP-1, 1920×1200 |
| WiFi | Qualcomm QCNFA765 (`wlp1s0`, `ath11k_pci`) |
| Compositor | Mangowm (Wayland) — the only desktop |
| Login | greetd + tuigreet on TTY, launching `mango` |

Installed 2026-07-29, migrating from Arch. **Arch is gone** — subvolumes, boot
entry and EFI residue were all deleted on 2026-07-30. There is no dual boot and
no fallback to it.

### Filesystem layout

One btrfs filesystem, five subvolumes, plus the EFI partition:

| Mount | Subvolume | Notes |
|---|---|---|
| `/` | `@nixos` | The system. Rebuilt, never hand-edited |
| `/nix` | `@nix` | The store. Separate so GC churn doesn't touch `/` snapshots |
| `/home` | `@home` | **Carried across from Arch untouched.** Snapshotted by snapper |
| `/var/log` | `@log` | Kept out of root snapshots |
| `/swap` | `@swap` | The 20 GiB hibernation swapfile. **Mounted without compression** |
| `/boot` | — | vfat ESP, 1 GB, shared with the (now removed) Arch entry |

All btrfs mounts use `compress=zstd:3`, `noatime`, `discard=async` — **except
`@swap`**, which must not be compressed. btrfs refuses a compressed swapfile
and `swapon` reports `Invalid argument`, which looks like file corruption rather
than a wrong mount option. See §9.

**`@home` is the important one.** It survived the migration in place, which is
why the browser profile, credentials and pairings are all still there — and
also why a large amount of live data is in **no repository**. See §11.

---

## 2. The mental model

Three layers, and almost every question is "which layer does this belong to?"

```
  ┌─────────────────────────────────────────────────────────────┐
  │ 1. THE FLAKE           ~/src/nix-config                      │
  │    Declares the system: packages, services, kernel, users —  │
  │    and now most of the dotfiles too, as Nix expressions.     │
  │    Changing it does nothing until a rebuild runs.            │
  └───────────────┬─────────────────────────────────────────────┘
                  │  nixos-rebuild switch
                  ▼
  ┌─────────────────────────────────────────────────────────────┐
  │ 2. THE ACTIVATED SYSTEM   /run/current-system, /nix/store    │
  │    Read-only. /etc is generated. Home-manager GENERATES most │
  │    of ~/.config and links the rest in from the store.        │
  └───────────────┬─────────────────────────────────────────────┘
                  │  programs write at runtime
                  ▼
  ┌─────────────────────────────────────────────────────────────┐
  │ 3. RUNTIME STATE       ~/.local/state, ~/.local/share        │
  │    Waybar layout, wallpaper, credentials. Mutable,           │
  │    deliberately outside the config tree, in no repo.         │
  └─────────────────────────────────────────────────────────────┘
```

Two rules follow from this and explain most of the surprises:

1. **`/etc` is generated and read-only.** Editing `/etc/tlp.conf` or
   `/etc/systemd/...` either fails or is silently reverted on the next rebuild.
   Change the flake instead.
2. **State must never live in the config tree.** A program writing into its own
   config directory is what stops that directory from becoming a read-only store
   path. This is why `~/.local/state/mango/` exists; see `docs/adr/0003`.

---

## 3. Repository map

`docs/ANATOMY.md` §5 is the canonical map: every directory, every file, what it
holds and why. It also covers `flake.nix` output by output and `flake.lock`'s
input graph.

The short orientation:

```
~/src/nix-config/
├── flake.nix              inputs and the thinkpad configuration. At the root — ADR 0001
├── flake.lock             pinned inputs; only moves on `update`
├── hosts/thinkpad/        host identity and hardware-configuration.nix
├── modules/system/        11 files, one concern each, all imported by the host
├── modules/home/          home-manager: packages, shell, programs, bars, theme
├── pkgs/                  the overlay: local packages, overrides, theme artefacts
├── checks/static.sh       the static assertion suite
├── dotfiles/              the hand-written dotfiles that remain
├── secrets/               sops-encrypted, tracked
└── docs/                  this file, ANATOMY, NIX-PRIMER, gotchas, ADRs
```

**`dotfiles/` is shrinking by design.** Most configs are generated by
`modules/home/programs.nix` and have no file here at all: `dotfiles/kitty/`,
`dotfiles/foot/`, `dotfiles/zed/`, `dotfiles/htop/`, `dotfiles/ncspot/`,
`dotfiles/imv/` and `dotfiles/ghostty/` were deleted on 2026-08-01. A config
file that is not in `dotfiles/` is generated; grep `modules/home/`. See §6.

**Do not move `flake.nix` down a level.** With it at the root, `dotfiles/` is
inside the flake and reachable by relative path, which is the only reason
dotfiles can be store-based at all. See `docs/adr/0001`.

---

## 4. The change loop

Every change follows the same shape: **edit the repo → rebuild → reload.**

### Commands

All defined as zsh aliases in `modules/home/shell.nix`:

| Alias | Does | When |
|---|---|---|
| `rebuild` | `nixos-rebuild switch` | Normal changes |
| `rebuild-test` | `nixos-rebuild test` | **Anything structural.** Applies now but does not touch the boot default — a mistake is one reboot from gone |
| `rebuild-boot` | `nixos-rebuild boot` | Apply at next boot only |
| `update` | `nix flake update` | Deliberately move the pinned inputs |
| `generations` | `nixos-rebuild list-generations` | See what is available to roll back to |
| `gc` | `nix-collect-garbage --delete-older-than 30d` | Reclaim store space |
| `search` | `nix search nixpkgs` | Find a package name |
| `waybar-reload` | Restart waybar from the current state | Wraps `scripts/waybar/waybar-restart.sh` |
| `mango-reload` | Dispatch `reload_config` — which re-fires the `exec=` lines, so **the bar restarts with it** | After a `rebuild` that touched keybinds, rules, autostart or the bar |

The mango scripts are not on `$PATH` — `~/.scripts` is, `~/.config/mango/scripts`
is not, and putting it there would drop 31 files with names like `lib.sh` into
command completion. The two that get typed by hand are aliased instead.

⚠️ Neither reload alias picks up repo edits on its own. `~/.config/mango` is a
store path, so **`rebuild` first, reload second** — running only the reload
restarts the bar against the config it already had, which looks the same as the
change having no effect.

**Always quote a hand-typed flake ref.** zsh runs with
`EXTENDED_GLOB`, which makes `#` a pattern operator, so an unquoted
`~/src/nix-config#thinkpad` is parsed as a glob, matches nothing, and dies with
`zsh: no matches found:` before `nixos-rebuild` runs, which looks like a broken
path. The aliases already quote it.

### Rolling back

Generations are numbered and every `switch` makes one:

```
generations                      # list them
sudo nixos-rebuild switch --rollback   # previous generation
```

Or pick a specific one from the systemd-boot menu at boot. Currently ~20
generations exist, all from 2026-07-29 onward.

⚠️ **`rebuild-test` does not create a generation.** It activates without a GC
root, so a later `gc` can delete exactly the store path the running system is
using. Use `test` to try things; follow with `switch` once satisfied.

### Reloading, per component

Rebuilding is not always enough — most desktop pieces need a nudge:

| Changed | Apply with |
|---|---|
| Anything under `dotfiles/mango/` | `rebuild`, **then** `mango-reload` |
| The bar (`modules/home/waybar.nix`, `dotfiles/mango/waybar/style-solid.css`) | `rebuild`, then `mango-reload` (which restarts it) or `scripts/waybar/waybar-restart.sh` for the bar alone |
| kitty | `rebuild`, then `kill -SIGUSR1 $KITTY_PID` or Ctrl+Shift+F5 |
| foot | `rebuild`, then restart the terminal — no live reload |
| zed, htop, imv, yazi | `rebuild`, then restart the app |
| ncspot | `rebuild`, then restart the app |
| wlogout | `rebuild` only — it is spawned fresh on each invocation |
| zsh config | `source ~/.config/zsh/conf.d/<file>.zsh`, or a new shell |
| Neovim plugins | `:Lazy sync` |
| GTK theme | `~/.config/mango/scripts/system/gtk-apply.sh` |
| `autostart.conf` | **Log out and back in** — `exec_once` only fires at compositor startup |

⚠️ **Almost nothing is live-editable any more.**
`dotfiles/mango/` became a store path on 2026-07-30, and on 2026-08-01 the nine
programs above stopped having a file in this repo at all — they are generated
from Nix. So "edit the dotfile and reload" no longer works in either case:
there is nothing to edit for the generated ones, and the store copy of the
others does not change until the next rebuild. **Reloading without rebuilding
first looks the same as the change having had no effect.**

`corectrl` is the only entry where an edit is still live without a rebuild.

**Never `sudo` the mango scripts.** Under sudo `~` is `/root`, so they fail with
what looks like a broken install, and write root-owned files into a config tree
they should not touch. `reload.sh` refuses to run as root.

---

## 5. Where do I change X?

The routing table. Find the row, edit the file, apply as in §4.

### System

| Want to change | Edit |
|---|---|
| Install/remove a package | `modules/home/packages.nix` (user) or `modules/system/*.nix` (`environment.systemPackages`). **Not** for the nine in `programs.nix` — their module installs the package too |
| A systemd service | `modules/system/<concern>.nix` — **never** `/etc/systemd/` |
| Kernel or boot params | `modules/system/boot.nix` |
| Battery charge thresholds | `modules/system/power.nix` (`services.tlp`) — see §9. The bar shows the raw percentage and does **not** rescale to the stop threshold; `checks/static.sh` asserts no `full-at` |
| Hibernation, lid and power key | `modules/system/power.nix` (`services.logind`) — no `systemd.sleep`, there is no suspend phase to configure |
| When the machine dims, locks or idle-sleeps | `modules/home/default.nix` (`services.swayidle.timeouts`) |
| What a dying battery does | `modules/system/power.nix` (`services.upower`) — not logind |
| Timezone, keymap, keyd | `modules/system/locale.nix` |
| Firewall ports | `modules/system/networking.nix` |
| Fonts | `modules/system/fonts.nix` |
| Printer / scanner | `modules/system/printing.nix` |
| VMs, containers, Steam | `modules/system/virtualisation.nix` |

### User environment

| Want to change | Edit |
|---|---|
| Shell aliases | `dotfiles/zsh/conf.d/10-aliases.zsh` |
| Shell options | `dotfiles/zsh/conf.d/00-options.zsh` |
| `$PATH`, `$EDITOR` | `modules/home/shell.nix` |
| Default applications | `modules/home/default.nix` (`xdg.mimeApps`) — there is no `mimeapps.list` in this repo |
| Which scheme the machine wears | `modules/home/scheme.nix` — one string naming a file in `modules/home/themes/`. Change it and rebuild; `docs/adr/0030`. Currently `heartbox` |
| Any colour | `modules/home/palette.nix` — a dispatcher over `modules/home/themes/*.nix`, evaluating to one flat attrset. Feeds swaylock, imv, nvim, swaync, the lock-background ramp, the bar's `colors.css`, kitty, foot, rofi, ncspot, Equibop and mango |
| Which schemes exist | `modules/home/themes/`. Five ship: `heartbox`, `mocha`, `mocha-high-contrast`, `gruvbox`, `nord`. All native but `heartbox`'s icon set, which is the repo's one stand-in (`native = false`) and is reported on every run. The selected scheme is contrast-audited by `checks/static.sh` against its own declared floors |
| The GTK / Qt / cursor theme | Generated from the selected theme file's colours by `pkgs/default.nix` — `paletteGtk`, `paletteKvantum`, `paletteCursors` (`docs/adr/0041`). yazi's flavour and Zed's theme are written the same way. Only the **icon set** is still a name in the `packages` block |
| nvim's colourscheme, Zed's theme | the theme file's `apps` block |
| kitty, foot, zed, htop, yazi, ncspot, imv, wlogout | `modules/home/programs.nix` — generated, no file to edit |
| GTK/Qt theme, icons, cursor | `modules/home/theme.nix` |
| Which hand-written dotfiles get linked | `modules/home/dotfiles.nix` |
| Language servers | `modules/home/packages.nix` — nvim takes them from `$PATH` |

### Desktop

| Want to change | Edit |
|---|---|
| Keybinds | `dotfiles/mango/universal/bind.conf` or `bind-shared.conf` |
| Window rules | `dotfiles/mango/universal/rule.conf` |
| Per-workspace layout | `dotfiles/mango/universal/tag.conf` |
| Startup programs | `dotfiles/mango/universal/autostart.conf` |
| Bar modules | `modules/home/waybar.nix` — **generated**, six configs |
| Waybar appearance | `dotfiles/mango/waybar/style-*.css` — hand-written rules. Its `colors.css` (from `palette.nix`) and `icons.css` (icon-theme names, ADR 0052) are **generated**; do not add either to `dotfiles/` |
| rofi appearance | `dotfiles/rofi/config.rasi` — hand-written layout, shared by **every** menu. Its `lines: 12` is a **fixed height** and only the cap for `rofi -show drun\|run\|window\|calc\|emoji`; hand-built menus size themselves through `lib.sh`'s `rofi_menu <max>` (`-theme-str`, since `-l` loses to the theme — `docs/gotchas.md` → rofi). Its `colors.rasi` is generated by `dotfiles.nix` |
| Session menu | `modules/home/programs.nix` (`programs.wlogout`); `dotfiles/wlogout/` holds only the six PNGs. **Adding an entry means bumping `-b` in `custom/power`'s click in `waybar.nix` too** |
| When the screen locks | `modules/home/default.nix` (`services.swayidle`) |
| Launcher entries | The launcher is `rofi -show drun` (`docs/adr/0043`) and its entries are the `.desktop` files in the profiles — nothing to declare; menu contents are in the `scripts/menus/*.sh` that build them |
| rofi's look or modes | `dotfiles/rofi/config.rasi` |
| how tall a menu is | `lib.sh`'s `rofi_menu <max>`, at the call site — **not** `config.rasi`, and never `-l` |
| Wallpaper | `~/.local/share/mango/wallpaper.png` — **not** in the repo |

---

## 6. How configuration reaches `~/.config`

**There are three tiers, not two.** The 2026-08-01 pass moved most of the repo
into the first one, so a lot of what used to be a "dotfile" is now a Nix
expression with no file behind it. The tiers, best first:

### Tier 1 — generated, by a native home-manager module

`modules/home/programs.nix` and `modules/home/waybar.nix`. Nix produces the
file from typed options; **there is no config file in this repo at all.**

| What | Module |
|---|---|
| kitty, foot | `programs.kitty`, `programs.foot` — colours from `palette.nix`, in `settings` |
| zed | `programs.zed-editor` |
| htop, imv, yazi | `programs.htop`, `programs.imv`, `programs.yazi` |
| ncspot | `programs.ncspot` — the theme from `palette.nix`'s `muted` set, in `settings.theme` |
| wlogout | `programs.wlogout` |
| swaylock | `programs.swaylock` — **`package = null`**, see §9 |
| The three waybar layouts (x2 positions = 6 files) | `modules/home/waybar.nix` — generated; `universal/autostart.conf` starts the bar (ADR 0051) |

This is where a config should end up unless there is a reason it cannot. The
argument is not tidiness:

- **Typos become build failures.** The recurring failure here is config that is
  wrong in a way *nothing reports* — the dead `mmsg -s -d` flags, empty
  `custom/*` modules, `appid:zen` matching nothing, six silently missing
  language servers. Typed options are the only mechanism here that turns that
  class of mistake into an error that cannot be missed. `waybar.nix` goes further and
  asserts on a module name with no definition.
- **One owner for the package and its config.** `programs.kitty.enable`
  installs the package *and* writes the config, so removing it removes both.
  Previously `kitty` was in `packages.nix` while `kitty/` was in
  `dotfiles.nix`, with nothing tying them together.
- **Values can be shared.** The palette is one file
  (`modules/home/palette.nix`, selecting from `modules/home/themes/`) instead of sixteen hex codes transcribed into
  four with nothing keeping them in step — the terminals, the bar's
  `colors.css` and rofi's `colors.rasi` all derive from it, and
  `checks/static.sh` asserts every generated name is used and every reference
  resolves. `icons.css` is the same shape one layer out: the icon *names* the
  bar draws are declared once and checked against the built theme, because a
  name that resolves to nothing draws nothing (ADR 0052).

### Tier 2 — store-based, `source = ../../dotfiles/X`

The file stays hand-written but lands read-only in the store. Reproducible;
`~/.config/X` stops depending on this checkout existing. Changes need a
rebuild.

Currently: `mango` (with `recursive = true`), `nvim`, `swaync` (body only), `glow`,
`zsh/conf.d`, and `~/.scripts` — plus the file-level entries `Kvantum`,
`nwg-look`, `rofi/config.rasi` and the `gtk-3.0`/`gtk-4.0` assets.

> **`rofi/config.rasi` is declared as a FILE, not a directory.** rofi writes a
> cache and `rofi.png` next to it, so linking the parent would give one path two
> owners. It is also the only thing connecting rofi to this repo — nothing in
> the mango tree names it, and rofi with no config falls back to its built-in
> theme rather than erroring. Same shape as `elephant/menus.toml` before it: until
> 2026-08-09 it was hand-written and in no repo. See ADR 0014.

> **File-level is a variant of this tier, not a separate one.**
> `xdg.configFile."X/config".source` pins the *file* read-only while leaving
> the *directory* writable for sibling runtime files — home-manager links a
> directory-valued source as one symlink, but a file-valued one as a real
> directory containing a file symlink. `htop`, `ncspot` and `zed` used to need
> this; their native modules now do exactly the same thing internally, so it
> became upstream's problem. What is left is `Kvantum`, `nwg-look` and the GTK
> asset directories, plus `rofi/config.rasi`.

`mango` and `nvim` reached this tier by **moving the writer** rather than
accepting a mutable directory — nvim's `lazy-lock.json` moved to
`stdpath("state")`, and mango's runtime state to `~/.local/state/mango/`. That
is the general technique.

### Tier 3 — out-of-store, `mkOutOfStoreSymlink`

A live symlink into this checkout: edits take effect with no rebuild, but a
fresh clone gets a symlink pointing at nothing.

Currently **`corectrl` only** — it writes its own `.ini` and profiles from its
GUI, and that GUI is the entire point of the tool. This is what an honest
out-of-store entry looks like: not "not converted yet", but "converting it
would remove functionality".

### Assets — a fourth thing that is not a tier

`dotfiles/wlogout/` still exists but contains **no config**. It holds data a
*generated* config points at: wlogout's six PNGs. `programs.nix` references it
by relative path, so it ends up in the store as its own path. Don't mistake this
for an unconverted config.

`dotfiles/yazi/` was the same shape until the Catppuccin migration and is now
gone. It was fetched from a third-party repo for a while; since `docs/adr/0041`
it is **written from the palette** by `pkgs/yazi-flavor.nix`, because a flavour
is 220 lines of colour and nothing else. That is the preferred end state for
this category: generate it if it is only colour, fetch it if it is not, and
vendor it only if neither works.

Two more files left `dotfiles/` for the same reason in `docs/adr/0032`, each
because it held a scheme's **name**: `Kvantum/kvantum.kvconfig` and
`nvim/lua/plugins/colorscheme.lua`.
A name is not a colour, so none of them showed up in a search for hex — which is
exactly how the Equibop theme stayed gruvbox through a whole migration.

`mango/universal/cursor.conf` joined them on 2026-08-18, for the fourth time the
same way: `universal/settings.conf` named the cursor theme by hand and kept
Catppuccin's through two scheme changes. It is now generated from
`config.home.pointerCursor` and `source=`d by `settings.conf`, alongside its
`colors.conf` sibling — so mango, GTK and `~/.icons/default` cannot disagree.
`docs/gotchas.md` → Theming has why it was invisible.

### What is deliberately not generated

Do not "finish the job" without reading these:

| Config | Why it stays a file |
|---|---|
| `nvim` | ~22 files of lazy.nvim config. `programs.neovim` with Nix-managed plugins is a *rewrite*, trading `:Lazy sync` for a rebuild per plugin bump. The store path already gives reproducibility. **Three files inside it ARE generated** and merged in the store — `lua/plugins/colorscheme.lua`, `lua/config/scheme.lua` and (conditionally) `lua/config/palette.lua`, because the colourscheme follows `scheme.nix` (`docs/adr/0032`) |
| `mango` | No module exists. `recursive = true` so the generated files (`colors.conf`, `cursor.conf`, the waybar configs) can live inside the hand-written tree |
| `swaync` | `services.swaync` exists and works, but declares the unit that is deliberately **masked**. `autostart.conf` owns swaync's lifecycle so restyles apply on reload. Adopting the module flips that ownership and needs its own decision. **Never run both** |
| waybar CSS | Same reasoning — hand-tuned presentation is data |
| `glow`, `nwg-look` | No module at this pin |
| `corectrl` | Writes its own config from the GUI, and that GUI is the program |

### Four traps

⚠️ **Two owners on one path is an activation failure, not a merge.** This is
the one to internalise, because it is how every conversion goes wrong. A
config must be generated *or* linked, never both — moving an entry into
`programs.nix` means deleting it from `dotfiles.nix` **and** deleting the file
from `dotfiles/` in the same change. `waybar.nix` writes into `~/.config/mango/`,
which the recursive `mango` link also owns, and that only works because the
four `.jsonc` files were deleted from `dotfiles/mango/waybar/`. `walker/config.toml`
broke `rebuild` outright this way: tracked in git *and* written as a symlink by
every autostart file. It is gone with walker, and its record was retired with it; the shape is not.

⚠️ **"Declarative" and "writable" are not actually in tension.** That was an
artefact of only having symlinks. `programs.zed-editor` runs an activation
script that **merges** the Nix-declared settings into the real, writable
`settings.json` with `jq -n '$dynamic * $static'` — Zed keeps persisting its
own state, and the declared keys win on every rebuild. Before assuming a config
must be read-only to be declarative, check whether its module merges instead of
links.

⚠️ **`recursive = true` can destroy the repo.** It creates files *inside*
`~/.config/X` rather than one symlink. If `~/.config/X` is already an
out-of-store symlink into the checkout, those writes follow it in — converting
`mango` this way replaced 65 tracked files with self-referential symlinks.
Delete `~/.config/X` first so home-manager builds a fresh directory.

⚠️ **The link source must be outside `~/.config`**, because
`xdg.configFile.<name>` writes *to* `~/.config/<name>`. That is why this repo
lives at `~/src/nix-config` and not at `~/.config` as it did under Arch.

---

## 7. The desktop

### Mangowm

A Wayland compositor in the dwl/dwm lineage: tags (workspaces), keyboard-driven.
Every tag is a dwindle tree with manual splits, as on the desktop; `⌥,` cycles to
monocle. Config lives in `dotfiles/mango/`: `config.conf`, which
mango reads, `source=`s everything under `universal/` — binds, window rules,
tags, settings, autostart — and the generated `universal/colors.conf` and
`cursor.conf`. One look: no animations, no gaps, square corners, a 1px border.
There is no desktop-mode switch (`docs/adr/0061`).

### Bar layouts

Two independent switches, both on the `/` key:

| | Options | Bind | State file |
|---|---|---|---|
| **Waybar layout** | `full`, `focus`, `minimal` | `⌥/` or `⌘,` | `~/.local/state/mango/bar-layout` |
| **Waybar position** | `top`, `bottom` | `⌥⇧/` | `~/.local/state/mango/bar-position` |

Layout selects which waybar modules are shown. Position moves the bar between
screen edges. There is one stylesheet, `style-solid.css`.

Waybar configs are generated as the **full layout × position matrix**:
`config-<layout>-<position>.jsonc`, 3 × 2 = 6 files. `waybar-restart.sh` only
builds a filename from the two state values; nothing is rewritten at runtime.

Layout opens a rofi picker; position is a **straight toggle**, since with two
options a menu costs more keystrokes than the thing it selects.
`waybar-position.sh` also accepts an explicit `top`/`bottom` argument for
scripting.

Both are read by **`scripts/waybar/waybar-restart.sh`**, which is the only place
that knows how they combine — so login, layout switch, position toggle and
`reload_config` all land on the same result.

**The state paths and their defaults live in `scripts/lib.sh`**, sourced by
every script that touches them. Each one used to re-derive
`${XDG_STATE_HOME:-$HOME/.local/state}/mango` and its own fallback value, which
is exactly how the old mode switch broke one-way on 2026-07-31 — one reader
disagreed with the writers about the path, silently.

> **How position actually works:** waybar takes only `-c`, `-s` and `-b` on the
> command line — `position` is a config key with no flag. So each position is a
> **separate generated file**, and the script picks between them.
>
> `atBottom` in `waybar.nix` only flips `position` now. It also MIRRORED the
> vertical margins until that change, which mattered for exactly one layout:
> hud used `"margin-bottom": -28` against a 28px bar to cancel its exclusive
> zone. Restore the mirroring before adding a layout with a vertical margin.
>
> Styling follows automatically — waybar adds its position as a CSS class on the
> window, so `window#waybar.bottom` in `style-solid.css` moves the separator
> line to the top edge.

> All three layouts show the battery relative to the TLP charge limit, so a
> battery parked at the 85% stop threshold reads 100%. The limit is read from
> `services.tlp.settings.STOP_CHARGE_THRESH_BAT0`, not copied. The rescale
> happens before `states` is compared, so `warning = 30` is a real 25.5%.

### Keybinds

The desktop's scheme (`henry/dotfiles`), in Mac names. mango binds what a
remapper sends, not the physical key (`docs/adr/0062`):

| Mac | Physical key | mango |
|---|---|---|
| ⌥ Option — desktop level | Super | `ALT` |
| ⌘ Cmd — window and system level | Alt | `SUPER+CTRL+ALT`, the "⌘ chord"; ⌘Tab is `SUPER+CTRL` |
| ⌃ Control | Ctrl | `CTRL`; ⌃⌘ is the chord + `SHIFT` |

keyd does the remapping (`modules/system/locale.nix`). ⌘ is Ctrl for apps, so
⌘C copies; in kitty and foot, `keyd-application-mapper` turns ⌘C, ⌘V and their
other shortcuts into Ctrl+Shift (`~/.config/keyd/app.conf`, generated in
`modules/home/default.nix`). ⌃ stays Ctrl, so ⌃C interrupts. Caps is Esc tapped
and the nav layer held; Right Alt is the typst layer.

**Cmd level**

| Key | Action |
|---|---|
| `⌘Space` | Launcher — `rofi -show drun` |
| `⌘Tab` / `⌘⇧Tab` | Window switcher with thumbnails; selects when ⌘ is released |
| `⌘Q` / `⌥⌘Esc` | Close window / force-kill it |
| `⌘,` | Waybar layout picker |
| `⌘⇧V` | Clipboard history |
| `⌘⇧3` / `⌘⇧4` | Full screen to clipboard / region screenshot |
| `⌃⌘Q` | Lock screen |
| `⌘⌫` | Delete to line start. Terminals get Ctrl+U, which zsh binds to `backward-kill-line` |
| `⌘←` / `⌘→` | Line start / end (Home/End from keyd); with `⇧`, select to there. The shell line has no selection, so in zsh `⇧` just moves |
| `⌃⌘\` / `⌃⌘Backspace` | Notification history / clear all — swaync's own panel. `swaync-client` against an unstarted daemon exits 0 (`docs/adr/0047`) |

**Tree, focus and layout**

| Key | Action |
|---|---|
| `⌥V` / `⌥⇧V` | Next window goes right / below |
| `⌃⌥V` | Flip the current container's split |
| `⌥H/J/K/L` | Focus left/down/up/right |
| `⌥⇧H/J/K/L` | Move the window beside its neighbour in that direction |
| `` ⌥` `` | Last focused window |
| `⌥,` | Dwindle ↔ monocle |
| `⌥A` / `⌥F` / `⌥⇧F` | Maximise / fullscreen / fake fullscreen |
| `⌥⇧Space` | Toggle floating |
| `⌥O` | Keep above everything (overlay) |
| `⌥G` | Toggle global (sticky) |
| `⌥I` / `⌥⇧I` | Minimise / restore the last one on this tag |
| `⌃⌥I` | Pick which minimised window comes back (ADR 0052). Same menu as clicking the bar's minimised count |
| `⌥R` | Resize mode: `H/J/K/L` by 50px, with `⇧` by 200px; `Esc`, `Return` or `⌥R` leaves |
| `⌥⇧R` | Reload mango config |
| `⌥Q` | Close window |
| `⌃⌥⇧M` | Quit the compositor |
| `⌥⇧X` / `⌥⇧Z` | More / fewer gaps |
| `⌥` + drag / right-drag / middle-click | Move / resize / maximise |

**Workspaces (tags)**

| Key | Action |
|---|---|
| `⌥1…9` | Go to tag |
| `⌥⇧1…9` | Move window to tag and follow |
| `⌃⌥⇧1…9` | Move window to tag and stay |
| `⌥Tab` | Back to the previous tag |
| `⌥⇧Tab` | Overview |
| `⌃⌥H` / `⌃⌥L` | Previous / next tag |
| `⌥⌘H` / `⌥⌘L` | Move window to previous / next tag |
| `⌃⌥,` / `⌃⌥.` | Focus monitor left / right; with `⇧`, move the window there |
| `⌥Z` | Scratchpad |
| `⌥[` / `⌥]` | Spotify / Equibop scratchpad. Bound by keycode, so `⌥8`/`⌥9` keep their tags (`docs/gotchas.md` → Desktop) |

**Apps and menus**

| Key | Action |
|---|---|
| `⌥Return` / `⌥⇧Return` | kitty / foot |
| `⌥B` | Zen browser |
| `⌥E` | Thunar |
| `⌥⇧E` | Open a file — `rofi -show recursivebrowser`, recursive from `$HOME` |
| `⌥P` | Bitwarden (`rofi-rbw`) |
| `⌥Space` | Apps **and** open windows in one list (`rofi -show combi`, `combi-modes: drun,window`) |
| `⌥W` | Window picker (`rofi -show window`) |
| `⌥=` | Calculator (`rofi -show calc`, result to the clipboard) |
| `⌥;` | Emoji picker |
| `⌥F1` | rofi's own keybindings (`rofi -show keys`); mango's are in `dotfiles/mango/universal/bind*.conf` |

Most of these go through `scripts/menus/shell.sh`, the one action table the
binds call; `checks/static.sh` asserts every row is bound and every bound action
is a row.

**Panels and system**

| Key | Action |
|---|---|
| `⌥C` | Control centre — thirteen rows in one list (network, bluetooth, VPN, volume, microphone, night light, keep awake, power profile, phone, weather, do-not-disturb, notifications, bar), each showing the state it is actually in. It is a **reader**: nothing in it changes anything itself, and five rows take their icon and their state from the waybar module that owns the fact (`docs/adr/0033`, `docs/adr/0038`). Weather is the one row with two verbs, and they are two keys: **Enter** opens the forecast and closes the panel, **Ctrl+Enter** refetches and stays (`docs/adr/0044`). On any other row Ctrl+Enter just re-renders |
| bar button, every layout | The same control centre — `custom/control-center` in `waybar.nix`, `on-click` running `shell.sh control-center` |
| `⌥D` | Calendar |
| `⌃⌥N` / `⌃⌥B` / `⌃⌥T` | Network / Bluetooth / VPN |
| `⌃⌥W` | Weather panel. **Enter** opens the forecast page, **Ctrl+Enter** refetches and redraws (`docs/adr/0050`) |
| `⌥Esc` | Power menu |
| `⌥/` | Waybar layout picker (also `⌘,`) |
| `⌥⇧/` | Waybar top/bottom |
| `⌥⇧N` | Do not disturb — `swaync-client -d -sw` |
| `⌥⇧A` | Keep awake — `wlinhibit.service` holds a Wayland idle inhibitor, the only thing that stops swayidle's ladder from inside the session (§9, `docs/adr/0031`). The bar glyph follows within 2 s; the key raises no notification, so that poll **is** the feedback |
| `⌥⇧P` | Cycle TLP power profile. Not ACPI: `platform_profile` is a placebo here (§9, `docs/adr/0017`) |
| `Print` / `CTRL+Print` | Region screenshot / full screen to clipboard |
| Media & brightness keys | Volume, playback, backlight (via wpctl / playerctl / brightnessctl). `⌥` + scroll is volume, `⌃⌥` + scroll is backlight |
| `XF86AudioMicMute` | Mic mute. Its state is on the bar (waybar's `pulseaudio`) and in the control centre; the ThinkPad LED is no longer the only place it shows |
| 3-finger swipe | Left/right focus, up overview, down float. 4-finger left/right changes tag |
| Power button | Tap hibernates, hold powers off — logind, not a mango bind (§9) |

### Waybar

Status bar. **The layouts are generated by `modules/home/waybar.nix`** — there
are no `config*.jsonc` files in this repo; the six
`config-<layout>-<position>.jsonc` are written into `~/.config/mango/waybar/`
alongside the hand-written CSS, which stays a file. Each module is defined once
and a layout is a list of names, so a name with no definition is an **eval
error** rather than an empty module. Per-layout divergences live in a `tweaks`
attribute at the call site.

**A layout side is a list of GROUPS, and group order is the same in all three.**
The first module of each group after the first is emitted as `name#sep`, which
waybar renders with the style class `sep` and the sheet's one `.sep` rule draws
the separator — so grouping is declared beside the order rather than inferred
from fifteen module-keyed borders in the CSS. A layout may drop a module but
never reposition one, so `⌥/` moves nothing two layouts share;
`checks/static.sh` asserts that, the `.sep` rule's existence, and that no
module-keyed border comes back. `docs/adr/0042`.

Right-hand groups, in order: notification · cpu memory · network vpn bluetooth
phone · pulseaudio backlight night-mode · idle-inhibitor power-profile battery ·
control-center tray · power. On the left: clock weather · workspaces ·
mpris minimized. The centre is the focused window's title.

> There is one stylesheet, `style-solid.css`. Check `waybar-restart.sh` can
> actually reach a file before adding another.

> The sheet asks for `"Symbols Nerd Font Mono", "3270 Nerd Font", monospace` in
> its `*` rule, in that order, at **13.5px and bold**. `checks/static.sh`
> asserts the stack and the size/weight pair. Symbols first puts each icon's ink
> inside its own cell; 3270 second is the bar's typeface, and its regular goes
> thin under 14px, so the size and the weight are one decision.
>
> 3270 is the bar's alone. The rofi menus, wlogout, the terminal, the editor and
> GTK are Hack — two faces by role, asserted, after a pass that briefly made
> everything Hack. `docs/adr/0059`, `docs/gotchas.md` → Waybar.

Notable custom modules — each is a script under `dotfiles/mango/scripts/`, so if one
is missing from the bar, **run its script by hand first**:

| Module | Script | Refresh signal |
|---|---|---|
| `custom/window` | `waybar/window-title.sh` | streams `mmsg watch focusing-client` |
| `custom/power-profile` | `system/power-profile.sh` | `RTMIN+11` |
| `custom/night-mode` | `menus/night-mode.sh` | `RTMIN+9` |
| `custom/phone` | `kdeconnect/phone-status.sh` | 30 s |
| `custom/weather` | `system/weather.sh` | `RTMIN+13`, plus a 300 s poll (`full` and `focus`). Left opens the panel, middle refetches, right opens the forecast page |
| `custom/minimized` | `waybar/minimized.sh` | streams `mmsg watch all-clients`. Left opens the picker |
| `mpris` | native | Left focuses the window that is playing, via `media/media-focus.sh` |
| `clock` | native | Left opens `menus/calendar.sh`, right toggles the date, scroll pages the tooltip calendar |

> **`phone-status.sh` takes verbs: `status` (the default, so waybar's argument-less
> `exec` still works) and `ring`.** The KDE Connect device id is written **once**,
> in that script — the bar's `on-click` and the control centre's row both call
> `… ring` rather than spelling `kdeconnect-cli -d <id> --ring` again. `ring`
> `notify-send`s when the phone is unreachable instead of failing silently.

> **`weather.sh` takes four verbs and only two may touch the network:**
> `status` (the bar — fetches when the 900 s cache has expired), `read` (the
> control-centre row — cache only, never a socket, because that menu renders in
> parallel and costs its slowest row), `refresh` (fetches past the cache, then
> raises `RTMIN+13` so the bar moves too) and `open` (hands
> `local.location.forecastUrl` to `xdg-open` — no network of its own, and it
> renders nothing). Coordinates come from `local.location` in
> `modules/home/options.nix` via the generated
> `mango/universal/weather-location.env`; the cache is `$STATE_DIR/weather.json`.
> A reading served from a failed fetch is `class` `stale`, greyed, with its age
> in the tooltip. **`minimal` carries no weather module**, so nothing keeps the
> cache warm there and the control-centre row is normally `stale` until Refresh —
> `docs/adr/0038`.

> **`menus/calendar.sh` is the calendar**, on the clock's left click and on
> `⌥D`. A month grid with ISO week numbers, today bold and
> underlined, the current week preselected. `Ctrl+Enter` and `Shift+Enter` page
> the month; `Enter` returns to today, then closes. It replaced `{calendar}` in
> the clock's tooltip, which could not be navigated or kept open. The grid is
> built in the script rather than read out of `cal -w`, so the cell that is
> today is known rather than found by counting columns. `docs/adr/0058`.

> **`media/media-focus.sh` is the media module's left click.** It resolves the
> active player's bus name to a pid over D-Bus, matches that against the pid
> mango reports per client, and focuses the window — or toggles the pad, if the
> client is a named scratchpad, which is what Spotify is. Matching on pid rather
> than on name is deliberate: zen-beta publishes
> `org.mpris.MediaPlayer2.firefox`, so a name table would need a row per browser
> and would go stale silently. It was `scratch-toggle.sh Spotify spotify` — one
> player, hardcoded, on a module that shows whichever is active.
> `docs/adr/0058`.

> **On the bar the three buttons are: left opens the panel, middle refetches,
> right opens the forecast page.** The panel is `weather.sh panel` —
> rofi, reading the cache this script already keeps, so there is one fetch of
> open-meteo rather than two (`docs/adr/0050`). waybar's `on-click` ran
> `refresh` until 2026-08-26 — a fetch whose only output is a two-digit label.

> **The panel is a `-mesg` header over a forecast list.** The header is the
> current reading — temperature at `xx-large`, place and condition, then today's
> range, humidity, UV, wind, pressure trend and sun times. The list is eight
> hourly rows at two-hour steps and then four daily ones, in one column layout so
> they read as a single table. Every row does the same thing on Enter, so nothing
> in it is inert.

> **One fetch carries the whole tooltip** — 19 fields, `forecast_days=5`. Now,
> feels-like, today's range and rain chance, humidity, UV with its WHO band,
> wind with the compass point it blows from, pressure with a trend over about
> three hours, sunrise/sunset with the day's length, then four hourly steps and
> the next four days. Eight hourly picks are computed at two-hour steps for the
> panel; the tooltip takes every other one. The trend is the one fact a single
> response cannot carry, so the cache also keeps six hours of pressure samples
> and claims nothing when they are too close together. `checks/static.sh`
> asserts the query and the tooltip name the same fields, in both directions —
> `docs/adr/0044`.
| `custom/power` | — opens wlogout | — |

> **`pulseaudio` is one module showing two devices.** `{format_source}` in its
> `format` — and repeated in `format-muted`, which replaces `format` rather than
> adding to it — is the microphone; `format-source` / `format-source-muted` are
> its two glyphs, and **both are non-empty on purpose**, because an indicator
> that vanishes in one state is indistinguishable from a broken one. No script,
> no `custom/microphone`: PipeWire owns the fact and the bar and the control
> centre are both readers of it (`docs/gotchas.md` → Waybar, `docs/adr/0033`).

> **Do not reintroduce waybar's built-in `dwl/window` module.** mango 0.15.5
> dropped the dwl IPC protocol it binds to, and its absence makes waybar
> segfault at startup. `custom/window` exists for this reason.

### The rest of the stack

| Piece | Role |
|---|---|
| **rofi** | The launcher (`⌘Space`, `-show drun` — `docs/adr/0043`) and every structured menu — bluetooth, clipboard, volume, network, VPN, the layout picker — plus `calc` and `emoji` as plugin modes. No daemon. Config *and* layout in `dotfiles/rofi/config.rasi`; colours in the generated `colors.rasi`. Grepping for `rofi` also substring-matches `power-profile` |
| **rofi-rbw** | Bitwarden (`⌥P`). Not a rofi plugin — a front-end over `rbw` |
| **swaync** | The notification daemon (`docs/adr/0051`), started by `universal/autostart.conf`. Its unit stays masked so that autostart owns the lifecycle — which also means `swaync-client` only works while swaync itself holds `org.erikreider.swaync.cc`. See `docs/gotchas.md` → Waybar |
| **awww** | Wallpaper daemon (the swww fork; the binary is `awww`) |
| **wlsunset** | Night light, owned by a systemd user unit |
| **wlogout** | Session menu behind the waybar power icon — lock, logout, suspend, hibernate, reboot, shutdown |
| **swaylock** | Screen lock (`swaylock-effects`). Needs the hand-declared PAM service in `desktop.nix`; configured by `programs.swaylock` (§9) |
| **lockscreen** | The wrapper every lock path actually calls — picks a background from the pool and execs swaylock (§9, `docs/adr/0018`) |
| **swayidle** | Lock handler *and* idle daemon — `lockscreen` on `before-sleep`/`lock-session`, plus the dim → lock+blank → suspend ladder (§9) |
| **poweralertd** | Low-battery notifications into whichever shell holds `org.freedesktop.Notifications`. `-S` keeps it to power supplies, so headphones don't alert (§9) |
| **KDE Connect** | Phone integration; `kdeconnectd` from autostart |

---

## 8. Shell, terminals, editors

**zsh is the login shell.** Configured from `~/.config/zsh/conf.d/*.zsh` via
`ZDOTDIR`; `programs.zsh` in `modules/home/shell.nix` owns `~/.zshrc`, the
plugins and history, and sources `conf.d/*.zsh` at the end — so `conf.d`
deliberately wins over home-manager's defaults. **Fish is gone.**

Aliases worth knowing: `cat`→`bat`, `ls`/`ll`/`la`→`eza`, `lf`→`yazi`,
`zed`→`zeditor`, `z` for zoxide jumping. In `~` only, bare `ls` hides a fixed
list of clutter directories; `ll`/`la` are the unfiltered escape hatches.

**Terminals:** kitty (`⌥Return`), foot (`⌥⇧Return`), ghostty. All on the selected scheme,
Hack Nerd Font Mono 11 — kitty additionally takes bold and italic from
0xProto Nerd Font Mono (bold-italic stays Hack; 0xProto ships none).
`checks/static.sh` asserts every family named here actually resolves.

⚠️ **kitty and foot are generated** by `programs.kitty` / `programs.foot`, from
the **single palette** in `modules/home/palette.nix` — kitty takes `#rrggbb`,
foot takes bare hex, both from the same attrset, which also feeds the bar and
rofi. There is no `dotfiles/kitty/` or `dotfiles/foot/` in this repo. Change a
colour there, once, and it lands everywhere on the next rebuild.
ghostty has no config at all: `dotfiles/ghostty/config.ghostty` was a zero-byte
file and was deleted rather than converted; the package runs on its defaults,
exactly as it already did.

There is no `active-theme` indirection any more, and it is now *impossible* to
reintroduce as it stood — there is no directory for a mode script to write a
theme into.

**Editors:** Neovim is `$EDITOR`/`$VISUAL`, so it is what git, `sudoedit`,
`systemctl edit`, lazygit and yazi all open. It is a hand-rolled lazy.nvim
config (~18 plugins), and the one large config still hand-written — see
`dotfiles/nvim/README.md`. It is now the only editor this repo configures:
**helix was removed 2026-08-17** (`docs/adr/0027`). Zed is generated too, but by
a module that *merges* into a writable `settings.json` rather than linking it.

⚠️ **nvim ships no language servers.** There is no mason; it takes servers from
`$PATH`, so every server must be declared in `modules/home/packages.nix`. A
missing server is skipped in **silence** — audit with the `command -v` loop in
`docs/gotchas.md` → Editors, or `:checkhealth lsp`, and read the *output*. See
`docs/adr/0007`.

---

## 9. Hardware behaviour

Three things look like faults and are not.

### Power modes

Three TLP profiles. `⌥⇧P` and a left-click on the waybar
leaf/bolt/adjust glyph toggle **balanced ↔ performance** — the two everyday
modes. **Fanless is right-click only**, and left-clicking out of it lands in
balanced. It is kept off the left-click path deliberately: a 1.1 GHz cap with
the iGPU pinned to 200 MHz is too large a penalty to reach by clicking one time
too many.

Right-click returns to whatever the current supply implies — performance on
mains, balanced on battery. It names that explicitly because
`TLP_AUTO_SWITCH=2` holds fanless across a charger change by design, so nothing
reverts it on its own.

| Profile | TLP | Governor / EPP | Max freq | Boost | iGPU | ABM |
|---|---|---|---|---|---|---|
| performance | `_ON_AC` | performance / performance | 4.63 GHz | on | auto | 0 |
| balanced | `_ON_BAT` | powersave / power | 4.63 GHz | **off** | auto | 1 |
| fanless | `_ON_SAV` | powersave / power | **1.12 GHz** | off | **low** | 3 |

`fanless` is TLP's `power-saver` (`SAV`). `TLP_AUTO_SWITCH=2` keeps it across a
charger transition, so it holds on mains — that is deliberate, and the tooltip
says so rather than looking like a bug.

⚠️ **"Fanless" is aspirational under sustained all-core load, and measurably
so.** Two `fan-calibrate` runs put the EC trip at ~47–48 °C against an idle
plateau of 40–46 °C depending on ambient; twelve threads cross that even at
418 MHz, the hardware minimum. There is no cap that makes sustained load
silent on this chassis, so the mode targets **bursty** desktop use, where it is
genuinely quiet.

The cap is therefore `lowest_nonlinear` (1115770) — the highest clock still at
minimum core voltage, i.e. the best perf-per-watt point. Efficiency is the
objective only because the thermal one proved unreachable; a lower cap buys
silence it cannot deliver and costs real speed. Details in `docs/adr/0017`.

> The everyday win is **balanced**, not fanless. With boost off and the 2.9 GHz
> base ceiling it idles fan-free at ~40 °C, where the old low-power mode ran at
> 2340 rpm. That is what fixed the original complaint.

> `platform_profile` moves with the profile but is not what does the work — it
> is a firmware hint and is identical across all three for everything the
> scheduler reads. Don't diagnose from it.

ABM 3 visibly shifts panel contrast; that is the mode working, not a display
fault. The iGPU pin costs compositor smoothness — 200 MHz against a 1899 MHz top
state — and is the first thing to relax if fanless feels sluggish.

#### The same three profiles over D-Bus

`power-profiles-tlp` owns `org.freedesktop.UPower.PowerProfiles` and answers it
from TLP, so clients written against power-profiles-daemon drive these three
profiles rather than finding no service. Reads come from `/run/tlp/last_pwr`,
writes go through `power-mode`, and a switch TLP makes on its own — a charger
transition — is pushed out as `PropertiesChanged`. `docs/adr/0026`.

```
busctl get-property org.freedesktop.UPower.PowerProfiles \
  /org/freedesktop/UPower/PowerProfiles \
  org.freedesktop.UPower.PowerProfiles ActiveProfile
```

Its consumers are `powerprofilesctl` and GNOME's power page.

Two things it deliberately does not do. **Profile holds are declined** with a
`NotSupported` error rather than recorded and ignored, so no application can pin
a profile behind the caller. And **it refuses to start** when TLP reports no profile,
rather than publishing a guess; `BindsTo=tlp.service` means a stopped TLP takes
the bus name with it. Both failures land in `systemctl status
power-profiles-tlp`.

### Battery stops below 100%

TLP sets EC thresholds **START 75 / STOP 85** (`modules/system/power.nix`,
confirmed against live sysfs). On AC the battery parks wherever it is and only
tops up below 75%. `status` then reads `Not charging`, which waybar renders as
a **plug** icon rather than a lightning bolt. A plug with a static sub-100%
reading is the hysteresis working.

Raising STOP does not trigger a charge — the EC only starts below START. To
force one: `sudo tlp setcharge 84 85 BAT0`.

> `upower -i` reports `charge-start-threshold: 75%` regardless of the real
> value. Trust `/sys/class/power_supply/BAT0/charge_control_*_threshold`.

> The bar shows the **raw** percentage. `full-at`, which rescaled it so the 85%
> stop read as 100%, was removed on 2026-08-09 — it made the bar disagree with
> `upower` and sysfs by a constant factor, and that masked two reports of the
> module freezing. `checks/static.sh` asserts no generated config carries it.
> Consequence: on AC the bar parks at 85% and never reads 100%.

### Suspend and s0i3

The firmware exposes only **s2idle** (`/sys/power/mem_sleep` → `[s2idle]`), not
S3 — so `mem_sleep_default=deep` would achieve nothing. Under s2idle the SoC
only reaches its low-power state (**s0i3**) once every IP block reports idle.

**A lit panel during suspend is a battery bug, not a cosmetic one.** The
DISPLAY block tracks the display *pipe*, so a screen left on holds s0i3 off
entirely and the machine idles at **~4.1 W** through what looks like sleep.
That is how the laptop was found flat after a night closed on the desk.

Fixed with `powerManagement.powerDownCommands`/`resumeCommands` in `power.nix`,
running **`wlopm --off '*'`** / `--on` through the shared `setDisplayPower`
helper. The resume hook is the load-bearing half: an output left in its off
power-mode is not restored by input, so dropping it wakes the machine to a
black screen no keypress fixes. `wlopm` needs the Wayland socket, so it cannot
run as root directly — the helper loops over `/run/user/*/wayland-[0-9]` and
`runuser`s to the owning user.

⚠️ **The backlight cannot do this job.** `brightnessctl` and `bl_power` only
drive PWM; the DISPLAY block tracks the CRTC. Hooks written that way succeed,
exit 0, and leave the panel lit and the battery draining.

**Result: fixed.** A 9h37m lid-closed suspend on battery cost **4 percentage
points** (58% → 54% of a 42.4 Wh cell) — about **0.15 W**, which is s0i3. That
retracts the earlier reading here: blanking the display was measured as taking
suspend from 4.10 W only to ~3.03 W, with `last_hw_sleep` still 0, and this
section concluded s0i3 was unreachable for unknown reasons. It is reachable.
The short instrumented measurements were the unreliable part, not the fix — a
long sleep measured by battery percentage either side is the honest test, and
the only one that matched what the machine actually does overnight.

Hibernation on the lid stays regardless: it is there for the resume hang and the
spurious wake (§below), not for the drain.

**The same pre-sleep hook also un-throttles.** After `setDisplayPower "off"`,
`powerDownCommands` enables `cpufreq/boost`, writes each policy's
`cpuinfo_max_freq` into its `scaling_max_freq`, and returns the iGPU to DPM
`auto` — so nothing throttled enters a sleep. The reason is hibernation's entry
phase: it preallocates ~5.8 GiB and compresses into zram *before* it can
snapshot, measured at 7 s at full clock against 22 s capped, and a lid reopened
inside that window hung the machine outright (`docs/gotchas.md` → Power).
Order matters — with boost off the driver clamps `cpuinfo_max_freq` to the
2901000 nominal, so boost must be lifted before the ceiling is read. There is no
restore half: `tlp suspend` touches only AHCI and PCIe ASPM, and `tlp resume`
reapplies the AC/BAT profile on the way back. It runs for suspend too, where the
entry phase is too short to matter, because one hook on `sleep.target` beats a
second unit that has to tell the two apart.

> If suspend drain is ever suspected again, read
> `/sys/kernel/debug/amd_pmc/smu_fw_info` **first** — it names the offending IP
> block directly, in one command.

### Idle

Until 2026-08-11 nothing acted on idleness at all: swayidle carried **no
timeouts**, so with the lid open the machine never dimmed, never locked and
never slept — 6.9 W until the 3% hibernate, roughly six hours, with the desktop
unlocked the whole time. That gap dwarfed every other power setting on this
machine.

The ladder now, all in `services.swayidle`:

| Idle | What happens | Undone by |
|---|---|---|
| 4 min | `brightnessctl -s set 10%` — dim, as the warning | `brightnessctl -r` on activity |
| 5 min | `lockscreen -f`, then `wlopm --off '*'` | `wlopm --on '*'` on activity |
| 30 min | `idle-suspend` — suspends only on battery, and only if no MPRIS player reports `Playing` | any input, instantly |

Three things make it safe rather than annoying:

- mango advertises `zwp_idle_inhibit_manager_v1`, so mpv and Firefox suppress
  the whole ladder during playback. Check with `wayland-info | grep inhibit`
  before assuming that of any compositor.
- The lock/blank step is joined with `;`, **not `&&`** — see `docs/gotchas.md`.
- `idle-suspend` is a `writeShellApplication`, so it is shellchecked at build
  time rather than being an inline string nothing gates.

On AC the ladder stops after the blank: locked, dark, and still up.

Playback is handled at two different levels, deliberately:

- **Video** needs nothing from us. mpv and Firefox hold a `zwp_idle_inhibit`
  surface while playing, which stops the ladder before the first rung — no dim,
  no lock, no sleep.
- **Audio-only** (ncspot, Spotify, a music tab) usually takes no inhibitor, so
  the ladder runs. That is wanted for the first two rungs — dimming and locking
  over an album is correct — but not for the last, so `idle-suspend` alone
  checks `playerctl --all-players status` and bails on `Playing`. `Paused` and
  `Stopped` sleep.

⚠️ **`systemd-inhibit --what=idle` does not hold any of this off.** swayidle
takes its idle signal from `ext_idle_notifier_v1`, i.e. from the compositor, and
mango does not bridge logind's inhibitors into it. So an unattended long build on
battery still hits the 30-minute suspend — it resumes where it left off, but
network connections will not. Same for anything playing audio without an MPRIS
interface: a game, a call in an app that publishes none.

#### Holding the ladder off — keep awake

**`⌥⇧A`, or click the bar's `custom/idle-inhibitor`** (`full` and
`focus` layouts, between night mode and the power profile). 󰒲 means the ladder
is live; 󰒳 in yellow means nothing dims, locks or sleeps, and closing the lid
does nothing.

Both run `scripts/system/idle-inhibit.sh toggle`, which starts or stops
**`wlinhibit.service`**. That unit holds a `zwp_idle_inhibit_manager_v1`
inhibitor — the mechanism mpv and Firefox use, the one mango feeds into
`wlr_idle_notifier_v1_set_inhibited`, and the only one that reaches swayidle at
all. **No timeout, ever**: an inhibitor that silently expires part-way through is
the failure it exists to prevent.

The same unit wraps wlinhibit in `systemd-inhibit --what=handle-lid-switch
--mode=block`, so a closed lid neither hibernates nor locks while it is held.
Check with `systemd-inhibit --list | grep lid`.

The unit is the state. It survives `waybar-reload`, both bar switches, a switch
to `minimal` (which does not carry the module) and a `mango-reload`; it ends
with the session and not before. Nothing starts it at login.

This used to be waybar's built-in `idle_inhibitor`, whose state was a bool in
the bar process — clickable and nothing else, and released by every one of those
events without a word. docs/adr/0031.

⚠️ **Red 󰒳 means the unit FAILED and the ladder is live.** The state lives
outside the bar now, so the bar reports rather than holds: `systemctl --user
status wlinhibit`.

`systemctl --user stop swayidle` (and `start` after) remains the bigger hammer:
it stops the ladder rather than inhibiting it.

### Locking

`services.swayidle` in `modules/home/default.nix` runs `lockscreen -f` on
`before-sleep`, on `lock`, and on the 5-minute idle timeout above. Before it
existed, swaylock was reachable only by hand (`SUPER+Delete`, `SUPER+SHIFT+s`,
the wlogout button) and **every lid-close resumed straight to the unlocked
desktop**.

swayidle rather than another `powerManagement` hook, for two reasons:

- It holds a **logind sleep inhibitor** — `-w` makes it wait for `lockscreen -f`
  to fork, and swaylock forks only once the lock surface is up. So the lock is
  guaranteed present before the suspend, not racing it.
- A root sleep hook runs inside `sleep-actions.service`, whose cgroup is
  **killed when the unit stops on resume** — taking the swaylock it just
  started with it. That leaves the compositor locked with no client, which
  `ext-session-lock-v1` makes unrecoverable (§13).

Ordering falls out of this: swayidle's inhibitor puts the lock up first, then
`sleep-actions` powers the panel down.

`lock`/`unlock` mean `loginctl lock-session` works too.

#### What it looks like, and why

`programs.swaylock` generates `~/.config/swaylock/config`, which **every lock
path reads** — all of them run `lockscreen -f`, which execs swaylock and passes
no `--config`.

`clock` + `indicator` are the point of it: a swaylock screen with nothing drawn
on it is indistinguishable from a machine that is off or hung, so the lock now
shows a **ticking clock inside a permanently visible indicator ring**. The clock
is the proof of life; the ring is where typing lands. `indicator-idle-visible`
keeps the ring up rather than fading it out.

Both options are **swaylock-effects extensions**, which is why the module sets
`package = null` — see the trap in `docs/gotchas.md`.

This replaced three separate copies of the same theme: two per-mode
`swaylock.conf` files, and an **untracked** hand-written
`~/.config/swaylock/config` that had been quietly supplying the theme to every
bare `swaylock -f` all along. The per-mode files are deleted; there is one lock
screen.

#### The background

The flat `#282828` was the same failure the clock fixes — nothing drawn is
nothing to distinguish from a dead machine. It is now a **blocky neutral
texture, with a different pattern on every lock** (`docs/adr/0018`).

| | |
|---|---|
| `pkgs/lock-backgrounds` | 24 PNGs at native 1920×1200, fixed seeds. 160×150px blocks, nine neutral shades of `#282828`, no block matching any neighbour |
| `pkgs/lockscreen` | picks one with `$RANDOM`, execs `swaylock -i`. Empty pool falls back to the solid `color` |
| `programs.swaylock` | sets `scaling = "fill"`; deliberately sets **no** `image` — the wrapper supplies it per lock |

**Every lock path calls `lockscreen`, not `swaylock`** — swayidle's
`before-sleep`/`lock` and its idle timeout, wlogout, `power-menu.sh`, and the
`⌃⌘Q` bind. It is not named `swaylock` because that
would shadow swaylock-effects in PATH, the same trap `package = null` exists
for. `checks/static.sh` asserts swayidle reaches it and that its pool is
non-empty — an empty pool is invisible, since the fallback is the old flat
colour.

Why a pool rather than generating per lock: swayidle's `before-sleep` hook
blocks suspend until it exits, so a PNG encode there risks a late or missing
lock for a difference nobody can see.

### Hibernation

A closed lid **hibernates**, on both power sources. There is no suspend phase
and no `HibernateDelaySec`, so a short lid-close costs a ~6 GiB write and a
~10–30 s resume rather than returning instantly.

**Docked is the exception and stays `ignore`**, so clamshell work on an external
display keeps running. Closing the lid docked therefore leaves the session awake
*and unlocked* — accepted, because the alternative locks the session out of the
external screen in use.

**Undocking with the lid still shut hibernates, and so locks.** This is logind's
own behaviour, not something configured here: a lid close installs an
`sd_event_add_post` handler that re-runs the lid decision after every event-loop
iteration for as long as the lid stays closed (`button_recheck`,
`logind-button.c`). Losing the display drops `manager_is_docked_or_external_displays()`
to false, so the re-check falls through to `HandleLidSwitch`/`…ExternalPower` —
hibernate — and that goes via `PrepareForSleep`, so swayidle's `before-sleep`
locks first. Verified against systemd 261; the repo's own `HoldoffTimeoutSec`
observation in `docs/adr/0015` is the same re-check seen after a resume.

Two edges of that mechanism worth knowing:

- The re-check passes `is_edge = false`, and `manager_handle_action` **returns
  early for `HANDLE_LOCK` when `!is_edge`**. So `lock` is an edge-only action:
  as a docked lid value it would fire once on close and never re-fire. Sleep
  actions have no such guard, which is why the undock path works.
- `HoldoffTimeoutSec` (30 s) suppresses lid handling right after startup or
  resume — deliberately, to let USB docks settle before their displays are
  counted. An undock inside that window waits it out.

**So does a tap on the power key**, with a long press left as `poweroff`. The
systemd defaults are the other way round — a brushed button ended the session
with no prompt, and holding it did nothing — which is the one power-management
default on this machine that could lose work.

Three routes into hibernation, then: the lid, the power key, and upower at 3%
(below). The 30-minute idle rung used to be a fourth and **suspends** now —
`docs/adr/0016` has why the lid evidence does not transfer to it, and why
upower's 3% action is what makes an unattended idle suspend safe.

That instant resume is what `suspend-then-hibernate` bought, and it was tried
twice — first with AC on a plain `suspend`, then with s-t-h on both sources. Both
lost the same way: a spurious wake ends the s-t-h cycle, and logind's lid
re-check ~30 s later degrades to a plain `suspend` with no hibernate timer
behind it, leaving the machine in the long s2idle its resume hangs from. Removing
the suspend phase removes the wake that starts it. `docs/gotchas.md` → Power has
the journal signature.

The image goes to the 20 GiB swapfile on `@swap` (§1). **zram remains the
working swap** at priority 5 against the file's −1, so ordinary swapping never
touches the disk — the file exists only to hold an image zram cannot, being
itself in the RAM being saved.

**A dying battery hibernates too**, via upower rather than logind:
`criticalPowerAction = "Hibernate"` at `percentageAction = 3`. NixOS defaults to
`HybridSleep`, which writes the image and then *stays in s2idle* — the session
survives, but the machine is still drawing at the one moment it must not. The
~3 W once measured for that state came from the same short-measurement batch as
the retracted s0i3 figure and should not be quoted; the argument does not need
it, since any suspend at 3% is the wrong state to be in.

3% is one point above upower's default, not a safety cushion: 1% is 0.42 Wh
here, worth ~60 s at the ~25 W a hibernate write draws, against a write that
takes ~30 s. The extra point covers the poll interval at this battery's 38 W
recorded peak. **The gauge is accurate this low** — it has logged 1% repeatedly,
so there is no firmware cliff to stay clear of, and a larger margin only costs
runtime.

⚠️ **`percentageLow`/`Critical`/`Action` must stay strictly descending** (20 >
5 > 3). Out of order or otherwise invalid, upower discards all three and uses
its own defaults — the action still fires, just at a charge nobody chose, and
nothing logs. Read back `/etc/UPower/UPower.conf`, not the Nix.

⚠️ **`resume_offset` is the fragile part, and getting it wrong fails silently.**
Both `boot.resumeDevice` and `boot.kernelParams = [ "resume_offset=…" ]` are
required: one names the filesystem, the other locates the image inside it. Get
it wrong and the machine simply boots fresh and discards the session, which
presents as "hibernate didn't work" rather than "resume was misconfigured". The
number is valid only for the exact file that exists now — recreating, resizing,
defragmenting or `balance`-ing it moves the image. Re-derive with:

```
sudo btrfs inspect-internal map-swapfile -r /swap/swapfile
```

⚠️ **A rebuild is not enough; this needs a REBOOT.** `resume=` is a kernel command
line parameter, so `rebuild` writes the new logind and sleep config while the
*running* kernel has neither. `systemctl hibernate` then snapshots memory,
prepares S4 and returns **without writing an image or powering off** — and
because the screen blanks and comes back, it looks like a fast, successful
hibernate. It is not. This is dangerous while half-applied, because the lid
handler goes live at rebuild time: closing the lid then attempts the failed
hibernate, thaws, and leaves the machine awake with the lid shut, draining
*faster* than plain suspend. **Reboot promptly after the rebuild.**

⚠️ **The kernel log does not say whether a hibernate succeeded.** The memory
image is snapshotted *before* the write and power-off, so a successful and a
refused attempt leave byte-identical traces. Do not conclude from
`Waking up from system sleep state S4` that anything worked, and in particular
do not set `HibernateMode=shutdown` on that misreading — that was tried and
reverted. What actually distinguishes them:

| Check | Meaning |
|---|---|
| Machine physically powers off; firmware screen on the way back | It really hibernated. **This is the primary signal** |
| `journalctl --list-boots` — boot ID unchanged across the cycle | Resume worked, session restored |
| A new boot ID | Image written but resume failed — session discarded |
| No power-off, journal continuous | Aborted. Check `grep -o 'resume[^ ]*' /proc/cmdline` shows **both** parameters |

> **RTC trap:** `rtc0` here is `acpi-tad` and has no `wakealarm`, so `rtcwake`
> fails with `not enabled for wakeup events` and looks like broken firmware.
> The alarm actually comes from **`rtc1` (`rtc_cmos`)**. Don't point anything
> at `rtc0` to "fix" it.

### WiFi dies after resume

The `ath11k_pci` driver does not cleanly reinitialise on resume; NM retries but
DHCP times out. Two independent layers fix it, and both are needed:

- **TLP** disables WiFi power saving on AC and battery — covers normal runtime
- **`systemd.services.wifi-resume`** cycles the radio 3 s after wake — this is
  what actually fixes the resume failure

Both are declarative (`networking.nix`, `power.nix`). If it recurs, check
`journalctl -u NetworkManager` for a DHCP timeout after wake.

### VPN — autoconnect is off, deliberately

Nine profiles (`homelab` WireGuard + 8 PIA OpenVPN exits) all came off the
backup with `autoconnect=yes`. **All nine were turned off. Do not turn them back
on.** `homelab` auto-activated, claimed the default route, and pushed DNS
`192.168.1.5` onto every link — so away from the home LAN, *all* name
resolution failed. Nothing identifies itself as a VPN problem at that point; it
presents as total DNS death.

Bring it up by hand when away from home: `nmcli connection up homelab`. On
`192.168.1.0/24` the Gitea host (`192.168.1.200`) is reachable directly and the
tunnel is not involved.

---

## 10. Services inventory

What is running, and who owns it.

**System units (declared in `modules/system/`)**

| Service | Purpose |
|---|---|
| `greetd` + tuigreet | Login, launches mango |
| `fprintd` | Fingerprint (Synaptics `06cb:00f9`). Enabling it turns `fprintAuth` on for **every** pam service; `swaylock` and `login` are switched back off — see `docs/gotchas.md` → swaylock |
| `NetworkManager` | Networking (**not** networkd) |
| `systemd-resolved` | DNS |
| `avahi` | mDNS, for CUPS printer discovery |
| `tlp` | Power tuning + battery thresholds |
| `power-profiles-tlp` | Owns `org.freedesktop.UPower.PowerProfiles` and answers it from TLP, so PPD clients see the three profiles (§9, `docs/adr/0026`). `BindsTo=tlp.service` |
| `thermald`, `fwupd`, `upower` | Thermals, firmware updates, battery reporting + the critical-battery hibernate (§9) |
| `pipewire` (+ pulse/jack) | Audio. PulseAudio proper is off |
| `cups` + `sane` | Brother MFC-L3740CDW, driverless IPP |
| `bluetooth` + blueman | Bluetooth |
| `udisks2`, `gvfs`, `tumbler` | Removable media, thumbnails |
| `snapper` | `/home` timeline snapshots — 5 hourly, 7 daily, 4 weekly, 2 monthly |
| `wifi-resume` | The resume fix above |
| `tor` | Client mode, enabled in `networking.nix` |
| `podman`, `libvirtd` | Containers and VMs |
| `keyd` | ⌥/⌘ positions, Caps nav/Esc, typst layer, for every keyboard (`docs/adr/0062`). Socket group `keyd`, for the mapper |

**User units**

| Unit | Purpose |
|---|---|
| `polkit-gnome-authentication-agent-1` | Polkit prompts (the `lxpolkit` autostart line is a dead Arch leftover) |
| `wlsunset` | Night light — reads its temperature from `~/.local/state/mango/night-temp`. `Restart=always` |
| `micmute-led` | Syncs the mic-mute LED with PipeWire. **The only place `pactl` exists** — it comes from this unit's `path`, not `systemPackages`. No longer the sole mic indicator: waybar's `pulseaudio` carries `{format_source}` since 2026-08-19, so this unit failing is now visible rather than silent (`docs/gotchas.md` → Waybar) |
| `nextcloud-client` | Cloud sync — credentials in gnome-keyring's `Default` collection, config at `~/.config/Nextcloud/`. If it asks for a login, check the unit's `XDG_CONFIG_HOME` before anything else (`docs/gotchas.md` → Session environment) |
| `cliphist` (+ `cliphist-images`) | Clipboard history behind `⌘⇧V` — read by rofi |
| `keyd-application-mapper` | Applies `~/.config/keyd/app.conf` per focused app: terminals take ⌘C/⌘V on Ctrl+Shift. Restarted by a rebuild that changes the file. `-v` logs each focused appid to its journal |
| `mango-session.target` | A marker other units can hang off; started from `autostart.conf` |
| `swaync.service` | **Masked** — autostart owns swaync instead |

`~/.config/systemd/user/` now contains **only** home-manager symlinks into the
store. Keep it that way: it overrides `/etc/systemd/user/`, so any hand-written
file there silently shadows the unit the flake generates.

⚠️ **One owner per daemon.** nixpkgs packages ship user units that Arch's did
not, and they auto-start. swaync raced its own autostart line for a week
before anyone noticed. When adding a package with a daemon, check
`ls $(nix eval --raw nixpkgs#foo)/share/systemd/user/` before assuming
autostart is the only owner. See `docs/adr/0005`.

⚠️ **`Restart=` without `StartLimitBurst=` is a loaded gun.** A misconfigured
rclone unit retried every 5 s until Proton returned an account-level abuse
restriction — the damage landed on the account, not the machine. Any unit that
talks to a remote API needs a start limit. See `docs/adr/0006`.

---

## 11. What is *not* in this repo

The flake reproduces the system. It does **not** reproduce the data. These
live only on `@home` or in root-owned system directories, survived the
migration by luck of the shared subvolume, and need separate backup:

| What | Where | Size |
|---|---|---|
| Zen browser profile | `~/.config/zen/` | **912 MB** — 13 extensions, logins, history. Growing |
| NetworkManager profiles | `/etc/NetworkManager/system-connections` | the ~29 ordinary APs, root-only, mode 600. The nine credential-bearing ones are declared — ADR 0013 |
| Bluetooth pairings | `/var/lib/bluetooth` | 7 devices |
| Wallpaper | `~/.local/share/mango/wallpaper.png` | 4.6 MB |
| Runtime state | `~/.local/state/mango/` | mode, layout, night-temp, last-vpn |
| **age private key** | `/var/lib/sops-nix/key.txt` | **189 bytes, in no repo — losing it makes `secrets/secrets.yaml` unreadable** |
| CLI credentials | `~/.config/{gh,glab-cli,gpu-screen-recorder,opencode,rclone,rbw,tea}` | gitignored by name |
| corectrl profiles | `~/.config/corectrl/` | written by its GUI |

Snapper covers `/home` against accidental deletion, but snapshots are on the
same disk — they are not a backup.

**Secrets moved into sops-nix on 2026-08-06** (ADR 0012). `secrets/secrets.yaml`
is encrypted and tracked; the PIA credentials, the `homelab` WireGuard key and
the `gh`/`glab`/`tea` tokens all live there. Edit with
`nix develop -c sops secrets/secrets.yaml` **from the repo root**.

⚠️ What replaced that gap is a smaller, sharper one: **the age key at
`/var/lib/sops-nix/key.txt` is a single point of failure in no backup.** Keep a
copy in Bitwarden and on the offline drive.

**The nine credential-bearing NetworkManager profiles moved into the flake on
2026-08-09** (ADR 0013) — `homelab` plus the eight PIA exits, with credentials
substituted from a sops template at activation. The ~29 ordinary access points
stay in NetworkManager's own state, which is a decision rather than a TODO:
`ensureProfiles` deletes nothing, so declaring a subset is supported.

> **Zen note:** there are two profiles in `~/.config/zen/` and only one is real
> (`kxsz4wom.Default (release)`, 839 MB). Which is default is selected
> per-installation by executable path, and that path became a store path at the
> migration — so Zen fell back to the legacy `Default=1` flag, which sat on the
> empty profile. Fixed by moving `Default=1` onto `[Profile0]`. **Do not "fix"
> it by adding an `[Install<hash>]` entry** — the store path changes on every
> Zen update, which would orphan the setting again.

---

## 12. Troubleshooting

Nearly every problem on this system fails **silently**. The catalogue:

| Symptom | Likely cause | Check |
|---|---|---|
| A waybar module is missing from the bar | Its script exited 127, or emitted an empty `text` | Run the script by hand. An empty custom module is indistinguishable from an absent one |
| `bad interpreter`, exit 127 | `#!/bin/bash` — **there is no `/bin/bash`**, `/bin` holds only `sh` | Use `#!/usr/bin/env bash` |
| A mango script "succeeds" but does nothing | Old dwl-era `mmsg -s -d` flags. `mmsg` takes verbs (`get`, `dispatch`, `watch`) and returns `{"error":...}` **with exit 0** | `mmsg dispatch <func>`, and check the output |
| Icons render as empty boxes | The font lacks that codepoint, or a CSS `url()` failed — GTK draws its missing-image box **without logging** | `fc-list ':charset=XXXX' family` |
| An icon is off-centre in its cell | Container wider than its content, filled from one end — glyph advance vs ink, or `min-width` vs `icon-size` | Compare the two numbers |
| Duplicate/leaked daemon processes | `pkill -x` against a nixpkgs wrapper — `comm` is `.kdeconnectd-wr` (truncated at 15 chars), not `kdeconnectd` | `pkill -f 'bin/kdeconnectd$'` |
| A user unit misbehaves in an Arch-like way | `~/.config/systemd/user/` shadows `/etc/systemd/user/` | Now clean — contains only home-manager symlinks. Keep it that way |
| Lock screen rejects the correct password | Missing `/etc/pam.d/swaylock` → PAM falls through to `other` = deny | `pam_warn(swaylock:auth)` in the journal. Declared in `desktop.nix` |
| Session blank after killing swaylock | `ext-session-lock-v1` **requires** the compositor to stay locked if the client dies. Not a bug | Relaunch swaylock on the same `WAYLAND_DISPLAY` and authenticate, or reboot |
| Total DNS failure | A VPN holding `Default Route: yes` and pushing an unreachable nameserver | `resolvectl status` |
| Rebuild aborts on a file conflict | Two packages owning the same path in `buildEnv` | `lib.hiPrio` on the **winner** — `lowPrio` on the loser silently does nothing when priorities are equal |
| A `/usr/share/...` path doesn't exist | `share/<pkgname>` is not in `environment.pathsToLink` | Vendor the asset and reference it relatively |

**General method:** run the failing thing by hand, in an ordinary shell, and look
at both its output *and* its exit code. Almost every bug in this catalogue was
invisible in logs and reported as "X is missing".

---

## 13. Known rough edges

Things that are true today and worth knowing. *(Reviewed 2026-08-20.)*

- **foot and ncspot keep their old colours until restarted** after a rebuild.
  foot 1.27 has no config re-read at all — `SIGUSR1`/`SIGUSR2` only pick between
  sections it already loaded — and ncspot reads `config.toml` once at startup.
  kitty reloads in place, and rofi re-reads on every launch.

- **Nothing here can hold off the idle ladder except a Wayland idle inhibitor.**
  `systemd-inhibit --what=idle` does not reach swayidle, so unattended work on
  battery meets the 30-minute suspend. `⌥⇧A` is the in-session answer
  and it now survives a waybar restart (docs/adr/0031); `systemctl --user stop
  swayidle` is still the one nothing in the desktop can undo silently. See §9.
- **The spurious s2idle wake source is still unidentified**, and it is what keeps
  `suspend-then-hibernate` off the lid. Standing suspect: the Synaptics
  fingerprint reader — at `1-3`, the *only* device on USB bus 1, with its own
  `power/wakeup` disabled but its parent XHCI controller `0000:74:00.3`
  `enabled`. Disabling wakeup on that controller costs nothing (there is nothing
  else behind it) and is untried. Since 2026-08-12 the idle rung suspends, so
  the machine finally produces samples to test it against — see
  `docs/adr/0016`.
- **The age key is a single point of failure.** `/var/lib/sops-nix/key.txt` is
  in no repo and no backup; without it `secrets/secrets.yaml` is unreadable.
  See §11.
- ~~Helix has no Python type checking~~ — **moot 2026-08-17.** Helix was
  removed (`docs/adr/0027`); `pyright` serves nvim, which asked for it.
- ~~Nothing gates a rebuild~~ — **closed 2026-08-03.** `nix flake check` now
  builds `system.build.toplevel` and the home-manager activation package, so
  `buildEnv` collisions and failing derivations surface before a `switch`.
  `verify-packages.sh` was retired as a strict subset of it.
- ~~`nix fmt` uses the unmaintained `nixpkgs-fmt`~~ — **closed 2026-08-03**,
  now `nixfmt` (RFC 166).
- **The `.nix` files are comment-heavy** — 1,346 of 3,506 lines. `dotfiles.nix`
  is 54 lines of code under 249 lines of prose. Much of it duplicates
  `docs/adr/`, which is where the narrative belongs.
- **`~/arch-residue-backup-2026-07-30/`** (2.1 MB) is still in the home
  directory and can be deleted.

---

## 14. Further reading

| Document | Read it when |
|---|---|
| `docs/NIX-PRIMER.md` | Before §6 makes sense — store paths, profiles, wrappers, activation |
| `CLAUDE.md` | Before changing anything — the rules that apply to every task |
| `docs/gotchas.md` | Before changing one area — the failure catalogue, by area |
| `docs/adr/0001` … `0012` | Before undoing something that looks redundant |
| `dotfiles/nvim/README.md` | The Neovim config map |
| `docs/agents/` | Issue tracker (Gitea at `git.henrydowd.dev`) and agent conventions |

The ADRs are short and each records the failure that motivated the decision:

| ADR | Decision |
|---|---|
| 0001 | The flake sits at the repo root |
| 0002 | When a dotfile may be out-of-store |
| 0003 | Runtime state lives outside the config tree |
| 0004 | Nix owns GTK theming |
| 0005 | One owner per daemon |
| 0006 | Start limits on units that call remote APIs |
| 0007 | Language servers are declared, not discovered |
| 0008 | Arch was removed outright |
| 0009 | Generate config from Nix where a module exists; link files only where one does not |
| 0010 | `nix flake check` is the gate; lints tuned to fire only on real findings |
| 0047 | A retired daemon is a call that exits 0 |
| 0048 | State colour rides the class the script prints |
| 0050 | The weather panel is rofi's, because a dropdown answers no key |
| 0051 | waybar is the bar again |
| 0061 | One desktop: noctalia and wayle are removed |
