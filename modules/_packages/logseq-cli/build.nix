{
  cctools,
  clang_20,
  cliBundlePnpmDeps,
  cliCljDeps,
  cliPnpmDeps,
  clojure,
  git,
  gnumake,
  jdk,
  lib,
  libsecret,
  logseqNodejs,
  logseqRev,
  ocamlBuildInputs,
  patchelf,
  pkg-config,
  pnpm_10,
  pnpmConfigHook,
  python3,
  sqlite,
  src,
  stdenv,
  version,
  xcbuild,
  zstd,
}:
# Build the Logseq CLI from source following upstream's release recipe
# (.github/workflows/deps-cli.yml + build-desktop-release.yml -> CLI steps):
#   opam exec -- pnpm cli:release             -> static/logseq-cli.js (OCaml/Melange)
#   pnpm db-worker-node:release:bundle        -> dist/db-worker-node.js (+assets)
#   node scripts/prepare-cli-package.mjs      -> dist/cli-package/
# Since logseq/logseq dbd220c95d
# (https://github.com/logseq/logseq/commit/dbd220c95d) the CLI front-end is OCaml
# compiled via Melange and bundled with Vite (`dune build @bundle`), not a
# shadow-cljs target; the db-worker-node sidecar it spawns at runtime is still a
# shadow-cljs :node-script release. `dist/logseq.js` is a committed launcher shim
# that requires `../static/logseq-cli.js`.
stdenv.mkDerivation {
  pname = "logseq-cli-built";
  inherit version src;

  # Temporary upstream fixes; each patch header documents the bug and its
  # removal condition. Only patches touching files compiled into the CLI
  # belong here. The nightly desktop build applies the full patches/ set in
  # .github/workflows/build-desktop.yml; keep the two apply sites in sync
  # when adding or removing a CLI-relevant patch. Patching here (not in the
  # source FOD) keeps cliSrcHash and the dependency FODs unchanged.
  patches = [ ../../../patches/logseq-cli-auth-bind-loopback-address-families.patch ];

  # keytar (db-worker OS-keychain access) ships no usable prebuilt for this Node
  # ABI, so its native addon is compiled from source with node-gyp (see the
  # "build keytar.node" step in buildPhase). That needs a C/C++ toolchain plus
  # libsecret on Linux; the other addons (lightningcss, rolldown, zvec) and WASM
  # sqlite (@sqlite.org/sqlite-wasm) are prebuilt and need no toolchain.
  nativeBuildInputs = [
    logseqNodejs
    pnpm_10
    pnpmConfigHook
    clojure
    jdk
    git
    python3
    gnumake
    pkg-config
    stdenv.cc
  ]
  # pnpmConfigHook propagates zstd onto PATH but not the sqlite3 CLI; the cli/
  # store extraction in buildPhase needs both.
  ++ [
    sqlite
    zstd
  ]
  # OCaml 5.4 + melange* + humanize closure (opam-nix) for `dune build @bundle`;
  # each carries setup hooks assembling OCAMLPATH so dune resolves the deps.
  ++ ocamlBuildInputs
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    patchelf
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    cctools
    xcbuild
    # clang 20 toolchain for the keytar node-gyp build (wired via $CC/$CXX in
    # buildPhase). The default stdenv.cc is clang 21, which rejects
    # node-addon-api@4.3.0 (pulled by keytar 7.9.0): napi.h initializes a
    # `static const napi_typedarray_type` with `static_cast<...>(-1)`, and
    # clang 21 treats that out-of-range enum cast as a hard error
    # (-Wenum-constexpr-conversion). clang 20 still compiles it. Matches the
    # in-tree nixpkgs "clang_21 breaks keytar" pins (azurite, basedpyright,
    # vscode-lldb, rust-analyzer). Kept in nativeBuildInputs so this wrapper's
    # setup hook configures its SDK/sysroot env for the explicit CC/CXX use.
    clang_20
  ];

  # keytar's posix build links libsecret-1 via pkg-config (Linux only); Darwin
  # uses the Keychain/AppKit framework and needs no extra buildInput.
  buildInputs = lib.optional stdenv.hostPlatform.isLinux libsecret;

  pnpmDeps = cliPnpmDeps;

  env = {
    # node-gyp resolves Node headers/common.gypi from npm_config_nodedir.
    npm_config_nodedir = logseqNodejs;
    npm_config_manage_package_manager_versions = "false";
  };

  buildPhase = ''
    runHook preBuild

    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"

    # Build keytar.node from source. pnpm 10 lists keytar in
    # onlyBuiltDependencies, but the offline install never runs its build
    # script, so the binding is missing and the db-worker dies at
    # `require("keytar")` with server-start-timeout-orphan. node-gyp needs Node
    # headers (npm_config_nodedir) and, on Linux, libsecret-1.pc on
    # PKG_CONFIG_PATH (keytar's binding.gyp shells out to pkg-config);
    # build_from_source skips prebuild-install's network fetch.
    ${lib.optionalString stdenv.hostPlatform.isLinux ''
      export PKG_CONFIG_PATH="${lib.getDev libsecret}/lib/pkgconfig''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    ''}
    ${lib.optionalString stdenv.hostPlatform.isDarwin ''
      # Force node-gyp to compile with clang 20. Listing clang_20 in
      # nativeBuildInputs is not enough: the default stdenv cc-wrapper still wins
      # $CC/$CXX, so node-gyp picked clang 21 and failed on node-addon-api's
      # napi.h (-Wenum-constexpr-conversion). Setting CC/CXX here (after all
      # setup hooks) deterministically routes node-gyp through clang 20.
      export CC="${clang_20}/bin/clang"
      export CXX="${clang_20}/bin/clang++"
    ''}
    # --reporter=append-only prints the node-gyp/clang output inline. The Nix
    # sandbox strips $CI, so pnpm otherwise picks its interactive reporter and a
    # native-build failure collapses into an empty progress box with no error.
    npm_config_build_from_source=true pnpm --reporter=append-only rebuild keytar

    # Fail loudly if the binding is still missing: a silent skip here is exactly
    # what shipped a non-functional CLI through a green smoke check.
    if ! node -e 'require.resolve("keytar/build/Release/keytar.node")' 2>/dev/null; then
      echo "keytar.node was not built; the db-worker cannot start. Check node-gyp/pkg-config/libsecret." >&2
      exit 1
    fi

    # tools.deps needs a writable Maven local repo and gitlibs tree; the FOD
    # outputs are read-only in the store, so copy them into $TMPDIR.
    cp -r ${cliCljDeps}/m2 "$TMPDIR/m2"
    cp -r ${cliCljDeps}/gitlibs "$TMPDIR/gitlibs"
    chmod -R u+w "$TMPDIR/m2" "$TMPDIR/gitlibs"

    # The FOD froze the worktree gitlinks' absolute build-dir path to the fixed
    # `@GITLIBS@` placeholder for byte-reproducibility. Restore the real path so
    # tools.gitlibs can resolve the `libs/<coord>/<sha>` worktrees offline.
    while IFS= read -r -d "" link; do
      substituteInPlace "$link" --replace-fail "@GITLIBS@" "$TMPDIR/gitlibs"
    done < <(grep -rFIlZ '@GITLIBS@' "$TMPDIR/gitlibs" 2>/dev/null || true)

    export GITLIBS="$TMPDIR/gitlibs"
    clj_sdeps="{:mvn/local-repo \"$TMPDIR/m2\"}"

    # Both the shadow-cljs build-metadata hook (db-worker) and cli/vite.config.mjs
    # (CLI bundle defines) read $LOGSEQ_REVISION before falling back to
    # `git describe` (impossible here: fetchFromGitHub strips .git).
    # Stamp the upstream commit so REVISION changes with the source:
    # logseq.cli.server restarts a running db-worker whose revision differs
    # from the CLI's, and a constant placeholder revision would let a newer
    # CLI silently reuse a stale worker from an older nightly. The git in
    # nativeBuildInputs stays: tools.gitlibs still shells out to it when
    # resolving the offline git deps tree.
    export LOGSEQ_REVISION=${lib.escapeShellArg logseqRev}
    # The hook's BUILD_TIME fallback is wall-clock; pin it to SOURCE_DATE_EPOCH
    # so rebuilds stay byte-identical.
    LOGSEQ_BUILD_TIME="$(date -u -d "@''${SOURCE_DATE_EPOCH:-0}" +%Y-%m-%dT%H:%M:%SZ)"
    export LOGSEQ_BUILD_TIME

    # Populate cli/node_modules offline from the cliBundlePnpmDeps store, which
    # is a separate pnpm workspace (cli/pnpm-lock.yaml: vite + transit-js) from
    # the monorepo root install pnpmConfigHook already materialized. This mirrors
    # nixpkgs pnpm-config-hook.sh (extract store tarball, point store-dir at it,
    # offline frozen install) for the cli/ directory.
    cli_store="$(mktemp -d)"
    tar --zstd -xf "${cliBundlePnpmDeps}/pnpm-store.tar.zst" -C "$cli_store"
    chmod -R +w "$cli_store"
    if [ -f "$cli_store/v11/index.db.sql" ]; then
      sqlite3 "$cli_store/v11/index.db" <"$cli_store/v11/index.db.sql"
      rm "$cli_store/v11/index.db.sql"
    fi
    (
      cd cli
      pnpm config set store-dir "$cli_store"
      pnpm config set package-import-method clone-or-copy
      pnpm install --offline --ignore-scripts --frozen-lockfile
    )
    # The @bundle rule execs cli/node_modules/.bin/vite directly; patch its
    # shebang so it does not depend on /usr/bin/env node in the sandbox.
    patchShebangs cli/node_modules

    # Compile the OCaml CLI to JS via Melange and bundle with Vite
    # (`pnpm --dir cli bundle` == `dune build @bundle`, cli/dist/dune), then stage
    # the result to static/logseq-cli.js. The opam closure (dune, melange,
    # melange-*, humanize) is on PATH/OCAMLPATH via ocamlBuildInputs;
    # LOGSEQ_REVISION/LOGSEQ_BUILD_TIME (exported above) feed vite.config.mjs's
    # build defines.
    (
      cd cli
      dune build @bundle
    )
    node ./scripts/stage-cli-runtime.mjs

    # db-worker-node stays a shadow-cljs :node-script release (the OCaml CLI
    # spawns it at runtime), then vite-bundles via build-db-worker-node-bundle.mjs.
    clojure -Sdeps "$clj_sdeps" -M:cljs release db-worker-node
    node ./scripts/build-db-worker-node-bundle.mjs

    # Assemble the publishable package layout under dist/cli-package/. Upstream's
    # prepare-cli-package.mjs reads the OCaml bundle (cli/_build/default/dist/
    # logseq-cli.js + static/logseq-cli.js) plus the bundled db-worker and writes
    # the dist/logseq.js bin shim + runtime package.json.
    export CLI_PACKAGE_VERSION=${lib.escapeShellArg version}
    node ./scripts/prepare-cli-package.mjs

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    # Ship upstream's prepared package layout (dist/logseq.js bin shim,
    # static/logseq-cli.js, static/js/db-worker-node.js, package.json) plus the
    # offline-installed runtime node_modules so requires resolve at runtime.
    mkdir -p "$out/lib"

    # prepare-cli-package.mjs emits package.json/dist/static but no node_modules.
    # Fail loudly if upstream starts shipping one: the prune below would nest it
    # (node_modules/node_modules) and break `require` only at runtime.
    if [ -e dist/cli-package/node_modules ]; then
      echo "prepare-cli-package.mjs now ships dist/cli-package/node_modules; revisit the prune in build.nix" >&2
      exit 1
    fi
    # Copy only the runtime closure of the generated package.json out of the
    # monorepo install; the full workspace node_modules is ~10x larger with
    # build-only deps (electron, webpack, vite, ...).
    node ${./prune-cli-node-modules.mjs} dist/cli-package

    # node-gyp intermediates under keytar/build (config.gypi, Makefile, .deps,
    # obj.target) embed toolchain store paths (pnpm, npm, libsecret-dev,
    # glib-dev) and would drag those build tools into the runtime closure; the
    # runtime needs only the compiled binding. The unmatched-glob failure here
    # is deliberate: it flags an upstream keytar relocation.
    for keytar_build in dist/cli-package/node_modules/.pnpm/keytar@*/node_modules/keytar/build; do
      keytar_node="$keytar_build/Release/keytar.node"
      mv "$keytar_node" "$TMPDIR/keytar.node"
      rm -rf "$keytar_build"
      mkdir -p "$keytar_build/Release"
      mv "$TMPDIR/keytar.node" "$keytar_node"

      ${lib.optionalString stdenv.hostPlatform.isLinux ''
        # Keep libsecret resolution scoped to keytar.node instead of exporting
        # LD_LIBRARY_PATH from the public wrapper to every child process.
        libsecret_path="${lib.makeLibraryPath [ libsecret ]}"
        keytar_rpath="$(patchelf --print-rpath "$keytar_node")"
        case ":$keytar_rpath:" in
          *":$libsecret_path:"*) ;;
          *)
            patchelf --set-rpath "$libsecret_path''${keytar_rpath:+:$keytar_rpath}" "$keytar_node"
            ;;
        esac
        keytar_rpath="$(patchelf --print-rpath "$keytar_node")"
        case ":$keytar_rpath:" in
          *":$libsecret_path:"*) ;;
          *)
            echo "keytar.node lacks a libsecret RPATH; do not rely on LD_LIBRARY_PATH in the wrapper." >&2
            exit 1
            ;;
        esac
      ''}
    done

    # The prune must carry the keytar binding compiled in buildPhase; a miss
    # here would only surface at db-worker startup.
    if ! node -e 'require.resolve("keytar/build/Release/keytar.node", { paths: [process.argv[1]] })' dist/cli-package 2>/dev/null; then
      echo "pruned node_modules lost keytar/build/Release/keytar.node" >&2
      exit 1
    fi

    cp -a dist/cli-package "$out/lib/logseq-cli"

    # wrapper.nix pins $LOGSEQ_DB_WORKER_NODE_SCRIPT to this path. Fail loudly if
    # upstream's prepare-cli-package.mjs relocates the bundled worker, rather than
    # shipping a CLI whose doctor and db commands cannot locate it.
    if [ ! -f "$out/lib/logseq-cli/static/js/db-worker-node.js" ]; then
      echo "bundled db-worker-node.js missing at static/js/db-worker-node.js; update wrapper.nix" >&2
      exit 1
    fi

    runHook postInstall
  '';

  dontStrip = true;
  dontPatchELF = true;
}
