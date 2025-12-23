{ pkgs, lib, config, inputs, ... }:

{
  languages.zig = {
    enable = true;
    version = "0.15.2";
  };
  languages.python = {
    enable = true;
  };
}
