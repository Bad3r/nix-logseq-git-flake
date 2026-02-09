{
  description = "Nightly Logseq wrapper flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    let
      systems = flake-utils.lib.defaultSystems;
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
        logseqTree = pkgs.runCommand "logseq-tree" { } ''
          mkdir -p $out/share/logseq
          src="${payload}"
          if [ -d "$src/Logseq-linux-x64" ]; then
            cp -r "$src/Logseq-linux-x64/." $out/share/logseq/
          else
            cp -r "$src/." $out/share/logseq/
          fi
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
            runScript = "${logseqTree}/share/logseq/Logseq";
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
          cp ${logseqTree}/share/logseq/resources/app/icon.png \
            $out/share/icons/hicolor/512x512/apps/logseq.png
        '';
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
        lefthookStatix = pkgs.writeShellApplication {
          name = "lefthook-statix";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.statix
          ];
          text = ''
            set -euo pipefail

            if [ "$#" -eq 0 ]; then
              statix check --format errfmt
              exit 0
            fi

            status=0
            for file in "$@"; do
              if [ -f "$file" ]; then
                statix check --format errfmt "$file" || status=$?
              fi
            done
            exit "$status"
          '';
        };
        lefthookFileHygiene = pkgs.writeShellApplication {
          name = "lefthook-file-hygiene";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.file
            pkgs.gnugrep
            pkgs.jq
            pkgs.yq-go
          ];
          text = ''
            set -euo pipefail

            status=0

            is_binary() {
              enc=$(file --mime-encoding -b "$1" 2>/dev/null || echo "binary")
              case "$enc" in
                us-ascii|utf-8|ascii) return 1 ;;
                *) return 0 ;;
              esac
            }

            is_excluded() {
              case "$1" in
                result/*|.direnv/*|.git/*|*.lock|*.patch) return 0 ;;
                *) return 1 ;;
              esac
            }

            for file in "$@"; do
              [ -f "$file" ] || continue
              is_excluded "$file" && continue
              is_binary "$file" && continue

              # Trailing whitespace
              if grep -Pn '\s+$' "$file" >/dev/null 2>&1; then
                echo "trailing-whitespace: $file"
                grep -Pn '\s+$' "$file" | head -5
                status=1
              fi

              # End-of-file newline
              if [ -s "$file" ]; then
                last_byte=$(tail -c1 "$file" | od -An -tx1 | tr -d ' ')
                if [ "$last_byte" != "0a" ]; then
                  echo "missing-eof-newline: $file"
                  status=1
                fi
              fi

              # Merge conflicts (pattern split to avoid self-match in source)
              conflict_marker="<""<""<""<""<""<""< "
              if grep -n "$conflict_marker" "$file" >/dev/null 2>&1; then
                echo "merge-conflict: $file"
                grep -n "$conflict_marker\|=======\|>>>>>>>" "$file" | head -10
                status=1
              fi

              # JSON validation
              case "$file" in
                *.json)
                  if ! jq empty "$file" 2>/dev/null; then
                    echo "invalid-json: $file"
                    status=1
                  fi
                  ;;
              esac

              # YAML validation
              case "$file" in
                *.yaml|*.yml)
                  if ! yq '.' "$file" >/dev/null 2>&1; then
                    echo "invalid-yaml: $file"
                    status=1
                  fi
                  ;;
              esac
            done

            exit "$status"
          '';
        };
        hookToolPackages = [
          pkgs.lefthook
          pkgs.deadnix
          pkgs.statix
          pkgs.nixfmt
          pkgs.biome
          pkgs.actionlint
          pkgs.nodePackages.prettier
          pkgs.shfmt
          pkgs.jq
          pkgs.yq-go
          lefthookStatix
          lefthookFileHygiene
        ];
        hookShellSetup = ''
          if command -v lefthook >/dev/null 2>&1; then
            pre_commit_hook="$(git rev-parse --git-path hooks/pre-commit 2>/dev/null || echo ".git/hooks/pre-commit")"
            if [ ! -f "$pre_commit_hook" ] || ! grep -q "lefthook" "$pre_commit_hook" 2>/dev/null; then
              lefthook install
            fi
          fi
        '';
        cli = pkgs.callPackage ./lib/cli.nix {
          inherit (manifest)
            logseqRev
            cliSrcHash
            cliVersion
            cliYarnDepsHash
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
        };
        devShells = {
          default = pkgs.mkShell {
            packages = [
              pkgs.coreutils
              pkgs.git
            ]
            ++ hookToolPackages;
            shellHook = hookShellSetup;
          };
          hooks = pkgs.mkShell {
            packages = [
              pkgs.coreutils
              pkgs.git
            ]
            ++ hookToolPackages;
            shellHook = hookShellSetup;
          };
        };
        formatter = pkgs.nixfmt-tree;
      }
    )
    // {
      overlays.default = import ./overlays {
        inherit (self) packages;
      };
    };
}
