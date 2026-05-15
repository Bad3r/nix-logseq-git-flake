{
  babashka,
  cacert,
  cliPnpmDeps,
  cliVendorHash,
  git,
  lib,
  logseqNodejs,
  pnpm_10,
  pnpmConfigHook,
  src,
  stdenv,
  version,
}:
stdenv.mkDerivation {
  pname = "logseq-cli-vendor";
  inherit version src;
  sourceRoot = "${src.name}/deps";

  nativeBuildInputs = [
    babashka
    cacert
    git
    logseqNodejs
    pnpm_10
    pnpmConfigHook
  ];

  pnpmDeps = cliPnpmDeps;
  pnpmRoot = "cli";

  env.npm_config_manage_package_manager_versions = "false";

  # FOD: allow network for nbb's git/maven fetches.
  impureEnvVars = lib.fetchers.proxyImpureEnvVars;
  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  outputHash = cliVendorHash;

  buildPhase = ''
    runHook preBuild
    pushd cli
    pnpm exec nbb-logseq -e :load-deps
    popd
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    shopt -s nullglob
    cache_dirs=(cli/.nbb/.cache/*/)
    shopt -u nullglob
    if [ ''${#cache_dirs[@]} -ne 1 ]; then
      echo "ERROR: expected exactly one nbb cache dir, got ''${#cache_dirs[@]}" >&2
      exit 1
    fi
    nbb_deps="''${cache_dirs[0]}nbb-deps"

    if [ ! -d "$nbb_deps" ]; then
      echo "ERROR: missing $nbb_deps — upstream may have changed nbb-deps layout" >&2
      exit 1
    fi

    # Mirror upstream's `bb build:vendor-nbb-deps` allowlist exactly.
    mkdir -p "$out"
    for dir in logseq malli borkdude medley; do
      if [ ! -d "$nbb_deps/$dir" ]; then
        echo "ERROR: missing $nbb_deps/$dir — upstream may have changed nbb-deps layout" >&2
        exit 1
      fi
      cp -r "$nbb_deps/$dir" "$out/$dir"
    done

    # Strip .git/ trees left behind by nbb's git-pinned deps. Their contents
    # are not bit-stable across clones and would tank the FOD output hash.
    find "$out" -name .git -type d -prune -exec rm -rf {} +

    runHook postInstall
  '';

  dontFixup = true;
}
