# AGENTS.md / CLAUDE.md

This file provides guidance to coding agents when working with this repository.

`CLAUDE.md` is a symlink to this file for Claude Code compatibility; keep the content tool-agnostic.

## Scope

- This repo packages Logseq nightly builds as a Nix flake for `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin`.
- Main outputs are `logseq` (desktop), `logseq-cli` (CLI), and `default` (both).
- Most implementation work happens in `modules/`, `lib/loadManifest.nix`, `lib/runtime-libs.nix`, `scripts/update-nightly.sh`, `scripts/render-nightly-release-notes.sh`, and `.github/workflows/nightly.yml`.

## Repo Map

- `flake.nix` is the small flake-parts/import-tree entrypoint.
- `modules/` contains auto-imported flake-parts modules for packages, checks, formatter, dev shells, hooks, overlays, and supported systems.
- `modules/_packages/`, `_checks/`, and `_hooks/` are helper trees ignored by import-tree because their paths include `/_`.
- `modules/_packages/logseq-nightly.nix` assembles the private package set exposed to flake modules as `logseqNightly`.
- `modules/_packages/desktop/assembly.nix` wires the desktop payload, upstream source, and OS-specific desktop derivation. Linux uses the FHS wrapper path; Darwin uses the `.app` bundle package path.
- `modules/_packages/desktop/package.nix` is the actual desktop derivation.
- `modules/_packages/desktop/package-darwin.nix` installs and re-signs the Darwin `.app` bundle.
- `data/logseq-nightly.json` is a validated manifest, not loose config.
- `lib/` contains generic helpers shared by flake modules, including manifest validation and runtime library lists.
- `lib/loadManifest.nix` enforces required keys and `sha256-` SRI hashes.
- `lib/runtime-libs.nix` feeds the Linux desktop FHS wrapper; `overlays/default.nix` stays intentionally small.
- `modules/_packages/logseq-cli/` builds the upstream CLI from the Logseq monorepo as a shadow-cljs `:node-script` release, with offline pnpm deps and an offline Clojure dependency tree (Maven jars plus tools.gitlibs git checkouts).
- `scripts/update-nightly.sh` regenerates manifest fields, CLI source/dependency hashes, and the CLI Clojure-deps hash.
- `scripts/render-nightly-release-notes.sh` renders release notes from the cloned upstream Logseq repo.
- `.actrc` is tracked local `act` configuration; `.act/` is runtime state and stays ignored.
- `.github/workflows/validate.yml` is the clearest snapshot of CI expectations.

## Architecture

### Nightly pipeline

The flake does **not** build Logseq Desktop from source inside Nix. It consumes per-system pre-packaged binary tarballs from a GitHub Release. Linux systems use the flat Electron payload wrapped in an FHS env with a desktop entry and icon. `aarch64-darwin` uses a top-level `Logseq.app` payload, installs it to `$out/Applications/Logseq.app`, re-signs the installed app with an ad-hoc signature, and exposes `$out/bin/logseq`. The CLI is built from source inside Nix on every supported system.

End-to-end data flow:

