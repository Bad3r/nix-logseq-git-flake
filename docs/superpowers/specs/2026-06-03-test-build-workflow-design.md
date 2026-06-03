# Test-build workflow design

Date: 2026-06-03
Status: approved, pending implementation plan

## Problem

Changes that affect the nightly build path (upstream compile commands, packaging,
release-asset generation, `scripts/update-nightly.sh`, `lib/loadManifest.nix`,
the flake itself) can only be exercised end-to-end by `.github/workflows/nightly.yml`.
That workflow either:

- builds all three arches but skips the entire publish pipeline
  (`workflow_dispatch` + `publish_release=false`), or
- runs the full publish pipeline and, on success, **creates a real
  `nightly-<date>` release and commits the regenerated manifest to `main`** -
  which is exactly what downstream consumers pick up.

There is no way to exercise the publish side (`gh release create` ->
`scripts/update-nightly.sh` -> `nix flake check` against freshly published
assets) from a feature branch without risking a real release or a manifest
commit to `main`. That publish side is the part that breaks most often and
cannot be validated without a real, fetchable release.

## Key facts that shape the design

- **Downstream pickup is driven by the manifest commit to `main`**, not by the
  GitHub Release itself. Downstream Nix consumers read
  `data/logseq-nightly.json`; the release tarballs are reached only through the
  URLs in that committed manifest. A published release that is not referenced by
  the committed manifest is invisible to downstream.
- **Nix fetches release assets unauthenticated.** A _draft_ release will not work
  for a flake check, because draft-release assets require auth. The test release
  must be a published `--prerelease`.
- **`nix flake check` in `publish-release` already validates a dirty, modified-
  but-uncommitted manifest** (the commit happens after the check). Because
  `data/logseq-nightly.json` is a tracked file, Nix's dirty-tree evaluation sees
  the regenerated content. The test job reuses this property: artifact-only, no
  commit, and the check still sees the regenerated manifest.
- **A local `uses: ./.github/workflows/...` reference resolves to the same commit
  as the caller.** Dispatching the test workflow from a feature branch pulls that
  branch's build steps, flake, and scripts.
- **A `workflow_dispatch` workflow must exist on the default branch to be
  dispatchable.** The test harness must land on `main` once (inert there:
  dispatch-only), after which it can run against any feature branch.

## Goals

- Exercise the same build steps as nightly on all three supported systems
  (`x86_64-linux`, `aarch64-linux`, `aarch64-darwin`), with zero duplication of
  those steps.
- Exercise the publish + manifest-regen + flake-check pipeline against a real,
  fetchable release.
- Guarantee zero downstream impact and no leftover state.
- Be dispatchable against an arbitrary feature branch.

## Non-goals

- Replacing or changing nightly's real release behavior.
- Per-arch desktop fetch validation beyond what nightly's `publish-release`
  already does (x64 flake check only). Per-arch validation remains in
  `validate.yml`.
- Committing a manifest bump anywhere (not to `main`, not to the feature branch).

## Architecture

Approach: extract nightly's build into a reusable `workflow_call` workflow, then
have both the production nightly workflow and a new test workflow call it.

### 1. New `.github/workflows/build-desktop.yml` (reusable)

- `on: workflow_call` only.
- Input: `logseq_branch` (string, required false, default `master`).
- Contains the current `resolve-revision` and `build` matrix jobs, moved verbatim
  from `nightly.yml`. The build steps must remain byte-identical (pure relocation).
- Build-time env (`NODE_VERSION`, `PNPM_VERSION`, `JAVA_VERSION`,
  `CLOJURE_VERSION`) is declared here, because a top-level `env:` block in the
  caller does not cross the `workflow_call` boundary. `LOGSEQ_BRANCH` becomes the
  `logseq_branch` input.
- No `outputs:` block. Metadata flows through artifacts exactly as today
  (`meta.txt`, `hash-*.txt`, the three tarballs, `release-notes.md`), consistent
  with the existing "matrix job outputs are unreliable" note.
- `permissions: contents: read`.

### 2. `.github/workflows/nightly.yml` (minimal edit)

- Replace the inline `resolve-revision` + `build` jobs with a single caller job:

  ```yaml
  build:
    uses: ./.github/workflows/build-desktop.yml
    with:
      logseq_branch: ${{ github.event.inputs.logseq_branch || 'master' }}
  ```

