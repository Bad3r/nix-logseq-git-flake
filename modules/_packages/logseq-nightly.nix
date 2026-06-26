{
  lib,
  manifestPath,
  opamNix,
  pkgs,
  system,
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
      cliBundlePnpmDepsHash
      cliCljDepsHash
      cliOpamPinOverrides
      cliPnpmDepsHash
      cliSrcHash
      cliVersion
      logseqRev
      ;
    inherit
      logseqNodejs
      opamNix
      pkgs
      system
      ;
  };
in
desktopAssembly
// {
  inherit cli;
}
