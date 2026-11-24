{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    inputs@{ self, ... }:
    let
      system = "x86_64-linux";
      # osu-lazer-bin is unfree: it bundles libbass, and osu's resources are CC BY-NC.
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfreePredicate = pkg: inputs.nixpkgs.lib.getName pkg == "osu-lazer-bin";
      };
    in
    {
      packages.${system} = {
        default = self.packages.${system}.osu-lazer-launcher;
        basscallwrap = pkgs.callPackage ./nix/pkgs/basscallwrap/package.nix { };
        osu-lazer-launcher = pkgs.callPackage ./nix/pkgs/osu-lazer-launcher/package.nix {
          inherit (self.packages.${system}) osu-lazer-bin-patched;
        };
        osu-lazer-bin-patched = pkgs.callPackage ./nix/pkgs/osu-lazer-bin-patched/default.nix { };
      };
    };
}
