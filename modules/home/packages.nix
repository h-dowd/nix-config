# User packages. Anything replaced by a NixOS module (pipewire, tlp, keyd, cups,
# podman, steam, …) lives in modules/system/ instead.
#
# One owner per package. A package is installed by exactly one of: its
# `programs.*` module, a `home.packages` entry here, or
# `environment.systemPackages`. User applications go in home; things needed
# before login or by a system unit go in system. A tool that does nothing
# without a system service goes with that service, so both can be removed at
# once — that is why `distrobox` is in virtualisation.nix, next to podman.
#
# Two copies resolving to the same store path are harmless until one side is
# overridden or pinned; then PATH order decides which binary you get.
# `checks/static.sh` checks for divergence, not duplication — 20 names are in
# both lists and 19 are byte-identical.
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

{
  home.packages =
    with pkgs;
    [
      # --- Shell / CLI core ---------------------------------------------------
      # Completions the NixOS zsh module used to carry — see hosts/thinkpad.
      zsh-completions
      nix-zsh-completions
      bat
      eza
      fd
      ripgrep
      fzf
      zoxide
      tree
      bottom # btm
      gdu
      tealdeer # tldr
      sysstat
      powertop
      unzip
      unrar
      p7zip
      jq
      wget
      curl
      rsync
      man-pages
      man-pages-posix

      # --- Git / forge --------------------------------------------------------
      git
      git-filter-repo
      lazygit
      gh
      glab
      tea # gitea

      # --- Editors ------------------------------------------------------------
      neovim
      vis
      vscode # vscodium collides over lib/vscode — pick one
      code-cursor
      jetbrains.pycharm

      # --- Language servers ---------------------------------------------------
      # nvim is mason-free, so servers come from $PATH. A missing one is skipped
      # in silence — audit with `:checkhealth lsp`, and confirm by output.
      nil # Nix
      lua-language-server
      bash-language-server
      marksman # Markdown
      taplo # TOML
      yaml-language-server
      pyright # Python type checking
      ruff # Python lint + format
      clang-tools # C/C++ — clangd is here, not in `clang`
      typescript-language-server
      typescript # tsserver for the above; not bundled with it
      gopls
      golangci-lint-langserver
      golangci-lint # required by the above
      texlab # LaTeX
      tinymist # Typst

      # --- Formatters ---------------------------------------------------------
      # Called by conform.nvim. rustfmt comes with rustup, ruff_format with ruff.
      stylua
      shfmt

      # --- ai / dev assistants ------------------------------------------------
      claude-code
      opencode
      codex
      cursor-cli
      github-copilot-cli

      # --- Terminals / multiplexer --------------------------------------------
      ghostty
      tmux

      # --- Languages / toolchains ---------------------------------------------
      rustup
      # gfortran ships its own cc/c++, colliding with clang. buildEnv only errors
      # when priorities are equal, so lowPrio on clang does nothing — hiPrio is
      # what breaks the tie. Cost: cc/c++ resolve to clang, unlike Arch.
      (lib.hiPrio clang)
      gfortran
      python313
      (lib.lowPrio python311) # 3.13 wins the unversioned python3/pydoc3/idle3
      python3Packages.pip
      lua5_1
      nodejs
      bun
      go
      # dlv. helix's built-in dap was the only thing wired to this; nvim has no
      # dap config, so it is now a standalone CLI debugger. Kept deliberately.
      delve

      # --- Kubernetes / cloud -------------------------------------------------
      kubectl
      kubernetes-helm
      argocd
      kubeseal

      # --- Networking / security ----------------------------------------------
      nmap
      masscan
      tcpdump
      dnsutils # dig, nslookup
      netcat-openbsd
      wireguard-tools
      openresolv
      sshfs
      rclone
      restic
      lynx
      qbittorrent # also the magnet/torrent handler — see xdg.mimeApps
      openssl

      # --- Documents / writing ------------------------------------------------
      pandoc
      typst
      typstyle
      # texliveFull would pull ~20 GiB of collections that aren't used here.
      (texlive.withPackages (
        ps: with ps; [
          scheme-basic
          collection-latex
          collection-latexrecommended
          collection-latexextra
          collection-xetex
          collection-fontsrecommended
        ]
      ))
      glow
      libreoffice-stable
      hunspellDicts.en_GB-ise
      hyphen
      zathura
      pdftk
      exiftool
      ghostscript # ~/.scripts/pdf_to_a4 needs gs

      # --- Notes / pkm --------------------------------------------------------
      obsidian
      anki
      iotas

      # --- Media --------------------------------------------------------------
      mpv
      yt-dlp
      gimp3
      blender
      spotify
      spicetify-cli
      gpu-screen-recorder
      gst_all_1.gst-libav
      gst_all_1.gst-plugins-good

      # --- Browsers / comms ---------------------------------------------------
      firefox
      chromium
      tor-browser
      equibop
      teams-for-linux
      bitwarden-desktop
      rbw # rofi-rbw (SUPER+p) is a front-end over this; without it the key opens an empty list
      pinentry-qt # rbw's config.json asks for "pinentry", which every variant provides
      warpinator
      kdePackages.kdeconnect-kde # not valent — the mango configs call kdeconnect-cli
      thunderbird # betterbird isn't packaged; this is its upstream
      proton-authenticator
      cloudflare-warp
      silverbullet
      # rstudio — boost::urls does not link under the GCC 16 stdenv, and hydra
      # has not built it either. docs/gotchas.md → nixpkgs. Restore the line.
      # rstudio

      # --- Games --------------------------------------------------------------
      lutris
      heroic
      prismlauncher
      dolphin-emu
      luanti
      itch
      nethack
      sl
      wineWow64Packages.stable # wineWowPackages is deprecated upstream
      winetricks
      sidequest
      winboat
      # Bedrock also needs the mcpelauncher-updates mod dropped in
      # ~/.local/share/mcpelauncher/mods/ — the packaged libc shim has no
      # pthread_sigmask. docs/gotchas.md -> nixpkgs and NixOS
      mcpelauncher-ui-qt

      # --- System / disk ------------------------------------------------------
      # nvd is here and not in the devShell: the `rebuild` aliases call it, and
      # from an ordinary shell a devShell-only binary exits 127 silently.
      nvd
      btrfs-progs
      btdu
      snapper
      ntfs3g
      ddcutil
      brightnessctl
      fastfetch
      eyedropper
      libqalculate
      dsearch
      weathr
      efibootmgr

      # --- Desktop utilities --------------------------------------------------
      pcmanfm
      pavucontrol
      wl-clipboard
      wtype # rofi-rbw autotypes with this
      grim
      slurp
      wlopm # power.nix drives it from the sleep hooks via ${pkgs.wlopm}
      # Here for the mango binds only: those are plain text in a store path and
      # cannot interpolate a Nix path, so they need the name on PATH. Every
      # caller Nix *can* reach uses ${pkgs.lockscreen} instead.
      lockscreen

      # --- Android / misc tooling ---------------------------------------------
      apktool
      android-tools
    ]
    ++ [
      inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
      inputs.claude-desktop.packages.${pkgs.stdenv.hostPlatform.system}.claude-desktop
    ];

  # Not in nixpkgs — all decided 2026-07-29, none of it open:
  #   piavpn-bin           pia already runs through NetworkManager (8 OpenVPN
  #                        profiles, passwords inline, certs under @home). Only
  #                        the gui kill switch / port forwarding is lost.
  #   freedownloadmanager  replaced by qbittorrent; torrent half only
  #   torbrowser-launcher  tor-browser itself is packaged
  #   betterbird-bin       thunderbird, the upstream it forks
  #   quickmedia, pipemixer, r-quick-share, haroopad, mdview, pdf-compress,
  #   qrookie-vrp          dropped — use distrobox if any turn out to be missed
  #   nerd-fonts-sf-mono   dropped, unreferenced (and not redistributable)
  #   ttf-phosphor-icons   dropped, unreferenced — was a DankMaterialShell dep
  #
  # Packaged locally in ../../pkgs/default.nix:
  #   brother-mfc-l3740cdw, curseforge
}
