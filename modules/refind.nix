{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.boot.loader.refind;
  efi = config.boot.loader.efi;
  refindInstallConfig = pkgs.writeText "refind-install.json" (
    builtins.toJSON {
      refindConfig = cfg.config;

      nixPath = config.nix.package;
      refindPath = cfg.package;

      efiBootMgrPath = pkgs.efibootmgr;
      sbsignPath = pkgs.sbsigntool;
      mokUtilPath = pkgs.mokutil;
      openSSLPath = pkgs.openssl;

      gptFDiskPath = pkgs.gptfdisk;
      coreUtilsPath = pkgs.coreutils;
      gnuGrepPath = pkgs.gnugrep;
      gnuSedPath = pkgs.gnused;
      gnuAwkPath = pkgs.gawk;
      findUtilsPath = pkgs.findutils;
      utilLinuxPath = pkgs.util-linux;
      glibcPath = pkgs.glibc;

      efiMountPoint = efi.efiSysMountPoint;
      luksDevices = config.boot.initrd.luks.devices;

      canTouchEfiVariables = efi.canTouchEfiVariables;
      efiInstallAsRemovable = cfg.efiInstallAsRemovable;

      generateLinuxConf = cfg.generateLinuxConf;
      maxGenerations = cfg.maxGenerations;
      signWithLocalKeys = cfg.signWithLocalKeys;
      installDrivers = cfg.installDrivers;
      installation = cfg.installation;
      tools = cfg.tools;
    }
  );
  types = {
    inherit (lib.types)
      bool
      str
      path
      enum
      nullOr
      listOf
      attrsOf
      attrTag
      either
      oneOf
      submodule
      ;

    positiveInt = lib.types.ints.positive;
    unsignedInt = lib.types.ints.unsigned;
    betweenInt = lib.types.ints.between;

    minInt = min: lib.types.addCheck lib.types.int (x: x >= min);

    pairOfPositiveInts = lib.types.listOf types.positiveInt // {
      check = xs: builtins.length xs == 2;
      name = "pair of positive integers";
    };

    uniqueEnumList =
      allowedValues:
      (lib.types.listOf (lib.types.enum allowedValues))
      // {
        check = xs: lib.lists.unique xs == xs;
        name = "list of unique enum values";
      };
  };
