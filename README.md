# nix-logseq-git-flake

Nix flake that packages **Logseq Desktop** (nightly Electron app) and **Logseq CLI** (graph management and MCP server) as first-class Nix packages.

The desktop app is built from the latest upstream commit via this repository's
[GitHub Actions nightly build](.github/workflows/nightly.yml), wrapped in an
opinionated FHS environment tuned for Electron workloads.

The CLI is built from the official `@logseq/cli` source, pinned to the same
upstream commit as the desktop app via the shared
[`data/logseq-nightly.json`](data/logseq-nightly.json) manifest. It provides
offline access to DB graphs for querying, exporting, and running an MCP server
without the desktop app.

> [!WARNING]
> This flake currently packages only Linux x86_64 builds. Additional platforms can be added if there is demand.

## Outputs

### Desktop App

| Output | Description |
|--------|-------------|
| `packages.${system}.logseq` | Standalone package with desktop entry and icons. |
| `packages.${system}.default` | Alias for `logseq`. |
| `apps.${system}.logseq` | `nix run` entry point. |
| `packages.${system}.logseq.fhs` | FHS environment (exposed via `passthru`). |
| `packages.${system}.logseq.fhsWithPackages` | Helper to extend the FHS with additional packages. |

### CLI

| Output | Description |
|--------|-------------|
| `packages.${system}.logseq-cli` | CLI package providing `logseq-cli` binary. |

All systems from `flake-utils.lib.defaultSystems` are built by default; the
default `nixpkgs` input tracks `nixos-unstable`, but you can point it at any
channel that provides the required runtime libraries.

> [!NOTE]
> The flake pins `nixpkgs` to `nixos-unstable` when its inputs aren't overridden.
> To reuse the caller's inputs instead, add `follows` entries:
>
> ```nix
> inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
> inputs.logseq.url = "github:your-user/nix-logseq-git-flake";
> inputs.logseq.inputs.nixpkgs.follows = "nixpkgs";
> inputs.logseq.inputs.flake-utils.follows = "flake-utils";
> ```

## Quick start

### Desktop App

```bash
# Run Logseq from the flake
nix run .#logseq

# Launch inside a shell without installing
nix shell .#logseq --command logseq
```

### CLI

```bash
# Run the CLI
nix run .#logseq-cli -- --help

# List local graphs
nix run .#logseq-cli -- list

# Query a graph
nix run .#logseq-cli -- search -g Whim "NixOS"

# Start MCP server against a local graph
nix run .#logseq-cli -- mcp-server -g Whim
```

The CLI binary is named `logseq-cli` to avoid collision with the desktop `logseq` binary.

## CLI Usage

The CLI reads DB graphs directly via SQLite -- no desktop app required.

### Available Commands

| Command | Description |
|---------|-------------|
| `logseq-cli list` | List all local graphs |
| `logseq-cli show <graph>` | Graph info (schema version, creation date) |
| `logseq-cli search -g <graph> "<term>"` | Text search |
| `logseq-cli query -g <graph> '<datalog>'` | Datalog query |
| `logseq-cli export -g <graph>` | Export as Markdown |
| `logseq-cli export-edn -g <graph>` | Export as EDN |
| `logseq-cli import-edn -g <graph> -f <file>` | Import EDN into graph |
| `logseq-cli validate -g <graph>` | Validate graph integrity |
| `logseq-cli mcp-server -g <graph>` | Start MCP server |

### MCP Server

Run an MCP server against a local graph for AI assistant integration:

```bash
# HTTP transport (default, port 12315)
logseq-cli mcp-server -g Whim

# Stdio transport (for Claude Desktop)
logseq-cli mcp-server -g Whim -s
```

**MCP tools provided:** `listPages`, `getPage`, `listTags`, `listProperties`, `searchBlocks`, `upsertNodes`.

#### Claude Desktop Configuration

```json
{
  "mcpServers": {
    "logseq": {
      "command": "logseq-cli",
      "args": ["mcp-server", "-g", "Whim", "-s"]
    }
  }
}
```

### Datalog Queries

The `query` command supports Datalog queries directly against local graphs. Use `-p` for human-readable property values:

```bash
# Find all blocks tagged with "Link" where Category is "NixOS"
logseq-cli query -g Whim -p \
  '[:find (pull ?b [:block/uuid :block/title
                    {:block/tags [:block/title]}
                    {:user.property/Category [:block/title]}])
    :where
    [?b :block/tags ?t]
    [?t :block/title "Link"]
    [?b :user.property/Category ?cat]
    [?cat :block/title "NixOS"]]'
```

> [!NOTE]
> The first run of the CLI downloads ClojureScript dependencies (~30s). These are cached in `$XDG_CACHE_HOME/logseq-cli/nbb/` for subsequent runs.

## Customizing the Desktop Runtime

The desktop launcher wraps Logseq in a `buildFHSEnv` populated with libraries
defined in [`lib/runtime-libs.nix`](lib/runtime-libs.nix) (GTK, PipeWire,
OpenGL, VA-API, etc.). To add extra tools, extend the wrapper:

```nix
{ inputs, pkgs, ... }:
let
  logseqPkg = inputs.nix-logseq-git-flake.packages.${pkgs.system}.logseq;
in {
  programs.logseq = {
    package = logseqPkg;
    fhs = logseqPkg.fhsWithPackages (pkgs: with pkgs; [
      aspell
      nodePackages.typescript-language-server
    ]);
  };
}
```

The launcher detects `/run/opengl-driver` and exports the environment variables
that NVIDIA's proprietary stack expects (`__NV_PRIME_RENDER_OFFLOAD`,
`LIBVA_DRIVER_NAME`, etc.). On machines without that path it falls back to Mesa.

## Troubleshooting

- **GPU mismatches**: The wrapper assumes that your running kernel module and the
  libraries in `/run/opengl-driver` belong to the same driver version. If ANGLE
  reports "Invalid visual ID requested," or NVML complains about mismatched
  versions, reboot (or reload the NVIDIA modules).
- **CLI first-run slow**: The first invocation downloads ClojureScript
  dependencies. Subsequent runs use the cache.

## CI pipelines

- [Nightly build](.github/workflows/nightly.yml) builds Logseq from upstream `master`, publishes the tarball, and runs [`scripts/update-nightly.sh`](scripts/update-nightly.sh) to compute all manifest fields (desktop hash, CLI source hash, yarn deps hash, CLI version) into `data/logseq-nightly.json`.
- [Validate](.github/workflows/validate.yml) runs formatting and static checks on every push/PR.
- [Flake Update](.github/workflows/flake-update.yml) updates `flake.lock` weekly (Sunday cron).

## License

This repository is released under the GNU Affero General Public License
v3.0 or later (matching Logseq's upstream license). See [LICENSE](LICENSE) for
the full text.
