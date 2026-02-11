# Logseq CLI package
# Provides MCP server and graph management tools for DB graphs
{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchYarnDeps,
  writeShellScript,
  nodejs_22,
  yarnConfigHook,
  nix_prefetch_git,
  python3,
  gnumake,
  gcc,
  pkg-config,
  sqlite,
  # Manifest-driven parameters (passed from flake.nix)
  logseqRev,
  cliSrcHash,
  cliVersion,
  cliYarnDepsHash,
}:

let
  version = cliVersion;

  src = fetchFromGitHub {
    owner = "logseq";
    repo = "logseq";
    rev = logseqRev;
    hash = cliSrcHash;
  };

  cliOfflineCache =
    (fetchYarnDeps {
      name = "logseq-cli-yarn-deps";
      inherit src;
      postPatch = "cd deps/cli";
      hash = cliYarnDepsHash;
    }).overrideAttrs
      (old: {
        # Upstream yarn prefetch occasionally regresses PATH setup for git deps.
        # Keep nix-prefetch-git explicitly available to avoid ENOENT in CI.
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ nix_prefetch_git ];
      });

  # Build the CLI from offline yarn cache
  # The CLI has local deps on sibling packages (outliner, db,
  # graph-parser, common) so we need the full deps/ tree.
  cliBuilt = stdenv.mkDerivation {
    pname = "logseq-cli-built";
    inherit version src;
    sourceRoot = "${src.name}/deps";

    nativeBuildInputs = [
      nodejs_22
      yarnConfigHook
      python3
      gnumake
      gcc
      pkg-config
    ];

    buildInputs = [ sqlite ];

    env.npm_config_nodedir = nodejs_22;

    # yarn.lock lives in cli/, not the sourceRoot — disable auto-hook
    dontYarnInstallDeps = true;

    postConfigure = ''
      pushd cli
      yarnOfflineCache="${cliOfflineCache}" yarnConfigHook
      npm rebuild --verbose
      popd
    '';

    dontBuild = true;

    installPhase = ''
      runHook preInstall

      # Install the full deps tree (cli + sibling local deps)
      mkdir -p $out
      cp -r . $out/

      # Patch nbb_deps.js to use NBB_CACHE_DIR env var if set
      # Original: mMa=esm_import$node_path.resolve(lMa,".nbb",".cache")
      # Patched: use process.env.NBB_CACHE_DIR or fallback to original
      substituteInPlace $out/cli/node_modules/@logseq/nbb-logseq/lib/nbb_deps.js \
        --replace-fail \
          'mMa=esm_import$node_path.resolve(lMa,".nbb",".cache")' \
          'mMa=process.env.NBB_CACHE_DIR||esm_import$node_path.resolve(lMa,".nbb",".cache")'

      runHook postInstall
    '';

    dontStrip = true;
    dontPatchELF = true;
  };

  # Wrapper that sets up writable cache directory
  wrapper = writeShellScript "logseq-cli-wrapper" ''
    # Set up writable cache for nbb-logseq
    export NBB_CACHE_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/logseq-cli/nbb"
    mkdir -p "$NBB_CACHE_DIR"

    exec ${nodejs_22}/bin/node "${cliBuilt}/cli/cli.mjs" "$@"
  '';
in
stdenv.mkDerivation {
  pname = "logseq-cli";
  inherit version;

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin $out/lib
    ln -s ${cliBuilt} $out/lib/logseq-cli
    cp ${wrapper} $out/bin/logseq-cli
    chmod +x $out/bin/logseq-cli
  '';

  meta = {
    description = "Logseq CLI for DB graphs - MCP server and graph management";
    homepage = "https://github.com/logseq/logseq/tree/master/deps/cli";
    license = lib.licenses.agpl3Plus;
    mainProgram = "logseq-cli";
    platforms = lib.platforms.linux;
  };
}
