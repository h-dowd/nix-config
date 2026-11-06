{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Display power via the compositor — wlopm needs the Wayland socket, so it
  # runs as the session user while the sleep hooks are root. The loop covers
  # whichever socket the session got (mango takes wayland-0 or wayland-1);
  # `|| true` degrades a failed hook to "screen stays on". docs/SYSTEM.md §9.
  setDisplayPower = mode: ''
    for sock in /run/user/*/wayland-[0-9]; do
      [ -e "$sock" ] || continue
      rundir=$(${pkgs.coreutils}/bin/dirname "$sock")
      uid=$(${pkgs.coreutils}/bin/basename "$rundir")
      user=$(${pkgs.coreutils}/bin/id -nu "$uid" 2>/dev/null) || continue
      ${pkgs.util-linux}/bin/runuser -u "$user" -- \
        ${pkgs.coreutils}/bin/env \
          "XDG_RUNTIME_DIR=$rundir" \
          "WAYLAND_DISPLAY=$(${pkgs.coreutils}/bin/basename "$sock")" \
          ${pkgs.wlopm}/bin/wlopm --${mode} '*' || true
    done
  '';
  # Nothing throttled goes into a sleep. Hibernation's entry phase preallocates
  # ~5.8 GiB and compresses into zram before it can snapshot — 7 s at full clock,
  # 22 s capped — and a lid reopened inside that window hung the machine outright
  # on 2026-08-13. No restore side is needed: `tlp suspend` touches only AHCI and
  # ASPM, and `tlp resume` reapplies the AC/BAT profile. docs/gotchas.md → Power.
  #
  # `set -e` is in effect in the generated pre-sleep script, so every write is
  # guarded — an unhandled failure here would abort the hook that powers the
  # panel down.
  unthrottleForSleep = ''
    # Boost first: with it off the driver clamps cpuinfo_max_freq to the 2901000
    # nominal, so reading it before this lifts the cap only part of the way.
    if [ -w /sys/devices/system/cpu/cpufreq/boost ]; then
      echo 1 > /sys/devices/system/cpu/cpufreq/boost || true
    fi

    # Counted, because uncapping nothing is the failure that looks like success.
    lifted=0
    for pol in /sys/devices/system/cpu/cpufreq/policy[0-9]*; do
      [ -w "$pol/scaling_max_freq" ] || continue
      top=$(${pkgs.coreutils}/bin/cat "$pol/cpuinfo_max_freq") || continue
      if echo "$top" > "$pol/scaling_max_freq"; then
        lifted=$((lifted + 1))
      fi
    done
    [ "$lifted" -gt 0 ] || echo "sleep: no cpufreq policy uncapped, entering sleep throttled" >&2

    for gpu in /sys/class/drm/card[0-9]/device/power_dpm_force_performance_level; do
      if [ -w "$gpu" ]; then
        echo auto > "$gpu" || true
      fi
    done
  '';
  # One command for a mode switch, because TLP cannot do all of it. Its amdgpu
  # branch folds PP_BAL and PP_SAV together and reads only
  # RADEON_DPM_PERF_LEVEL_ON_BAT — a `_ON_SAV` variant is accepted into
  # tlp.conf and never read, so the iGPU pin has to happen here. docs/adr/0017.
  powerMode = pkgs.writeShellApplication {
    name = "power-mode";
    runtimeInputs = [ config.services.tlp.package ];
    text = ''
      case "''${1:-}" in
        performance | balanced | power-saver) ;;
        *)
          echo "usage: power-mode <performance|balanced|power-saver>" >&2
          exit 2
          ;;
      esac

      tlp "$1" >/dev/null

      # 200 MHz vs the 1899 MHz top state. Only the fanless mode pays the
      # compositor latency for it.
      case "$1" in
        power-saver) level=low ;;
        *) level=auto ;;
      esac
      # `if`, not `[ -w … ] && …`: writeShellApplication sets -e, so the AND-list
      # form exits 1 on the first card without the node. Counted because pinning
      # nothing is the failure that looks like success.
      pinned=0
      for gpu in /sys/class/drm/card[0-9]/device/power_dpm_force_performance_level; do
        if [ -w "$gpu" ]; then
          echo "$level" > "$gpu"
          pinned=$((pinned + 1))
        fi
      done
      [ "$pinned" -gt 0 ] || echo "power-mode: no writable amdgpu DPM node, iGPU not pinned" >&2

      exit 0
    '';
  };
in
{
  # --- TLP ------------------------------------------------------------------
  # Conflicts with TLP. Note that this removes the ANSWER as well as the second
  # tuner — PPD is also the interface desktops ask the profile through — so
  # power-profiles-tlp below owns that bus name instead. docs/adr/0026.
  services.power-profiles-daemon.enable = false;

  services.tlp = {
    enable = true;
    settings = {
      # WiFi half of the ath11k resume workaround; the rest is in networking.nix.
      WIFI_PWR_ON_AC = "off";
      WIFI_PWR_ON_BAT = "off";

      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      CPU_SCALING_GOVERNOR_ON_SAV = "powersave";
      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
      CPU_ENERGY_PERF_POLICY_ON_SAV = "power";

      PLATFORM_PROFILE_ON_AC = "performance";
      PLATFORM_PROFILE_ON_BAT = "low-power";
      PLATFORM_PROFILE_ON_SAV = "low-power";

      # The fan responds to bursts, not to averages: EPP only biases how eagerly
      # the governor ramps, so with boost on, a keystroke-sized task still hits
      # 4.63 GHz and spikes the package to ~30 W. Capping is the only thing that
      # stops it. docs/adr/0017.
      CPU_BOOST_ON_AC = 1;
      CPU_BOOST_ON_BAT = 0;
      CPU_BOOST_ON_SAV = 0;

      # Every profile states BOTH ends, including the two wanting the full range:
      # an unset bound leaves the previous profile's cap in place, not "no
      # limit". docs/gotchas.md → Power.
      #
      # 418414 is cpuinfo_min_freq (the driver's own floor, lowest_nonlinear,
      # is 2.7x higher); 4630443 is cpuinfo_max_freq, which the driver clamps
      # to the 2901000 nominal with boost off — intended, not a surprise.
      CPU_SCALING_MIN_FREQ_ON_AC = 418414;
      CPU_SCALING_MAX_FREQ_ON_AC = 4630443;
      CPU_SCALING_MIN_FREQ_ON_BAT = 418414;
      CPU_SCALING_MAX_FREQ_ON_BAT = 4630443;
      CPU_SCALING_MIN_FREQ_ON_SAV = 418414;

      # amd_pstate_lowest_nonlinear_freq: the highest clock still at minimum core
      # voltage, so the best perf-per-watt point on the curve.
      #
      # Efficiency is the objective here only because the thermal one turned out
      # to be unreachable. Two fan-calibrate runs put the EC trip at ~47-48 °C
      # against a 40-46 °C idle, and twelve threads cross that even at 418 MHz —
      # sustained all-core work cannot be fanless on this chassis at any clock,
      # so a lower cap buys silence it cannot deliver and costs real speed.
      # docs/adr/0017.
      CPU_SCALING_MAX_FREQ_ON_SAV = 1115770;

      # Panel self-dimming, 0-3. Visibly shifts contrast at 3, which is why the
      # everyday profile stays at 1.
      AMDGPU_ABM_LEVEL_ON_AC = 0;
      AMDGPU_ABM_LEVEL_ON_BAT = 1;
      AMDGPU_ABM_LEVEL_ON_SAV = 3;

      # Longevity over runtime. On AC the battery parks where it is and only
      # tops up below START, so a static sub-100% reading is correct — see
      # docs/SYSTEM.md §9.
      START_CHARGE_THRESH_BAT0 = 75;
      STOP_CHARGE_THRESH_BAT0 = 85;
    };
  };

  # The waybar toggle needs root for `tlp`. Scoped to this one wrapper rather
  # than the tlp binary, which also carries discharge/setcharge/recalibrate.
  # sudo-rs, not sudo — hosts/thinkpad disables the latter.
  environment.systemPackages = [ powerMode ];

  # Both paths, because sudo-rs resolves the *directory* symlinks of the command
  # it is given and stops: `power-mode` off $PATH canonicalises to
  # $system-path/bin/power-mode, not to the package it links to, and a rule
  # naming only the package silently does not match — the toggle just reports
  # "interactive authentication is required". docs/gotchas.md → Power.
  security.sudo-rs.extraRules = [
    {
      groups = [ "wheel" ];
      commands =
        map
          (c: {
            command = c;
            options = [ "NOPASSWD" ];
          })
          [
            "${powerMode}/bin/power-mode"
            "${config.system.path}/bin/power-mode"
          ];
    }
  ];

  # --- the PPD bus name, answered from TLP ----------------------------------
  # Everything that speaks power-profiles-daemon — `powerprofilesctl`, GNOME's
  # power page — finds no service here, because TLP
  # holds the ground PPD would (`services.power-profiles-daemon.enable = false`
  # above). They render nothing and say nothing. This unit owns the name and
  # answers it from `/run/tlp/last_pwr` and `power-mode`, so those clients drive
  # the same three profiles as the bar and ⌥⇧P. docs/adr/0026.
  systemd.services.power-profiles-tlp = {
    description = "power-profiles-daemon D-Bus API, served from TLP";
    wantedBy = [ "multi-user.target" ];

    # BindsTo, not Requires: with TLP gone the name must LEAVE the bus, so
    # clients see an absent service rather than a stale profile that looks live.
    #
    # `multi-user.target` here is LOAD-BEARING even though nothing needs it —
    # without it the `wantedBy` above closes an ordering cycle and systemd
    # breaks it by deleting this unit's start job, which looks exactly like the
    # unit not existing. docs/gotchas.md → Power has the journal output.
    after = [
      "tlp.service"
      "multi-user.target"
    ];
    bindsTo = [ "tlp.service" ];

    # StartLimit* belong in [Unit], not [Service] — docs/adr/0006. The daemon
    # refuses to start when TLP reports no profile, so without a limit a
    # too-early start becomes an unbounded loop that reads as `activating`.
    startLimitIntervalSec = 60;
    startLimitBurst = 5;

    serviceConfig = {
      Type = "simple";
      # The wrapper is passed in rather than looked up: this is the one
      # definition of `power-mode`, and a PATH lookup that missed would be a
      # daemon that starts and cannot switch anything.
      ExecStart = "${pkgs.power-profiles-tlp}/bin/power-profiles-tlp --power-mode ${powerMode}/bin/power-mode";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  # Ships share/dbus-1/system.d/…PowerProfiles.conf — the policy that lets root
  # own the name and wheel set the profile. Without this the daemon starts and
  # cannot claim the name at all.
  services.dbus.packages = [ pkgs.power-profiles-tlp ];

  services.thermald.enable = false; # Intel-only

  # --- zram -----------------------------------------------------------------
  # Priority 5 against the swapfile's -1, so ordinary swapping never hits disk.
  # The swapfile exists only for hibernation images, which zram cannot hold.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  # --- Lid / suspend --------------------------------------------------------
  # Hibernate, not suspend-then-hibernate: a spurious wake degrades s-t-h to a
  # plain suspend the machine sometimes never resumes from. docs/adr/0015.
  # (The idle rung suspends — docs/adr/0016. Different evidence.)
  services.logind.settings.Login = {
    HandleLidSwitch = "hibernate";
    HandleLidSwitchExternalPower = "hibernate";
    # Clamshell on an external display must keep running. Undocking with the lid
    # still shut re-handles as an undocked close — see docs/SYSTEM.md §9.
    HandleLidSwitchDocked = "ignore";

    # Tap matches the lid, long press is the hard stop. The systemd defaults
    # are the other way round, so a brushed button ended the session.
    HandlePowerKey = "hibernate";
    HandlePowerKeyLongPress = "poweroff";
  };

  # Without this a logind.conf-only change never reaches the running daemon and
  # the lid keeps its previous action until reboot, unlogged. `restartTriggers`
  # not `reloadTriggers`: the module's `reloadIfChanged` turns it into a reload,
  # and setting both warns. docs/gotchas.md → Power.
  systemd.services.systemd-logind.restartTriggers = [
    config.environment.etc."systemd/logind.conf".source
  ];

  # --- Power the display down across sleep ----------------------------------
  # A lit panel holds s0i3 off and costs ~4 W through the whole suspend. The
  # backlight cannot do this — brightnessctl drives the PWM and leaves the
  # DISPLAY block active. Overlaps swayidle's own wlopm timeout harmlessly.
  # docs/SYSTEM.md §9.
  #
  # The un-throttle runs last, and for suspend as well as hibernate — only
  # hibernate has an entry phase long enough to matter, but one hook for
  # sleep.target beats a second unit that has to tell them apart.
  powerManagement.powerDownCommands = setDisplayPower "off" + unthrottleForSleep;

  # Load-bearing: an output left off is not restored by input, so without this
  # the machine wakes to a black screen no keypress fixes.
  powerManagement.resumeCommands = setDisplayPower "on";

  programs.corectrl.enable = true; # avoids a polkit prompt per launch

  # Overdrive is deliberately absent: it sets amdgpu.ppfeaturemask, which taints
  # every boot CPU_OUT_OF_SPEC and gets upstream reports dismissed unread.
  # Nothing here used it. docs/gotchas.md → Power.

  # --- Critical battery -----------------------------------------------------
  # `Hibernate`, not the NixOS default `HybridSleep`, which writes the image and
  # then stays in s2idle at the one moment the machine must draw nothing. Also
  # the backstop under the idle suspend (docs/adr/0016).
  #
  # 3%, one point above upower's default, for poll-interval slack. The three
  # percentages must stay strictly descending or upower silently discards all
  # three for its own. docs/SYSTEM.md §9.
  services.upower = {
    enable = true;
    criticalPowerAction = "Hibernate";
    percentageAction = 3;
  };

  services.fwupd.enable = true;
}
