# Anatomy of the flake

What `flake.nix` and `flake.lock` do, what every directory and file holds, and
why the tree is shaped this way.

| Document | Answers |
|---|---|
| **`docs/ANATOMY.md`** (this file) | What is in the repo, and why is it arranged like this? |
| `docs/NIX-PRIMER.md` | How do packages and configs work at all? |
| `docs/SYSTEM.md` | How is the machine laid out, and how do I use it? |
| `docs/gotchas.md` | What has broken, by area? |
| `docs/adr/` | Why this decision rather than the obvious one? |

§5 is the canonical repository map. `README.md` and `docs/SYSTEM.md` §3 point
here rather than repeating it.

---

## 1. What a flake is here

A flake is a function from `inputs` to `outputs`, evaluated in pure mode: no
`$NIX_PATH`, no channels, no `<nixpkgs>`, no `builtins.getEnv`, and no access to
any path outside the flake's own directory.

Two consequences shape the rest of this file.

**A flake evaluates from a copy of itself in `/nix/store`, containing only
git-tracked files.** An untracked file does not exist as far as the build is
concerned. This is why `checks/static.sh` sees exactly what a fresh clone would,
and why `local.checkout` in `modules/home/options.nix` has to be written down:
Nix cannot discover where the repo was cloned.

**A flake can only reference paths at or below its own directory.** `../mango`
does not resolve. This is why `flake.nix` sits at the repo root
([0001](adr/0001-flake-at-repo-root.md)).

---

## 2. `flake.nix`

285 lines, four outputs.

### Inputs

| Input | URL | `follows` |
|---|---|---|
| `nixpkgs` | `github:NixOS/nixpkgs/nixos-unstable` | — it is the root |
| `home-manager` | `github:nix-community/home-manager` | `nixpkgs` |
| `nixos-hardware` | `github:NixOS/nixos-hardware` | none needed |
| `sops-nix` | `github:Mic92/sops-nix` | `nixpkgs` |
| `zen-browser` | `github:0xc000022070/zen-browser-flake` | `nixpkgs` |
| `claude-desktop` | `github:k3d3/claude-desktop-linux-flake` | deliberately not |

`inputs.X.follows = "nixpkgs"` rewrites that input's own `nixpkgs` edge to point
at ours. Without it, each flake brings a full second nixpkgs, a second `glibc`,
and two incompatible copies of every library shared across the closure.

`claude-desktop` is the exception. It references `pkgs.nodePackages`, which
nixpkgs has removed. Inputs evaluate as one graph, so forcing our nixpkgs onto it
breaks evaluation of the entire system, not just that one package. Leaving it
unfollowed costs a second nixpkgs of sources on disk.

`nixos-hardware` needs no `follows`. It ships modules, not packages, so nothing
in it is built against its own nixpkgs.

### The `let` block

```nix
system   = "x86_64-linux";
pkgs     = nixpkgs.legacyPackages.${system};   # no overlay, deliberately
overlays = [ (import ./pkgs { inherit inputs; }) ];
```

This `pkgs` is used only by the lint and check derivations, and it skips the
overlay so that a lint result cannot depend on a package override. The system's
`pkgs` is a different, overlaid one, built inside `nixosSystem`.

### Output 1 — `nixosConfigurations.thinkpad`

The attribute `nixos-rebuild switch --flake ~/src/nix-config#thinkpad` looks up.
`networking.hostName = "thinkpad"` must match it, because with no fragment
`nixos-rebuild` falls back to the hostname.

Module list, in order:

1. `{ nixpkgs.overlays = overlays; }`, an inline module. Everything after it sees
   an overlaid `pkgs`.
2. Four `nixos-hardware` modules: `lenovo-thinkpad`, `common-cpu-amd`,
   `common-gpu-amd`, `common-pc-laptop-ssd`.
3. `./hosts/thinkpad`.
4. `home-manager.nixosModules.home-manager`, plus its configuration block.

`specialArgs = { inherit inputs; }` is what puts `inputs` in a system module's
argument header; `extraSpecialArgs` does the same for home modules. Without them,
`modules/system/secrets.nix` could not write `inputs.sops-nix.nixosModules.sops`.

The home-manager settings:

- `useGlobalPkgs = true` — home-manager uses the system `pkgs`, overlay included,
  instead of instantiating its own nixpkgs.
