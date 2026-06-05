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
  # Upstream deleted `deps/cli` and migrated the CLI from an nbb sub-package to a
  # shadow-cljs release target in `src/main/logseq/cli`. The build now runs from
  # the repo root: `pnpm db-worker-node:release:bundle` needs vite + terser, and
  # the prepared CLI package needs better-sqlite3, keytar, ws, mldoc, etc., all
  # pinned by the root `pnpm-lock.yaml`.
  sourceRoot = src.name;
  pnpm = pnpm_10;
  fetcherVersion = 3;
  hash = cliPnpmDepsHash;
  # The root package.json pins `packageManager: pnpm@<exact version>`. When the
  # nixpkgs-provided pnpm doesn't match exactly, pnpm self-installs the
  # requested version into $HOME/.local/share before running any command, which
  # fails in sandboxed builds. The env var is consulted before any
  # package.json walk.
  env.npm_config_manage_package_manager_versions = "false";
}
