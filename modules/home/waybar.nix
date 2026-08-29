# Waybar layouts, generated from one shared set of module definitions.
#
# Each module is defined once in `modules` below and a layout is a list of
# names; `lib.genAttrs` emits definitions for exactly the names a layout uses.
# An unused definition cannot linger, and A name with no definition is an eval
# error instead of a module that renders as nothing. That is why these are
# generated: the four hand-maintained .jsonc files drifted, and `custom/window`
# ended up with max-length 60 in two and 80 in a third. docs/adr/0009.
#
# `style-*.css` stay hand-written (rules, not settings) while `colors.css` is
# generated (data that also lived in two other files): docs/SYSTEM.md §6 for
# the line between them, docs/adr/0028 for why a drifted palette gets a check
# rather than a convention.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  s = "~/.config/mango/scripts";

  # The shared palette, in GTK CSS spelling. `style-*.css` `@import` this and
  # refer to the names, so a colour is written once here and nowhere else.
  p = import ./palette.nix;

  # Icon-theme names by mango appid, drawn by `iconCss` below. docs/adr/0052.
  #
  # Keys are appids as mango reports them, case included — `Equibop` sat here
  # until 2026-08-28 and never matched. equibop and imv are stand-ins in
  # adr/0041's sense: neither name exists in the theme.
  appIcons = {
    foot = "foot";
    kitty = "kitty";
    zen-beta = "zen-browser";
    equibop = "discord";
    imv = "multimedia-photo-viewer";
    Spotify = "spotify";
    default = "application-default-icon";
  };

  # rofi's wayland window mode resolves an icon from the LOWERCASE APPID against
  # the icon theme and takes no desktop-file step, unlike drun
  # (rofi's wayland-window.c:610). So an appid that is not itself an icon name
  # draws nothing and logs nothing — the same silent half docs/adr/0052 gave the
  # bar's names a check for, reached from a different direction.
  #
  # These are the appids above the theme has no name for. NOT `equibop`: it
  # ships its own hicolor icon, so an alias would be a buildEnv collision at
  # `nix flake check` rather than a fallback. checks/static.sh asserts the set is
  # neither short nor stale, against the built generation. docs/adr/0060
  appIconAliases = [
    "zen-beta"
    "imv"
  ];

  # One symlink per alias into hicolor, which every icon lookup falls back to.
  # Sourced from `themeIcons` rather than papirus directly, so an alias carries
  # the same art the bar draws on whichever scheme is selected. The theme's own
  # directory first, then the whole package: Papirus-Dark inherits most app
  # icons from Papirus and holds only the ones it overrides.
  #
  # `exit 1` on a name the package does not have. A dangling symlink here would
  # be indistinguishable from having no icon at all.
  appIconAliasPkg = pkgs.runCommand "rofi-app-icon-aliases" { } (
    ''
      d="$out/share/icons/hicolor/scalable/apps"
      mkdir -p "$d"
    ''
    + lib.concatMapStrings (
      appid:
      let
        icon = appIcons.${appid};
        root = "${pkgs.themeIcons}/share/icons";
      in
      ''
        # LARGEST first, and it is not cosmetic: Papirus draws its small sizes
        # simplified, and a 16x16 asset parked under scalable/ is what rofi then
        # renders at menu size. Sorting by the size directory picks the detailed
        # asset. The theme's own directory before the rest of the package —
        # Papirus-Dark holds only what it overrides and inherits the remainder.
        src=$(
          { find -L ${root}/${p.packages.icons.name} -name '${icon}.svg' 2>/dev/null
            find -L ${root} -name '${icon}.svg' 2>/dev/null
          } | awk -F/ '{ for (i = NF; i > 0; i--) if ($i ~ /^[0-9]+x[0-9]+$/) { split($i, a, "x"); print a[1] " " $0; next } print "0 " $0 }' \
            | sort -rns | head -1 | cut -d" " -f2-
        )
        [ -n "$src" ] || { echo "no icon '${icon}' in ${p.packages.icons.name} for appid '${appid}'" >&2; exit 1; }
        ln -s "$src" "$d/${appid}.svg"
      ''
    ) appIconAliases
  );

  # Mirrored by `css_class()` in window-title.sh; checks/static.sh runs both.
  cssClass = lib.replaceStrings [ "." " " ] [ "-" "-" ];

  # Keyed on `.some`, not on the bare id: the shared module block's
  # `background: transparent` shorthand out-ranks a bare rule here and the icon
  # vanishes silently. Every rule this file emits carries a class for that
  # reason. docs/gotchas.md -> Waybar.
  # `-symbolic` matters: a symbolic name follows the module's CSS `color`, a
  # plain one renders as its own asset. Plain `view-restore` drew a white icon
  # beside a tinted count. docs/adr/0053.
  moduleIcons = {
    "custom-minimized.some" = "view-restore-symbolic";
  };

  # Papirus's battery ladder — the icons wayle wore, which were Adwaita's.
  # docs/adr/0052.
  #
  # `at` is a capacity ceiling: waybar picks the tightest class whose value is
  # >= capacity (waybar-states(5)), so 44% wears `l50`. The bottom two are 5 and
  # 20 rather than 0 and 10 because they carry the colour too, still matched to
  # upower's PercentageCritical/Low in power.nix.
  batteryRungs = [
    {
      level = 0;
      at = 5;
    }
    {
      level = 10;
      at = 10;
    }
    {
      level = 20;
      at = 20;
    }
    {
      level = 30;
      at = 30;
    }
    {
      level = 40;
      at = 40;
    }
    {
      level = 50;
      at = 50;
    }
    {
      level = 60;
      at = 60;
    }
    {
      level = 70;
      at = 70;
    }
    {
      level = 80;
      at = 80;
    }
    {
      level = 90;
      at = 90;
    }
    {
      level = 100;
      at = 100;
    }
  ];

  rungClass = r: "l${toString r.level}";

  # Papirus has no `battery-level-100-charging-symbolic`; the full one is
  # `-charged-`. checks/static.sh resolves every name this emits.
  rungIcon = r: "battery-level-${toString r.level}-symbolic";
  rungCharging =
    r:
    if r.level == 100 then
      "battery-level-100-charged-symbolic"
    else
      "battery-level-${toString r.level}-charging-symbolic";

  # One `-gtk-icontheme()` rule per appid and per battery rung. Generated so the
  # name and its selector are one fact; the geometry around them, and the
  # fallback icon, stay in style-solid.css. docs/adr/0052.
  iconCss = ''
    /* GENERATED from modules/home/waybar.nix — edit appIcons there, then
       rebuild. Imported by every style-*.css. */
  ''
  + lib.concatStrings (
    lib.mapAttrsToList (name: icon: ''
      #${name} { background-image: -gtk-icontheme("${icon}"); }
    '') moduleIcons
  )
  + lib.concatStrings (
    lib.mapAttrsToList (
      appid: icon:
      lib.optionalString (appid != "default") ''
        #custom-window.${cssClass appid} { background-image: -gtk-icontheme("${icon}"); }
      ''
    ) appIcons
  )
  + lib.concatStrings (
    map (r: ''
      #battery.${rungClass r} { background-image: -gtk-icontheme("${rungIcon r}"); }
      #battery.${rungClass r}.charging,
      #battery.${rungClass r}.plugged { background-image: -gtk-icontheme("${rungCharging r}"); }
    '') batteryRungs
  );

  # ── One glyph pack ────────────────────────────────────────────────────────
  #
  # Every glyph below is nf-md (Material Design, U+F0000+). The bar carried 18
  # Font Awesome, 16 Material, one Octicon, one Linux and three bare Unicode
  # arrows before 2026-08-27 — four vocabularies at four different stroke
  # weights, which is most of what made it read as assembled rather than
  # designed.
  #
  # These are the glyphs a module's label carries, and a label is text. The
  # window title, the minimized count and the battery wear real Papirus art
  # instead, through `-gtk-icontheme()` in the stylesheet — see `appIcons` and
  # `batteryRungs` above, and docs/adr/0052. nf-md is what the rest still use:
  # Material is the design language Papirus's symbolic set follows, which is why
  # the two sit together.
  #
  # Every codepoint was checked by rendering it, not by trusting its name — two
  # were the other way round from what they are called (`md-memory` U+F035B is
  # the CPU chip, `md-chip` U+F061A is the RAM stick). checks/static.sh asserts
  # the pack holds.
  modules = {
    clock = {
      format = "{:%H:%M}";
      format-alt = "{:%a %d %b}";
      # A date, not a calendar. The month grid moved to menus/calendar.sh, which
      # can be navigated and stays open; a tooltip could do neither and appeared
      # wherever the pointer was. docs/adr/0058.
      tooltip-format = "{:%A %d %B %Y}";
      # Left opens the panel, so the label toggle moves to the right button.
      # `format-alt-click` is a button number — mkBar defaults it to 1 for every
      # module carrying a format-alt, and this is the one that wants another.
      on-click = "${s}/menus/calendar.sh";
      format-alt-click = 3;
      # waybar's own action names, not commands — they reach Clock::doAction
      # rather than a shell. docs/adr/0057.
      actions = {
        on-scroll-up = "shift_up";
        on-scroll-down = "shift_down";
      };
    };

    "ext/workspaces" = {
      format = "{icon}";
      ignore-hidden = true;
      on-click = "activate";
      on-click-right = "deactivate";
      on-scroll-up = "mmsg dispatch viewtoleft_have_client";
      on-scroll-down = "mmsg dispatch viewtoright_have_client";
      sort-by-id = true;
      format-icons = {
        "1" = "1";
        "2" = "2";
        "3" = "3";
        "4" = "4";
        "5" = "5";
        "6" = "6";
        "7" = "7";
        "8" = "8";
        "9" = "9";
        default = "󰄰 ";
        urgent = "󰀨 ";
      };
    };

    # Was `mmsg -g -l | awk '{print $3}'` — dwl-era flags mango no longer takes.
    mpris = {
      format = "{status_icon} {dynamic}";
      # Three keys, and only one of them was set. All three were found by
      # rendering this module beside wayle's; none of it is guesswork.
      #
      # `dynamic-order` is which fields render. Unwritten it defaults to title,
      # artist, album and position, so the bar showed `The Yogscast
      # [06:03/13:48]` — a running clock nothing asked for, in the space the
      # title should have had. "Absence in this list means force exclusion"
      # (waybar-mpris(5)), so naming two excludes the rest.
      #
      # `dynamic-len` is a drop threshold, not a truncation one: waybar removes
      # a field that does not fit rather than shortening it. At 25 a 35-char
      # title vanished entirely and the 12-char artist was what remained —
      # which is why this is 100 and `max-length` does the cutting.
      # Reordering `dynamic-importance-order` does not change it; tried both
      # ways, same output.
      #
      # `max-length` is the one that behaves like wayle's `label-max-length`:
      # It truncates the composed string with an ellipsis. 27 = the status icon,
      # its space, and wayle's 25.
      dynamic-len = 100;
      max-length = 27;
      dynamic-order = [
        "title"
        "artist"
      ];
      dynamic-importance-order = [
        "title"
        "artist"
      ];
      status-icons = {
        playing = "󰐊 ";
        paused = "󰏤 ";
      };
      # Empty, and that is the whole reason this module was blank. `[ "firefox" ]`
      # came through the generation refactor from the hand-written configs with
      # no reason attached — waybar's own docs suggest it, because firefox can
      # expose one MPRIS player per playing tab. On this machine it exposes one
      # (`playerctl -l` → a single `firefox.instance_*`), and firefox is the only
      # player running, so the ignore meant the media module rendered nothing,
      # always. wayle's `media` has no such list, which is why that bar showed a
      # track where this one showed empty bar. docs/adr/0051.
      ignored-players = [ ];
      # The window this module is reporting, whichever player that is. It was
      # `scratch-toggle.sh Spotify spotify` — one player, hardcoded, so a video
      # playing in the browser put Spotify over it. docs/adr/0058.
      on-click = "${s}/media/media-focus.sh";
      on-click-right = "playerctl play-pause";
      on-scroll-up = "playerctl next";
      on-scroll-down = "playerctl previous";
    };

    # The windows the workspace tags cannot account for. A count and one icon,
    # because CSS gives a module one background image; the per-window art is the
    # picker's. Click restores a specific window, which `restore_minimized`
    # could not do and `focusid client,<id>` can. docs/adr/0052.
    "custom/minimized" = {
      exec = "${s}/waybar/minimized.sh";
      return-type = "json";
      format = "{}";
      on-click = "${s}/menus/minimized-menu.sh";
      escape = true;
    };

    # Not waybar's built-in dwl/window: mango 0.15.5 dropped the dwl IPC
    # protocol that module binds, and its absence makes waybar SIGSEGV on
    # startup. CSS selector is #custom-window, not #window.
    #
    # The icon is the stylesheet's: the script emits the appid as a `class` and
    # `iconCss` gives it a themed background. docs/adr/0052. 45 is coupled to
    # the stylesheet's font-size and to the padding that holds the icon.
    "custom/window" = {
      exec = "${s}/waybar/window-title.sh";
      return-type = "json";
      format = "{}";
      max-length = 45;
      escape = true;
    };

    cpu = {
      format = "󰍛 {usage}%";
      # The load average was in the tooltip and nowhere a click could reach,
      # while memory beside it had a second reading. docs/adr/0057.
      format-alt = "󰍛 {load}";
      tooltip-format = "CPU: {usage}%\nLoad: {load}";
      interval = 2;
      states = {
        warning = 70;
        critical = 90;
      };
      on-click-right = "${s}/scratchpad/scratch-toggle.sh sysmonitor ${s}/system/sysmonitor.sh";
    };

    memory = {
      format = "󰘚 {percentage}%";
      format-alt = "󰘚 {used:0.1f}·{total:0.1f}G";
      tooltip-format = "{used:0.1f} / {total:0.1f} GiB";
      interval = 5;
      states = {
        warning = 70;
        critical = 90;
      };
      # No `on-click = "alt"`. That is not one of waybar's action names, so
      # AModule::handleUserEvent fell through to forkExec and ran `alt` as a
      # shell command on every left-click — command not found, once per click,
      # silently. `format-alt-click` in mkBar is what actually toggles.
      # docs/adr/0057.
      on-click-right = "${s}/scratchpad/scratch-toggle.sh sysmonitor ${s}/system/sysmonitor.sh";
    };

    "custom/notification" = {
      tooltip = false;
      format = "{icon}";
      format-icons = {
        notification = "󰂚";
        none = "󰂚";
        dnd-notification = "󰂛";
        dnd-none = "󰂛";
        inhibited-notification = "󰂚";
        inhibited-none = "󰂚";
        dnd-inhibited-notification = "󰂛";
        dnd-inhibited-none = "󰂛";
      };
      return-type = "json";
      exec-if = "which swaync-client";
      exec = "swaync-client -swb";
      on-click = "sleep 0.1s && swaync-client -t -sw";
      on-click-right = "swaync-client -d -sw";
      escape = true;
    };

    network = {
      interval = 3;
      format-wifi = "󰖩 {essid}";
      format-ethernet = "󰈀 {ifname}";
      format-linked = "󰋗 No IP";
      format-disconnected = "󰖪 󰅖";
      format-disabled = "󰖪";
      tooltip-format = "{ifname}  {ipaddr}/{cidr}\nGateway: {gwaddr}\nStrength: {signalStrength}%";
      format-alt = "󰁅{bandwidthDownBytes} 󰁝{bandwidthUpBytes}";
      on-click-right = "${s}/menus/network-menu.sh";
    };

    "custom/vpn" = {
      exec = "${s}/menus/vpn.sh";
      return-type = "json";
      interval = 5;
      signal = 10;
      on-click = "${s}/menus/vpn.sh toggle";
      on-click-right = "${s}/menus/vpn-menu.sh";
      tooltip = true;
    };

    bluetooth = {
      format = "󰂯";
      format-disabled = "󰂳";
      format-connected = "󰂱";
      format-connected-battery = "󰂱 {device_battery_percentage}%";
      tooltip-format = "{controller_alias}\n{num_connections} connected";
      tooltip-format-connected = "{controller_alias}\n\n{device_enumerate}";
      tooltip-format-enumerate-connected = "{device_alias}";
      tooltip-format-enumerate-connected-battery = "{device_alias} {device_battery_percentage}%";
      on-click = "bluetoothctl power on; ${s}/menus/bluetooth-menu.sh";
      on-click-right = "bluetoothctl power off";
    };

    pulseaudio = {
      # `{format_source}` is the microphone, and it repeats into `format-muted`
      # because that replaces `format` rather than adding to it — a placeholder
      # left out of a replacement disappears under that condition, so muting the
      # speakers would take the microphone indicator off the bar with them.
      # docs/adr/0033 for why there is no `custom/microphone`.
      #
      # The live state is empty, and only the live one. docs/gotchas.md said
      # "neither state may render as nothing" and that over-generalised from the
      # muted case: what must never be invisible is muted, because "muted" and
      # "the module is broken" becoming one picture is being recorded when you
      # thought you were not. An empty live state fails the other way — no glyph
      # reads as "live", and a broken module also shows no glyph, so the wrong
      # reading is "I am being recorded", which is the safe one. A mic icon on
      # the bar at all times is a permanent indicator for a state that is
      # normal.
      #
      # The space lives in the muted glyph, not in `format`. A trailing
      # `{format_source}` that resolves to nothing still leaves the space before
      # it, which is a module that changes width for no visible reason.
      format = "{icon} {volume}%{format_source}";
      format-muted = "󰖁{format_source}";
      format-source = "";
      format-source-muted = " 󰍭";
      # Which sink is live was on the bar nowhere. The glyph says headphones or
      # speakers and stops there, so switching between two headsets, or to HDMI,
      # moved audio to a device the bar could not name. docs/adr/0057.
      tooltip-format = "{desc}";
      on-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
      on-click-right = "${s}/menus/volume-menu.sh";
      # Reads backwards on purpose. `trackpad_natural_scrolling=1` in
      # mango/universal/settings.conf inverts the axis before waybar sees it,
      # so fingers-UP arrives as on-scroll-DOWN — this is what makes swiping up
      # raise the volume. `-l 1.5` is a ceiling and belongs on the increase.
      on-scroll-up = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-";
      on-scroll-down = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%+ -l 1.5";
      format-icons = {
        headphone = "󰋋";
        headset = "󰋋";
        # One icon, not a three-step ladder — `network` and `bluetooth` name a
        # state and let the text carry the number, and the volume percentage is
        # already right beside this. A one-element array is how waybar says "the
        # same at every level"; wayle's `level-icons` took a single-element list
        # for the same reason. docs/adr/0051.
        default = [ "󰕾" ];
      };
    };

    backlight = {
      format = "{icon} {percent}%";
      # A moon and A sun until 2026-08-27, so low brightness drew `md-weather-
      # night` — a night-time glyph for a display setting, next to a night-mode
      # module that is a different thing entirely. One icon now, at every level,
      # for the reason the volume ladder lost its: the percentage is in the text
      # and the icon says which module this is. docs/adr/0051.
      format-icons = [ "󰃠" ];
      # Inverted for the same reason as pulseaudio above — natural scrolling
      # delivers fingers-up as on-scroll-down.
      on-scroll-up = "brightnessctl --class=backlight set 2%-";
      on-scroll-down = "brightnessctl --class=backlight set 2%+";
    };

    "custom/night-mode" = {
      format = "{}";
      exec = "${s}/menus/night-mode.sh status";
      return-type = "json";
      interval = "once";
      signal = 9;
      on-click = "${s}/menus/night-mode.sh toggle";
      on-click-right = "${s}/menus/night-mode.sh menu";
      tooltip = true;
    };

    # "Do not sleep" — the escape hatch for a long build on battery, and the
    # only thing that stops swayidle's ladder from inside the session.
    #
    # Was waybar's built-in `idle_inhibitor`, which held the inhibitor on the
    # bar's own layer surface. That worked, but the state was a bool in the
    # waybar process: it could only be toggled by clicking the widget — waybar
    # offers no IPC and no signal for it — and it was released, silently, by
    # every `waybar-reload`, mode switch and layout switch. Now the inhibitor is
    # a user unit that outlives the bar, this module only reports it, and
    # SUPER+shift+A reaches the same script. docs/adr/0031.
    #
    # `interval` as well as `signal`: the signal makes a toggle instant, and the
    # poll is the floor. If wlinhibit dies on its own the bar must stop claiming
    # the machine is held awake within 30s rather than never.
    "custom/idle-inhibitor" = {
      format = "{}";
      exec = "${s}/system/idle-inhibit.sh status";
      return-type = "json";
      interval = 30;
      signal = 12;
      on-click = "${s}/system/idle-inhibit.sh toggle";
      tooltip = true;
    };

    # Reads TLP's active profile from /run/tlp/last_pwr. Replaced waybar's
    # built-in power-profiles-daemon module, which bound a D-Bus API nothing
    # here implements — ppd is disabled because it conflicts with TLP, so the
    # module rendered empty and read as missing from the bar. It then spent a
    # year reporting the acpi platform profile, which moves nothing the
    # scheduler sees; docs/adr/0017.
    "custom/power-profile" = {
      exec = "${s}/system/power-profile.sh";
      return-type = "json";
      interval = 30;
      signal = 11;
      on-click = "${s}/system/power-profile-cycle.sh";
      on-click-right = "${s}/system/power-profile-cycle.sh toggle-fanless";
    };

    # The control centre, as a bar button. It runs menus/shell.sh rather than
    # control-center.sh directly, so the button and SUPER+C go through the one
    # router that knows which surface a mode has — in noctalia mode this reaches
    # noctalia's own control centre instead (docs/adr/0023, docs/adr/0033). A
    # bind or an on-click naming the implementation is a dead key in the other
    # mode that still exits 0.
    #
    # No `exec`: there is nothing to report. A custom module with only a format
    # is a static button, which is why this one cannot render empty the way the
    # exec-backed ones can.
    #
    # U+F1DE (nf-fa-sliders), checked against both bar fonts before picking —
    # `fc-list ':charset=F1DE' family`. The bar is "3270 Nerd Font" and
    # "Symbols Nerd Font Mono", not the Hack the menus use, and U+F6FF is the
    # standing proof that assuming coverage is how a glyph becomes a box.
    # Deliberately not the `bars` glyph: the control centre's own waybar row
    # already wears that, and two meanings for one glyph is worse than either.
    "custom/control-center" = {
      format = "󰘮";
      tooltip = false;
      on-click = "${s}/menus/shell.sh control-center";
    };

    # Built as a module first, read by the control centre second — a row that
    # fetched would own a fact the bar cannot see. docs/adr/0038.
    #
    # `interval` 300 against the script's 900 s ttl: the poll is a floor, not a
    # fetch. `signal` 13 is what `weather.sh refresh` raises; checks/static.sh
    # asserts the two numbers agree, because waybar drops an unhandled rt signal
    # in silence.
    "custom/weather" = {
      format = "{}";
      exec = "${s}/system/weather.sh status";
      return-type = "json";
      interval = 300;
      signal = 13;
      # Left opens the panel. It ran `refresh` until 2026-08-26 — a fetch whose
      # only possible output is a two-digit label that rarely moves inside a
      # quarter of an hour, i.e. a click that appears to do nothing. `refresh`
      # moved to the middle button, where it has the signal below to show for
      # itself. docs/adr/0050.
      on-click = "${s}/system/weather.sh panel";
      on-click-middle = "${s}/system/weather.sh refresh";
      # The tooltip is a reading, not a forecast site. Right-click is the way
      # out to one, and the verb is the script's so the bar holds no URL.
      on-click-right = "${s}/system/weather.sh open";
      tooltip = true;
    };

    "custom/phone" = {
      exec = "${s}/kdeconnect/phone-status.sh";
      return-type = "json";
      interval = 30;
      # A verb, not `kdeconnect-cli -d <id> --ring`: the device id belongs in
      # the script that already holds it, or the bar, the script and the
      # control-centre row end up with three copies of one string.
      on-click = "${s}/kdeconnect/phone-status.sh ring";
      on-click-right = "kdeconnect-cli --refresh";
    };

    # `bat`/`adapter` are named rather than left to waybar's auto-detection,
    # which walks /sys/class/power_supply in readdir order and keeps the last
    # entry carrying `online` or `status` as the adapter. This machine exposes
    # four supplies — AC, BAT0 and two ucsi-source-psy-USBC000:00* — and the
    # ucsi pair carry both attributes, so the adapter is currently AC only
    # because AC happens to sort last. Whichever one wins decides Plugged vs
    # Discharging when TLP's stop threshold parks BAT0 at `Not charging`.
    #
    # `interval` is explicit because waybar's default is 60s: the module is
    # otherwise event-driven (udev power_supply + an inotify watch on
    # BAT0/uevent) and falls back to a once-a-minute poll, so an unplug could
    # sit unreflected for a minute even when nothing is wrong.
    #
    # There is deliberately no `full-at`. It rescaled the reading as
    # `shown = real / full-at * 100` to make TLP's 85% charge stop read as
    # 100%, at the cost of the bar permanently disagreeing with every other
    # reading on the machine — 27% real showed as 32% against fastfetch's 27%,
    # which is how a frozen module got misdiagnosed as a rescale bug twice.
    # Showing the raw percentage costs only that the bar parks at 85% on AC.
    battery = {
      bat = "BAT0";
      adapter = "AC";
      interval = 5;

      # The ladder is the style's: each rung is a CSS class icons.css gives a
      # themed background. See `batteryRungs` above. docs/adr/0052.
      states = lib.listToAttrs (map (r: lib.nameValuePair (rungClass r) r.at) batteryRungs);

      # No `format-charging`/`format-plugged`: they only swapped the glyph, and
      # the charging icon is a CSS class now. That also frees `format-alt`,
      # which `update()` overrode whenever a per-status format existed — the
      # click did nothing on AC (battery.cpp:730), and now works in every state.
      format = "{capacity}%";
      format-alt = "{power}W · {time}";
      format-time = "{H}:{m}";
      tooltip-format = "{time}\n{health} · {cycles}";
    };

    # 16 to match every other icon on the bar; the symbolic backgrounds in
    # icons.css are 16px and the tray sat at 14. docs/adr/0053.
    tray = {
      icon-size = 16;
      spacing = 6;
    };

    # Glyph is nf-md-power (U+F0425). It was nf-linux-nixos (U+F313), and this
    # comment outlived it by one glyph-pack pass (docs/adr/0051), as did the
    # stylesheet calling it the NixOS logo and colouring it blue. The trailing
    # space went too: the right screen edge is `#custom-power`'s padding now.
    # docs/adr/0053.
    "custom/power" = {
      format = "󰐥";
      tooltip = false;
      # `-b` is a column count: keep it equal to the wlogout entry count in
      # programs.nix, or the overflow wraps into a row the margins leave no
      # room for. The margins are absolute pixels sized for eDP-1's 1920x1200
      # (§1) — they set the button size, and at -T/-B 320 the buttons were
      # 320x560 boxes holding a 52px icon.
      on-click = "wlogout -b 6 -c 12 -r 12 -T 505 -B 505 -L 290 -R 290 --protocol layer-shell";
      # The rofi power menu, not swaync. Right-click here opened the
      # notification panel until 2026-08-28 — byte-identical to
      # `custom/notification`'s left-click, two modules apart, and nothing on
      # the power button suggests it. docs/adr/0057.
      on-click-right = "${s}/menus/power-menu.sh";
    };
  };

  # ── Shared bar settings ───────────────────────────────────────────────────
  #
  # All margins are 0, for every layout, since hud left. They
  # used to be `margin-top = 6; margin-left/right = 8` — a floating bar — but
  # nothing ever rendered that: `waybar-restart.sh` zeroed all three with sed on
  # every launch, because the only mode with a bar is `tiling` and tiling wants
  # it flush. Those values were residue from the removed `dms` mode.
  barBase = {
    layer = "top";
    position = "top";
    height = 32;
    margin-top = 0;
    margin-bottom = 0;
    margin-left = 0;
    margin-right = 0;
    spacing = 0;

    # The bar re-reads style-solid.css and everything it @imports when the file
    # changes, so a rebuild alone applies a CSS edit. It does not cover the
    # .jsonc, which is why `waybar-restart.sh` still exists. Default is false.
    reload_style_on_change = true;
  };

  # ── Separators are structure ──────────────────────────────────────────────
  #
  # A side is a list of groups, flattened here into the flat list waybar wants.
  # Every group after the first has `#sep` appended to its first member: waybar
  # splits a module name on `#` (factory.cpp:129), names the widget after the
  # part before it and adds the part after as a style class (ALabel.cpp:34, and
  # the same three lines in wlr/taskbar, sni/tray and ext/workspace_manager), so
  # one `.sep` rule in style-solid.css draws every separator.
  #
  # The point is that grouping now belongs to the layout. It used to be fifteen
  # `border-left` rules keyed by module, so which groups appeared depended on
  # which modules a layout happened to carry — `custom/weather` opened a group
  # containing `cpu memory` in one layout and `custom/control-center` in
  # another, and neither was chosen. docs/adr/0042.
  tagGroups =
    groups:
    let
      present = lib.filter (g: g != [ ]) groups;
    in
    lib.concatLists (
      lib.imap0 (i: g: if i == 0 then g else [ "${lib.head g}#sep" ] ++ lib.tail g) present
    );

  # `foo#sep` -> `foo`. Definitions, tweaks and the assertions are all keyed by
  # the module's real name; only the emitted list carries the suffix.
  unTag = n: lib.head (lib.splitString "#" n);

  # Assemble a layout. `tweaks` patches a module for this layout only; every
  # such entry is a deliberate divergence and should say why at the call site.
  mkBar =
    {
      left,
      center ? [ [ "custom/window" ] ],
      right,
      bar ? { },
      tweaks ? { },
    }:
    let
      leftM = tagGroups left;
      centerM = tagGroups center;
      rightM = tagGroups right;
      emitted = leftM ++ centerM ++ rightM;
      used = map unTag emitted;
      unknown = lib.subtractLists (lib.attrNames modules) used;
      # A tweak for a module this layout does not carry is silently ignored by
      # waybar — which is how the old hand-written config-hud.jsonc ended up
      # defining a custom/power it never displayed.
      deadTweaks = lib.subtractLists used (lib.attrNames tweaks);
      # Keyed by the emitted name: waybar looks a tagged module's config up under
      # the suffixed key (factory.cpp passes `config_[name]`, not `config_[ref]`),
      # so `network#sep` with its settings under `network` renders with waybar's
      # defaults and nothing says so.
      # `format-alt` DOES NOTHING WITHOUT THIS. ALabel::handleToggle is gated on
      # `config_["format-alt-click"].isUInt()` (ALabel.cpp:181) and waybar sets
      # no default, so the four modules here that declare a `format-alt` — clock,
      # memory, network, battery — have never toggled. Added here rather than on
      # each module so the pair cannot come apart: declaring the format is what
      # asks for the click. docs/adr/0057.
      defs = lib.genAttrs emitted (
        n:
        let
          b = unTag n;
          m = modules.${b} // (tweaks.${b} or { });
        in
        lib.optionalAttrs (m ? format-alt) { format-alt-click = 1; } // m
      );
    in
    assert lib.assertMsg (
      unknown == [ ]
    ) "waybar: layout references undefined module(s): ${lib.concatStringsSep ", " unknown}";
    assert lib.assertMsg (
      deadTweaks == [ ]
    ) "waybar: tweaks for module(s) not in this layout: ${lib.concatStringsSep ", " deadTweaks}";
    barBase
    // bar
    // defs
    // {
      modules-left = leftM;
      modules-center = centerM;
      modules-right = rightM;
    };

  toWaybar = name: value: (pkgs.formats.json { }).generate name value;

  # ── The three layouts ─────────────────────────────────────────────────────
  #
  # Each side is a list of groups, and the group order is the same in all three:
  # A layout may drop a module but never reposition one, so SUPER+/ moves
  # nothing that both layouts carry. `checks/static.sh` asserts that, because it
  # is an invariant a plausible-looking edit can break in silence.
  #
  # These are position-independent. The top/bottom variants are derived below
  # rather than written out.
  baseLayouts = {
    # Full — everything.
    full = mkBar {
      left = [
        # Time and weather are one reading of "what is it like now", so they
        # share a group and no line divides them.
        [
          "clock"
          "custom/weather"
        ]
        [
          "ext/workspaces"
        ]
        [
          "mpris"
          "custom/minimized"
        ]
      ];
      right = [
        [ "custom/notification" ]
        [
          "cpu"
          "memory"
        ]
        # Custom/phone is KDE Connect, so it belongs with the radios rather than
        # beside the battery it happens to report.
        [
          "network"
          "custom/vpn"
          "bluetooth"
          "custom/phone"
        ]
        [
          "pulseaudio"
          "backlight"
          "custom/night-mode"
        ]
        [
          "custom/idle-inhibitor"
          "custom/power-profile"
          "battery"
        ]
        [
          "custom/control-center"
          "tray"
        ]
        [ "custom/power" ]
      ];
    };

    # Focus — drops the taskbar and the cpu/memory/phone readouts.
    focus = mkBar {
      left = [
        # Weather is ambient, not diagnostic — it is not one of the cpu/memory
        # readouts this layout drops. `focus` is the daily layout, so leaving it
        # out left the cache with nothing keeping it warm and the control-centre
        # row parked at `stale` as its default rather than its edge case.
        [
          "clock"
          "custom/weather"
        ]
        [
          "ext/workspaces"
        ]
        [ "mpris" ]
      ];
      right = [
        [ "custom/notification" ]
        [
          "network"
          "custom/vpn"
          "bluetooth"
        ]
        [
          "pulseaudio"
          "backlight"
          "custom/night-mode"
        ]
        [
          "custom/idle-inhibitor"
          "custom/power-profile"
          "battery"
        ]
        [
          "custom/control-center"
          "tray"
        ]
        [ "custom/power" ]
      ];
    };

    # Minimal — battery, tray and power only, plus the one way in to everything
    # else. This is where a single entry point is worth most: the toggles this
    # layout drops are exactly the ones the control centre still reaches.
    #
    # No custom/weather: this layout is deliberately near-empty, the
    # control-centre row is the way in, and `stale` is that row's honest state
    # when no module is keeping the cache warm. docs/adr/0038.
    minimal = mkBar {
      left = [
        [ "clock" ]
        [
          "ext/workspaces"
        ]
        [ "mpris" ]
      ];
      right = [
        [ "battery" ]
        [
          "custom/control-center"
          "tray"
        ]
        [ "custom/power" ]
      ];
      # No `custom/window` tweak. It was 80 here — "more room on the right, so
      # the title gets more characters" — which was true at 11px and is not at
      # 14px. wayle carried one cap for all three layouts and this is that.
      # docs/adr/0051.
    };

  };

  # ── Position variants, enumerated at build time ───────────────────────────
  #
  # `position` cannot be passed on the command line (`waybar --help` offers only
  # -c, -s and -b), so it has to be in the file: 3 layouts x 2 positions = 6
  # files, all statically known, and the script only picks a filename. It used
  # to be a runtime `sed -E` rewrite of the JSON Nix had just produced.
  #
  # Only `position` differs. Vertical margins were mirrored here too, for hud
  # alone, which cancelled its own exclusive zone with `margin-bottom = -28`.
  # Hud is gone and every remaining layout has all four margins
  # at 0 — restore the mirroring before adding a layout with a non-zero one.
  atBottom = bar: bar // { position = "bottom"; };

  layouts = lib.listToAttrs (
    lib.concatMap (name: [
      (lib.nameValuePair "config-${name}-top.jsonc" baseLayouts.${name})
      (lib.nameValuePair "config-${name}-bottom.jsonc" (atBottom baseLayouts.${name}))
    ]) (lib.attrNames baseLayouts)
  );
