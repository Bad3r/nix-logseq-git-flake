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
    acc: key:
    throwIf (
      !hasPrefix "sha256-" parsed.${key}
    ) "Manifest ${key} must begin with sha256- (Nix SRI)." acc;
in
throwIf (missing != [ ]) "Manifest missing required keys: ${concatStringsSep ", " missing}" (
  builtins.foldl' validateHash parsed [
    "assetSha256"
    "cliSrcHash"
    "cliYarnDepsHash"
  ]
)
