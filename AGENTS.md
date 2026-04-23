# AGENTS.md

Repo guidance for coding agents working in `nix-logseq-git-flake`.

## Scope

- This repo packages Logseq nightly builds as a Nix flake for Linux `x86_64-linux`.
- Main outputs are `logseq` (desktop), `logseq-cli` (CLI), and `default` (both).
- Most implementation work happens in `flake.nix`, `lib/cli.nix`, `lib/loadManifest.nix`, `lib/runtime-libs.nix`, and `scripts/update-nightly.sh`.

## Repo Map

- `flake.nix` defines packages, checks, formatter, dev shells, and hook config.
- `data/logseq-nightly.json` is a validated manifest, not loose config.
- `lib/loadManifest.nix` enforces required keys and `sha256-` SRI hashes.
- `lib/cli.nix` builds the upstream CLI from the Logseq monorepo with offline Yarn deps.
- `lib/runtime-libs.nix` feeds the desktop FHS wrapper; `overlays/default.nix` stays intentionally small.
- `scripts/update-nightly.sh` regenerates manifest fields and CLI hashes.
- `.github/workflows/validate.yml` is the clearest snapshot of CI expectations.

## Core Commands

```bash
nix develop
nix build .#logseq
nix build .#logseq-cli
nix run .#logseq
nix run .#logseq-cli -- --help
nix fmt
nix fmt -- --ci
nix flake check
nix develop -c pre-commit run --all-files
```

## Build, Lint, and Test Reality

- There is no traditional unit or integration test suite here.
- Validation is done through flake evaluation, package builds, executable smoke checks, formatters, and hook-backed linters.
- When someone asks for a "single test", the closest equivalent is one flake check attr or one targeted package build.

## Smallest Useful Checks

```bash
nix build .#checks.x86_64-linux.logseq
nix build .#checks.x86_64-linux.logseq-cli
nix build .#checks.x86_64-linux.pre-commit-check
nix build .#logseq
nix build .#logseq-cli
```

## Direct Lint Commands

```bash
nix run nixpkgs#deadnix -- --fail
nix run nixpkgs#statix -- check
```

## One-File Formatting Commands

`treefmt` is the umbrella formatter. For one file, use the underlying tool:

```bash
nixfmt path/to/file.nix
biome format --write path/to/file.json
prettier --write path/to/file.md
prettier --write path/to/workflow.yml
shfmt -s -w -i 2 path/to/script.sh
```

## Flake and Manifest Maintenance

```bash
nix flake update
nix flake lock --update-input nixpkgs
nix run nixpkgs#flake-checker -- \
  --no-telemetry \
  --fail-mode \
  --check-outdated \
  --check-owner \
  --check-supported \
  flake.lock
bash scripts/update-nightly.sh
```

Required env vars for `scripts/update-nightly.sh`: `LOGSEQ_REV`, `LOGSEQ_VERSION`, `ASSET_URL`, `ASSET_HASH`, `NIGHTLY_TAG`.

## What To Run After Common Changes

- `flake.nix`: run `nix fmt` and at least one targeted build or check attr.
- `lib/cli.nix`: run `nix build .#logseq-cli` or `nix build .#checks.x86_64-linux.logseq-cli`.
- `lib/loadManifest.nix` or `data/logseq-nightly.json`: run `nix flake check`.
- `.github/workflows/*.yml` or `scripts/*.sh`: run the relevant formatter, then `nix develop -c pre-commit run --all-files` if practical.

## Code Style Guidelines

### General

- Prefer small, explicit changes over broad refactors.
- Preserve the current packaging-oriented structure; keep logic in focused files instead of spreading it across new abstractions.
- Keep comments short and only for non-obvious runtime, packaging, hook, or upstream-compatibility behavior.

### Nix Style

- Follow `nixfmt` output exactly; do not hand-format against it.
- Use `let ... in` when it makes dense expressions readable.
- Prefer explicit attrsets over clever abstraction unless repetition is clearly harmful.
- Add `meta` fields on derivations you introduce, and keep overlays minimal.

### Imports, Attrs, and Types

- Prefer `inherit` and `inherit (scope)` to avoid repeating attr names.
- Follow existing patterns like `inherit system`, `inherit version src`, and `inherit (manifest) ...`.
- Import local Nix files with explicit argument passing.
- Treat manifest JSON as schema-bound input; validate required keys and hash prefixes with explicit checks such as `throwIf` and `hasPrefix "sha256-"`.
- When adding manifest fields, update both the JSON producer and `lib/loadManifest.nix` in the same change.

### Naming

- Use `camelCase` for local Nix names like `logseqTree`, `runtimeLibList`, or `cliOfflineCache`.
- Use `kebab-case` for public package and check names like `logseq-cli` and `pre-commit-check`.
- Use uppercase `SNAKE_CASE` for shell environment variables.
- Prefer descriptive packaging-oriented names over short abbreviations.

### Error Handling

- In shell scripts, start with `set -euo pipefail`.
- Validate required env vars with `: "${VAR:?must be set}"`.
- Print actionable stderr messages before exiting.
- Fail loudly rather than silently skipping invalid state.
- Use `|| true` only for genuinely optional cleanup or best-effort operations.
- In embedded Python patching snippets, assert exact patch counts.

### Shell and Workflow Style

- Bash is acceptable and already used; quote variable expansions consistently.
- Prefer temporary files plus `mv` for rewrites and structure longer scripts into labeled phases.
- Keep shell indentation compatible with `shfmt -i 2`.
- Preserve the existing GitHub Actions style: explicit timeouts, concurrency groups, scoped permissions, and current major-pinned action versions.
- PRs touching `.github/workflows/*` or `flake.lock` trigger a policy check that requires the `security-review-approved` label.

### JSON, Markdown, and YAML

- Let `biome` format JSON.
- Let `prettier` format Markdown and YAML.
- Keep manifest keys in lowerCamelCase.
- Do not hand-wrap files against formatter output.

## Repo-Specific Advice

- Do not edit the `result` symlink; it is a build artifact.
- Treat `data/logseq-nightly.json` as generated data unless the task is specifically about manifest format or manifest values.
- When updating the CLI source revision flow, expect to update both `cliSrcHash` and `cliYarnDepsHash`.
- The fastest trustworthy feedback is usually a targeted `nix build` or one check attr, not a full `nix flake check`.
- Before finishing, prefer `nix fmt` plus the smallest relevant build or check for the files you changed.
