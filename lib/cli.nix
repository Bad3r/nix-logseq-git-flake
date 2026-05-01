# Logseq CLI package
# Provides MCP server and graph management tools for DB graphs
{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  writeShellScript,
  nodejs_22,
  pnpm_10,
  pnpmConfigHook,
  python3,
  gnumake,
  gcc,
  pkg-config,
  sqlite,
  # Manifest-driven parameters (passed from flake.nix)
  logseqRev,
  cliSrcHash,
  cliVersion,
  cliPnpmDepsHash,
}:

let
  version = cliVersion;
  src = fetchFromGitHub {
    owner = "logseq";
    repo = "logseq";
    rev = logseqRev;
    hash = cliSrcHash;
  };

  cliPnpmDeps = fetchPnpmDeps {
    pname = "logseq-cli";
    inherit version src;
    sourceRoot = "${src.name}/deps/cli";
    pnpm = pnpm_10;
    fetcherVersion = 3;
    hash = cliPnpmDepsHash;
    # nixpkgs fetchPnpmDeps disables pnpm's auto-switch via `pushd ..; pnpm
    # config set ...`, but `..` is still inside the upstream repo, whose root
    # package.json pins `packageManager: pnpm@10.33.0`. pnpm walks up, finds it,
    # and tries to self-install before applying the setting. Place an .npmrc at
    # the pushd target so the setting is read first.
    postPatch = ''
      chmod +w ..
      echo "manage-package-manager-versions=false" >> ../.npmrc
    '';
  };

  # Build the CLI from an offline pnpm store.
  # The CLI has local deps on sibling packages (outliner, db,
  # graph-parser, common) so we need the full deps/ tree.
  cliBuilt = stdenv.mkDerivation {
    pname = "logseq-cli-built";
    inherit version src;
    sourceRoot = "${src.name}/deps";

    nativeBuildInputs = [
      nodejs_22
      pnpm_10
      pnpmConfigHook
      python3
      gnumake
      gcc
      pkg-config
    ];

    buildInputs = [ sqlite ];

    pnpmDeps = cliPnpmDeps;
    pnpmRoot = "cli";

    env.npm_config_nodedir = nodejs_22;

    buildPhase = ''
      runHook preBuild

      pushd cli
      pnpm rebuild
      popd

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      # Install the full deps tree (cli + sibling local deps)
      mkdir -p $out
      cp -r . $out/

      # Patch nbb_deps.js to use NBB_CACHE_DIR env var if set. The file is
      # minified, so upstream regularly renames local symbols while keeping the
      # same resolve(<state>,".nbb",".cache") structure.
      python <<'PY'
      import os
      import re
      from pathlib import Path

      path = (
          Path(os.environ["out"])
          / "cli/node_modules/@logseq/nbb-logseq/lib/nbb_deps.js"
      )
      text = path.read_text()
      pattern = re.compile(
          r'([A-Za-z_$][A-Za-z0-9_$]*)=esm_import\$node_path\.resolve\('
          r'([A-Za-z_$][A-Za-z0-9_$]*),"\.nbb","\.cache"\)'
      )
      replacement = (
          r'\1=process.env.NBB_CACHE_DIR||'
          r'esm_import$node_path.resolve(\2,".nbb",".cache")'
      )
      patched, count = pattern.subn(replacement, text, count=1)
      if count != 1:
          raise SystemExit(
              f"expected to patch one nbb cache path assignment in {path}, got {count}"
          )
      path.write_text(patched)
      PY

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
