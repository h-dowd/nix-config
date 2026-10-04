# Gotchas — the failure catalogue

Everything here has broken this machine at least once. Read the section for the
area being changed. `CLAUDE.md` carries the rules that apply to every
task; this file carries the ones that apply to one area.

Almost all of them share a shape: **the failure is silent**. A missing component
and a broken one look identical, so "it ran and exited 0" is not evidence.

- [Arch carryover](#arch-carryover) — state that survived via `@home`
- [nixpkgs and NixOS](#nixpkgs-and-nixos) — packaging traps
- [Desktop](#desktop) — mango, rofi, swaync, wlogout
- [Waybar](#waybar)
- [Power](#power) — battery, suspend, hibernation, the GPU freeze
- [Editors](#editors)
- [Theming](#theming)
- [Networking](#networking)
- [Secrets](#secrets) — sops, what the flake installs
- [Credentials and keyrings](#credentials-and-keyrings) — gnome-keyring, what apps save
- [Session environment](#session-environment) — what user units inherit
- [Scripts](#scripts)

---

## Arch carryover

`@home` is shared, so imperative state crossed the migration untouched. **Nothing
in this repo is wrong in these cases and no rebuild can fix them** — the bad
value lives in a profile directory. Suspect this shape for anything that worked
on Arch and now fails instantly and silently.

**Chromium/Electron apps that die instantly** — `~/.cache/<app>/SingletonLock` is
a symlink naming `<hostname>-<pid>`. The hostname is now `thinkpad`, not `arch`;
Chromium cannot check a PID on another machine, so it assumes the profile is open
elsewhere and exits 1 with **nothing on stdout or stderr**. Spotify failed this
way. Fix: rename `Singleton{Lock,Cookie,Socket}` aside. Presents as "my shortcut
isn't working", not as the app failing.

**Zen — everything is called `zen-beta`.** The flake installs the beta channel,
so the binary, the desktop file and the Wayland `app_id` are all `zen-beta`;
Arch's package used `zen`. Every reference had to change and each failed
silently — `xdg.mimeApps` pointed at a nonexistent `zen.desktop` (so https fell
back to chromium), and two `mango/universal/rule.conf` rules matched `appid:zen`
and never fired. Confirm an appid with `mmsg watch focusing-client`.

> `nvim/scripts/zen-wrapper` is unrelated — a knap preview wrapper that launches
> chromium in app mode. Don't "fix" it to use Zen.

**Zen's profile selection.** `profiles.ini` picks the default per-installation
via an `[Install<hash>]` section keyed on the **executable path**, which became a
store path. With no match, Zen fell back to the legacy `Default=1` flag, which
sat on a near-empty profile — so the first NixOS launch had no extensions, logins
or history. Fixed by moving `Default=1` onto `[Profile0]` (the real 839 MB
profile). **Do not add an `[Install<hash>]` entry for the current store path** —
it changes on every Zen update and would orphan the setting again.

**LibreOffice's "defective JRE" dialog** came from
`libreoffice/4/user/config/javasettings_Linux_X86_64.xml` recording an Arch JVM
path. Delete that file *and* its `user/pack/` copy (`SecureUserConfig=true` keeps
packed backups, so leaving the pack invites a restore); it regenerates as
`javaInfo xsi:nil="true"`, which raises no dialog. What made it want Java at all
was an orphaned Zotero extension — `unopkg list`, then `unopkg remove`. No JDK is
needed for ordinary use, and `javaldx` exiting 255 is the normal "no JRE" signal.

**`~/.config/systemd/user/` overrides `/etc/systemd/user/`**, so Arch-era units
silently shadowed generated ones. `micmute-led.service` was shadowed by a copy
with no `PATH=`, so `pactl` was not found and it restart-looped 6,464 times. That
directory now holds only home-manager symlinks, so the hazard is closed rather
than merely audited — keep it that way. A unit's `path` is its **entire** PATH,
including `bash` itself.

**NetworkManager profiles and Bluetooth pairings** were restored by hand into
root-owned directories and are **not declarative** — a decision, not a TODO.
Re-restoring reintroduces `autoconnect=yes`; see [Networking](#networking).

**A desktop entry whose `TryExec` names `/usr/bin` is hidden, not broken.** Two
in `~/.local/share/applications/` pointed there for binaries that *are*
installed at Nix paths; the launcher simply stopped listing them. Use a bare
binary name so `PATH` resolves it. `grep -rlE '^(Exec|TryExec)=/usr/' ~/.local/share/applications/`
finds the rest.

**`~/.config/autostart/` does nothing here** — `xdg-desktop-autostart.target` is
inactive under mango, which uses `autostart.conf` instead
([0005](adr/0005-one-owner-per-daemon.md)). An entry added there is not a second
owner, it is a no-op; the directory was deleted on 2026-08-25 rather than fixed.

**Deleting under `~` does not return the space.** `@home` carries the live
snapper timeline, so 26 GB of Arch-era `~/.cache/paru` stayed referenced and
`df` barely moved. It comes back as snapshots age out. See
2026-08-25.

---

## nixpkgs and NixOS

**There is no `/bin/bash`.** `/bin` holds one entry, `sh`. A `#!/bin/bash`
shebang fails with exit 127 and *silence* — a waybar `custom/*` module whose exec
exits 127 renders as an empty module, which looks like the module being absent.
This bit 13 scripts after the migration. `checks/static.sh` now fails the build
on it.

**Wrapped binaries break `pkill -x`.** nixpkgs ships wrappers, so `comm` becomes
`.foo-wrapped`, truncated by the kernel to 15 chars (`.elephant-wrapp`). `-x`
matches `comm` exactly, so it silently matches nothing — every mango reload
leaked another elephant, and every swaync restyle hit an instance that never
died. Match the command line: `pkill -f 'bin/elephant$'`, `pkill -f '^swaync( |$)'`.

> **The `$` anchor only holds for a process invoked with no arguments.**
> `pkill -f 'bin/wlogout$'` matches nothing against
> `…/bin/wlogout -b 6 -c 12 …`, because `-f` matches the *whole* command line
> and the arguments come after the path. It exits 1 and leaves the process
> running — which, for a fullscreen layer-shell overlay, means it stays on
> screen. Drop the anchor when the process takes arguments.

**`pgrep -x` fails the same way, and `pgrep -f` cannot replace it in a guard.**
All four `pgrep -x` targets in the repo were dead: `elephant`, `kdeconnectd` and
`awww-daemon` are wrapped, and the compositor's `comm` is `mango` — `mangowm`
was never a process name. The read-only form fails in *both* directions: a guard
that never matches respawns a running daemon, and a liveness test that never
matches exits a healthy loop (`scratch-watch.sh` could only ever `exit 0` on
reconnect). `phone-status.sh` reported "KDE Connect not running" against a
kdeconnectd that had been up since boot.

Swapping in `-f` is a trap here, because a guard's own shell is a match:
`pgrep -f 'kdeconnectd$' || kdeconnectd` matches the shell running that very
line — the cmdline ends in `kdeconnectd` — so the guard is now permanently
*true* and the daemon never starts. Anchoring on `bin/` does not help either;
`kdeconnectd` and `mango` are invoked bare, so their cmdline carries no path.

**Match `comm` with a regex that tolerates the wrapper's dot:**

```bash
pgrep '^\.?kdeconnectd' >/dev/null || kdeconnectd   # matches .kdeconnectd-wr
```

`comm` never contains the guard's own command line, so it cannot self-match, and
the `\.?` prefix plus prefix-matching absorbs both the wrapper dot and the
15-char truncation. Keep `-x` only for a binary that is genuinely unwrapped, and
anchor it (`pgrep -x mango`) — a bare prefix would also match `mangohud`.
`checks/static.sh` resolves every `-x` target through both profiles and fails on
a wrapped one.

**`buildEnv` collisions abort the whole generation.** Two packages owning one
file path is the failure to expect when adding packages. If one supersedes the
other, drop it; if they merely contend, use `lib.hiPrio` on the **winner** —
`lib.lowPrio` on the loser does nothing when the priorities are already equal.

**`cc` and `c++` are clang**, the reverse of Arch. `packages.nix` carries
`(lib.hiPrio clang)` to break a collision with `gfortran`, which ships its own
`cc`. `gcc`, `g++` and `gfortran` are all still on PATH.

**The nixpkgs attribute is not the binary name.** `clangd` ships in
`clang-tools`; the Nix LSP is `nil`; there is **no bare `pinentry`** attribute
(removed in favour of the variants, so `pkgs.pinentry` is an eval error).
Searching for the binary's name finds nothing and looks like "not packaged".

**`share/<pkgname>` is not in `environment.pathsToLink`**, so a package's data
files exist *only* at its versioned store path —
`/run/current-system/sw/share/wlogout/` does not exist even with wlogout
installed. Never hardcode `/usr/share/...`. The one safe absolute path is one
**computed at build time**: `programs.wlogout` interpolates each vendored PNG as
its own store path. GTK draws its missing-image box for a failed CSS `url()`
**without logging a warning**, so this class of bug is invisible in logs — it was
reported as "the icons are just square boxes".

**`programs.zsh.enableCompletion = false` deletes every package's completions,
not just the second `compinit`.** The NixOS module reads
`environment.pathsToLink = lib.optional cfg.enableCompletion "/share/zsh"`, so
turning the flag off — done here to drop a duplicate `compinit` worth 219 ms —
also unlinked `share/zsh` from **both** profiles, and dropped
`nix-zsh-completions` with it. `/run/current-system/sw/share/zsh` and
`/etc/profiles/per-user/henry/share/zsh` simply did not exist, leaving one live
entry in a 20-entry `fpath`: zsh's own store path. Completion therefore still
*worked* — `git`, `ssh`, filenames, command names all come bundled with zsh —
so the failure looked like "tab complete is broken sometimes" rather than
anything missing. `_nix`, `_systemctl`, `_cargo`, `_gh` and ~330 others were
gone. Both are restored explicitly: `environment.pathsToLink = [ "/share/zsh" ]`
in `hosts/thinkpad`, and the two completion packages in
`modules/home/packages.nix`. **A non-existent `fpath` entry is not an error**,
so the tell is the directory, not a message:

```bash
ls /run/current-system/sw/share/zsh/site-functions | wc -l   # 0 = broken
```

**nixpkgs packages ship user units that Arch's did not, and they auto-start.**
nixpkgs' swaync ships `swaync.service` with `WantedBy=graphical-session.target`,
which raced the `exec=` line in `autostart.conf`; autostart won the bus name and
the unit died five times into `start-limit-hit`. Notifications worked throughout,
which is why it went unnoticed. It is masked via
`xdg.configFile."systemd/user/swaync.service".text = ""` — an empty unit file
loads as `masked`, and `source = "/dev/null"` is rejected by pure evaluation.
**Before trusting autostart to be the only owner**, check
`ls $(nix eval --raw nixpkgs#foo)/share/systemd/user/`. See `docs/adr/0005`.

**`Restart=` without `StartLimitBurst=` is a loaded gun.** A `rclone` unit
reproduced an Arch path that only worked by accident, could not create its mount
point, and retried every 5 s — 230 restarts, escalating past HTTP 429 into an
**account-level abuse restriction on Proton's side**. The damage landed on
someone else's service, not on this machine. Any unit that talks to a remote API
needs a start limit. See `docs/adr/0006`. (Proton Drive was removed outright;
don't re-add it — Proton blocks rclone's access method.)

**The node named `nixpkgs` in `flake.lock` is not our nixpkgs.** Node names are
allocated in traversal order, so `claude-desktop`'s un-`follows`ed nixpkgs took
the bare name and ours is **`nixpkgs_3`**. Reading
`.nodes.nixpkgs.locked.rev` therefore reports the wrong flake's pin — and
convincingly, since it is a real nixpkgs rev that moves on its own schedule. It
made a `nix flake update` that had bumped our nixpkgs by 18 months of aliases
look like it had changed nothing. Resolve the name first:

```bash
jq -r '.nodes[.nodes.root.inputs.nixpkgs].locked.rev' flake.lock
```

**A package at upstream's newest release can still be missing a symbol.**
Minecraft Bedrock 1.26.x dies on launch with `Signal 11`. The signal is the
fallout; the cause is the line above it — `dlopen failed: cannot locate symbol
"pthread_sigmask" referenced by libminecraftpe.so`. The load fails and the client
then dereferences the null handle, so every version crashes identically and the
backtrace names only the client. The launcher's Android libc shim exports 54
`pthread_*` symbols and not that one, on 1.7.6 *and* on `libc-shim` master, so
bumping nixpkgs cannot fix it (mcpelauncher-manifest#1970). The fix is the
`mcpelauncher-updates` mod in `~/.local/share/mcpelauncher/mods/`, which patches
the game's pairip libraries in place at load. That tree is runtime-owned, so it
cannot become an `xdg.configFile`; it survives a rebuild, not a fresh install.

Two more once it loads: only the **UI** wrapper adds the client's bin to PATH, so
running the client's store path directly fails Xbox login with
`mcpelauncher-webview not found`; and the profile's `arch` must be `x86_64`,
because the client is 64-bit only and `x86` loads nothing. The
`Failed to load host libfmod` warning is noise — the launcher never loads it.

**A flake input can pin a builder nixpkgs has deleted.** `nix flake update` moved
nixpkgs past 2026-09-15, where `buildGo125Module` became a throw (Go 1.25 is
end-of-life). sops-nix still builds `sops-install-secrets` with it, and
`sops.package` is reached from `system.activationScripts`, so the entire system
closure fails to evaluate on an error that names a Go version and nothing else —
not the input, not the package. The only identifying detail in the trace is the
store path of the sops-nix source.

The carry is an alias in the overlay, `buildGo125Module = prev.buildGoModule;`,
until upstream migrates. It has to be global: `.override { buildGo125Module = …; }`
on the package throws anyway, because callPackage forces the whole argument set
before the override is applied.

**An unused build input can still break the whole closure.** The 2026-10-02
re-lock moved the default stdenv to GCC 16.2, and `breakpad` 2024.02.16 no longer
links under it: `undefined reference to vtable for
google_breakpad::FastSourceLineResolver::Module`. Hydra has not built it either,
so there is nothing to substitute, and every path to it runs through
`noctalia-shell → noctalia-qs → breakpad`. nixpkgs leaves `CRASH_HANDLER` off, so
the binary never used breakpad — the running closure has never referenced it. The
overlay filters it out of `noctalia-qs.buildInputs`.

Two details cost an hour between them. `prev.noctalia-shell.overrideAttrs` keeps
prev's `noctalia-qs`, so overriding `noctalia-qs` alone changes nothing that
reaches the system; it needs `.override { inherit (final) noctalia-qs; }` first.
And the guards cannot wrap the attrset `overrideAttrs` returns — the attribute
*names* are forced to build the fixpoint, so a top-level `throwIf` reading `old`
is an infinite recursion reported at `make-derivation.nix:236`. They go inside
the `buildInputs` value instead.

Filtering a list that no longer holds the item passes by doing nothing, which is
why the override throws if breakpad is absent, and throws again if a future
version turns `CRASH_HANDLER` on and makes it load-bearing.

`rstudio` 2026.09.0 broke in the same bump and is commented out in
`modules/home/packages.nix` until upstream builds again: `undefined reference to
boost::urls::grammar::detail::condition_cat`, linking `rsession` against boost
1.91. Not a stdenv mismatch — boost and rstudio are both on GCC 16.2 — so there
is no local override to align, and `.override { stdenv = gcc15Stdenv; }` would
leave the symbol in a boost still built by GCC 16. Nothing else here uses R.

Both were found the same way: `nix flake check --keep-going`, which reports every
root failure instead of stopping at the first. Without it rstudio was invisible
behind breakpad. Watch the exit status rather than the tail of a pipe — `nix
flake check 2>&1 | tail` exits 0 on the *tail*, which is how the first run of
this looked clean.

---

## Desktop

### The greeter comes up with boot text drawn through it

`services.greetd.useTextGreeter` defaults to **false**, and nothing warns when a
TUI greeter is configured without it. tuigreet then runs on a greetd.service with
no TTY handling whatsoever — no `StandardInput/Output=tty`, no `TTYPath`, no
`TTYReset`/`TTYVHangup`/`TTYVTDisallocate`, the set `getty@` has always carried.
So greetd never claims tty1 and never clears it: the greeter paints on top of
whatever the boot left on that VT, and systemd keeps writing `[ OK ] Started …`
over it afterwards, because `/dev/console` is the *foreground* VT — the one the
greeter is on.

`Type=idle` is already set and does not help. It delays the start until jobs
are dispatched or 5 s pass, whichever comes first, and does nothing about output
after that. Everything dispatched later still lands on the greeter:

```
02:16:56 Started greetd.service          ← tuigreet starts drawing
02:16:57 Started libvirt legacy monolithic daemon.
02:16:57 Reached target Graphical Interface.
02:17:02 Started Session 1 of User greeter.
02:17:03 Started RealtimeKit Scheduling Policy Service.   ← still printing over it
```

The fix is one line — `useTextGreeter = true` — and it is the module's own switch
for "this greeter is a TUI", not a workaround.

**Don't reach for `quiet` or `boot.consoleLogLevel` here.** The kernel was not the
source: console loglevel is 4, so only priority < 4 reaches the VT, and

```console
$ journalctl -b -k -p err --since <greetd start> --until <login>
-- No entries --
```

Lowering it would have changed nothing while looking exactly like a fix that
worked, because the next boot's timing varies anyway. Check which stream is
actually printing before quietening either one.

### The session's output prints there too, which is a different bug

`useTextGreeter` is also what causes this one, and it looks identical from the
chair. It puts `StandardInput/Output=tty` and `TTYPath=/dev/tty1` on
greetd.service — correct, tuigreet needs them — and tuigreet's `--cmd` session
then **inherits those descriptors**. So the compositor and every child it spawns
write into the greeter's VT text buffer:

```console
$ ls -l /proc/$(pgrep -x mango)/fd/{0,1,2}
… /proc/3110/fd/0 -> /dev/tty1
… /proc/3110/fd/1 -> /dev/tty1
… /proc/3110/fd/2 -> /dev/tty1
```

It is invisible while mango holds the VT in graphics mode. It shows at the
edges of a session — as the compositor comes up over the greeter, and under the
greeter afterwards, because `TTYVTDisallocate` clears tty1 once at
**greetd.service start** and never again. Read `sudo cat /dev/vcs1` to get the
buffer verbatim; it is full of xkbcomp warnings, swaync's startup banner,
`libva info:` lines and GTK warnings — a page of session noise that looks like a
boot-time fault because it is sitting on the login screen.

**The tell that separates the two:** PID 1's overdraw is `[ OK ] Started …`
lines. This one is application text. Fixing the first does nothing for the
second.

`modules/system/desktop.nix` wraps the session in `systemd-cat --identifier=mango`
rather than redirecting to `/dev/null` — the noise is diagnostic, and two real
faults were found in it the first time it was read (the GTK4 theme import below,
and `gtk-interface-color-scheme`). It is `journalctl -t mango` now.

### A script committed 644 is a dead key

**Nix preserves the mode bit, so a `bind=` pointing at a non-executable script
does nothing and exits 0.** Found on 2026-08-14 while adding `notify.sh` for the
noctalia mode: the file was written without `chmod +x`, arrived in the store as
`-r--r--r--`, and `CTRL+ALT+\` silently stopped toggling notifications. Nothing
logged, and the file is present and correctly linked in `~/.config` — the same
tell as the section below.

`checks/static.sh` had asserted exactly this for scripts named by a **waybar
config** since the empty-module bugs, but not for the far larger set named by
`bind=` and `exec=` lines in the mango tree. It now covers both, and fails on a
reference count of zero rather than passing by matching nothing.

The tell: `ls -lL ~/.config/mango/scripts/<name>` — the target's mode, not the
symlink's. Git tracks the bit, so `chmod +x` needs a `git add` to take effect in
the build.

### `swaync-client` against a masked unit exits 0

swaync is the tiling mode's daemon and is not started in noctalia mode; between
2026-08-24 and 2026-08-27 it was started in neither, and its unit is masked on
top of that (`docs/adr/0051`). `swaync-client -D -sw` then prints

```
GDBus.Error:org.freedesktop.DBus.Error.NameHasNoOwner: Could not activate remote
peer 'org.erikreider.swaync.cc': activation request failed: unit is masked
```

on **stderr** and **exits 0**. Three keys (`CTRL+ALT+\`, `CTRL+ALT+BackSpace`,
`SUPER+SHIFT+N`) and two control-centre rows were dead that way for a month: the
rows rendered `?`, which means "I could not ask" and is correct, and the keys
reported success.

The daemon is `wayle notify` in tiling and noctalia's own IPC in noctalia.
`checks/static.sh` now fails on any script naming `swaync-client`.
`docs/adr/0047`.

### noctalia and swaync cannot both run

**The second claimant of `org.freedesktop.Notifications` does not error — it
just never receives a notification.** noctalia-shell is a notification daemon as
well as a bar, so `noctalia/autostart.conf` kills swaync and does not restart it,
and `tiling/` restarts swaync and stops the noctalia unit. ADR 0005 is the
general rule; ADR 0020 is this instance.

Verify by ownership, never by "it started": `busctl --user status
org.freedesktop.Notifications` names the owning PID. `notify-send test` then
identifies which one drew it.

### The noctalia bar does not appear, and nothing says why

**Two failures stack, and the second one hides the first.** Seen 2026-08-15
after switching tiling → noctalia → tiling → noctalia: the second entry produced
no bar at all.

The crash is `Failed to create wl_display (No such file or directory)` followed
by Qt's `no Qt platform plugin could be initialized` and `SIGABRT`, ~700 ms in.
It means the **systemd user manager's** `WAYLAND_DISPLAY` names a socket that is
not there — the manager has its own copy of the environment, published once by
`dbus-update-activation-environment --systemd --all` in
`universal/autostart.conf`, and it does not track the session afterwards.
Compare the two directly; they are supposed to agree:

```sh
systemctl --user show-environment | grep -E 'WAYLAND_DISPLAY|^DISPLAY|MANGO'
printf '%s %s %s\n' "$WAYLAND_DISPLAY" "$DISPLAY" "$MANGO_INSTANCE_SIGNATURE"
# repair, from inside the session:
dbus-update-activation-environment --systemd WAYLAND_DISPLAY DISPLAY MANGO_INSTANCE_SIGNATURE
```

⚠️ **Running a nested mango is how the environment goes stale.** The nested
instance runs the live `universal/autostart.conf`, whose first line republishes
*its* `WAYLAND_DISPLAY` into the user manager; killing it then leaves the
manager pointing at a socket that no longer exists, and every user unit started
afterwards connects to nothing. This is the same trap as the config paths above,
one layer further out — strip the `autostart.conf` sources from any test config.

**Then the unit wedges, and that is what makes it look intermittent.** Five
crashes inside `StartLimitIntervalSec` leave it `failed` with
`start-limit-hit`; after that `systemctl --user start` refuses with "attempted
too often" and exits 1 — but an `exec=` line in an autostart has no reader for
that, so the mode switch reports success and produces nothing. So **fixing the
environment is not enough**: the unit stays wedged until a `reset-failed`.
`scripts/modes/noctalia-start.sh` now does that on every entry into the mode,
waits for the unit to be up *and stay* up, and restores swaync with a
`notify-send` if it does not — losing the bar and the notification daemon at
once is otherwise completely silent.

### noctalia's workspace widget is empty, and the shell says so once

**mango advertises no dwl IPC, so noctalia's Workspace and ActiveWindow widgets
render nothing** — and the Workspace widget is the centre of its bar. The shell
picks the right backend and reports it (`MangoService Initializing MangoWC/DWL
compositor integration (DWL protocol)`), which looks like success; every path in
that backend is then guarded on `DwlIpc.available`, which is false forever.
quickshell probes for the Wayland global `zdwl_ipc_manager_v2`; mango 0.16.0
creates only `wlr_*` globals, and `mmsg`'s JSON socket is a different interface
that noctalia uses for two unrelated calls. One line at startup is the whole
tell:

```sh
journalctl --user -u noctalia | grep 'DWL is not available'
```

**Read this as a method, not a fact about one widget.** `docs/adr/0020` recorded
the integration as working because `MangoService.qml` exists and is selected —
a file's existence stood in for a running system, in the one repo whose first
rule is that those look identical. A compositor integration is only confirmed by
watching the widget change on a tag switch.

### `noctalia-shell ipc call` exits 0 when the name is wrong

**`Target not found.` and `Function not found.` are printed, and the status is
0.** A successful void call prints nothing. So **output is the signal** and the
exit status carries no information — the same shape as the dwl-era `mmsg -s -d` that
broke five scripts here. Test a call by capturing it, never by `&&`:

```sh
out=$(noctalia-shell ipc call launcher toggle 2>&1); [ -z "$out" ] || echo "FAILED: $out"
noctalia-shell ipc show   # the authoritative list of targets and functions
```

`checks/static.sh` pairs every call in `scripts/menus/shell.sh` against the
`IpcHandler` blocks in the shipped QML, matching the function *inside* its own
target — `dock clear` would otherwise pass, because `notifications` declares
`clear`.

**Its logout is inert on this machine.** `MangoService.logout()` runs
`mmsg -s -q`, the flag form mango answers with `{"error":"unknown command"}` and
exit 0. The session menu's logout button is disabled in `settings-pinned.json`
for that reason — a missing button beats one that silently does nothing.

### noctalia's whole mango backend spoke dwl, so the launcher did nothing

`logout()` above was not the only one. **Five calls in `MangoService.qml` used
the `mmsg -s -d <func>` flag form**, including `spawn()` — which is what
`ApplicationsProvider` reaches through `CompositorService.spawn()`, so **picking
an app in noctalia's launcher launched nothing**. Not every time, which is why it
went unnoticed: entries whose `Exec` has quoted or spaced arguments take an
earlier branch (`app.execute()`) and do work.

The overlay rewrites them to `mmsg dispatch` (`docs/adr/0025`), with a check
pairing each verb against mango's own function table — `mmsg` answers an unknown
*function* exactly as it answers an unknown *command*: `{"error":…}`, exit 0.

Two calls are deliberately left in the flag form. `mmsg -g -A` (display scales)
and `mmsg -s -t` (tag switch) need a different call **shape**, not a different
spelling; they are the `DwlIpc` half above, behind the empty workspace widget.

⚠️ **Once a package is overridden in the overlay, `prev.<pkg>` is the wrong
one.** Every consumer must take `final.`, or the system carries two closures and
they are not interchangeable: **quickshell resolves an ipc target by the
`shell.qml` PATH the instance was started from**, so a caller built against the
unpatched derivation gets `No running instances` while the shell is up. The
`lockscreen` wrapper is the one that matters — it would hand every unattended
lock back to swaylock, indistinguishably from noctalia simply being down.
`checks/static.sh` pins the wrapper's copy to the system's.

⚠️ **This also decides where applications live.** `mmsg dispatch
spawn_shell` makes them children of **mango**, in the session scope. The
alternative fix — noctalia's `appLauncher.customLaunchPrefix`, which routes
through `Quickshell.execDetached` — makes them children of the *shell*, inside
`noctalia.service`, whose `KillMode=control-group` means **a mode switch kills
everything launched from noctalia**. Same for anything started from the dock.

### Leaving noctalia mode leaves 1 MB of tmpfs behind, every time

The shell itself exits cleanly — the unit's cgroup takes the whole tree,
`setsid` and all — but **quickshell never removes its instance directory**. Each
start leaves `$XDG_RUNTIME_DIR/quickshell/by-id/<id>/` holding a socket, a lock
and a `log.qslog` that reaches 1.5 MB. It *knows* they are dead: every failed
`ipc call` prints a "Dead instances:" list naming them. 18 of them were holding
11 MB of RAM on 2026-08-16.

`noctalia-start.sh` prunes them before each start, using quickshell's own
`by-pid/` index for liveness rather than parsing the binary lock file.

```sh
du -sh "$XDG_RUNTIME_DIR/quickshell"   # what it has accumulated
```

### Entering noctalia mode used to end night light for the session

`NightLightService.qml` runs **`pkill -x wlsunset` in `Component.onCompleted`,
unconditionally** — on every start, whether or not `nightLight.enabled` is
pinned off. It matches: this repo's wlsunset is unwrapped, so `comm` is plain
`wlsunset` and `-x` hits (the usual `-x`-misses-the-wrapper trap does not save
this — see Scripts).

The reason it stayed dead is systemd's, not noctalia's. **`Restart=on-failure`
does not restart a process killed by SIGTERM**: systemd counts SIGTERM, SIGINT,
SIGHUP and SIGPIPE as *clean* exits. Confirmed with a transient unit —
`Result=success`, `NRestarts=0`. `night-light-run.sh` ends in `exec wlsunset`,
so wlsunset **is** the unit's main process and takes the signal directly.

The unit is now `Restart=always`, with a check on it. noctalia's own journal is
where this was found, and it says so plainly:

```sh
journalctl --user -u noctalia | grep 'Killed stale wlsunset'
systemctl --user show wlsunset -p NRestarts -p ActiveState
```

### A night light left on in tiling was unreachable in noctalia mode

wlsunset's only controls are the `custom/night` bar module and the control
centre's `night` row, and noctalia mode runs neither. Its own night light is
pinned off, so its panel could not reach wlsunset either: the screen stayed
warm, with nothing able to change it, until the next switch back. Nothing logged.

`noctalia-start.sh` stops the unit on **every** entry into the mode — not just a
switch, because the unit is `WantedBy=graphical-session.target` and logging
straight in produced this too — and says so. It stays off on the way out
(`docs/adr/0037`). **`stop`, not `pkill`**: see the entry above.

### Editing noctalia's settings seed changes nothing

**`noctalia/settings.json` is written once, when there is no file at all**, so
on any machine that has entered the mode even once, adding a key there is a
change that lands in the repo and never on the machine — which looks exactly
like a key that does not work. The half that *does* apply is
`noctalia/settings-pinned.json`, merged over the live file on every entry into
the mode (ADR 0022). Put a setting that must hold there; put a preference the
UI may keep in the seed.

**noctalia ignores a settings key it does not know, in silence** — no log, no
fallback, and the UI shows its own default. So a key renamed upstream stops
applying and looks as though it was never set. `checks/static.sh` asserts every
key path in both files still exists in the package's
`Assets/settings-default.json`.

The pin is skipped while the shell is running, because noctalia holds settings
in memory and writes the whole file back. It says so with `notify-send` rather
than reporting a merge that was about to be overwritten.

### A tracked, linked file can still be inert

**The program has to be told where it is, and that pointer is config too.**
Three cases found on 2026-08-09, all of which looked fully converted:
`elephant` read `~/.config/elephant/menus.toml` for its menu path, not the
mango tree the menus lived in; `fsel` read `~/.config/fsel`, reached only by a
hand-made symlink; the bitwarden provider read
`~/.config/elephant/bitwarden.toml`. Every bridge was in `@home` and in no
repo, so all three worked here and on no other machine. All were declared
(ADR 0014); the elephant pair left with walker, and fsel with the launcher
(`docs/adr/0043`).

**`rofi` is the live instance of the same shape.** It reads
`~/.config/rofi/config.rasi` and nothing in the mango tree points at it, so
`modules/home/dotfiles.nix` naming that path is the only thing connecting the
two — and rofi with no config falls back to its built-in theme rather than
erroring. `checks/static.sh` asserts the declaration exists.

The tell is never the filesystem — the file is present and linked either way.
Ask the program: `rofi -no-config -h` must list the expected modes.

### mango

**`mmsg` takes verbs, not flags:** `get`, `dispatch`, `watch`. Anything else
returns `{"error":"unknown command"}` **and exits 0**, so a script on the old
dwl-era `-s -d` form reports success while doing nothing. Five scripts and all
four waybar layouts were silently broken this way. Translations: `mmsg -s -d <f>`
→ `mmsg dispatch <f>`; `mmsg -w -c` → `mmsg watch all-clients`. There is **no
`get layout`** — the symbol lives on the monitor object:

```sh
mmsg get all-monitors | jq -r '.monitors[] | select(.active) | .layout_symbol'
```

Check the return value; it is the only signal available. `checks/static.sh` fails
on a dash-flag `mmsg`.

**`no_border_when_single=1` removes every tiled window's border, not just a lone
one.** Tiling mode ran without an active-window border for as long as it carried
that line; noctalia mode always set it to `0`, which is why the symptom looked
mode-specific. The option is read in `check_hit_no_border()`
(`src/fetch/client.h`), whose first arm is
`ISSCROLLTILED(c) && visible_scroll_tiling_clients == 1` — and `ISSCROLLTILED` is
not a scroller-layout test, it is `!floating && !minimized && !killing &&
!unglobal`, so it holds for ordinary `tile` windows too. With three windows on
screen the counter still read 1 and every tiled border went. Floating windows kept
theirs, which is the tell. Verified on mango 0.16.0 by A/B on the live session at
`borderpx=1`: `0` → 11,190 border-coloured pixels below the bar, `1` → none.
`checks/static.sh` fails on a mode config that sets it back to `1`.

⚠️ **Sample the framebuffer; do not trust `mmsg get`.** Nothing in the client JSON
exposes `bw`, so the only way to see whether a border is drawn is `grim` plus a
pixel dump for the theme's `focuscolor`. A nested instance
(`XDG_CONFIG_HOME=… WLR_BACKENDS=wayland mango`) did *not* reproduce this, so it
also cannot be the whole test — bisect against the running session by re-pointing
`config.conf` at a scratch copy and `mmsg dispatch reload_config`.

**`mango/config.conf` is a symlink, gitignored, and the file it points at *is*
tracked.** `apply_mode` re-points it with `ln -sfn` on every mode switch
(`docs/adr/0040`), so **`readlink ~/.config/mango/config.conf` names the active
mode** — that is the quick way to ask. The real files are `tiling/tiling.conf`
and `noctalia/noctalia.conf`; tracking the link would commit something that
changes on every switch.

It is seeded to `tiling` at activation by `seedModeConfig`, so a fresh clone is
no longer the hole it was. **If it ever goes missing or dangles, mango starts on
built-in defaults — no waybar, no keybinds, nothing logged.** The fallback it
tries first is `/etc/mango/config.conf`, which does not exist on NixOS: the
package ships its default under `$out/etc/`, which never lands at `/etc`.
Confirmed by probe — `HOME=$empty mango -p` exits 1 with
`Failed to open config file: /etc/mango/config.conf`.

⚠️ **It used to be a `cp`, and reverting to one would look like it worked.** A
copy is stale by construction: rebuild while a mode is active and `<mode>.conf`
re-points at a new store path while `config.conf` keeps the old bytes until the
next switch. `checks/static.sh` asserts the `ln -sfn` is still there for exactly
that reason.

**`mango/walker/config.toml` was the same shape and once broke `rebuild`
outright.** Each `autostart.conf` `ln -sf`'d it into place, but it was *also*
tracked, so home-manager wanted to own it: activation died with `Existing file …
would be clobbered`, and `backupFileExtension` does not help. The timing was
the nasty part — the symlink only exists once a mode script has run, so the
failure surfaced after an unrelated mode switch. It is gone with walker (rofi
has one config for every mode), but **when adding anything under
`dotfiles/mango/`, check nothing writes to that path at runtime.**

**Don't `sudo` the mango scripts.** Under sudo `~` is `/root`, so `reload.sh`
fails with `No such file or directory` and `MANGO_INSTANCE_SIGNATURE is not set`
— which looks like a broken install rather than a wrong user — and used to
leave a **root-owned elephant** an ordinary `pkill` cannot kill. `reload.sh`
refuses to run as root; it no longer restarts any daemon, because rofi has
none.

**Runtime state is `${XDG_STATE_HOME:-$HOME/.local/state}/mango`** (`current-mode`,
`waybar-layout`, `waybar-position`, `night-temp`, `last-vpn`). One script
disagreeing about that path made mode switching **one-way with nothing logged**:
`current_mode()` never found the file, fell back to `"tiling"`, and the
"already in that mode" guard exited 0. Running the mode script by hand always
worked, which hid it. If a mode switch goes one-way again, check that every
reader *and* writer agrees. `checks/static.sh` scans for the old path.
See `docs/adr/0003`.

**`bind=` matches on keycode; `bindsym=` matches on keysym.** So
`SUPER+SHIFT,slash` is correct and not dead: shift turns `/` into `question`, but
`bind=` entries resolve to keycodes at parse time and compare without consulting
the shift level. Same for `SUPER+SHIFT,1..9`. **Switching a shifted bind to
`bindsym=`, spell out the shifted keysym** — otherwise it never fires, with
nothing in any log.

**`exec-once` fires only on initial compositor startup, not on reload** — log out
and back in after changing autostart. The `lxpolkit` line there is an Arch
leftover guarded by `command -v`, so it is a permanent no-op; the real agent is
the `polkit-gnome-authentication-agent-1` user service in `desktop.nix`.

**Editing `dotfiles/mango/` needs a rebuild** — `~/.config/mango` is a store path
with `recursive = true` (so the mode scripts can still `cp`), and the files there
are read-only copies. Rebuild, *then* reload.

**The parser is last-wins, and `source=` is processed inline at its position.**
So a key set *after* a `source=` overrides what that file set — which is how
`noctalia/noctalia.conf` sources the shared settings and then disagrees with
them (ADR 0022) — and the same key set *before* it is silently discarded.
Measured on 2026-08-15, not assumed. The probe is cheap, because one option has
a value that can be read back:

```sh
# in a scratch HOME: sub.conf sets `xkb_rules_layout=de`, config.conf sources it
# and then sets `us`. `mmsg get keyboardlayout` names the winner.
printf 'source=./sub.conf\nxkb_rules_layout=us\n' > "$H/.config/mango/config.conf"
```

**mango ignores `XDG_CONFIG_HOME` — it reads `$HOME/.config/mango/config.conf`.**
This bites exactly when testing: a nested instance started with a scratch
`XDG_CONFIG_HOME` reads the **live** config and runs the live `autostart.conf`
against the running session, killing waybar and starting daemons. Override
`HOME`, not `XDG_CONFIG_HOME`, and strip the `autostart.conf` sources from the
test config.

**`mango -p` validates whichever config it had when it saw the flag, and the
wrong flag order reports success.** `getopt` returns on `-p` mid-parse
(`mango.c:7797`), so `mango -p -c FILE` never sees `FILE` — it checks the live
`~/.config/mango/config.conf` and exits 0. **`mango -c FILE -p` is the working
form.** And `-p` exits 1 for an unknown *keyword* but **0 for a `source=` it
cannot open** (the return value is discarded, `parse_config.h:3248`), printing
`[ERROR]: Failed to open config file: …` to stderr instead. So a bad `source=`
is not silent — under `systemd-cat` it is in `journalctl -t mango` — but any
check must read stderr, not the exit status.

**Relative `source=` resolves against the config file's own directory only when
`-c` is used.** With no `-c` it is hard-coded `$HOME/.config/mango/`; with `-c`
it is `dirname` of that path, for nested includes too (`parse_config.h:3276`).
So moving `config.conf` breaks all 20 `source=./…` lines at once. `~/` paths
work everywhere and are the fix if it ever moves.

**Settings are last-wins but binds are first-wins, and a duplicate warns.**
Binds append (`parse_config.h`: `realloc(… count + 1 …)`) and the dispatcher
stops at the first match (`src/mango.c`, `only match the first keybind`), so a
mode conf sourced *ahead* of `universal/bind.conf` does override it — the exact
opposite of the rule for scalar settings two paragraphs up. Do not use it
without a reason: mango also prints `[WARNING] Key binding conflict` naming both
files and both lines for every duplicate, unless both binds carry the `c` flag,
and a handful of those trains the eye to ignore the one that matters. Mode-dependent
keys go through `scripts/menus/shell.sh` instead (ADR 0023); only keys that
exist in *one* mode are bound per-mode.

**A misspelled option IS reported** — a rarity in this repo, so use it. mango
prints `[ERROR]: Unknown keyword: <key>` with the file and line number to
stderr, at parse time. Nothing else validates a conf file, so a nested instance
started against a candidate config is the only pre-flight there is; one that
logs a single deliberately-planted error has accepted every other line.

### swaylock

**swaylock needs a PAM service declared by hand, or it can never unlock.** It is
not setuid and authenticates as the PAM service name `swaylock`; with no
`/etc/pam.d/swaylock`, PAM falls back to `other` = `pam_warn` + `pam_deny`, so
**every password is rejected, correct or not**. sway and river get this free from
`wayland-session.nix`, which `programs.mango.enable` does not import. Declared in
`modules/system/desktop.nix`. The only diagnostic is `pam_warn(swaylock:auth)` in
the journal — the lock screen just says the password is wrong.

**Do not `pkill swaylock` to escape it.** `ext-session-lock-v1` requires the
compositor to **stay locked** if the lock client dies without sending
`unlock_and_destroy` — that is the protocol's guarantee, not a bug. The result is a
permanently blank surface with the session still locked, and `mmsg` has no unlock
command. The ways out are relaunching swaylock on the same `WAYLAND_DISPLAY` to
take over the abandoned lock, or restarting the session.

**That is why lock-on-sleep is swayidle and not a `powerManagement` hook.** A
root sleep hook runs inside `sleep-actions.service`, which is
`RemainAfterExit` and **stopped on resume** — systemd then kills its cgroup,
including the `swaylock -f` the hook forked into it. The result is the
permanently blank locked surface above, arriving every single resume. swayidle
runs in the user session instead, and its `-w` sleep inhibitor also guarantees
the lock is up *before* the suspend rather than racing it.

**Chain the idle lock with `;`, never `&&`.** Only one client may hold an
`ext-session-lock-v1` lock, so the `swaylock -f` on the 5-minute timeout exits
non-zero whenever a manual lock was already up — and with `&&` the
`wlopm --off` after it never runs, leaving the panel lit for the rest of the
idle period. It costs battery and logs nothing. `;` blanks either way, which is
correct in both cases: already locked, or newly locked.

**That same failure is the only way to ask "is the session locked?".** Nothing
here answers the question directly: noctalia's `lockScreen` IPC declares one
function, `lock()`, and returns before its lock surface exists; `mmsg get` has
no session-lock subcommand; `loginctl`'s `LockedHint` tracks the logind *signal*
and not the Wayland protocol, so it is unchanged by either locker. What does
answer it is running swaylock and reading the exit status — it prints
`Failed to lock session -- is another lockscreen running?` and exits non-zero
only once the compositor has confirmed the session locked. `lockscreen` uses
exactly that as the proof behind the noctalia lock (`docs/adr/0024`), which is
also why it is safe: the probe's *success* case is a lock too.

**`programs.swaylock.package` must be `null` here.** `desktop.nix` installs
**swaylock-effects** system-wide and declares PAM for it, but the home-manager
module defaults to installing plain `pkgs.swaylock`, which lands *earlier* in
PATH and would shadow it. Measured against swaylock 1.8.6: it **lacks
`clock`, `timestr` and `datestr`** (though it does have `indicator` and
`indicator-idle-visible`), so the clock — the entire reason the lock screen is
configured this way — just stops appearing.

⚠️ **swaylock exits 0 on an unrecognised config key.** It prints
`unrecognized option '--clock'` and a full usage dump, and the exit status is
`0` for a good config and a bad one alike. Only the output tells them apart.

> **Validating the config without locking the session**: swaylock parses its
> config *before* it connects to the compositor, so
> ```
> env -u WAYLAND_DISPLAY swaylock --config ~/.config/swaylock/config -f
> ```
> exercises the parse and then fails to find a display, locking nothing.
> **Silence means it parsed.** Any usage dump means a key was rejected.

That config is also the *only* one now: `~/.config/swaylock/config` used to be
an **untracked** hand-written file that quietly supplied the theme to every bare
`swaylock -f`, alongside a per-mode copy at `mango/<mode>/swaylock.conf` for
the `--config` binds. All of them are gone.

**Its colours come from `palette.nix`, and did not until 2026-08-16.** The ring
and the keypress highlight were gruvbox *orange* (`d65d0e`, `fe8019`) while the
machine's accent has always been yellow (`d79921`) — hex typed by hand into the
one surface nothing compared against the palette, and the one place where it
cannot be seen next to anything else. Add a colour here as
`opaque gruvbox.<role>` or `wash gruvbox.<role>`, never as a literal.

⚠️ **The `--effect-*` options do nothing without a background image, and
pixelating a solid colour does nothing even then.** Two independent no-ops that
compose into one silent failure:

- `apply_effects` runs on a *loaded image*. With no `-i` and no `-S` there is no
  image, so the effects list is never reached — the flag parses, and is ignored.
- `effect_pixelate` averages each block, and the average of a uniform field is
  that same value. `--effect-pixelate 40` over `color=282828ff` returns
  `#282828`.

So `swaylock --effect-blur 7x5 -f` on a colour-only config exits 0, renders
identically, and looks exactly like a broken build. **Effects need `-i` or
`-S`.** The background is now a pre-generated pool instead (`docs/adr/0018`).

**Backgrounds are resampled with `CAIRO_FILTER_BILINEAR`.** Any image that is
not 1:1 with the output gets its edges softened, which destroys a deliberately
blocky image without erroring. The pool is generated at the panel's native
1920×1200 so the scale factor is exactly 1.

⚠️ **`#282828` is neutral, so a background "shade" of it must have R=G=B.**
A ramp built from stops like `#322e2b` (R50/G46/B43) is a warm brown: it reads
as a *different colour* rather than a lighter or darker version of the
background, however carefully its mean is matched. This survived four rounds of
brightness adjustment because brightness was never what was wrong. The
derivation asserts neutrality per tone rather than trusting the ramp.

**A weighted ramp clumps.** Sampling five tones with one of them at 68% put
**236 of 360 blocks into a single connected region** — two thirds of the screen
as one flat mass, which defeats the point of a texture. The generator bans a
block from matching any of its eight neighbours; below about nine tones there
are too few colours left for that constraint to be satisfiable.

⚠️ **`services.fprintd.enable` switches the sensor on for every pam service, not
just the ones named.** `security.pam.services.<x>.fprintAuth` defaults to
`config.services.fprintd.enable`, so one `enable = true` put `pam_fprintd` into
all 23 stacks — `swaylock` and `login` included. Setting it explicitly on `sudo`
looks like scoping and is pure no-op; only an explicit `fprintAuth = false`
removes it. This was written into this file as "sudo only, deliberately" while
the opposite was live. **Verify with
`grep -l pam_fprintd /etc/pam.d/*`, never from the Nix.**

That matters because `pam_fprintd` is `sufficient` at order 11400, *ahead* of
`pam_unix` at 11700, and a password-first UI cannot survive that ordering.
swaylock has no way to render the sensor's prompt, so the first `timeout`
seconds of every unlock swallow the typing with no indication why — 30 s at the
default. Inverting the order is not a fix either: it only polls the sensor after
that submits an *empty* password, making the gesture "press Enter, then touch"
([swaylock#61](https://github.com/swaywm/swaylock/issues/61)). `greetd` inherits
the problem by substacking `login`, so it needs `login.fprintAuth = false` rather
than a rule of its own.

`fprintAuth` is therefore off on `swaylock` and `login`, and left on everywhere
else — `sudo`, `su` and the rest are terminal prompts, where the order reads
correctly and Ctrl-C falls through. Doing it properly on the lock screen means a
different locker (hyprlock has native fprintd support) or the third-party
`swaylock-fprintd` wrapper, which is not in nixpkgs — both judged more churn than
the feature is worth.

**Ctrl-C at the fingerprint prompt drops to the password prompt** rather than
killing `sudo` — the module catches SIGINT and returns `PAM_AUTHINFO_UNAVAIL`,
which a `sufficient` control passes through to `pam_unix`. Confirmed by hand on
2026-08-11. It is not guaranteed by the code: `signalfd` only receives *blocked*
signals and the module never calls `sigprocmask`, so this works because `sudo`
happens to block SIGINT across the PAM call. Re-test it if the fall-through ever
stops working; don't assume the module owns the behaviour.

**`pam_fprintd`'s `timeout` fires once; `max-tries` is a different counter.** A
timeout returns `PAM_AUTHINFO_UNAVAIL` immediately rather than consuming a try,
so an *untouched* sensor costs `timeout` seconds and no more — upstream's default
30 s is the stall people mistake for a hang. `max-tries` (default 3)
only counts real `verify-no-match` results, i.e. a finger that was read and
rejected, each getting a fresh `timeout` window. Set via
`rules.auth.fprintd.settings`, **not** `args` — `args` is computed from
`settings` by the NixOS module, so defining it directly collides. Confirm the
result with `grep ^auth /etc/pam.d/sudo`; the tokens are `timeout=` and
`max-tries=` (hyphen, not underscore, despite the log text saying `max_tries`).

### rofi

`rofi` replaced walker and elephant on 2026-08-14; that record was retired with
them. The walker findings are kept below the rule, because the shape of each
recurs.

**rofi 2.0 is a layer surface, so `windowrule` cannot reach it.** It passes the
literal `rofi` as its `zwlr_layer_surface` namespace, which is why
`layerrule=...,layer_name:rofi` works — and why `mmsg get all-clients` does not
list it while it is on screen. mango therefore draws **no border** on it. The
`windowrule=isfloating:1,appid:Rofi` / `isnoborder:1,appid:Rofi` pair in
`universal/rule.conf` could never match and was removed on 2026-08-20;
`isnoborder` in particular said the opposite of what happens.

The consequence is visual and was live for months: with `shadows=0` and
`layer_shadows=0`, rofi's own 1px `@overlay` edge was the only thing separating
the menu from a window the same colour behind it — 1.67:1 in gruvbox, 1.45:1 in
nord. It wore `@subtext` from then until 2026-08-21 and wears **`@accent`**
now, which is mango's own `focuscolor` — one ring, drawn by whichever surface
is in front, since the launcher became a rofi mode (`docs/adr/0043`).
**3.87–9.23:1 against `@base` across the five schemes in service.** `bg3` and
`comment` are calmer still and both collapse to 1.69:1 in nord, which is the
border `@subtext` replaced.

**Global options belong on the command line when only one caller wants them.**
The launcher passes `-matching fuzzy -sort -sorting-method fzf`; the hand-built
`-dmenu` menus want rofi's default matching over their short, hand-ordered
entries. No count here on purpose — it was nine when this was written and is
fourteen now; `checks/static.sh` counts them and holds the floor. Unlike `-l` below, the command line **does** win for
these — `rofi -matching fuzzy -dump-config` is the cheap way to see which way
a given option resolves, and it is worth checking per option rather than
assuming either direction.

**A `-dmenu` window never shows a mode switcher, so styling it is invisible
work until it isn't.** `-dmenu` is single-mode; `-show drun` draws tabs for
every mode in `modes:`. Until the launcher became one, no window here had ever
rendered a `mode-switcher`, so it carried no rule and would have come up on
rofi's own metrics. Its widgets are `mode-switcher` and `button` (plus
`button selected`), and they resolve colour through the `*` role sweep either
way — so the failure would have been shape, not colour, which is the harder
one to notice.

**`lines` is a fixed height, `dynamic` does not fit to contents, and `-l` is
ignored.** All three at once, which is why every menu on this machine was
twelve rows tall whatever it held — a two-entry mode picker with ten blank rows
under it, and the control centre paging the moment it grew a thirteenth row,
silently.

- **`dynamic: true` is about FILTERING.** rofi's own docs: "True if the size
  should change when filtering the list, False if it should keep the original
  height." It does not size the list to its entry count. The comment in
  `config.rasi` claimed the opposite for as long as the file existed.
- **`-l` loses to the theme.** On rofi 2.0 `listview { lines: … }` overrides the
  command line, so a caller's `-l` is accepted, ignored, and exits 0.
  `rofi -dump-theme -l 15` still prints `lines: 12`, which is the cheap way to
  see it. **`-theme-str 'listview { lines: N; }'` is the override that works.**
- Measured 2026-08-20 at 2, 6, 15 and 30 entries: the window never changed size.

`lib.sh`'s **`rofi_menu <max>`** is the one place that override lives — entries
on stdin, sized to them, capped at `max`. Every hand-built menu goes through it
and `checks/static.sh` asserts so, along with "no caller passes `-l`" and "the
control centre's row count stays under its ceiling". The theme's `lines: 12`
remains, and is now only the cap for `rofi -show drun|run|window|calc|emoji`,
where the list is unbounded and paging is the honest answer.

**`recursivebrowser`'s `filter-regex` is a PRUNE, and its default is load-bearing.**
`recursivebrowser.c:201` `continue`s on a match *before* the `DT_DIR` case that
queues the descent, so a matched directory is never entered — the regex controls
the walk, not just what is listed. rofi's default is `^(\..*)`, which is what
keeps the whole dot-tree out: `$HOME` holds 1,030,333 entries and the mode walks
190,640 of them, because `.cache` (92,914) and `.local/share/Steam` (186,560)
are pruned by it. **Overriding `filter-regex` without carrying that alternation
forward turns a 0.33s walk into the other 840,000 entries**, and nothing reports
it — the list just keeps filling. `SUPER+SHIFT+E` extends it rather than
replacing it.

Its two siblings are not the same lever: `directory` sets the root (default
`$HOME` already) and `command` is the *opener*, not the walker, so an `fd` with
better ignore rules cannot be substituted. Broken symlinks cost a `Failed to
stat` warning each on a stderr no keybind reads — `~/Games`' Wine `dosdevices`
were 1,940 of them, hence `Games` in the alternation.

**rofi does not read GTK's icon theme.** `config.icon_theme` is its own
setting, and with it unset the fetcher's fallback chain is `{"Adwaita",
"gnome"}` plus hicolor (`rofi-icon-fetcher.c:276`) — not the Papirus-Dark that
GTK, the bar and everything else here wear. The launcher spent 2026-08-29
drawing Adwaita art beside Papirus and resolving 90 of 97 desktop entries
instead of 96, and nothing said so: an unresolved name draws a blank icon
column, never an error. `rofi/icons.rasi` is generated from the palette by
`modules/home/dotfiles.nix` and `@import`ed by `config.rasi`, so the name has
one owner. Scheme-level, not per mode — the icon set is an artefact
(`docs/adr/0034`), which is why it is a second file rather than a line in
`colors.rasi`.

**Window mode looks an icon up by the lowercase appid, with no desktop-file
step.** `wayland-window.c:610` calls `rofi_icon_fetcher_query(g_utf8_strdown(
app_id))` and stops there, so an appid that is not itself an icon name draws
nothing — `zen-beta`, `dev.zed.Zed`, `yazi`, `thunar-*` and every Steam game.
Measured 2026-08-29: 44 of 97 candidate appids before the icon theme was named,
55 after. drun does not share the problem because it reads the desktop file's
`Icon=`. The fetcher *can* read a `.desktop` file, but only when handed an
**absolute path** (`rofi-icon-fetcher.c:575`, nested under
`g_path_is_absolute`), which window mode never does — a hand-built dmenu row
can, and that is the other way to solve this. The way taken instead:
`modules/home/waybar.nix` aliases the appids the theme has no name for into
`hicolor/scalable/apps/<appid>.svg`, sourced from `themeIcons` so an alias
follows the scheme. A package rather than an `xdg.dataFile`, so a name another
package already owns is a buildEnv collision at `nix flake check` instead of one
of the two silently winning — which is why `equibop` is *not* aliased, it ships
its own. `checks/static.sh` asserts the floor: every appid in `app-icons.json`
resolves, however it resolves.

**dmenu silently ignores the row options script mode honours.** Both parse the
`\0key\x1fvalue` syntax, and both accept `icon` — that is how
`minimized-menu.sh` draws per-window art. `nonselectable` and `permanent` are
**script-mode only**. Measured 2026-08-29 with one `nonselectable` row under
`-auto-select`: dmenu selected it, script mode did not, and neither logged
anything. So a `-dmenu` separator row is pressable and every menu here absorbs
that at the handler — `control-center.sh` returns 1 on one and re-renders,
which is visibly nothing happening. `-modes "name:script"` is the way out, and
it also brings `keep-selection` (the control centre's loop respawns rofi per
action, so the cursor returns to row 1 and the filter clears) and `ROFI_DATA`.

**`terminal:` names one binary, and the default goes looking.** rofi ships
`terminal: "rofi-sensible-terminal"`, a script that walks eighteen names in its
own order — `… alacritty kitty wezterm foot ghostty` — and execs the first that
resolves. foot, kitty and ghostty are all installed here, so it picked kitty,
which is not this machine's terminal. It reads `$TERMINAL` first, and that is
unset in a keybind's environment. `terminal: "foot"` since 2026-08-29, resolved
against both profiles by `checks/static.sh`. Reached by run mode's Shift+Enter
and by ssh mode.

**A rofi plugin listed as its own package is a plugin rofi never loads.**
nixpkgs `rofi` is a `symlinkJoin` over `rofi-unwrapped` that adds
`-plugin-path` pointing into its own `lib/rofi`, so a `rofi-calc` sitting
beside it in `systemPackages` puts the `.so` somewhere nothing looks. `-show
calc` then prints `Mode calc is not found` to a stderr nobody reads and **exits
1** — a dead key. Plugins go through `rofi.override { plugins = [ … ]; }`.
`rofi-rbw` is the exception and not a plugin at all: a standalone front-end
over `rbw`, so it is an ordinary package.

**Ask the binary, not the Nix:** `rofi -no-config -h | sed -n '/Detected
modes/,/^$/p'` lists what actually `dlopen`ed, which is what `checks/static.sh`
now reads. Under the build sandbox it needs `HOME` set to something writable —
with `/homeless-shelter` rofi fails to create its runtime dir, warns, and
prints **no help at all**, which looks like "the scan is broken" rather than
"rofi is broken".

**`-no-custom` cannot be un-set.** Setting it in `config.rasi` applies to every
`-dmenu` call, and `-no-no-custom` on the command line is accepted, ignored,
and exits 0. So it goes at the call site: every fixed-choice menu passes it,
and the password prompt in `menus/network-menu.sh` must not — with it, Enter
returns nothing and `nmcli` runs with an empty password.

**`-kb-custom-N` is the only accept key a `-dmenu` caller can tell apart, and
its answer is the exit status.** `Enter`, `Shift+Enter` and `Ctrl+Enter` all
exit **0** on their own default bindings: `modes/dmenu.c` gives `MENU_OK`
(accept-entry), `MENU_CUSTOM_INPUT` (accept-custom) and `MENU_OK |
MENU_CUSTOM_ACTION` (accept-alt, without `-multi-select`) the same `retv =
TRUE`, and only `MENU_CUSTOM_COMMAND` becomes `10 + n`. So a second action on
one row is a `-kb-custom-N` or it is nothing — **10–28 across the nineteen
of them, 0 accept, 1 cancel** (`rofi-dmenu(5)`).

Then the status has to be *read*. Every menu here is written
`choice=$(… rofi …) || exit 0`, which takes 10 for a cancel and closes the menu
instead of acting — the key looks unbound. `menus/control-center.sh` captures
`$?` into a `case` instead, for `Ctrl+Enter` on the weather row.

**Check the key is free, and free it if it is not.** rofi ships `Control+Return`
as `kb-accept-custom`; binding it on top is not ignored and not a warning —
`source/keyb.c` collects `Binding \`Control+Return\` is already bound` into an
**error dialog drawn where the menu should be**. `rofi -list-keybindings`
prints the configured table (it lists a clash rather than rejecting it, so read
it before binding, not after), and **an empty string unsets**:
`-kb-accept-custom ""`, per `rofi-keys(5)` → *Unsetting a binding*. Both go on
the command line, so the default survives in `menus/network-menu.sh`, where the
typed string is the answer.

Unsetting it costs the control centre nothing, because that call passes
`-no-custom`: with `only_selected` set, `MENU_CUSTOM_INPUT` falls into the
`else` branch of `dmenu.c` and just restarts the view. `Ctrl+Enter` there had
always done nothing, and had never said so.

There is no `-mesg` hint on the panel saying the key exists: one was tried on
2026-08-24 and removed the same day. A standing line of instructions above a
list whose point is to *show state* is the menu explaining itself instead of
reporting. `weather.sh panel` passes a `-mesg` and it is a **reading**, not a
hint — which is the distinction, not "no menu may pass one".

**rofi sizes the window from the configured font's metrics, not from the
rendered layout, so a markup span larger than `font:` gets clipped.** The
weather panel's header is eight lines with an `xx-large` temperature on the
first; the eighth line came up cut in half by the listview drawn over it.
Nothing logged, and the reading it clipped (sun times) is the one a reader is
least likely to miss. Measured both ways on 2026-08-26 — the same eight lines
with no span render whole — so it is the span, not the line count.

The fix is bottom padding on `message`, in `config.rasi` rather than at the call
site: `padding: 6px 10px 12px 10px`. One caller today; a future `-mesg` with no
oversized span gets 6px of extra room, which is not wrong.

`message textbox { text-color: @text; }` is a **valid rofi 2.0 selector** and
overrides the global `textbox` rule — worth knowing, because the message widget
is a box whose child is the textbox, and `message { text-color: … }` does not
reach it past a rule that names `textbox` directly. `rofi -dump-theme` prints
the resolved tree and is the cheap way to check a selector parses at all.

**Pinning `mainbox { children: [ ... ] }` silently deletes every widget
left out.** rofi's default is `[ inputbar, message, listview, mode-switcher ]`.
Writing `[ inputbar, listview ]` to "keep it simple" removed the message bar —
and **rofi-calc renders its live result through the mode `_get_message` hook**,
which `rofi_view_reload_message_bar` (view.c:208) returns from immediately when
`mesg_box` is NULL. So `SUPER+=` stopped previewing while typing, while Enter
went on working, because `calc-command` fires off the entry, not the message.
Nothing logged. Do not pin the list except to reorder something: the
default order is already the wanted one, and an empty message bar is
`widget_disable`d, so it costs the dmenu menus no space.

**rofi's built-in defaults are Solarized light, and they show through.** A rasi
that styles only the widgets it names leaves every other one resolving through
rofi's default *role* variables — `urgent-background` is `#fdf6e3`, cream on a
gruvbox window, and it surfaces the first time a menu marks a row urgent.
Override the roles (`normal-*`, `selected-*`, `active-*`, `urgent-*`,
`alternate-*`) rather than the widgets. The check is
`rofi -dump-theme | grep 'var(lightbg)\|var(blue)\|var(red)'` — anything left
is a widget still wearing the default theme.

**rofi's shipped `gruvbox-dark` is a different gruvbox from this system's.**
2px borders against `borderpx=1`, an `#a89984` border matching nothing here,
`#665c54` selection where the terminals use `#504945`, and alternate rows
striped `#32302f`. Importing it looked like the cheap way to match and was
the reason the menus read as foreign. The palette is
`modules/home/palette.nix`; see ADR 0009.

**Sizing comes from the theme, not the caller.** rofi has no `--maxheight`;
`listview { dynamic: true; lines: N; }` makes `lines` a ceiling and shrinks to
fit. Porting a walker call by dropping `--maxheight` is correct, not lossy.

**walker 2.x could not draw a window without elephant, and exited 0 about it.**
This is why the migration happened, and it is the sharpest example in this file
of the same silent failure. With the walker daemon up and only elephant
killed, `walker -d` **exits 0, prints nothing, opens no window** — from the
keyboard indistinguishable from pressing Escape, and from a script
indistinguishable from a cancel, because every caller reads a cancel as
`|| exit 0`. The control run with elephant up exits 124, the window still being
open when the timeout fires. **Two exit codes that differ only by a timeout is
the whole diagnostic.**

**An elephant provider whose backing CLI was missing did not load, and said
nothing.** `SUPER+P` opened an empty window for weeks because `bitwarden.so`
shelled out to **`rbw`**, which was never declared — while `~/.config/rbw/` had
come across via `@home`, so the config surviving made it look verified. The
same trap is live for `rofi-rbw`, which is a front-end over the same `rbw`:
`rbw`, `wtype` and `pinentry-qt` stay declared in `modules/home/packages.nix`
for it, and the failure looks identical (an empty list, exit 0).

**Every elephant provider was ~26 MB and all were loaded at startup** — Go
plugins each statically linking their own runtime, `symbols.so` alone 144 MB,
all `dlopen`ed by the daemon. Trimming 25 providers to 15 cut the store path
807 → 546 MB and moved RSS **not at all**: 295 MB before, 305 MB after. Recorded
because the prediction that it would fall was written down as though it had been
measured.

**A menu glyph the menu font lacks is a box, not an error, and `fc-list` is the
only thing that says so.** `rofi/config.rasi` pins `Hack Nerd Font 11` because
the menus carry their icons in the entry *text*. Hack Nerd Font does **not**
cover `nf-fa-network_wired` (U+F6FF), which `menus/network-menu.sh` uses for its
ethernet entry — fontconfig falls through to `IBM Plex Sans TC`, draws whatever
that has at the codepoint, and logs nothing. Found on 2026-08-19 while building
`menus/control-center.sh`, which uses `nf-md-ethernet` (U+F0200) instead, the
same glyph `waybar.nix`'s `format-ethernet` uses. **Fixed in
`network-menu.sh` on 2026-08-20** — it wears U+F0200 too, written as a
`$'\U000F0200'` escape rather than a literal, and `fc-match ':charset=f6ff'`
was resolving to `Unifont Sample`. Check any new one with
`fc-list ':charset=<hex>' family | grep -i hack`
before it goes in — the nf-fa range is not covered end to end, and the nf-md
range (U+F0000+) is a different question again.

### `lines: 12` is shared, so a menu that grows a row starts paging

`dotfiles/rofi/config.rasi` sets `lines: 12` on the `listview` as a ceiling, with
`dynamic: true` shrinking anything shorter. That is right for the menus that are
genuinely lists — the AP list, clipboard history — where paging is the honest
answer to "there are more of these than fit".

It is wrong for a menu that is a **set**. Adding the microphone row took
`menus/control-center.sh` to eleven rows plus two separators, i.e. 13 rendered
lines, and rofi quietly split it across two pages: the last two toggles were
gone from a menu whose entire purpose is showing the whole set at once. The
symptom is not an error — it is a menu that looks complete and is not.

The fix belongs at the **caller**, not in the shared theme: `control-center.sh`
passes `-l "${#ROWS[@]}"`, because `render()` prints exactly one line per `ROWS`
element (a `-` becomes a separator line), so the array length *is* the rendered
height and a row added later widens the window instead of re-paging. A literal
`-l 13` would have been the same bug on a timer. `dynamic: true` still applies,
so this raises a ceiling for one menu rather than forcing a height.

Any fixed-set menu here is exposed the same way as it grows past twelve.

### An icon row cannot go through a shell variable, because of one NUL byte

rofi's dmenu icon syntax is `<text>\0icon\x1f<name>` — the metadata is separated
from the row by a **NUL**, and no bash string can hold one. Both of the obvious
ways to build the menu drop it, silently:

```bash
menu+="${title}"$'\0'"icon"$'\x1f'"${icon}"$'\n'   # $'\0' expands to nothing
entries=$(cat)                                     # command substitution strips NUL
```

The first version of `menus/minimized-menu.sh` did both and rendered rows
reading `Spotify Premiumicon␟spotify` — every row's metadata as visible text,
with nothing erroring anywhere. Found by screenshotting the menu.

`lib.sh`'s `rofi_menu` is the second line, so **a menu with icons cannot use
it** and must `printf` its rows straight down the pipe. It passes the same
`-theme-str "listview { lines: N; }"` by hand; the sizing check in
`checks/static.sh` accepts a direct call that does. `docs/adr/0052`.

### `-show-icons` beats config.rasi, and `-l` does not

Both are "the file wins" candidates and only one of them is. `config.rasi` sets
`show-icons: false` for every menu here — the glyphs are already in the text —
and the minimized picker turns them on for itself. Verified rather than assumed,
which takes one command:

```sh
rofi -show-icons -dump-config | grep show-icons   # show-icons: true
rofi -dump-config | grep show-icons               # show-icons: false
```

The difference is what kind of setting it is. `show-icons` is a **configuration**
option, which the command line overrides; `lines` is a **theme** property, and
on rofi 2.0 the theme beats the command line — which is why `-l` is inert here
and `-theme-str` is not.

**A keysym can live on two keys, and the second bind silently loses.** The gb
layout includes `latin`, which puts `bracketleft` on `<AE08>` and `bracketright`
on `<AE09>` at AltGr level — AltGr+8 is `[`. mango resolves a bind's keysym to a
keycode, so `bind=SUPER,bracketleft` and `bind=SUPER,8` land on the same keycode
and one of them does nothing. The two named-scratchpad binds and the tag-8/tag-9
views had been in that state since they were added.

mango only started reporting it in 0.17.4, as `[WARNING] Key binding conflict in
keymode default` naming the two config lines; 0.16.3 took the config without a
word. `checks/static.sh` fails on any mango stderr, which is why the bump
surfaced it — a conflict warning is the same class of defect as the `[ERROR]`
that check was written for.

`SUPER,8` and `SUPER,9` are gone rather than the brackets. Modifiers are part of
the comparison, so `SUPER+SHIFT,8` and `SUPER+CTRL+SHIFT,8` are unaffected and
both tags stay reachable. Verify a candidate key before using it: `mango -p` in a
scratch `$HOME` with the real `xkb_rules_layout`, which is what found that
`SUPER+ALT,bracketleft` and `SUPER,minus` are clean while `SUPER,braceleft` is
not.

---

## Wayle

**Installed and generated; nothing starts it.** wayle held the bar, the
notification daemon, the OSD and the wallpaper engine in tiling mode between
2026-08-24 and 2026-08-27. `docs/adr/0051` says what came back and why. Its
config is still built by `modules/home/wayle.nix` and its stylesheet is still
`dotfiles/wayle/index.scss`, so a rebuild still has to satisfy the two
constraints below.

The rest of what was learned porting the bar to it — its selector precedence,
its spacing model, its icon chain, its Jinja2 formats and its silent config-key
clamps — went with the section on 2026-08-28. It described a surface no mode
draws, and `git log` has it if wayle is ever started again.

**`services.wayle.settings` must stay `{ }`.** The module claims
`wayle/config.toml` the moment it holds one value, and that path is owned by
`scripts/wayle/wayle-restart.sh`, which re-points it per layout and position.
Two owners for one path is an activation failure, not a merge, and
`checks/static.sh` asserts the file is absent from the generation. A missing
link there leaves a plausible bar that is not this one, which is why
`wayle.nix` seeds it at activation.

**`runtime.toml` beats the config file, quietly.** `wayle config set` writes
`~/.config/wayle/runtime.toml` and it wins over everything generated. Nothing
warns. If wayle is ever started again, check that file before believing the
generated one.

## Waybar

> waybar was the tiling bar until 2026-08-24, wayle's between then and
> 2026-08-27, and is again. `docs/adr/0051`. Nothing below was invalidated by
> the round trip; the four findings at the top of this section came *out* of it,
> from rendering the two bars side by side rather than from reading configs.

**`format-alt` does nothing on its own.** `ALabel::handleToggle` is gated on
`config_["format-alt-click"].isUInt()` (`ALabel.cpp:181`) and waybar sets no
default, so a module declaring `format-alt` and nothing else has a second
reading no click can reach. Four did here — clock, memory, network and battery
— for as long as they had existed. `mkBar` now emits `format-alt-click = 1`
for any module carrying a `format-alt`, so the pair cannot come apart.
`docs/adr/0057`.

**And `on-click = "alt"` is not how to ask for it.** "alt" is not one of
waybar's action names; `AModule::handleUserEvent` looks the event name up, finds
`config_["on-click"]` is a string, and `forkExec`s it. So the setting spawned
`alt` as a shell command on every left-click of the memory module and failed,
once per click, with nothing on any stderr anyone reads. The real action names
are per-module and documented in the module's man page — `mode`, `shift_up`,
`tz_up`, `activate` — and they go in an `actions` block, not in `on-click`.

**A styled state can be one waybar never renders.** `#tray > .passive` dimmed
passive tray items for as long as it existed, and `show-passive-items` defaults
to false (`waybar-tray(5)`), so no passive item was ever drawn for it to match.
A rule for a widget that does not exist looks exactly like a rule that works.
Deleted; set the option if they should show. `docs/adr/0057`.

**rofi selects a row whether the surface wants one or not.** A readout built
from rows — the weather panel, the calendar — gets its first row highlighted,
which on the calendar was the `Mo Tu We` header and read as a broken list.
`-selected-row` moves it somewhere that means something; the calendar puts it on
the week containing today. There is no "select nothing".

**A scan for glyph escapes has to read both widths.** `$'\uXXXX'` and
`$'\UXXXXXXXX'` are both legal bash and the check read only the second, so 39
Font Awesome and nf-weather glyphs were invisible to it — including the one it
was written to catch. It reported "all N are nf-md" for a year. Below U+E000 an
escape is not a glyph at all (`\u001f` is window-title.sh's field separator);
above it, a 4-digit escape cannot reach U+F0000 and is therefore always another
pack. `docs/adr/0057`.

**The generated config keys a module by its TAGGED name, so `.mpris` is not
where `mpris` lives.** `waybar.nix` appends `#sep` to the first module of each
group and `defs` is keyed by the emitted name — waybar looks a tagged module's
config up under the suffixed key (`factory.cpp` passes `config_[name]`, not
`config_[ref]`). So the real key is `"mpris#sep"`, and
`jq '.mpris["dynamic-len"] = 25'` against the built file **creates a second,
empty `mpris` object that waybar ignores** and reports success. Three test
renders were spent on that. `jq 'keys[]' config-full-top.jsonc | grep mpris`
first.

**`mpris` has three length keys and only one of them truncates.**

| key | what it actually does |
|---|---|
| `dynamic-order` | WHICH fields render. Unwritten it defaults to title, artist, album **and position** — so the label was `The Yogscast [06:03/13:48]`, a running clock in the space the title should have had. "Absence in this list means force exclusion" (`waybar-mpris(5)`) |
| `dynamic-len` | a **DROP** threshold, not a truncation one. waybar removes a field that does not fit rather than shortening it, so at 25 a 35-character title vanished entirely and the 12-character artist was what remained. Reordering `dynamic-importance-order` does not change it — tried both ways, same output |
| `max-length` | the one that behaves like wayle's `label-max-length`: truncates the composed string with an ellipsis |

So "cap the media label at 25 characters" is `dynamic-len` high enough that
nothing is dropped plus `max-length = 27` (the status icon, its space, and 25),
which is the opposite of how it reads.

**`ignored-players = [ "firefox" ]` blanked the module completely.** It came
through the generation refactor from the hand-written configs with no reason
attached — waybar's own docs suggest it, because firefox can expose one MPRIS
player per playing tab. On this machine it exposes one (`playerctl -l` → a
single `firefox.instance_*`) and firefox is the only player, so the module
rendered nothing, always, and looked like a module with nothing to say.

**`{icon}` in a custom module's `format` renders the whole label empty.** The
documented way to give `custom/window` a per-app glyph is `format = "{icon} {}"`
with a `format-icons` map keyed by the JSON `alt` field. On waybar 0.15.0 the
module then draws **nothing at all** — not the text without the icon, the whole
label — and **waybar logs not one line**, with stderr kept, either way. Verified
both directions by rendering: `format = "{}"` draws the title, adding `{icon}`
blanks it.

So the app glyph is prepended by `window-title.sh` and the appid→glyph table is
passed to it as a JSON argument from `waybar.nix`. The table stays declared in
one place and the glyph actually draws. `alt` is still emitted — it costs
nothing and it is what a `#custom-window.<app>` rule would key on.

> **A module's LABEL cannot hold an icon name, but its STYLESHEET can.**
> `wlr/taskbar` and `tray` ask the icon theme directly and draw real Papirus
> art. Every glyph in a `format` string comes from a font instead — but
> `background-image: -gtk-icontheme("firefox")` in `style-solid.css` renders the
> real themed icon behind any module, keyed on whatever class the module emits.
> Verified by rendering on 2026-08-27, after this file claimed the opposite.
>
> Two limits. It is **one icon per module**, not per item: GTK takes multiple
> background layers but their positions are static, so a variable-length list
> like `custom/minimized` cannot get one icon each. And app icons arrive in
> **full colour** — symbolic names render as their own asset rather than
> following the palette, because GTK's symbolic recolouring applies to image
> widgets, not to CSS backgrounds. waybar's `image` module is the other route:
> a real GtkImage from a path a script prints, so it needs its own module slot
> and shows no text.

**The bar is one glyph pack — nf-md — and a check enforces it.** It carried 18
Font Awesome, 16 Material, one Octicon, one nf-linux and three bare Unicode
arrows until 2026-08-27: four vocabularies at four stroke weights. nf-md lives
in plane 15 at U+F0000 and above, and every other pack sits in the BMP
private-use area, so "not nf-md" is just "codepoint below U+F0000" — which is
the whole assertion, via jq's `explode`.

> **Verify a glyph by RENDERING it, never by its name.** `md-memory` (U+F035B)
> is the CPU chip and `md-chip` (U+F061A) is the RAM stick — exactly the other
> way round from what they are called. `magick -font SymbolsNerdFontMono label:`
> over the candidate list catches that in one pass; `fc-list ':charset=…'` only
> only confirms the codepoint exists.

**`mmsg dispatch restore_minimized` answers `{"success":true}` when it restores
nothing.** It is mango's only restore verb, takes no client, and pops the last
minimized window **on the current tag**. Verified on 2026-08-27 both ways: a
window minimized and restored on one tag round-trips exactly (`is_minimized`
false again, `tags` back to the active tag); a window minimized on tag 1 stays
minimized while tag 2 is active — and the dispatch reports success in both
cases. `SUPER+SHIFT+I` has the same behaviour, because it is the same verb.

> **Minimizing clears the client's tag list to `[]`.** So `is_minimized` is the
> only way to find these windows, and there is no way to tell from the IPC which
> tag one would come back to. That is why `custom/minimized` lists what is hidden
> and does not offer to restore a chosen one: a menu that accepts a choice it
> cannot honour is worse than no menu (`docs/adr/0033`).

**`mmsg` reports whether a COMMAND or a FUNCTION was wrong, and exits 0 for
both.** `mmsg dispatch <nonexistent>` → `{"error":"unknown function"}`;
`mmsg <nonexistent>` and `mmsg dispatch` with no argument →
`{"error":"unknown command"}`. That difference is the cheap way to confirm a
subcommand exists at all — `mmsg`'s own usage text lists only `get` and `watch`,
so `dispatch` looks absent until probed with a bogus function name.

**Two bare `#id` rules for one module: the later one wins and the earlier does
nothing.** `#custom-weather { font-size }` was written twice — once beside the
clock, once in the weather section — at equal specificity, so the size did not
change and the sheet reported nothing, because both rules are perfectly valid
CSS. A rebuild was spent on it. `checks/static.sh` now asserts one bare rule per
id; state rules (`#custom-weather.ok`) are a different selector and are not
counted, and neither is the last line of a multi-selector block, which opens one
rule over many selectors and looks identical to a bare rule under grep.

**`#custom-window` drew at `@subtext` and 11px** against a bar of `@text` at
14px — dimmer and three points smaller than every other module, on the one label
that is a sentence rather than a number. Its rule is gone; the shared rules give
it the bar's own colour and size. **Its cap moved with it**, 60 → 45, because the
same characters are a third wider at 14px: raising the size without lowering the
cap is the half-change, and the centre then reaches the modules either side.

**swaync claims `org.erikreider.swaync.cc` only when it also gets
`org.freedesktop.Notifications`.** That second name is a *separate*,
D-Bus-activatable one and its activation unit is deliberately masked
(`modules/home/default.nix`, so `autostart.conf` owns the lifecycle). With
something else already holding the notification name, swaync starts, claims
`org.erikreider.swaync`, and **does not claim `.cc`** — so every `swaync-client`
call falls through to activation and dies with `NameHasNoOwner … unit is
masked`, on a stderr no keybind reads, **exiting 0**. A running swaync is
therefore not evidence that `swaync-client` works. Check
`busctl --user list | grep swaync` for all three names, not the process.

The eight `config-<layout>-<position>.jsonc` files are **generated** by
`modules/home/waybar.nix` — there are no `config*.jsonc` in this repo. Each
module is defined once and a layout is a list of names, so **a module name with
no definition is an eval error rather than an empty module**. Two asserts back
it: one for undefined names, one for a `tweaks` entry targeting a module the
layout does not carry (which waybar ignores in silence). The stylesheets stay
hand-written — hand-tuned presentation is data, not settings.

`xdg.configFile` writes them into `~/.config/mango/waybar/`, which coexists with
the recursive mango link **only** because the hand-written `.jsonc` files were
deleted. Two owners for one path is an activation failure.

**Killing waybar leaks the `mmsg watch` behind `window-title.sh`.** The module
script dies with the bar; the stream inside its process substitution does not.
Four orphans were alive at once on 2026-08-16 — PPID 1, up to fourteen hours
old, ~5 MB each, every one holding an open IPC socket to mango with nothing
reading from it. One leaks per `pkill waybar`, so **every mode switch and every
`waybar-reload`**. The tell is that they carry `WAYBAR_OUTPUT_NAME` in their
environment long after the bar that set it is gone:

```sh
pgrep -a 'mmsg watch'                       # more than one per module = leaked
tr '\0' '\n' < /proc/<pid>/environ | grep WAYBAR_OUTPUT_NAME
```

The fix is `trap 'pkill -P $$' EXIT PIPE HUP INT TERM` — by **parent**, not by
name, since matching `mmsg` would take out every other module's watcher too.
`PIPE` is in the list because a closed bar pipe is how the script usually dies,
and SIGPIPE's default action skips the `EXIT` trap. `checks/static.sh` requires
it of every script that streams `mmsg watch`.

**`on-scroll-up` on the volume and backlight modules DECREASES, and that is
correct.** `trackpad_natural_scrolling=1` makes libinput invert the axis before
any client sees it, so fingers-up arrives as `on-scroll-down`. Reading the
generated JSON alone makes this look like an inversion bug; it was "fixed" on
that basis once and reverted. Note `mouse_natural_scrolling=0`, so an external
wheel gets the opposite behaviour and no single config serves both. `-l 1.5` is a
volume ceiling and belongs on whichever direction increases.

> `mpris` and `ext/workspaces` disagree about scroll direction in either frame.
> Known, deliberately left alone — flag it rather than changing it unasked.

**Glyphs in `waybar.nix` must be literal UTF-8** — Nix has no `\uXXXX` escape.
Transcribing them by hand is exactly how this repo loses icons; four `network`
glyphs were silently changed during the conversion and had to be recovered from
git by codepoint. Verify with `jq -r` piped through a codepoint dump, not by eye.
A glyph the font lacks renders as an empty box with nothing in any log — check
with `fc-list ':charset=<hex>' family` before swapping one in.

**The whole bar asks for `Symbols Nerd Font Mono` before `3270 Nerd Font`**, and
that ordering is load-bearing. 3270 patches the Nerd Font icons in at their
natural width but keeps a narrow 0.54em advance, so the ink overflows its cell to
the right with all the slack on the left. **Padding cannot fix it** — symmetric
padding centres the advance box, not the ink. A module gets *wider* when fixed,
since the real advance was understated.

> Font-family **order** is the fix, not fallback. Pango only falls back for a
> codepoint the first font LACKS, and 3270 has these glyphs — badly — so it wins
> unless Symbols is named first. Naming Symbols first is safe because it carries
> 10,519 codepoints of which only 14 are outside the Nerd Font PUA (`U+23FB`–`FE`,
> `2630`, `2665`, `26A1`, `276C`–`2771`, `2B58`) and the bar prints none of them:
> icons come from Symbols, digits and text fall through to 3270 per character.

This was four per-module `font-family` overrides until 2026-08-21, on
`custom/power-profile`, `custom/idle-inhibitor`, `custom/phone` and
`custom/weather`. **Ten modules needed it** — measured, in 3270 Regular, worst
overflow first: `custom/notification` and `network` and `pulseaudio` a full em,
`cpu` and `custom/power` +920, `ext/workspaces` and `custom/control-center` +766,
`backlight` +756, `memory` +535, `mpris` +305. The four that had it were the four
someone had looked at. `custom/control-center` was reported as "the icon isn't
centred in its module", which is what this looks like from the outside.

**Measure the advance, don't infer it from how the glyph looks.** Two comments in
`style-solid.css` claimed the opposite of what the fonts do and were corrected
only after measuring. `fc-list ':charset=<hex>'` answers whether a glyph exists,
not whether it fits; for that, read `hmtx` against the glyph's ink bounds:

```sh
nix shell --impure --expr 'with import <nixpkgs> {}; python3.withPackages (ps: [ ps.fonttools ])' \
  --command python3 -c '…TTFont(path); hmtx[g] against a BoundsPen over glyphSet…'
```

Only the invocation was ever wrong; `glyf[g].xMax` reads correctly for the
patched icons (they are simple glyphs, not composites). A `BoundsPen` over
`getGlyphSet()` gives the same number and also covers composites.

`nix shell nixpkgs#python3Packages.fonttools -c python` does **not** work — that
puts the `ttx` CLI on `PATH` without putting the module on `PYTHONPATH`, and the
import fails in a way that looks like the package being wrong.

Measured on 3270 (upem 2000) vs Symbols Nerd Font Mono (upem 2048):

| glyph | 3270 advance / ink | Symbols advance / ink |
|---|---|---|
| `U+F10B` fa-mobile | 874 / 0–1269 — **overflows 395** | 2048 / 320–1728 |
| `U+F0084` md-battery | 874 / 0–1000 — **overflows 126** | 2048 / 409–1639 |

**`#taskbar button` must keep `min-width` ≤ `icon-size`.** waybar `pack_start`s
the icon, so any width beyond the icon becomes empty space on the **right only**.
The two numbers are coupled — change both together.

**`custom/power`'s `wlogout -b N` must equal the wlogout entry count**, which is
declared in a different file (`programs.nix`). `-b` is a column count, not a
maximum: leave it at 5 after adding a sixth entry and the extra button wraps
onto a second row that `-T 320 -B 320` has left no height for.

**Do not reintroduce `dwl/window`.** mango 0.15.5 dropped the `zdwl_ipc_manager_v2`
protocol that module binds, and its absence makes waybar **SIGSEGV on startup**.
The title comes from `custom/window` (`scripts/waybar/window-title.sh`); the CSS
selector is `#custom-window`.

**The bar shows the RAW battery percentage — `full-at` was removed, do not put it
back.** It rescaled the reading as `shown = real / full-at × 100` so TLP's 85%
stop would read 100%, which made the bar disagree with fastfetch, `upower` and
sysfs by a constant factor forever. That is not a bug anyone notices, it is one
that *explains* things — it absorbed two separate reports of the module freezing
before anyone checked whether the number was stale rather than merely rescaled.
`checks/static.sh` asserts no generated config carries it. Consequence: the bar
parks at 85% on AC and never reads 100%, and `states.warning = 30` now fires at a
real 30%.

**The battery module freezes — an open waybar bug.** The tell is an
**asymmetry**: the CSS class tracks reality while the label text does not (the
module renders `#battery.warning`, which needs a reading ≤30, while displaying
81%). `Battery::update()` applies the CSS class as a *side effect* of
`getState()`, and `label_.set_markup()` is the last statement; `bar.cpp` wraps
the whole call in a `try`/`catch` that logs and continues. **Anything that throws
between those two lines leaves the class current and the text frozen forever,
with the module still repainting.** What throws is still unknown, because
`waybar-restart.sh` used to discard stderr — **stderr now goes to
`~/.local/state/mango/waybar.log`, with the previous run kept as `waybar.log.1`.
When the number sticks again, read that file *before* restarting.** Workaround:
`waybar-reload`. Do not reach for `full-at` or the charge thresholds — a frozen
module and a rescaled one look identical in a screenshot, which is how this
survived two rounds.

> Diagnostics: `/var/lib/upower/history-charge-*.dat` logs one line per change,
> so it dates a freeze precisely — a click-corrected reading that predates the
> last gap means the module was stuck, not the battery. waybar 0.15.0 has a stray
> `puts()` in `Battery::update()`, so a throwaway single-module instance gives an
> exact one-line-per-update counter (use `stdbuf -o0`; the live bar discards
> stdout).

> `bat`/`adapter` are named explicitly. Auto-detection keeps the **last**
> `/sys/class/power_supply` entry carrying `online` or `status`, decided by
> readdir order — this machine has four supplies and it resolved to `AC` only by
> luck.

**The idle inhibitor used to be process state, and a waybar restart released
it.** Fixed on 2026-08-18 (docs/adr/0031): it is `wlinhibit.service` now and the
bar module only reports it, so `waybar-reload`, a layout switch, a mode switch
and `SUPER+/` all leave it held. Before that the toggle was a static bool on a
surface that died with the bar — and the glyph went back to `󰒲` at the same
instant, so the bar was never visibly *wrong*, it just stopped being what had
been set. `minimal` still does not carry the module; it no longer needs to,
because
`SUPER+SHIFT+A` reaches it in every mode and every layout.

Two things that remain true about it:

- **A `failed` unit has already released the inhibitor.** The state lives
  outside the thing that draws it now, so the bar can lag reality — hence the
  red `failed` class and a 30s poll underneath the signal. Red `󰒳` means the
  ladder is live, whatever the glyph suggests.
- **Entering noctalia releases it, on purpose.** `SUPER+SHIFT+A` drives
  quickshell's `IdleInhibitor` in noctalia mode and `wlinhibit` in tiling
  (docs/adr/0023), and noctalia's IPC has no getter — so the two can never be
  read into step, and `apply_mode` hands over instead: one owner per mode. A
  notification fires when it actually releases something, and re-arming in
  noctalia is the same key. **The handover is one-way**: coming back out to
  tiling does not restore it, because nothing can ask noctalia whether it
  was holding one.

`checks/static.sh` asserts at least one layout still carries the module, that
the unit exists, and that it has no `WantedBy=` — an inhibitor armed at login
looks exactly like a deliberate one.

**When a `custom/*` module is missing from the bar, run its exec by hand and
check the `text` field is non-empty** — not just that the script succeeds. An
empty custom module is indistinguishable from an absent one. `custom/power-profile`
emitted `{"text":""}` for a while because its icons were written as literal
glyphs and lost in transit; they are `$'\uXXXX'` escapes now, deliberately.

**A separator draws the group; the spacing has to agree with it.** Replacing the
module-keyed borders left every module on `padding: 0 6px`, so the gap inside a
group (12px) and the gap between two groups (13px) were the same — the line said
"new group" and the rhythm said "same group", and the widest gap on the bar was
`#clock`'s 14px padding sitting between the time and the weather beside it. The
bar is `padding: 0 5px` with `margin-left: 10px` on `.sep` now: 20–24px between
groups against ≤12px inside one, measured off a screenshot rather than judged.

> Compensation for the 0.54em advance was scattered through this too, and it all
> looks like spacing: `padding: 0 8px` on three icon modules, `min-width: 28px` on
> two more, and a **double space** in ten `format` strings where `battery`,
> `mpris` and `bluetooth` used one. A glyph overflowing its cell looks jammed
> against its own number, and the fix people reach for is more space. Fix the
> font first, then take the compensation back out — otherwise it is doubled.

**A separator keyed to a module moves when a layout drops its neighbour.**
`style-solid.css` drew the bar's groups with fifteen `border-left` rules keyed by
module id until 2026-08-21, so grouping was a property of the module while the
thing it separates is a property of position. `custom/weather`'s one border
opened a group containing `cpu memory` in `full` and `custom/control-center` in
`focus`, and twelve of `full`'s sixteen right-hand modules carried a border, so
nearly every boundary was a line and nothing read as grouped. A layout is a list
of groups now and the sheet has one `.sep` rule; `docs/adr/0042`.

> waybar turns `network#sep` into the widget `network` with the style class
> `sep` — `factory.cpp:129` splits the name, `ALabel.cpp:34` adds the class, and
> `wlr/taskbar.cpp`, `sni/tray.cpp` and `ext/workspace_manager.cpp` each carry
> the same three lines for their `box_`. **Its config key must carry the suffix
> too**: the factory looks up `config_[name]`, not `config_[ref]`, so
> `network#sep` with its settings under `network` renders waybar's defaults and
> says nothing.

> **The group gap needs a margin and a padding, and both must live in the `*`
> rule.** A border is drawn between margin and padding, so `margin-left` puts
> space *before* the line and `padding-left` puts it *after* — a `.sep` carrying
> only the margin gives the group its whole gap on one side, which looks like
> every group shifted left against its own separator. That is how this first
> shipped and how it was reported.
>
> GTK CSS ranks selectors as the web does, so an `#id` rule setting either
> property beats `.sep` and takes the gap off that side for the module it names.
> `#workspaces { padding: 0 }` did, and `#workspaces` leads a group in all three
> layouts.
>
> **Style a module through `.module`, waybar's own class** (`AModule.hpp:15`) —
> it is added to the same widget as the `#id` and the `#sep` tag, so a rule on
> it reaches exactly what the rest of the sheet reaches. The two obvious
> alternatives are both wrong and fail differently: `*` also matches the label
> inside a workspace button, the image inside a taskbar button and the icon
> inside a tray item, and stacks its padding on the button's own; while
> `.modules-right > *` matches the **EventBox wrapper** one level out, so the
> padding is set on a widget that never draws it and every module inside a group
> renders flush against its neighbour.

**A waybar module with no CSS rule, and one with an empty `format`, both render
without erroring.** Since 2026-08-20 `checks/static.sh` asserts both, for every
module every layout carries: a rule exists in `style-solid.css`, and no `format`
is the empty string. Both were made in one sitting while adding
`custom/control-center` — the glyph was lost writing the Nix (there is no
`\uXXXX` escape, so a bar glyph is literal UTF-8 that an edit can drop) and the
module built, validated and rendered as nothing.

> The scan reads the module lists out of the generated configs with `jq`, and
> the keys have to be QUOTED: `.modules-left` is jq for `.modules` minus `left`,
> which yields null rather than an error — so the first version of the check
> scanned nothing and only the zero-floor caught it.

**`sed '/\/\*/,/\*\//d'` does not strip CSS comments — it strips most of the
file.** A sed range looks for its end pattern from the NEXT line on, so a
one-line `/* ── Tooltip ── */` header opens a range that closes only at the
following comment's `*/`, taking every rule between them. The first version of
the rule→module check in `checks/static.sh` scanned the two thirds of
`style-solid.css` that survived this and passed — including on a deliberately
planted orphan rule, which is how it was caught. Flatten first, then match
comments as a unit:

```sh
tr '\n' ' ' <"$f" | sed 's|/\*[^*]*\*\+\([^/*][^*]*\*\+\)*/| |g'
```

The tell was the count: 15 styled ids where the sheet has 23.

**And the inverse: a module invisible for long enough loses its stylesheet.**
`custom/phone` was listed in the `full` layout and in hud's, but had **no CSS
rule in either sheet** — not even a place in the shared reset list — for as long as it
existed. Nothing caught it, because for that whole time `phone-status.sh`'s
liveness guard could not match a wrapped `kdeconnectd` and the script always took
its "KDE Connect not running" branch, which emits empty text. Fixing that guard
(`866b57b`) made the module render for the first time, unstyled: no padding, no
`border-left`, so the phone glyph sat flush against `custom/power-profile` and
read as **a second icon inside the power module** rather than a module of its
own. It was reported that way, and blamed on the noctalia work landing the same
week.

Two things follow. **A dead guard hides a presentation bug behind a functional
one**, and fixing the functional one exposes it with no warning — when a guard
fix makes something appear, check it has a rule. And **`custom/phone` deliberately
emits empty text when the phone is unreachable**, so the module is absent rather
than a permanently grey glyph; only `connected` / `warning` / `critical` are
styled, and `disconnected` / `offline` are unstyled on purpose.

### The microphone was on no surface at all

Until 2026-08-19 `pulseaudio` in `waybar.nix` carried `format`, `format-muted`,
icons and handlers for the **sink** and no `{format_source}`, and there was no
`custom/microphone` either. So mic mute state appeared **nowhere on screen**.
The only indicator on this machine was the ThinkPad LED, driven by the
`micmute-led` user unit — one `pactl subscribe` loop writing
`/sys/class/leds/platform::micmute/brightness`.

That is the same silent failure, applied to the worst available fact: a dead
`micmute-led` and a live microphone look **exactly** alike, and the cost of
reading it wrong is being recorded when nobody thinks it is. It needed no
new script — waybar's built-in module already supports `format-source`,
`format-source-muted` and `{format_source}` inside `format`; the fields were
simply never filled in. Both the bar and the control centre read PipeWire
directly, which owns the fact, exactly as they already both read the sink.

Two traps in filling them in, and both produce a bar that looks fine:

- **`format-muted` needs `{format_source}` too.** It is a *replacement* for
  `format`, not an addition to it, so a placeholder left out of it disappears
  under that condition — muting the **speakers** would have taken the
  **microphone** indicator off the bar with them, and nothing anywhere says so.
  Any placeholder worth putting in `format` has to be repeated into every
  `format-*` variant that can replace it.
- **The MUTED state may never render as nothing.** `format-source-muted`
  defaults to the empty string, which looks like a tidy bar and is the one
  arrangement that cannot be debugged: "muted" and "the module is broken"
  become the same picture.

  This said *"neither state"* until 2026-08-27 and that over-generalised from
  the muted case. **The live state is empty now**, deliberately: with no glyph
  meaning live, a broken module also shows no glyph, so the wrong reading is
  "I am being recorded" — the safe one. A permanent indicator for the normal
  state is also the thing that makes the dangerous state hard to spot, because
  it turns "is there an icon" into "which of these two similar icons is it".
  The asymmetry is the point, and it only works in one direction.

  The **space** lives in the muted glyph, not in `format`: a trailing
  `{format_source}` that resolves to nothing still leaves the space before it,
  so the module would change width for no visible reason.

The `custom/phone` rule directly above is not the counter-example it looks like.
An absent phone module means *there is no phone*, which nobody can be misled by;
an absent microphone indicator means one of two things, and only one of them is
safe.

### A cached reading served as a current one cannot be spotted

`custom/weather` serves its cache when the fetch fails, because losing the
reading is worse than showing an old one. Served **without a class**, that is
yesterday's temperature in today's font: nothing errors, nothing logs, and the
bar looks exactly right. It is the same silent failure in a tidier form, and
it is the reason `weather.sh` has three classes rather than a temperature and a
fallback — `ok`, `stale` (greyed, with its age in the tooltip *and* in `alt`)
and `error` (`?`, never a number). docs/adr/0038.

The general shape: **any module with a cache needs a way to say the cache is
what is on screen.** A module that can only be right or absent has no way
to be honest about being out of date.

### `alt` is the field for a phrase the control centre also wants

The weather row first cut its description out of the module's tooltip and
rendered `light` for `light drizzle` — the description has a space in it and the
tooltip has five more. `alt` is one of waybar's own custom-module keys
(`text`/`alt`/`tooltip`/`class`/`percentage`) and goes unused whenever `format`
is `{}`, so it is free to carry a second reader's field.

Same fix as `jfields`: give the reader a field rather than a substring index.
Two owners for one string, one of them a `${...#*— }`, is drift by another route.

### `background: transparent` resets the icon, and both stylesheets are valid

The bar draws themed art with `background-image: -gtk-icontheme("name")`
(`docs/adr/0052`). `style-solid.css` also gives every module:

```css
#workspaces, #custom-minimized, #custom-window, … #battery {
    background: transparent;
}
```

That is the **shorthand**, so it resets `background-image` to `none`. It sits at
one-id specificity and is read *after* the `@import` of the generated
`icons.css`, so a generated rule keyed on a bare id loses and the module draws no
icon at all. Nothing is invalid and GTK logs nothing.

`#custom-minimized` was written that way and rendered as a bare count. The
battery rungs and the appid rules were unaffected — `#battery.l30` and
`#custom-window.foot` carry a class, so they out-rank the shared block. **Every
rule in `icons.css` carries a class for that reason**, and `checks/static.sh`
asserts none is a bare id.

The same file is why a *second* declaration of one property for one selector is
dangerous here: `icons.css` is imported first, so `style-solid.css` wins in
silence. The check asserts the two never claim the same selector.

### An appid is case-sensitive, and `Equibop` is not one

`windowIcons` was keyed on `Equibop` from the day the glyphs were written. mango
reports **`equibop`**, so every Equibop window wore the default glyph and the
entry matched nothing — for as long as the table existed. `Spotify` beside it
*is* capitalised, which is most of why it read as plausible.

```sh
mmsg get all-clients | jq -r '.clients[]?.appid' | sort -u
```

is the whole check, and it is worth running before adding a key rather than
after. The desktop-file name is not the appid either: `spotify.desktop` declares
`Icon=spotify-client` while the appid is `Spotify`.

### An icon name that resolves to nothing draws nothing

The failure `docs/adr/0041` gave the GTK, Kvantum and cursor names a check for,
one layer down: `-gtk-icontheme("battery-level-100-charging-symbolic")` is
perfectly good CSS for an icon Papirus does not ship (the full one is
`-charged-`). GTK draws nothing and says nothing, so the module looks empty.

`checks/static.sh` resolves every name the bar draws against the scheme's own
icon theme **and the themes it inherits** — not against the whole of
`share/icons`, where a name that exists only in some other installed theme would
pass and still draw nothing in the session.

### An `#id` rule that sets padding beats `.sep`, and the tag strip uses that

`.sep` draws the group line and pays for it on both sides: 6px of margin before,
11px of padding after (`docs/adr/0042`). `#workspaces { padding: 0 }` is (1,0,0)
against `.sep`'s (0,1,0), so it wins and the line before the tags gets no gap
after it. `#mpris.sep { margin-left: 0 }` takes the gap off the other side.

Both are deliberate (`docs/adr/0053`). The buttons keep their own 8px, so a glyph
never touches a line but the box reaches it, which lets a hover or an urgent fill
run to the group edge.

It looks like a bug, because 11px sits after every other separator, and an 11px
"restore" shipped for one commit on that reasoning. `checks/static.sh` fails if
`#workspaces.sep` reappears or `#mpris.sep`'s margin stops being 0. It reads the
rule's body rather than its presence, because the regression was a rule that
existed with the wrong value.

### A plain icon name ignores `color`; only `-symbolic` follows it

`docs/adr/0052` recorded that a `-symbolic` CSS background follows the module's
`color` while an app icon comes through in full colour. The case that bites is a
plain name that looks symbolic: `-gtk-icontheme("view-restore")` renders
Papirus's own white asset and ignores `color`, so a tinted module drew a tinted
number beside a white icon.

`view-restore-symbolic` is the same art as a recolourable mask. Papirus ships the
symbolic set under `Papirus`, not `Papirus-Dark`, so inheritance is what makes
the name resolve. That is why the icon check resolves against the scheme's theme
and the themes it inherits.

### `grep -r` skips symlinks under `~/.config`; use `-R`

Everything home-manager installs is a symlink into the store, and `grep -r` does
not follow symlinks it meets while recursing. So a scan of
`~/.config/mango/scripts/` matches nothing, whatever is in the files.

That is indistinguishable from the target being absent, and it
is most convincing right after a rebuild, when "not there yet" is the expected
answer. `grep -R` follows them. The same applies to any scan of the live config
rather than the repo.

### An undefined colour inside `mix()` is silent

GTK reports an invalid property on waybar's stderr and says nothing about an
undefined `@colour`. Both fed at once:

```css
#clock { border-left: 1px solid mix(@base, @nosuchcolour, 0.3); }
#cpu   { flooble: 3px; }
```

waybar logged `'flooble' is not a valid property name` and nothing for the
colour; the border drew in an inherited value. So a clean CSS log is not evidence
that the colours resolved, which matters now that the bar's hairlines are built
with `mix()` (`docs/adr/0053`).

The both-directions `palette_pair` check covers this: every colour `colors.css`
defines must be used, and every colour the sheet names must be defined.

---

## Power

`docs/SYSTEM.md` §9 is the reference for battery thresholds, suspend, hibernation
and the WiFi resume fix. The traps worth remembering:

- ⚠️ **`/sys/firmware/acpi/platform_profile` changes nothing the scheduler
  sees.** It is a `thinkpad_acpi` DYTC hint to the firmware's power budget.
  Diffed across `low-power`/`balanced`/`performance`, the governor, EPP,
  `scaling_min_freq`, `scaling_max_freq` and `boost` are byte-identical. The
  waybar toggle cycled it for a year and moved a glyph and nothing else — and
  TLP rewrote it on every charger transition anyway. **Power modes are TLP
  profiles** (`docs/adr/0017`). Reaching for this attribute to
  change CPU behaviour ships a placebo.
- **`EPP=power` is not a cap.** It biases how eagerly the governor ramps; it
  sets no ceiling. With `boost=1` and no `scaling_max_freq`, a keystroke-sized
  task still hits 4.63 GHz and spikes the package to ~30 W. **The fan on this
  chassis tracks bursts, not averages**, which is why "low-power" idled at
  ~2340 RPM and 45–52 °C. Only `CPU_SCALING_MAX_FREQ_*` and `CPU_BOOST_*` stop
  it.
- ⚠️ **An unset TLP bound does not mean "no limit" — it means "don't write".**
  `set_cpu_scaling_min_max_freq` skips the write when
  `CPU_SCALING_MAX_FREQ_ON_<profile>` is empty, so the **previous** profile's cap
  survives the switch. Leaving fanless left every core pinned at its ceiling
  while waybar reported `performance`; caught only by reading `scaling_max_freq`
  directly. Every profile in `power.nix` now states both ends, including the two
  that want the full range. Check with
  `tlp-stat -p | grep scaling_m`, not with the bar.
- **A TLP setting the version does not read is accepted silently.** TLP 1.9.1's
  amdgpu branch folds `PP_BAL` and `PP_SAV` into one arm reading only
  `RADEON_DPM_PERF_LEVEL_ON_BAT` — there is **no** `_ON_SAV`. Written into
  `tlp.conf` it is inert and unlogged, which is why the iGPU pin lives in the
  `power-mode` wrapper instead. **Grep the installed TLP's `func.d/` for a
  setting before trusting it**, rather than the manpage: 1.9.1 also ships a
  `tlpctl(1)` page for a binary it does not install.
- ⚠️ **A sudoers rule naming a package's store path does not match the same
  binary reached through `$PATH`.** sudo-rs resolves the *directory* symlinks of
  the command it is handed and stops, so `sudo -n power-mode` canonicalises to
  `$system-path/bin/power-mode` — not to the `power-mode` package that
  `/run/current-system/sw/bin/power-mode` links to. The rule silently does not
  apply and the only symptom is `sudo: interactive authentication is required`,
  which looks like a missing rule rather than a mismatched one. `power.nix`
  lists **both** `${powerMode}/bin/power-mode` and
  `"${config.system.path}/bin/power-mode"`.
  **`sudo -l <cmd>` cannot detect this** — it exits 0 for anything wheel may run
  *with* a password, so it says "permitted" for a rule that will still prompt.
  Test with `sudo -n <cmd>` and read the exit code, and do not put a pipe
  between the two: `sudo -n … | tail` reports `tail`'s status, which is how this
  was first mis-verified as working.
- **`tlp` needs root and `sudo -n` fails loudly — let it.** The old cycle script
  redirected its own errors to `/dev/null`; the same habit hid 24 shellcheck
  findings once, and hid every failed sysfs write during the fan investigation.
  A write to `scaling_max_freq` as a non-root user fails and the shell carries
  on, so the sweep "ran" and measured the unmodified machine.

- ⚠️ **A `services.logind` change is not live after `switch` — logind is never
  reloaded, so the lid keeps the previous action until reboot.** nixpkgs sets
  `systemd.services.systemd-logind.reloadIfChanged` but leaves the matching
  `restartTriggers` line **commented out** (`nixos/modules/system/boot/systemd/
  logind.nix`), so a `logind.conf`-only change marks no unit as changed and
  `switch-to-configuration` reloads nothing. `/etc/systemd/logind.conf` reads
  correctly the whole time; only the daemon disagrees. Cost a whole overnight
  lid-close that suspended under the *old* handler. `power.nix` now declares the
  trigger. **Check the daemon, not the file:**
  `busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager HandleLidSwitch`.
  To apply by hand: `systemctl reload systemd-logind` — `Type=notify-reload`, so
  it re-reads config without dropping sessions. A *restart* would kill them.
- **Idle behaviour is not a power-management default — nothing supplies it.**
  There is no desktop environment here, so until swayidle got `timeouts` the
  machine had no dim, no idle lock and no idle sleep at all, and the only visible
  symptom was a battery that "seemed to go quickly". Check
  `services.swayidle.timeouts`, not TLP, when idle drain is the complaint.
- **The idle suspend's media check sees MPRIS only.** `playerctl` reports what
  publishes an MPRIS interface — ncspot, Spotify, browsers, mpv. A game, or a
  call in an app that publishes none, plays audio into a machine that sleeps
  under it. Video is unaffected either way: mpv and Firefox hold a
  `zwp_idle_inhibit` surface, which stops the ladder before any rung runs.
- **`poweralertd` alerts on every UPower device, headphones included.** `-S`
  restricts it to power supplies and `-s` drops the burst of current-state
  notifications at login. Without both, it looks broken rather than noisy.
- **A lit panel during suspend is a battery bug, not a cosmetic one** — the
  DISPLAY block tracks the CRTC, so it holds s0i3 off and the machine idles at
  ~4 W through what looks like sleep. **The backlight cannot fix it**;
  `brightnessctl` and `bl_power` only drive PWM, and hooks written that way
  succeed, exit 0, and change nothing. `wlopm --off '*'` is the mechanism.
- **s0i3 *is* reached now** — measured at ~0.15 W over a 9h37m lid-closed
  suspend (58% → 54%), against the ~3–4 W this file recorded when the panel
  stayed lit. The earlier "s0i3 is never reached even so, cause unknown" was
  written before the `wlopm` hooks landed and is retracted. Measure it the same
  way — battery percentage either side of a long sleep — rather than by eye; if
  the figure regresses, read `/sys/kernel/debug/amd_pmc/smu_fw_info` **first**,
  it names the offending IP block in one command.
- **Nothing locked the screen on sleep until swayidle** — logind's
  `HandleLidSwitch` suspends, it does not lock, so a closed lid resumed straight
  to the desktop. See the swaylock section for why the lock handler cannot be a
  `powerManagement` hook.
- **A lid action of `ignore` also means "do not lock".** The lock hangs off
  swayidle's `before-sleep`, so it fires only when something actually *sleeps*.
  `HandleLidSwitchDocked = "ignore"` therefore leaves a docked closed lid awake
  and unlocked — accepted here, since locking would lock the session out of the
  external display in use. It is easy to miss precisely because it looks like the
  lid doing nothing, which is what `ignore` is supposed to look like.
- **`lock` as a lid action is edge-only, and would silently not re-fire.**
  `manager_handle_action` bails on `HANDLE_LOCK` when `!is_edge`
  (`logind-action.c`), while sleep actions have no such guard. Since logind
  re-runs the lid decision at *level* for as long as the lid is shut, a `lock`
  branch fires once on close and never again — so it cannot pick up a later
  change like an undock. Sleep actions can, which is what makes undock-then-
  hibernate work with `ignore`. Read the source before assuming a lid value
  behaves like its neighbours.
- Verify the live values with `busctl get-property org.freedesktop.login1
  /org/freedesktop/login1 org.freedesktop.login1.Manager HandleLidSwitchDocked`,
  not the Nix — see the reload trap above.
- **upower's critical-battery percentages fail silently as a set**: give
  `percentageLow`/`Critical`/`Action` values that aren't strictly descending and
  it discards all three for its own defaults, unlogged — the action fires at a
  charge nobody chose. Check `/etc/UPower/UPower.conf`, not the Nix.
- **`HybridSleep` on a critical battery is not hibernation here** — it writes the
  image and then *stays in s2idle*, which at 3% charge is the one moment the
  machine must draw nothing. That is the NixOS default; this host sets
  `Hibernate`. (The ~3 W once recorded for that s2idle is from the same batch of
  short measurements as the retracted s0i3 figure above, and is not to be
  trusted. The decision does not rest on it: any suspend at 3% is wrong.)
- **`suspend-then-hibernate` on the lid was abandoned — logind's re-check
  degrades it to a plain `suspend`.** A spurious wake ends the s-t-h cycle
  outright; ~30 s later (`HoldoffTimeoutSec`) logind re-handles the still-closed
  lid and logs a bare `Suspending...`, *not* `Suspending, then hibernating...`.
  That is an unbounded s2idle with no hibernate timer behind it, which is where
  the resume hang below lives. Setting **both** lid handlers to s-t-h does not
  help — it was tried, and the re-check still degraded. Observed identically on
  three consecutive boots; every lid close ended in a power cycle. The lid now
  hibernates outright — the *lid* does. The 30-minute idle rung suspends
  (`docs/adr/0016`): every failure in this bullet is logind re-handling a lid
  that is still shut, and there is no lid switch to re-handle when the rung fires
  with the lid open. Do not generalise one to the other in either direction.
  - **Read the operation name, not the fact that it suspended.** logind logs a
    D-Bus request as `suspend requested from client PID … ('systemctl')`; the
    bare `Suspending...` with no such line is logind's *own* handler. That one
    distinction is what separates "a script did this" from "logind chose this".
  - Each wake coincides with the Synaptics reader (`06cb:00f9`) dropping off
    USB bus 1; the counters reset per boot, so it is unconfirmed. **The path is
    the parent, not the device** — `1-3` reads `power/wakeup` = `disabled`, but
    its XHCI controller `0000:74:00.3` is `enabled`, which is how a device
    leaving the bus raises a PME. Checking the device alone says "wakeup is off"
    and is not the answer. The reader is the only device on bus 1, so
    `echo disabled > /sys/bus/pci/devices/0000:74:00.3/power/wakeup` costs
    nothing. Untried on purpose: it would remove the confirming symptom. The
    idle rung's suspend (`docs/adr/0016`) is what produces samples.
  - **It also fails the other way: no spurious wake, and no hibernate either.**
    A 2026-08-11 lid-close logged `Suspending, then hibernating...` cleanly and
    then sat in s2idle for **9h37m** with `HibernateDelaySec=30m` set — the timed
    wake simply never fired, and nothing logged its absence. Suspect the alarm
    RTC: `rtc0` is `acpi-tad` with **no `wakealarm` attribute at all**, and only
    `rtc1` (`rtc_cmos`) reports "RTC can wake from S4". Unproven; two independent
    ways for s-t-h to end in an unbounded s2idle is the argument for not
    returning to it, whatever the wake source turns out to be.
- **Long s2idle sometimes never resumes, and it looks like a dead machine.** The
  panel is off (`wlopm --off` in `sleep-actions.service`'s `ExecStart`) and is
  only restored by `resumeCommands` in that unit's `ExecStop` — so a resume that
  hangs before then leaves a black screen and dead input, indistinguishable from
  a machine that is merely asleep. The tell is in the journal, not on the screen:
  a good wake logs `amdgpu … PCIE GART … enabled` and `SMU is resuming…`; the
  failing one logs neither and the boot's journal simply **stops**. Compare two
  wakes before blaming the display hooks.
- **Hibernation's `resume_offset` fails silently**: the machine boots fresh and
  discards the session, presenting as "hibernate didn't work". It is valid only
  for the exact swapfile that exists now.
- **The kernel log does not say whether a hibernate succeeded** — the image is
  snapshotted *before* the write, so success and refusal leave byte-identical
  traces. The primary signal is the machine physically powering off. Do not set
  `HibernateMode=shutdown` on that misreading; it was tried and reverted.
- ⚠️ **Hibernation entry is a multi-second window, and reopening the lid inside
  it hung the machine outright.** 2026-08-13 04:11:51 `Lid closed.` →
  `Hibernating...` → 04:11:52.78 `PM: hibernation: hibernation entry`, and that
  is the **last line of the boot**. The lid was reopened <5 s later; the machine
  was dead — no panel, no input — and had to be power-cycled. The next boot at
  04:12:38 logged `PM: Image not found (code -22)`, so **no image was ever
  written**: the hang is in the entry phase, before the snapshot, not in resume.
  This is distinct from the s2idle resume hang below — that one ends a boot at
  `PM: suspend entry (s2idle)`.
  - **The window is not instantaneous.** Preallocation alone measured **7.10 s**
    and **22.17 s** on the two hibernates either side of this one
    (`PM: hibernation: Allocated … kbytes in N seconds`), on top of process
    freeze and device suspend. Any lid-open within ~20 s of a lid-close lands
    inside it. Treat a short lid close as the hazard case, not the cheap one.
  - **How to tell a hang from a success, since both look like silence.** A
    hibernate that *worked* replays its entry-phase kernel lines at **resume**
    time — the kmsg buffer is inside the image — so `Marking nosave` …
    `hibernation exit` all arrive with the resume's timestamp, hours after the
    entry line. Aug 12 18:08:06 entry → Aug 13 00:58:35 replay is the good
    shape. A journal that **stops** at `hibernation entry` and is followed by a
    fresh boot logging `Image not found` is the hang. There is no third signal:
    journald is frozen for the whole entry phase, so nothing written after the
    freeze survives unless a resume flushes it.
  - **Correlate, unconfirmed:** `power-mode power-saver` ran **2.5 s** before the
    lid close, so the entry ran with the CPU capped at 1115770 kHz, boost off,
    and the iGPU pinned to DPM `low` — i.e. the slowest possible version of the
    window it then had to survive. Worth checking against the mode at the time
    before blaming the lid alone.
  - **Mitigated, not fixed.** `powerDownCommands` now un-throttles before
    `sleep.target` (`docs/SYSTEM.md` §9, `docs/adr/0017`), which removes that
    correlate and shortens the window. It does not make the window safe, and the
    hang has **one** observation behind it — do not read a quiet month as proof.
    ⚠️ **Order the writes: boost first.** With boost off the driver clamps
    `cpuinfo_max_freq` to the 2901000 nominal, so reading the ceiling before
    lifting boost uncaps the CPU to *nominal* and looks like it worked. Verified
    both ways live: `boost=0` → `cpuinfo_max_freq` 2901000, `boost=1` → 4630443.
- **Re-test "this protocol isn't available" claims.** This file long asserted
  mango advertised no `wl_output`, so DPMS was impossible — which is what sent
  sleep blanking down the backlight path that could never have worked, and cost a
  flat battery to discover. `wlopm --json` is one command.
- ⚠️ **Turning off power-profiles-daemon removed the *answer*, not just the
  second tuner.** PPD is also the interface desktops use to *ask* what the power
  profile is, so `services.power-profiles-daemon.enable = false` left every such
  client — noctalia's control-centre button, GNOME's power page,
  `powerprofilesctl` — finding no service and rendering a greyed control, in
  silence, for months. `power-profiles-tlp` now owns that bus name and answers it
  from TLP (`docs/adr/0026`). **When a daemon is disabled because it conflicts,
  check what else was reading its interface.**
- ⚠️ **A running unit is not an activatable bus name, and `systemctl status`
  cannot distinguish the two.** `power-profiles-tlp` came up, owned the name,
  and answered `busctl` correctly — and noctalia still did nothing, because
  quickshell probes the name at *its* startup, tries to **activate** it when
  unowned, and gives up for the life of the process. The tell was an hour-old
  journal line, `Could not launch service …: The name is not activatable`,
  followed by `The PowerProfiles service will not work`. Meanwhile
  `noctalia-shell ipc call powerProfile set balanced` printed nothing, which by
  `docs/adr/0023`'s rule looks like success. **Any daemon here that owns a bus name
  a desktop client consumes needs `share/dbus-1/system-services/<name>.service`
  with `SystemdService=`**, not just a `wantedBy` unit. `checks/static.sh`
  asserts it.
- **An XML comment may not contain `--`, and dbus rejects the whole file if one
  does.** The first draft of `pkgs/power-profiles-tlp/dbus-policy.conf` had a
  prose double hyphen in its header comment. Since that file is loaded by the
  *system* bus, the blast radius is every service on it, not the one being
  added. `checks/static.sh` runs `xmllint --noout` over it; keep prose dashes
  single.
- **`services.tuned.ppdSupport` is the off-the-shelf version of this and is the
  wrong tool here.** It does claim both PPD bus names, but it translates into
  *tuned* profiles, which set governor and EPP themselves — a second owner on the
  cpufreq path alongside TLP (`docs/adr/0005`), and every number in
  `docs/adr/0017` was measured with TLP applying them alone.
- **Reading a Qt/QML client's D-Bus contract needs `strings -e l`.** The profile
  names quickshell parses (`power-saver`, `balanced`, `performance`) are UTF-16
  literals in the binary and do **not** appear in a default ASCII `strings` dump
  — which looks like "the names are unconstrained" rather than "the scan missed
  them".

### `wantedBy` a target the unit is transitively ordered after deletes its start job

`power-profiles-tlp` (`docs/adr/0026`) declared `wantedBy = [ "multi-user.target" ]`
and `after = [ "tlp.service" ]`, and **never started at all** — no failure, no
`systemctl --failed` entry, just an inactive unit and a bus name nobody served.

A target implicitly gains `After=` on everything in its `Wants=`, *unless that
unit already orders itself against the target*. Upstream `tlp.service` is
`After=multi-user.target`. So the `wantedBy` alone closed a three-unit cycle —
target after us, us after TLP, TLP after target — and systemd broke it the way it
always does, by **deleting a job**; ours:

```
multi-user.target: Found ordering cycle: power-profiles-tlp.service/start after
  tlp.service/start after multi-user.target/start - after power-profiles-tlp.service
multi-user.target: Job power-profiles-tlp.service/start deleted to break ordering cycle
dbus-broker-launch[…]: Activation request for 'org.freedesktop.UPower.PowerProfiles' failed.
```

D-Bus activation cannot rescue it either — the cycle is in the transaction, so
every activation attempt fails identically. To a client this is indistinguishable
from the unit not existing.

The fix is to name the target in `after` as well as `wantedBy`, which suppresses
the implicit edge. `wifi-resume` in `networking.nix` already does this against
`suspend.target`; that is the pattern, not redundancy — **don't "tidy" a target
out of an `after` list that also appears in `wantedBy`.**

Confirm which way a unit sits, on the running system rather than in the file
(the edge is implicit, so it is *not* in the generated unit):

```console
$ systemctl show multi-user.target -p After | tr ' ' '\n' | grep power-profiles-tlp
multi-user.target-after=power-profiles-tlp.service   # ← cycle
$ systemctl show suspend.target -p After | tr ' ' '\n' | grep wifi-resume
                                                     # ← empty: correct
```

`journalctl -b | grep 'ordering cycle'` is the general scan, and is worth running
after adding any unit with both `wantedBy` and `after`.

### The amdgpu/TTM freeze

A GPF in `ttm_lru_bulk_move_tail` kills the faulting task **while it still holds
the TTM `lru_lock`**, so every later GPU touch deadlocks and one oops becomes a
total hang. Power-cycling mid-freeze then **latches the i8042**, so the next boot
has a greeter that accepts no keystrokes — which looks like a PAM/greetd fault
and is not; a full power cycle clears it.

Mitigated, not fixed: Overdrive removed (the prime suspect and the differentiating
variable vs Arch), `kernel.panic_on_oops = 1` + `kernel.panic = 10` (which is what
breaks the double-hard-reset chain), `kernel.sysrq = 1`. **No kernel version
change will fix this** — the code has been unchanged since 2021, so there is
nothing to bisect. Don't drop to `pkgs.linuxPackages` hoping otherwise.

**Reading an old journal as `henry` greps to zero exactly like a clean history.**
`system@*.journal` is ACL'd to a GID this user is not in, so an unprivileged
`journalctl -D <dir>` silently reads only the `user-1000@` session files, which
carry no kernel messages. This produced a confident "zero crashes on Arch" that
was an artefact of the read. Confirm the `Linux version` lines are non-empty
before believing any zero.

### linux-firmware 20260910 breaks the panel

After the re-lock to linux-firmware 20260910, the internal panel rendered in the
top half with streaks below. Rolling back fixed it. The build and the switch
reported nothing. The cause is `amdgpu/yellow_carp_dmcub.bin`: 20260910 ships
DMUB `0x0400004A`, older than 20260810's `0x0400004C`, and it fails to load:

```
[drm] *ERROR* Error getting DMUB FW meta info: 4
failed to load ucode DMCUB(0x3F)
[drm] *ERROR* dc_dmub_srv_log_diagnostic_data: DMCUB error - collecting diagnostic data
```

It was the firmware, not the kernel. Boots on kernels 7.2.5 and 7.2.6 both broke
with 20260910, and generations 166 and 167 had the same kernel.

**Fixed upstream in 20260916, which ships 20260810's file back byte-identical**
(`sha256:4bcb91d5…`), so the `pkgs.yellow-carp-dmcub` pin is retired. Comparing
the two blobs settled the retest without a reboot — identical bytes cannot load
differently. Confirmed on kernel 7.2.8: `Loading DMUB firmware via PSP:
version=0x0400004C`.

`checks/static.sh` now hashes the decompressed blob the system ships rather than
asserting which package carries it. That survives the pin's removal, and it
fires if the regression returns through any package. Firmware loads at boot, so
a change here is tested with `boot` or `switch`, never `test`. The tell is
`journalctl -k -b | grep 'Loading DMUB'`.

---

## Editors

**No mason — language servers come from `$PATH`**, so they must be declared in
`modules/home/packages.nix`. A missing server is **skipped in silence**: after
the migration only `rust-analyzer` worked, and nobody noticed for a day. All 12
resolve now.

```sh
for s in nil lua-language-server bash-language-server marksman taplo \
         yaml-language-server pyright ruff clangd typescript-language-server \
         texlab tinymist stylua shfmt gopls; do
  command -v $s >/dev/null || echo "$s MISSING"
done
```

**`typescript-language-server` does not bundle `tsserver`** — nixpkgs ships it
with an empty `node_modules`, so it resolves typescript from the workspace or
`$PATH`. Without a separate `typescript` entry the server starts and then fails
on any file outside a project with its own `node_modules`, which looks like the
server being broken rather than absent.

**Helix was removed 2026-08-17** (`docs/adr/0027`) — nvim is the only editor
this repo configures. Its `hx --health <lang>` was the fastest way to audit
servers, one line per language with `✘` against anything missing; the surviving
equivalents are the loop above and `:checkhealth lsp`. Both must be read by
**output**, not exit status — a missing server is silence either way.

`$EDITOR`/`$VISUAL` are `nvim` — that is what git, `sudoedit`, `systemctl edit`,
lazygit and yazi invoke, so changing editors means changing those, not adding an
alias. `mimeapps.list` separately points markdown and shell scripts at
`nvim.desktop`, which governs GUI double-clicks only.

`nvim` stays hand-written on purpose — see `docs/SYSTEM.md` §6. See also
`docs/adr/0007`.

---

## Theming

### A GTK theme with no `gtk-4.0/` unstyles every libadwaita app, silently

`gtk.gtk4.theme` makes home-manager write an `@import` into
`~/.config/gtk-4.0/gtk.css` — GTK4 ignores `gtk-theme-name`, so user CSS is the
only way in. The import names `<theme>/gtk-4.0/gtk.css` inside the package, and
**nothing checks that the file exists**:

```
Gtk-WARNING: Theme parser error: gtk.css:5:1-132: Failed to import:
  Error opening file /nix/store/…-gruvbox-dark-gtk-1.0.2/share/themes/gruvbox-dark/gtk-4.0/gtk.css:
  No such file or directory
```

`gruvbox-dark-gtk` ships `gtk-2.0`, `gtk-3.0`, `gtk-3.20` and nothing else. GTK3
apps are themed, GTK4/libadwaita apps drop to Adwaita, and the only symptom is
two toolkits looking different — which looks like libadwaita being libadwaita.
`catppuccin-gtk` and `nordic` both ship `gtk-4.0`, so this was a gruvbox-only
hole, and it arrived with the scheme rather than with any change to the GTK
config. Found 2026-08-19, in session output that had been printing to the
greeter's VT unread — see Desktop, above.

The scan in `checks/static.sh` did not catch it, because it asserted
`share/themes/<name>` resolves — one directory level above the file that was
missing. **A theme directory existing is not the same as a theme being
usable.** It now asserts `<name>/gtk-4.0/gtk.css` is readable as well.

Fixed by building the theme instead: `pkgs/default.nix` packages
`Fausto-Korpsvart/Gruvbox-GTK-Theme` (`Gruvbox-Dark`), whose installer compiles
the GTK4 SCSS. Nixpkgs has no gruvbox GTK theme that ships `gtk-4.0` — check
before assuming a rename will do.

**Colours are generated from a single Nix palette** — `modules/home/palette.nix`,
feeding kitty, foot, swaylock, imv, ncspot, nvim, mango, swaync, Equibop, the
lock-background ramp, the bar's `colors.css` and rofi's `colors.rasi`. Change it
once and rebuild. See `docs/adr/0028`.

**Grepping for a hex code does not find every copy of it.** The 2026-08-17 audit
found twelve copies the palette was not reaching, in five spellings — mango
writes `0xd79921ff`, swaync writes `rgb(215, 153, 33)`, and nvim and the
GTK/Kvantum/cursor/noctalia themes carry no hex at all. A repo-wide grep for
`d79921` found **neither** decimal copy. `checks/static.sh` now asserts the
accent is present in each consumer's own spelling, and — the other direction —
that no palette hex appears anywhere in `dotfiles/` outside the exempt
third-party theme data (Kvantum, the GTK Breeze files).

**That scan reads its needles out of `palette.nix`.** It used to carry its own
list of twenty gruvbox hex values, which would have survived the 2026-08-18
Catppuccin migration by matching nothing and reporting success — the exact bug
the scan exists to find, inside the scan. It now extracts the values from the
palette and **fails below sixteen of them**, so a sed that stops matching is
loud rather than reassuring.

**The artefacts the palette cannot reach are declared in the theme file**, since
`docs/adr/0032`: the GTK theme, GTK4 (follows it), icons, cursor, Kvantum, yazi's
flavor, and the names noctalia, nvim and Zed resolve internally. They live in the
`packages` and `apps` blocks of `modules/home/themes/*.nix`; `pkgs/default.nix`
resolves them and `checks/static.sh` asserts each resolves to a real directory.
Before that they were spelled across six files with nothing checking them.
**`docs/THEME-MIGRATION.md` is the runbook**, and its §2 has the availability
matrix.

**These names are not guessable from the attribute that builds them.** Catppuccin
is `mochaMauve` → `catppuccin-mocha-mauve-standard` (GTK),
`catppuccin-mocha-mauve-cursors`, `catppuccin-mocha-mauve` (Kvantum) — four
spellings. `nordic` ships `Nordic-darker` and `Nordic-Darker` in one package.
`capitaine-cursors-themed` installs `Capitaine Cursors (Gruvbox)`, parentheses
included. **A GTK theme name matching nothing falls back to Adwaita without
logging.** Read the name off the built package:
`ls "$(nix build --no-link --print-out-paths nixpkgs#<attr>)/share/themes"`.

**A name only the toolkit can resolve is a name no check can.** `Adwaita-dark`
renders — GTK3 has it compiled in — and no directory for it exists anywhere. If a
name works on screen but the check cannot find it, that is the check working.

**The cursor has a consumer outside the theme file, and it kept the old scheme's
name for two migrations.** `dotfiles/mango/universal/settings.conf` set
`cursor_theme=catppuccin-mocha-mauve-cursors` by hand. Under gruvbox and nord
that package is not installed at all, and mango does not complain: it passes the
name to `wlr_xcursor_manager_create`, which falls back to its own default. The
pointer simply stops matching the scheme, which looks like a cursor someone chose.

The second half is worse. mango `setenv`s `XCURSOR_THEME` from that value
(`src/config/parse_config.h`), and every client it spawns inherits it — so one
stale line in a tier-2 file overrode `home.pointerCursor` for the whole session.
**A terminal hid this**: zsh re-sources `hm-session-vars.sh`, which sets
`XCURSOR_THEME` back to the correct name, so anything checked from a shell
reported the right theme while GUI apps launched from a keybind got the wrong
one. Checking `env | grep XCURSOR` in a terminal is not evidence.

Now generated: `modules/home/dotfiles.nix` emits
`mango/universal/cursor.conf`, `source=`d by `settings.conf`, reading
`config.home.pointerCursor` so the compositor cannot disagree with GTK and
`~/.icons/default` about the theme or the size. `checks/static.sh` asserts the
generated name equals the scheme's, and that no hand-written file under
`dotfiles/mango` sets `cursor_theme` again. mango resolves a `source=./…` path
against the config-dir root at any nesting depth, so the include works from
inside `universal/`.

**No shipped scheme uses a `native = false` stand-in, and that is the selection
criterion.** noctalia constrains the set: it resolves its palette from a name in
its own shipped Assets, so a scheme it does not ship leaves half the screen on a
different palette. Of its ten, nixpkgs fully serves Catppuccin, Gruvbox and Nord.
Rose Pine is the nearest miss, short only a GTK theme.

**ncspot's `muted.err` is a BACKGROUND, and the check measured it as text.** It
sets `error_bg`, with `error_fg` (= `muted.fg`) on top. The check compared it
against `muted.surface` — a pair ncspot never renders — and reported 7.05:1 for a
row measuring **1.28:1** on the running machine. Every theme carried it.
**A check measuring the wrong two colours is worse than no check, because it
reports a number.** `docs/adr/0032`.

**Contrast has two floors, and there is no minimum under them.** `contrastFloor`
is what this machine draws text with; `ansiFloor` is the sixteen terminal slots,
which nothing here draws text in — gruvbox's normal red is 2.69:1 by upstream's
design, so one shared floor would have had to be 2.6 and would have let
`comment` rot to meet it. The global `HARD_MIN = 3.0` was removed 2026-08-18 as
an invention: it arrived with `mocha-high-contrast` out of a request for readable
text, then read like an external requirement, and it would have forbidden Nord at
1.69:1 as published. **Upstream values ship as published; values this repo
derives are chosen to be legible.**

**Python's `round()` is round-half-to-even, and it broke the lock ramp.** The
background pool interpolated all three channels independently and trusted them to
round alike; at `t=.25` the triple `(5, 8, 14)` rounds to `(6, 10, 16)`, a hue
shift. It only diverges when the half-case lands *and* the integer parts differ
in parity — gruvbox's `#282828` is three equal channels, Mocha's `#1e1e2e` three
even ones, so both shipped schemes hid it. It surfaced while evaluating Ayu,
whose `#0b0e14` is (11, 14, 20) and drifted on 4 of 9 tones — Ayu was not kept,
but the bug it exposed is real for any palette whose channels differ in parity.
The ramp now interpolates one channel and derives the others from fixed
offsets, so hue preservation is structural rather than an accident.

**ImageMagick picks a colorspace from content, and a neutral palette is Gray.**
The lock pool's own checkPhase failed under gruvbox claiming the green channel
was 0, when the pixels were correct: `#282828` is `r=g=b`, so the PNG was written
as Gray and `mean.g` reads 0. The 2026-08-18 pass generalised that check from
`R = G = B` to per-channel offsets and fixed the tinted case while opening the
neutral one — both schemes it was tested against were tinted. Now `-type
TrueColor` on write and `-colorspace sRGB` on every measurement.

**mango's colours need a `rebuild`, not a `mango-reload`.** They are generated
into `universal/colors-<mode>.conf` and live in the store like everything else
under `dotfiles/mango/`. Reloading alone re-reads the *last* rebuild's copy,
which looks exactly like the change having had no effect.

**`dotfiles/swaync/style-body.css` is a fragment, not a stylesheet.** Its
`:root` block is generated from the palette and concatenated on at build time.
Opening the file and finding no colours defined is the expected state.

**GTK theming is owned by Nix** (`modules/home/theme.nix`), not by the mode
scripts: both `settings.ini` files, both `gtk.css` files, the Thunar bookmarks
and the dconf keys. `gtk-apply.sh` now only exports `GTK_THEME` to the systemd
user environment and restarts `xdg-desktop-portal-gtk` (which caches the theme at
startup). **Never have both setting the theme** — one owner, in either direction.
See `docs/adr/0004`.

> It **reads the name out of the generated `gtk-3.0/settings.ini`** rather than
> carrying its own literal, and refuses to export an empty one. A stale literal
> there would have overridden the correct settings for every user service
> started afterwards — the export is the more authoritative of the two.

**A GTK theme can be deleted from nixpkgs underneath the config, and the failure
is an eval error naming an untouched package.** GTK2 went, taking
`gtk-engine-murrine` with it, and murrine's reverse dependencies were removed
rather than fixed — `gruvbox-gtk-theme` and `gruvbox-material-gtk-theme` both, on
2026-07-22. It aborts the whole config before any build starts, on the next
`nix flake update`, so it looks far worse than it is. This repo carried a
vendored copy (the removed derivation minus murrine) until the Catppuccin
migration on 2026-08-18 retired it; `catppuccin-gtk` is in nixpkgs, so there is
nothing to vendor.

> The removal left one trap behind: the vendored attribute had been **shadowing**
> nixpkgs' tombstone, so deleting it from the overlay un-hid the `throw` and
> `modules/system/desktop.nix` — which listed the theme among `systemPackages`
> a long way from `theme.nix` — failed the eval. When retiring a vendored
> package, grep for the *attribute name* across the whole repo, not just the
> module being edited.

> Any theme still carrying a `gtk-2.0/` directory is a candidate to go the same
> way. The tell is a removal notice in nixpkgs' `pkgs/top-level/aliases.nix`
> quoting a *transitive* GTK2 dependency, not a problem with the package itself.

**Papirus folder icons are recoloured at build time.** Stock folders are blue,
which looks badly broken against a non-blue scheme — the symptom is Thunar
looking correctly themed *except* every folder. The usual fix, the
`papirus-folders` CLI, recolours the theme **in place** and so cannot work: the
icon theme is a read-only store path, and the tool silently achieves nothing.
`pkgs/default.nix` overrides the package with `color = "violet"` instead —
Papirus's nearest name to Catppuccin's mauve, since **the folder colour is chosen
from Papirus's own list, not supplied as hex**. It is done in the
**overlay** rather than at the call sites because both `gtk.iconTheme.package`
and `systemPackages` reference the theme — overriding one would put two Papirus
derivations on `XDG_DATA_DIRS` and let lookup order pick the folder colour.

**Indirection that selects nothing is this repo's recurring dead weight.**
`kitty/active-theme.conf`, the `gtk-*-tiling` variants and `waybar/style.css`
were each a switch whose arms were identical or unreachable, left behind when the
`dms` mode was removed. Before adding a per-mode variant, check the modes
actually differ.

**A Nerd Font package and its unpatched twin have different family names.**
`_0xproto` is family `0xProto`; only `nerd-fonts._0xproto` is
`0xProto Nerd Font Mono`. kitty's `bold_font`/`italic_font` asked for the latter
while `fonts.nix` installed the former, so both lines fell back to Hack and bold
text simply looked normal — nothing logged, for months. Same class as the 3270
miss above it. **`fc-match` will not catch this**: it matches on *family* alone,
so `fc-match "0xProto Nerd Font Mono Bold"` reports a fallback even when the font
is installed correctly. Verify with the application's own resolver —
`kitty --debug-font-fallback` prints the file it actually opened for each of
Normal/Bold/Italic/Bold-Italic. 0xProto ships no bold-italic, so that one variant
is Hack by design.

**`programs.ncspot.settings` must stay `{ }`, and that is load-bearing rather
than leftover.** ncspot's whole config is its theme, so since `docs/adr/0034`
phase 3 `~/.config/ncspot/config.toml` is a runtime symlink `apply_theme()`
re-points per mode. The home-manager module wraps its own
`xdg.configFile."ncspot/config.toml"` in `mkIf (cfg.settings != { })`, so an
empty set installs the package and claims no path — but **one** value there
re-claims it, and two owners for one path is an activation failure, not a merge.
Any future non-theme ncspot setting belongs in `mode-theme.nix` with the
colours. `checks/static.sh` asserts the path is absent from the generation.

**ncspot draws from the `muted` set, and a colour from the wrong HALF of the
right scheme is invisible to an accent scan.** Writing `p.accent` where
`m.accent` was meant produces a file that still contains the muted accent
somewhere, so the needle check passes — measured, that exact edit passed every
other assertion in `checks/static.sh`. The check that catches it asserts every
hex in ncspot's generated config is a value from that scheme's `muted` set,
which is only stateable because ncspot is the one consumer drawn entirely from
one half.

**Some applications hold a theme *name*, and the palette cannot reach those
either.** Beyond the six packages above: lualine's `theme`, lazy.nvim's
`install.colorscheme` fallback, Zed's `theme.dark`/`light`, and the Equibop
`enabledThemes` line in `mango/scripts/lib.sh`. A scheme migration has to grep
for the old scheme's *name*, not just its hex — none of these carry a colour.

> **Zed is the sharp one: Gruvbox ships inside Zed, Catppuccin does not.**
> Renaming the theme without `programs.zed-editor.extensions = [ "catppuccin" ]`
> leaves Zed on One Dark, logging nothing.

**Equibop enables its theme by FILENAME, and ignores a name that matches
nothing.** `apply_theme()` in `mango/scripts/lib.sh` writes `enabledThemes` on
every mode switch, and the file it names is generated by `dotfiles.nix` into
`~/.config/equibop/themes/` — two halves, in different languages, in different
directories, with nothing but a string in common. Rename one and Discord goes
unstyled with nothing logged anywhere. `checks/static.sh` now asserts the two
agree; that assertion exists because the rename is the obvious move and the
failure is invisible.

> Since `docs/adr/0034` phase 3 the name is the **mode's** —
> `<mode>.theme.css`, one generated per mode — so what the check asserts is
> that lib.sh's suffix and the generated set agree for *every* mode. That is
> also why Equibop needed no symlink to join the per-mode swap: a name it reads
> out of its own settings file is the indirection the other four consumers had
> to be given.

> **A rebuild alone does not enable it.** `enabledThemes` is written by the mode
> scripts, so the generated theme can be sitting in `~/.config/equibop/themes/`,
> correct and unreferenced, while Discord still wears the old one. It self-heals
> on the next mode switch; `mmsg dispatch reload_config` on its own does not do
> it, because that reloads the compositor without running `mode.sh`. This is what
> the static check cannot catch — it asserts the two *names* agree, not that the
> setting was ever applied.

> The theme itself is **generated**, on the swaync pattern: hand-written layout
> in `dotfiles/equibop/theme-body.css` with no hex in it, and the `:root` block
> plus `.hljs` rules appended from the palette at build time. The fragment leads
> rather than trails — CSS requires `@import` before every other rule, and the
> midnight-discord framework is imported at the top of it. It was an untracked
> hand-written file in `~/.config` until 2026-08-18, which is the same shape as
> the swaylock config that quietly supplied a theme before it.

**A `#` line inside a Nix `''` string is not a comment — and it is not one in
Lua either.** A comment written into the `nvimPalette` block was emitted
verbatim into the generated `palette.lua`, which then failed to parse. Every
gate passed: `nix flake check` built it, `checks/static.sh` grepped it for the
accent and found one, and nvim reports a failed plugin config and falls back to
*no colourscheme* — which looks like a theme that did not apply, not a syntax
error. The derivation now runs `luajit -b` over the result, so a malformed
generated Lua fails the build. Put the explanation in the Nix source above the
string, never inside it.

**Which colour a program actually uses is a MEASUREMENT.** nvim paints `Comment`
with Catppuccin's `overlay2` and NonText/Conceal/FoldColumn with `overlay1` —
established by asking the running editor (`nvim_get_hl`), after a first pass
read the plugin's source, assumed `overlay0`, and was wrong by a factor of two
in contrast. A colour the palette does not *name* escapes to upstream and is
invisible to every audit here, because no file in this repo contains it. That is
how the most-read dim colour on the machine sat outside the palette through an
entire migration.

**Contrast is asserted per theme, and the floor is declared by the theme.**
`checks/static.sh` recomputes WCAG ratios for every text role on each run —
against `bg0`, and for ncspot's `muted` set against *its own* raised surface,
since ncspot fills whole rows with that colour and `bg0` is the wrong reference.
Checking against `bg0` passed three values that fail where they are drawn. The
floor is per-theme because upstream Catppuccin Mocha does not reach WCAG AA on
its greys (`brBlack` is 4.44:1), so a global 4.5 floor would make it impossible
to ship Mocha as Mocha. `docs/adr/0030`.

**The lock-screen ramp asserts the palette's hue, not greyness.** The background
pool is a ±6 lightness ramp through `bg0`, and `pkgs/default.nix` fails the
build if any generated tone drifts off `bg0`'s channel offsets. It read
`R = G = B` until 2026-08-18 — correct while the base was gruvbox's `#282828`,
and an outright blocker for Mocha's `#1e1e2e`, which is blue-tinted by 16. The
check was generalised rather than deleted, because the failure it catches is
real: the lock screen is the one surface that can end up wearing a colour the
palette never named, and nothing about it looks wrong at a glance. If changing
`bg0`, there is nothing to update here — the ramp is derived from it.

### Three colour includes, three different failures — and foot is the loud one

kitty, foot and rofi each read their palette through a runtime symlink since
`docs/adr/0034`. What each does when the link is missing or dangling was
**measured on 2026-08-19**, not assumed, and they do not agree:

| | Missing include | Symptom |
|---|---|---|
| rofi | skipped, nothing logged | built-in Solarized; looks like a theme |
| kitty | skipped, nothing logged | `color0` and `background` both `#000000` |
| foot | `failed to open`, **exit 230** | **foot does not start** |

The design that produced these assumed all three were silent. Two are. foot
refusing to start is not a worse bug — it is the only noticeable one — but
it means the seed in `modules/home/mode-theme.nix` is load-bearing for *having a
terminal*, not for having a styled one. Do not remove it on the grounds that
`apply_theme` makes the links anyway: `apply_theme` runs on a mode SWITCH, and a
fresh machine has not had one.

Reproduce:

```sh
# with ~/.config/foot/themes/noctalia moved aside
foot --check-config; echo $?      # 230, and it says which line
```

**foot also cannot reload.** 1.27's `SIGUSR1`/`SIGUSR2` switch between the
`[colors-dark]`/`[colors-light]` sections *already loaded* — there is no config
re-read at all, so a swap reaches **new windows only**. `apply_theme` says so in
its notification every time, because a terminal that did not change colour with
everything else looks like the swap being broken. kitty's `SIGUSR1` does work.

### A hex no theme declares is invisible to the drift ceiling

`checks/static.sh` scans hand-written files for palette colours by grepping for
the hexes `modules/home/themes/*.nix` **currently** declare. A colour that no
theme names matches none of them — so an orphan left behind by a retired scheme
passes the ceiling built to catch exactly that.

`inactive_tab_foreground = "#d5c4a1"` — gruvbox's `fg2`, which this palette has
no role for — sat in `modules/home/programs.nix` as kitty's inactive tab colour
through gruvbox → Catppuccin Mocha → gruvbox. Found by hand on 2026-08-19 while
moving kitty's colours out, not by any check. It is `p.subtext` now.

Closed by a second, differently-shaped assertion: **no six-digit hex literal in
any `.nix` outside `modules/home/themes/`.** The pass state is zero matches, so
the floor is on the number of files scanned rather than on the match count.

### noctalia's theming templates un-manage a file rather than failing on it

`templates.activeTemplates` renders noctalia's palette into a sidecar per app,
then runs a post-hook that edits the app's real config to point at it. Three of
those hooks contain deliberate NixOS handling, and it is the wrong kind —
measured 2026-08-20 against noctalia-shell 4.7.7:

| Template | What the hook does to a store symlink |
|---|---|
| GTK | `gtk-refresh.py` detects a "read-only symlink (e.g. NixOS)", then **unlinks `gtk.css` and writes a local copy** |
| mango | `cp --remove-destination` over it, and strips colour vars from every top-level `*.conf` |
| yazi | `sed -i` on `theme.toml`, which **is** a home-manager symlink |

None of that errors. The app starts, the colours are fine, and the repo has
quietly stopped owning the path — a later `nixos-rebuild switch` neither restores
it nor complains, because home-manager sees a regular file where it expected its
own link.

The quieter half: kitty's hook writes `current-theme.conf` and foot's *sidecar
is* `themes/noctalia`, both owned by `apply_theme` (`docs/adr/0034`). The rest
write files nothing here reads, so they look like they worked.

**Off permanently and asserted — `docs/adr/0036`**, which carries the
per-template measurements and the test to apply before ever enabling one.

### A contrast floor that audits one scheme passes a mode nobody can read

`checks/static.sh` measured every text role against its theme's declared floors
— for **the scheme `scheme.nix` names**, because `flake.nix` passed it exactly
one resolved palette. That was correct until `modules/home/modes.nix` landed
(`docs/adr/0034`) and a second scheme went on screen in noctalia mode. The
second one would then have been unaudited, with the check still printing a green
line about the first: the scan passing by never looking at the thing that
changed, which is what every floor in this file exists to prevent.

Caught before it shipped, and only because the phase that introduced the second
scheme also looked at what the check was reading. The fix is the shape, not the
loop: `flake.nix`'s fourth argument is now `{ artefact, modes, schemes }` where
`schemes` holds **every scheme in service**, deduplicated and built from the
same two files that put them there. Adding a mode scheme cannot add an unaudited
one — there is no list to remember to update.

nord's numbers had never been measured before this. They pass.

---

Baseline: **whatever `modules/home/scheme.nix` names** — currently `gruvbox`.
That is the **artefact** scheme (widget art, icons, cursor, yazi, nvim, Zed) and
the default for every colour consumer. `modules/home/modes.nix` names a colour
scheme **per desktop mode** (`docs/adr/0034`); `noctalia` mode is currently
`nord`, which reaches mango's chrome and noctalia's own palette and nothing else
yet. Hack Nerd Font Mono 11 in the terminals, with kitty bold/italic in 0xProto
Nerd Font Mono. Modes are **tiling** and **noctalia**; the active one is
in `~/.local/state/mango/current-mode`.

---

### `xrdb` failing a cosmetic reload aborts the whole home-manager generation

`nixos-rebuild switch` returned **exit 4** with the switch already applied, and
the only clue was two lines in the journal:

```
xrdb: Connection refused
xrdb: Can't open display ':1'
home-manager-henry.service: Main process exited, code=exited, status=1/FAILURE
```

home-manager's `xresources` module hangs an `onChange` on `.Xresources` that
guards with `[[ -v DISPLAY ]]` and then runs `xrdb -merge`. **Set is not the
same as reachable**: on a Wayland session `DISPLAY` can name a socket that is
not there, so the guard passes, `xrdb` exits 1, and the activation script — which
runs under `set -e` — takes the whole generation down with it. The switch had
already happened, so the system was fine and the report said otherwise.

Two things made it routine rather than a curiosity:

- `.Xresources` carries `Xcursor.theme`, so **every scheme change rewrites it**
  and fires the hook (`docs/adr/0041`).
- The `DISPLAY=:1` was itself wrong — see *Session environment* below, which is
  the more expensive half of this and was found by chasing this.

`modules/home/theme.nix` overrides the hook with `lib.mkForce` and an `|| true`.
Nothing in this session loads `.Xresources` — `xsession.profileExtra` does not
run here — so the merge is best-effort by definition and must not be able to
abort anything.

**Key the override by `config.xresources.path`, not `".Xresources"`.** That
option is an *absolute* path, and home-manager writes `home.file.${cfg.path}`;
a relative key defines a second, sourceless entry instead of overriding the
first, and the failure is an eval error about `.source` having no value.

## Networking

Full detail in `docs/SYSTEM.md` §9. The three things that mislead:

**`nmcli dev wifi` is a scan, and it blocks.** "By default, nmcli ensures that
the access point list is no older than 30 seconds and triggers a network scan if
necessary" — `nmcli(1)`. So a status reader that reaches for it pays for a full
scan whenever it has been more than 30 seconds since the last one: **6.4 s
measured** on the first open of `menus/control-center.sh`, during which the menu
had not appeared at all, because Network is its first row. Nothing errors and
nothing logs; it looks like the key not working.

`menus/network-menu.sh` carries its `/tmp` cache and its `--warm` verb for
exactly this, and it is the reason to reach for it. For *status* — "am I on, and
on what" — use `nmcli -t -f DEVICE,TYPE,STATE,CONNECTION dev` instead: it reads
properties, never scans, answers the ethernet and wifi questions in one call, and
runs in 50 ms. Note that nmcli escapes a colon inside any field (`22\:22\:5C…`
for a paired Bluetooth device, and an SSID may contain one), so splitting the
`-t` output on `:` mis-parses those rows unless the escaped ones are hidden
first.

**WiFi does not survive resume** — `ath11k_pci` does not cleanly reinitialise and
DHCP times out. **Two layers, both needed and not mergeable**: TLP disables radio
power saving for normal runtime (applied by its service), and
`systemd.services.wifi-resume` cycles the radio 3 s after wake (executed by
systemd) — the latter is what actually fixes resume. Both are declarative; `/etc`
is generated and read-only, so don't edit it.

**VPN autoconnect is off on all nine profiles, deliberately.** They came off the
backup with `autoconnect=yes`; `homelab` auto-activated, claimed the default
route, and pushed DNS `192.168.1.5` onto every link — so away from the home LAN
**all** name resolution failed. Nothing identifies itself as a VPN problem at
that point; it presents as total DNS death. Check `resolvectl status` for a
tunnel holding `Default Route: yes` before suspecting anything else. Since
2026-08-09 the nine are declared in `networking.nix` and `checks/static.sh`
fails the build on a missing `autoconnect=false`, so this is enforced rather
than remembered (`docs/adr/0013`).

**Editing one of the nine from a GUI silently un-declares it.** All three
keyfile directories are read — `/etc`, `/run`, `/usr/lib` — and `ensureProfiles`
writes to `/run`. An `nmcli con modify` writes a *new* file into `/etc` with the
same UUID, and one of the two is then ignored, so the edited profile and the
profile Nix generates stop being the same thing with no error either way. The
tell is `nmcli -f NAME,FILENAME con show`: the nine must report a `/run/...`
path. This is why the hand-restored `/etc` copies had to be moved aside when
they were declared — leaving them made the declaration a no-op.

**The other 29 profiles are deliberately not declared.** `ensureProfiles`
deletes nothing, so a subset is the supported shape. Don't "finish the job" by
adding the ordinary access points: it moves 29 hotel WiFi passwords into sops to
buy nothing.

> `git.henrydowd.dev` is `192.168.1.200`, a LAN address — on `192.168.1.0/24` it
> is reachable directly and the tunnel is not involved. Bring it up by hand only
> when away: `nmcli connection up homelab`.

---

## Secrets

`secrets/secrets.yaml` is sops-encrypted and tracked in git. The age key is
`/var/lib/sops-nix/key.txt`, in no repo and no backup — **back it up separately**,
or that file is unreadable and a fresh install cannot reach the VPN.

**Edit with `nix develop -c sops secrets/secrets.yaml` from the repo root.** sops
resolves recipients from the `.sops.yaml` in the *working directory*, so running
it from inside `secrets/` makes the relative path resolve to a file that does not
exist — at which point sops silently opens its `hello: Welcome to SOPS!` template
for a *new* file instead of erroring. **That template is the tell.** `sops` and
`age` are devShell-only for exactly this reason.

**A secret is declared only where something reads it.** `sops.secrets.<name>`
decrypts to `/run/secrets/<name>` on every boot, so declaring one nothing
consumes just puts plaintext on a running system. Declared: `pia/username`,
`pia/password`. Stored-only (recover with `sops -d --extract`): the `homelab`
WireGuard key and the `gh`/`glab`/`tea` tokens — those three CLIs rewrite their
own config, which is the `corectrl` fight.

`checks/static.sh` asserts every `secrets/*.yaml` carries the `sops:` metadata
block, because **an unencrypted secrets file looks exactly like an encrypted
one** unless opened, and the mistake is unrecoverable once pushed. It does
**not** check the values are real — a file of placeholders encrypts and passes.

Changing the PIA credentials is `sops` then `rebuild`; `vpn-menu.sh` has no "set
credentials" entry, because a sops secret is root-installed mode 0400. A fallback
to a writable file was rejected on purpose — it would leave "no plaintext secret
outside sops" unenforceable. See `docs/adr/0012`.

---

## Credentials and keyrings

gnome-keyring (`services.gnome.gnome-keyring.enable`, `hosts/thinkpad/default.nix`)
is the *runtime* credential store, and is the opposite of the section above: sops
holds what the flake installs, the keyring holds what applications save while
running. **Nothing here is declarative** — `~/.local/share/keyrings/` is state the
daemon rewrites itself, so it has no tier and no check.

| File | What it is |
|---|---|
| `login.keyring` | the only keyring `pam_gnome_keyring.so` opens. The name is hardcoded on PAM's side: it unlocks *this* file with the password typed at login, and re-encrypts it on password change via the `use_authtok` line |
| `Default.keyring` | an ordinary keyring. Nothing about the name is special to PAM |
| `default` | **a pointer, not a keyring** — the target of the Secret Service `default` alias. Currently the 7 bytes `Default` |
| `user.keystore` | not a Secret Service keyring at all: the PKCS#11 token store, for certificates and keys |

A third collection, `session`, appears on the bus with no file — in-memory, discarded at logout.

**The default collection is `Default`, not `login`, and that is correct here.**
`login.keyring` holds an item labelled `Unlock password for: Default`, with the
attribute `keyring=LOCAL:/keyrings/Default.keyring`. PAM unlocks `login` at
greetd (`/etc/pam.d/login` carries `pam_gnome_keyring` at auth, password and
session; `/etc/pam.d/greetd` substacks it — the same inheritance that makes
`fprintAuth = false` on `login` cover the greeter), and the daemon then reads
Default's password out of that item and unlocks it too. Both collections report
`Locked=false` after login as a result.

The split is an accident of ordering, preserved because it works. Timestamps:
`Default.keyring` was created 2025-12-05 16:26:15 — the same second the `default`
pointer was written — when some app asked for the default collection, found no
alias, and had one created for it. `login.keyring` and `user.keystore` both carry
2025-12-06 15:13:48, a day later: `pam_gnome_keyring`'s first run. **An alias is
only set when it is unset**, so it never moved. Both dates are Arch-era.

**Do not "consolidate" by deleting `Default`.** It holds 33 items — three
Nextcloud tokens, the Chrome/Chromium/Vivaldi/Claude safe-storage keys that
encrypt every password those browsers saved, IntelliJ, copilot, two Matrix
accounts, Proton, Spotify, zed — against three in `login`. There is no supported
bulk move: seahorse has no such operation, and by hand means reconstructing each
item's attribute set.

Repointing the alias does not achieve anything either. **Applications never ask
for a keyring by name** — libsecret's `SECRET_COLLECTION_DEFAULT` resolves through
the `default` file, and *lookups* (`SearchItems`) span every unlocked collection,
so only *stores* follow the alias. Editing it therefore splits secrets across two
keyrings while fixing nothing.

The real fragility is the chain's single item. If `login.keyring` is ever
recreated — password changed by something that bypasses PAM's `use_authtok`, or
the file deleted — that item goes with it and `Default` starts prompting for a
password set in December 2025. **Knowing that password independently is the only
recovery**; restructuring the keyrings is not.

Inspect without decrypting anything:

```bash
file ~/.local/share/keyrings/*.keyring   # name, item count, creation time
busctl --user call org.freedesktop.secrets \
  /org/freedesktop/secrets/collection/Default \
  org.freedesktop.DBus.Properties Get ss org.freedesktop.Secret.Collection Locked
```

---

## Session environment

`dotfiles/mango/universal/autostart.conf:1` runs
`dbus-update-activation-environment --systemd --all`, which copies the
compositor's **entire** environment into the systemd user manager and the D-Bus
activation environment. Every user unit started afterwards inherits it. That is
the point — `WAYLAND_DISPLAY` has to reach the units somehow — and it is the
trap: **re-running that command from any other shell overwrites the session
environment with that shell's.**

On 2026-08-16 it was re-run from inside this repo's `nix develop` shell. That put
`stdenv`, `buildPhase`, `nativeBuildInputs`, `IN_NIX_SHELL` and — the damaging
one — `XDG_CONFIG_HOME=/tmp/…/scratchpad/cfg` into the manager environment.
`nextcloud-client.service` started at 00:24:22 and inherited it:

- the client read `$XDG_CONFIG_HOME/Nextcloud/nextcloud.cfg`, found nothing, and
  **asked to log in** — while the real config, account intact, sat untouched at
  `~/.config/Nextcloud/`;
- its login flow handed the same environment to `xdg-open` → `zen-beta`, which
  takes its profile root from `$XDG_CONFIG_HOME/zen`, found nothing, and **created
  a new empty profile** — a Zen with no extensions, no logins, no history. Reads
  exactly like the Arch-carryover profile bug, unrelated cause;
- noctalia wrote its `settings.json` under `/tmp` for a day, where a reboot would
  have taken it.

**Three applications, three apparent bugs, one cause, nothing logged anywhere.**
The tells:

```bash
systemctl --user show-environment | grep -E '^(stdenv|buildPhase|IN_NIX_SHELL)='   # any hit = poisoned
tr '\0' '\n' < /proc/$(systemctl --user show <unit> -p MainPID --value)/environ | grep XDG_CONFIG_HOME
```

The compositor's own environment leaves `XDG_CONFIG_HOME` **unset**; unset or
`~/.config` are both healthy, any other path is this. Repair is
`systemctl --user unset-environment <var>…` followed by restarting the affected
units — but a re-login is what actually rebuilds the environment from scratch,
and already-running processes keep the old one until they restart.

Two things that make the repair itself misfire: in zsh `for v in $VARS` does
**not** word-split, so the whole list arrives as one name and every call fails
with `Invalid environment variable names` (use an explicit list, or `${=VARS}`);
and `unset-environment` is silent about names that were not set anyway.

---

## Scripts

`dotfiles/scripts/` → `~/.scripts`, a **store path**. Before they moved into the
repo they existed on this disk only, while `audio.nix` declared a unit whose
`ExecStart` pointed at one — so a fresh install produced a unit that could not
start.

### A generated data file under `scripts/` is not a script

`weather.sh` reads its coordinates from a file `dotfiles.nix` generates. Put at
`mango/scripts/system/weather-location.env` it failed `nix flake check`
immediately, and the check was right: the mango tree is scanned for every
`$MANGO_DIR/scripts/…` reference and each one must be an **executable script**,
because a `bind=` naming a 644 file is a key that does nothing. A data file
there is not a bug in the scan.

Generated mango data belongs in `universal/`, with `colors-*.conf` and
`cursor.conf`. The store path is the same either way; the directory is what says
which kind of file it is.

### A missing `set -u` variable becomes a valid API request

`weather.sh` refuses when its generated coordinates file is absent, rather than
letting the request go out with `latitude=&longitude=`. open-meteo answers that
form: it is the weather at 0°N 0°E, in the Gulf of Guinea, and it renders as a
perfectly ordinary temperature. `set -u` does not help — the variable is not
*unset*, it is interpolated into a string that is still a valid URL.

Any parameter that arrives from the generation is worth checking for emptiness
before it reaches a service that will answer regardless. `checks/static.sh`
asserts the file is in the generation and that the variable names in it are the
ones the script sources; the runtime refusal is the second line.

### `mapfile < <(cmd)` reports success however `cmd` exits

A process substitution does not propagate its exit status, so

```bash
if ! mapfile -t rows < <(read_list); then   # never taken
```

is always false — `mapfile` succeeded, with zero rows. For
`menus/notifications.sh` that spelling would have rendered "nothing waiting" for
a notification daemon that was not answering, which are the two readings that
script exists to keep apart. Command substitution *does* propagate, so capture
first and split after:

```bash
rows_tsv=$(read_list) || { ...; exit 1; }
mapfile -t rows <<<"$rows_tsv"
```

`docs/adr/0047`.

### `IFS=$'\t' read` cannot see an empty leading field

TAB is **IFS whitespace**, like space and newline, so bash strips it at the start
of the input and collapses runs of it. `IFS=$'\t' read -r a b` on `"\toffline"`
yields `a=offline`, `b=` — not `a=`, `b=offline`. There is no warning, and the
shape looks obviously correct.

`menus/control-center.sh`'s `jfields()` pulled several fields out of a waybar
module's JSON with `jq … | @tsv` and read them exactly that way. Every consumer
therefore took the **class** as its icon and rendered `?` for a module that had
answered perfectly — the failure the whole file exists to prevent, living inside
the helper written to prevent it.

It shipped unnoticed because `night-mode.sh`, `idle-inhibit.sh` and
`power-profile.sh` always emit a non-empty `text`. **`custom/phone` emits an
empty `text` as its resting state** (above), so adding the phone row on
2026-08-19 hit it on the first render — and only because the row was tested
against all five classes the script can emit, rather than the one the phone
happened to be in.

The fix is a separator that is **not** whitespace: `jfields` joins on `U+001F`
and callers use `IFS=$'\037'`, where empty fields survive exactly. `@tsv` went
with it, so the `gsub` that replaces it is load-bearing too — `@tsv` was also
escaping the real newline in `custom/phone`'s tooltip, which `read` would
otherwise stop dead at.

Two `IFS=$'\t'` reads remain in that file and are correct: both take a first
field that cannot be empty (`eth`/`wifi`/`none`, and an icon that every `state_*`
guarantees).

### A cleanup trap that does not `exit` makes the script immune to SIGTERM

`trap cleanup EXIT PIPE HUP INT TERM`, with `cleanup() { pkill -P $$; }`,
**replaces** SIGTERM's default action instead of running before it. bash runs the
handler and then *resumes* — so a `while true` daemon reaps its child, falls back
into the loop and runs forever. Nothing logs it: the script is doing exactly what
it was told.

This cost **90 seconds on every shutdown and reboot**. `scratch-watch.sh` and
`window-title.sh` both had the shape, both sat in the graphical `session-N.scope`,
and logind's SIGTERM bounced off both. They spun on `sleep 1` until the scope hit
`DefaultTimeoutStopUSec` (1 min 30 s) and systemd SIGKILLed them. The whole event
is four lines, none of which name a script:

```
systemd-logind[…]: Session 10 logged out. Waiting for processes to exit.
systemd[1]: session-10.scope: Stopping timed out. Killing.
systemd[1]: session-10.scope: Killing process 1552530 (sleep) with signal SIGKILL.
systemd[1]: session-10.scope: Failed with result 'timeout'.
```

**The tell that it is a live loop and not a wedged process**: the surviving PIDs
are *higher* than the PID of the `reboot` that started the shutdown — the loop was
still spawning new `sleep`s ninety seconds after being asked to stop.

Write it as two traps, so the signal exits and `EXIT` does the reaping exactly
once on every path:

```bash
cleanup() { pkill -P $$ 2>/dev/null; }
trap cleanup EXIT
trap 'exit 0' PIPE HUP INT TERM
```

**Verify by killing it, never by reading it** — the two shapes are one line apart
and the broken one looks more careful:

```bash
./script & pid=$!; sleep 0.5; kill -TERM $pid; sleep 1.5
kill -0 $pid 2>/dev/null && echo "STILL ALIVE — the bug"
```

`fan-calibrate` had the same shape with `restore`, where it read as "Ctrl-C
restores the frequency limits" and actually meant "Ctrl-C restores them and keeps
calibrating."

**None of them have a file extension.** Don't add `.sh`; fish's aliases did, and
were therefore always broken.

| Script | Note |
|---|---|
| `micmute-led` | syncs the ThinkPad mic-mute LED with PipeWire. Runs as the user service in `audio.nix`, which is the **only** place `pactl` exists (from `pkgs.pulseaudio`, deliberately not in `systemPackages`) — so running it from a shell fails with `pactl: command not found` |
| `toggle_lid_action` | **inert on NixOS**, and fails in a way that looks like a permissions problem: it edits `/etc/systemd/logind.conf` in place, which is a symlink into a read-only store path, so it exits 1 with `Permission denied` and `sudo` does not help. Reading still works. The setting is declarative in `power.nix`. Kept only to answer "what is it set to" |
| `clean_tmp` | `cleantmp` alias |
| `keyd-application-mapper` | per-application keyd layers |
| `pdf_to_a4` | Ghostscript A4 conversion, aspect preserved |
| `texpdf` | pdflatex + aux cleanup |
