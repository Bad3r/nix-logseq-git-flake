{
  cliBundlePnpmDepsHash,
  fetchPnpmDeps,
  pnpm_10,
  src,
  version,
}:
# The OCaml CLI bundles to a single CommonJS file with Vite, which lives in the
# `cli/` workspace's own lockfile (cli/pnpm-lock.yaml: vite + transit-js),
# separate from the monorepo root `pnpm-lock.yaml`. `dune build @bundle`
# (cli/dist/dune) execs `cli/node_modules/.bin/vite`, so this FOD populates the
# cli/ pnpm store offline. The root pnpm-deps FOD still supplies the db-worker
# and runtime closure (keytar, better-sqlite3, ws, @zvec, ...).
fetchPnpmDeps {
  pname = "logseq-cli-bundle";
  inherit version src;
  sourceRoot = "${src.name}/cli";
  pnpm = pnpm_10;
  fetcherVersion = 3;
  hash = cliBundlePnpmDepsHash;
  env.npm_config_manage_package_manager_versions = "false";
}
