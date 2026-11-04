# Renders a dark Logseq theme stylesheet from a semantic palette. Besides the
# app's CSS variables (on the root, and on the components shui.css re-tints
# under the logseq accent) it styles only the root background, text selection
# under the none accent, the few component states the logseq accent paints
# near-invisibly (theme picker rows, ghost button hover, form input borders,
# faded command palette groups), inline code text, a VS Code Dark 2026 layout
# (the top bar, both sidebars, and dialogs on step 2 around step 1 content with
# step 4 edges; right-sidebar cards as outlined content panes; translucent
# hover and active overlays on sidebar and settings lists; menus with the
# widget border, shadow, and accent-outlined highlight; the keyboard-selected
# command palette row in the focus fill; scrollbar thumbs), the icon picker's
# colour presets wherever they render, and CodeMirror
# code blocks (surface, gutters, line numbers, cursor, selection, active line,
# bracket matching, tokens), so it survives component restyles;
# checks.<system>.logseq-theme-plugin fails when the pinned app stops
# consuming a variable (or every step of a scale), pins one to a fixed colour
# or paints one of its properties in a rule the sheet does not out-rank, or
# stops using a class or attribute a selector names.
{ lib }:
let
  inherit (builtins)
    concatStringsSep
    elemAt
    floor
    genList
    substring
    ;

  hexDigits = "0123456789abcdef";

  parseHex =
    color:
    let
      digits = lib.removePrefix "#" color;
    in
    lib.throwIfNot (builtins.match "[0-9a-fA-F]{6}" digits != null)
      "logseq-theme: expected #rrggbb, got '${color}'"
      (genList (i: lib.fromHexString (substring (i * 2) 2 digits)) 3);

  clampByte =
    value:
    if value < 0 then
      0
    else if value > 255 then
      255
    else
      value;

  roundHalfUp = value: floor (value + 0.5);

  byteHex =
    value:
    let
      byte = clampByte value;
    in
    substring (byte / 16) 1 hexDigits + substring (lib.mod byte 16) 1 hexDigits;

  toHex = channels: "#" + concatStringsSep "" (map byteHex channels);

  # Fixed-point decimal rendering for a non-negative float.
  fixed =
    decimals: value:
    let
      scale = lib.foldl' (acc: _: acc * 10) 1 (genList (x: x) decimals);
      scaled = roundHalfUp (value * scale);
      fraction = toString (lib.mod scaled scale);
      padded = lib.fixedWidthString decimals "0" fraction;
    in
    "${toString (scaled / scale)}.${padded}";

  # `amount` of colour `top` over colour `bottom`.
  mix =
    top: bottom: amount:
    let
      a = parseHex top;
      b = parseHex bottom;
    in
    toHex (genList (i: roundHalfUp (elemAt b i + (elemAt a i - elemAt b i) * amount)) 3);

  # Space-separated `H S% L%` triplet, the shape shadcn-style `hsl(var(--x))`
  # references expect.
  hslTriplet =
    color:
    let
      channels = map (c: c / 255.0) (parseHex color);
      r = elemAt channels 0;
      g = elemAt channels 1;
      b = elemAt channels 2;
      maxc = lib.max r (lib.max g b);
      minc = lib.min r (lib.min g b);
      sum = maxc + minc;
      delta = maxc - minc;
      lightness = sum / 2;
      saturation =
        if delta == 0 then
          0.0
        else if lightness <= 0.5 then
          delta / sum
        else
          delta / (2.0 - sum);
      rc = (maxc - r) / delta;
      gc = (maxc - g) / delta;
      bc = (maxc - b) / delta;
      sextant =
        if delta == 0 then
          0.0
        else if r == maxc then
          bc - gc
        else if g == maxc then
          2.0 + rc - bc
        else
          4.0 + gc - rc;
      turn = sextant / 6.0;
      hue = turn - floor turn;
    in
    "${fixed 1 (hue * 360)} ${fixed 1 (saturation * 100)}% ${fixed 1 (lightness * 100)}%";

  rgbString =
    color: alpha:
    let
      channels = parseHex color;
    in
    "rgb(${concatStringsSep " " (map toString channels)} / ${alpha})";

  # Translucent overlay that composites back to `target` over `bg`, so
  # `-alpha` scale steps match their solid steps in either direction. The
  # alpha is the smallest per-mille value that keeps the overlay in gamut;
  # rounding it up and solving the overlay for that alpha keeps the composite
  # within half a byte of `target`.
  alphaOver =
    target: bg:
    let
      t = parseHex target;
      b = parseHex bg;
      channels = genList (i: i) 3;
      delta = i: elemAt t i - elemAt b i;
      distance = i: if delta i < 0 then -(delta i) else delta i;
      headroom = i: if delta i > 0 then 255 - elemAt b i else elemAt b i;
      perMille = i: if delta i == 0 then 0 else (1000 * distance i + headroom i - 1) / headroom i;
      alphaMille = lib.foldl' lib.max 0 (map perMille channels);
      overlay = map (i: roundHalfUp (elemAt b i + delta i * 1000.0 / alphaMille)) channels;
    in
    if alphaMille == 0 then
      rgbString bg "0.000"
    else
      rgbString (toHex overlay) (fixed 3 (alphaMille / 1000.0));

  declare = name: value: "  ${name}: ${value};";

  pad2 = index: lib.fixedWidthString 2 "0" (toString index);

  indexed = values: lib.imap1 (index: value: { inherit index value; }) values;

  # VS Code Dark 2026 UI greys over GitHub Dark syntax colours. The accent
  # tones are left to `withTones`.
  defaultColors = {
    background = "#121314";
    sidebar = "#191a1b";
    popup = "#202122";
    border = "#2a2b2c";
    activeItem = "#313233";
    raised = "#414243";
    strongBorder = "#454545";
    bullet = "#555555";
    subtle = "#616161";
    dim = "#858889";
    muted = "#8c8c8c";
    text = "#bbbebf";
    bright = "#f0f6fc";
    onAccent = "#ffffff";
    accent = "#3994bc";
    danger = "#da3633";
    mark = "#cd9731";
    cloze = "#ffa657";
    syntax = {
      keyword = "#ff7b72";
      constant = "#79c0ff";
      function = "#d2a8ff";
      variable = "#c9d1d9";
      parameter = "#ffa657";
      type = "#ffa657";
      string = "#a5d6ff";
      regexp = "#7ee787";
      comment = "#9198a1";
      tag = "#7ee787";
      heading = "#1f6feb";
      invalid = "#ffa198";
    };
  };

  # Accent tones tuned for the shipped accent, background, and bright.
  shippedTones = {
    highlight = "#1a3540";
    selection = "#245c73";
    accentStrong = "#297aa0";
    link = "#48a0c7";
    linkHover = "#79c0ff";
  };

  # Fills each unset (null) accent tone. The shipped accent, background, and
  # bright keep their tuned tones; any other combination blends the palette's
  # own accent toward the background or `bright`, so the accent scale, links, and
  # selection share one hue. `accentStrong` (accent step 7) has no option; it
  # fills primary buttons and the keyboard-selected command palette row.
  withTones =
    colors:
    let
      shipped =
        colors.accent == defaultColors.accent
        && colors.background == defaultColors.background
        && colors.bright == defaultColors.bright;
      fallback =
        if shipped then
          shippedTones
        else
          {
            highlight = mix colors.accent colors.background 0.25;
            selection = mix colors.accent colors.background 0.55;
            accentStrong = mix colors.accent colors.background 0.8;
            link = mix colors.bright colors.accent 0.15;
            linkHover = mix colors.bright colors.accent 0.4;
          };
    in
    colors
    // lib.mapAttrs (
      name: tone: if colors.${name} or null == null then tone else colors.${name}
    ) fallback;

  # The icon picker's colour presets (`color-picker` in icon.cljs), in its
  # order, each with the palette key an unset (null) override falls back to.
  # The chosen hex is stored on the node and rendered as an inline style, so
  # the sheet can only re-colour these exact values.
  iconPresets = [
    {
      name = "gray";
      hex = "#6e7b8b";
      fallback = [
        "syntax"
        "comment"
      ];
    }
    {
      name = "indigo";
      hex = "#5e69d2";
      fallback = [
        "syntax"
        "function"
      ];
    }
    {
      name = "cyan";
      hex = "#00b5ed";
      fallback = [
        "syntax"
        "constant"
      ];
    }
    {
      name = "green";
      hex = "#00b55b";
      fallback = [
        "syntax"
        "regexp"
      ];
    }
    {
      name = "yellow";
      hex = "#f2be00";
      fallback = [ "mark" ];
    }
    {
      name = "orange";
      hex = "#e47a00";
      fallback = [
        "syntax"
        "parameter"
      ];
    }
    {
      name = "pink";
      hex = "#f38e81";
      fallback = [
        "syntax"
        "invalid"
      ];
    }
    {
      name = "red";
      hex = "#fb434c";
      fallback = [
        "syntax"
        "keyword"
      ];
    }
  ];

  # One spelling per colour: hex digits are case-insensitive, so lowercase
  # them before the shipped-palette test and before they reach the sheet.
  canonical = lib.mapAttrsRecursive (
    _: value: if lib.isString value then lib.toLower value else value
  );

  render =
    { colors, extraCss }:
    let
      palette = canonical colors;
      c = withTones palette;
      s = palette.syntax;

      gray = [
        c.background
        c.sidebar
        c.popup
        c.border
        c.activeItem
        c.raised
        c.strongBorder
        c.bullet
        c.subtle
        c.dim
        c.muted
        c.text
      ];

      # Steps without a palette entry blend toward the background.
      accent = [
        (mix c.accent c.background 0.06)
        (mix c.accent c.background 0.10)
        c.highlight
        (mix c.selection c.highlight 0.5)
        c.selection
        (mix c.accentStrong c.selection 0.5)
        c.accentStrong
        c.accent
        c.accent
        c.link
        c.link
        c.bright
      ];

      # Each step plus the one variant form the app reads for that scale.
      grayLines =
        prefix: variant:
        let
          forms = {
            hsl = hslTriplet;
            alpha = value: alphaOver value c.background;
          };
        in
        lib.concatMap (
          { index, value }:
          let
            step = "${prefix}-${pad2 index}";
          in
          [
            (declare step value)
            (declare "${step}-${variant}" (forms.${variant} value))
          ]
        ) (indexed gray);

      accentLines = lib.concatMap (
        { index, value }:
        let
          step = "--lx-accent-${pad2 index}";
        in
        [
          (declare step value)
          (declare "${step}-alpha" (alphaOver value c.background))
        ]
      ) (indexed accent);

      hslLines = lib.mapAttrsToList (name: value: declare "--${name}" (hslTriplet value)) {
        inherit (c) accent background border;
        foreground = c.text;
        card = c.background;
        card-foreground = c.text;
        popover = c.popup;
        popover-foreground = c.text;
        primary = c.accentStrong;
        primary-foreground = c.onAccent;
        secondary = c.activeItem;
        secondary-foreground = c.text;
        muted = c.popup;
        muted-foreground = c.muted;
        accent-foreground = c.onAccent;
        destructive = c.danger;
        destructive-foreground = c.onAccent;
        input = c.border;
        ring = c.accent;
      };

      lsLines = lib.mapAttrsToList (name: declare "--${name}") {
        ls-primary-background-color = c.background;
        ls-secondary-background-color = c.sidebar;
        ls-tertiary-background-color = c.popup;
        ls-quaternary-background-color = c.border;
        ls-page-properties-background-color = c.popup;
        ls-a-chosen-bg = c.activeItem;
        lx-popover-bg = c.popup;
        ls-border-color = c.border;
        ls-secondary-border-color = c.border;
        ls-tertiary-border-color = c.border;
        ls-primary-text-color = c.text;
        ls-secondary-text-color = c.muted;
        ls-icon-color = c.muted;
        ls-active-primary-color = c.accent;
        ls-link-text-color = c.link;
        ls-link-text-hover-color = c.linkHover;
        ls-link-ref-text-color = c.link;
        ls-block-highlight-color = c.highlight;
        ls-selection-background-color = c.selection;
        ls-page-checkbox-color = c.subtle;
        ls-page-blockquote-color = c.text;
        ls-page-blockquote-bg-color = c.sidebar;
        ls-page-blockquote-border-color = c.subtle;
        ls-page-mark-color = c.bright;
        ls-page-mark-bg-color = rgbString c.mark "0.4";
        ls-cloze-text-color = c.cloze;
        ls-pie-bg-color = c.border;
        ls-pie-fg-color = c.accent;
        color-level-2 = c.popup;
        color-level-3 = c.border;
        color-level-4 = c.activeItem;
        color-level-5 = c.raised;
        color-level-6 = c.strongBorder;
      };

      # Under the logseq accent shui.css pins these components' shadcn tokens
      # to fixed teal, which beats the root values by inheritance. The values
      # mirror the app's own rules for every other accent; components without
      # one inherit the root value there.
      componentTokens = [
        {
          selectors = [
            ".ui__dropdown-menu-content"
            ".ui__dropdown-menu-sub-content"
            ".ui__context-menu-content"
            ".ui__context-menu-sub-content"
            ".ui__popover-content"
            ".ui__select-content"
          ];
          tokens = {
            accent = "var(--rx-gray-04-hsl)";
            muted = "var(--rx-gray-05-hsl)";
            secondary-foreground = hslTriplet c.text;
          };
        }
        {
          selectors = [ ".ui__calendar" ];
          tokens.accent = "var(--rx-gray-04-hsl)";
        }
        {
          selectors = [ ".ui__button.as-outline" ];
          tokens.accent = "var(--rx-gray-02-hsl)";
        }
        {
          selectors = [ ".rc-datepicker" ];
          tokens.accent = hslTriplet c.accent;
        }
      ];

      componentLines = lib.concatMap (
        { selectors, tokens }:
        [
          (
            concatStringsSep ",\n" (map (selector: "html[data-theme=dark][data-color] ${selector}") selectors)
            + " {"
          )
        ]
        ++ lib.mapAttrsToList (name: declare "--${name}") tokens
        ++ [ "}" ]
      ) componentTokens;

      # .cm-s-dark outranks the app's theme rules, which reach three classes
      # (`.dark .cm-s-lsradix.cm-s-dark`, `.cm-s-lsradix.cm-s-dark.CodeMirror
      # ::selection`).
      cm = "html[data-theme=dark] .CodeMirror.cm-s-dark";
      root = "html[data-theme=dark][data-color]";
      logseq = "html[data-theme=dark][data-color=logseq]";
      card = "${root} .cp__right-sidebar .sidebar-item";
      hoverOverlay = rgbString c.bright "0.08";
      activeOverlay = rgbString c.bright "0.13";
      menuSelection = rgbString c.accent "0.15";
      widgetShadow = "rgb(0 0 0 / 0.36) 0 0 8px 2px";

      iconOverrides = palette.icons or { };
      iconColor =
        { name, fallback, ... }:
        if iconOverrides.${name} or null == null then
          lib.getAttrFromPath fallback c
        else
          iconOverrides.${name};
      # Blink stores a colour set through the CSSOM in the style attribute as
      # `rgb(r, g, b)` and a custom property as written; match both forms.
      inlineStyle =
        hex:
        let
          channels = concatStringsSep ", " (map toString (parseHex hex));
        in
        ":is([style*=\"rgb(${channels})\"], [style*=\"${hex}\" i])";
      iconRules = lib.concatMap (
        preset:
        let
          match = inlineStyle preset.hex;
          color = iconColor preset;
        in
        [
          "${root} :is(.ls-icon-color-wrap, .icon-cp-container)${match},"
          "${root} .cp__emoji-icon-picker .color-picker > strong${match} { color: ${color} !important; }"
          "${root} .cp__emoji-icon-picker${match} { --ls-color-icon-preset: ${color} !important; }"
          "${root} .color-picker-presets .it${match} { background-color: ${color} !important; }"
        ]
      ) iconPresets;

      codeRules = [
        " { background-color: ${c.sidebar}; color: ${c.text}; text-shadow: none; }"
        " .CodeMirror-gutters { background-color: ${c.sidebar}; border-right: 0; }"
        " .CodeMirror-linenumber { color: ${c.dim}; }"
        " .CodeMirror-cursor { border-left-color: ${c.text}; }"
        " div.CodeMirror-selected { background: ${c.selection}; }"
        " ::selection { background: ${c.selection}; }"
        " .CodeMirror-activeline-background { background: ${c.popup}; }"
        " .cm-keyword { color: ${s.keyword}; }"
        " .cm-operator { color: ${s.keyword}; }"
        " .cm-atom { color: ${s.constant}; }"
        " .cm-number { color: ${s.constant}; }"
        " .cm-property { color: ${s.constant}; }"
        " .cm-attribute { color: ${s.constant}; }"
        " .cm-qualifier { color: ${s.constant}; }"
        " .cm-def { color: ${s.function}; }"
        " .cm-variable { color: ${s.variable}; }"
        " .cm-variable-2 { color: ${s.parameter}; }"
        " .cm-variable-3, ${cm} .cm-type { color: ${s.type}; }"
        " .cm-builtin { color: ${s.type}; }"
        " .cm-string { color: ${s.string}; }"
        " .cm-string-2 { color: ${s.regexp}; }"
        " .cm-comment { color: ${s.comment}; font-style: italic; }"
        " .cm-meta { color: ${c.muted}; }"
        " .cm-tag { color: ${s.tag}; }"
        " .cm-bracket { color: ${c.text}; }"
        " .cm-header { color: ${s.heading}; font-weight: 600; }"
        " .cm-quote { color: ${c.muted}; }"
        " .cm-link { color: ${s.string}; }"
        " .cm-hr { border-top-color: ${c.border}; }"
        " .cm-error, ${cm} .cm-invalidchar { color: ${s.invalid}; }"
        " .CodeMirror-matchingbracket { color: ${c.bright} !important; outline: 1px solid ${c.subtle}; }"
        " .CodeMirror-nonmatchingbracket { color: ${s.invalid} !important; }"
      ];
    in
    lib.concatLines (
      [
        "/* Generated by nix-logseq-git-flake (homeManagerModules.default). */"
        ""
        # Unlayered and loaded after the app sheet. The variables go on html,
        # body, and .dark-theme because every accent except `logseq` and
        # `none` redeclares the scales on body (colors.css).
        "html[data-theme=dark][data-color],"
        "html[data-theme=dark][data-color] body,"
        "html[data-theme=dark][data-color] .dark-theme {"
        "  /* Radix neutral scale (radix.css) */"
      ]
      ++ grayLines "--rx-gray" "hsl"
      ++ [
        ""
        "  /* Logseq neutral scale (colors.css) */"
      ]
      ++ grayLines "--lx-gray" "alpha"
      ++ [
        ""
        "  /* Logseq accent scale (colors.css) */"
      ]
      ++ accentLines
      ++ [
        ""
        "  /* shadcn-style HSL triplets (shui.css, colors.css) */"
      ]
      ++ hslLines
      ++ [
        ""
        "  /* Classic --ls-* palette (vars-classic.css, colors.css) */"
      ]
      ++ lsLines
      ++ [
        "}"
        ""
        "/* shui.css paints the page #161616, or #002b36 under the logseq accent. */"
        "html[data-theme=dark][data-color] { background-color: ${c.background}; }"
        ""
        "/* The none accent paints text selection from --primary (colors.css); every"
        "   other accent uses the selection variable. */"
        "html[data-theme=dark][data-color=none] ::selection { background-color: var(--ls-selection-background-color); }"
        ""
        "/* Component tokens shui.css re-tints under the logseq accent. */"
      ]
      ++ componentLines
      ++ [
        ""
        "/* The logseq accent paints these with accent step 1, nearly the page"
        "   colour here, and fades palette groups; use the app's rules for the"
        "   other accents. */"
        "${logseq} .cp__themes-installed .it.is-active,"
        "${logseq} .cp__themes-installed .it:hover { background-color: var(--lx-gray-06); }"
        "${logseq} .ui__button.as-ghost:hover { background-color: hsl(var(--secondary) / 0.7); }"
        "${logseq} .form-input { border-color: var(--lx-gray-07); }"
        "${logseq} .cp__cmdk .border-gray-06,"
        "${logseq} .cp__cmdk .border-gray-07 { opacity: 1; }"
        ""
        "/* Inline code sets step 11 text on its step 6 chip, too close in this"
        "   palette. */"
        "${root} :not(pre) > code { color: var(--lx-gray-12); }"
        ""
        "/* VS Code-style layout: the top bar and both sidebars sit on gray step 2"
        "   around step 1 content, with step 4 edges between them. */"
        "${root} .cp__header { background-color: var(--lx-gray-02); box-shadow: 0 1px 0 var(--lx-gray-04); }"
        "/* The collaborators group (header.cljs) fills itself with step 1. */"
        "${root} .cp__header .bg-gray-01 { background-color: transparent; }"
        "${root} .left-sidebar-inner.as-container { border-right-color: var(--lx-gray-04); }"
        "${root} .cp__right-sidebar-inner { box-shadow: inset 1px 0 0 var(--lx-gray-04); }"
        "${root} .cp__right-sidebar-inner,"
        "${root} .cp__right-sidebar-topbar,"
        "${root} .cp__right-sidebar-settings-btn { background-color: var(--lx-gray-02); }"
        "/* Right-sidebar cards are content panes, so what they hold keeps the"
        "   main page's surfaces. */"
        "${card} { background-color: var(--lx-gray-01); box-shadow: 0 0 0 1px var(--lx-gray-04); }"
        "${card} .sidebar-item-header,"
        "${card}.item-type-block .sidebar-item-header,"
        "${card}.collapsed.item-type-block .sidebar-item-header,"
        "${root} .sidebar-item .cp__shortcut-page-x { background: var(--lx-gray-01); }"
        ""
        "/* Lists: translucent `bright` overlays, 8% on hover and 13% with `bright`"
        "   text on the active item. */"
        "${root} .left-sidebar-inner a.item:hover,"
        "${root} .left-sidebar-inner .sidebar-content-group-inner > .hd:not(.non-collapsable):hover,"
        "${root} .left-sidebar-inner .sidebar-content-group-inner > .bd ul li > a:first-of-type:hover,"
        "${root} .cp__settings-inner .settings-menu-item:hover,"
        "${root} [data-cmdk-item][data-hoverable]:not([data-kb-highlighted]):hover { background-color: ${hoverOverlay}; }"
        "${root} .left-sidebar-inner a.item.active,"
        "${root} .left-sidebar-inner .sidebar-content-group-inner > .bd ul li > a:first-of-type[data-popup-active],"
        "${root} .cp__settings-inner aside > ul > li.active {"
        "  background-color: ${activeOverlay};"
        "  color: ${c.bright};"
        "}"
        "${root} .cp__settings-inner aside > ul > li.active .settings-menu-link { color: ${c.bright}; }"
        ""
        "/* Menus on the widget background with a border and shadow; the"
        "   highlighted item, and the editor autocomplete's chosen row, is tinted"
        "   and outlined in the accent. */"
        "${root} :is(.ui__dropdown-menu-content, .ui__context-menu-content, .ui__popover-content, .ui__select-content),"
        "${root} :is(.menu-links-wrapper, .dropdown-wrapper) {"
        "  border-color: var(--lx-gray-04);"
        "  border-radius: 6px;"
        "  box-shadow: ${widgetShadow};"
        "}"
        "${root} :is(.ui__dropdown-menu-content, .ui__context-menu-content, .ui__select-content) [data-highlighted],"
        "${root} :is(.menu-links-wrapper, .dropdown-wrapper) .menu-link:hover,"
        "${root} #ui__ac-inner .menu-link.chosen {"
        "  background-color: ${menuSelection};"
        "  border-radius: 4px;"
        "  color: ${c.text};"
        "  outline: 1px solid ${c.accent};"
        "  outline-offset: -1px;"
        "}"
        ""
        "/* Dialogs on gray step 2 over a dimmed page; the keyboard-selected"
        "   command palette row in the focus fill, like a VS Code quick input"
        "   row. */"
        "${root} .ui__dialog-overlay { background-color: rgb(0 0 0 / 0.4); }"
        "${root} .ui__dialog-content {"
        "  background-color: var(--lx-gray-02);"
        "  border-color: var(--lx-gray-04);"
        "  border-radius: 6px;"
        "  box-shadow: ${widgetShadow};"
        "}"
        "${root} [data-cmdk-item][data-kb-highlighted] { background-color: ${c.accentStrong}; color: ${c.onAccent}; }"
        "${root} [data-cmdk-item][data-kb-highlighted] * { background-color: transparent; color: ${c.onAccent}; }"
        ""
        "/* Scrollbar thumbs on gray step 9 over a transparent track. */"
        "${root},"
        "${root} #main-content-container { scrollbar-color: var(--lx-gray-09) transparent; }"
        ""
        "/* Icon colour presets: node icons, the picker's icon grid, its palette"
        "   button, and its swatches. Each preset is an inline style, which only"
        "   !important out-ranks. */"
      ]
      ++ iconRules
      ++ [
        ""
        "/* Code blocks: CodeMirror 5 theme 'solarized dark' without an accent,"
        "   'lsradix dark' with one (extensions/code.cljs). */"
      ]
      ++ map (rule: cm + rule) codeRules
      ++ lib.optionals (extraCss != "") [
        ""
        extraCss
      ]
    );
in
{
  inherit defaultColors iconPresets render;
}
