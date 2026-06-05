{
  cacert,
  cctools,
  clang_20,
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
  patchelf,
  pkg-config,
  pnpm_10,
  pnpmConfigHook,
  python3,
  stdenv,
  writeShellScript,
  xcbuild,
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
      version
      ;
  };
  cliBuilt = import ./build.nix {
    inherit
      cctools
      clang_20
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
      src
      stdenv
      version
      xcbuild
      ;
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

  # Expose the FODs so `scripts/update-nightly.sh` can target them
  # individually (`nix build .#logseq-cli.cliPnpmDeps` and `.cliCljDeps`).
  passthru = {
    inherit cliPnpmDeps cliCljDeps;
  };

  meta = {
    description = "Logseq CLI for DB graphs - graph management and queries";
    homepage = "https://github.com/logseq/logseq/tree/master/src/main/logseq/cli";
    license = lib.licenses.agpl3Plus;
    mainProgram = "logseq-cli";
    platforms = lib.platforms.linux ++ [ "aarch64-darwin" ];
  };
}