- `useUserPackages = true` — `home.packages` land in
  `/etc/profiles/per-user/henry`, so they are part of the system generation and
  roll back with it.
- `backupFileExtension = "hm-bak"` — an unmanaged file in the way is renamed
  rather than aborting activation. `.gitignore` ignores `*.hm-bak`.

### Output 2 — `checks.x86_64-linux`

| Check | What it builds |
|---|---|
| `system` | `config.system.build.toplevel`, the real system closure |
| `home` | `home.activationPackage`, the real home generation |
| `statix` | Nix lints; `repeated_keys` is off, see `statix.toml` |
| `deadnix` | `--no-lambda-pattern-names`, which drops 37 module-header findings |
| `shellcheck` | shellcheck and shfmt over every bash script, found by shebang |
| `static` | `checks/static.sh` |

The first two are the point of [0010](adr/0010-flake-check-is-the-gate.md). They
are build products, so checking them builds the whole closure: `buildEnv`
collisions, failing derivations and eval errors surface here instead of halfway
through a `switch`. An evaluate-only script cannot do that.

The `shellcheck` check asserts a floor:

```sh
found=$(tr -cd '\0' < "$TMPDIR/scripts" | wc -c)
if [ "$found" -lt 30 ]; then exit 1; fi
```

A scan that stops matching otherwise passes by finding nothing. `static.sh` uses
the same pattern 41 times.

The `static` check is handed two JSON files that Nix builds at eval time:

- `schemes.json` — every scheme the machine wears, with values resolved. The
  check used to read hex out of the theme files with `sed`, so a role written as
  an alias (`okColor = green;`) read as "role absent". Four did, and went
  unaudited. Nix resolves the `rec` first, so the shell sees values rather than
  source text ([0032](adr/0032-the-theme-file-owns-its-artefacts.md)).
- `packages.json` — both package lists as `name -> store path`. Ownership is an
  eval question, so it is answered by eval rather than by grepping two files.

The rule behind both: anything decidable at eval time is decided by Nix and
handed to the shell as data.

### Output 3 — `formatter`

`nix fmt` runs a wrapped `writeShellApplication` rather than `pkgs.nixfmt`
directly, because `nix fmt` passes no file arguments and bare `nixfmt` then fails
on empty stdin with `unexpected end of input`. The wrapper covers `*.nix` and
every bash script found by shebang — half of `dotfiles/scripts/*` has no
extension — so `nix fmt` is a no-op across both languages.

Replace it with treefmt-nix rather than growing it further.

### Output 4 — `devShells.default`

`nixfmt statix deadnix shellcheck nix-tree sops age`, plus `SOPS_AGE_KEY_FILE`.
`.envrc` is one line, `use flake`, so direnv enters the shell automatically.

`sops` and `age` are devShell-only rather than in `packages.nix` because `sops`
resolves recipients from the `.sops.yaml` in the working directory
([0012](adr/0012-secrets-in-sops.md)).

### What is not an output

No `packages`, no `nixosModules`, no `homeConfigurations`, no `apps`. This flake
builds one machine and exports nothing for anyone else to consume.

---

## 3. `flake.lock`

The lock turns every mutable reference into an immutable one.
`github:NixOS/nixpkgs/nixos-unstable` is a branch, so it means something
different every hour. The lock records a commit plus a `narHash` of the fetched
tree, so a tampered tarball fails.

Twelve nodes, schema `version: 7`:

```
root
├── nixpkgs        → nixpkgs_3      NixOS/nixpkgs  0e251e24a4f2
├── home-manager   → home-manager        nixpkgs → [root nixpkgs]
├── nixos-hardware → nixos-hardware
│      └── nixpkgs → nixpkgs_2      its own, unfollowed
├── sops-nix       → sops-nix            nixpkgs → [root nixpkgs]
├── zen-browser    → zen-browser         nixpkgs → [root nixpkgs]
│      └── home-manager → home-manager_2     nixpkgs → [root nixpkgs]
└── claude-desktop → claude-desktop
       ├── nixpkgs → nixpkgs        NixOS/nixpkgs  6ad174a6dc07  (2025-06)
       └── flake-utils → flake-utils → systems
```

Reading the suffixed names:

- `nixpkgs_3` is ours. Unsuffixed `nixpkgs` is **claude-desktop's**, pinned to a
  June 2025 commit — the `nodePackages` era, which is why the `follows` is
  omitted.
