# 0051 — Waybar is the tiling bar again, and wayle is installed but unstarted

**Status:** Accepted (2026-08-27). The "installed but unstarted" half is
superseded by [0061](0061-one-desktop-noctalia-and-wayle-removed.md): wayle and
noctalia are both removed.

Reverses 0045 for the tiling mode, and with
it the clauses of [0047](0047-a-retired-daemon-is-a-call-that-exits-0.md) that
retired swaync and swayosd. 0020 is
untouched: noctalia still runs its own shell and its own wallpaper.

This is the **restore** half. wayle is still installed, still generated, and
still one `exec=` line from coming back; nothing has been deleted.

## Context

0045 made wayle the tiling shell on the strength of it being one program where
there had been three. That held. What did not hold is the reason for wanting it:
every job it took over turned out to be reachable from waybar and rofi, and one
of them — the detailed weather reading — was reachable *only* from a mouse click
on one bar module, because no wayle dropdown answers a key
([0050](0050-the-weather-panel-is-rofis.md)).

Three findings decided it, all checked rather than assumed:

- **wayle's dropdowns are a closed set of ten** and nothing opens one from
  outside the bar. Recorded in 0050.
- **waybar was never dismantled.** All six configs are still generated,
  `style-solid.css` is intact, and `waybar-layout.sh` / `waybar-position.sh` /
  `window-title.sh` are still in the tree. Only `waybar-restart.sh` had been
  deleted, and it came back out of git unchanged but for three renamed lib.sh
  helpers.
- **swaync was never dismantled either.** Its stylesheet is still generated from
  the palette, and the empty `systemd/user/swaync.service` that masks it is
  deliberate and predates wayle — `autostart.conf` owns the lifecycle so a
  restyle applies on a mode switch (0005).

## Decision

**`tiling/autostart.conf` starts waybar, swaync and awww. It does not start
wayle.**

Three jobs came back to their own owners:

| Job | Was | Is |
|---|---|---|
| Notifications | wayle claims `org.freedesktop.Notifications` | swaync, started by `exec=` after wayle is stopped |
| OSD | wayle's `[osd]` | swayosd, the only OSD in this mode — waybar has none |
| Wallpaper | `wayle wallpaper set`, awww as wayle's child | `wallpaper-restore.sh`, starting `awww-daemon` itself |

**The bar state was never renamed away.** `bar_layout`, `bar_position` and
`mode_has_bar` are lib.sh's names since 0045 — *"the state outlives whichever
program draws it"* — so coming back cost no state reset and no migration.

**wayle stays installed.** `modules/home/wayle.nix`, `dotfiles/wayle/` and
`scripts/wayle/` are untouched and unreferenced by any autostart line. Removing
them is a separate decision.

## Consequences

- **The rofi history list is gone.** `menus/notifications.sh` read
  `com.wayle.Notifications1`; `swaync-client` offers count, dnd and toggle and
  no list to rebuild it from. swaync's own panel is the history again, which is
  what `CTRL+ALT+\` opened before 0045.
- **swayosd is second in noctalia**, which draws its own caps-lock overlay. That
  was true before 0045 too and is the cost of one line in the file that runs in
  both modes.
- **The weather bar-push is back.** waybar takes `RTMIN+13` and
  `custom/weather` declares `signal = 13`, so `weather.sh refresh` is visible
  again rather than waiting out a 300 s poll. `|| true` on it, because the same
  script runs in noctalia where the pkill matches nothing and would otherwise
  return 1 — 0047's finding, one script over.
- **Three waybar module settings were wrong and invisible**, all found by
  rendering the bar beside wayle's rather than by reading the config:
  - `mpris.ignored-players = [ "firefox" ]` carried through from the
    hand-written configs with no reason attached. firefox is the only player on
    this machine, so the media module rendered nothing, always.
  - `dynamic-order` unwritten defaults to include **position**, so the label was
    a running clock where the title should have been.
  - `dynamic-len` is a **drop** threshold, not a truncation one: waybar removes
    a field that does not fit rather than shortening it, so a 35-character title
    vanished and left the 12-character artist. `max-length` is the key that
    behaves like wayle's `label-max-length`.
- **`#custom-window` lost its own rule.** It drew at `@subtext` and 11px against
  a bar of `@text` at 14px — dimmer and smaller than everything else, on the one
  label that is a sentence rather than a number. Its cap went 60 → 45 in the
  same change, because the same characters are a third wider now; raising the
  size alone is the half-change.
- **The checks inverted rather than went away.** The retired-daemon scan that
  caught `swaync-client` and `pkill -RTMIN+N waybar` now catches calls to the
  wayle CLI, excluding `scripts/wayle/` the way it always excluded
  `noctalia-start.sh` running `swaync`. Both live daemons are asserted from the
  other end instead: something must *start* them.
