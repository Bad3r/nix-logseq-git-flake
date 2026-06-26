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
  # CLI-relevant patch basenames (manifest patches[] cli:true subset). build.nix
  # resolves these against patches/; the workflow applies the full patches[] list.
  cliPatches = map (p: p.file) (lib.filter (p: p.cli) manifest.patches);
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
      cliPatches
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