- `nixpkgs_2` is nixos-hardware's own, unfollowed and harmless.
- `home-manager_2` is zen-browser's copy of home-manager: a second source tree,
  not a second nixpkgs, because its nixpkgs edge already follows ours.
- `flake-utils` and `systems` are claude-desktop's boilerplate. This flake uses
  neither.

Anything in `[...]` brackets is a `follows` edge. Anything bare is an
independently locked copy.

Re-lock deliberately: `nix flake update` for everything, `nix flake update
nixpkgs` for one input. Never as a side effect of a build.

---

## 4. The evaluation chain

```
nixos-rebuild switch --flake .#thinkpad
  └─ flake.nix outputs.nixosConfigurations.thinkpad
       └─ nixpkgs.lib.nixosSystem
            ├─ { nixpkgs.overlays = [ import ./pkgs ] }
            │     └─ pkgs/default.nix   ── imports modules/home/palette.nix directly
            │           └─ import ./themes/${import ./scheme.nix}.nix
            ├─ nixos-hardware modules ×4
            ├─ hosts/thinkpad/default.nix
            │     ├─ hardware-configuration.nix
            │     └─ modules/system/*.nix  ×11
            └─ home-manager.nixosModules.home-manager
                  └─ modules/home/default.nix
                        └─ options, packages, shell, programs, waybar,
                           dotfiles, theme
  → system.build.toplevel  (a store path)
  → switch-to-configuration
```

The marked line explains a choice that otherwise looks wrong. **An overlay runs
before any module evaluates**, so `pkgs/default.nix` cannot read `config.*`. The
selected scheme therefore cannot be a home-manager option: an option would reach
eleven consumers and miss the twelfth, the lock-background ramp built in the
overlay. `scheme.nix` is a bare file that both sides `import`
([0030](adr/0030-the-scheme-is-a-file-not-an-option.md)).

---

## 5. Repository map

```
~/src/nix-config/
├── flake.nix                 inputs and the thinkpad configuration. At the root — 0001
├── flake.lock                pinned inputs; only moves on `update`
├── CLAUDE.md                 agent instructions; wins over SYSTEM.md on conflict
├── README.md                 entry point
├── .envrc                    `use flake`
├── .gitignore                a denylist
├── .sops.yaml                age recipients, one key
├── statix.toml               lint config
├── verify-claims.sh          the assertions only a live session can answer
├── hosts/thinkpad/
├── modules/system/           11 files, one concern each
├── modules/home/             17 files, home-manager
├── pkgs/                     the overlay
├── checks/static.sh          the static assertion suite
├── dotfiles/                 what is still a hand-written file
├── secrets/                  sops-encrypted, tracked
└── docs/
```

### Root

| File | Purpose |
|---|---|
| `flake.nix` | §2 |
| `flake.lock` | §3 |
| `CLAUDE.md` | Agent-facing instructions. Where it and `docs/SYSTEM.md` disagree, it wins — it is kept current against failures |
| `README.md` | Entry point: what this is, the change loop, rebuild aliases |
| `.envrc` | `use flake` |
| `.gitignore` | A denylist. It was a 119-line allowlist when the repo root was `~/.config`; the history is kept in comments because the shape recurs |
| `.sops.yaml` | age recipients — one key, `&thinkpad` — and `creation_rules` matching `secrets/*.yaml` |
| `statix.toml` | Disables `repeated_keys` (W20). It produced 69 findings, all of them wrong for NixOS module style, and a check that always fails stops being read |
| `verify-claims.sh` | The assertions that need a live Wayland session: `wlopm` enumerates an output, `mmsg` reports a monitor. Skips rather than fails when headless |

### `hosts/thinkpad/` — identity

| File | Purpose |
|---|---|
| `default.nix` | 84 lines. Imports the eleven system modules, then only what is specific to this machine: hostname, the `henry` user with uid and gid pinned to 1000 because `@home` came from Arch, sudo-rs, polkit, rtkit, gnome-keyring, `system.stateVersion` |
| `hardware-configuration.nix` | 152 lines. Btrfs subvolumes on one UUID, the ESP, kernel modules, swap. `fsUUID` and `btrfsOpts` are factored into a `let` so the UUID appears once |

### `modules/system/` — 11 files, 1,346 lines

