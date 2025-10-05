{
  description = "Nightly Logseq wrapper flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      systems = flake-utils.lib.defaultSystems;
    in flake-utils.lib.eachSystem systems (system:
      let
        pkgs = import nixpkgs { inherit system; };
        lib = pkgs.lib;
        manifest = (import ./lib/loadManifest.nix {
          inherit lib;
          manifestPath = ./data/logseq-nightly.json;
        });
        runtimeLibs = (import ./lib/runtime-libs.nix) pkgs;
        payload = pkgs.fetchzip {
          url = manifest.assetUrl;
          hash = manifest.assetSha256;
          stripRoot = true;
        };
        logseqTree = pkgs.runCommand "logseq-tree" {} ''
          mkdir -p $out/share/logseq
          src="${payload}"
          if [ -d "$src/Logseq-linux-x64" ]; then
            cp -r "$src/Logseq-linux-x64/." $out/share/logseq/
          else
            cp -r "$src/." $out/share/logseq/
          fi
        '';
        logseqFhs = pkgs.buildFHSEnv {
          name = "logseq-fhs";
          targetPkgs = _: runtimeLibs;
          runScript = "${logseqTree}/share/logseq/Logseq";
        };
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
        icon = pkgs.runCommand "logseq-icon" {} ''
          mkdir -p $out/share/icons/hicolor/512x512/apps
          cp ${logseqTree}/share/logseq/resources/app/icon.png \
            $out/share/icons/hicolor/512x512/apps/logseq.png
        '';
        launcher = pkgs.writeShellScriptBin "logseq" ''
          exec ${logseqFhs}/bin/logseq-fhs "$@"
        '';
        package = pkgs.stdenv.mkDerivation {
          pname = "logseq";
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
            description = "Logseq nightly wrapper";
            homepage = "https://github.com/logseq/logseq";
            license = licenses.agpl3Plus;
            platforms = platforms.linux;
            mainProgram = "logseq";
          };
        };
      in {
        packages.logseq = package;
        packages.default = package;
        apps.logseq = {
          type = "app";
          program = "${package}/bin/logseq";
        };
        checks.logseq = pkgs.runCommand "logseq-check" {} ''
          ${pkgs.coreutils}/bin/test -x ${package}/bin/logseq
          touch $out
        '';
        formatter = pkgs.nixpkgs-fmt;
      }
    ) // {
      nixosModules.logseq = import ./modules/logseq-module.nix self;
    };
}
