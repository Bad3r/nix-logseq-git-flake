{
  babashka,
  cacert,
  cctools,
  cliPnpmDepsHash,
  cliSrcHash,
  cliVendorHash,
  cliVersion,
  fetchFromGitHub,
  fetchPnpmDeps,
  git,
  gnumake,
  lib,
  logseqNodejs,
  logseqRev,
  pkg-config,
  pnpm_10,
  pnpmConfigHook,
  python3,
  sqlite,
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
  cliVendor = import ./vendor.nix {
    inherit
      babashka
      cacert
      cliPnpmDeps
      cliVendorHash
      git
      lib
      logseqNodejs
      pnpm_10
      pnpmConfigHook
      src
      stdenv
      version
      ;
  };
  cliBuilt = import ./build.nix {
    inherit
      cliPnpmDeps
      cliVendor
      cctools
      gnumake
      lib
      logseqNodejs
      pkg-config
      pnpm_10
      pnpmConfigHook
      python3
      sqlite
      src
      stdenv
      version
      xcbuild
      ;
  };
  wrapper = import ./wrapper.nix {
    inherit cliBuilt logseqNodejs writeShellScript;
  };
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

  # Expose the FODs so `scripts/update-nightly.sh` can target them
  # individually (`nix build .#logseq-cli.cliPnpmDeps` and `.cliVendor`).
  passthru = {
    inherit cliPnpmDeps cliVendor;
  };

  meta = {
    description = "Logseq CLI for DB graphs - MCP server and graph management";
    homepage = "https://github.com/logseq/logseq/tree/master/deps/cli";
    license = lib.licenses.agpl3Plus;
    mainProgram = "logseq-cli";
    platforms = lib.platforms.linux ++ [ "aarch64-darwin" ];
  };
}