| File | Configures |
|---|---|
| `boot.nix` | systemd-boot with `configurationLimit = 6`, kernel and `kernelParams`, firmware, `services.snapper` |
| `locale.nix` | `time.timeZone`, `en_GB.UTF-8`, console keymap, `services.keyd` (the ⌥/⌘ layers mango binds against) and its `keyd` group |
| `networking.nix` | NetworkManager and its declared profiles, firewall, avahi, resolved, tor, wireshark, the wifi-resume unit |
| `pia-ca.pem` | PIA's public CA, vendored so the profiles do not depend on `~/.local/share` residue |
| `audio.nix` | PipeWire with alsa, pulse and jack; pulseaudio off; the micmute-led udev rule and unit |
| `desktop.nix` | mango, greetd, portals, graphics, bluetooth and blueman, thunar with gvfs/tumbler/udisks2, fprintd, dconf, PAM |
| `fonts.nix` | `nerd-fonts.*` individually, plus fontconfig defaults |
| `power.nix` | 314 lines. TLP, charge thresholds, logind, upower, thermald, fwupd, corectrl, the sleep and resume hooks |
| `printing.nix` | CUPS and sane, with the Brother MFC-L3740CDW |
| `virtualisation.nix` | podman with docker compat, libvirtd, virt-manager, spice USB redirection, steam, gamescope, gamemode |
| `nix-settings.nix` | `experimental-features`, `auto-optimise-store`, `trusted-users`, GC, registry, daemon scheduling |
| `secrets.nix` | sops-nix. Declares only what something reads, because a declared secret with no consumer is a plaintext file in `/run/secrets` at every boot ([0012](adr/0012-secrets-in-sops.md)) |

### `modules/home/` — 15 files, 4,210 lines

Entry and plumbing:

| File | Purpose |
|---|---|
| `default.nix` | 289 lines. The `imports` list, XDG and `mimeApps`, and the session-level pieces: swayidle's four-rung idle ladder, poweralertd, the `wlsunset` and `wlinhibit` units, the masked `swaync.service`, nextcloud-client, `systemd.user.sessionVariables` |
| `options.nix` | Separate for a mechanical reason: a module that declares `options` must put everything else under `config`, so mixing `options.foo` with a bare `home.username` is an evaluation error. Declares `local.checkout` and `local.location` |

Colour:

| File | Purpose |
|---|---|
| `scheme.nix` | Twelve lines; the last is `"heartbox"`. The artefact scheme |
| `palette.nix` | 55 lines of comment over one line of code: `import ./themes/${import ./scheme.nix}.nix` |
| `themes/*.nix` | Five files: `heartbox`, `mocha`, `mocha-high-contrast`, `gruvbox`, `nord`. Each is a `rec` attrset holding the colour ramp, semantic roles, sixteen ANSI slots, its own measured `contrastFloor` and `ansiFloor`, `packages` (GTK, Kvantum, cursor, icons) and `apps` (nvim). `rec` matters: a missing key is an evaluation error rather than a silent default |

Config, by tier ([0009](adr/0009-generated-config-over-linked-files.md), and
`docs/SYSTEM.md` §6 for the tier rules):

| File | Tier | Purpose |
|---|---|---|
| `programs.nix` | 1 | 628 lines. Native `programs.*` for kitty, foot, zed, htop, imv, yazi, ncspot, git and bat, all coloured from `palette.nix` in their own `settings` |
| `waybar.nix` | 1 | 972 lines. **The bar in service** ([0051](adr/0051-waybar-is-the-tiling-bar-again.md)). Six layouts generated from one shared module set via `lib.genAttrs`. The four hand-maintained `.jsonc` files had drifted: `custom/window` carried `max-length` 60 in two of them and 80 in a third. Also owns `appIcons`, the appid-to-icon-name map, which generates `icons.css`, `app-icons.json` and the hicolor aliases rofi's window mode needs ([0052](adr/0052-the-bar-draws-the-icon-theme.md)) |
| `theme.nix` | 1 | 166 lines. GTK, Qt, cursor and icons, with every name taken from the theme file rather than spelled out |
| `dotfiles.nix` | 2, 3 | 539 lines. What is still a hand-written file. Exactly one tier-3 entry survives: `corectrl`. Generates rofi's `colors.rasi` and `icons.rasi`, mango's `universal/colors.conf` and Equibop's theme, whose name an activation step writes into Equibop's own `settings.json` |
| `packages.nix` | — | 271 lines. `home.packages`, one owner per package |
| `shell.nix` | — | 131 lines. zsh via `dotDir`, sourcing `conf.d/*` from `initContent` |

