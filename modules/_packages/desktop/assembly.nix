{
  lib,
  manifest,
  pkgs,
  runtimeLibs,
}:
let
  payload = import ./payload.nix {
    inherit manifest pkgs;
  };
  logseqSrc = import ./upstream-source.nix {
    inherit manifest pkgs;
  };
  logseqTree = import ./tree.nix {
    inherit payload pkgs;
  };
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux system;
  logseqDesktop =
    if isLinux then
      let
        runtimeLibList = runtimeLibs pkgs;
        runtimeLibPath = lib.makeLibraryPath runtimeLibList;
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
      in
      import ./package.nix {
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
      }
    else if isDarwin then
      import ./package-darwin.nix {
        inherit
          lib
          logseqTree
          manifest
          pkgs
          ;
      }
    else
      throw "logseq desktop: unsupported system ${system}";
in
{
  inherit
    logseqDesktop
    logseqSrc
    payload
    ;
}
