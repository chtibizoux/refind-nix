{
  description = "rEFInd bootloader flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs =
    { self, nixpkgs, ... }:
    {
      nixosModules = {
        refind = import ./modules/refind.nix;
        default = self.nixosModules.refind;
      };

      packages.x86_64-linux.refind = nixpkgs.legacyPackages.x86_64-linux.refind;
      packages.x86_64-linux.default = self.packages.x86_64-linux.refind;
    };
}