1. `.github/workflows/nightly.yml` -> `build` job runs as a `strategy.matrix` over Linux x64 (`ubuntu-24.04`), Linux arm64 (`ubuntu-24.04-arm`), and Darwin arm64 (`macos-26`), **without** Nix during upstream compilation. Each leg clones upstream `logseq/logseq`, installs upstream pnpm dependencies, runs `pnpm gulp:build && pnpm cljs:release-electron && pnpm db-worker-node:bundle && pnpm webpack-app-build && pnpm desktop:prepare-runtime-js` to populate `static/` and stage runtime JS under `static/js/`. Linux runs `pnpm electron:make` and packages `dist/linux*-unpacked` as `logseq-linux-<arch>-<version>.tar.gz`. Darwin verifies `rebuild:all` and `electron:make-macos-arm64`, runs `pnpm rebuild:all && pnpm electron:make-macos-arm64`, copies the single `dist/mac-arm64/*.app` into a clean top-level `Logseq.app` payload, ad-hoc signs it, then packages `logseq-darwin-arm64-<version>.tar.gz`. Each leg writes an SRI hash file; the x64 leg additionally writes shared `meta.txt` (version/revision/datestring) and rendered release notes, because matrix job `outputs` are unreliable.
2. `.github/workflows/nightly.yml` -> `publish-release` job downloads build artifacts, resolves shared metadata + per-system hashes, requires Linux and Darwin tarballs plus their SRI hash files, installs Nix + Cachix, publishes all three tarballs, then runs `bash scripts/update-nightly.sh`. The Darwin matrix leg is release-blocking, so a Darwin build failure or missing Darwin artifact prevents publishing. `workflow_dispatch` can set `publish_release=false` to validate the build matrix without creating a release or committing a manifest bump.
3. `scripts/update-nightly.sh` rewrites `data/logseq-nightly.json` with the per-system release URLs + SRI hashes (under `assets.<system>`), upstream rev, and CLI version. It requires `ASSET_URL_X86_64`, `ASSET_SHA256_X86_64`, `ASSET_URL_AARCH64`, `ASSET_SHA256_AARCH64`, `ASSET_URL_AARCH64_DARWIN`, and `ASSET_SHA256_AARCH64_DARWIN`. It resolves `cliPnpmDepsHash` and `cliCljDepsHash` with deliberate placeholder fixed-output builds, parsing the resulting `got: sha256-...` error from stderr and rewriting the manifest after each hash.
4. `nix flake check` validates the updated manifest through `lib/loadManifest.nix`, rebuilds both packages, then the `logseq-nightly-bot` auto-commits the manifest bump to `main`.

The manifest is the single source of truth for downstream consumers. Adding a field requires updating **both** `scripts/update-nightly.sh` (producer) **and** `lib/loadManifest.nix` (validator) in the same change.

### Manifest fan-out inside flake modules

- `modules/logseq-scope.nix` loads `data/logseq-nightly.json` through `lib/loadManifest.nix` and exposes the shared package set as a per-system module argument.
- `modules/_packages/desktop/payload.nix` selects the per-system desktop bundle from `manifest.assets.<system>` (`url` + `sha256`), keyed by `pkgs.stdenv.hostPlatform.system`, and throws on an unsupported system.
- `modules/_packages/desktop/tree.nix` branches by OS. Linux expects the flat Electron payload with an executable `logseq`; Darwin expects exactly one top-level `*.app` bundle containing `Contents/MacOS/Logseq` and `Contents/Resources/app.asar`.
- `modules/_packages/desktop/upstream-source.nix` fetches `logseq/logseq` at `manifest.logseqRev` with `manifest.cliSrcHash`; this source is shared by the desktop icon and CLI build.
- `modules/_packages/logseq-cli/` also reads `cliPnpmDepsHash`, `cliCljDepsHash`, and `cliVersion`. The pnpm hash feeds the offline pnpm store; the Clojure-deps hash pins a fixed-output derivation that resolves the `:cljs` alias classpath (Maven jars under `m2/` plus tools.gitlibs git checkouts under `gitlibs/`) so the shadow-cljs release compiles offline. The CLI builds from source on `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin`; these hashes are currently shared across systems (the Clojure deps are pure JVM/ClojureScript artifacts, and the pnpm fetch is expected to be platform-independent). If a non-x86_64 build ever reports a hash mismatch, split the affected hash per system in the manifest, validator, and producer together.

### Upstream layout assumptions

The bundle's internal layout is dictated by upstream's packaging tool and changes when upstream switches tools. Since `logseq/logseq#12517` (2026-04-17) migrated from electron-forge to electron-builder, the tarball contains a flat tree with:

- `logseq` (lowercase executable; earlier electron-forge builds shipped `Logseq`).
- `resources/app.asar` (app sources sealed, with no unpacked `resources/app/` tree).
- Chromium runtime libs, locales, swiftshader, etc.

`logseqTree` in `modules/_packages/desktop/tree.nix` expects the flat electron-builder payload on Linux and a single top-level `Logseq.app` payload on Darwin. Linux copies the flat tree directly and the FHS `runScript` executes `share/logseq/logseq`. Darwin copies the app to `Logseq.app`; `package-darwin.nix` later installs it under `$out/Applications/Logseq.app` and re-signs the installed copy. If upstream reintroduces a nested Linux bundle root, renames the Linux executable, or changes the Darwin app name/layout, fix tree normalization and the launcher/package path together. The Linux icon is fetched from `logseqSrc` (upstream repo at pinned rev), not extracted from the tarball, because asar-packed resources aren't filesystem-accessible.

