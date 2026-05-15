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
  logseqNodejs = pkgs.nodejs_24;
  desktopAssembly = import ./desktop/assembly.nix {
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
    inherit logseqNodejs;
  };
in
desktopAssembly
// {
  inherit cli;
}
