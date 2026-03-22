# Logseq CLI package
# Provides MCP server and graph management tools for DB graphs
{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchYarnDeps,
  writeShellScript,
  writeShellScriptBin,
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
  nixPrefetchGitCompat = writeShellScriptBin "nix-prefetch-git" ''
    # nixpkgs can ship only a version-suffixed executable (e.g. nix-prefetch-git-<ver>).
    # prefetch-yarn-deps still calls plain "nix-prefetch-git", so provide a stable shim.
    for candidate in \
      ${nix_prefetch_git}/bin/nix-prefetch-git \
      ${nix_prefetch_git}/bin/nix-prefetch-git-*; do
      if [ -x "$candidate" ]; then
        exec "$candidate" "$@"
      fi
    done

    echo "nix-prefetch-git executable not found under ${nix_prefetch_git}/bin" >&2
    exit 127
  '';

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
        # prefetch-yarn-deps expects "nix-prefetch-git" in PATH. Newer nixpkgs
        # may only provide a version-suffixed binary, so add a stable shim.
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ nixPrefetchGitCompat ];
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
