{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    inputs@{ self, ... }:
    let
      system = "x86_64-linux";
      pkgs = inputs.nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system} = {
        default = self.packages.${system}.osu-lazer-bin-patched;
        basscallwrap = pkgs.callPackage ./nix/pkgs/basscallwrap/package.nix { };
        osu-lazer-bin-patched = pkgs.callPackage ./nix/pkgs/osu-lazer-bin-patched/default.nix { };
      };
    };
}
