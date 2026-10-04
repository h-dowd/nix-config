{
  description = "Henry's ThinkPad L14 Gen 5 — NixOS + home-manager (migrated from Arch)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hardware quirks for ThinkPads / AMD laptops.
    nixos-hardware.url = "github:NixOS/nixos-hardware";

    # Secrets — docs/adr/0012. `follows` is fine here, unlike claude-desktop.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # --- Third-party flakes --------------------------------------------------
    # Only these two. Everything else once sourced from a flake — mango, walker,
    # elephant and the rest — is in nixpkgs (checked 2026-07-27).

    # zen-browser-bin — not in nixpkgs
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # claude-desktop — not in nixpkgs. Deliberately NOT `follows`: it references
    # `pkgs.nodePackages`, which nixpkgs removed, so forcing our nixpkgs onto it
    # breaks evaluation of the whole system. Costs a second nixpkgs of sources.
    claude-desktop.url = "github:k3d3/claude-desktop-linux-flake";
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nixos-hardware,
      ...
    }@inputs:
    let
      system = "x86_64-linux";

      # Tooling only, deliberately WITHOUT the overlay — a lint result must not
      # depend on a package override.
      pkgs = nixpkgs.legacyPackages.${system};

      # Single overlay point — see ./pkgs/default.nix.
      overlays = [
        (import ./pkgs { inherit inputs; })
      ];
    in
    {
      nixosConfigurations.thinkpad = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };

        modules = [
          { nixpkgs.overlays = overlays; }

          # ThinkPad + AMD tuning from nixos-hardware.
          nixos-hardware.nixosModules.lenovo-thinkpad
          nixos-hardware.nixosModules.common-cpu-amd
          nixos-hardware.nixosModules.common-gpu-amd
          nixos-hardware.nixosModules.common-pc-laptop-ssd

          ./hosts/thinkpad

          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit inputs; };
              users.henry = import ./modules/home;
              backupFileExtension = "hm-bak";
            };
          }
        ];
      };

      # The gate — docs/adr/0010. `system` and `home` are real build products,
      # so checking them builds the whole closure: collisions, failing
      # derivations and eval errors surface here, not halfway through a switch.
      # An evaluate-only check cannot do that, which is why the old one went.
      checks.${system} = {
        system = self.nixosConfigurations.thinkpad.config.system.build.toplevel;
        home = self.nixosConfigurations.thinkpad.config.home-manager.users.henry.home.activationPackage;

        # Lints, tuned to fire only on real findings — a check that always
        # fails is one you learn to ignore. statix.toml says why.
        statix = pkgs.runCommandLocal "statix-check" { nativeBuildInputs = [ pkgs.statix ]; } ''
          cd ${self}
          statix check
          touch $out
        '';

        # `--no-lambda-pattern-names` excludes the module headers — required
        # boilerplate, and 37 of them bury the 2 real findings.
        deadnix = pkgs.runCommandLocal "deadnix-check" { nativeBuildInputs = [ pkgs.deadnix ]; } ''
          deadnix --fail --no-lambda-pattern-names ${self}
          touch $out
        '';

        # Shell is the layer that actually breaks here — docs/adr/0011. SC1091
        # is excluded permanently: shellcheck cannot statically resolve a
        # `. "$HOME/.config/…"` source path.
        # shellcheck AND shfmt over the same list: one shebang scan, one floor.
        # A second derivation would be a second copy of both.
        shellcheck =
          pkgs.runCommandLocal "shellcheck-check"
            {
              nativeBuildInputs = [
                pkgs.shellcheck
                pkgs.shfmt
                pkgs.findutils
              ];
            }
            ''
              cd ${self}
              find . -type f -print0 \
                | while IFS= read -r -d "" f; do
                    # tr strips null bytes binary files would otherwise feed
                    # to the substitution, which bash warns about.
                    case "$(head -c 64 "$f" 2>/dev/null | tr -d '\0' | head -1)" in
                      '#!'*bash*) printf '%s\0' "$f" ;;
                    esac
                  done > "$TMPDIR/scripts"

              # A scan that stops matching passes by finding nothing.
              found=$(tr -cd '\0' < "$TMPDIR/scripts" | wc -c)
              if [ "$found" -lt 30 ]; then
                echo "shellcheck: only $found scripts found — the shebang scan is broken" >&2
                exit 1
              fi

              xargs -0 -r shellcheck -e SC1091 < "$TMPDIR/scripts"
              echo "shellcheck: $found scripts clean"

              # `-d`, so the failure names the file and prints the diff. NOT
              # `-s`: simplify rewrites code rather than layout, and it is the
              # one mode `git diff -w` cannot clear.
              xargs -0 -r shfmt -d < "$TMPDIR/scripts"
              echo "shfmt: $found scripts formatted"
              touch $out
            '';

        # The documented claims, minus the ones needing a live compositor —
        # those stay in verify-claims.sh. docs/adr/0011.
        static =
          pkgs.runCommandLocal "static-check"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.jq
                pkgs.findutils
                pkgs.gnugrep
                # fc-scan, for the font check; its absence trips that
                # check's own floor rather than passing quietly.
                pkgs.fontconfig
                # xmllint, for power-profiles-tlp's dbus policy — an ill-formed
                # one is rejected by the whole system bus, not just by us.
                pkgs.libxml2
                # zstd, to hash the display firmware the system actually ships.
                pkgs.zstd
              ];
            }
            ''
              bash ${self}/checks/static.sh ${self} \
                ${self.nixosConfigurations.thinkpad.config.home-manager.users.henry.home.activationPackage} \
                ${self.nixosConfigurations.thinkpad.config.system.build.toplevel} \
                ${
                  # Every scheme this machine WEARS, RESOLVED. The check used to
                  # read hex out of the theme file with sed, which meant a role
                  # written as an alias (`okColor = green;`) read as "role
                  # absent" and went unaudited — four of them did. Nix resolves
                  # the `rec` here, so the check sees values rather than source
                  # text and every role is audited however it is spelled.
                  # docs/adr/0032.
                  #
                  # PLURAL since docs/adr/0034: modes.nix can put a second
                  # scheme on screen, and a legibility floor that only ever
                  # audits scheme.nix's would pass a mode nobody can read.
                  # `schemes` therefore holds the artefact scheme AND every one
                  # a mode names, deduplicated — so adding a mode scheme cannot
                  # add an unaudited one.
                  let
                    modes = import ./modules/home/modes.nix;
                    artefact = import ./modules/home/scheme.nix;
                    names = nixpkgs.lib.unique ([ artefact ] ++ nixpkgs.lib.attrValues modes);
                  in
                  pkgs.writeText "schemes.json" (
                    builtins.toJSON {
                      inherit artefact modes;
                      schemes = nixpkgs.lib.genAttrs names (n: import ./modules/home/themes/${n}.nix);
                    }
                  )
                } \
                ${
                  # Both package lists, name -> store path, RESOLVED. Ownership
                  # is an eval question, so it is answered exactly rather than by
                  # grepping two files. The check flags a name in both lists whose
                  # paths DIFFER — duplication is harmless until one side is
                  # overridden or pinned, and the naive intersection is 20 names
                  # of which 19 are byte-identical NixOS module defaults —
                  # too much noise to be worth reporting.
                  let
                    cfg = self.nixosConfigurations.thinkpad.config;
                    idx =
                      ps:
                      nixpkgs.lib.listToAttrs (
                        map (p: {
                          name = p.name or "?";
                          value = p.outPath or "?";
                        }) ps
                      );
                  in
                  pkgs.writeText "packages.json" (
                    builtins.toJSON {
                      system = idx cfg.environment.systemPackages;
                      home = idx cfg.home-manager.users.henry.home.packages;
                    }
                  )
                }
              touch $out
            '';
      };

      # Plain `nixfmt`, not `nixfmt-rfc-style` — same derivation at this pin,
      # and the alias warns on every eval.
      #
      # WRAPPED because `formatter = pkgs.nixfmt` cannot work: nixfmt takes
      # files, `nix fmt` passes none, and it then dies on empty stdin with
      # "unexpected end of input". Replace with treefmt-nix rather than growing
      # this.
      formatter.${system} = pkgs.writeShellApplication {
        name = "fmt";
        runtimeInputs = [
          pkgs.nixfmt
          pkgs.shfmt
          pkgs.findutils
        ];
        text = ''
          root="''${1:-.}"
          find "$root" -type f -name '*.nix' \
            -not -path '*/.git/*' -not -path '*/.direnv/*' -print0 \
            | xargs -0 -r nixfmt

          # Shell too, so `nix fmt` is a no-op across both languages. Selected
          # by SHEBANG rather than by extension — half these scripts have none
          # (dotfiles/scripts/*).
          find "$root" -type f \
            -not -path '*/.git/*' -not -path '*/.direnv/*' -print0 \
            | while IFS= read -r -d "" f; do
                case "$(head -c 64 "$f" 2>/dev/null | tr -d '\0' | head -1)" in
                  '#!'*bash*) printf '%s\0' "$f" ;;
                esac
              done \
            | xargs -0 -r shfmt -w
        '';
      };

      # `nix develop`, or via .envrc. Pins the tooling off PATH.
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.nixfmt
          pkgs.statix
          pkgs.deadnix
          pkgs.shellcheck
          pkgs.nix-tree # inspect closures

          # Here rather than packages.nix: only ever used against this repo,
          # and sops needs this directory's .sops.yaml for the recipients.
          pkgs.sops
          pkgs.age
        ];

        # One key rather than an editing key and a host key; henry-owned 600,
        # and root reads it at activation regardless.
        SOPS_AGE_KEY_FILE = "/var/lib/sops-nix/key.txt";
      };
    };
}
