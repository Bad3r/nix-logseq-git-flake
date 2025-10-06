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
            if [ -z "''${VK_ICD_FILENAMES-}" ] && [ -f /run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json ]; then
              export VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json
            fi
          else
            export LD_LIBRARY_PATH="$base_ld"
          fi
          exec ${logseqFhs}/bin/logseq-fhs "$@"
        '';
        package = pkgs.stdenv.mkDerivation {
          pname = "logseq";
          version = manifest.logseqVersion;
          dontUnpack = true;
          nativeBuildInputs = [ pkgs.wrapGAppsHook3 ];
          dontWrapGApps = true;
          buildCommand = ''
            mkdir -p $out
            cp -r --no-preserve=mode,ownership ${logseqTree}/share $out/
            cp -r --no-preserve=mode,ownership ${icon}/share $out/
            cp -r --no-preserve=mode,ownership ${desktopEntry}/share $out/
            mkdir -p $out/bin
            ln -s ${launcher}/bin/logseq $out/bin/logseq
          '';
          meta = with lib; {
            description = "Logseq nightly wrapper";
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
        packages.logseq = package;
        packages.default = package;
        apps.logseq = {
          type = "app";
          program = "${package}/bin/logseq";
          meta = {
            description = "Launch the nightly Logseq build packaged from the upstream master branch";
            homepage = "https://github.com/logseq/logseq";
            source = self.outPath;
          };
        };
        checks.logseq = pkgs.runCommand "logseq-check" { } ''
          ${pkgs.coreutils}/bin/test -x ${package}/bin/logseq
          touch $out
        '';
        formatter = pkgs.nixfmt-rfc-style;
      }
    );
}
