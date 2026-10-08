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
# upstream `deps.edn`. The shadow-cljs release of the `db-worker-node` target needs
# these on the classpath, but resolving them touches Maven Central, Clojars,
# and the GitHub repos behind the `:git/url` deps, so the fetch must happen in
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
    # Darwin builds run unsandboxed by default; keep a host /etc/gitconfig
    # (core.autocrlf, ...) from rewriting the shipped checkouts.
    export GIT_CONFIG_NOSYSTEM=1
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

    # tools.gitlibs clones each git dep with `git clone --mirror`, which also
    # fetches every branch, tag, and GitHub `refs/pull/*` ref. Those move with
    # upstream activity (GitHub recomputing one `refs/pull/<n>/merge` commit is
    # enough), so shipping the clones would make this hash go stale within a
    # day. Ship only the `libs/<lib>/<sha>` checkouts, which the pinned SHAs
    # fully determine, minus their `.git` gitlinks (absolute build-dir paths),
    # plus an empty `_repos/<url>/config` per clone: tools.gitlibs takes that
    # file as an existing clone and serves a full-SHA coord from its checkout
    # without running git.
    mkdir -p "$out/gitlibs"
    cp -r "$TMPDIR/gitlibs/libs" "$out/gitlibs/libs"
    find "$out/gitlibs/libs" -mindepth 4 -maxdepth 4 -name .git -delete
    while IFS= read -r -d "" objects; do
      stub="$out/gitlibs/$(dirname "''${objects#"$TMPDIR/gitlibs/"}")"
      mkdir -p "$stub"
      touch "$stub/config"
    done < <(find "$TMPDIR/gitlibs/_repos" -type d -name objects -prune -print0)

    # The stubs cannot serve a coord that needs git history: a `:git/tag`, or
    # two SHAs of a lib the root deps.edn does not pin, which tools.deps orders
    # by ancestry. Re-resolve the classpath against this output's gitlibs with
    # git disabled so such a coord fails here rather than in the offline build.
    if ! GITLIBS="$out/gitlibs" GITLIBS_COMMAND=false \
      clojure -Sforce -Sdeps "{:mvn/local-repo \"$TMPDIR/m2\"}" -Spath -M:cljs >/dev/null; then
      echo "clj-deps: the :cljs classpath does not resolve from the gitlibs stubs with git disabled (tools.deps error above); see the comment on this check in modules/_packages/logseq-cli/clj-deps.nix" >&2
      exit 1
    fi

    runHook postInstall
  '';

  dontFixup = true;
}
