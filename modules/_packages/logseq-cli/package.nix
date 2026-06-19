{
  cacert,
  cctools,
  clang_20,
  cliBundlePnpmDepsHash,
  cliCljDepsHash,
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
  writeShellScript,
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
      opamNix
      pkgs
      src
      system
      ;
  };
  cliBuilt = import ./build.nix {
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
  };
  wrapper = import ./wrapper.nix {
    inherit
      cliBuilt
      logseqNodejs
      writeShellScript
      ;
  };
in
stdenv.mkDerivation {
  pname = "logseq-cli";
  inherit version;

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin
    cp ${wrapper} $out/bin/logseq-cli
    chmod +x $out/bin/logseq-cli
  '';

  # Expose the FODs so `scripts/update-nightly.sh` can target them individually
  # (`nix build .#logseq-cli.cliPnpmDeps`, `.cliBundlePnpmDeps`, `.cliCljDeps`).
  passthru = {
    inherit cliPnpmDeps cliBundlePnpmDeps cliCljDeps;
    inherit (opamDeps) ocamlBuildInputs;
  };

  meta = {
    description = "Logseq CLI for DB graphs - graph management and queries";
    homepage = "https://github.com/logseq/logseq/tree/master/cli";
    license = lib.licenses.agpl3Plus;
    mainProgram = "logseq-cli";
    platforms = lib.platforms.linux ++ [ "aarch64-darwin" ];
  };
}
