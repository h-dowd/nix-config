# 0031 — The idle inhibitor is a unit, not a bool in the bar

**Status:** Accepted (2026-08-18). The noctalia handover is gone with
[0061](0061-one-desktop-noctalia-and-wayle-removed.md); the unit stands.

Extends 0023 (noctalia owns its own
actions): `keep-awake` was the last `fb=none` row in `shell.sh`, and this is
what gave it a fallback.

## Context

"Do not sleep" is the only escape hatch this machine has from swayidle's
ladder. swayidle takes its idle signal from the compositor, so
`systemd-inhibit --what=idle` never reaches it (SYSTEM.md §9) and a long
unattended build on battery meets the 30-minute suspend regardless. The one
mechanism mango's `ext_idle_notifier` honours is a
`zwp_idle_inhibit_manager_v1` inhibitor.

waybar's built-in `idle_inhibitor` module holds exactly that, on the bar's own
layer surface, and it worked. Two things were wrong with *where the state
lived*:

- **It could only be reached by clicking the widget.** waybar exposes no IPC
  for it. `SIGUSR1`/`SIGUSR2` run the configured bar-*visibility* action, the
  `signal` option refreshes `custom/*` modules only, and the `ipc` option is
  Sway's bar protocol. So there was no command, and therefore no keybind —
  which is what prompted this.
- **It died with the bar, silently.** The toggle is a static bool in the waybar
  process and the inhibitor lives on a surface that goes away with it, so
  `waybar-reload`, a layout switch, a mode switch and `SUPER+/` all handed the
  machine back to the idle ladder. The glyph went back to `󰒲` at the same
  moment, so the bar was never *wrong* — it just quietly stopped being what
  set. Confirmed live during this change: the bar came in showing `󰒳`, one
  `waybar-restart.sh` released it, and nothing said so.

The `minimal` and `hud` layouts do not carry the module at all, so switching to
either released it with nothing left to re-arm it from.

## Decision

**The inhibitor is `wlinhibit.service`, a user unit. The bar module only
reports it.**

`custom/idle-inhibitor` polls `systemctl --user is-active` every 30s and on
`SIGRTMIN+12`; clicking it and pressing `SUPER+SHIFT+A` both run
`scripts/system/idle-inhibit.sh toggle`, which starts or stops the unit. The
process lifetime *is* the state, so there is no state file to drift out of step
with the thing it describes — the failure that broke the mode switch one-way on
2026-07-31.

**No `[Install]` section.** Nothing starts it at login. An inhibitor that came
up on its own is the failure the feature exists to prevent, and from the bar it
would look exactly like someone having pressed the key. `checks/static.sh`
asserts the absence, because adding a `WantedBy=` is a one-line change that
nothing else would report.

**`SUPER+SHIFT+A` moves to `universal/bind.conf`.** It was noctalia-only
precisely because no inhibitor outside noctalia could be reached from a key.
noctalia keeps driving quickshell's own `IdleInhibitor` — one mechanism serving
both would leave the other shell's indicator lying, which is 0023's whole
argument.

**And `apply_mode` releases wlinhibit on the way into noctalia**, so exactly one
of the two is ever holding. noctalia's IPC offers `toggle`, `enable`, `disable`
and `enableFor` and **no getter** (read from `IPCService.qml`, 4.7.7), so the
two cannot be kept in step by reading one and setting the other: whichever
belongs to the mode just left would sit there holding the machine awake behind an
indicator reading off. The handover is one-way for the same reason — leaving
noctalia cannot re-arm wlinhibit, because nothing can ask whether noctalia was
holding one.

## Consequences

- The inhibitor survives `waybar-reload`, both bar switches, all three modes and
  a switch to a layout that does not carry the module. It ends with the session
  (`PartOf=graphical-session.target`) and not before.
- **A third-party C program is now in the path.** `wlinhibit` is 90 lines whose
  only job is to hold an inhibitor open until killed. Its `while (1)
  wl_display_dispatch()` does not check for -1, so a display error would spin;
  `PartOf` covers the case that actually produces one.
- `Restart=on-failure`, deliberately not the `always` that
  [wlsunset needs](../gotchas.md): wlinhibit exits 0 on SIGTERM, so `always`
  would be survivable but `on-failure` is what lets `systemctl stop` — the
  toggle's off path — stay stopped. A crash still comes back.
- **A mode switch into noctalia releases it, deliberately** — the one place
  this reintroduces the behaviour the whole ADR removes. It is not silent: the
  handover notifies, and only when something was actually held, so the message
  is never noise. `checks/static.sh` asserts the line still exists, because
  deleting it leaves both inhibitors real and only an indicator wrong, which is
  precisely the shape that goes unnoticed here.
- **The bar can now show a state the inhibitor is not in**, which the built-in
  could not. A unit that hits its restart limit has released the inhibitor while
  something has to say so: hence the `failed` class, red, and the 30s poll as a
  floor under the signal. This is the cost of the state living outside the thing
  that draws it, and it is worth paying.
- `idle-inhibit.sh on` verifies rather than trusting `systemctl start`, which
  returns once the process is forked. wlinhibit exits 1 when the compositor
  advertises no manager, and that lands after the return — the exact shape of
  "it ran and exited 0" this repo keeps meeting.
- Verified by output, both directions, before the rebuild: with wlinhibit up, a
  `swayidle timeout 1` probe fired 0 times in 15s; with it stopped, 1. mango
  honours an inhibitor on a bare unmapped `wl_surface` for the same reason it
  honours one on waybar's layer surface — `checkidleinhibitor` gets `c = NULL`
  and `idleinhibit_ignore_visible=0` takes the `!c` arm.
