# 0026 — Serve the power-profiles-daemon bus name from TLP

**Status:** Accepted (2026-08-17). noctalia, its first client, is removed by
[0061](0061-one-desktop-noctalia-and-wayle-removed.md); `powerprofilesctl` and GNOME's power page still use the name.

Follows [0017](0017-tlp-profiles-not-platform-profile.md) (power modes are TLP
profiles) and [0005](0005-one-owner-per-daemon.md) (one owner per daemon).
Closes one of the three inert things 0020
measured in noctalia mode.

## Context

`services.power-profiles-daemon.enable = false` has been in `power.nix` since
TLP arrived, with the comment "conflicts with TLP". That is correct and it is
not the whole cost. **PPD is not only a tuner; it is also the interface every
desktop uses to ask what the power profile is.** Turning it off removes the
answer as well as the second tuner.

So a whole class of clients finds nothing here, and none of them says so:

- **noctalia's control centre** carries a `PowerProfile` button in its *default*
  shortcut row (`Assets/settings-default.json` → `controlCenter.shortcuts.right`).
  It is `enabled: hasPP`, and `hasPP` is `PowerProfileService.available`, which
  is `powerProfiles.hasPerformanceProfile`. With no service on the bus that is
  false, every function in `PowerProfileService.qml` returns early, and the
  button sits greyed out. `docs/SYSTEM.md` §13 has carried it as inert since
  2026-08-14.
- **noctalia's battery panel** has a three-position profile slider behind the
  same gate.
- `powerprofilesctl`, GNOME's power page, and anything else written against the
  documented API get `ServiceUnknown` and typically render an empty control.

This is the repo's signature failure in someone else's code: **a thing that is
missing and a thing that is broken look identical**. It is worth fixing not
because the widget is important, but because the honest states are "the control
works" and "the control is absent" — and neither of those was what was on
screen.

Two mechanisms could carry it, and one is a trap.

**`services.tuned.ppdSupport` exists in the pinned nixpkgs, and claims both bus
names** (`org.freedesktop.UPower.PowerProfiles.service` and the legacy
`net.hadess.PowerProfiles.service`, both shipped by `tuned` 2.27.0 — verified in
the store). It is rejected. tuned-ppd translates PPD calls into *tuned* profiles,
which set governor and EPP themselves. That puts a second owner on the cpufreq
path alongside TLP — [0005](0005-one-owner-per-daemon.md) verbatim — and every
number in [0017](0017-tlp-profiles-not-platform-profile.md) was measured against
TLP applying them alone.

**The wire contract was read off the running client, not guessed.** The
`noctalia-qs` binary resolves quickshell's `PowerProfiles` singleton to bus name
and interface `org.freedesktop.UPower.PowerProfiles` at
`/org/freedesktop/UPower/PowerProfiles`, binding the properties `ActiveProfile`
(writable), `Profiles`, `ActiveProfileHolds` and `PerformanceDegraded`. The
profile strings it parses — `power-saver`, `balanced`, `performance` — are
UTF-16 literals in the binary and do not appear in an ASCII `strings` dump,
which is why the first pass found nothing and nearly concluded the names were
free.

## Decision

**A small daemon owns the PPD bus name and answers it from TLP.**
`pkgs/power-profiles-tlp/` — ~315 lines of Python on dbus-python and GLib, run
as a system unit from `modules/system/power.nix`.

It is a **translator, not a tuner**, and the split is the whole point:

- **Reads** `/run/tlp/last_pwr` — the same file the waybar module polls, same
  `PP_PRF=0 PP_BAL=1 PP_SAV=2` decoding from `tlp-func-base`.
- **Writes** through `power-mode`, the existing root wrapper, so the iGPU pin
  that TLP cannot do for `SAV` still happens. PPD's profile names and
  `power-mode`'s arguments coincide exactly, so only the read side maps.
- **Watches** `last_pwr` with a `Gio.FileMonitor` and emits `PropertiesChanged`,
  so TLP's own charger-transition switches reach the client. Without this the
  widget would track only its own clicks and go stale on the first unplug —
  which looks like a broken widget rather than a stale one.

Four choices inside it are deliberate:

**It refuses to start rather than publish a guess.** No readable profile from
`last_pwr`, or a `power-mode` that is not executable, exits 1 with the reason on
stderr. The API has no "unknown" value, so the alternative is to invent one and
serve it forever. `BindsTo=tlp.service` extends the same rule to runtime: with
TLP stopped the name *leaves the bus*, and clients see an absent service — true
— instead of a live-looking stale profile.

**It declines profile holds, loudly.** PPD lets an application pin a profile
while it runs. Honouring that here would let any app override a profile whose
every value was measured for this chassis, and recording a hold that changed
nothing would be that same silent failure, chosen deliberately. `HoldProfile`
raises `NotSupported` with a sentence saying why, and `ActiveProfileHolds` is
empty by construction rather than merely empty so far.

**Every write is read back.** `power-mode` shells out to `tlp`, and a `tlp`
write that reports success and changes nothing is exactly what
[0017](0017-tlp-profiles-not-platform-profile.md) was written about.
`set_active` re-reads `last_pwr` and raises if TLP reports a different profile,
so a lie fails the D-Bus call rather than moving the slider.

