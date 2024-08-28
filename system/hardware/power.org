
I have a server working on a laptop with Intel Adapter that use iwlwifi driver.
The issue was that when closing the lid (display) the wifi stopped working.
So I had to add an additional option.
All info below.


Certainly! Let's break down the concepts you're asking about:

### 1. **`boot.extraModprobeConfig` in NixOS**

In NixOS, `boot.extraModprobeConfig` is a configuration option within the `configuration.nix` file. It allows you to pass specific settings to kernel modules when they are loaded. These settings are written into a modprobe configuration file, which is processed by the kernel to apply the specified options to the relevant modules.

- **`modprobe`**: `modprobe` is a Linux command used to add or remove kernel modules (drivers) dynamically. Modules can be configured with options that adjust their behavior.

- **`extraModprobeConfig`**: This option lets you specify additional configuration lines that should be added to the modprobe configuration files. These configurations are typically stored in `/etc/modprobe.d/` or `/run/current-system/kernel-modules/lib/modules/$(uname -r)/modprobe.d/` in NixOS.

#### Example

```nix
boot.extraModprobeConfig = ''
  options iwlwifi power_save=0
'';
```

In this example:
- **`options iwlwifi power_save=0`**: This line configures the `iwlwifi` kernel module to disable power-saving mode (`power_save=0`).

This setup is particularly useful for setting parameters that the module should use when it is loaded, and it ensures that these options are applied every time the system boots up.

### 2. **What is `iwlwifi`?**

`iwlwifi` is a kernel module (driver) used in Linux to manage Intel wireless network interfaces (Wi-Fi cards). If your laptop or computer uses an Intel Wi-Fi chip, the `iwlwifi` module is the driver responsible for enabling and controlling that hardware.

- **Intel Wi-Fi Chipsets**: Intel produces various Wi-Fi chipsets that are commonly found in laptops. The `iwlwifi` driver provides the necessary functionality to use these chipsets for connecting to wireless networks.

- **Loading the Driver**: When your system boots and detects an Intel Wi-Fi chipset, it loads the `iwlwifi` driver to manage that hardware. The driver then interacts with the Wi-Fi card to allow your system to connect to wireless networks.

### 3. **What Does `power_save=0` Do?**

The `power_save` option is a parameter specific to the `iwlwifi` driver, and it controls the power management behavior of the Wi-Fi card:

- **`power_save=0`**: This disables power-saving features for the Wi-Fi card. Disabling power saving can prevent the Wi-Fi connection from dropping or becoming unstable when the system tries to conserve power (such as when closing the laptop lid).

- **Why Disable Power Saving?**: Power saving can sometimes lead to performance issues, especially with network stability. For instance, the Wi-Fi connection might drop or become unreliable if the card enters a low-power state. By setting `power_save=0`, you instruct the Wi-Fi card to remain fully active, avoiding these issues.

### 4. **Summary**

- **`boot.extraModprobeConfig`** in NixOS is used to pass options to kernel modules, configuring them to behave in specific ways when they are loaded.
- **`iwlwifi`** is the Linux kernel module (driver) for Intel Wi-Fi chipsets.
- **`power_save=0`** is a parameter for the `iwlwifi` module that disables power-saving features on Intel Wi-Fi cards, ensuring a stable connection even in situations where the system might otherwise try to save power (like closing the laptop lid).

This approach provides a declarative way to ensure that your Wi-Fi connection remains stable by configuring the system at a low level, in line with NixOS’s philosophy of managing configurations centrally and reproducibly.