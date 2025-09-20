{
  description = "rEFInd bootloader flake";

  outputs =
    { self }:
    {
      nixosModules = {
        refind = import ./modules/refind.nix;
        default = self.nixosModules.refind;
      };
    };
}
