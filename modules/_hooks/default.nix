{
  git-hooks,
  lib,
  pkgs,
  system,
}:
let
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
        exec ${lib.getExe pkgs.dprint} --config ${dprintConfig}
      fi

      subcommand="$1"
      shift
      exec ${lib.getExe pkgs.dprint} "$subcommand" --config ${dprintConfig} "$@"
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
    src = ../..;

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
in
{
  inherit
    dprintWithPlugins
    hookGitleaks
    hookNixParse
    hookStatix
    preCommit
    ;
}
