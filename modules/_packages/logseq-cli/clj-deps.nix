{
  cacert,
  clojure,
  cliCljDepsHash,
  git,
  jdk,
  lib,
  src,
  stdenv,
}:
# Fixed-output derivation that populates a Maven local repository (`m2/`) and
# Clojure git-deps checkouts (`gitlibs/libs/`) for the `:cljs` alias in
# upstream `deps.edn`. The shadow-cljs release of the `logseq-cli` target needs
# these on the classpath, but resolving them touches Maven Central, Clojars,
# and several `:git/url` forks (datascript, malli, glogi, hsx, cljs-time,
# cljc-fsrs, cljs-http-missionary, logseq-schema), so the fetch must happen in
# an FOD with network access.
stdenv.mkDerivation {
  # Unversioned name on purpose: this FOD's store path must stay stable across
  # nightlies so a single Cachix push stays valid until the content
  # (cliCljDepsHash) actually changes. A per-nightly version churns the path
  # daily, re-uploading an identical Maven + gitlibs tree and leaving consumers
  # pinned to an older commit on a cache miss. Mirrors fetchPnpmDeps, which
  # names cliPnpmDeps `logseq-cli-pnpm-deps` without a version.
  name = "logseq-cli-clj-deps";
  inherit src;

  nativeBuildInputs = [
    clojure
    jdk
    git
    cacert
  ];

  # FOD: allow network for Maven/git dependency resolution.
  impureEnvVars = lib.fetchers.proxyImpureEnvVars;
  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  outputHash = cliCljDepsHash;

  buildPhase = ''
    runHook preBuild

    export HOME="$TMPDIR/home"
    export GITLIBS="$TMPDIR/gitlibs"
    mkdir -p "$HOME"

    # `-A:cljs -P` mirrors upstream CI (.github/workflows/deps-cli.yml): it
    # downloads the full classpath (Maven jars + git libs) without running a
    # build. The deps/* local roots ship in `src`, so only remote deps fetch.
    clojure -Sdeps "{:mvn/local-repo \"$TMPDIR/m2\"}" -A:cljs -P

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    cp -r "$TMPDIR/m2" "$out/m2"

    # Maven writes resolver bookkeeping that embeds timestamps and remote repo
    # URLs (including SNAPSHOT `maven-metadata*.xml`); drop it so the output
    # hash stays stable across fetches.
    find "$out/m2" \
      \( -name '_remote.repositories' \
      -o -name '_maven.repositories' \
      -o -name '*.lastUpdated' \
      -o -name 'maven-metadata*.xml' \
      -o -name 'resolver-status.properties' \) -delete

    # tools.gitlibs needs both the `libs/<coord>/<sha>` worktrees and the
    # `_repos/<url>` clones to resolve the classpath offline. Those clones store
    # GitHub-served pack files whose bytes vary between fetches, and the git
    # worktree bookkeeping embeds mtimes and absolute build-dir paths, all of
    # which would make this FOD's hash unstable. Normalize the tree so the
    # output is byte-reproducible on every platform.
    cp -r "$TMPDIR/gitlibs" "$out/gitlibs"
    shopt -s nullglob
    if [ -d "$out/gitlibs/_repos" ]; then
      while IFS= read -r -d "" objects; do
        repo="$(dirname "$objects")"
        export GIT_DIR="$repo"
        # Explode packs into content-addressed loose objects (deterministic for
        # a fixed git/zlib), dropping the non-reproducible pack/idx/rev files.
        # If a nixpkgs bump changes git/zlib loose-object bytes,
        # scripts/update-nightly.sh re-resolves cliCljDepsHash on the next bump.
        # The FOD's non-interactive bash lacks `compgen`, so glob with nullglob
        # set; an empty match yields an empty array rather than a literal.
        packs=( "$repo"/objects/pack/*.pack )
        if [ "''${#packs[@]}" -gt 0 ]; then
          mkdir "$repo/.unpack"
          mv "$repo"/objects/pack/*.pack "$repo/.unpack/"
          # Clear all residual pack metadata (idx/rev, plus any stray bitmap,
          # multi-pack-index, or .keep), keeping the directory itself; only
          # loose objects from the unpack below may remain under objects/.
          rm -rf "$repo"/objects/pack/*
          for pack in "$repo"/.unpack/*.pack; do
            git unpack-objects -q <"$pack"
          done
          rm -rf "$repo/.unpack"
        fi
        # Regenerable / timestamp-bearing metadata, plus the git template
        # `hooks` whose sample scripts carry nixpkgs-patched perl/bash
        # store-path shebangs (an FOD must not reference store paths).
        rm -rf "$repo/objects/info" "$repo/logs" "$repo/hooks" \
          "$repo/FETCH_HEAD" "$repo/ORIG_HEAD"
        if [ -d "$repo/worktrees" ]; then
          find "$repo/worktrees" -depth \
            \( -name index -o -name logs -o -name ORIG_HEAD -o -name FETCH_HEAD \) \
            -exec rm -rf {} +
        fi
        unset GIT_DIR
      done < <(find "$out/gitlibs/_repos" -type d -name objects -print0)
    fi
    shopt -u nullglob

    # The git worktree gitlinks (`libs/**/.git` and `_repos/**/worktrees/*/gitdir`)
    # hold the absolute build-dir path, which varies by platform. Rewrite it to a
    # fixed placeholder; build.nix substitutes the real location back before
    # running Clojure.
    while IFS= read -r -d "" link; do
      substituteInPlace "$link" --replace-fail "$TMPDIR/gitlibs" "@GITLIBS@"
    done < <(grep -rFIlZ "$TMPDIR/gitlibs" "$out/gitlibs" 2>/dev/null || true)

    runHook postInstall
  '';

  dontFixup = true;
}
