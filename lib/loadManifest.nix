{ lib, manifestPath }:
let
  inherit (builtins)
    attrNames
    foldl'
    fromJSON
    hasAttr
    isAttrs
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
  assetsIsAttrs = hasAttr "assets" parsed && isAttrs parsed.assets;
  missingAssetSystems =
    if assetsIsAttrs then
      lib.filter (system: !hasAttr system parsed.assets) requiredAssetSystems
    else
      requiredAssetSystems;

  # Type checks fire before any consumer touches a value, so a malformed
  # generated manifest fails with a manifest-shaped message instead of a raw
  # Nix type error from hasPrefix/hasAttr deep inside a package expression.
  validateString =
    acc: key: throwIf (!isString parsed.${key}) "Manifest ${key} must be a string." acc;

  validateHash =
    acc: key:
    throwIf (
      !(isString parsed.${key} && hasPrefix "sha256-" parsed.${key})
    ) "Manifest ${key} must be a string beginning with sha256- (Nix SRI)." acc;

  # update-nightly.sh resolves each cli/logseq-cli.opam pin-depends entry whose git
  # ref is a mutable branch into an explicit commit (opam-nix refuses a non-sha1 git
  # pin in pure evaluation mode). opam-deps.nix rewrites each `from` URL to `to`
  # before opam-nix reads the file. Require an explicit 40-char sha1 fragment on
  # every `to` so a stale/branch override cannot reach the pure-eval resolver.
  pinOverrides = if hasAttr "cliOpamPinOverrides" parsed then parsed.cliOpamPinOverrides else [ ];
  validatePinOverride =
    acc: entry:
    throwIf (!isAttrs entry) "Manifest cliOpamPinOverrides entries must be sets with from and to." (
      throwIf (!(hasAttr "from" entry && isString entry.from))
        "Manifest cliOpamPinOverrides entries must carry a string from."
        (
          throwIf (
            !(hasAttr "to" entry && isString entry.to && match ".*#[0-9a-f]{40}" entry.to != null)
          ) "Manifest cliOpamPinOverrides entries must carry a to URL ending in an explicit 40-char sha1." acc
        )
    );

  # Each per-system desktop asset must carry a string url and an SRI sha256.
  assetSystems = if assetsIsAttrs then attrNames parsed.assets else [ ];
  validateAsset =
    acc: system:
    let
      entry = parsed.assets.${system};
    in
    throwIf (!isAttrs entry) "Manifest assets.${system} must be a set with url and sha256." (
      throwIf (!(hasAttr "url" entry && isString entry.url))
        "Manifest assets.${system}.url must be a string."
        (
          throwIf (match ".*\\+.*" entry.url != null)
            "Manifest assets.${system}.url must encode plus signs as %2B."
            (
              throwIf (
                !(hasAttr "sha256" entry && isString entry.sha256 && hasPrefix "sha256-" entry.sha256)
              ) "Manifest assets.${system}.sha256 must be a string beginning with sha256- (Nix SRI)." acc
            )
        )
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
  # isAttrs guards hasAttr: hasAttr on a non-attrset throws an opaque builtin
  # error, so a malformed patches[] element (e.g. a bare string) would crash the
  # eval instead of hitting the throwIf message. The file charset excludes `/`
  # (and any path separator): both consumers concatenate file into a filesystem
  # path (workflow `git apply "../patches/$file"`, build.nix `../../../patches +
  # "/${file}"`), and `.*` would let a hand-edited `logseq-../...patch` escape
  # patches/. This validator is the only schema check on the field.
  validatePatch =
    acc: entry:
    throwIf
      (
        !(
          isAttrs entry
          && hasAttr "file" entry
          && isString entry.file
          && match "logseq-[A-Za-z0-9._-]+\\.patch" entry.file != null
        )
      )
      "Manifest patches[].file must name a logseq-*.patch basename."
      (
        throwIf (!(hasAttr "cli" entry && isBool entry.cli)) "Manifest patches[].cli must be a boolean." acc
      );
in
throwIf (!isAttrs parsed) "Manifest must be a JSON object." (
  throwIf (missing != [ ]) "Manifest missing required keys: ${concatStringsSep ", " missing}" (
    throwIf (hasAttr "assets" parsed && !isAttrs parsed.assets)
      "Manifest assets must be an attribute set keyed by system."
      (
        throwIf (missingAssetSystems != [ ])
          "Manifest missing required desktop asset systems: ${concatStringsSep ", " missingAssetSystems}"
          (
            throwIf (!isList pinOverrides) "Manifest cliOpamPinOverrides must be a list." (
              throwIf (!isList patches) "Manifest patches must be a list." (
                throwIf (!isAttrs toolchain) "Manifest toolchain must be an attribute set." (
                  foldl' validatePatch (foldl' validateToolchain (foldl' validatePinOverride (foldl' validateAsset (
                    foldl'
                    validateHash
                    (foldl' validateString parsed [
                      "tag"
                      "publishedAt"
                      "logseqRev"
                      "logseqVersion"
                      "cliVersion"
                    ])
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
      )
  )
)
