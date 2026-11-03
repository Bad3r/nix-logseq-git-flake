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

The flake also exports `homeManagerModules.default`, which installs a
generated theme plugin (see [Theme Plugin](#theme-plugin)).

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

## Theme Plugin

`homeManagerModules.default` adds `programs.logseq.themePlugin`, which renders
a dark theme from a semantic palette and installs it as a theme-only plugin in
`~/.logseq/plugins/<name>/` (`package.json` plus `theme.css`, no code).

```nix
{ config, inputs, ... }:
let
  c = config.lib.stylix.colors.withHashtag;
in
{
  imports = [ inputs.logseq-nightly.homeManagerModules.default ];

  programs.logseq.themePlugin = {
    enable = true;
    name = "stylix";
    title = "Stylix";
    colors = {
      background = c.base00;
      sidebar = c.base01;
      popup = c.base01;
      border = c.base02;
      activeItem = c.base02;
      raised = c.base02;
      strongBorder = c.base03;
      placeholder = c.base03;
      subtle = c.base03;
      dim = c.base04;
      muted = c.base04;
      text = c.base05;
      accent = c.base0D;
      syntax.keyword = c.base08;
    };
  };
}
```

Each unset colour keeps its default, a VS Code Dark 2026 palette with GitHub
Dark syntax colours. The exceptions are the accent tones `highlight`,
`selection`, `accentStrong`, `link`, and `linkHover`: unset, they blend from
`accent` toward `background` or `bright`, so setting `accent` alone recolours
the whole accent scale. The shipped `accent` over the shipped `background`
keeps hand-tuned tones instead.

The twelve neutral keys, `background` through `text`, form one scale ordered
from the page background to body text, so a palette that replaces them sets
all twelve: unset steps keep the VS Code greys and break the ordering. The
option descriptions in
`modules/_home-manager/theme-plugin.nix` list every key; `extraCss` appends
rules after the generated ones.

The theme sets Logseq's CSS variables (gray and accent scales on `html` and
`body`, the shadcn HSL triplets, and the classic `--ls-*` palette) rather than
styling components, so it holds across accent colours and most app updates.
Only CodeMirror token colours use selectors. The
`checks.<system>.logseq-theme-plugin` check fails when the pinned app no
longer reads a variable the theme sets in dark mode, or its stylesheet no
longer knows a class or root attribute the theme selects on. A read counts
only where the theme's value can reach the screen: not in light-mode rules,
and not as the fallback of another variable the theme sets, since the theme
always defines the primary. The numbered steps of a scale pass together once
the app reads one of them.

Logseq lists only real directories under `~/.logseq/plugins`, so the module
links each file separately and Home Manager creates the plugin folder itself.

After the first activation, restart Logseq and pick the theme once in
Settings > Themes. Logseq records the choice in `~/.logseq/preferences.json`,
which this module leaves alone; renaming `name` changes the plugin id and
requires picking the theme again. The theme applies in dark mode only.

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

Note: `logseq-cli` takes its OCaml/Melange closure from the materialized
opam-nix solve in `modules/_packages/logseq-cli/opam-defs.json`, so
evaluating it needs no import-from-derivation (IFD).
`scripts/update-nightly.sh` regenerates it from
`.#logseq-cli.opamDefs` and stamps `cliOpamDefsRev`; evaluation fails when the
stamp differs from `logseqRev`. `opam-deps.nix` derives the closure from
`cli/logseq-cli.opam` and checks that the `ocaml`, `dune`, and `melange`
toolchain entries are present before the build proceeds.

The Darwin desktop package is validated by the `validate-aarch64-darwin`
workflow job, which builds the package on macOS, verifies the app signature, and
runs a bounded launch probe.

## License

[AGPL-3.0-or-later](LICENSE)
