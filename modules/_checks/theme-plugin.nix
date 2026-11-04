# Evaluates the Home Manager theme-plugin module against a stub `home.file`,
# builds the plugin it links, and checks it against the pinned app
# (theme-plugin-cascade.py): in dark mode some app rule or script must still
# consume each custom property theme.css sets, or for a numbered scale step
# at least one step of its scale (whether the consuming element renders is
# out of reach); every variable theme.css reads must still be read by some
# dark-mode app rule or script; theme.css must out-rank every rule that pins
# a variable it sets to a fixed colour on the root or under an accent, and
# every accent-scoped rule (data-color on the root element) that paints a
# property it paints or a fixed colour; and every class and attribute its
# selectors use must still appear in the compiled style.css, attributes on
# html as root selectors; the app's icon colour picker must still offer exactly
# the presets the sheet re-colours. An upstream change then fails here instead
# of silently unstyling part of the UI.
{
  appAsar,
  lib,
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

  evalTheme =
    settings:
    lib.evalModules {
      modules = [
        ../_home-manager/theme-plugin.nix
        homeFileStub
        {
          _module.args.pkgs = pkgs;
          programs.logseq.themePlugin = settings;
        }
      ];
    };

  evaluated = evalTheme {
    enable = true;
    inherit name;
    title = "Check Theme";
    colors.accent = "#ff0000";
    colors.syntax.keyword = "#00ff00";
    extraCss = "/* extra-css-marker */";
  };

  cfg = evaluated.config.programs.logseq.themePlugin;
  homeFiles = evaluated.config.home.file;

  theme = import ../../lib/logseq-theme.nix { inherit lib; };
  renderColors =
    colors:
    theme.render {
      colors = (evalTheme { inherit colors; }).config.programs.logseq.themePlugin.colors;
      extraCss = "";
    };

  declarations =
    css:
    lib.listToAttrs (
      map (match: lib.nameValuePair (lib.elemAt match 0) (lib.elemAt match 1)) (
        lib.filter (match: match != null) (
          map (builtins.match "  (--[a-z0-9-]+): (.*);") (lib.splitString "\n" css)
        )
      )
    );

  hexChannels =
    hex:
    map (i: lib.fromHexString (builtins.substring (1 + 2 * i) 2 hex)) [
      0
      1
      2
    ];

  # Every `-alpha` step, composited over the background the way the browser
  # does, must land on its solid step.
  alphaStepsComposite =
    label: css:
    let
      vars = declarations css;
      background = hexChannels vars."--lx-gray-01";
      composites =
        stepName:
        let
          parsed = builtins.match "rgb\\(([0-9]+) ([0-9]+) ([0-9]+) / ([01]\\.[0-9]{3})\\)" vars.${stepName};
          overlay = map lib.toInt (lib.take 3 parsed);
          alpha = builtins.fromJSON (lib.elemAt parsed 3);
          composite = lib.zipListsWith (
            bg: over: builtins.floor (bg + (over - bg) * alpha + 0.5)
          ) background overlay;
        in
        parsed != null
        && alpha <= 1.0
        && lib.all (channel: channel <= 255) overlay
        && composite == hexChannels vars.${lib.removeSuffix "-alpha" stepName};
      failing = lib.filter (stepName: !composites stepName) (
        lib.filter (lib.hasSuffix "-alpha") (lib.attrNames vars)
      );
    in
    lib.throwIf (failing != [ ])
      "theme-plugin: ${label}: -alpha steps do not composite to their solid steps: ${toString failing}"
      true;

  accentSteps = map (step: "--lx-accent-${lib.fixedWidthString 2 "0" (toString step)}") (
    lib.range 1 12
  );

  # A dark accent scale brightens from step 1 to step 12.
  accentScaleOrdered =
    label: css:
    let
      vars = declarations css;
      brightness = map (step: lib.foldl' builtins.add 0 (hexChannels vars.${step})) accentSteps;
    in
    lib.throwIfNot (
      lib.sort lib.lessThan brightness == brightness
    ) "theme-plugin: ${label}: accent scale ${toString accentSteps} is not ordered by brightness" true;

  # With only `accent` set to pure red, every colour derived from it keeps a
  # red hue instead of falling back to the shipped blues.
  accentHueFollows =
    css:
    let
      vars = declarations css;
      derivedFromAccent = lib.take 11 accentSteps ++ [
        "--ls-block-highlight-color"
        "--ls-selection-background-color"
        "--ls-link-text-color"
        "--ls-link-text-hover-color"
      ];
      redDominant =
        var:
        let
          rgb = hexChannels vars.${var};
        in
        lib.elemAt rgb 0 > lib.elemAt rgb 1 && lib.elemAt rgb 0 > lib.elemAt rgb 2;
      failing = lib.filter (var: !redDominant var) derivedFromAccent;
    in
    lib.throwIf (
      failing != [ ]
    ) "theme-plugin: colors.accent = #ff0000 alone left non-red accent tones: ${toString failing}" true;

  # The compiled cljs vector literal of icon.cljs `color-picker`; the
  # compiler may break the line between elements.
  iconPresetList =
    "\\[" + lib.concatMapStrings (preset: "\"${preset.hex}\",\\s*") theme.iconPresets + "null\\]";

  # The rule set an icon preset's colour lands in.
  iconPresetColor =
    css: hex:
    let
      lines = lib.splitString "\n" css;
      ruleEnd = lib.findFirst (
        line: lib.hasInfix "[style*=\"${hex}\" i])" line && lib.hasInfix "{ color:" line
      ) null lines;
    in
    if ruleEnd == null then
      null
    else
      builtins.match ".*\\{ color: (#[0-9a-f]{6}) !important; }" ruleEnd;

  checkedCss = theme.render { inherit (cfg) colors extraCss; };
  defaultCss = renderColors { };

  # Per-file links are what make the plugin folder a real directory.
  expectedLinks = [
    "${pluginDir}/package.json"
    "${pluginDir}/theme.css"
  ];
  links =
    lib.throwIfNot (lib.attrNames homeFiles == expectedLinks)
      "theme-plugin: home.file must link exactly ${toString expectedLinks}, got ${toString (lib.attrNames homeFiles)}"
      homeFiles;
in
assert alphaStepsComposite "checked palette" checkedCss;
assert accentScaleOrdered "checked palette" checkedCss;
assert accentHueFollows checkedCss;
assert alphaStepsComposite "default palette" defaultCss;
assert accentScaleOrdered "default palette" defaultCss;
assert lib.assertMsg (
  (declarations (renderColors {
    bright = "#404040";
  }))."--ls-link-text-color" != (declarations defaultCss)."--ls-link-text-color"
) "theme-plugin: link tones ignore a changed bright";
assert lib.assertMsg (
  iconPresetColor checkedCss "#fb434c" == [ "#00ff00" ]
) "theme-plugin: the red icon preset does not follow colors.syntax.keyword";
assert lib.assertMsg (
  iconPresetColor (renderColors {
    icons.gray = "#123456";
  }) "#6e7b8b" == [ "#123456" ]
) "theme-plugin: colors.icons.gray does not re-colour the gray icon preset";
assert lib.assertMsg (
  renderColors (lib.mapAttrsRecursive (_: lib.toUpper) theme.defaultColors) == defaultCss
) "theme-plugin: the default palette spelled in uppercase renders differently";
assert alphaStepsComposite "sidebar darker than the background" (renderColors {
  background = "#1e1e1e";
  sidebar = "#141414";
});
assert alphaStepsComposite "light tinted palette on white" (renderColors {
  background = "#ffffff";
  sidebar = "#fdf6e3";
  popup = "#eee8d5";
  border = "#e4ddc8";
  activeItem = "#d9d2bd";
  raised = "#cfc7b1";
  strongBorder = "#bdb5a0";
  bullet = "#93a1a1";
  subtle = "#839496";
  dim = "#657b83";
  muted = "#586e75";
  text = "#073642";
  bright = "#002b36";
  accent = "#268bd2";
});
pkgs.runCommand "logseq-theme-plugin-check"
  {
    nativeBuildInputs = [
      pkgs.asar
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jq
      pkgs.python3
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
      for scale in lx-gray lx-accent; do
        required+=("--$scale-$step" "--$scale-$step-alpha")
      done
      required+=("--rx-gray-$step" "--rx-gray-$step-hsl")
    done
    for var in "''${required[@]}"; do
      grep -qE "^  $var: [^;]+;$" "$theme_css" || fail "missing $var"
    done

    grep -qF -- '--lx-accent-09: #ff0000;' "$theme_css" || fail "colors.accent did not reach --lx-accent-09"
    grep -qF -- '.cm-keyword { color: #00ff00; }' "$theme_css" || fail "colors.syntax.keyword did not reach .cm-keyword"
    test "$(tail -n 1 "$theme_css")" = "/* extra-css-marker */" || fail "extraCss is not appended last"
    test "$(grep -o '{' "$theme_css" | wc -l)" = "$(grep -o '}' "$theme_css" | wc -l)" || fail "unbalanced braces"

    asar extract-file "${appAsar}" css/style.css
    test -s style.css || fail "app.asar has no css/style.css"
    # The app's own bundles; cljs code builds some var() reads as strings.
    mkdir js
    asar list "${appAsar}" | grep -E '^/js/[^/]+\.m?js$' > js-files \
      || fail "app.asar lists no js/ bundles"
    while read -r file; do
      (cd js && asar extract-file "${appAsar}" "''${file#/}")
    done < js-files
    python3 -I -B ${./theme-plugin-cascade.py} "$theme_css" style.css js/* || exit 1
    python3 -I -B ${./theme-plugin-cascade-test.py} ${./theme-plugin-cascade.py} \
      "$theme_css" style.css js/* || exit 1

    # Selectors fail as silently as variables: every class the sheet targets
    # (CodeMirror 5 markup, .dark-theme) must still appear in the app's
    # stylesheet, and every attribute it selects on must still style the root.
    sed -z 's|/\*[^*]*\*\+\([^/*][^*]*\*\+\)*/||g; s/{[^}]*}//g' "$theme_css" > selectors
    grep -oE '\.[A-Za-z_-][A-Za-z0-9_-]*' selectors | sort -u > classes \
      || fail "selects no classes"
    while read -r class; do
      grep -qE -- "\\$class([^A-Za-z0-9_-]|\$)" style.css \
        || fail "selector $class is unknown to the pinned app's css/style.css"
    done < classes
    grep -oE 'html(\[[^]]*\])+' selectors | grep -oE '\[[^]]*\]' | sort -u > attributes \
      || fail "selects no root attributes"
    while read -r attribute; do
      case "$attribute" in
        *=*) grep -qF -- "html$attribute" style.css ;;
        *) grep -qE -- "html\\''${attribute%]}[]=]" style.css ;;
      esac || fail "the pinned app's css/style.css no longer styles html$attribute"
    done < attributes
    # The app's sheet never selects on style; the icon preset rules match it,
    # and the preset list guard below covers them.
    grep -oE '\[[A-Za-z_-]+' selectors | grep -vxF '[style' | sort -u > attribute-names \
      || fail "selects no attributes"
    while read -r attribute; do
      grep -qE -- "\\$attribute"'[]=~|^$*]' style.css \
        || fail "attribute ''${attribute#[} is unknown to the pinned app's css/style.css"
    done < attribute-names

    # The icon colour picker must still offer exactly the presets the sheet
    # re-colours, in order, plus the trailing "no colour" entry.
    grep -qzE -- '${iconPresetList}' js/* \
      || fail "the pinned app's icon colour presets are no longer ${
        toString (map (preset: preset.hex) theme.iconPresets)
      }"
    for hex in ${lib.escapeShellArgs (map (preset: preset.hex) theme.iconPresets)}; do
      grep -qF -- "[style*=\"$hex\" i]" "$theme_css" || fail "no rule re-colours icon preset $hex"
    done

    touch "$out"
  ''