**Bus policy, not polkit.** Upstream gates `ActiveProfile` behind a polkit
action. One seat and one admin: `wheel` may set the profile, everyone else may
only read it. **Reads stay open to `default`** on purpose — a denied `Get`
renders exactly like a daemon that is not running, which is the state this
daemon exists to remove.

**It ships a D-Bus activation file as well as an always-on unit, and the second
does not make the first redundant.** This was learned the hard way, on the first
live run. With the daemon running and answering `busctl` correctly, noctalia
still did nothing: `noctalia-shell ipc call powerProfile set balanced` printed
nothing — success, by 0023's rule — and
changed neither TLP nor the CPU. The journal had the reason, from an hour
earlier:

```
WARN quickshell.dbus: Could not launch service org.freedesktop.UPower.PowerProfiles:
  QDBusError(org.freedesktop.DBus.Error.ServiceUnknown, The name is not activatable)
WARN quickshell.service.powerprofiles: Could not start PowerProfilesDaemon.
  The PowerProfiles service will not work.
```

quickshell probes the name at startup and, finding it unowned, tries to
**activate** it — then gives up for the life of the process. A unit that happens
to be running is not the same thing as a name D-Bus can start, and nothing in
`systemctl status` distinguishes them. `SystemdService=power-profiles-tlp.service`
in `share/dbus-1/system-services/` closes it; `Exec=` is the non-systemd
fallback, following upower's file in the same nixpkgs.

### Seven checks, because three files must agree and nothing makes them

`checks/static.sh` gained a `power profiles` section — seven checks. Each guards
a seam that fails silently:

| Check | The silent failure it catches |
|---|---|
| daemon and `power-mode` accept the same profile names | `power-mode` exits 2; the slider snaps back |
| daemon and the waybar module decode `last_pwr` alike | one of the two reports a stale or wrong profile forever |
| daemon and policy name the same bus, and it is PPD's | a service nothing finds — the state being fixed |
| the policy is well-formed XML | **the system bus rejects the file**, blast radius everything |
| the unit exists and passes an executable `--power-mode` | starts, switches nothing |
| an activation file names the bus, the unit, and an executable | a client that starts first gives up forever |
| `power-profiles-daemon` is not also enabled | two owners for one name |

`fanless` is normalised to `power-saver` in the second check: it is this repo's
name for TLP's `SAV` and the one deliberate difference between the two decoders,
so it is declared rather than tolerated by a looser comparison.

The XML check is not hypothetical. **The first draft of the policy was
ill-formed** — an XML comment may not contain a double hyphen, and the header
comment had one. dbus rejects the whole file, and the file is loaded by the
*system* bus.

## Consequences

- **noctalia's control-centre power button goes live with no settings change**,
  because `PowerProfile` is already in the shipped default shortcut row. That is
  the seamless half, and it needed nothing seeded.
- **That button cycles, and the cycle reaches fanless.**
  `PowerProfileService.cycleProfile()` runs balanced → performance → power-saver
  → balanced, so a third click lands on the 1.1 GHz cap that
  [0017](0017-tlp-profiles-not-platform-profile.md) deliberately kept off the
  bar's left-click. Accepted rather than blocked: it is a labelled button, not a
  scroll wheel, and noctalia raises a toast naming the profile it moved to — the
  feedback the bar cycle lacked. `SUPER+SHIFT+P` and the waybar module return to
  balanced.
- **The battery panel's slider is not enabled by default, and is not seeded.**
  `showPowerProfiles` is a per-instance setting on the `Battery` *bar widget*
  (`BarWidgetRegistry.qml` default `false`), so turning it on means pinning the
  whole `bar.widgets` layout into the seed — owning a structure that upstream
  changes between releases, against
  0022's "seeded, never owned".
  It is two clicks in noctalia's own settings panel. Left to the user.
- **Every PPD client on the machine starts working, not just noctalia.**
  `powerprofilesctl` is not installed; `busctl get-property
  org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles
  org.freedesktop.UPower.PowerProfiles ActiveProfile` needs nothing extra.
- **`Version` reports `0.30` — the API level implemented, not this daemon's
  version.** Provenance goes in each profile's `Driver` field (`tlp`), which is
  where `powerprofilesctl` prints it. A daemon reporting its own version number
  there would be read as an ancient PPD by clients that branch on it.
- **A python3 + pygobject closure joins the system.** Roughly 200 MiB, fully
  cached, for a daemon that is idle almost always. The alternative was a C or
  Rust binary to maintain by hand; this is the cheaper mistake to undo.
- **The build proves the imports.** `doInstallCheck` runs `--help`, which
  imports `dbus` and `gi` and exits, so a missing dependency or an unwrapped
  `GI_TYPELIB_PATH` fails the *build* rather than arriving as a unit that
  crash-loops after the next reboot.
- **`--bus session` and `--pwrfile` exist as test seams.** The daemon was
  exercised end to end on a private `dbus-launch` bus against a fake
  `power-mode` — set, read back, external change, and all five error paths —
  before it was ever given the real name. Keep them; a daemon that can only be
  tested by switching the system will not be tested.
- **Removal is one pass.** Delete `pkgs/power-profiles-tlp/`, its overlay entry,
  the unit and `services.dbus.packages` line in `power.nix`, and the check
  section. Nothing else references it; noctalia's button returns to grey.
