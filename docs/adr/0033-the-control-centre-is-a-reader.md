# 0033 — The control centre is a reader, not a second owner

**Status:** Accepted (2026-08-19). noctalia is removed by [0061](0061-one-desktop-noctalia-and-wayle-removed.md); the
menu is the only control centre.

Extends 0023 (noctalia owns its own
actions) and follows [0031](0031-the-idle-inhibitor-outlives-the-bar.md), which
did the same thing for `keep-awake`: `control-center` was one of the three
remaining `fb=none` rows in `shell.sh`, and this is what gave it a fallback.
Uses the one-owner rule from [0005](0005-one-owner-per-daemon.md).

## Context

noctalia is described — accurately — as feeling more cohesive and more intuitive
than this repo's modular desktop, at little performance cost. Taken apart, that
feeling is three separate claims, and only one of them is about noctalia being a
better program:

1. **One visual language.** Already true here and by a wider margin:
   `modules/home/palette.nix` feeds twelve consumers with `checks/static.sh`
   asserting no drift, while noctalia's own template theming is ungated by every
   check this repo owns.
2. **One place per action.** Half-true here. `scripts/menus/shell.sh` is already
   a single verb table both shells route through, and the check asserts both
   halves of every row exist — but the fifteen actions live on fifteen separate
   keys, and **nothing showed the set, or the state each toggle was in**. It took
   to remember the key, press it, and read the answer off the bar.
3. **One live state model.** noctalia is one process holding one model, so its
   bar glyph, its OSD and its control-centre slider are three views of one
   object and cannot disagree. Here every fact has a different owner: waybar
   polls `wpctl`, swayosd listens to libinput, `volume-menu.sh` shells out.

The gap that was actually felt is (2), and it was never about the toggles. Every
one of them already had a script, a key and a waybar module here. What was
missing was a list.

## Decision

**A control centre in tiling and hud modes, as a rofi menu that reads the
existing owners.** `scripts/menus/control-center.sh`, on `SUPER+C` — the same
key noctalia mode already used, moved from `noctalia/bind.conf` into
`universal/bind.conf` and routed by `shell.sh` as before, so there is one key
with two implementations rather than two keys.

Twelve rows: network, bluetooth, VPN, volume, microphone, night light, keep
awake, power profile, phone, do-not-disturb, notifications, bar. Each shows its
current state.

Three properties make it a reader rather than a second owner:

- **Nothing here changes anything.** Every action delegates to the script that
  already owned that fact, so the bar, the key and the menu cannot end up
  disagreeing about what a toggle did.
- **Four rows take their icon *and* their state from the waybar module that
  owns the fact** — `night-mode.sh status`, `idle-inhibit.sh status`,
  `power-profile.sh`, `phone-status.sh status` — parsed out of the JSON those
  modules already emit.
  Reproducing a glyph here would be a second owner for it, which is
  [0028](0028-one-palette-reaches-every-config-it-can.md)'s failure one
  directory over.
- **It re-renders after every action instead of closing.** The state model is
  not shared, so a row can only ever be *stale*; rebuilding the whole list on
  every open and after every action is the honest way to make stale impossible
  to observe. That loop is the feature, not a convenience.

**`?` is a state, and it is not "off".** Every `state_*` has a branch for "the
owner did not answer", and it renders `?`. A row that quietly reads "off"
because `nmcli` was missing is the same silent failure in a tidier form.

**The microphone row came with a bar indicator, and had to.** It was added on
2026-08-19, the first item off this menu's own queue, and it is the only row
whose fact was on *no* surface beforehand: every other toggle here already had a
key, a script and a waybar module, while mic mute state existed solely as the
ThinkPad LED that `micmute-led` drives. A row alone would have made the control
centre the only place that fact appeared — which is this record's inversion, a
menu owning a state the bar cannot see. So `{format_source}` went into
`waybar.nix`'s existing `pulseaudio` module in the same change, rather than into
a `custom/microphone` of its own: PipeWire owns the fact and both are readers,
exactly as this menu's `volume` row and that same module have always both read
the sink. **Both mic states carry a glyph.** An indicator that renders nothing
when muted cannot be told apart from one that is not running — the `?`-is-a-state
rule above, one surface over. `docs/gotchas.md` → Waybar.

