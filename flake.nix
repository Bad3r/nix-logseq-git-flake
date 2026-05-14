{
  description = "Nightly Logseq wrapper flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
    extra-substituters = [
      "https://nix-logseq-git-flake.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-logseq-git-flake.cachix.org-1:DSBNW07PSRyCvS926tpIWahb53OIydwwZhsP6LhJNZo="
    ];
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      git-hooks,
    }:
    let
      systems = [ "x86_64-linux" ];
    in
    flake-utils.lib.eachSystem systems (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        inherit (pkgs) lib;
        manifest = import ./lib/loadManifest.nix {
          inherit lib;
          manifestPath = ./data/logseq-nightly.json;
        };
        runtimeLibs = import ./lib/runtime-libs.nix;
        runtimeLibList = runtimeLibs pkgs;
        runtimeLibPath = lib.makeLibraryPath runtimeLibList;
        payload = pkgs.fetchzip {
          url = manifest.assetUrl;
          hash = manifest.assetSha256;
          stripRoot = false;
        };
        logseqSrc = pkgs.fetchFromGitHub {
          owner = "logseq";
          repo = "logseq";
          rev = manifest.logseqRev;
          hash = manifest.cliSrcHash;
        };
        logseqTree = pkgs.runCommand "logseq-tree" { } ''
          mkdir -p $out/share/logseq
          src="${payload}"
          cp -r "$src/." $out/share/logseq/
        '';
        fhsBase =
          {
            additionalPkgs ? (_pkgs: [ ]),
          }:
          pkgs.buildFHSEnv {
            name = "logseq-fhs";
            targetPkgs = pkgs: runtimeLibs pkgs ++ additionalPkgs pkgs;
            extraBwrapArgs = [
              "--bind-try"
              "/etc/nixos"
              "/etc/nixos"
              "--ro-bind-try"
              "/etc/xdg"
              "/etc/xdg"
            ];
            extraInstallCommands = ''
              ln -s ${logseqTree}/share $out/share
            '';
            runScript = "${logseqTree}/share/logseq/logseq";
          };
        logseqFhs = fhsBase { };
        desktopEntry = pkgs.writeTextFile {
          name = "logseq-desktop";
          destination = "/share/applications/logseq.desktop";
          text = ''
            [Desktop Entry]
            Type=Application
            Name=Logseq
            Exec=logseq %U
            Icon=logseq
            Terminal=false
            Categories=Office;Productivity;
            StartupWMClass=Logseq
            MimeType=x-scheme-handler/logseq;
          '';
        };
        icon = pkgs.runCommand "logseq-icon" { } ''
          mkdir -p $out/share/icons/hicolor/512x512/apps
          cp ${logseqSrc}/resources/icon.png \
            $out/share/icons/hicolor/512x512/apps/logseq.png
        '';
        dprintPlugins = pkgs.dprint-plugins.getPluginList (
          plugins: with plugins; [
            dprint-plugin-json
            dprint-plugin-markdown
            dprint-plugin-toml
            g-plane-pretty_yaml
            g-plane-markup_fmt
          ]
        );
        dprintConfig = pkgs.writeText "dprint.json" (
          builtins.toJSON {
            plugins = dprintPlugins;
          }
        );
        dprintWithPlugins = pkgs.writeShellApplication {
          name = "dprint";
          runtimeInputs = [ pkgs.dprint ];
          text = ''
            if [ "$#" -eq 0 ]; then
              exec dprint --config ${dprintConfig}
            fi

            subcommand="$1"
            shift
            exec dprint "$subcommand" --config ${dprintConfig} "$@"
          '';
        };
        hookStatix = pkgs.writeShellApplication {
          name = "hook-statix";
          runtimeInputs = [ pkgs.statix ];
          text = ''
            status=0
            for path in "$@"; do
              if [ -e "$path" ]; then
                statix check --format errfmt "$path" || status=$?
              fi
            done
            exit "$status"
          '';
        };
        hookNixParse = pkgs.writeShellApplication {
          name = "hook-nix-parse";
          runtimeInputs = [ pkgs.nix ];
          text = ''
            paths=()
            for path in "$@"; do
              if [ -e "$path" ]; then
                paths+=("$path")
              fi
            done

            if [ "''${#paths[@]}" -eq 0 ]; then
              exit 0
            fi

            exec nix-instantiate --parse "''${paths[@]}" >/dev/null
          '';
        };
        hookGitleaks = pkgs.writeShellApplication {
          name = "hook-gitleaks";
          runtimeInputs = [
            pkgs.git
            pkgs.gitleaks
          ];
          text = ''
            exec gitleaks git . --redact --no-banner
          '';
        };
        launcher = pkgs.writeShellScriptBin "logseq" ''
                    base_ld="${runtimeLibPath}"
                    if [ -n "''${LD_LIBRARY_PATH-}" ]; then
                      base_ld="$base_ld:''${LD_LIBRARY_PATH}"
                    fi
                    if [ -d /run/opengl-driver ]; then
                      export LD_LIBRARY_PATH="/run/opengl-driver/lib:/run/opengl-driver-32/lib:$base_ld"
                      export LIBGL_DRIVERS_PATH="''${LIBGL_DRIVERS_PATH:-/run/opengl-driver/lib/dri}"
                      export LIBVA_DRIVERS_PATH="''${LIBVA_DRIVERS_PATH:-/run/opengl-driver/lib/dri}"
                      if ls /run/opengl-driver/lib/libnvidia-*.so >/dev/null 2>&1; then
                        export __NV_PRIME_RENDER_OFFLOAD="''${__NV_PRIME_RENDER_OFFLOAD:-1}"
                        export __VK_LAYER_NV_optimus="''${__VK_LAYER_NV_optimus:-NVIDIA_only}"
                        export LIBVA_DRIVER_NAME="''${LIBVA_DRIVER_NAME:-nvidia}"
                        # Electron relies on EGL/ANGLE; forcing a GLX vendor breaks PRIME on NVIDIA (Invalid visual ID).
                        if [ -n "''${LOGSEQ_GLX_VENDOR-}" ]; then
                          export __GLX_VENDOR_LIBRARY_NAME="''${__GLX_VENDOR_LIBRARY_NAME:-''${LOGSEQ_GLX_VENDOR}}"
                        fi
                        if [ -z "''${VK_ICD_FILENAMES-}" ] && [ -f /run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json ]; then
                          export VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json
                        fi
                      fi
                    else
                      export LD_LIBRARY_PATH="$base_ld"
                      export LIBGL_DRIVERS_PATH="''${LIBGL_DRIVERS_PATH:-${pkgs.mesa}/lib/dri}"
                      export LIBVA_DRIVERS_PATH="''${LIBVA_DRIVERS_PATH:-${pkgs.mesa}/lib/dri}"
          	          fi
          	          exec ${logseqFhs}/bin/logseq-fhs "$@"
          	        '';
        afterFormatting = [ "treefmt" ];
        afterLinters = [
          "deadnix"
          "statix"
          "nix-parse"
          "actionlint"
          "shellcheck"
        ];
        lockPatchExcludes = [
          "\\.lock$"
          "\\.patch$"
        ];
        preCommit = git-hooks.lib.${system}.run {
          src = ./.;

          hooks = {
            treefmt = {
              enable = true;
              require_serial = true;
              settings = {
                fail-on-change = true;
                # NOTE: This applies to both local hooks and `nix flake check`.
                # Deterministic behavior is preferred over speed here.
                no-cache = true;
                formatters = [
                  pkgs.nixfmt
                  dprintWithPlugins
                  pkgs.shfmt
                ];
              };
            };

            deadnix = {
              enable = true;
              after = afterFormatting;
            };

            statix = {
              enable = true;
              # Built-in statix hook doesn't pass filenames; keep staged-only behavior.
              pass_filenames = true;
              entry = "${hookStatix}/bin/hook-statix";
              after = afterFormatting;
            };

            nix-parse = {
              enable = true;
              name = "nix-parse";
              description = "Parse staged Nix files with nix-instantiate --parse.";
              entry = "${hookNixParse}/bin/hook-nix-parse";
              pass_filenames = true;
              require_serial = true;
              files = "\\.nix$";
              after = afterFormatting;
            };

            actionlint = {
              enable = true;
              after = afterFormatting;
              stages = [
                "pre-commit"
                "pre-push"
                "manual"
              ];
            };

            shellcheck = {
              enable = true;
              after = afterFormatting;
              stages = [
                "pre-commit"
                "pre-push"
                "manual"
              ];
            };

            gitleaks = {
              enable = true;
              name = "gitleaks";
              description = "Detect hardcoded secrets in repository history.";
              entry = "${hookGitleaks}/bin/hook-gitleaks";
              pass_filenames = false;
              always_run = true;
              stages = [
                "pre-push"
                "manual"
              ];
            };

            trim-trailing-whitespace = {
              enable = true;
              after = afterLinters;
              excludes = lockPatchExcludes;
            };

            end-of-file-fixer = {
              enable = true;
              after = afterLinters;
              excludes = lockPatchExcludes;
            };

            check-merge-conflicts = {
              enable = true;
              after = afterLinters;
              excludes = lockPatchExcludes;
            };

            check-json = {
              enable = true;
              after = afterLinters;
            };

            check-yaml = {
              enable = true;
              after = afterLinters;
            };
          };
        };
        cli = pkgs.callPackage ./lib/cli.nix {
          inherit (manifest)
            logseqRev
            cliSrcHash
            cliVersion
            cliPnpmDepsHash
            cliVendorHash
            ;
        };
        logseqDesktop = pkgs.stdenv.mkDerivation {
          pname = "logseq-desktop";
          version = manifest.logseqVersion;
          dontUnpack = true;
          buildCommand = ''
            mkdir -p $out
            cp -r --no-preserve=mode,ownership ${logseqTree}/share $out/
            cp -r --no-preserve=mode,ownership ${icon}/share $out/
            cp -r --no-preserve=mode,ownership ${desktopEntry}/share $out/
            mkdir -p $out/bin
            ln -s ${launcher}/bin/logseq $out/bin/logseq
          '';
          meta = with lib; {
            description = "Logseq nightly desktop app";
            homepage = "https://github.com/logseq/logseq";
            license = licenses.agpl3Plus;
            platforms = platforms.linux;
            mainProgram = "logseq";
          };
          passthru = {
            fhs = logseqFhs;
            fhsWithPackages = fhsBase;
          };
        };
      in
      {
        packages = {
          logseq = logseqDesktop;
          logseq-cli = cli;
          hook-gitleaks = hookGitleaks;
          hook-nix-parse = hookNixParse;
          hook-statix = hookStatix;
          default = pkgs.symlinkJoin {
            name = "logseq-nightly";
            paths = [
              logseqDesktop
              cli
            ];
          };
        };
        apps.logseq = {
          type = "app";
          program = "${logseqDesktop}/bin/logseq";
          meta = {
            description = "Launch the nightly Logseq build packaged from the upstream master branch";
            homepage = "https://github.com/logseq/logseq";
            source = self.outPath;
          };
        };
        checks = {
          logseq = pkgs.runCommand "logseq-check" { } ''
            ${pkgs.coreutils}/bin/test -x ${logseqDesktop}/bin/logseq
            touch $out
          '';
          logseq-cli = pkgs.runCommand "logseq-cli-check" { } ''
            ${pkgs.coreutils}/bin/test -x ${cli}/bin/logseq-cli
            touch $out
          '';
          # Runtime smoke test: invoking the CLI exercises nbb-logseq's
          # classpath (cli/src + cli/vendor/src). Any missing vendor
          # namespace (the regression class fixed in PR #21) crashes here
          # on the first loadFile, so passing both probes is a strong
          # signal that the FOD copy still produces a working tree.
          #
          # Both probes assert on stable upstream substrings (`Usage:`,
          # `mcp-server`, `database version`). If upstream rewords any of
          # these, the grep fails closed — that's the right direction for
          # a regression guard, and the failing line in the build log
          # points at the exact substring to update.
          #
          # Probe order matters: probe 1 (`--help`) populates
          # `NBB_CACHE_DIR` before probe 2 (`list`) reuses it. That keeps
          # probe 2 fast at the cost of not independently verifying empty-
          # cache population — probe 1 covers that case implicitly.
          logseq-cli-help = pkgs.runCommand "logseq-cli-help-check" { } ''
            export HOME=$TMPDIR
            export XDG_CACHE_HOME=$TMPDIR/cache

            # Probe 1: --help exercises the help renderer's namespace.
            help_output=$(${cli}/bin/logseq-cli --help 2>&1)
            help_status=$?
            if [ "$help_status" -ne 0 ]; then
              echo "logseq-cli --help exited $help_status" >&2
              echo "$help_output" >&2
              exit 1
            fi
            # `Usage:` and `mcp-server` are stable substrings of the help
            # output produced by the upstream CLI; require both so a future
            # silent fallthrough (e.g. nbb prints a stack trace but still
            # exits 0) doesn't get rubber-stamped.
            echo "$help_output" | ${pkgs.gnugrep}/bin/grep -q '^Usage:'
            echo "$help_output" | ${pkgs.gnugrep}/bin/grep -q 'mcp-server'

            # Probe 2: `list` against an empty HOME forces the
            # graph-discovery namespace (the original regression site —
            # `logseq.common.graph-dir`) to load. With no graphs present
            # the CLI emits a stable warning string and exits 0; a missing
            # vendor namespace would crash before reaching that point.
            list_output=$(${cli}/bin/logseq-cli list 2>&1)
            list_status=$?
            if [ "$list_status" -ne 0 ]; then
              echo "logseq-cli list exited $list_status" >&2
              echo "$list_output" >&2
              exit 1
            fi
            echo "$list_output" | ${pkgs.gnugrep}/bin/grep -qF 'database version'

            touch $out
          '';
          pre-commit-check = preCommit;
        };
        devShells =
          let
            hookShell = pkgs.mkShell {
              packages = preCommit.enabledPackages ++ [
                pkgs.coreutils
                pkgs.git
                pkgs.pre-commit
              ];
              inherit (preCommit) shellHook;
            };
          in
          {
            default = hookShell;
            # Compatibility alias for older docs/scripts: `nix develop .#hooks`.
            hooks = hookShell;
          };
        formatter = preCommit.config.hooks.treefmt.package;
      }
    )
    // {
      overlays.default = import ./overlays {
        inherit (self) packages;
      };
    };
}
