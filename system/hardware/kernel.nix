{ config, pkgs, lib, systemSettings, ... }:

{
  boot.kernelPackages = systemSettings.kernelPackages;
  boot.consoleLogLevel = 0;

  # Kernel 7.2 split the AMD 800-series chipset xHCI (1022:43fc/43fd, "Promontory 21")
  # out of xhci_pci into its own driver. nixos-generate-config can't detect it while
  # running an older kernel, so without this the chipset USB ports are dead in the
  # initrd — no keyboard at the LUKS passphrase prompt (DESK_A, gen 14).
  # The module doesn't exist before 7.2, hence the version gate.
  boot.initrd.availableKernelModules =
    lib.optionals (lib.versionAtLeast config.boot.kernelPackages.kernel.version "7.2")
      [ "xhci_pci_prom21" ];
}
