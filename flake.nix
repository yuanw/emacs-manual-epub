{
  description = "Generate emacs manual in epub format";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    git-hooks-nix.url = "github:cachix/git-hooks.nix";


    emacs = {
      url = "github:nix-community/emacs-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
      ];
      imports = [
        inputs.git-hooks-nix.flakeModule
      ];
      perSystem = { config, pkgs, system, ... }: {
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [
            inputs.emacs.overlay
            (final: prev: {
              # ... things you need to patch ...
            })
          ];
          config = { };
        };
        pre-commit.settings.hooks = {
          nixpkgs-fmt.enable = true;
        };

        devShells.default = pkgs.mkShell {
          shellHook = ''
            ${config.pre-commit.shellHook}
          '';
        };
      };

    };
}
