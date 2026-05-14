{
  cliPnpmDepsHash,
  fetchPnpmDeps,
  pnpm_10,
  src,
  version,
}:
fetchPnpmDeps {
  pname = "logseq-cli";
  inherit version src;
  sourceRoot = "${src.name}/deps/cli";
  pnpm = pnpm_10;
  fetcherVersion = 3;
  hash = cliPnpmDepsHash;
  # Both source/package.json and source/deps/cli/package.json pin
  # `packageManager: pnpm@<exact version>`. When the nixpkgs-provided pnpm
  # doesn't match exactly, pnpm self-installs the requested version into
  # $HOME/.local/share before running any command, which fails in sandboxed
  # builds. The env var is consulted before any package.json walk.
  env.npm_config_manage_package_manager_versions = "false";
}
