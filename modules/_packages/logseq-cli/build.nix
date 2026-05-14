{
  cliPnpmDeps,
  cliVendor,
  gcc,
  gnumake,
  nodejs_22,
  pkg-config,
  pnpm_10,
  pnpmConfigHook,
  python3,
  sqlite,
  src,
  stdenv,
  version,
}:
stdenv.mkDerivation {
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

    # Install the full deps tree (cli + sibling local deps).
    mkdir -p $out
    cp -r . $out/

    # Wire up vendor sources next to cli/src so nbb-logseq can resolve
    # logseq.common.graph-dir etc. at runtime.
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
}
