# How packages and configuration actually work

The layer below `docs/SYSTEM.md` §6. That section says which tier a config
belongs in and `docs/adr/0009` says why; this file explains the mechanism they
both sit on: what a package is, how it reaches `$PATH`, and how a config file
reaches `~/.config`.

For what is in this repo and how it is arranged, see `docs/ANATOMY.md`.

Every example below is real output from this machine, not an illustration.

---

## 1. A package is a directory, not an installation

There is no install step in Nix. Building a package produces one immutable
directory under `/nix/store`, named by a hash of every input that went into it:

```
/nix/store/pbsm8dv4d5nhdmdr494ibwsq393cvka2-kitty-0.48.2/
├── bin/kitty
├── lib/
└── share/
```

Change a dependency, a flag or a patch and the hash changes, so both versions
coexist. Nothing is mutated in place and nothing is overwritten. That is
the whole model; the rest is plumbing that decides which store paths are visible.

This is why `nix flake check` catches errors that a switch would otherwise hit
halfway through: building the closure is separate from installing it.

## 2. How a store path reaches `$PATH` — profiles

A **profile** is a directory of symlinks pointing into the store, built by
`buildEnv` from a list of packages. Two matter here:

| Profile | Built from | Symlinked at |
|---|---|---|
| system | `environment.systemPackages` (`modules/system/`) | `/run/current-system/sw/bin` |
| user | `home.packages` + every enabled `programs.*` (`modules/home/`) | `/etc/profiles/per-user/henry/bin` |

The user profile lands under `/etc` rather than `~/.nix-profile` because
`flake.nix` sets `useUserPackages = true` — home-manager hands its package list
to NixOS to install, so one rebuild owns both.

Follow the chain for kitty:

```
/etc/profiles/per-user/henry/bin/kitty
  → /nix/store/…-home-manager-path/bin/kitty       the user profile's buildEnv
  → /nix/store/…-kitty-0.48.2/bin/kitty            the package
```

Three consequences:

- **A package in both lists is only harmless while both resolve to the same
  store path.** Twenty names are in both here; override or pin one side and PATH
  order silently decides which binary wins. `checks/static.sh` checks for
  divergence, not duplication.
- **Two packages providing the same file collide at `buildEnv`**, not at
  runtime. That failure surfaces during `nix flake check` because the gate
  builds both closures — an evaluate-only script cannot see it (`docs/adr/0010`).
- **`nix develop` prepends its own store paths.** Inside this repo's devShell,
  `which` reports the devShell's copy. That is why CLAUDE.md forbids
  `dbus-update-activation-environment` from a task shell: it would push that PATH
  into every user unit started afterwards.

## 3. The binary invoked is usually not the binary that runs

nixpkgs wraps most programs so they can find their own libraries, plugins and
data at runtime. The wrapper takes the real name; the payload is hidden beside
it with a dot:

```
$ ls -a …-waybar-0.15.0/bin/
waybar              # a 16 KB shell script — sets env, then execs the next line
.waybar-wrapped     # the 3.7 MB real binary
```

The exec replaces the process, so the *running* process is the payload:

```
$ ps -eo comm,args | grep waybar
.waybar-wrapped   waybar -c …/config-full-top.jsonc -s …/style-solid.css
```

`comm` is `.waybar-wrapped`; the command line still says `waybar`. The kernel
also truncates `comm` to 15 characters, which is how `elephant` used to appear
as `.elephant-wrapp`.

This is behind the process rules in CLAUDE.md. `pkill -x waybar` matches `comm`,
finds nothing, and leaks the process without reporting anything. Match the
command line to kill (`pkill -f 'bin/waybar$'`) and match `comm` to test
(`pgrep '^\.?waybar'`).

## 4. How a config reaches `~/.config`

Home-manager collects every file it is asked to manage into one store path —
`…-home-manager-files` — and, at activation, symlinks each entry into place.
So `~/.config` is a directory of symlinks pointing into the store:

```
~/.config/kitty/kitty.conf → /nix/store/…-home-manager-files/.config/kitty/kitty.conf
~/.config/nvim            → /nix/store/…-home-manager-files/.config/nvim
```

The three tiers in `docs/SYSTEM.md` §6 differ only in **what sits at the far end
of that link**:

| Tier | Far end | Written by |
|---|---|---|
| 1 — generated | a store file with no source in this repo | Nix, from typed options |
| 2 — store-based | a store copy of `dotfiles/X` | hand-written, copied in at build |
| 3 — out-of-store | a symlink to `~/src/nix-config/dotfiles/X` | hand-written, live |

Tier 3 is a symlink to a symlink: `~/.config/corectrl` points into
`home-manager-files`, which points at a link back into the checkout. That is why
edits take effect with no rebuild, and why a fresh clone at a different path gets
a dangling link.

