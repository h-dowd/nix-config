{
  config,
  pkgs,
  lib,
  ...
}:

{
  boot.loader.systemd-boot = {
    enable = true;
    # Your esp is only 1 GiB and is shared with Arch's kernel+initramfs
    # (~60 MiB). NixOS writes a full kernel + initrd per generation, roughly
    # 120 MiB each, so an unbounded list will fill the partition and break
    # `nixos-rebuild`. 6 is a safe ceiling; raise it if you enlarge the esp.
    configurationLimit = 6;
    editor = false; # don't let anyone type init=/bin/sh at the boot menu
  };
  boot.loader.efi.canTouchEfiVariables = true;

  # Tracks mainline closely — currently 7.1.5. Do not "fix" the amdgpu/TTM crash
  # by dropping to `pkgs.linuxPackages` (6.18.40): the Arch install that preceded
  # this ran the same 7.1.5 and never crashed, so the version is not the variable
  # — Overdrive was, and it is off in power.nix. See docs/gotchas.md → Power.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Carried over from your systemd-boot entry. zswap is disabled because you
  # use zram (see power.nix) — running both is counterproductive.
  boot.kernelParams = [ "zswap.enabled=0" ];

  # Crash behaviour. The amdgpu/TTM oops this machine hits kills its process
  # while it still holds the TTM lru_lock ("exited with preempt_count 1"), so
  # every later GPU client deadlocks behind the leaked lock and the box freezes
  # instead of dying. With panic_on_oops it panics at the first fault and
  # reboots, which matters for more than convenience: cutting power mid-freeze
  # leaves the i8042 latched, and the next boot enumerates the keyboard without
  # enabling it ("Failed to enable keyboard on isa0060/serio0") — so the greeter
  # takes no keystrokes and needs a *second* hard reset. Rebooting cleanly is
  # what breaks that chain. The panic still reaches /sys/fs/pstore.
  #
  # sysrq is 1 (all functions) rather than NixOS's default 16 (sync only) so a
  # freeze can be escaped with Alt+SysRq+S,U,B instead of the power button. That
  # does hand full sysrq to anyone at the keyboard; this disk is unencrypted, so
  # physical access already wins.
  boot.kernel.sysctl = {
    "kernel.panic_on_oops" = 1;
    "kernel.panic" = 10;
    "kernel.sysrq" = 1;
  };

  boot.supportedFilesystems = [
    "btrfs"
    "ntfs"
  ];

  # Arch's `linux-firmware` equivalent, plus the sof-firmware you have installed.
  hardware.enableAllFirmware = true;
  # yellow-carp-dmcub goes first, because the first package with a file wins.
  # docs/gotchas.md → Power.
  hardware.firmware = lib.mkMerge [
    (lib.mkBefore [ pkgs.yellow-carp-dmcub ])
    [ pkgs.sof-firmware ]
  ];

  # Snapper: on NixOS this is much less load-bearing than on Arch, because
  # every rebuild already produces a rollback-able generation. Kept for /home,
  # which generations do not cover.
  services.snapper = {
    configs.home = {
      SUBVOLUME = "/home";
      ALLOW_USERS = [ "henry" ];
      TIMELINE_CREATE = true;
      TIMELINE_CLEANUP = true;
      TIMELINE_LIMIT_HOURLY = 5;
      TIMELINE_LIMIT_DAILY = 7;
      TIMELINE_LIMIT_WEEKLY = 4;
      TIMELINE_LIMIT_MONTHLY = 2;
      TIMELINE_LIMIT_YEARLY = 0;
    };
  };
}
