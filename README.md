# nix-config

Henry's NixOS system for a ThinkPad L14 Gen 5: the flake that builds the
machine, and the dotfiles it installs.

**This is the booted system.** NixOS was installed 2026-07-29 and Arch was
removed 2026-07-30. There is no dual boot and no fallback.

## Layout

```
flake.nix          the system, at the root so it can reference everything below
flake.lock         pinned inputs; re-lock deliberately with `update`
hosts/thinkpad/    host config and hardware-configuration.nix
modules/system/    boot, locale, networking, audio, desktop, fonts, power, …
modules/home/      home-manager: packages, shell, theme, dotfiles, and the
                   configs generated from Nix (programs.nix, waybar.nix)
dotfiles/          the hand-written dotfiles that remain (mango, nvim, zsh, …)
pkgs/              overlay for anything not in nixpkgs
checks/static.sh   the static assertion suite, run by `nix flake check`
secrets/           sops-encrypted, tracked in git
docs/              see below
```

[`docs/ANATOMY.md`](docs/ANATOMY.md) is the full map: every file, what it holds,
and why the tree is arranged this way.

## Start here

| I want to… | Read |
|---|---|
| Work on the configs themselves | [`CLAUDE.md`](CLAUDE.md) — the rules that apply to every change |
| Know what is in the repo and why | [`docs/ANATOMY.md`](docs/ANATOMY.md) — the flake, the lock, the file map |
| Understand how Nix works underneath | [`docs/NIX-PRIMER.md`](docs/NIX-PRIMER.md) — packages, profiles, wrappers |
| Use or change the machine | [`docs/SYSTEM.md`](docs/SYSTEM.md) — the operator's manual |
| Avoid a known trap in one area | [`docs/gotchas.md`](docs/gotchas.md) — the failure catalogue |
| Change the colour scheme | [`docs/THEME-MIGRATION.md`](docs/THEME-MIGRATION.md) — the runbook |
| Know why a decision was made | [`docs/adr/`](docs/adr/) — 55 numbered records |
| Know how agents should use this repo | [`docs/agents/`](docs/agents/) |

## Checking a change

```
nix flake check     # builds the system and home closures, plus the lints
nix fmt             # nixfmt over *.nix, shfmt over every bash script
./verify-claims.sh  # the assertions only a live session can answer
```

Run `nix flake check` before `rebuild`. It builds `system.build.toplevel` and
the home-manager activation package, so `buildEnv` collisions and failing
derivations surface there rather than halfway through a switch.

## Rebuilding

| Alias | Runs |
|---|---|
| `rebuild` | `nixos-rebuild switch`, then `nvd diff` against the previous system |
| `rebuild-test` | `nixos-rebuild test` — applies **without** changing the boot default |
| `rebuild-boot` | `nixos-rebuild boot` — next boot only, then `nvd diff` |
| `update` | `nix flake update` |
| `generations` | `nixos-rebuild list-generations` |
| `gc` | `nix-collect-garbage --delete-older-than 30d` |

All six are defined in `modules/home/shell.nix`.

Use `rebuild-test` for anything structural: it applies without touching the boot
default, so a mistake is one reboot from gone. The exception is
`boot.kernelParams`, where `test` writes no boot entry — see `CLAUDE.md`.

**Quote flake refs in zsh.** `EXTENDED_GLOB` is on
(`dotfiles/zsh/conf.d/00-options.zsh`), which makes `#` a pattern operator, so an
unquoted `~/src/nix-config#thinkpad` is globbed, matches nothing, and fails with
`zsh: no matches found:` before `nixos-rebuild` runs.

## Where the configuration lives

Three tiers, best first. `docs/SYSTEM.md` §6 has the full rule and the reasoning.

| Tier | Mechanism | Declared in |
|---|---|---|
| **Generated** | a native home-manager module writes the file from typed options | `modules/home/programs.nix`, `waybar.nix`, `theme.nix` |
| **Store-based** | the file stays hand-written but lands read-only in the store | `modules/home/dotfiles.nix` → `dotfiles/` |
| **Out-of-store** | a live symlink into this checkout | `corectrl` only |

Generated is the default, because a typed option turns a config typo into a
build failure. Most of what has broken this machine broke without reporting
anything, so an error that cannot be missed is worth the churn.

**Almost nothing is live-editable.** `corectrl` is the exception. Everything else
needs a `rebuild` before a reload, and the generated configs have no file to edit
at all.

`nixos-rebuild` reads this checkout directly. The repo is expected at
`~/src/nix-config`, declared once as `local.checkout` in
`modules/home/options.nix`. It cannot be `~/.config` itself, because that is
where the links are written to.

**`dotfiles/` is shrinking by design.** kitty, foot, zed, htop, ncspot, imv,
yazi, wlogout and the bar layouts are generated from `modules/home/` and have no
file in this repo. If a config is not under `dotfiles/`, grep `modules/home/`
for it.

## The `.gitignore` is a denylist

It was an allowlist until 2026-07-30, when the repo root was `~/.config` itself
and a new directory stayed invisible to git until someone un-ignored it by name.
The root is an ordinary project root now, so a new config directory is tracked by
adding it.

What is still ignored is specific: generated files
(`dotfiles/mango/config.conf`), runtime state, zsh's compdump, and the credential
directories (`gh`, `glab-cli`, `opencode`, `gpu-screen-recorder`, `rclone`,
`rbw`, `tea`). None of those are linked by the flake either.

**Flakes copy only git-tracked files.** An ignored or merely untracked file does
not exist as far as the build is concerned. That is why the wallpaper lives at
`~/.local/share/mango/wallpaper.png` and is in no repo.

## Applying changes

Everything below assumes `rebuild` has already run.

| Component | Reload |
|---|---|
| NixOS / home-manager | `rebuild`, or `rebuild-test` |
| Mangowm | `mango-reload` |
| Waybar | `waybar-reload` |
| Switch mode | `~/.config/mango/scripts/modes/<mode>.sh` |
| zsh | open a new shell, or `source ~/.config/zsh/conf.d/<file>.zsh` |
| kitty | `kill -SIGUSR1 $KITTY_PID` |
| foot, zed, htop, ncspot, imv, yazi | restart the app |
| wlogout | nothing; it is spawned fresh each time |
| Neovim plugins | `:Lazy sync` |
| GTK theme | `~/.config/mango/scripts/system/gtk-apply.sh` |
| `autostart.conf` | log out and back in; `exec_once` fires only at startup |

**Edits under `dotfiles/` need a rebuild too.** They are store paths, not live
symlinks. Reloading without rebuilding restarts against the config that was
already there, which looks the same as the change having had no effect.
