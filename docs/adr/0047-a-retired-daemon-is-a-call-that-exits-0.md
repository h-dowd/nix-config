# 0047 — A retired daemon is a call that exits 0

**Status:** Accepted (2026-08-26). wayle is removed outright by
[0061](0061-one-desktop-noctalia-and-wayle-removed.md); the finding stands.

Follows 0045, which retired waybar and
swaync from tiling mode. It moved the bar; it did not move the callers.

## Context

Neither waybar nor swaync is started in either mode. swaync's unit is
additionally **masked** (`modules/home/default.nix` writes an empty unit, from
back when the `exec=` line owned its lifecycle). Their callers stayed, in three
shapes, none of which announces itself:

- **`pkill -RTMIN+N waybar`, in six scripts** — `night-mode.sh`, `vpn.sh`,
  `vpn-menu.sh`, `weather.sh`, `power-profile-cycle.sh`, `idle-inhibit.sh`.
  waybar's refresh push; wayle takes no signal at all. A `pkill` matching
  nothing returns 1, and each of these was the *last* statement in its function,
  so a toggle that worked exited non-zero. wayle logs
  `command failed, cmd: …` for it — caught in this session's journal, for a
  night-mode toggle that had in fact toggled.
- **`swaync-client`, in three keys and two control-centre rows.** Against a
  masked unit it prints `NameHasNoOwner … unit is masked` on stderr and **exits
  0**. `CTRL+ALT+\`, `CTRL+ALT+BackSpace` and `SUPER+SHIFT+N` were dead; the
  panel's Do-not-disturb and Notifications rows read `?` and did nothing.
- **Daemons still started for a consumer that is gone.** `scratch-watch.sh` kept
  `/tmp/scratch-<pad>` in step with the focused client and signalled waybar's
  two scratchpad modules — which went with the bar, as
  [0042](0042-separators-belong-to-the-layout.md) noticed when their CSS
  outlived them. Nothing has read those files since. `swayosd-server` drew a
  caps-lock overlay on top of the one wayle draws in tiling and the one noctalia
  draws in noctalia; nothing here has ever called `swayosd-client`.
  0020 accepted that overlap when it
  happened in one mode and swayosd was the only OSD in the other. Both halves of
  that trade are gone.

## Decision

**Every push is removed, and nothing replaces it.** wayle's `on-action` covers
the click path; the module interval covers the key and the control centre.
`custom-idle-inhibitor` polls at **2 s** rather than 30 — its key raises no
notification, so that interval *is* the feedback.

**The notification verbs point at the daemon that is running.** `wayle notify
dnd` and `wayle notify dismiss-all` in `menus/shell.sh`'s tiling half and in the
control centre; `wayle notify status`, parsed, for the two rows.

**The history gets a menu, because it cannot get the panel.** wayle's history is
a *dropdown*: `com.wayle.Shell1` exposes `BarShow`/`BarHide`/`BarToggle` and no
more, and a click action is a shell command or a `dropdown:`, never both — so a
bar click opens one and nothing else can. `menus/notifications.sh` is the list a
key can reach, a reader that delegates every action to `wayle notify`
([0033](0033-the-control-centre-is-a-reader.md)'s shape). The bar's power button
keeps the real panel on right-click.

**`scratch-watch.sh` is deleted**, with its `exec-once` line.

**swayosd is removed outright**, and its udev rule moves. That rule was the only
thing on this machine granting `video` write access to
`/sys/class/backlight/*/brightness`, so the brightness keys — which run
`brightnessctl`, never `swayosd-client` — depended on a package nothing else
used. `services.udev.packages = [ pkgs.brightnessctl ]` is the same two lines
plus the `leds` grant upstream ships with them.

## Consequences

**`checks/static.sh` asserts no script signals waybar or calls `swaync-client`.**
Over code with **comments stripped**, deliberately: each of the six removals left
a comment naming the line it replaced — this repo's whole convention — and a
scan matching anywhere in the file fires on its own documentation. A
commented-out call is not a call.

**The signal-number check is gone.** It read `pkill -RTMIN+13 waybar` out of
`weather.sh` and matched it against `custom/weather`'s `signal` in the generated
waybar config. Both ends went; there is nothing left to agree.

**The trap check is down to one subject.** `window-title.sh` is the last
long-running script, and it is waybar's, so retiring waybar takes that check's
population with it. Its floor is 1 and the comment says to re-base on the next
daemon rather than delete the scan — the failure it catches cost 90 s on every
shutdown.

**waybar and swaync are still built.** Only their callers are gone. Retiring the
packages, `waybar.nix`, and `scripts/waybar/` is a separate decision with its own
uninstall.

**Four `layerrule`s still name swaync's layer namespaces** in
`universal/rule.conf`, matching nothing in either mode. Left rather than
repointed: wayle's own namespace was not established, and guessing one is the
failure this record is about.
