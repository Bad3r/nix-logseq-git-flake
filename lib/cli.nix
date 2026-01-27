# Logseq CLI package
# Provides MCP server and graph management tools for DB graphs
{
  lib,
  stdenv,
  fetchFromGitHub,
  writeShellScript,
  nodejs_22,
  yarn,
  python3,
  gnumake,
  gcc,
  pkg-config,
  sqlite,
  cacert,
  git,
}:

let
  version = "0.4.2";

  src = fetchFromGitHub {
    owner = "logseq";
    repo = "logseq";
    rev = "master";
    hash = "sha256-2qwleKVmWhqMvtJOT+dWFq1MoLpxaZ+wIvVGL2jShaw=";
  };

  # Build the CLI - allow network for GitHub dependency
  # The CLI has local deps on sibling packages (outliner, db,
  # graph-parser, common) so we need the full deps/ tree.
  cliBuilt = stdenv.mkDerivation {
    pname = "logseq-cli-built";
    inherit version src;
    sourceRoot = "${src.name}/deps";

    __noChroot = true; # Allow network for yarn install (GitHub dep)

    nativeBuildInputs = [
      nodejs_22
      yarn
      python3
      gnumake
      gcc
      pkg-config
      cacert
      git
    ];

    buildInputs = [ sqlite ];

    env.npm_config_nodedir = nodejs_22;

    buildPhase = ''
      runHook preBuild
      export HOME=$TMPDIR
      export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt

      cd cli
      yarn install --frozen-lockfile --ignore-engines
      cd ..

      runHook postBuild
    '';

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