in
{
  # Installed rather than declared through xdg.dataFile: the profile's buildEnv
  # then reports a name another package already owns as a collision at
  # `nix flake check`, instead of one of the two silently winning.
  home.packages = [ appIconAliasPkg ];

  # Generated into ~/.config/mango/waybar/ alongside the hand-written CSS. The
  # `mango` entry in dotfiles.nix is `recursive = true`, so home-manager links
  # files individually and these coexist with it — but only because the four
  # .jsonc files were deleted from home/mango/waybar/. Two owners for one path
  # is an activation failure, not a merge.
  xdg.configFile =
    lib.mapAttrs' (
      name: value:
      lib.nameValuePair "mango/waybar/${name}" {
        source = toWaybar (lib.replaceStrings [ "." ] [ "-" ] name) value;
      }
    ) layouts
    // {
      # Derived from modules/home/palette.nix, so this file is not in
      # dotfiles/mango/waybar/ — one path, one owner. The names are the bar's own
      # vocabulary and the style sheets are written against them, which is why
      # they are spelled out rather than emitted by iterating the palette: a
      # renamed role should break the build here, not silently stop matching in
      # a `@import`ed stylesheet where GTK ignores the unknown colour without a
      # word.
      #
      # `surface` was here until hud left — style-hud.css was
      # its only consumer, and a generated colour nothing imports is exactly
      # what the both-directions assertion in checks/static.sh exists to catch.
      # Re-add it the moment a stylesheet wants it; the check enforces both ways.
      # The same table the stylesheet is generated from, for the picker to read.
      # A file rather than an argument on the bar's click: SUPER+CTRL+I opens the
      # same menu, and a table that reached only one of the two callers would
      # give the key a menu with no icons. docs/adr/0052.
      "mango/waybar/app-icons.json".text = builtins.toJSON appIcons;

      # Generated for the reason colors.css is — one owner for the name and the
      # selector that uses it. docs/adr/0052.
      "mango/waybar/icons.css".text = iconCss;

      "mango/waybar/colors.css".text = ''
        /* GENERATED from modules/home/palette.nix — edit that, then rebuild.
           Imported by every style-*.css. */
        @define-color base    #${p.base};
        @define-color overlay #${p.overlay};
        @define-color text    #${p.text};
        @define-color subtext #${p.subtext};
        @define-color accent  #${p.accent};
        @define-color green   #${p.okColor};
        @define-color red     #${p.errColor};
        @define-color yellow  #${p.warnColor};
        @define-color blue    #${p.infoColor};
      '';
    };
}
