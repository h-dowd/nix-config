{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

{
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true; # hardlink identical files in /nix/store
    trusted-users = [
      "root"
      "henry"
    ];

    # Prebuilt binaries so you're not compiling Chromium locally.
    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];

    # 12 threads on the 7535U.
    max-jobs = "auto";
    cores = 0;
  };

  # Garbage collection. Without this /nix/store grows without bound — the
  # single most common complaint from new NixOS users.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Pin `nixpkgs` (for `nix shell nixpkgs#foo` and legacy nix-* commands) to
  # the exact revision the system was built from, instead of letting it fetch
  # a second, drifting copy of nixpkgs.
  nix.registry.nixpkgs.flake = inputs.nixpkgs;
  nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

  # Named, not blanket. `allowUnfree = true` permits any unfree package,
  # including one arriving transitively — so an input that starts pulling one in
  # is something you find out about later, if at all. A predicate turns that
  # into a build error naming the package.
  #
  # Longer than the application list. Six of these were found only by setting
  # the predicate and rebuilding until it went green: nixpkgs splits some apps
  # across several derivations, and `hardware.enableAllFirmware` (boot.nix)
  # drags in unfree firmware for hardware this machine does not have.
  nixpkgs.config.allowUnfreePredicate =
    p:
    builtins.elem (lib.getName p) [
      # Applications.
      "steam"
      "steam-unwrapped"
      "steam-run"
      "spotify"
      "obsidian"
      "vivaldi"
      "google-chrome"
      "unrar"
      "cloudflare-warp"
      "hplip" # printer drivers
      "1password"

      # Editors and assistants.
      "vscode"
      "cursor"
      "cursor-cli"
      "pycharm"
      "claude-code"
      "claude-desktop"
      "github-copilot-cli"

      # Not asked for directly. corefonts is steam's `fontPackages`; the rest
      # come from hardware.enableAllFirmware, for hardware this ThinkPad does
      # not have. Listed rather than worked around, so the predicate records
      # what is actually permitted.
      "corefonts"
      "broadcom-bt-firmware"
      "b43-firmware"
      "xone-dongle-firmware"
      "facetimehd-calibration"
      "facetimehd-firmware"
    ];

  # Optional but recommended for a laptop: build in the background at low
  # priority so a rebuild doesn't make the machine unusable.
  nix.daemonCPUSchedPolicy = "idle";
  nix.daemonIOSchedClass = "idle";
}