in
{
  options = {
    boot.loader.refind = {
      enable = lib.mkEnableOption "the rEFInd boot loader";
      config = lib.mkOption {
        type = types.nullOr (
          types.submodule {
            options = {
              timeout = lib.mkOption {
                type = types.minInt (-1);
                default = if config.boot.loader.timeout != null then config.boot.loader.timeout else 20;
                defaultText = lib.literalExpression "config.boot.loader.timeout";
                example = 30;
                description = ''
                  Timeout in seconds for the main menu screen.

                  Setting the timeout to 0 disables automatic booting.
                  Setting it to -1 causes an immediate boot to the default OS unless
                  a keypress is in the buffer when rEFInd launches, in which case that
                  keypress is interpreted as a shortcut key. If no matching shortcut
                  is found, rEFInd displays its menu with no timeout.
                '';
              };

              logLevel = lib.mkOption {
                type = types.nullOr (types.betweenInt 0 4);
                default = null;
                example = 1;
                description = ''
                  Set the logging level.

                  When set to 0, rEFInd does not log its actions.
                  When set to 1 or above, rEFInd creates a file called `refind.log` in
                  its home directory on the ESP and records its actions.
                  Higher values record more information, up to a maximum of 4.

                  This option should be left at the default of 0 except when debugging problems.

                  Default is 0.
                '';
              };

              shutdownAfterTimeout = lib.mkOption {
                type = types.nullOr types.bool;
                default = null;
                example = true;
                description = ''
                  Normally, when the timeout period has passed, rEFInd boots the
                  defaultSelection. If the following option is uncommented, though,
                  rEFInd will instead attempt to shut down the computer.

                  CAUTION: MANY COMPUTERS WILL INSTEAD HANG OR REBOOT! Macs and more
                  recent UEFI-based PCs are most likely to work with this feature.

                  Default is false.
                '';
              };

              useNvram = lib.mkOption {
                type = types.nullOr types.bool;
                default = if !efi.canTouchEfiVariables then false else null;
                defaultText = lib.literalExpression "!config.boot.loader.efi.canTouchEfiVariables";
                example = false;
                description = ''
                  Whether to store rEFInd's rEFInd-specific variables in NVRAM or in files in the "vars" subdirectory of rEFInd's directory on disk.

                  Using NVRAM works well with most computers; however, it increases wear on the motherboard's NVRAM, and if the EFI is buggy or the NVRAM is old and worn out, it may not work at all.
                  Storing variables on disk is a viable alternative in such cases, or if you want to minimize wear and tear on the NVRAM; however, it won't work if rEFInd is stored on a filesystem that's read-only to the EFI (such as an HFS+ volume), and it increases the risk of filesystem damage.

                  Note that this option affects ONLY rEFInd's own variables, such as the PreviousBoot, HiddenTags, HiddenTools, and HiddenLegacy variables. It does NOT affect Secure Boot or other non-rEFInd variables.

                  Default is true.
                '';
              };

              screensaver = lib.mkOption {
                type = types.nullOr (types.minInt (-1));
                default = null;
                example = 300;
                description = ''
                  Screen saver timeout; the screen blanks after the specified number of seconds with no keyboard input.
                  The screen returns after most keypresses (unfortunately, not including modifier keys such as Shift, Control, Alt, or Option).
                  Setting a value of "-1" causes rEFInd to start up with its screen saver active. The default is 0, which disables the screen saver.

                  Default is 0.
                '';
              };

              hideui = lib.mkOption {
                type = types.nullOr (
                  types.either (types.uniqueEnumList [
                    "banner"
                    "label"
                    "singleuser"
                    "safemode"
                    "hwtest"
                    "arrows"
                    "hints"
                    "editor"
                    "badges"
                  ]) (lib.types.enum [ "all" ])
                );
                default = null;
                example = [ "singleuser" ];
                description = ''
                  Hide user interface elements for personal preference or to increase security:
                    banner      - the rEFInd title banner (built-in or loaded via "banner")
                    label       - boot option text label in the menu
                    singleuser  - remove the submenu options to boot macOS in single-user or verbose modes; affects ONLY macOS
                    safemode    - remove the submenu option to boot macOS in "safe mode"
                    hwtest      - the submenu option to run Apple's hardware test
                    arrows      - scroll arrows on the OS selection tag line
                    hints       - brief command summary in the menu
                    editor      - the options editor (+, F2, or Insert on boot options menu)
                    badges      - device-type badges for boot options
                    all         - all of the above

                  Default is none of these (all elements active)
                '';
              };

              extraIcons = lib.mkOption {
                default = { };
                type = types.attrsOf types.path;
                example = lib.literalExpression ''
                  { "os_nixos.png" = ../icons/os_nixos.png; }
                '';
                description = ''
                  A set of files to be copied to `/boot/refind/extra-icons`. Each attribute name denotes the
                  destination file name in `/boot/refind/extra-icons`, while the corresponding attribute value
                  specifies the source file.

                  If extraIcons is set, the rEFInd config `icons_dir` option is set to `extra-icons`.
                '';
              };

              banner = lib.mkOption {
                type = types.nullOr types.path;
                default = null;
                example = "hostname.bmp";
                description = ''
                  Use a custom title banner instead of the rEFInd icon and name.
                  The file path is relative to the directory where refind.efi is located.
                  The color in the top left corner of the image is used as the background color for the menu screens. Currently uncompressed BMP images with color depths of 24, 8, 4 or 1 bits are supported, as well as PNG and JPEG images. (ICNS images can also be used, but ICNS has limitations that make it a poor choice for this purpose.) PNG and JPEG support is limited by the underlying libraries; some files, like progressive JPEGs, will not work.
                '';
              };

              bannerScale = lib.mkOption {
                type = types.nullOr (
                  types.enum [
                    "noscale"
                    "fillscreen"
                  ]
                );
                default = null;
                example = "fillscreen";
                description = ''
                  Specify how to handle banners that aren't exactly the same as the screen size:
                    noscale     - Crop if too big, show with border if too small
                    fillscreen  - Fill the screen

                  Default is noscale.
                '';
              };

              bigIconSize = lib.mkOption {
                type = types.nullOr (types.minInt 32);
                default = null;
                example = 256;
                description = ''
                  All icons are square, so just one value is specified.
                  The big icons are used for OS selectors in the first row.
                  Drive-type badges are 1/4 the size of the big icons.
                  If the icon files do not hold icons of the proper size, the icons are scaled to the specified size.

                  Default is 128.
                '';
              };

              smallIconSize = lib.mkOption {
                type = types.nullOr (types.minInt 32);
                default = null;
                example = 96;
                description = ''
                  All icons are square, so just one value is specified.
                  The small icons are used for tools on the second row.
                  If the icon files do not hold icons of the proper size, the icons are scaled to the specified size.

                  Default is 48.
                '';
              };

              selectionBig = lib.mkOption {
                type = types.nullOr types.path;
                default = null;
                example = lib.literalExpression "../assets/selection-big.png";
                description = ''
                  Custom image for the selection background of for the OS icons (144 x 144).
                  If only a big one is given, the built-in default will be used for the small icons.
                  If an image other than the optimal size is specified, it will be scaled in a way that may be ugly.

                  Like the banner option above, these options take a filename of an uncompressed BMP, PNG, JPEG, or ICNS image file with a color depth of 24, 8, 4, or 1 bits. The PNG or ICNS format is required if you need transparency support (to let you "see through" to a full-screen banner).
                '';
              };

              selectionSmall = lib.mkOption {
                type = types.nullOr types.path;
                default = null;
                example = lib.literalExpression "../assets/selection-small.png";
                description = ''
                  Custom image for the selection background of for the function icons in the second row (64 x 64).
                  If only a small image is given, that one is also used for the big icons by stretching it in the middle.
                  If an image other than the optimal size is specified, it will be scaled in a way that may be ugly.

                  Like the banner option above, these options take a filename of an uncompressed BMP, PNG, JPEG, or ICNS image file with a color depth of 24, 8, 4, or 1 bits. The PNG or ICNS format is required if you need transparency support (to let you "see through" to a full-screen banner).
                '';
              };

              font = lib.mkOption {
                type = types.nullOr types.path;
                default = null;
                example = lib.literalExpression "../assets/myfont.png";
                description = ''
                  Set the font to be used for all textual displays in graphics mode.
                  For best results, the font must be a PNG file with alpha channel transparency.
                  It must contain ASCII characters 32-126 (space through tilde), inclusive, plus a glyph to be displayed in place of characters outside of this range, for a total of 96 glyphs. Only monospaced fonts are supported. Fonts may be of any size, although large fonts can produce display irregularities.

                  The default is rEFInd's built-in font, Luxi Mono Regular 12 point.
                '';
              };

              textonly = lib.mkOption {
                type = types.nullOr types.bool;
                default = null;
                example = true;
                description = ''
                  Use text mode only. When enabled, this option forces rEFInd into text mode.

                  Default is false.
                '';
              };

              textmode = lib.mkOption {
                type = types.nullOr (types.minInt 0);
                default = null;
                example = 2;
                description = ''
                  Set the EFI text mode to be used for textual displays.
                  This option takes a single digit that refers to a mode number.
                  Mode 0 is normally 80x25, 1 is sometimes 80x50, and higher numbers are system-specific modes.
                  Mode 1024 is a special code that tells rEFInd to not set the text mode; it uses whatever was in use when the program was launched.
                  If you specify an invalid mode, rEFInd pauses during boot to inform you of valid modes.

                  CAUTION: On VirtualBox, and perhaps on some real computers, specifying a text mode and uncommenting the "textonly" option while NOT specifying a resolution can result in an unusable display in the booted OS.

                  Default is 1024 (no change).
                '';
              };

              resolution = lib.mkOption {
                type = types.nullOr (
                  types.oneOf [
                    (lib.types.enum [ "max" ])
                    types.positiveInt
                    types.pairOfPositiveInts
                  ]
                );
                default = null;
                example = [
                  1024
                  768
                ];
                description = ''
                  Set the screen's video resolution. Pass this option one of the following:
                    * two integer values, corresponding to the X and Y resolutions
                    * one integer value, corresponding to a GOP (UEFI) video mode
                    * the string "max", which sets the maximum available resolution
                  Note that not all resolutions are supported.
                  On UEFI systems, passing an incorrect value results in a message being shown on the screen to that effect, along with a list of supported modes.
                  On EFI 1.x systems (e.g., Macintoshes), setting an incorrect mode silently fails.
                  On both types of systems, setting an incorrect resolution results in the default resolution being used.
                  A resolution of 1024x768 usually works, but higher values often don't.
                '';
              };

              enableTouch = lib.mkOption {
                type = types.nullOr types.bool;
                default = null;
                example = true;
                description = ''
                  Enable touch screen support.
                  If active, this feature enables use of touch screen controls (as on tablets).
                  Note, however, that not all tablets' EFIs provide the necessary underlying support, so this feature may not work for you.
                  If it does work, you should be able to launch an OS or tool by touching it.
                  In a submenu, touching anywhere launches the currently-selection item; there is, at present, no way to select a specific submenu item.
                  This feature is mutually exclusive with the enableMouse feature.
                  If both are uncommented, the one read most recently takes precedence.

                  Default is false.
                '';
              };

              enableMouse = lib.mkOption {
                type = types.nullOr types.bool;
                default = null;
                example = true;
                description = ''
                  Enable mouse support.
                  If active, this feature enables use of the computer's mouse.
                  Note, however, that not all computers' EFIs provide the necessary underlying support, so this feature may not work for you.
                  If it does work, you should be able to launch an OS or tool by clicking it with the mouse pointer.
                  This feature is mutually exclusive with the enableTouch feature.
                  If both are uncommented, the one read most recently takes precedence.

                  Default is false.
                '';
              };

              mouseSize = lib.mkOption {
                type = types.nullOr types.positiveInt;
                default = null;
                example = 32;
                description = ''
                  Size of the mouse pointer, in pixels, per side.

                  Default is 16.
                '';
              };

              mouseSpeed = lib.mkOption {
                type = types.nullOr (types.betweenInt 1 32);
                default = null;
                example = 8;
                description = ''
                  Speed of mouse tracking. Higher numbers equate to faster mouse movement.
                  This option requires that enableMouse be uncommented.

                  Default is 4.
                '';
              };

              useGraphicsFor = lib.mkOption {
                type = types.nullOr (
                  types.uniqueEnumList [
                    "osx"
                    "linux"
                    "elilo"
                    "grub"
                    "windows"
                  ]
                );
                default = null;
                example = [
                  "osx"
                  "linux"
                ];
                description = ''
                  Launch specified OSes in graphics mode.
                  By default, rEFInd switches to text mode and displays basic pre-launch information when launching all OSes except macOS.
                  Using graphics mode can produce a more seamless transition, but displays no information, which can make matters difficult if you must debug a problem.
                  Also, on at least one known computer, using graphics mode prevents a crash when using the Linux kernel's EFI stub loader.
                  You can specify an empty list to boot all OSes in text mode.
                  Valid options:
                    osx     - macOS
                    linux   - A Linux kernel with EFI stub loader
                    elilo   - The ELILO boot loader
                    grub    - The GRUB (Legacy or 2) boot loader
                    windows - Microsoft Windows

                  Default is osx.
                '';
              };

              showtools = lib.mkOption {
                type = types.nullOr (
                  types.uniqueEnumList [
                    "shell"
                    "memtest"
                    "gptsync"
                    "gdisk"
                    "apple_recovery"
                    "windows_recovery"
                    "mok_tool"
                    "csr_rotate"
                    "install"
                    "bootorder"
                    "about"
                    "hidden_tags"
                    "exit"
                    "shutdown"
                    "reboot"
                    "firmware"
                    "fwupdate"
                    "netboot"
                  ]
                );
                default = null;
                example = [
                  "shell"
                  "memtest"
                ];
                description = ''
                  Which non-bootloader tools to show on the tools line, and in what
                  order to display them:
                    shell            - the EFI shell (requires external program; see rEFInd documentation for details)
                    memtest          - the memtest86 program, in EFI/tools, EFI/memtest86, EFI/memtest, EFI/tools/memtest86, EFI/tools/memtest, or a boot loader's directory
                    gptsync          - the (dangerous) gptsync.efi utility (requires external program; see rEFInd documentation for details)
                    gdisk            - the gdisk partitioning program
                    apple_recovery   - boots the Apple Recovery HD partition, if present
                    windows_recovery - boots an OEM Windows recovery tool, if present (see also the windows_recovery_files option)
                    mok_tool         - makes available the Machine Owner Key (MOK) maintenance tool, MokManager.efi, used on Secure Boot systems
                    csr_rotate       - adjusts Apple System Integrity Protection (SIP) policy. Requires "csr_values" to be set.
                    install          - an option to install rEFInd from the current location to another ESP
                    bootorder        - adjust the EFI's (NOT rEFInd's) boot order
                    about            - an "about this program" option
                    hidden_tags      - manage hidden tags
                    exit             - a tag to exit from rEFInd
                    shutdown         - shuts down the computer (a bug causes this to reboot many UEFI systems)
                    reboot           - a tag to reboot the computer
                    firmware         - a tag to reboot the computer into the firmware's user interface (ignored on older computers)
                    fwupdate         - a tag to update the firmware; launches the fwupx64.efi (or similar) program
                    netboot          - launch the ipxe.efi tool for network (PXE) booting
                  Default is shell, memtest, gptsync, gdisk, apple_recovery, windows_recovery, mok_tool, about, hidden_tags, shutdown, reboot, firmware, fwupdate.
                '';
              };

              alsoScanToolDirs = lib.mkOption {
                type = types.nullOr (types.listOf types.str);
                default = null;
                example = [
                  "EFI/memtest"
                  "ESP2:/EFI/tools/memtest86"
                ];
                description = ''
                  Additional directories to scan for tools
                  You may specify a directory alone or a volume identifier plus pathname.

                  The default is to scan no extra directories, beyond EFI/tools and any directory in which an EFI loader is found.
                '';
              };

              dontScanTools = lib.mkOption {
                type = types.nullOr (types.listOf types.str);
                default = null;
                example = [
                  "ESP2:/EFI/ubuntu/mmx64.efi"
                  "gptsync_x64.efi"
                ];
                description = ''
                  Tool binaries to be excluded from the tools line, even if the general class is specified in showtools.
                  This enables trimming an overabundance of tools, as when you see multiple mok_tool entries after installing multiple Linux distributions.
                  Just as with dont_scan_files, you can specify a filename alone, a full pathname, or a volume identifier (filesystem label, partition name, or partition GUID) and a full pathname.
                '';
              };

              windowsRecoveryFiles = lib.mkOption {
                type = types.nullOr (types.listOf types.str);
                default = null;
                example = [ "LRS_ESP:/EFI/Microsoft/Boot/LrsBootmgr.efi" ];
                description = ''
                  Boot loaders that can launch a Windows restore or emergency system.
                  These tend to be OEM-specific.
                  Default is "LRS_ESP:/EFI/Microsoft/Boot/LrsBootmgr.efi".
                '';
              };

              scanDriverDirs = lib.mkOption {
                type = types.nullOr (types.listOf types.str);
                default = null;
                example = [
                  "EFI/tools/drivers"
                  "drivers"
                ];
                description = ''
                  Directories in which to search for EFI drivers.
                  These drivers can provide filesystem support, give access to hard disks on plug-in controllers, etc.
                  In most cases none are needed, but if you add EFI drivers and you want rEFInd to automatically load them, you should specify one or more paths here.
                  rEFInd always scans the "drivers" and "drivers_{arch}" subdirectories of its own installation directory (where "{arch}" is your architecture code); this option specifies ADDITIONAL directories to scan.
                '';
              };

              scanfor = lib.mkOption {
                type = types.nullOr (
                  types.uniqueEnumList [
                    "internal"
                    "external"
                    "optical"
                    "netboot"
                    "hdbios"
                    "biosexternal"
                    "cd"
                    "manual"
                    "firmware"
                  ]
                );
                default = null;
                example = [
                  "internal"
                  "external"
                  "optical"
                  "manual"
                  "firmware"
                ];
                description = ''
                  Which types of boot loaders to search, and in what order to display them:
                    internal      - internal EFI disk-based boot loaders
                    external      - external EFI disk-based boot loaders
                    optical       - EFI optical discs (CD, DVD, etc.)
                    netboot       - EFI network (PXE) boot options
                    hdbios        - BIOS disk-based boot loaders
                    biosexternal  - BIOS external boot loaders (USB, eSATA, etc.)
                    cd            - BIOS optical-disc boot loaders
                    manual        - use stanzas later in this configuration file
                    firmware      - boot EFI programs set in the firmware's NVRAM
                  Note that the legacy BIOS options require firmware support, which is
                  not present on all computers.
                  The netboot option is experimental and relies on the ipxe.efi and ipxe_discover.efi program files.

                  On UEFI PCs, default is internal,external,optical,manual
                  On Macs, default is internal,hdbios,external,biosexternal,optical,cd,manual
                '';
              };

              uefiDeepLegacyScan = lib.mkOption {
                type = types.nullOr types.bool;
                default = null;
                example = true;
                description = ''
                  By default, rEFInd relies on the UEFI firmware to detect BIOS-mode boot devices.
                  This sometimes doesn't detect all the available devices, though.
                  For these cases, uefi_deep_legacy_scan results in a forced scan and modification of NVRAM variables on each boot.
                  This token has no effect on Macs or when no BIOS-mode options are set via scanfor.
                '';
              };

              scanDelay = lib.mkOption {
                type = types.nullOr types.unsignedInt;
                default = null;
                example = 5;
                description = ''
                  Delay for the specified number of seconds before scanning disks.
                  This can help some users who find that some of their disks (usually external or optical discs) aren't detected initially, but are detected after pressing Esc.

                  Default is 0.
                '';
              };

              alsoScanDirs = lib.mkOption {
                type = types.nullOr (types.listOf types.str);
                default = null;
                example = [
                  "boot"
                  "ESP2:EFI/linux/kernels"
                  "@/boot"
                  "+"
                  "@/kernels"
                ];
                description = ''
                  When scanning volumes for EFI boot loaders, rEFInd always looks for macOS's and Microsoft Windows' boot loaders in their normal locations, and scans the root directory and every subdirectory of the /EFI directory for additional boot loaders, but it doesn't recurse into these directories.
                  The also_scan_dirs token adds more directories to the scan list.
                  Directories are specified relative to the volume's root directory. This option applies to ALL the volumes that rEFInd scans UNLESS you include a volume name and colon before the directory name, as in "myvol:/somedir" to scan the somedir directory only on the filesystem named myvol. If a specified directory doesn't exist, it's ignored (no error condition results). The "+" symbol denotes appending to the list of scanned directories rather than overwriting that list.
                  The default is to scan the "boot" and "@/boot" directories in addition to various hard-coded directories.
                '';
              };

              dontScanVolumes = lib.mkOption {
                type = types.nullOr (types.listOf types.str);
                default = null;
                example = [ "Recovery HD" ];
                description = ''
                  Partitions (or whole disks, for legacy-mode boots) to omit from scans.
                  For EFI-mode scans, you normally specify a volume by its label, which you can obtain in an EFI shell by typing "vol", from Linux by typing "blkid /dev/{devicename}", or by examining the disk's label in various OSes' file browsers.
                  It's also possible to identify a partition by its unique GUID (aka its "PARTUUID" in Linux parlance).
                  (Note that this is NOT the partition TYPE CODE GUID.)
                  This identifier can be obtained via "blkid" in Linux or "diskutil info {partition-id}" in macOS.
                  For legacy-mode scans, you can specify any subset of the boot loader description shown when you highlight the option in rEFInd.

                  The default is "LRS_ESP".
                '';
              };

              dontScanDirs = lib.mkOption {
                type = types.nullOr (types.listOf types.str);
                default = null;
                example = [
                  "ESP:/EFI/boot"
                  "EFI/Dell"
                  "EFI/memtest86"
                ];
                description = ''
                  Directories that should NOT be scanned for boot loaders.
                  By default, rEFInd doesn't scan its own directory, the `EFI/tools` directory, the `EFI/memtest` directory, the `EFI/memtest86` directory, or the `com.apple.recovery.boot` directory.
                  Using the dont_scan_dirs option enables you to "blacklist" other directories; but be sure to use "+" as the first element if you want to continue blacklisting existing directories.
                  You might use this token to keep EFI/boot/bootx64.efi out of the menu if that's a duplicate of another boot loader or to exclude a directory that holds drivers or non-bootloader utilities provided by a hardware manufacturer.
                  If a directory is listed both here and in also_scan_dirs, dont_scan_dirs takes precedence.
                  Note that this blacklist applies to ALL the filesystems that rEFInd scans, not just the ESP, unless you precede the directory name by a filesystem name or partition unique GUID, as in "myvol:EFI/somedir" to exclude EFI/somedir from the scan on the myvol volume but not on other volumes.
                '';
              };

              dontScanFiles = lib.mkOption {
                type = types.nullOr (types.listOf types.str);
                default = null;
                example = [
                  "shim.efi"
                  "MokManager.efi"
                ];
                description = ''
                  Files that should NOT be included as EFI boot loaders (on the first line of the display).
                  If you're using a boot loader that relies on support programs or drivers that are installed alongside the main binary or if you want to "blacklist" certain loaders by name rather than location, use this option.
                  Note that this will NOT prevent certain binaries from showing up in the second-row set of tools.
                  Most notably, various Secure Boot and recovery tools are present in this list, but may appear as second-row items.
                  The file may be specified as a bare name (e.g., "notme.efi"), as a complete pathname (e.g., "/EFI/somedir/notme.efi"), or as a complete pathname with volume (e.g., "SOMEDISK:/EFI/somedir/notme.efi" or 2C17D5ED-850D-4F76-BA31-47A561740082:/EFI/somedir/notme.efi").
                  OS tags hidden via the Delete or '-' key in the rEFInd menu are added to this list, but stored in NVRAM.
                  The default is shim.efi,shim-fedora.efi,shimx64.efi,PreLoader.efi,TextMode.efi,ebounce.efi,GraphicsConsole.efi,MokManager.efi,HashTool.efi,HashTool-signed.efi,bootmgr.efi,fb{arch}.efi (where "{arch}" is the architecture code, like "x64").
                  If you want to keep these defaults but add to them, be sure to specify "+" as the first item in the new list; if you don't, then items from the default list are likely to appear.
                '';
              };

              dontScanFirmware = lib.mkOption {
                type = types.nullOr (types.listOf types.str);
                default = null;
                example = [
                  "HARDDISK"
                  "shell"
                  "Removable Device"
                ];
                description = ''
                  EFI NVRAM Boot#### variables that should NOT be presented as loaders when "firmware" is an option to "scanfor".
                  The comma-separated list presented here contains strings that are matched against the description field -- if a value here is a case-insensitive substring of the boot option description, then it will be excluded from the boot list.
                  To specify a string that includes a space, enclose it in quotes.
                  Specifying "shell" will counteract the automatic inclusion of built-in EFI shells.
                '';
              };

              scanAllLinuxKernels = lib.mkOption {
                type = types.nullOr types.bool;
                default = null;
                example = false;
                description = ''
                  Scan for Linux kernels that lack a ".efi" filename extension.
                  This is useful for better integration with Linux distributions that provide kernels with EFI stub loaders but that don't give those kernels filenames that end in ".efi", particularly if the kernels are stored on a filesystem that the EFI can read.
                  When set to true, this option causes all files in scanned directories with names that begin with "vmlinuz", "bzImage", or "kernel" to be included as loaders, even if they lack ".efi" extensions.
                  When set to false, this option causes kernels without ".efi" extensions to NOT be scanned.
                  Default is true -- to scan for kernels without ".efi" extensions.
                '';
              };

              supportGzippedLoaders = lib.mkOption {
                type = types.nullOr types.bool;
                default = null;
                example = true;
                description = ''
                  Support loaders that have been compressed with gzip.
                  On x86 and x86-64 platforms, Linux kernels are self-decompressing.
                  On ARM64, Linux kernel files are typically compressed with gzip, including the EFI stub loader. This makes them unloadable in rEFInd unless rEFInd itself uncompresses them. This option enables rEFInd to do this. This feature is unnecessary on x86 and x86-64 systems.

                  Default is "false" on x86 and x86-64; "true" on ARM64.
                '';
              };

              foldLinuxKernels = lib.mkOption {
                type = types.nullOr types.bool;
                default = null;
                example = false;
                description = ''
                  Combine all Linux kernels in a given directory into a single entry.
                  When so set, the kernel with the most recent time stamp will be launched by default, and its filename will appear in the entry's description.
                  To launch other kernels, the user must press F2 or Insert; alternate kernels then appear as options on the sub-menu.

                  Default is true -- kernels are "folded" into a single menu entry.
                '';
              };

              linuxPrefixes = lib.mkOption {
                type = types.nullOr (types.listOf types.str);
                default = null;
                example = [
                  "vmlinuz"
                  "bzImage"
                  "kernel"
                ];
                description = ''
                  Filename prefixes that indicate a file is a Linux kernel. Files that begin with any of these strings are treated as Linux kernels, if they are also EFI boot loaders. To include the default string, use "+".

                  Default is "vmlinuz,bzImage,kernel", except on ARM64, where it is "vmlinuz,Image,kernel".
                '';
              };

              extraKernelVersionStrings = lib.mkOption {
                type = types.nullOr (types.listOf types.str);
                default = null;
                example = [
                  "linux-lts"
                  "linux"
                ];
                description = ''
                  Comma-delimited list of strings to treat as if they were numbers for the purpose of kernel version number detection.
                  These strings are matched on a first-found basis; that is, if you want to treat both "linux-lts" and "linux" as version strings, they MUST be specified as "linux-lts,linux", since if you specify it the other way, both vmlinuz-linux and vmlinuz-linux-lts will return with "linux" as the "version string," which is not what you'd want. Also, if the kernel or initrd file includes both a specified string and digits, the "version string" includes both. For instance, "vmlinuz-linux-4.8" would yield a version string of "linux-4.8".
                  This option is intended for Arch and other distributions that don't include version numbers in their kernel filenames, but may provide other uniquely identifying strings for multiple kernels. If this feature causes problems (say, if your kernel filename includes "linux" but the initrd filename doesn't), be sure this is set to an empty string (extraKernelVersionStrings = "") or comment out the option to disable it.
                '';
              };

              writeSystemdVars = lib.mkOption {
                type = types.nullOr types.bool;
                default = null;
                example = true;
                description = ''
                  Write to systemd EFI variables (currently only LoaderDevicePartUUID) when launching Linux via an EFI stub loader, ELILO, or GRUB. This variable, when present, causes systemd to mount the ESP at /boot or /efi *IF* either directory is empty and nothing else is mounted there.

                  Default is false.
                '';
              };

              followSymlinks = lib.mkOption {
                type = types.nullOr types.bool;
                default = null;
                example = true;
                description = ''
                  Symlinked loaders will be processed when this setting is set to true.
                  These are ignored by default as they may result in undesirable outcomes.
                  This token may, however, be useful on Linux setups that provide symbolic links in scanned locations that point to kernels in unscanned locations, such as some openSUSE installations.

                  Default is false.
                '';
              };

              maxTags = lib.mkOption {
                type = types.nullOr types.unsignedInt;
                default = null;
                example = 10;
                description = ''
                  Set the maximum number of tags that can be displayed on the screen at
                  any time. If more loaders are discovered than this value, rEFInd shows
                  a subset in a scrolling list. If this value is set too high for the
                  screen to handle, it's reduced to the value that the screen can manage.
                  If this value is set to 0 (the default), it's adjusted to the number
                  that the screen can handle.

                  Default is 0.
                '';
              };

              defaultSelection = lib.mkOption {
                type = types.nullOr (
                  types.oneOf [
                    (types.betweenInt 1 9)
                    types.str
                    (types.listOf (types.either (types.betweenInt 1 9) types.str))
                  ]
                );
                default = null;
                example = [
                  1
                  "Microsoft"
                  "\"+,bzImage,vmlinuz\""
                  "Maintenance 23:30 2:30"
                  "\"Maintenance,macOS\" 1:00 2:30"
                ];
                description = ''
                  Set the default menu selection.  The available arguments match the keyboard accelerators available within rEFInd.
                  You may select the default loader using:
                    - A digit between 1 and 9, in which case the Nth loader in the menu will be the default.
                    - A "+" symbol at the start of the string, which refers to the most recently booted loader.
                    - Any substring that corresponds to a portion of the loader's title (usually the OS's name, boot loader's path, or a volume or filesystem title).
                  You may also specify multiple selectors by separating them with commas and enclosing the list in quotes. (The "+" option is only meaningful in this context.)
                  If you follow the selector(s) with two times, in 24-hour format, the default will apply only between those times. The times are in the motherboard's time standard, whether that's UTC or local time, so if you use UTC, you'll need to adjust this from local time manually.
                  Times may span midnight as in "23:30 00:30", which applies to 11:30 PM to 12:30 AM. You may specify a list of defaultSelection, in which case the last one to match takes precedence. Thus, you can set a main option without a time followed by one or more that include times to set different defaults for different times of day.

                  The default behavior is to boot the previously-booted OS.
                '';
              };

              enableAndLockVmx = lib.mkOption {
                type = types.nullOr types.bool;
                default = null;
                example = true;
                description = ''
                  Enable VMX bit and lock the CPU MSR if unlocked.
                  On some Intel Apple computers, the firmware does not lock the MSR 0x3A.
                  The symptom on Windows is Hyper-V not working even if the CPU meets the minimum requirements (HW assisted virtualization and SLAT)
                  DO NOT SET THIS EXCEPT ON INTEL CPUs THAT SUPPORT VMX! See http://www.thomas-krenn.com/en/wiki/Activating_the_Intel_VT_Virtualization_Feature for more on this subject.

                  The default is false: Don't try to enable and lock the MSR.
                '';
              };

              spoofOsxVersion = lib.mkOption {
                type = types.nullOr types.str;
                default = null;
                example = "10.9";
                description = ''
                  Tell a Mac's EFI that macOS is about to be launched, even when it's not.
                  This option causes some Macs to initialize their hardware differently than when a third-party OS is launched normally.
                  In some cases (particularly on Macs with multiple video cards), using this option can cause hardware to work that would not otherwise work.
                  On the other hand, using this option when it is not necessary can cause hardware (such as keyboards and mice) to become inaccessible.
                  Therefore, you should not enable this option if your non-Apple OSes work correctly; enable it only if you have problems with some hardware devices.
                  When needed, a value of "10.9" usually works, but you can experiment with other values.
                  This feature has no effect on non-Apple computers.

                  The default is inactive (no macOS spoofing is done).
                '';
              };

              csrValues = lib.mkOption {
                type = types.nullOr types.str;
                default = null;
                example = "10,877";
                description = ''
                  Set the CSR values for Apple's System Integrity Protection (SIP) feature.
                  Values are two-byte (four-character) hexadecimal numbers.
                  These values define which specific security features are enabled.
                  Below are the codes for what the values mean. Add them up (in hexadecimal!) to set new values.
                  Apple's "csrutil enable" and "csrutil disable" commands set values of 10 and 877, respectively. (Prior to OS 11, 77 was used rather than 877; 877 is required for OS 11, and should work for OS X 10.x, too.)
                    CSR_ALLOW_UNTRUSTED_KEXTS            0x0001
                    CSR_ALLOW_UNRESTRICTED_FS            0x0002
                    CSR_ALLOW_TASK_FOR_PID               0x0004
                    CSR_ALLOW_KERNEL_DEBUGGER            0x0008
                    CSR_ALLOW_APPLE_INTERNAL             0x0010
                    CSR_ALLOW_UNRESTRICTED_DTRACE        0x0020
                    CSR_ALLOW_UNRESTRICTED_NVRAM         0x0040
                    CSR_ALLOW_DEVICE_CONFIGURATION       0x0080
                    CSR_ALLOW_ANY_RECOVERY_OS            0x0100
                    CSR_ALLOW_UNAPPROVED_KEXTS           0x0200
                    CSR_ALLOW_EXECUTABLE_POLICY_OVERRIDE 0x0400
                    CSR_ALLOW_UNAUTHENTICATED_ROOT       0x0800  
                '';
              };

              theme = lib.mkOption {
                type = types.nullOr types.path;
                default = null;
                example = lib.literalExpression ''./refind-themes/my-theme'';
                description = ''
                  Copy the theme to `/boot/EFI/refind/themes`.
                  And add `include "themes/<theme-name>/theme.conf"` to `refind.conf`.
                '';
              };

              menuEntries = lib.mkOption {
                type = types.attrsOf (
                  lib.types.submodule {
                    options = {
                      volume = lib.mkOption {
                        type = types.nullOr types.str;
                        default = null;
                        example = "904404F8-B481-440C-A1E3-11A5A954E601";
                        description = ''
                          Sets the volume that's used for subsequent file accesses (by icon and loader, and by implication by initrd if loader follows volume). You pass this token a filesystem's label, a partition's label, or a partition's GUID.
                          A filesystem or partition label is typically displayed under the volume's icon in file managers and rEFInd displays it on its menu at the start of the identifying string for an auto-detected boot loader.
                          If this label isn't unique, the first volume with the specified label is used.
                          The matching is nominally case-insensitive, but on some EFIs it's case-sensitive.
                          If a volume has no label, you can use a partition GUID number. If this option is not set, the volume defaults to the one from which rEFInd launched.
                        '';
                      };

                      loader = lib.mkOption {
                        type = types.nullOr types.str;
                        default = null;
                        example = "bzImage-3.3.0-rc7";
                        description = ''
                          Sets the filename for the boot loader. You may use either Unix-style slashes (/) or Windows/EFI-style backslashes (\) to separate directory elements.
                          In either case, the references are to files on the ESP from which rEFInd launched or to the one identified by a preceding volume token.
                          The filename is specified as a path relative to the root of the filesystem, so if the file is in a directory, you must include its complete path, as in \EFI\myloader\loader.efi.
                          This option should normally be the first in the body of an OS stanza; if it's not, some other options may be ignored. An exception is if you want to boot a loader from a volume other than the one on which rEFInd resides, in which case volume should precede loader.
                        '';
                      };

                      initrd = lib.mkOption {
                        type = types.nullOr types.str;
                        default = null;
                        example = "initrd-3.3.0.img";
                        description = ''
                          Sets the filename for a Linux kernel's initial RAM disk (initrd).
                          This option is useful only when booting a Linux kernel that includes an EFI stub loader, which enables you to boot a kernel without the benefit of a separate boot loader.
                          When booted in this way, though, you must normally pass an initrd filename to the boot loader.
                          You must specify the complete EFI path to the initrd file with this option, as in initrd EFI/linux/initrd-3.8.0.img.
                          You'll also have to use the options line to pass the Linux root filesystem, and perhaps other options (as in options "root=/dev/sda4 ro").
                          The initial RAM disk file must reside on the same volume as the kernel.
                        '';
                      };

                      firmwareBootnum = lib.mkOption {
                        type = types.nullOr types.str;
                        default = null;
                        example = "0001";
                        description = ''
                          Sets the EFI boot loader's boot number to be executed.
                          These numbers appear in the output of Linux's efibootmgr and in rEFInd's own EFI boot order list (when showtools bootorder is activated) as Boot#### values, for instance.
                          When this option is used, most other tokens have no effect. In particular, this option is incompatible with volume, loader, initrd, options, and most other tokens.
                          Exceptions are menuentry, icon, and disabled; these three tokens work with firmwareBootnum.
                        '';
                      };

                      icon = lib.mkOption {
                        type = types.nullOr types.str;
                        default = null;
                        example = "/EFI/refind/icons/os_linux.png";
                        description = ''
                          Sets the filename for an icon for the menu.
                          If you omit this item, a default icon will be used, based on rEFInd's auto-detection algorithms. The filename should be a complete path from the root of the current directory, not relative to the default icons subdirectory or the one set via `iconsDir`.
                        '';
                      };

                      ostype = lib.mkOption {
                        type = types.nullOr types.enum [
                          "MacOS"
                          "Linux"
                          "Windows"
                          "XOM"
                        ];
                        default = null;
                        example = "Linux";
                        description = ''
                          Determines the options that are available on a sub-menu obtained by pressing the Insert key with an OS selected in the main menu.
                          If you omit this option, rEFInd selects options using an auto-detection algorithm.
                        '';
                      };

                      graphics = lib.mkOption {
                        type = types.nullOr types.bool;
                        default = null;
                        example = true;
                        description = ''
                          Set to true to enable graphics-mode boot (useful mainly for MacOS) or false for text-mode boot.
                          Default is auto-detected from loader filename.
                        '';
                      };

                      options = lib.mkOption {
                        type = types.nullOr types.str;
                        default = null;
                        example = "ro root=UUID=5f96cafa-e0a7-4057-b18f-fa709db5b837";
                        description = ''
                          Pass arbitrary options to your boot loader with this line. Note that if the option string should contain spaces (as it often should) or characters that should not be modified by rEFInd's option parser (such as slashes or commas), it must be enclosed in quotes.
                        '';
                      };

                      submenuEntries = lib.mkOption {
                        type = types.attrsOf (
                          lib.types.submodule {
                            loader = lib.mkOption {
                              type = types.nullOr types.str;
                              default = null;
                              example = "bzImage-3.3.0-rc7";
                              description = ''
                                Replace the boot loader file.
                              '';
                            };

                            initrd = lib.mkOption {
                              type = types.nullOr types.str;
                              default = null;
                              example = "initrd-3.3.0.img";
                              description = ''
                                Replace the initial RAM disk file.
                              '';
                            };

                            graphics = lib.mkOption {
                              type = types.nullOr types.bool;
                              default = null;
                              example = true;
                              description = ''
                                Set to true to enable graphics-mode boot (useful mainly for MacOS) or false for text-mode boot. Default is auto-detected from loader filename.
                              '';
                            };

                            options = lib.mkOption {
                              type = types.nullOr types.str;
                              default = null;
                              example = "ro root=UUID=5f96cafa-e0f9-4057-b18f-fa709db5b837";
                              description = ''
                                Replace the options to be passed to the boot loader.
                              '';
                            };

                            addOptions = lib.mkOption {
                              type = types.nullOr types.str;
                              default = null;
                              example = "ro root=UUID=5f96cafa-e0f9-4057-b18f-fa709db5b837";
                              description = ''
                                Add additional options to be passed to the boot loader.
                              '';
                            };

                            enable = lib.mkOption {
                              type = types.bool;
                              default = true;
                              example = false;
                              description = ''
                                Disable this submenu entry by setting this option to false.
                              '';
                            };
                          }
                        );
                      };

                      enable = lib.mkOption {
                        type = types.bool;
                        default = true;
                        example = false;
                        description = ''
                          Disable this menu entry by setting this option to false.
                        '';
                      };
                    };
                  }
                );
                default = { };
                example = {
                  # A sample entry for a Linux 3.13 kernel with EFI boot stub support
                  # on a partition with a GUID of 904404F8-B481-440C-A1E3-11A5A954E601.
                  # This entry includes Linux-specific boot options and specification
                  # of an initial RAM disk. Note uses of Linux-style forward slashes.
                  # Also note that a leading slash is optional in file specifications.
                  "Linux" = {
                    icon = "/EFI/refind/icons/os_linux.png";
                    volume = "904404F8-B481-440C-A1E3-11A5A954E601";
                    loader = "bzImage-3.3.0-rc7";
                    initrd = "initrd-3.3.0.img";
                    options = "ro root=UUID=5f96cafa-e0a7-4057-b18f-fa709db5b837";
                    enable = false;
                  };

                  # Below is a more complex Linux example, specifically for Arch Linux.
                  # This example MUST be modified for your specific installation; if nothing
                  # else, the PARTUUID code must be changed for your disk. Because Arch Linux
                  # does not include version numbers in its kernel and initrd filenames, you
                  # may need to use manual boot stanzas when using fallback initrds or
                  # multiple kernels with Arch. This example is modified from one in the Arch
                  # wiki page on rEFInd (https://wiki.archlinux.org/index.php/rEFInd).
                  "Arch Linux" = {
                    icon = "/EFI/refind/icons/os_arch.png";
                    volume = "Arch Linux";
                    loader = "/boot/vmlinuz-linux";
                    initrd = "/boot/initramfs-linux.img";
                    options = "root=PARTUUID=5028fa50-0079-4c40-b240-abfaf28693ea rw add_efi_memmap";
                    submenuEntries = {
                      "Boot using fallback initramfs" = {
                        initrd = "/boot/initramfs-linux-fallback.img";
                      };
                      "Boot to terminal" = {
                        addOptions = "systemd.unit=multi-user.target";
                      };
                    };
                    enable = false;
                  };
                  # A sample entry for loading Ubuntu using its standard name for
                  # its GRUB 2 boot loader. Note uses of Linux-style forward slashes
                  "Ubuntu" = {
                    loader = "/EFI/ubuntu/grubx64.efi";
                    icon = "/EFI/refind/icons/os_linux.png";
                    enable = false;
                  };

                  # A minimal ELILO entry, which probably offers nothing that
                  # auto-detection can't accomplish.
                  "ELILO" = {
                    loader = "/EFI/elilo/elilo.efi";
                    enable = false;
                  };

                  # Like the ELILO entry, this one offers nothing that auto-detection
                  # can't do; but you might use it if you want to disable auto-detection
                  # but still boot Windows....
                  "Windows 7" = {
                    loader = "/EFI/Microsoft/Boot/bootmgfw.efi";
                    enable = false;
                  };

                  # EFI shells are programs just like boot loaders, and can be
                  # launched in the same way. You can pass a shell the name of a
                  # script that it's to run on the "options" line. The script
                  # could initialize hardware and then launch an OS, or it could
                  # do something entirely different.
                  "Windows via shell script" = {
                    icon = "/EFI/refind/icons/os_win.png";
                    loader = "/EFI/tools/shell.efi";
                    options = "fs0:\\EFI\\tools\\launch_windows.nsh";
                    enable = false;
                  };

                  # MacOS is normally detected and run automatically; however,
                  # if you want to do something unusual, a manual boot stanza may
                  # be the way to do it. This one does nothing very unusual, but
                  # it may serve as a starting point. Note that you'll almost
                  # certainly need to change the "volume" line for this example
                  # to work.
                  "My macOS" = {
                    icon = "/EFI/refind/icons/os_mac.png";
                    volume = "macOS boot";
                    loader = "/System/Library/CoreServices/boot.efi";
                    enable = false;
                  };

                  # The firmware_bootnum token takes a HEXADECIMAL value as an option
                  # and sets that value using the EFI's BootNext variable and then
                  # reboots the computer. This then causes a one-time boot of the
                  # computer using this EFI boot option. It can be used for various
                  # purposes, but one that's likely to interest some rEFInd users is
                  # that some Macs with HiDPI displays produce lower-resolution
                  # desktops when booted through rEFInd than when booted via Apple's
                  # own boot manager. Booting using the firmware_bootnum option
                  # produces the better resolution. Note that no loader option is
                  # used in this type of configuration.
                  "macOS via BootNext" = {
                    icon = "/EFI/refind/icons/os_mac.png";
                    firmwareBootnum = "80";
                    enable = false;
                  };
                };
                description = ''
                  Menu entries to be added to the rEFInd configuration.
                '';
              };

              manageNixOSEntries = lib.mkOption {
                type = types.nullOr (
                  types.enum [
                    "by-generation"
                    "by-profile"
                  ]
                );
                default = null;
                example = "by-generation";
                description = ''
                  Manage NixOS entries with `refind.conf` instead of rely on refind kernel detection and `refind_linux.conf`.
                  Use it with `dontScanDirs` or `dontScanFiles` or `scanAllLinuxKernels = false` to remove auto-detected kernels.
                '';
              };
            };
          }
        );
        default = null;
        example = {
          timeout = 5;
          enableMouse = true;
          manageNixOSEntries = true;
        };
        description = ''
          If this option is set to `null` the flake don't manage the rEFInd `refind.conf` configuration.
          Otherwise, it will replace it content at each update.

          Default is null.
        '';
      };
      signWithLocalKeys = lib.mkOption {
        type = types.bool;
        default = false;
        example = true;
        description = ''
          Sign refind binaries if `installation` is set and the nixos kernel with your machine owner keys (MOK).

          If you want to use your own keys, you need to place them in the `/etc/refind.d/keys` directory with the names `refind_local.key`, `refind_local.crt` and `refind_local.cer`.
          Else refind will use the default keys.

          Those keys can be used with shim or to replace platform keys.
        '';
      };
      installDrivers = lib.mkOption {
        type = types.enum [
          "all"
          "boot"
          "none"
        ];
        default = if cfg.efiInstallAsRemovable then "all" else "boot";
        defaultText = lib.literalExpression "if cfg.efiInstallAsRemovable then \"all\" else \"boot\"";
        example = "all";
        description = ''
          Install drivers with rEFInd.
            - all: Install all drivers (great for removable drives).
            - boot: Install only drivers needed to boot the system.
            - none: Don't install any drivers.
        '';
      };
      installation = lib.mkOption {
        type = types.either types.bool types.str;
        default = true;
        example = false;
        description = ''
          If this option is set to `true` rEFInd will be installed and updated on the ESP.
          If this option is set to `false` rEFInd will not be installed on the ESP (useful if you want to install it with another OS).
          If this option is set to a string rEFInd will be installed with PreLoader.efi or shim(x64).efi to enable UEFI Secure Boot.

          The string will be the path of the preloader or shim file to be used.

          Files can be downloaded here: https://blog.hansenpartnership.com/linux-foundation-secure-boot-system-released/ and here https://launchpad.net/ubuntu/+source/shim-signed/

          PreLoader only works with hash approval that means that you need to reenroll linux kernel at each update.

          Shim can work with local keys that means you can have Secure Boot enabled without needing to reenroll the kernel at each update and without editing the platform keys.
          This flake will automaticaly sign the kernel if `signWithLocalKeys` is set.
        '';
      };
      package = lib.mkPackageOption pkgs "refind" { };
      maxGenerations = lib.mkOption {
        default = null;
        example = 50;
        type = types.nullOr types.positiveInt;
        description = ''
          Maximum number of latest generations in the boot menu.
          Useful to prevent boot partition of running out of disk space.
          `null` means no limit i.e.
        '';
      };
      generateLinuxConf = lib.mkOption {
        type = types.bool;
        default = true;
        example = false;
        description = ''
          Generate `refind_linux.conf` file next to the kernel.
        '';
      };
      efiInstallAsRemovable = lib.mkEnableOption null // {
        default = !efi.canTouchEfiVariables;
        # example = true;
        defaultText = lib.literalExpression "!config.boot.loader.efi.canTouchEfiVariables";
        description = ''
          Whether or not to install the rEFInd EFI files as removable.
          Use the `--usedefault` option of `refind-install`.

          See {option}`boot.loader.grub.efiInstallAsRemovable`
        '';
      };
      tools = lib.mkOption {
        default = { };
        type = types.attrsOf types.path;
        example = lib.literalExpression ''
          { "memtest86.efi" = "''${pkgs.memtest86-efi}/BOOTX64.efi"; }
        '';
        description = ''
          A set of files to be copied to `/boot/tools`. Each attribute name denotes the
          destination file name in `/boot/boot`, while the corresponding attribute value
          specifies the source file.

          Thoses tools can next be used from refind tools bar.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          pkgs.stdenv.hostPlatform.isx86_64
          || pkgs.stdenv.hostPlatform.isi686
          || pkgs.stdenv.hostPlatform.isAarch64;
        message = "rEFInd can only be installed on aarch64 & x86 platforms";
      }
    ];

    boot.loader.timeout = lib.mkDefault 20;

    boot.loader.grub.enable = lib.mkDefault false;

    # Common attribute for boot loaders so only one of them can be
    # set at once.
    system = {
      boot.loader.id = "refind";
      build.installBootLoader = pkgs.replaceVarsWith {
        src = ./refind-install.py;
        isExecutable = true;
        replacements = {
          python3 = pkgs.python3;
          configPath = refindInstallConfig;
        };
      };
    };
  };
}
