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

        # osu and osu-framework built from local git branches. Needs --impure.
        # OSU_SRC / OSU_FRAMEWORK_SRC and OSU_REF / OSU_FRAMEWORK_REF pick other clones or branches.
        osu-lazer-source-patched =
          let
            env = name: default: if builtins.getEnv name != "" then builtins.getEnv name else default;
          in
          pkgs.callPackage ./nix/pkgs/osu-lazer-source-patched/package.nix {
            osuSrc = builtins.fetchGit {
              url = env "OSU_SRC" "/home/n/llm-projects/osu-lazer";
              ref = env "OSU_REF" "gameplay-allocations";
            };
            osuFrameworkSrc = builtins.fetchGit {
              url = env "OSU_FRAMEWORK_SRC" "/home/n/llm-projects/osu-framework";
              ref = env "OSU_FRAMEWORK_REF" "input-latency";
            };
          };
        osu-lazer-launcher-source = pkgs.callPackage ./nix/pkgs/osu-lazer-launcher/package.nix {
          osu-lazer-bin-patched = self.packages.${system}.osu-lazer-source-patched;
        };
      };
    };
}
