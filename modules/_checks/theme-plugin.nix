# Evaluates the Home Manager theme-plugin module against a stub `home.file`,
# builds the plugin it links, and checks it against the pinned app: every
# custom property theme.css sets must still be declared or read by the app's
# compiled style.css, so an upstream variable rename fails here instead of
# silently unstyling part of the UI.
{
  lib,
  logseqTree,
  pkgs,
}:
let
  name = "check-theme";
  pluginDir = ".logseq/plugins/${name}";

  homeFileStub = {
    options.home.file = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.source = lib.mkOption { type = lib.types.path; };
        }
      );
      default = { };
    };
  };

  evaluated = lib.evalModules {
    modules = [
      ../_home-manager/theme-plugin.nix
      homeFileStub
      {
        _module.args.pkgs = pkgs;
        programs.logseq.themePlugin = {
          enable = true;
          inherit name;
          title = "Check Theme";
          colors.accent = "#ff0000";
          colors.syntax.keyword = "#00ff00";
          extraCss = "/* extra-css-marker */";
        };
      }
    ];
  };

  cfg = evaluated.config.programs.logseq.themePlugin;
  homeFiles = evaluated.config.home.file;

  # Per-file links are what make the plugin folder a real directory.
  expectedLinks = [
    "${pluginDir}/package.json"
    "${pluginDir}/theme.css"
  ];
  links =
    lib.throwIfNot (lib.attrNames homeFiles == expectedLinks)
      "theme-plugin: home.file must link exactly ${toString expectedLinks}, got ${toString (lib.attrNames homeFiles)}"
      homeFiles;

  asarPath =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "${logseqTree}/Logseq.app/Contents/Resources/app.asar"
    else
      "${logseqTree}/share/logseq/resources/app.asar";
in
pkgs.runCommand "logseq-theme-plugin-check"
  {
    nativeBuildInputs = [
      pkgs.asar
      pkgs.gnugrep
      pkgs.jq
    ];
  }
  ''
    package_json="${links."${pluginDir}/package.json".source}"
    theme_css="${links."${pluginDir}/theme.css".source}"
    test "$(dirname "$package_json")" = "${cfg.package}"

    jq -e '
      .name == "${name}"
      and (.version | type == "string")
      and .logseq.id == "${name}"
      and .logseq.title == "Check Theme"
      and (.logseq | (has("main") or has("entry") or has("devEntry")) | not)
      and (has("main") | not)
      and (.logseq.themes | length == 1)
      and .logseq.themes[0].name == "Check Theme"
      and .logseq.themes[0].url == "./theme.css"
      and .logseq.themes[0].mode == "dark"
    ' "$package_json" >/dev/null || {
      echo "package.json does not describe a single theme-only plugin:" >&2
      cat "$package_json" >&2
      exit 1
    }

    fail() {
      echo "theme.css: $*" >&2
      exit 1
    }

    required=(--background --foreground --ls-primary-background-color --ls-primary-text-color)
    for step in 01 02 03 04 05 06 07 08 09 10 11 12; do
      required+=("--lx-gray-$step" "--lx-accent-$step" "--rx-gray-$step" "--rx-gray-$step-hsl")
    done
    for var in "''${required[@]}"; do
      grep -qE "^  $var: [^;]+;$" "$theme_css" || fail "missing $var"
    done

    grep -qF -- '--lx-accent-09: #ff0000;' "$theme_css" || fail "colors.accent did not reach --lx-accent-09"
    grep -qF -- '.cm-keyword { color: #00ff00; }' "$theme_css" || fail "colors.syntax.keyword did not reach .cm-keyword"
    test "$(tail -n 1 "$theme_css")" = "/* extra-css-marker */" || fail "extraCss is not appended last"
    test "$(grep -o '{' "$theme_css" | wc -l)" = "$(grep -o '}' "$theme_css" | wc -l)" || fail "unbalanced braces"

    asar extract-file "${asarPath}" css/style.css
    test -s style.css || fail "app.asar has no css/style.css"
    grep -oE '^  --[a-z0-9-]+' "$theme_css" | tr -d ' ' | sort -u > declared
    test -s declared || fail "declares no custom properties"
    while read -r var; do
      grep -qF -- "$var:" style.css || grep -qE -- "var\\($var[,)]" style.css \
        || fail "$var is unknown to the pinned app's css/style.css"
    done < declared

    touch "$out"
  ''
