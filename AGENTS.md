# Repository Guidelines

## Project Structure & Module Organization

This repository packages Logseq nightly builds as a Nix flake for Linux `x86_64`.

- `flake.nix` defines packages, checks, dev shells, and the overlay.
- `lib/` contains packaging logic: `cli.nix` builds `logseq-cli`, `loadManifest.nix` validates the nightly manifest, and `runtime-libs.nix` lists desktop runtime libraries.
- `data/logseq-nightly.json` is the manifest consumed by the desktop package and updated by automation.
- `scripts/update-nightly.sh` regenerates manifest metadata and hashes.
- `overlays/default.nix` exposes `pkgs.logseq-nightly`.
- `.github/workflows/` contains validation, nightly build, flake update, and review automation.

## Build, Test, and Development Commands

- `nix build .#logseq` builds the desktop package.
- `nix build .#logseq-cli` builds the CLI package.
- `nix run .#logseq-cli -- --help` is the quickest CLI smoke test.
- `nix flake check` runs the repo checks declared in `flake.nix`, including executable checks and pre-commit hooks.
- `nix fmt` formats Nix, shell, JSON, Markdown, and YAML files.
- `nix develop` enters the dev shell and installs the pre-commit hook toolchain.
- `nix develop -c pre-commit run --all-files` runs the same hook stack locally.

## Coding Style & Naming Conventions

Let the formatter drive style. `nixfmt` formats `*.nix`, `biome` formats JSON and JS/TS, `prettier` formats Markdown/YAML, and `shfmt -i 2` formats shell scripts. Follow existing names and keep new files descriptive: packaging helpers live under `lib/`, automation scripts use kebab-case in `scripts/`, and manifest keys stay stable because `lib/loadManifest.nix` validates them strictly.

## Testing Guidelines

There is no standalone unit test tree. Validation is build-centric: run `nix flake check` before opening a PR, and run a targeted build for the package you changed. If you edit manifest or CLI packaging logic, also do a direct smoke test such as `nix run .#logseq-cli -- --help`.

## Commit & Pull Request Guidelines

History follows short Conventional Commit subjects such as `chore: bump nightly manifest`, `chore(deps): automated flake input update`, and `fix(cli): replace the brittle literal patch`. Keep subjects imperative and scoped when useful. PRs should describe which surface changed (`logseq`, `logseq-cli`, manifest, overlay, or workflow), note the validation commands you ran, and link related issues when applicable. Changes to `.github/workflows/*` or `flake.lock` are treated as sensitive in CI and require the `security-review-approved` label before merge.
