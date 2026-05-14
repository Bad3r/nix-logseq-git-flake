{ manifest, pkgs }:
pkgs.fetchzip {
  url = manifest.assetUrl;
  hash = manifest.assetSha256;
  stripRoot = false;
}
