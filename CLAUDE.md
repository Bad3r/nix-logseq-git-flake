# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Nix flake packaging two Logseq outputs: the **desktop app** (nightly Electron builds) and the **CLI** (DB graph management / MCP server). A GitHub Actions workflow builds Logseq from upstream source daily and publishes tarballs that the flake consumes. Linux x86_64 only.

## Common Commands

```bash
# Build packages
nix build .#logseq        # desktop app
nix build .#logseq-cli    # CLI tool

# Run directly
nix run .#logseq
nix run .#logseq-cli -- --help

# Validation (CI runs these on every push/PR)
nix flake check           # builds checks + evaluates flake
nix fmt                   # format all files (nixfmt, biome, prettier, shfmt)

# Linters (also run as lefthook pre-commit hooks)
nix run nixpkgs#deadnix -- --fail
nix run nixpkgs#statix -- check

# Dev shell (auto-installs lefthook hooks)
nix develop
nix develop -c lefthook run pre-commit
```

## Architecture

### Two Packages, One Flake

`flake.nix` produces three package outputs (`logseq`, `logseq-cli`, `default`→both) plus an overlay (`overlays.default`) and checks that verify each binary is executable. The formatter is `nixfmt`. The desktop derivation is named `logseqDesktop` internally (pname `logseq-desktop`) but exposed as `packages.logseq`; the `default` output is a `symlinkJoin` of both desktop and CLI.

### Desktop App — Manifest-Driven FHS Wrapper

The desktop package does **not** build Logseq from source. Instead:

1. `data/logseq-nightly.json` stores the tarball URL, SRI hash, version, and git rev. This manifest is auto-committed by the nightly CI workflow.
2. `lib/loadManifest.nix` validates the manifest (required keys: `tag`, `publishedAt`, `assetUrl`, `assetSha256`, `logseqRev`, `logseqVersion`; hash must start with `sha256-`).
3. `flake.nix` fetches the tarball via `fetchzip`, extracts it into `logseqTree`, then wraps it in a `buildFHSEnv` with libraries from `lib/runtime-libs.nix`.
4. A `launcher` shell script (inline in `flake.nix`) auto-detects NVIDIA vs Mesa via `/run/opengl-driver` and exports GPU environment variables before execing the FHS wrapper.
5. The final `stdenv.mkDerivation` assembles the launcher, desktop entry, and icon into one package. `passthru.fhsWithPackages` lets consumers extend the FHS.

### CLI — Yarn/Node Build from Source

`lib/cli.nix` builds `@logseq/cli` from the upstream monorepo:

1. `fetchFromGitHub` clones the full repo; `sourceRoot` is set to `deps/` because the CLI depends on sibling packages (outliner, db, graph-parser, common).
2. `fetchYarnDeps` creates a fixed-output derivation for offline yarn install (the `postPatch` cd's into `deps/cli` where `yarn.lock` lives).
3. Native deps (`python3`, `gcc`, `pkg-config`, `sqlite`) are needed to rebuild the `better-sqlite3` native addon.
4. A `substituteInPlace` patches `nbb_deps.js` to respect `NBB_CACHE_DIR` env var so the Nix store stays read-only.
5. A wrapper script sets `NBB_CACHE_DIR` to `$XDG_CACHE_HOME/logseq-cli/nbb/` before invoking `node cli.mjs`.

**When updating the CLI**: you must update both `src.hash` (the GitHub source hash) and `cliOfflineCache.hash` (the yarn deps FOD hash). Use `nix build` and let the hash mismatch errors give you the correct values.

## CI Workflows

- **`nightly.yml`** — Daily cron: clones upstream Logseq, compiles ClojureScript + Electron, packages tarball, creates GitHub release, updates `data/logseq-nightly.json`, runs `nix fmt` and `nix flake check`.
- **`validate.yml`** — Every push/PR: `nix fmt -- --check .` and `nix flake check`.
- **`flake-update.yml`** — Weekly cron (Sunday): `nix flake update`, format, check, auto-commit.

## Git Hooks (lefthook)

`lefthook.yml` manages pre-commit hooks via [lefthook](https://lefthook.dev/). Hooks are installed automatically when entering `nix develop`. The `scripts/lefthook-rc.sh` caches the PATH from `nix develop .#hooks` so hooks also work outside the dev shell.

```bash
# Enter dev shell (auto-installs lefthook)
nix develop

# Run hooks manually
nix develop -c lefthook run pre-commit
```

**Hooks** (run in priority order):
1. **formatting** — `nix fmt -- --fail-on-change` (treefmt with nixfmt, biome, prettier, shfmt). CI uses `--ci` instead, which also disables the cache and adjusts output for CI environments.
2. **linting** (parallel) — deadnix, statix (`*.nix`), actionlint (`.github/workflows/`), shellcheck (`*.sh`)
3. **file-hygiene** — trailing whitespace, EOF newline, merge conflicts, JSON/YAML validation

**Dev shells**:
- `devShells.default` — full dev shell with all hook tools
- `devShells.hooks` — minimal shell used by `lefthook-rc.sh` for PATH caching
