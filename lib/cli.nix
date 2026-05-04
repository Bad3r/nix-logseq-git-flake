# Logseq CLI package
# Provides MCP server and graph management tools for DB graphs
{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  writeShellScript,
  babashka,
  cacert,
  git,
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
  cliVendorHash,
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
    # Both source/package.json and source/deps/cli/package.json pin
    # `packageManager: pnpm@<exact version>`. When the nixpkgs-provided pnpm
    # doesn't match exactly (e.g. patch-level bump), pnpm self-installs the
    # requested version into $HOME/.local/share before running any command —
    # failing in the build sandbox. fetchPnpmDeps tries to suppress this with
    # `pushd ..; pnpm config set manage-package-manager-versions false`, but
    # that runs from `source/deps/`, where pnpm walks up to `source/package.json`
    # and triggers the auto-switch *during* the config-set itself. The env var
    # is consulted before any package.json walk, so it short-circuits cleanly.
    env.npm_config_manage_package_manager_versions = "false";
  };

  # Replicate upstream's `bb build:vendor-nbb-deps` task. nbb-logseq is an
  # interpreter, not a compiler, so the CLI needs the source of every
  # transitively-required namespace at runtime. Upstream collects them under
  # deps/cli/vendor/src/ before publishing to npm; we have to do the same
  # before the runtime classpath (cli/src + cli/vendor/src) can resolve
  # `logseq.common.graph-dir` and friends.
  #
  # Implemented as a fixed-output derivation: `pnpm exec nbb-logseq -e
  # :load-deps` fetches sha-pinned git/maven deps over the network. The
  # `:load-deps` keyword itself is a no-op expression; nbb just has to
  # bootstrap its dep graph before evaluating any `-e` form, and that
  # bootstrap is what populates `.nbb/.cache/<hash>/nbb-deps/`. The output is
  # CLJS sources keyed by namespace, so the NAR hash is deterministic.
  #
  # `babashka` is required at build time even though we never invoke `bb`
  # directly: nbb-logseq's `nbb_deps.js` shells out to `bb uberjar` to pack
  # the resolved deps before populating the cache. Removing it from
  # nativeBuildInputs surfaces as `bb: not found` from execSync in the
  # buildPhase log.
  cliVendor = stdenv.mkDerivation {
    pname = "logseq-cli-vendor";
    inherit version src;
    sourceRoot = "${src.name}/deps";

    nativeBuildInputs = [
      babashka
      cacert
      git
      nodejs_22
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

      # Copy every namespace subdir, not just upstream's current vendor
      # allowlist. nbb's resolver may pull in new top-level deps in a future
      # nightly (e.g. rewrite-clj); a hardcoded allowlist would silently drop
      # them and re-trigger the namespace-resolution failure this FOD is
      # meant to prevent. Loose top-level files like `data_readers.clj` /
      # `data_readers.cljc` are intentionally skipped — they live at
      # classpath root and Clojure auto-loads them, so vendoring them would
      # alter runtime tagged-literal handling.
      mkdir -p "$out"
      shopt -s nullglob
      copied=0
      for entry in "$nbb_deps"/*/; do
        name=$(basename "$entry")
        cp -r "$entry" "$out/$name"
        copied=$((copied + 1))
      done
      shopt -u nullglob
      if [ "$copied" -eq 0 ]; then
        echo "ERROR: $nbb_deps had no namespace subdirs — upstream nbb-deps layout may have changed" >&2
        exit 1
      fi

      # Strip .git/ trees left behind by nbb's git-pinned deps. Their contents
      # (pack files, refs) are not bit-stable across clones and would tank the
      # FOD output hash even though the source files themselves are pinned.
      find "$out" -name .git -type d -prune -exec rm -rf {} +

      # Sanity check: upstream's `bb build:vendor-nbb-deps` always copies these
      # four top-level namespaces into vendor/src. If any are missing, nbb's
      # deps loader produced an unexpected layout and the rest of this build
      # is suspect.
      for dir in logseq malli borkdude medley; do
        if [ ! -d "$out/$dir" ]; then
          echo "ERROR: $out/$dir not found after copy — upstream nbb-deps layout may have changed" >&2
          exit 1
        fi
      done

      runHook postInstall
    '';

    dontFixup = true;
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

    env = {
      npm_config_nodedir = nodejs_22;
      # Same rationale as on cliPnpmDeps: pin packageManager mismatch would
      # otherwise trigger pnpm's auto-switch during `pnpm rebuild`.
      npm_config_manage_package_manager_versions = "false";
    };

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

      # Wire up vendor sources next to cli/src so nbb-logseq can resolve
      # logseq.common.graph-dir etc. at runtime. The bb task also drops
      # nbb.edn so the runtime doesn't try to re-resolve deps from network.
      mkdir -p $out/cli/vendor/src
      cp -r ${cliVendor}/. $out/cli/vendor/src/
      chmod -R u+w $out/cli/vendor
      rm -f $out/cli/nbb.edn

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
