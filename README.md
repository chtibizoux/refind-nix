# rEFInd NixOS Module

This flake provides a NixOS module for easily configuring and installing the rEFInd boot manager.

## Features

- Easy installation and configuration of rEFInd
- Support for themes
- Automatic detection of other operating systems
- Configurable timeout and default boot entry
- Optional NVRAM registration

## Usage

1. Add this flake to your system's `flake.nix`:

```nix
{
  inputs.refind-nix = {
    url = "github:chtibizoux/refind-nix";
  };

  outputs = { self, nixpkgs, refind-nix, ... }@inputs: {
    nixosConfigurations.your-hostname = nixpkgs.lib.nixosSystem {
      modules = [
        refind-nix.nixosModules.default
        # ... other modules
      ];
    };
  };
}
```

2. Enable and configure rEFInd in your `configuration.nix`:

```nix
# Little example
{ config, ... }:

{
  boot.loader.refind = {
    enable = true;

    # By default this flake don't handle the configuration of rEFInd file `refind.conf` unless you set `config` option.
    config = {
      timeout = 30;
      defaultSelection = 1;
      resolution = "1920 1080";
      useGraphicsFor = "linux";
    };
  };
}
```

## Configuration Options

- **`config`**:
  All rEFInd options can be configured here using `camelCase` keys (see the [rEFInd documentation](https://www.rodsbooks.com/refind/configfile.html) for details).
  An additional option, `manageNixOSEntries`, can be used to add NixOS-specific boot entries to the rEFInd configuration. This can replace or supplement rEFInd’s usual kernel auto-detection, allowing fine-grained control over the boot menu and disabling kernel scanning if desired.

  The `include` option has been replaced by `theme`, which copies the theme into `/boot/EFI/refind/themes` and adds:

  ```
  include "themes/<theme-name>/theme.conf"
  ```

  The `icons_dir` option has been replaced by `extraIcons`, which copies the icons into `/boot/EFI/refind/extra-icons` and sets:

  ```
  icons_dir extra-icons
  ```

  The options `banner`, `selectionBig`, `selectionSmall`, and `font` now copy their files into `/boot/EFI/refind/assets` before setting the corresponding configuration option to point to that location.

- **`signWithLocalKeys`**:
  Whether to sign the rEFInd binaries and Linux kernels using local Machine Owner Keys (MOK) during installation.
  If enabled, rEFInd will be signed with keys located in `/etc/refind.d/keys` (`refind_local.key`, `refind_local.crt`, and `refind_local.cer`).
  Useful for Secure Boot setups using shim or custom platform keys, enabling kernel signing without reenrollment on every update.

- **`installDrivers`**:
  Specifies which rEFInd drivers to install:

  - `"all"`: installs all available drivers (recommended for removable drives).
  - `"boot"`: installs only drivers essential for booting the system (default for non-removable installs).
  - `"none"`: installs no drivers.
    This controls the amount of driver support bundled with rEFInd for file system or hardware access.

- **`installation`**:
  Controls whether and how rEFInd is installed on the EFI System Partition (ESP).

  - `true`: install and update rEFInd normally.
  - `false`: do not install rEFInd (useful if managed by another OS or manually).
  - `string`: path to a PreLoader or shim EFI binary, enabling Secure Boot support with key management.
    Shim supports local keys and automatic kernel signing, while PreLoader requires kernel reenrollment on updates.

- **`package`**:
  Specifies the rEFInd package from Nixpkgs to use for installation. By default, it uses the standard `refind` package from Nixpkgs.

- **`maxGenerations`**:
  Maximum number of NixOS generations to show in the rEFInd boot menu.
  Useful to limit the number of boot entries and prevent the boot partition from filling up.
  Set to `null` for no limit (default).

- **`generateLinuxConf`**:
  Whether to generate the `refind_linux.conf` file next to the Linux kernel(s).
  This file contains kernel options and is used by rEFInd for booting Linux kernels without separate loader stanzas.
  Defaults to `true`.

- **`efiInstallAsRemovable`**:
  Whether to install the rEFInd EFI files as removable media (using the `--usedefault` flag of `refind-install`).
  Useful on systems where EFI variables cannot be modified or when installing rEFInd on USB drives or other removable devices.
  Defaults to true if EFI variables are not writable.

* **`tools`**:
  A set of additional EFI tool files to be copied into `/boot/tools`.
  Each attribute key is the destination filename under `/boot/tools`, and the corresponding attribute value is the path to the source file.
  These tools become available in the rEFInd tools menu bar for quick access.
  Example:

  ```nix
  { "memtest86.efi" = "${pkgs.memtest86-efi}/BOOTX64.efi"; }
  ```

## To fix glitches and unremovable tools that are due to the GNU efi build :

```nix
{ pkgs, lib, ... }:

{
  boot.loader.refind.package = pkgs.refind.overrideAttrs (oldAttrs: {
    src = pkgs.fetchurl {
      url = "mirror://sourceforge/refind/0.14.2/refind-bin-0.14.2.zip";
      hash = "sha256-QQx4KMT+wvIXm9lWBzUiQVgx0nwAQWOBuPcRU8GQoxE=";
    };

    patches = [ ];

    nativeBuildInputs = [
      pkgs.unzip
      pkgs.makeWrapper
    ];

    buildPhase = "true";

    installPhase = lib.replaceString "install -D -m0644 drivers_" "install -D -m0644 refind/drivers_" (
      lib.replaceString "install -D -m0644 gptsync/gptsync_" "install -D -m0644 refind/tools_x64/gptsync_"
        (
          lib.replaceString "install -D -m0644 refind.conf-sample"
            "install -D -m0644 refind/refind.conf-sample"
            (
              lib.replaceString "\ninstall -D -m0644 BUILDING.txt $out/share/refind/docs/BUILDING.txt" "" (
                lib.replaceString "install -D -m0644 icons/*.png" "install -D -m0644 refind/icons/*.png" (
                  lib.replaceString "\n# images\ninstall -D -m0644 images/*.{png,bmp} $out/share/refind/images/\n" ""
                    oldAttrs.installPhase
                )
              )
            )
        )
    );
  });
}
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

This project was inspired by the work of [RossComputerGuy](https://github.com/RossComputerGuy/nixpkgs/tree/feat/refind/nixos/modules/system/boot/loader/refind) and [betaboon](https://gist.github.com/betaboon/97abed457de8be43f89e7ca49d33d58d).