When a nightly fails, first check whether upstream renamed a path, changed the packaging tool, or moved an expected file. The cleanest signal is usually a diff of upstream's `.github/workflows/build-desktop-release.yml` around the failing step.

### Desktop packaging

The Linux desktop package is wrapped in `pkgs.buildFHSEnv` because Electron expects a traditional `/lib`, `/usr/lib` filesystem layout for its Chromium runtime. `lib/runtime-libs.nix` lists the injected libraries. Extend it only when a runtime-load failure points to a missing `.so`. The Linux `launcher` shell script in `modules/_packages/desktop/launcher.nix` additionally sets NVIDIA PRIME and Mesa driver paths before execing the FHS env; GPU-related regressions belong there, not in `runtime-libs.nix`.

The Darwin desktop package does not use the FHS wrapper, Linux launcher, icon derivation, or desktop entry. The workflow removes copied extended attributes before tarballing the `.app`; the Nix package installs `Logseq.app`, ad-hoc signs the final store app, and exposes `bin/logseq` as a symlink to `Contents/MacOS/Logseq`. `validate-aarch64-darwin` builds the package, verifies its signature, and runs a bounded launch probe on a macOS runner when the Darwin manifest hash is real.

## Core Commands

```bash
nix develop
nix build .#logseq
nix build .#logseq-cli
nix build .#packages.aarch64-darwin.logseq-cli
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
nix build .#checks.x86_64-linux.logseq-runtime-assets
nix build .#checks.x86_64-linux.logseq
nix build .#checks.x86_64-linux.logseq-cli
nix build .#checks.x86_64-linux.logseq-cli-help
nix build .#checks.x86_64-linux.pre-commit-check
nix eval --accept-flake-config .#packages.aarch64-darwin.logseq.meta.mainProgram
nix eval --accept-flake-config .#packages.aarch64-darwin.logseq-cli.meta.mainProgram
nix build .#logseq
nix build .#logseq-cli
```

## Long-Running Local Workflow Check (takes over 25min)

Use this `act` command only when the user explicitly asks for local nightly workflow validation, or when changes materially affect the `nightly.yml` `build` job, `workflow_dispatch` inputs, dependency installation, cache/artifact paths, packaging, release-asset generation, or upstream desktop-build commands in a way that targeted Nix checks cannot cover. Do not run it eagerly after docs-only edits, formatting-only edits, manifest-only edits, metadata/comment-only edits, or small Nix/package changes that can be validated with the smaller checks above.

```bash
GITHUB_TOKEN="$(gh auth token)" \
  act workflow_dispatch -W .github/workflows/nightly.yml -j build \
  --input logseq_branch=master --input publish_release=false -s GITHUB_TOKEN \
  2>&1 | tee ".act/logs/nightly-build-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Prefer the lightest tightly scoped validation first: formatter for touched files, a relevant `nix build .#checks.x86_64-linux.<name>` attr, `nix flake check` for manifest/load-path changes, or one package build. Treat the `act` build as an expensive end-to-end confidence check, not the default finish step.

## Direct Lint Commands

```bash
nix run nixpkgs#deadnix -- --fail
nix run nixpkgs#statix -- check
nix-instantiate --parse path/to/file.nix >/dev/null
nix develop -c pre-commit run gitleaks --hook-stage manual
```

## One-File Formatting Commands

`treefmt` is the umbrella formatter. For one file, use the underlying tool:

