{
  config,
  pkgs,
  lib,
  ...
}:

{
  fonts = {
    enableDefaultPackages = true;

    packages = with pkgs; [
      # Nerd Fonts. On nixpkgs-unstable these are individual packages under
      # `nerd-fonts.*` (the old monolithic `nerdfonts` with `fonts = [...]`
      # was split up in 2024 — if you pin an older nixpkgs, use that instead).
      nerd-fonts.hack # ttf-hack-nerd — your kitty/foot font
      nerd-fonts.fira-code # ttf-firacode-nerd
      nerd-fonts.jetbrains-mono # ttf-jetbrains-mono-nerd
      # The bar's icons — style-solid.css names this ahead of its text face so
      # the patched-in glyphs keep their own metrics.
      nerd-fonts.symbols-only

      # The bar's text. It left with docs/adr/0058 and came back with
      # docs/adr/0059: it is the look the bar is wanted to have, and no
      # other surface asks for it.
      nerd-fonts._3270

      # kitty's bold_font and italic_font. Only the Nerd-patched build provides
      # family "0xProto Nerd Font Mono" — plain `_0xproto` is family "0xProto",
      # so both lines silently fell back to Hack. A font named in a config and
      # missing from this list renders as a silent fallback; found 2026-08-11
      # via `kitty --debug-font-fallback`.
      nerd-fonts._0xproto

      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji # NOT `noto-fonts-emoji` — that name doesn't exist
      ibm-plex # ttf-ibm-plex
      liberation_ttf
      corefonts # ttf-ms-fonts (unfree)
      dejavu_fonts

      # Serif faces you have installed
      charis # ttf-bitstream-charter's packaged relative (attr is `charis`, not `charis-sil`)
      league-gothic # ttf-league-gothic

      # Icon font for the bar / shell widgets
      material-symbols
      # ttf-phosphor-icons is NOT in nixpkgs. If your Waybar config renders
      # Phosphor glyphs, drop the TTFs into ~/.local/share/fonts — fontconfig
      # picks them up with no packaging needed. (It was mainly a DMS
      # dependency, which is being dropped, so you may not need it at all.)
    ];

    fontconfig = {
      enable = true;
      antialias = true;
      hinting.enable = true;
      hinting.style = "slight";
      subpixel.rgba = "rgb";

      defaultFonts = {
        monospace = [
          "Hack Nerd Font Mono"
          "Noto Sans Mono"
        ];
        sansSerif = [
          "IBM Plex Sans"
          "Noto Sans"
        ];
        serif = [
          "Charis SIL"
          "Noto Serif"
        ];
        emoji = [ "Noto Color Emoji" ];
      };
    };
  };

  # nerd-fonts-sf-mono (AUR) has no nixpkgs equivalent — Apple's SF Mono is
  # not redistributable. Drop it, or add the patched TTFs by hand:
  #   fonts.packages = [ (pkgs.runCommand "sf-mono-nerd" {} ''
  #     mkdir -p $out/share/fonts/truetype
  #     cp ${./../../assets/sf-mono}/*.ttf $out/share/fonts/truetype/
  #   '') ];
}
