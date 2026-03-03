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
  };

  outputs =
    { nixpkgs, flake-utils, zig-overlay, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ zig-overlay.overlays.default ];
        };
      in
      {
        devShells.default = pkgs.mkShell { 
            packages = with pkgs; [ zigpkgs.master zls wasmtime python3 just lua samply valgrind kdePackages.kcachegrind ];
            shellHook = ''
              export ZIG_GLOBAL_CACHE_DIR=.zig-cache
              echo $ZIG_GLOBAL_CACHE_DIR
              '';
        };
      }
    );
}
