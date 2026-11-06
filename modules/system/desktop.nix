{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  # tuigreet's `--cmd` inherits greetd.service's own file descriptors, which
  # `useTextGreeter` below points at /dev/tty1 — so the compositor and every
  # child it spawns write stdout and stderr into the greeter's VT text buffer.
  # Confirm with `ls -l /proc/$(pgrep -x mango)/fd/1` → /dev/tty1. The text is
  # invisible while mango holds the VT in graphics mode and shows through the
  # greeter at the edges of a session, which reads as the overdraw bug below
  # coming back. It is not that one: this stream is the session's, not PID 1's.
  #
  # `systemd-cat`, not /dev/null: output that goes nowhere is this repo's
  # signature bug. Read it with `journalctl -t mango`. docs/gotchas.md → Desktop.
  mangoSession = pkgs.writeShellScript "mango-session" ''
    exec ${pkgs.systemd}/bin/systemd-cat --identifier=mango \
      ${config.programs.mango.package}/bin/mango
  '';
in
{
  # --- Session / login ------------------------------------------------------
  # tuigreet is a TTY greeter, so it cannot fail in a way that locks you out of
  # a graphical session. `regreet`/`gtkgreet` are the graphical swaps.
  services.greetd = {
    enable = true;

    # tuigreet IS a text greeter, and this flag is the module's own switch for
    # saying so — it defaults to false, which is right for the graphical
    # greeters and wrong for every TUI one. It gates `StandardInput/Output=tty`
    # plus TTYPath/TTYReset/TTYVHangup/TTYVTDisallocate on greetd.service, the
    # same set `getty@` carries. Without them greetd never claims or clears
    # tty1, so the greeter draws on top of whatever the boot left there and
    # systemd keeps printing `[ OK ] Started …` over it for every job dispatched
    # after `Type=idle` gave up waiting — libvirt, the greeter's own user
    # session, polkit. It reads as a corrupt or half-drawn login screen.
    #
    # Note the kernel is NOT the source here: console loglevel is 4, and
    # `journalctl -k -p err` over the greeter's window is empty. `quiet` and
    # `boot.consoleLogLevel` would be cargo cult. docs/gotchas.md → Desktop.
    useTextGreeter = true;

    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd ${mangoSession}";
      user = "greeter";
    };
  };

  # --- Compositor -----------------------------------------------------------
  programs.mango.enable = true; # in nixpkgs — no upstream flake needed

  # Load-bearing: without /etc/pam.d/swaylock, PAM falls back to `other` —
  # pam_warn + pam_deny — and every password is rejected, correct or not. sway
  # and river get this from wayland-session.nix; programs.mango does not import
  # it. docs/gotchas.md → swaylock.
  security.pam.services.swaylock = {
    # Off deliberately. swaylock cannot render pam_fprintd's prompt, so with the
    # sensor ahead of pam_unix the first seconds of every unlock swallow your
    # typing. docs/gotchas.md → swaylock.
    fprintAuth = false;
  };

  # --- Fingerprint ----------------------------------------------------------
  # Synaptics 06cb:00f9; enrol with `fprintd-enroll`. This turns the sensor on
  # for EVERY pam service — `fprintAuth` defaults to it — so the password-first
  # UIs are switched back off individually below.
  services.fprintd.enable = true;

  # greetd substacks `login`, so this covers the greeter and TTY login both.
  security.pam.services.login.fprintAuth = false;

  # Stall before the password prompt; upstream default is 30 s. `settings`, not
  # `args` — args is computed from it.
  security.pam.services.sudo.rules.auth.fprintd.settings.timeout = 10;

  # Everything mango's config, scripts and keybinds shell out to.
  environment.systemPackages = with pkgs; [
    # Bar / notifications / OSD / lock
    waybar
    swaynotificationcenter
    # THE OSD. waybar has none, so without it the volume, brightness and lock
    # keys have no feedback whatever.
    #
    # Its udev rule did NOT come back with it and does not need to: the
    # backlight grant is brightnessctl's own now, a superset of what
    # `99-swayosd.rules` gave. modules/system/audio.nix.
    swayosd
    swaylock-effects
    # wlogout is deliberately absent — programs.wlogout owns it in home. Two
    # profiles carrying one binary makes PATH order decide which you get.
    wayfreeze

    # Launchers & menus. SUPER+space is `rofi -show drun` since docs/adr/0043;
    # there is no separate launcher package any more.
    # nixpkgs `rofi` is the merged wayland fork; `rofi-wayland` is gone. It is
    # a wrapper over `rofi-unwrapped`, so plugins go through `plugins = [...]`
    # — listing them as separate systemPackages entries drops a .so into a
    # directory rofi never looks in, and `-show calc` then fails with "Mode
    # calc is not found" on a stderr nobody reads. Verify with
    # `rofi -h | sed -n '/Detected modes/,/^$/p'`, which must list both.
    # dotfiles/rofi/config.rasi names the same two modes; static.sh pairs them.
    (rofi.override {
      plugins = [
        rofi-calc # `=` in walker; SUPER+equal here. Shells out to its own qalc.
        rofi-emoji # `.` in walker; SUPER+semicolon here
      ];
    })
    # NOT a rofi plugin — a standalone front-end over `rbw`, so it is a package
    # in its own right rather than an entry above. Replaced elephant's
    # bitwarden provider (SUPER+p).
    rofi-rbw

    # Clipboard
    cliphist
    wl-clip-persist
    wl-clipboard

    # Wallpaper / colour
    mpvpaper
    matugen
    awww # nixpkgs renamed `swww` -> `awww`

    # Utilities the keybinds and mode scripts shell out to, derived by grepping
    # the mango tree for invoked binaries rather than guessed.
    libnotify # notify-send
    jq # mode scripts patch Equibop's settings.json
    glib # gsettings, for gtk-apply.sh
    libsForQt5.qttools # qdbus, for phone-status.sh
    brightnessctl
    ddcutil
    playerctl
    wev
    grim
    slurp
    wlsunset
    xwayland-satellite
    uwsm
    bluez # bluetoothctl, for the bluetooth menu

    # Session bits
    gnome-keyring
    polkit_gnome
    networkmanagerapplet
    blueman
    pavucontrol

    # Theming — packages only; the GTK/Qt settings live in theme.nix.
    catppuccin-gtk # pinned to mocha/mauve by the overlay
    adw-gtk3
    gnome-themes-extra
    papirus-icon-theme # recoloured violet by the overlay
    # `papirus-folders` is deliberately absent: it recolours in place, so on a
    # store path it is a no-op that looks like the solution. See pkgs/default.nix.
    libsForQt5.qtstyleplugin-kvantum
    kdePackages.qtstyleplugin-kvantum
    kdePackages.qt6ct # no top-level `qt6ct` attribute exists
    libsForQt5.qt5ct
    nwg-look
  ];

  # A user service rather than an autostart.conf line, which only fires on
  # initial compositor start.
  systemd.user.services.polkit-gnome-authentication-agent-1 = {
    description = "polkit-gnome authentication agent";
    wantedBy = [ "graphical-session.target" ];
    wants = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
      RestartSec = 1;
    };
  };

  # --- Portals --------------------------------------------------------------
  # wlr handles screencast on wlroots compositors; gtk the file chooser.
  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
    ];
    config.common.default = [
      "wlr"
      "gtk"
    ];
  };

  # --- Bluetooth ------------------------------------------------------------
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings.General.Experimental = true; # battery reporting for headsets
  };
  services.blueman.enable = true;

  # --- Graphics -------------------------------------------------------------
  hardware.graphics = {
    enable = true;
    enable32Bit = true; # Steam / wine
    extraPackages = with pkgs; [
      libva-vdpau-driver # renamed from `vaapiVdpau`; don't list both
      libvdpau-va-gl
    ];
  };

  # --- Theming --------------------------------------------------------------
  qt = {
    enable = true;
    platformTheme = "qt5ct";
  };

  programs.dconf.enable = true;

  # File manager + trash/mount support
  programs.thunar = {
    enable = true;
    plugins = with pkgs; [
      thunar-archive-plugin
      thunar-volman
    ];
  };
  services.gvfs.enable = true;
  services.tumbler.enable = true;
  services.udisks2.enable = true;

  # Flatpak is deliberately absent (2026-07-28): the three Arch flatpaks were
  # not wanted. `services.flatpak.enable` ships the daemon only — the remote and
  # the apps are still manual.
}
