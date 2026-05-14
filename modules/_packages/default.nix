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
  desktop = import ./desktop.nix {
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
desktop
// {
  inherit cli;
}
