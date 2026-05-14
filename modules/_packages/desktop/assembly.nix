{
  lib,
  manifest,
  pkgs,
  runtimeLibs,
}:
let
  runtimeLibList = runtimeLibs pkgs;
  runtimeLibPath = lib.makeLibraryPath runtimeLibList;
  payload = import ./payload.nix {
    inherit manifest pkgs;
  };
  logseqSrc = import ./upstream-source.nix {
    inherit manifest pkgs;
  };
  logseqTree = import ./tree.nix {
    inherit payload pkgs;
  };
  fhsBase = import ./fhs.nix {
    inherit logseqTree pkgs runtimeLibs;
  };
  logseqFhs = fhsBase { };
  desktopEntry = import ./desktop-entry.nix { inherit pkgs; };
  icon = import ./icon.nix {
    inherit logseqSrc pkgs;
  };
  launcher = import ./launcher.nix {
    inherit
      logseqFhs
      pkgs
      runtimeLibPath
      ;
  };
  logseqDesktop = import ./package.nix {
    inherit
      desktopEntry
      fhsBase
      icon
      launcher
      lib
      logseqFhs
      logseqTree
      manifest
      pkgs
      ;
  };
in
{
  inherit
    logseqDesktop
    logseqSrc
    payload
    ;
}
