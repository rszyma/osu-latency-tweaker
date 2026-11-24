{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # Sources of osu-lazer-source-patched. These are only fetched when that package is built.
    # Run `nix flake update osu-src osu-framework-src` to build newer commits of the branches,
    # or use --override-input to build other clones or branches.
    osu-src = {
      url = "git+file:///home/n/llm-projects/osu-lazer?ref=gameplay-allocations";
      flake = false;
    };
    osu-framework-src = {
      url = "git+file:///home/n/llm-projects/osu-framework?ref=input-latency";
      flake = false;
    };
  };

  outputs =
    inputs@{ self, ... }:
    let
      system = "x86_64-linux";
      # osu-lazer is unfree: it bundles libbass, and osu's resources are CC BY-NC.
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfreePredicate =
          pkg:
          builtins.elem (inputs.nixpkgs.lib.getName pkg) [
            "osu-lazer-bin"
            "osu-lazer"
          ];
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

        # osu and osu-framework built from the local git branches in the osu-src and osu-framework-src inputs.
        osu-lazer-source-patched = pkgs.callPackage ./nix/pkgs/osu-lazer-source-patched/package.nix {
          osuSrc = inputs.osu-src;
          osuFrameworkSrc = inputs.osu-framework-src;
        };
        osu-lazer-launcher-source = pkgs.callPackage ./nix/pkgs/osu-lazer-launcher/package.nix {
          osu-lazer-bin-patched = self.packages.${system}.osu-lazer-source-patched;
        };
      };
    };
}