```bash
nixfmt path/to/file.nix
dprint fmt path/to/file.json
dprint fmt path/to/file.md
dprint fmt path/to/file.toml
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

Required env vars for `scripts/update-nightly.sh`: `LOGSEQ_REV`, `LOGSEQ_VERSION`, `ASSET_URL_X86_64`, `ASSET_SHA256_X86_64`, `ASSET_URL_AARCH64`, `ASSET_SHA256_AARCH64`, `ASSET_URL_AARCH64_DARWIN`, `ASSET_SHA256_AARCH64_DARWIN`, `NIGHTLY_TAG`.

## What To Run After Common Changes

- `flake.nix` or `modules/**`: run `nix fmt`, `nix flake show --all-systems --accept-flake-config`, the relevant Darwin metadata evals when Darwin outputs are touched, and at least one targeted build or check attr.
- `modules/_packages/logseq-cli/**`: run `nix build .#logseq-cli` or `nix build .#checks.x86_64-linux.logseq-cli-help`; the smoke check runs `logseq-cli doctor` plus a db-worker spawn probe (`graph create` then `list page`), exercising the shadow-cljs runtime and the bundled `db-worker-node.js`. The worker requires `keytar`, whose native binding is built from source with node-gyp (`libsecret` on Linux); keychain operations additionally need a running secret service at runtime. Darwin CLI changes also need GitHub `validate-aarch64-darwin` because the local host is Linux.
- `lib/loadManifest.nix` or `data/logseq-nightly.json`: run `nix build .#checks.x86_64-linux.logseq-runtime-assets` for desktop ASAR layout changes, or `nix flake check` for broader manifest/load-path changes. For Darwin asset changes, use the `aarch64-darwin` runtime-assets check in CI once the Darwin hash is real.
- `flake.lock`: if the bump changes `git` or `zlib`, the CLI Clojure-deps FOD output can change bytes (its git deps are exploded to loose objects, whose encoding depends on those tools), so `nix build .#logseq-cli` fails with a `cliCljDepsHash` mismatch until `scripts/update-nightly.sh` re-resolves the hash; the nightly workflow is the only flow that re-resolves it automatically. Validate lock bumps with `nix build .#checks.x86_64-linux.logseq-cli` (or the `logseq-cli-help` check) before merging.
- `.github/workflows/*.yml` or `scripts/*.sh`: run the relevant formatter, then `nix develop -c pre-commit run --all-files` if practical. Use the long-running local `act` build only when the workflow or script change materially affects the nightly build path and smaller checks cannot cover it.
- Hook config changes: run `nix build .#checks.x86_64-linux.pre-commit-check`; for pre-push-only hooks, also run the specific hook with `nix develop -c pre-commit run <hook> --hook-stage pre-push --all-files`.

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
- PRs touching `.github/workflows/*` or `flake.lock` trigger a policy check that requires the `status(security-review-approved)` label.

### JSON, Markdown, and YAML

- Let `dprint` format JSON, Markdown, TOML, YAML, and XML.
- Do not format `.github/workflows/**` with `dprint`; rely on YAML validation and `actionlint` for workflow files.
- `statix` is wrapped to receive staged Nix filenames; do not switch it back to the built-in whole-tree hook unless that behavior is intentional.
- `nix-parse` runs `nix-instantiate --parse` on staged Nix files.
- `gitleaks` runs on `pre-push` and `manual`, not ordinary `pre-commit`.
- Keep manifest keys in lowerCamelCase.
- Do not hand-wrap files against formatter output.
- New auto-imported files under `modules/` must be visible to Git before flake evaluation; use explicit `git add -N <path>` when needed.

## Repo-Specific Advice

- Do not edit the `result` symlink; it is a build artifact.
- Treat `data/logseq-nightly.json` as generated data unless the task is specifically about manifest format or manifest values.
- When updating the CLI source revision flow, expect to update `cliSrcHash`, `cliPnpmDepsHash`, and `cliCljDepsHash`.
- When changing the CLI dependency flow (pnpm or Clojure deps), keep `modules/_packages/logseq-cli/`, `scripts/update-nightly.sh`, `lib/loadManifest.nix`, and `data/logseq-nightly.json` in sync.
- For local `act` runs, inspect jobs with `act -l -W .github/workflows/nightly.yml`; default to the safe `build` job unless the user explicitly wants the side-effectful `publish-release` path.
- `publish-release` creates/releases assets and can auto-commit a manifest bump back to `main`; after a successful live run, the local checkout may need `git pull --ff-only origin main`.
- The fastest trustworthy feedback is usually a targeted `nix build` or one check attr, not a full `nix flake check`.
- Before finishing, prefer `nix fmt` plus the smallest relevant build or check for the files you changed.
