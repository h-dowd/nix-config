{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  # `lockscreen`, not `swaylock`: it picks a background from the pool per lock
  # and execs swaylock-effects. docs/adr/0018.
  lockCmd = "${pkgs.lockscreen}/bin/lockscreen -f";

  # The last rung of the idle ladder, with the two exceptions worth making.
  #
  # `suspend`, not `hibernate` (ADR 0016): s0i3 is 0.15 W measured, so the rung
  # costs no image write and returns instantly. The lid is the other decision
  # and stays on hibernate — see the ADR for which evidence applies to which.
  idleSuspend = pkgs.writeShellApplication {
    name = "idle-suspend";
    runtimeInputs = [
      pkgs.systemd
      pkgs.playerctl
    ];
    text = ''
      # On AC, locked and blanked is enough. A missing AC node counts as
      # on-battery, so the sleep still happens.
      if [ "$(cat /sys/class/power_supply/AC/online 2>/dev/null || echo 0)" != 0 ]; then
        exit 0
      fi

      # Music with the lid open should not sleep. Only this rung checks:
      # dimming and locking over an album is right, and video needs no check at
      # all — mpv and Firefox hold a zwp_idle_inhibit surface, which stops the
      # ladder before it starts. `-x` so "Paused" does not match.
      if playerctl --all-players status 2>/dev/null | grep -qx Playing; then
        exit 0
      fi

      systemctl suspend
    '';
  };
in
{
  imports = [
    ./options.nix
    ./packages.nix
    ./shell.nix
    # Native home-manager program modules. Anything here GENERATES its config
    # from Nix; dotfiles.nix carries what is still a hand-written file. New
    # conversions go into programs.nix and come out of dotfiles.nix in the same
    # change — a config with two owners fails activation.
    ./programs.nix
    ./tmux.nix
    ./waybar.nix
    ./dotfiles.nix
    ./theme.nix
  ];

  home.username = "henry";
  home.homeDirectory = "/home/henry";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  # --- XDG ------------------------------------------------------------------
  xdg.enable = true;
  xdg.userDirs.enable = true;
  # Default flipped to false in home-manager; keep the legacy behaviour so
  # $XDG_DOWNLOAD_DIR etc. are exported to your session.
  xdg.userDirs.setSessionVariables = true;

  # mimeapps.list becomes a read-only store symlink, so "set as default" in a
  # GUI app fails — change it here and rebuild.
  xdg.mimeApps = {
    enable = true;
    defaultApplications =
      let
        # `zen-beta.desktop`, NOT `zen.desktop` — the flake installs the beta
        # channel, and the wrong name makes xdg fall back silently (it reported
        # chromium for https until 2026-07-30). Confirm the filename in
        # `/etc/profiles/per-user/henry/share/applications/` after a channel
        # change rather than assuming it.
        browser = [ "zen-beta.desktop" ];
        pdf = [ "org.pwmt.zathura.desktop" ];
        image = [ "imv.desktop" ];
        media = [ "mpv.desktop" ];
        files = [ "thunar.desktop" ];
        mail = [ "eu.betterbird.Betterbird.desktop" ];
        editor = [ "nvim.desktop" ];
        # qBittorrent rather than freedownloadmanager, which is not in nixpkgs.
        torrent = [ "org.qbittorrent.qBittorrent.desktop" ];
      in
      {
        "text/html" = browser;
        "x-scheme-handler/http" = browser;
        "x-scheme-handler/https" = browser;
        "x-scheme-handler/about" = browser;
        "x-scheme-handler/unknown" = browser;

        "application/pdf" = pdf;

        "image/png" = image;
        "image/jpeg" = image;
        "image/gif" = image;
        "image/webp" = image;
        "image/svg+xml" = image;

        "video/mp4" = media;
        "video/x-matroska" = media;
        "video/webm" = media;
        "audio/mpeg" = media;
        "audio/flac" = media;

        "inode/directory" = files;
        "application/zip" = files;

        "x-scheme-handler/mailto" = mail;
        "text/calendar" = mail;

        "text/markdown" = editor;
        "application/x-shellscript" = editor;
        "text/plain" = editor;

        "application/x-bittorrent" = torrent;
        "x-scheme-handler/magnet" = torrent;

        "x-scheme-handler/discord" = [ "equibop.desktop" ];
        "x-scheme-handler/obsidian" = [ "obsidian.desktop" ];
      };
  };

  # --- Services -------------------------------------------------------------
  services.cliphist.enable = true; # replaces your cliphist autostart

  # The only thing that locks on sleep. NOT a power.nix hook — that cgroup is
  # killed on resume, taking swaylock with it (docs/SYSTEM.md §9). Absolute
  # paths throughout: swayidle's `sh -c` has bash on PATH and nothing else.
  #
  # Safe to lock on idle because mango advertises zwp_idle_inhibit_manager_v1,
  # so mpv and Firefox suppress the ladder during playback.
  services.swayidle = {
    enable = true;
    events = {
      before-sleep = lockCmd;
      lock = lockCmd;
    };
    timeouts = [
      # Dim as the warning that the lock is coming; -s/-r save and restore.
      {
        timeout = 240;
        command = "${pkgs.brightnessctl}/bin/brightnessctl -s set 10%";
        resumeCommand = "${pkgs.brightnessctl}/bin/brightnessctl -r";
      }
      # Lock, THEN blank: `-f` forks only once the lock is up, so this order
      # cannot flash the desktop. `;` not `&&` — a swaylock started over a
      # manual lock exits non-zero, and `&&` would leave the panel lit for the
      # rest of the idle period.
      {
        timeout = 300;
        command = "${lockCmd}; ${pkgs.wlopm}/bin/wlopm --off '*'";
        resumeCommand = "${pkgs.wlopm}/bin/wlopm --on '*'";
      }
      # Idle with the panel dead is still several watts, which is a flat battery
      # overnight; suspended it is 0.15 W. upower's 3% hibernate is the backstop
      # under it, so an unattended suspend cannot end in a lost session.
      {
        timeout = 1800;
        command = "${idleSuspend}/bin/idle-suspend";
      }
    ];
  };

  # The only low-battery warning: upower's percentages are policy inputs and
  # waybar only recolours. -S limits it to power supplies (else the headphones
  # alert too); -s drops the startup burst of current-state events.
  services.poweralertd = {
    enable = true;
    extraArgs = [
      "-s"
      "-S"
    ];
  };

  # nixpkgs' swaync unit races the `exec=` line in autostart.conf, which owns
  # the lifecycle, so it is masked — docs/adr/0005. An empty file rather than a
  # /dev/null symlink: both mask, and pure eval refuses the absolute path.
  xdg.configFile."systemd/user/swaync.service".text = "";

  # Not `services.wlsunset`: it bakes the temperature into ExecStart, and
  # wlsunset has no runtime IPC, so the waybar picker could not change it. The
  # runner reads ~/.local/state/mango/night-temp instead.
  #
  # This unit owns the process — only one client can hold a Wayland gamma
  # control, and the loser fails silently.
  systemd.user.services.wlsunset = {
    Unit = {
      Description = "Day/night gamma adjustments (night light)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };
    Service = {
      ExecStart = "%h/.config/mango/scripts/system/night-light-run.sh";
      # A unit's `PATH=` is its entire PATH, so `bash` is mandatory — without
      # it the runner's `env bash` shebang exits 127.
      Environment = [
        "PATH=${
          lib.makeBinPath [
            pkgs.bash
            pkgs.coreutils
            pkgs.wlsunset
          ]
        }"
        "NIGHT_LAT=53.35" # Dublin
        "NIGHT_LONG=-6.26"
        "NIGHT_DAY_TEMP=6500"
      ];
      Restart = "always";
      RestartSec = 3;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # "Do not sleep". Holds a `zwp_idle_inhibit_manager_v1` inhibitor on a bare
  # wl_surface — the one mechanism mango's ext_idle_notifier honours, and so the
  # only thing that stops swayidle's ladder from inside the session
  # (`systemd-inhibit --what=idle` does not reach it at all, SYSTEM.md §9).
  # It also blocks `handle-lid-switch`, so a closed lid does nothing while held;
  # logind honours that lock whatever `LidSwitchIgnoreInhibited` says.
  #
  # A unit rather than waybar's built-in idle_inhibitor module, which kept the
  # state as a bool in the bar process and released it on every reload and
  # layout switch — and could only ever be toggled by clicking the
  # widget, never from a key. docs/adr/0031.
  #
  # NO [Install]. Nothing starts this at login: it is switched on by
  # ⌥⇧A or a click on the bar, via scripts/system/idle-inhibit.sh,
  # and an inhibitor that came up on its own would be the failure it exists to
  # prevent. `PartOf` still ends it with the session.
  systemd.user.services.wlinhibit = {
    Unit = {
      Description = "Hold a Wayland idle inhibitor (keep awake)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };
    Service = {
      ExecStart = "${pkgs.systemd}/bin/systemd-inhibit --what=handle-lid-switch --mode=block --who=wlinhibit '--why=Keep awake' ${pkgs.wlinhibit}/bin/wlinhibit";
      # `on-failure`, not `always`: wlinhibit exits 0 on SIGTERM, so a
      # deliberate `systemctl --user stop` — which is what the toggle does —
      # must stay stopped. A crash must not: a silently released inhibitor is
      # exactly the failure mode here, and the bar polls every 30s so a unit
      # that hits the restart limit shows up rather than lingering as a lie.
      Restart = "on-failure";
      RestartSec = 1;
    };
  };

  # ⌘ is Ctrl for apps (modules/system/locale.nix); terminals take copy, paste
  # and their own shortcuts on Ctrl+Shift instead. Bindings are `keyd bind`
  # expressions, applied on focus by keyd-application-mapper. docs/adr/0062
  xdg.configFile."keyd/app.conf".text = ''
    [kitty]
    cmd.c = C-S-c
    cmd.v = C-S-v
    cmd.equal = C-S-equal
    cmd.minus = C-S-minus
    cmd.backspace = C-u

    [foot]
    cmd.c = C-S-c
    cmd.v = C-S-v
    cmd.n = C-S-n
    cmd.f = C-S-f
    cmd.backspace = C-u

    # appid com.mitchellh.ghostty; the mapper matches it lowercased, dots as -.
    [*ghostty]
    cmd.c = C-S-c
    cmd.v = C-S-v
    cmd.t = C-S-t
    cmd.w = C-S-w
    cmd.n = C-S-n
    cmd.backspace = C-u
  '';

  # A file, not ~/.config/keyd: the mapper writes app.lock beside it. It
  # reloads on app.conf's mtime, which a store path never changes, hence the
  # restart trigger.
  systemd.user.services.keyd-application-mapper = {
    Unit = {
      Description = "Per-application keyd bindings";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
      X-Restart-Triggers = [ config.xdg.configFile."keyd/app.conf".source ];
    };
    Service = {
      ExecStart = "${pkgs.keyd}/bin/keyd-application-mapper -v";
      # Unbuffered, or `-v`'s appid log never reaches the journal.
      Environment = [
        "KEYD_BIN=${pkgs.keyd}/bin/keyd"
        "PYTHONUNBUFFERED=1"
      ];
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  services.nextcloud-client = {
    enable = true;
    startInBackground = true;
  };

  # --- Session environment --------------------------------------------------
  # `systemd.user.sessionVariables`, not `home.*`: the latter writes
  # hm-session-vars.sh, which user units do not source — and the target here is
  # xdg-desktop-portal-gtk, a user unit that ignores settings.ini without
  # GTK_THEME. Must match theme.nix's `gtk.theme.name`.
  systemd.user.sessionVariables = {
    GTK_THEME = "catppuccin-mocha-mauve-standard";
    QT_QPA_PLATFORM = "wayland";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
  };

  # --- User systemd units ---------------------------------------------------
  # autostart.conf starts this target; without it that exec_once fails silently
  # on every boot. A marker for other units to hang off — nothing Wants it.
  systemd.user.targets.mango-session = {
    Unit = {
      Description = "MangoWC Session Target";
      Requires = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
  };

  # Proton Drive is deliberately absent (2026-07-30): Proton blocks rclone's
  # access method. Its unit is also the motivating failure for docs/adr/0006 —
  # anything talking to a remote API needs a StartLimitBurst.
}
