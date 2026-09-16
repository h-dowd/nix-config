{
  config,
  pkgs,
  lib,
  ...
}:

let
  # PIA's public CA, vendored so the profiles do not depend on the unmanaged
  # copies under ~/.local/share that `nmcli connection import` left behind.
  piaCa = ./pia-ca.pem;

  # The eight exits differ only in the remote. UUIDs are the ones the existing
  # profiles already carry, so this replaces them rather than adding duplicates.
  piaExits = {
    algeria = {
      remote = "dz.privacy.network:1198";
      uuid = "06ca0528-ded9-4e61-942c-38f6ade33146";
    };
    ca_ontario = {
      remote = "ca-ontario.privacy.network:1198";
      uuid = "344c0cad-9406-49fe-8a08-a0801584655a";
    };
    ireland = {
      remote = "ireland.privacy.network:1198";
      uuid = "9a01179b-e84e-4bb8-a8c7-8adaae65442b";
    };
    netherlands = {
      remote = "nl-amsterdam.privacy.network:1198";
      uuid = "a35c6f2c-5ecc-46a2-8b1b-047113936654";
    };
    us_chicago = {
      remote = "us-chicago.privacy.network:1198";
      uuid = "6deec400-be5f-4d5e-b24a-86d6e085065e";
    };
    us_east = {
      remote = "us-newjersey.privacy.network:1198";
      uuid = "5266ecfe-263b-4545-a381-1e858506299d";
    };
    us_houston = {
      remote = "us-houston.privacy.network:1198";
      uuid = "00d0e219-a76c-4897-9a30-d0f6d60c3500";
    };
    us_new_york = {
      remote = "us-newyorkcity.privacy.network:1198";
      uuid = "4734d13f-0a2e-4710-bb09-e60f35126729";
    };
  };

  # $PIA_* are substituted by envsubst from the sops-rendered env file, so no
  # credential reaches the world-readable store. checks/static.sh asserts it.
  mkPiaExit = name: exit: {
    connection = {
      id = name;
      inherit (exit) uuid;
      type = "vpn";
      autoconnect = false;
    };
    vpn = {
      service-type = "org.freedesktop.NetworkManager.openvpn";
      auth = "sha1";
      ca = "${piaCa}";
      challenge-response-flags = 2;
      cipher = "aes-128-cbc";
      compress = "yes";
      connection-type = "password";
      dev = "tun";
      password-flags = 0;
      inherit (exit) remote;
      remote-cert-tls = "server";
      reneg-seconds = 0;
      username = "$PIA_USERNAME";
    };
    vpn-secrets.password = "$PIA_PASSWORD";
    ipv4.method = "auto";
    ipv6.method = "auto";
  };
in
{
  networking.networkmanager = {
    enable = true;
    wifi.powersave = false; # see the ath11k note below
    plugins = with pkgs; [ networkmanager-openvpn ];
  };

  # --- Declared connection profiles ----------------------------------------
  # Only the nine that carry a credential or can hijack the default route. The
  # ~29 ordinary APs stay in NetworkManager's own state: ensureProfiles writes
  # to /run and deletes nothing, so declaring a subset is the supported shape,
  # not a compromise. See docs/adr/0013.
  networking.networkmanager.ensureProfiles = {
    environmentFiles = [ config.sops.templates."networkmanager.env".path ];

    profiles = (lib.mapAttrs mkPiaExit piaExits) // {
      # Split tunnel: ipv4.never-default is deliberately absent because the
      # peer's allowed-ips already scope the routes. `autoconnect = false` is
      # the load-bearing line — see docs/adr/0013 for what enabling it costs.
      homelab = {
        connection = {
          id = "homelab";
          uuid = "1532bf5d-d039-4403-9e99-ee6a24fa0c64";
          type = "wireguard";
          interface-name = "homelab";
          autoconnect = false;
        };
        wireguard.private-key = "$WG_HOMELAB_PRIVATE_KEY";
        "wireguard-peer.jwg75JGsLgmtvA0JPCgrr/yf4YXCpH3ltDEeHlYsbjU=" = {
          endpoint = "home.henrydowd.dev:443";
          allowed-ips = "192.168.1.1/32;192.168.1.5/32;192.168.1.2/32;192.168.1.10/32;192.168.1.11/32;192.168.1.200/32;10.0.0.0/24;";
          persistent-keepalive = 25;
        };
        ipv4 = {
          method = "manual";
          address1 = "10.0.0.2/32";
          dns = "192.168.1.5;";
        };
        ipv6.method = "disabled";
      };
    };
  };

  # You have BOTH NetworkManager and systemd-networkd enabled on Arch, which is
  # a genuine conflict — networkd is enabled by preset and NM is doing the real
  # work. NixOS refuses to let both manage interfaces, so only NM is enabled.
  networking.useNetworkd = false;
  networking.useDHCP = false;

  services.resolved.enable = true;

  networking.firewall = {
    enable = true;
    # Warpinator (file transfer) and KDE Connect need these open.
    allowedTCPPorts = [
      42000
      42001
    ];
    allowedTCPPortRanges = [
      {
        from = 1714;
        to = 1764;
      }
    ]; # KDE Connect
    allowedUDPPortRanges = [
      {
        from = 1714;
        to = 1764;
      }
    ];
  };

  # mDNS — you run avahi for CUPS printer discovery.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
      userServices = true;
    };
  };

  # --- WiFi resume fix ------------------------------------------------------
  # Your Arch system carries /etc/systemd/system-sleep/wifi-resume.sh because
  # the ath11k_pci driver on the QCNFA765 does not reassociate cleanly with the
  # Minerva_2 router after suspend. That hook is reproduced here as a proper
  # systemd unit. `wifi.powersave = false` above replaces the TLP
  # WIFI_PWR_ON_{AC,BAT}=off half of the fix.
  systemd.services.wifi-resume = {
    description = "Cycle the WiFi radio after resume (ath11k_pci reassociation workaround)";
    after = [
      "suspend.target"
      "hibernate.target"
      "hybrid-sleep.target"
    ];
    wantedBy = [
      "suspend.target"
      "hibernate.target"
      "hybrid-sleep.target"
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "wifi-resume" ''
        sleep 3
        ${pkgs.networkmanager}/bin/nmcli radio wifi off
        sleep 1
        ${pkgs.networkmanager}/bin/nmcli radio wifi on
      '';
    };
  };

  # Regulatory database for the WiFi card.
  hardware.wirelessRegulatoryDatabase = true;

  services.tor = {
    enable = true;
    client.enable = true;
  };

  programs.wireshark = {
    enable = true;
    package = pkgs.wireshark; # Qt GUI
  };
}