### `pkgs/` — the overlay, 821 lines plus generators

One overlay, one entry point. `pkgs/default.nix` is `{inputs}: final: prev:` and
defines three groups.

**Theme artefacts built from the palette**
([0041](adr/0041-artefacts-are-generated-not-named.md)) — `paletteGtk` (Colloid
recompiled from generated SCSS), `paletteKvantum` (an achromatic SVG re-tinted by
luminance), `paletteCursors`, `themeYazi`, `themeZed`, `lock-backgrounds`,
`lockscreen`.

**Packages absent from nixpkgs** — `power-profiles-tlp`.

| Helper | Purpose |
|---|---|
| `colloid-palette.py` | Writes Colloid's `_color-palette-*.scss` from `palette.json` |
| `kvantum-recolour.py` | Maps a greyscale Kvantum SVG onto the palette by luminance |
| `zed-theme.py` | Writes a Zed theme JSON |
| `yazi-flavor.nix` | 220 lines of colour, generated rather than fetched from four unrelated upstreams that agree on the schema and nothing else |
| `lock-backgrounds/blocks.py` | Emits one swaylock background as a binary PPM at grid resolution. Upscaling is ImageMagick's job, because swaylock draws with `CAIRO_FILTER_BILINEAR` ([0018](adr/0018-lock-background-is-a-pool.md)) |
| `power-profiles-tlp/daemon.py` | 315 lines. Serves the power-profiles-daemon D-Bus API from TLP ([0026](adr/0026-serve-the-ppd-bus-name-from-tlp.md)) |
| `power-profiles-tlp/dbus-policy.conf` | Bus policy in place of polkit: wheel writes, everyone reads |
| `power-profiles-tlp/dbus-service.in` | The D-Bus activation stub |

`paletteJson` is built once and shared by both Python generators, so a role
present for one and absent for the other is a build-time `KeyError` rather than a
divergence.

### `checks/static.sh` — 3,191 lines

Takes five arguments: source root, home generation, system toplevel,
`schemes.json`, `packages.json`. Sections: Repo, Scripts, Secrets,
Runtime-selected files, Mango config parse, Generated palette, Theme packages,
NetworkManager profiles, Generated waybar configs,
Battery, Idle, Fonts, Shell completions, Display firmware, Signal traps, Package ownership.

It reads what home-manager actually wrote, under `$GEN/home-files/.config`,
rather than the sources — several files no longer have a source. Nothing is
allowed to skip, and 41 assertions carry a floor
([0011](adr/0011-shell-is-gated-too.md)).

### `dotfiles/` — the hand-written remainder

| Directory | Holds |
|---|---|
| `mango/` | The compositor. `config.conf` sources `universal/`; plus 31 bash scripts under `scripts/` and `waybar/style-solid.css` |
| `nvim/` | The one large hand-rolled config, lazy.nvim, ~22 files. Not generated ([0009](adr/0009-generated-config-over-linked-files.md)) |
| `zsh/conf.d/` | Shell options, aliases, PATH, bindings, prompt |
| `swaync/` | `style-body.css` |
| `glow/`, `rofi/`, `nwg-look/` | Apps with no module, or whose module is not adopted |
| `gtk-3.0/`, `gtk-4.0/` | `colors.css` and the titlebar button assets |
| `wlogout/icons/` | Assets only; the config is generated |
| `equibop/` | `theme-body.css` |
| `corectrl/` | The single out-of-store entry |
| `scripts/` | Extensionless bash, linked to `~/.scripts` |

This directory shrinks by design. kitty, foot, zed, htop, ncspot, imv, yazi,
wlogout and the bar layouts have no file here. If a config is not under
`dotfiles/`, it is generated: grep `modules/home/`.

### `secrets/` and `docs/`

`secrets/secrets.yaml` is sops-encrypted and tracked on purpose, holding the
`pia`, `wireguard` and `forge` keys. The age private key lives at
`/var/lib/sops-nix/key.txt` and is in no repo and no backup. `secrets/README.md`
documents the split between declared and stored-only secrets.

