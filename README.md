# nix-logseq-git-flake

Nix flake that packages the Logseq nightly tarball produced by this repository’s
[GitHub Actions nightly build](.github/workflows/nightly.yml) (built from the latest upstream commit) as a first-class Nix
package, with an opinionated FHS wrapper tuned for Electron workloads. The
package exposes a `logseq` binary you can run directly, a Nix app for `nix run`,
and helper builders for composing your own environments.

> [!NOTE]
> Highlights information that users should take into account, even when skimming.
>
> This flake currently packages only the Linux x86_64 build of Logseq. Additional platforms can be added if there is demand.


## Outputs

| Output                                   | Description                                                       |
| ---------------------------------------- | ----------------------------------------------------------------- |
| `packages.${system}.logseq`              | Standalone package containing Logseq, desktop entry, and icons.   |
| `apps.${system}.logseq`                  | `nix run` entry point invoking the packaged binary.               |
| `packages.${system}.logseq.fhs`          | FHS environment used by the launcher (exposed via `passthru`).    |
| `packages.${system}.logseq.fhsWithPackages` | Helper to extend the FHS with additional packages at build time. |

All systems from `flake-utils.lib.defaultSystems` are built by default; the
default `nixpkgs` input tracks `nixos-unstable`, but you can point it at any
channel that provides the required Electron runtime libraries.


## Quick start

```bash
# Run Logseq from the flake in the current directory
nix run .#logseq

# Build the package and add it to your profile
nix build .#logseq
nix profile install result

# Launch Logseq inside a shell without installing it
nix shell .#logseq --command logseq
```

## Customizing the runtime

The launcher wraps Logseq in a `buildFHSEnv` populated with libraries defined in
[`lib/runtime-libs.nix`](lib/runtime-libs.nix) (GTK, PipeWire, OpenGL, VA-API, etc.).
To add extra tools (for example, language servers or fonts), extend the wrapper:

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

The launcher also detects `/run/opengl-driver` and exports the environment
variables that NVIDIA’s proprietary stack expects (`__NV_PRIME_RENDER_OFFLOAD`,
`LIBVA_DRIVER_NAME`, etc.). On machines without that path it falls back to Mesa.

## Troubleshooting

- **GPU mismatches**: The wrapper assumes that your running kernel module and the
  libraries in `/run/opengl-driver` belong to the same driver version. If ANGLE
  reports “Invalid visual ID requested,” or NVML complains about mismatched
  versions, reboot (or reload the NVIDIA modules) before assuming the flake is
  at fault.

## CI pipelines

- [Nightly build](.github/workflows/nightly.yml) keeps `data/logseq-nightly.json` in sync with the latest upstream commit and publishes the tarball consumed by this flake.
- [Validate](.github/workflows/validate.yml) runs formatting and static checks on every push/PR to keep the flake tidy.

## License

This repository is released under the GNU Affero General Public License
v3.0 or later (matching Logseq’s upstream license). See [LICENSE](LICENSE) for
the full text.
