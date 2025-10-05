{ lib, manifestPath }:
let
  inherit (builtins) fromJSON hasAttr readFile;
  inherit (lib) concatStringsSep hasPrefix throwIf;
  parsed = fromJSON (readFile manifestPath);
  requiredKeys = [
    "tag"
    "publishedAt"
    "assetUrl"
    "assetSha256"
    "logseqRev"
    "logseqVersion"
  ];
  missing = lib.filter (key: !hasAttr key parsed) requiredKeys;
in
throwIf (missing != [ ]) "Manifest missing required keys: ${concatStringsSep ", " missing}" (
  throwIf (
    !hasPrefix "sha256-" parsed.assetSha256
  ) "Manifest assetSha256 must begin with sha256- (Nix base32)." parsed
)