`docs/` holds this file, `NIX-PRIMER.md`, `SYSTEM.md`, `gotchas.md`,
`THEME-MIGRATION.md`, `adr/` (55 records) and `agents/` (issue tracker, triage
labels, documentation conventions).

---

## 6. Why this shape

### The choices that are load-bearing

**The flake is at the root, not in `nixos/`.** The repo used to be `arch-config`,
and its root *was* `~/.config`, with the flake one level down. That cost two
things, and the second is decisive: `.gitignore` had to be an allowlist over
9.6 GB of browser profiles and real credentials, and the dotfiles were outside
the flake root, so `source = ../mango` could not resolve. Converting a config to
a store path was not difficult, it was impossible. Do not move the flake back
down: the existing out-of-store links keep working, so the lost capability stays
invisible until someone tries to use it
([0001](adr/0001-flake-at-repo-root.md)).

**home-manager is a NixOS module, not standalone.** The alternative is
`homeConfigurations.henry` plus `home-manager switch`, which buys a fast rootless
rebuild loop and portability to non-NixOS machines. It costs what this repo
relies on: one `nix flake check` that builds both closures, one generation that
rolls both halves back together, and one `pkgs` with the overlay shared by both.
The halves are coupled — the overlay builds theme artefacts the home modules
consume, and `static.sh` reads the home generation and the system toplevel in one
pass — so splitting them means two gates that can disagree.

**The split is by layer (`modules/system` and `modules/home`), not by feature.**
The alternative is `modules/desktop/` holding both its NixOS and its
home-manager halves. That is better when features are independent. Here they are
not: the desktop spans greetd, the compositor, six generated bar layouts, a
palette and 31 scripts, so a feature split would put most of the
repo in one directory. The layer split matches the two closures the gate builds.

**`hosts/thinkpad/` exists for a single host.** It is overhead today: 84 lines,
14 of them imports. It stays because it is the only place that says "this
machine", and the alternative sprays host settings through `modules/system/`,
which makes a second machine a refactor rather than a directory.

**One `pkgs/default.nix`, not per-package files.** nixpkgs' own `by-name`
convention is the shape that scales. With eight packages sharing `paletteJson`,
`themePkg` and `themeData`, splitting them means either re-importing the palette
in eight files or inventing a local `lib`. The `final: prev:` comment names the
constraint that keeps it one file: `lockscreen` composes `lock-backgrounds` from
the same overlay, and only the fixpoint argument sees it.

**A `dotfiles/` tree, not per-app colocation.** `modules/home/nvim/{default.nix,
init.lua}` reads better per app, but loses the property this repo uses:
`dotfiles/` is a visible record of what is not yet generated, and it shrinks.
Spread across module directories, "how much is still hand-written" stops being
answerable at a glance.

**Checks are flake outputs, not a `justfile`.** `nix flake check` is one command,
it is what CI would run, and because `system` and `home` are real derivations the
check is the build ([0010](adr/0010-flake-check-is-the-gate.md)).

**No flake-parts, flake-utils or treefmt-nix.** All three pay off across multiple
systems or many outputs. With one system and one host, `system =
"x86_64-linux"` in a `let` is shorter than any of them. The `formatter` comment
names its own exit condition: replace it with treefmt-nix rather than growing it.

### What this shape costs

- `hosts/thinkpad/default.nix` lists its imports by hand, so adding a system
  module means editing two files. `lib.filesystem.listFilesRecursive` would
  remove that, at the price of a stray `.nix` file becoming live config with
  nothing said.
- `waybar.nix` holds 972 lines. It does one job, but generated bar layouts
  could reasonably be their own directory.
- `static.sh` is a 3,191-line file with fifteen sections and no test framework.
  It is the most likely candidate for splitting next.
- `palette.nix` is 55 lines of comment over one line of code. That follows the
  documented style, but it makes the dispatcher look heavier than it is.
- The unfollowed `claude-desktop` nixpkgs is a year-stale second source tree,
  carried for one application.

### The rule underneath

Every structural choice above is the same trade taken repeatedly: make a mistake
fail at evaluation time, loudly. `scheme.nix` is a file, so a typo is "file not
found". The theme files use `rec`, so a missing role is an evaluation error.
Layouts go through `lib.genAttrs`, so a module name with no definition fails
instead of rendering as nothing. The overlay writes `final.${d.attr}`, so a bad
package name errors with the name in it. Every scan carries a floor, so a check
that stops matching fails instead of passing.
