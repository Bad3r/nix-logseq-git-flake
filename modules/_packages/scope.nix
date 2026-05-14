{
  lib,
  manifestPath,
  pkgs,
}:
let
  manifest = import ../../lib/loadManifest.nix {
    inherit lib manifestPath;
  };

  runtimeLibs = import ../../lib/runtime-libs.nix;
  desktopScope = import ./desktop/scope.nix {
    inherit
      lib
      manifest
      pkgs
      runtimeLibs
      ;
  };
  cli = pkgs.callPackage ./logseq-cli/package.nix {
    inherit (manifest)
      cliPnpmDepsHash
      cliSrcHash
      cliVendorHash
      cliVersion
      logseqRev
      ;
  };
in
desktopScope
// {
  inherit cli;
}
