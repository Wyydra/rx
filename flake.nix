{
  description = "Rx shell devenv";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default";
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell { 
            packages = with pkgs; [ zig zls wasmtime python3 just lua ]; 
            shellHook = ''
              export ZIG_GLOBAL_CACHE_DIR=.zig-cache
              echo $ZIG_GLOBAL_CACHE_DIR
              '';
        };
      }
    );
}
