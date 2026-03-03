{
  description = "Rx shell devenv";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default";
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
    zig-overlay.url = "github:mitchellh/zig-overlay";
    zls = {
      url = "github:zigtools/zls";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.zig-overlay.follows = "zig-overlay";
    };
  };

  outputs =
    { nixpkgs, flake-utils, zig-overlay, zls, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ zig-overlay.overlays.default ];
        };
        zig = pkgs.zigpkgs.master;
        zls_pkg = zls.packages.${system}.zls;
      in
      {
        devShells.default = pkgs.mkShell { 
          packages = with pkgs; [ wasmtime python3 just lua valgrind kdePackages.kcachegrind ]
                     ++ [ zig zls_pkg ];
          shellHook = ''
            export ZIG_GLOBAL_CACHE_DIR=.zig-cache
          '';
        };
      }
    );
}
