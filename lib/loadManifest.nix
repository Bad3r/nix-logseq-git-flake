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
    "cliSrcHash"
    "cliYarnDepsHash"
    "cliVersion"
  ];
  missing = lib.filter (key: !hasAttr key parsed) requiredKeys;
  validateHash =
    key:
    throwIf (!hasPrefix "sha256-" parsed.${key}) "Manifest ${key} must begin with sha256- (Nix SRI).";
in
throwIf (missing != [ ]) "Manifest missing required keys: ${concatStringsSep ", " missing}" (
  validateHash "assetSha256" (validateHash "cliSrcHash" (validateHash "cliYarnDepsHash" parsed))
)
