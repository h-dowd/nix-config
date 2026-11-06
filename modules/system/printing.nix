{
  config,
  pkgs,
  lib,
  ...
}:

{
  services.printing = {
    enable = true;
    drivers = with pkgs; [
      gutenprint
      gutenprintBin
      hplip
      # The Brother MFC-L3740CDW prints driverless (IPP Everywhere, via
      # cups-filters); brlaser is the open-source fallback.
      cups-filters
      brlaser
    ];
  };

  # Driverless discovery over mDNS. With avahi (networking.nix) this is often
  # enough for a modern Brother — check `lpinfo -v` before installing drivers.
  services.printing.browsing = true;
  services.printing.browsedConf = ''
    BrowseDNSSDSubTypes _cups,_print
    BrowseLocalProtocols all
    BrowseRemoteProtocols dnssd cups
    CreateIPPPrinterQueues All
  '';

  # Scanning — hplip and Brother MFCs both need SANE.
  hardware.sane = {
    enable = true;
    extraBackends = with pkgs; [ hplipWithPlugin ];
  };
  users.users.henry.extraGroups = [
    "scanner"
    "lp"
  ];
}
