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
  # The app's sealed sources inside the normalized tree. tree.nix globs the
  # Darwin bundle as `*.app` and renames it, so an upstream productName change
  # keeps this path valid.
  appAsar =
    if isDarwin then
      "${logseqTree}/Logseq.app/Contents/Resources/app.asar"
    else
      "${logseqTree}/share/logseq/resources/app.asar";
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
    appAsar
    logseqDesktop
    logseqSrc
    logseqTree
    payload
    ;
}
