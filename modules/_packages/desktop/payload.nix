{ manifest, pkgs }:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  asset =
    manifest.assets.${system}
      or (throw "logseq desktop: no asset for system ${system} in manifest.assets");
in
pkgs.fetchzip {
  inherit (asset) url;
  hash = asset.sha256;
  stripRoot = false;
}
