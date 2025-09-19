{
  description = "rEFInd bootloader flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      {
        nixosModules = {
          refind = import ./modules/refind.nix;
          default = self.nixosModules.refind;
        };

        packages = {
          refind = nixpkgs.legacyPackages.${system}.refind;
          default = self.packages.${system}.refind;
        };
      }
    );
}