**What is deliberately not reached from here.** The fanless power profile, for
`power-profile-cycle.sh`'s own reason — it caps every core at 418 MHz, too large
a penalty to land on by pressing Enter one time too many — and offering the three
profile names would put TLP's list in a second file. The row cycles
balanced↔performance, exactly as a left-click on the bar does.

**(3) is not attempted.** Shared live state needs a single process, and that is
what noctalia *is*. Two of the three claims are reachable without it; this closes
the second.

## Consequences

- **Two `fb=none` rows remain** — `calendar` and `dock` — and both are
  panel-shaped rather than list-shaped, which is why they stay noctalia-only.
  The header in `noctalia/bind.conf` now says two, not three.
- **A new floor in `checks/static.sh`.** The rows are declared once in a `ROWS`
  array, and the check asserts every id has a `LABEL`, a `state_*` and an
  `act_*`, in both directions and with a zero floor on each side. A row missing
  a half renders and then does nothing — bash reports "command not found" to a
  stderr nobody reads. The script re-checks the same thing before it draws, so
  the failure is caught at the first press if it ever gets past the build.
- **A render is parallel, and that is not an optimisation.** The rows are
  independent and each is one round trip to an idle daemon; serially they
  measured **450 ms**, and this menu re-renders after every action, so the cost
  lands on every press rather than once. Run concurrently — the shape
  `network-menu.sh`'s `build_menu` already uses — a render is **73 ms**, the
  slowest single row. A reader that is slower than the thing it reads stops
  being the place to look.
- **The phone row cost the device ID a home.** `custom/phone`'s `on-click`
  spelled `kdeconnect-cli -d <32-hex-id> --ring` in `waybar.nix` while
  `phone-status.sh` held the same id in its own `DEVICE=`, and a row that rang
  the phone would have made three copies of one string. `phone-status.sh` grew a
  `ring` verb instead, so the id is written once and the bar, the row and the
  script cannot drift — [0005](0005-one-owner-per-daemon.md) applied to a
  constant rather than a daemon. Bare invocation stays `status`, because
  waybar's `exec` passes no argument.
- **`ring` says why it cannot ring.** Both callers previously got silence when
  the phone was away, which is indistinguishable from the ring having failed;
  the verb `notify-send`s and returns 1. An action that appears to do nothing is
  the one outcome a row must not have.
- **The menu sets its own `-l`, from `ROWS`.** rofi's shared `lines: 12` ceiling
  paged this menu in two the moment the microphone row took it to 13 rendered
  lines, hiding the last two toggles behind a scroll — the "nothing showed the
  the set" gap above, rebuilt one layer down and looking like a complete menu.
  `-l "${#ROWS[@]}"` rather than a number, since `render()` emits one line per
  element: a row added later widens the window instead of re-paging.
  `docs/gotchas.md` → rofi.
- **The Network row must never call `nmcli dev wifi`.** That triggers a scan and
  blocks for seconds; the first version of this file did, and cost 6.4 s on the
  first open. `docs/gotchas.md` → Networking.
- **`SUPER+C` is now bound in all three modes**, so it must not be taken by
  anything else. The existing duplicate-bind check covers that per mode.
- **A latent bug in `jfields` surfaced, and it was this record's own failure
  mode.** `IFS=$'\t' read` cannot see an empty leading field — TAB is IFS
  whitespace — so every module-backed row took the *class* as its icon and
  rendered `?` whenever `text` was empty. Invisible while only night, awake and
  power used it, since all three always emit a glyph; `custom/phone` emits an
  empty `text` as its resting state and hit it immediately. `jfields` now joins
  on `U+001F`. Found only because the row was tested against all five classes
  `phone-status.sh` can emit rather than the one the phone was in —
  **enumerate the branches off the source, never off the observed value.**
  `docs/gotchas.md` → Scripts.
- **One glyph bug found and not inherited.** `menus/network-menu.sh` uses
  `nf-fa-network_wired` (U+F6FF) for its ethernet entry, and Hack Nerd Font does
  not cover it — fontconfig falls through to IBM Plex Sans TC and draws a box,
  with nothing logged. The control centre uses `nf-md-ethernet` (U+F0200), which
  is what `waybar.nix`'s own `format-ethernet` uses. `network-menu.sh` is
  untouched here; see `docs/gotchas.md` → Theming.
