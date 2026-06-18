{ lib, manifestPath }:
let
  inherit (builtins)
    attrNames
    foldl'
    fromJSON
    hasAttr
    isString
    readFile
    ;
  inherit (lib) concatStringsSep hasPrefix throwIf;
  parsed = fromJSON (readFile manifestPath);
  requiredKeys = [
    "tag"
    "publishedAt"
    "assets"
    "logseqRev"
    "logseqVersion"
    "cliSrcHash"
    "cliPnpmDepsHash"
    "cliBundlePnpmDepsHash"
    "cliCljDepsHash"
    "cliVersion"
  ];
  missing = lib.filter (key: !hasAttr key parsed) requiredKeys;
  requiredAssetSystems = [
    "x86_64-linux"
    "aarch64-linux"
    "aarch64-darwin"
  ];
  missingAssetSystems =
    if hasAttr "assets" parsed then
      lib.filter (system: !hasAttr system parsed.assets) requiredAssetSystems
    else
      requiredAssetSystems;

  validateHash =
    acc: key:
    throwIf (
      !hasPrefix "sha256-" parsed.${key}
    ) "Manifest ${key} must begin with sha256- (Nix SRI)." acc;

  # Each per-system desktop asset must carry a string url and an SRI sha256.
  assetSystems = if hasAttr "assets" parsed then attrNames parsed.assets else [ ];
  validateAsset =
    acc: system:
    let
      entry = parsed.assets.${system};
    in
    throwIf (!(hasAttr "url" entry && isString entry.url))
      "Manifest assets.${system}.url must be a string."
      (
        throwIf (
          !(hasAttr "sha256" entry && hasPrefix "sha256-" entry.sha256)
        ) "Manifest assets.${system}.sha256 must begin with sha256- (Nix SRI)." acc
      );
in
throwIf (missing != [ ]) "Manifest missing required keys: ${concatStringsSep ", " missing}" (
  throwIf (missingAssetSystems != [ ])
    "Manifest missing required desktop asset systems: ${concatStringsSep ", " missingAssetSystems}"
    (
      foldl' validateAsset (foldl' validateHash parsed [
        "cliSrcHash"
        "cliPnpmDepsHash"
        "cliBundlePnpmDepsHash"
        "cliCljDepsHash"
      ]) assetSystems
    )
)
