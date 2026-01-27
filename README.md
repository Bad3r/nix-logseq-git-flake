# nix-logseq-git-flake

Nix flake packaging **Logseq Desktop** (nightly) and **Logseq CLI** (DB graph management / MCP server) from upstream `master`.

> [!WARNING]
> Linux x86_64 only. [Open an issue](https://github.com/Bad3r/nix-logseq-git-flake/issues) to request other platforms.

## Packages

| Package      | Binary       | Description                                  |
| ------------ | ------------ | -------------------------------------------- |
| `logseq`     | `logseq`     | Desktop app with FHS wrapper                 |
| `logseq-cli` | `logseq-cli` | CLI for DB graphs: query, export, MCP server |
| `default`    | both         | Desktop app + CLI combined                   |

## Installation

### Try Without Installing

```bash
nix run github:Bad3r/nix-logseq-git-flake#logseq
nix run github:Bad3r/nix-logseq-git-flake#logseq-cli -- --help
```

### Flake Input

```nix
{
  inputs.logseq-nightly.url = "github:Bad3r/nix-logseq-git-flake";
  # optional: share nixpkgs
  inputs.logseq-nightly.inputs.nixpkgs.follows = "nixpkgs";

  # in your NixOS module:
  environment.systemPackages = [
    inputs.logseq-nightly.packages.${pkgs.system}.logseq
    inputs.logseq-nightly.packages.${pkgs.system}.logseq-cli
  ];
}
```

### Overlay

```nix
{
  nixpkgs.overlays = [ inputs.logseq-nightly.overlays.default ];
  environment.systemPackages = [
    pkgs.logseq-nightly.logseq
    pkgs.logseq-nightly.logseq-cli
  ];
}
```

## CLI Reference

### Commands

| Command                                      | Description                                |
| -------------------------------------------- | ------------------------------------------ |
| `logseq-cli list`                            | List local graphs                          |
| `logseq-cli show <graph>`                    | Graph info (schema version, creation date) |
| `logseq-cli search -g <graph> "<term>"`      | Full-text search                           |
| `logseq-cli query -g <graph> '<datalog>'`    | Datalog query                              |
| `logseq-cli export -g <graph>`               | Export as Markdown                         |
| `logseq-cli export-edn -g <graph>`           | Export as EDN                              |
| `logseq-cli import-edn -g <graph> -f <file>` | Import EDN into graph                      |
| `logseq-cli validate -g <graph>`             | Validate graph integrity                   |
| `logseq-cli mcp-server -g <graph>`           | Start MCP server                           |

### MCP Server

```bash
# HTTP transport (default, port 12315)
logseq-cli mcp-server -g MyGraph

# Stdio transport (for Claude Desktop / Claude Code)
logseq-cli mcp-server -g MyGraph -s
```

MCP tools provided: `listPages`, `getPage`, `listTags`, `listProperties`, `searchBlocks`, `upsertNodes`.

#### Claude Desktop Configuration

Add to `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "logseq": {
      "command": "logseq-cli",
      "args": ["mcp-server", "-g", "MyGraph", "-s"]
    }
  }
}
```

#### Claude Code Configuration

```bash
claude mcp add logseq -- logseq-cli mcp-server -g MyGraph -s
```

> [!NOTE]
> The first CLI run downloads ClojureScript dependencies (~30s). These are cached in `$XDG_CACHE_HOME/logseq-cli/nbb/` for subsequent runs.

## Development

```bash
nix build .#logseq        # desktop app
nix build .#logseq-cli    # CLI tool
nix flake check           # build checks + evaluate flake
nix fmt                   # format all Nix files (nixfmt)
```

## License

[AGPL-3.0-or-later](LICENSE)
