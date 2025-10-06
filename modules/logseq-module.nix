{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkIf
    mkOption
    types
    attrByPath
    isString
    mkMerge
    mkDefault
    ;
  cfg = config.services.logseq;
  ownerUsername = attrByPath [ "flake" "lib" "meta" "owner" "username" ] config null;
  defaultUser = if isString ownerUsername then ownerUsername else "vx";
  nixCmd = "${cfg.nixBinary}/bin/nix";
  syncScript = pkgs.writeShellApplication {
    name = "logseq-sync";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.gnugrep
      cfg.nixBinary
    ];
    text = ''
      set -euo pipefail

      dir="''${LOGSEQ_BUILD_DIR:-}"
      if [ -z "$dir" ]; then
        if [ -d "$HOME/nixos" ]; then
          dir="$HOME/nixos"
        elif [ -d /etc/nixos ]; then
          dir="/etc/nixos"
        else
          ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
          printf '{"timestamp":"%s","level":"error","message":"logseq flake directory not found"}\n' "$ts"
          exit 1
        fi
      fi

      ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      if out=$(${nixCmd} build "$dir"#logseq --print-out-paths 2>&1); then
        store_path=$(printf '%s' "$out" | ${pkgs.jq}/bin/jq -Rsa .)
        printf '{"timestamp":"%s","level":"info","message":"logseq built","storePath":%s}\n' "$ts" "$store_path"
      else
        err=$(printf '%s' "$out" | ${pkgs.jq}/bin/jq -Rsa .)
        printf '{"timestamp":"%s","level":"error","message":"logseq build failed","stderr":%s}\n' "$ts" "$err"
        exit 1
      fi
    '';
  };
  defaultPackage = mkDefault pkgs.emptyDirectory;
in
{
  options.services.logseq = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable automation for installing nightly Logseq builds.";
    };

    package = mkOption {
      type = types.package;
      default = defaultPackage;
      description = "Logseq package to install.";
    };

    timerOnCalendar = mkOption {
      type = types.str;
      default = "02:00";
      description = "systemd OnCalendar expression controlling nightly sync.";
    };

    logLevel = mkOption {
      type = types.enum [
        "info"
        "warn"
        "debug"
      ];
      default = "info";
      description = "Log verbosity level recorded by the sync service.";
    };

    user = mkOption {
      type = types.str;
      default = defaultUser;
      description = "System user that should run the sync job.";
    };

    buildDirectory = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Optional flake directory to build (defaults to $HOME/nixos, falling back to /etc/nixos).";
    };

    nixBinary = mkOption {
      type = types.path;
      default = pkgs.nix;
      description = "Path to the nix executable used for builds.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {

      systemd.services.logseq-sync = {
        description = "Nightly Logseq package realisation";
        environment = {
          NIX_CONFIG = lib.concatStringsSep "\n" [
            "accept-flake-config = true"
            "experimental-features = nix-command flakes"
          ];
          LOGSEQ_LOG_LEVEL = cfg.logLevel;
        }
        // lib.optionalAttrs (cfg.buildDirectory != null) {
          LOGSEQ_BUILD_DIR = toString cfg.buildDirectory;
        };
        serviceConfig = {
          Type = "oneshot";
          User = cfg.user;
          ExecStart = "${syncScript}/bin/logseq-sync";
        };
      };

      systemd.timers.logseq-sync = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.timerOnCalendar;
          Persistent = true;
        };
      };
    }
  ]);
}
