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
        zig = zig-overlay.packages.${system}."0.16.0";
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ 
            (final: prev: {
                inherit zig;
             })
          ];
        };
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [ zig zls pkg-config wasmtime python3 just lua valgrind kdePackages.kcachegrind gtk4 xorg.libXcursor];
          shellHook = ''
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath (with pkgs; [
              wayland
              libxkbcommon
              libdecor
              libGL
              libglvnd
            ])}"
            export ZIG_GLOBAL_CACHE_DIR=.zig-cache
          '';
        };
      }
    );
}
