{ lib, manifestPath }:
let
  inherit (builtins) fromJSON readFile hasAttr;
  inherit (lib) assertMsg concatStringsSep hasPrefix;
  parsed = fromJSON (readFile manifestPath);
  requiredKeys = [
    "tag"
    "publishedAt"
    "assetUrl"
    "assetSha256"
    "logseqRev"
    "logseqVersion"
  ];
  missing = lib.filter (key: ! hasAttr key parsed) requiredKeys;
  _ = assertMsg (missing == [])
        "Manifest missing required keys: ${concatStringsSep ", " missing}";
  _sha = assertMsg (hasPrefix "sha256-" parsed.assetSha256)
        "Manifest assetSha256 must begin with sha256- (Nix base32).";
in
parsed
