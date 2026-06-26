{ lib, manifestPath }:
let
  inherit (builtins)
    attrNames
    foldl'
    fromJSON
    hasAttr
    isBool
    isList
    isString
    match
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
    "cliOpamPinOverrides"
    "cliPnpmDepsHash"
    "cliBundlePnpmDepsHash"
    "cliCljDepsHash"
    "cliVersion"
    "toolchain"
    "patches"
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

  # update-nightly.sh resolves each cli/logseq-cli.opam pin-depends entry whose git
  # ref is a mutable branch into an explicit commit (opam-nix refuses a non-sha1 git
  # pin in pure evaluation mode). opam-deps.nix rewrites each `from` URL to `to`
  # before opam-nix reads the file. Require an explicit 40-char sha1 fragment on
  # every `to` so a stale/branch override cannot reach the pure-eval resolver.
  pinOverrides = if hasAttr "cliOpamPinOverrides" parsed then parsed.cliOpamPinOverrides else [ ];
  validatePinOverride =
    acc: entry:
    throwIf (!(hasAttr "from" entry && isString entry.from))
      "Manifest cliOpamPinOverrides entries must carry a string from."
      (
        throwIf (
          !(hasAttr "to" entry && isString entry.to && match ".*#[0-9a-f]{40}" entry.to != null)
        ) "Manifest cliOpamPinOverrides entries must carry a to URL ending in an explicit 40-char sha1." acc
      );

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

  # CI toolchain versions consumed by build-desktop.yml setup-* steps via
  # resolve-revision outputs. No Nix file reads these (the Nix side pins nixpkgs
  # attrs), so they have zero Nix consumers; validated here to keep the workflow
  # producer/consumer schema honest.
  toolchain = if hasAttr "toolchain" parsed then parsed.toolchain else { };
  toolchainKeys = [
    "node"
    "pnpm"
    "java"
    "clojure"
  ];
  validateToolchain =
    acc: key:
    throwIf (
      !(hasAttr key toolchain && isString toolchain.${key} && toolchain.${key} != "")
    ) "Manifest toolchain.${key} must be a non-empty string." acc;

  # Both apply sites read this list: build-desktop.yml applies every file; the CLI
  # build (build.nix) applies only the cli:true subset. update-nightly.sh
  # regenerates file from patches/ preserving the hand-set cli flag.
  patches = if hasAttr "patches" parsed then parsed.patches else [ ];
  validatePatch =
    acc: entry:
    throwIf
      (!(hasAttr "file" entry && isString entry.file && match "logseq-.*\\.patch" entry.file != null))
      "Manifest patches[].file must name a logseq-*.patch file."
      (
        throwIf (!(hasAttr "cli" entry && isBool entry.cli)) "Manifest patches[].cli must be a boolean." acc
      );
in
throwIf (missing != [ ]) "Manifest missing required keys: ${concatStringsSep ", " missing}" (
  throwIf (missingAssetSystems != [ ])
    "Manifest missing required desktop asset systems: ${concatStringsSep ", " missingAssetSystems}"
    (
      throwIf (!isList pinOverrides) "Manifest cliOpamPinOverrides must be a list." (
        throwIf (!isList patches) "Manifest patches must be a list." (
          foldl' validatePatch (foldl' validateToolchain (foldl' validatePinOverride (foldl' validateAsset (
            foldl'
            validateHash
            parsed
            [
              "cliSrcHash"
              "cliPnpmDepsHash"
              "cliBundlePnpmDepsHash"
              "cliCljDepsHash"
            ]
          ) assetSystems) pinOverrides) toolchainKeys) patches
        )
      )
    )
)
