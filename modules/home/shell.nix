{
  config,
  pkgs,
  ...
}:

{
  # --- zsh ------------------------------------------------------------------
  # The login shell. home-manager owns ~/.zshrc, so the hand-written conf.d
  # files are sourced from initContent rather than re-expressed in Nix.
  programs.zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh"; # relative dotDir is deprecated

    autosuggestion.enable = true; # zsh-autosuggestions
    syntaxHighlighting.enable = true; # zsh-syntax-highlighting
    enableCompletion = true; # zsh-completions
    historySubstringSearch.enable = true; # zsh-history-substring-search

    history = {
      size = 50000;
      save = 50000;
      ignoreDups = true;
      ignoreSpace = true;
      share = true;
      path = "${config.xdg.dataHome}/zsh/history";
    };

    initContent = ''
      for f in "$ZDOTDIR"/conf.d/*.zsh(N); do
        source "$f"
      done
    '';
  };

  # fish was dropped 2026-07-28. If it comes back, use
  # EITHER programs.fish.enable OR a dotfiles link, never both.

  # --- Tools that hook the shell -------------------------------------------
  # `--cmd cd` here rather than in conf.d/10-aliases.zsh, which duplicated it.
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
    options = [
      "--cmd"
      "cd"
    ];
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableZshIntegration = true;
  };

  # --- Aliases --------------------------------------------------------------
  # Minimal on purpose: the interesting ones are shell *functions* in
  # conf.d/10-aliases.zsh, sourced above. See CLAUDE.md for the `ls` trap.
  home.shellAliases = {
    cat = "bat";
    lf = "yazi";
    zed = "zeditor";
    pdf = "xdg-open";
    cleantmp = "~/.scripts/clean_tmp";
    lidaction = "~/.scripts/toggle_lid_action";

    # ~/.config/mango/scripts is deliberately off PATH — 31 files with names
    # like `lib.sh` would land in completion. Aliases for the two typed by
    # hand are cheaper. Both need a `rebuild` first: the tree is a store path.
    waybar-reload = "~/.config/mango/scripts/waybar/waybar-restart.sh";
    mango-reload = "~/.config/mango/scripts/reload.sh";

    # The flake ref MUST stay quoted: EXTENDED_GLOB makes `#` a pattern
    # operator, so an unquoted ref dies with `zsh: no matches found:` before
    # nixos-rebuild runs. See CLAUDE.md.
    #
    # `&& nvd diff` because on a config where reloading without rebuilding looks
    # exactly like the change having had no effect, seeing what actually moved
    # is worth a line. `&&`, so a failed rebuild does not diff a system it did
    # not build.
    #
    # THE TWO TAKE DIFFERENT ARGUMENTS. `switch` activates, so afterwards
    # /run/current-system and /nix/var/nix/profiles/system are the same path
    # and diffing them always prints nothing — so capture the old system first.
    # `boot` does not activate, so there the two differ and the plain form
    # works.
    #
    # rebuild-test is deliberately bare: it creates no profile generation, so
    # there is nothing to diff against.
    rebuild = ''prev=$(readlink -f /run/current-system); sudo nixos-rebuild switch --flake "${config.local.checkout}#thinkpad" && nvd diff "$prev" /run/current-system'';
    rebuild-test = ''sudo nixos-rebuild test --flake "${config.local.checkout}#thinkpad"'';
    rebuild-boot = ''sudo nixos-rebuild boot --flake "${config.local.checkout}#thinkpad" && nvd diff /run/current-system /nix/var/nix/profiles/system'';
    update = ''nix flake update --flake "${config.local.checkout}"'';
    generations = "nixos-rebuild list-generations";
    gc = "sudo nix-collect-garbage --delete-older-than 30d";
    search = "nix search nixpkgs";
  };

  # PATH additions that were in conf.d/20-path.zsh. cargo and bun stay because
  # rustup and bun are user-installed.
  home.sessionPath = [
    "$HOME/.config/emacs/bin"
    "$HOME/.cargo/bin"
    "$HOME/.local/bin"
    "$HOME/.scripts"
    "$HOME/.bun/bin"
  ];

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    BUN_INSTALL = "$HOME/.bun";
    # XDG_CONFIG_HOME stays default; the mango tree is reached per-keybind
    # instead.
  };

  programs.git = {
    enable = true;
    settings = {
      user.name = "Henry";
      user.email = "henry@dowd.ie";
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };
}
