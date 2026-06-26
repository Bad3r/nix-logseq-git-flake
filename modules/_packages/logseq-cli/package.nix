{
  cacert,
  cctools,
  clang_20,
  cliBundlePnpmDepsHash,
  cliCljDepsHash,
  cliOpamPinOverrides,
  cliPnpmDepsHash,
  cliSrcHash,
  cliVersion,
  clojure,
  fetchFromGitHub,
  fetchPnpmDeps,
  git,
  gnumake,
  jdk,
  lib,
  libsecret,
  logseqNodejs,
  logseqRev,
  makeWrapper,
  opamNix,
  patchelf,
  pkg-config,
  pkgs,
  pnpm_10,
  pnpmConfigHook,
  python3,
  sqlite,
  stdenv,
  system,
  xcbuild,
  zstd,
}:
let
  version = cliVersion;
  src = import ./source.nix {
    inherit fetchFromGitHub cliSrcHash logseqRev;
  };
  cliPnpmDeps = import ./pnpm-deps.nix {
    inherit
      cliPnpmDepsHash
      fetchPnpmDeps
      pnpm_10
      src
      version
      ;
  };
  # Vite + transit-js for `dune build @bundle`, from cli/pnpm-lock.yaml.
  cliBundlePnpmDeps = import ./cli-pnpm-deps.nix {
    inherit
      cliBundlePnpmDepsHash
      fetchPnpmDeps
      pnpm_10
      src
      version
      ;
  };
  cliCljDeps = import ./clj-deps.nix {
    inherit
      cacert
      cliCljDepsHash
      clojure
      git
      jdk
      lib
      src
      stdenv
      ;
  };
  # OCaml 5.4.0 + melange* + humanize closure for the Melange CLI compile.
  opamDeps = import ./opam-deps.nix {
    inherit
      cliOpamPinOverrides
      lib
      opamNix
      pkgs
      src
      system
      ;
  };
in
# build.nix produces the single public `logseq-cli` derivation (bin + lib). The
# wrapper that pins the db-worker path and PATH is generated inside that
# derivation's installPhase.
import ./build.nix {
  inherit
    cctools
    clang_20
    cliBundlePnpmDeps
    cliCljDeps
    cliPnpmDeps
    clojure
    git
    gnumake
    jdk
    lib
    libsecret
    logseqNodejs
    logseqRev
    makeWrapper
    patchelf
    pkg-config
    pnpm_10
    pnpmConfigHook
    python3
    sqlite
    src
    stdenv
    version
    xcbuild
    zstd
    ;
  inherit (opamDeps) ocamlBuildInputs;
}