Two mechanics that decide most placement questions:

- **A directory-valued `source` becomes one symlink; a file-valued one becomes a
  real directory containing a file symlink.**
  `xdg.configFile."Kvantum/kvantum.kvconfig".source` therefore pins the file
  while leaving the parent writable for the app's own runtime files. Linking the
  parent instead would give one path two owners.
- **Activation fails when two things claim one path.** It is not a merge and not
  a last-writer-wins. If a program rewrites a file at runtime, no
  `xdg.configFile` may claim it and git must not track it — that is why
  `programs.ncspot.settings` has to stay `{ }`.

A module that merges avoids this entirely: `programs.zed-editor` runs
`jq -n '$dynamic * $static'` over the real writable `settings.json` instead of
linking it. Declarative does not have to mean read-only, so check for a merging
module before accepting a mutable directory.

## 5. Why "install" and "configure" are one option

`programs.kitty.enable = true` adds kitty to `home.packages` *and* generates
`kitty.conf`. One option owns both, so removing it removes both.

The alternative is a package in `packages.nix` and a directory in
`dotfiles.nix`: two independent declarations that nothing connects, so removing
one leaves the other. That was the state of kitty, foot, zed, htop, ncspot, imv
and yazi before the 2026-08-01 pass. The full argument is `docs/adr/0009`.

The second payoff is that typed options make a typo an evaluation error. A
hand-written file that Nix copies verbatim reproduces the typo exactly, and in
this repo a wrong config usually renders as an empty widget rather than an error.
That is why generated config is the default rather than a preference.

## 6. What `rebuild` actually does

```
nix flake check     evaluate + build both closures + lint          ← the gate
       │
       ▼
nixos-rebuild switch
  1. evaluate flake.nix → a system derivation
  2. build it and everything it depends on (the closure)
  3. link the result as a new generation:  /nix/var/nix/profiles/system-111-link
  4. point /nix/var/nix/profiles/system at it
  5. run the activation script: write /etc, start and stop units,
     and run home-manager's — which relinks ~/.config
```

Steps 3 and 4 are why rollback is instant: the old generation is still a
complete tree in the store. `system-105-link` through `system-111-link` are all
present right now.

They are also what the three variants trade against each other:

| | Activates now | Writes a generation | Writes a boot entry |
|---|---|---|---|
| `switch` | yes | yes | yes |
| `boot` | no | yes | yes |
| `test` | yes | **no** | **no** |

`test` is right for structural changes, because a mistake is one reboot from
gone, and wrong for `boot.kernelParams`, which exist only in a boot entry that
`test` never writes. It also creates no GC root, which is what made the
`recursive = true` accident worse.

**Nothing in `~/.config` changes until step 5 runs.** Reloading an app without
rebuilding first reloads what the last rebuild produced, which looks the same as
the change having had no effect.

## 7. The overlay — changing a package without forking it

`pkgs/default.nix` is the one overlay, a function of `final` and `prev`:

```nix
paletteGtk = (prev.colloid-gtk-theme.override { … }).overrideAttrs (old: { … });
```

`prev` is the package before this overlay; `final` is the package after every
overlay has applied. Use `prev` to build on the original, as above, where
Colloid is compiled against this repo's palette. Use `final` when one package must pick up
another package's override, or it gets the unpatched copy with nothing said.

`flake.nix` deliberately builds its lint tooling without the overlay: a lint
result must not depend on a package override.

## 8. Build time and runtime

Everything above happens at build time. Nothing evaluated then can react to
anything that happens afterwards.

- A generated artefact cannot change at runtime. A built GTK theme follows a
  scheme change only through a rebuild.
- A systemd unit's `Environment = [ "PATH=…" ]` is its entire PATH; there is no
  ambient environment to fall back on. Omitting `pkgs.bash` is how the wlsunset
  runner's `env bash` shebang exited 127.
- Nix strings have no `\uXXXX` escape, so a glyph must be literal UTF-8 in the
  source. No build step reports the difference.

---

## Where this shows up

| Symptom | Read |
|---|---|
| asking what a file in this repo is for | `docs/ANATOMY.md` §5 |
| a `pkill`/`pgrep` that matches nothing | §3 above, then CLAUDE.md → Writing shell here |
| activation fails on a file two things claim | §4 above, then `docs/gotchas.md` → Theming |
| choosing a tier for a new app's config | `docs/SYSTEM.md` §6, then `docs/adr/0009` |
| a package appearing in two profiles | §2 above, `modules/home/packages.nix` header |
| a change that appears to have had no effect | §6 above; rebuild before reload |
| a daemon started twice, or not at all | `docs/adr/0005` |
