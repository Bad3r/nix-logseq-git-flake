# nix-logseq-git-flake

Nix flake for Logseq nightly packages.

It packages the Logseq Desktop nightly artifacts built by this repository's
workflow and builds the Logseq CLI from upstream's OCaml/Melange source. The
current manifest is [data/logseq-nightly.json](data/logseq-nightly.json).

Supported systems:

- `x86_64-linux`
- `aarch64-linux`
- `aarch64-darwin`

## Outputs

| Output       | Binary       | Notes                                                 |
| ------------ | ------------ | ----------------------------------------------------- |
| `logseq`     | `logseq`     | Desktop app                                           |
| `logseq-cli` | `logseq-cli` | CLI for Logseq DB graphs                              |
| `default`    | both         | Symlink join of desktop and CLI packages              |
| overlay      | n/a          | Exposes the same packages under `pkgs.logseq-nightly` |

## Quick Use

```bash
nix run --accept-flake-config github:Bad3r/nix-logseq-git-flake#logseq
nix run --accept-flake-config github:Bad3r/nix-logseq-git-flake#logseq-cli -- --help
```

The flake advertises its Cachix cache through `nixConfig`, so
`--accept-flake-config` enables:

```nix
extra-substituters = [ "https://nix-logseq-git-flake.cachix.org" ];
extra-trusted-public-keys = [
  "nix-logseq-git-flake.cachix.org-1:DSBNW07PSRyCvS926tpIWahb53OIydwwZhsP6LhJNZo="
];
```

## Flake Usage

Add the input:

```nix
{
  inputs.logseq-nightly = {
    url = "github:Bad3r/nix-logseq-git-flake";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

Use the packages directly from a module where `inputs` and `pkgs` are in scope:

```nix
environment.systemPackages = [
  inputs.logseq-nightly.packages.${pkgs.stdenv.hostPlatform.system}.logseq
  inputs.logseq-nightly.packages.${pkgs.stdenv.hostPlatform.system}.logseq-cli
];
```

Or use the overlay:

```nix
nixpkgs.overlays = [ inputs.logseq-nightly.overlays.default ];

environment.systemPackages = [
  pkgs.logseq-nightly.logseq
  pkgs.logseq-nightly.logseq-cli
];
```

## CLI

Upstream's CLI self-identifies as `logseq`; this flake installs the wrapper as
`logseq-cli` so it can coexist with the desktop launcher.

```bash
logseq-cli --help
logseq-cli doctor
logseq-cli example <command>
```

`doctor` is a smoke check for the OCaml/Melange CLI runtime and the bundled
shadow-cljs `db-worker-node.js`. The db-worker requires `keytar`, whose native binding is
built from source with node-gyp (and `libsecret` on Linux); the
`logseq-cli-help` check boots the worker so a missing binding fails the build.

Current command groups include:

- Graph inspect and edit: `list`, `show`, `search`, `query`, `upsert`, `remove`.
- Graph management: `graph`, `graph backup`, `server`, `doctor`.
- Sync and auth: `sync`, `login`, `logout`.
- Utilities: `agent`, `completion`, `debug`, `example`, `skill`.

Global options include `-g/--graph`, `-o/--output`, `--root-dir`, `--config`,
`--timeout-ms`, `--profile`, `-v/--verbose`, and `--version`.

## Maintenance

`data/logseq-nightly.json` is generated data and is the source of truth for:

- per-system desktop artifact URLs and SRI hashes
- upstream Logseq revision and version
- CLI source, root pnpm, `cli/` bundle pnpm, and Clojure dependency hashes

`scripts/update-nightly.sh` rewrites the manifest during the nightly release
flow. Manifest schema changes must update both that producer and
[lib/loadManifest.nix](lib/loadManifest.nix).

Useful local checks:

```bash
nix build .#logseq
nix build .#logseq-cli
nix build .#checks.x86_64-linux.logseq-runtime-assets
nix build .#checks.x86_64-linux.logseq-cli-help
nix flake check --accept-flake-config --no-build --offline
nix fmt
```

Note: `logseq-cli` resolves its OCaml/Melange closure through opam-nix
import-from-derivation (IFD), so the `--no-build`/`--offline` check above still
realizes those intermediate opam derivations during evaluation; they must
already be built or substitutable.

The Darwin desktop package is validated by the `validate-aarch64-darwin`
workflow job, which builds the package on macOS, verifies the app signature, and
runs a bounded launch probe.

## License

[AGPL-3.0-or-later](LICENSE)