- `publish-release`, `report-failure`, and `report-recovery` are unchanged.
  `needs: build` and `needs.build.result` / `needs['publish-release'].result`
  still resolve when `build` is a reusable-workflow call job.
- The top-level build env vars move into `build-desktop.yml`; the
  `publish_release` input and the publish job stay as they are.

### 3. New `.github/workflows/test-build.yml` (caller, dispatch-only)

- `on: workflow_dispatch` with input `logseq_branch` (default `master`). No
  `schedule` trigger: it never runs on cron.
- `permissions: contents: write` (only to create and delete its own test
  release + tag).
- `build:` job -> `uses: ./.github/workflows/build-desktop.yml` (same reusable
  build, all three arches).
- `publish-test:` job (`needs: build`) with its own concurrency group
  `repo-test-publish-${{ github.ref }}` (cancel-in-progress), disjoint from
  `repo-main-writer`.

#### `publish-test` data flow

1. `checkout` the dispatched ref (the feature branch under test).
2. `gh run download "${{ github.run_id }}"` to fetch build artifacts.
   Reusable-workflow jobs share the caller's `run_id`, so their artifacts are
   retrievable here.
3. Resolve metadata from `meta.txt` and the `hash-*.txt` files (same parsing as
   `publish-release`). Build a disjoint tag
   `test-${datestring}-${{ github.run_id }}` (never `nightly-*`, unique per run).
4. Install Nix. Configure Cachix with `skipPush: true`: read the public cache to
   speed the CLI build, never push test-branch artifacts into it.
5. `gh release create <test-tag> --prerelease --latest=false <tarballs>` -
   published so Nix can fetch unauthenticated, but never marked "latest".
   Prefix with a best-effort `gh release delete <test-tag> -y || true` for
   idempotent same-run retries.
6. `bash scripts/update-nightly.sh` with the test URLs/hashes and
   `NIGHTLY_TAG=<test-tag>`. This regenerates `data/logseq-nightly.json` and
   resolves `cliSrcHash`, `cliPnpmDepsHash`, and `cliCljDepsHash`.
7. `nix fmt` then `nix flake check` against the test release (x64, mirroring
   `publish-release`).
8. Upload the regenerated `data/logseq-nightly.json` plus its `git diff` as a
   `test-manifest` artifact. No commit, no push, anywhere.
9. `if: always()` cleanup: `gh release delete <test-tag> --cleanup-tag -y || true`.

## Isolation guarantees

| Vector                           | Guard                                               |
| -------------------------------- | --------------------------------------------------- |
| Manifest commit to `main`        | Never committed: artifact-only                      |
| Clobbering real `nightly-<date>` | Disjoint `test-*` tag namespace                     |
| Becoming "latest" release        | `--prerelease --latest=false`                       |
| Leftover tags/releases           | `if: always()` delete + `--cleanup-tag`             |
| Blocking real releases           | Separate concurrency group (not `repo-main-writer`) |
| Cache pollution                  | `skipPush: true`                                    |

## Caveats (documented, not blockers)

- **One-time landing.** `test-build.yml` and `build-desktop.yml` must merge to
  `main` once for the test workflow to become dispatchable. It is inert on `main`
  (dispatch-only). After that, run it with
  `gh workflow run test-build.yml --ref <branch>` and it uses that branch's code.
- **Sensitive-change policy.** These are `.github/workflows/*` edits, so the
  introducing PR needs the `status(security-review-approved)` label and CODEOWNER
  approval.
- **Per-arch fetch coverage.** The flake check runs on x64 only, mirroring
  nightly's `publish-release`. The aarch64/darwin tarballs are built in the matrix
  but their fetch+hash is not re-validated here.

## Validation plan

- `actionlint` on all three workflow files
  (`build-desktop.yml`, `nightly.yml`, `test-build.yml`).
- Confirm the relocated `resolve-revision` + `build` steps in `build-desktop.yml`
  are byte-identical to nightly's current steps (pure relocation; diff to verify).
- Real end-to-end: after the harness lands on `main`, dispatch `test-build.yml`
  against a feature branch and confirm:
  - all three arch builds succeed,
  - the `test-*` prerelease is created, the flake check passes against it, and
  - the `test-*` release and tag are deleted by the cleanup step.

## Resolved decisions

- Structure: reusable build workflow (Approach B), not an inline mode in
  `nightly.yml` and not a standalone copy.
- Regenerated manifest: artifact-only, no git writes.
- Test release lifecycle: auto-delete after the flake check.
