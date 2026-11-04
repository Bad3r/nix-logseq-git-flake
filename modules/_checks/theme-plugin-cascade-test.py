"""Regression cases for theme-plugin-cascade.py.

usage: theme-plugin-cascade-test.py HELPER THEME_CSS STYLE_CSS [JS ...]

Each pipeline case edits the pinned style.css (or theme.css) and states
whether the helper must fail; the unit tables pin its predicates.
"""

import importlib.util
import re
import sys

# Importing the helper must not leave __pycache__ beside it.
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("cascade", sys.argv[1])
cascade = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cascade)

failures = []


def expect(label, got, want):
    if got != want:
        failures.append(f"{label}: got {got!r}, want {want!r}")


DECLARED = {"--declared", "--rx-red-11", "--tw-bg-opacity", "--shadow-alpha"}
FIXED_COLOUR = [
    ("gray", True),
    ("#808080", True),
    ("#ab", False),
    ("transparent", False),
    ("currentColor", False),
    ("inherit", False),
    ("AccentColor", False),
    ("1px solid red", True),
    ("0 0 0 1px tan inset", True),
    ("teal!important", True),
    ("url(red.png)", False),
    ('"red"', False),
    ("rgb(255 255 255/var(--tw-bg-opacity,1))", True),
    ("rgba(0,0,0,var(--shadow-alpha))", True),
    ("hsl(200 50% 50% / .5)", True),
    ("rgb(var(--x) 0 0)", False),
    ("rgba(var(--x),.5)", False),
    ("hsl(var(--x))", False),
    ("color(srgb 1 0 0)", True),
    ("color(srgb var(--r) 0 0)", False),
    ("rgb(from red r g b)", True),
    ("rgb(from var(--x) r g b)", False),
    ("var(--undeclared,#586e75)", True),
    ("var(--declared,#586e75)", False),
    ("var(--rx-red-11,red)", False),
    ("var(--undeclared)", False),
    ("var(--u1,var(--u2,red))", True),
    ("var(--u1,var(--declared,red))", False),
    ("color-mix(in srgb,currentColor 16%,transparent)", False),
    ("color-mix(in oklab,currentcolor 10%,transparent)", False),
    ("color-mix(in oklab,red 20%,transparent)", True),
    ("color-mix(in oklab,hsl(var(--p)) 20%,transparent)", False),
    ("linear-gradient(red,blue)", True),
    ("linear-gradient(var(--declared),transparent)", False),
    ("rgb(from currentColor r g b / 50%)", False),
    ("hsl(from currentcolor h s calc(l - 20%))", False),
    ("oklch(from currentColor l c h / .5)", False),
    ("color(from currentColor srgb r g b / .5)", False),
    ("rgb(from Canvas r g b)", False),
    ("rgb(from transparent r g b)", False),
    ("rgb(from\tcurrentColor r g b)", False),
    ("rgb(from var(--undeclared,red) r g b)", True),
    ("rgb(from var(--declared,red) r g b)", False),
    ("rgb(from #ff0000 r g b / .5)", True),
    ("color(srgb\tvar(--declared) 0 0)", False),
    ("#0000", False),
    ("#fff0", False),
    ("#ffffff00", False),
    ("#ffffff01", True),
    ("#ffff", True),
    ("0 0 #0000", False),
    ("rgba(0,0,0,0)", False),
    ("rgb(0 0 0 / 0)", False),
    ("rgb(0 0 0 / 0%)", False),
    ("rgba(0,0,0,.0)", False),
    ("hsl(0 0% 0% / 0.0)", False),
    ("rgb(0 0 0 / .05)", True),
]
for value, want in FIXED_COLOUR:
    expect(
        f"fixed_colour_value({value!r})",
        cascade.fixed_colour_value(value, DECLARED),
        want,
    )

CAN_BE_ROOT = [
    ("html", True),
    (":root", True),
    ("[data-color=logseq]", True),
    ("[data-color=logseq]:hover", True),
    ("*[data-color=x]", True),
    ("[data-theme=dark][data-color=logseq][data-x]", True),
    ("[data-highlight]", False),
    ("[data-cmdk-item][data-kb-highlighted]", False),
    ("*", False),
    (".x[data-color=yellow]", False),
    ("[data-color=logseq]::before", False),
    (":is(mark,.ls-highlight):hover", False),
]
for compound, want in CAN_BE_ROOT:
    got = cascade.can_be_root(cascade.compound_facts(compound))
    expect(f"can_be_root({compound!r})", got, want)

LIGHT_ONLY = [
    ("html[data-theme=light] .x", True),
    ("html[DATA-THEME = 'light'] .x", True),
    (".white-theme .x", True),
    (":is(html[data-theme=light]) .x", True),
    (".x:where([data-theme=light],[data-theme=light] *)", True),
    ("html:not([data-theme=light]) .x", False),
    (".x:has([data-theme=light])", False),
    (":is([data-theme=light],.y) .x", False),
]
for selector, want in LIGHT_ONLY:
    expect(f"light_only({selector!r})", cascade.light_only(selector), want)

IMPORTANT = [("1px !important", True), ("1px ! IMPORTANT", True), ("1px", False)]
for value, want in IMPORTANT:
    expect(f"important({value!r})", bool(cascade.IMPORTANT.search(value)), want)

with open(sys.argv[2]) as handle:
    THEME = handle.read()
with open(sys.argv[3]) as handle:
    STYLE = handle.read()
JS = cascade.js_variable_reads(sys.argv[4:])
CLOZE = ".cloze,.cloze-revealed{color:var(--ls-cloze-text-color)"
ROOT_BG = "html[data-theme=dark][data-color=logseq]{background-color:#002b36"
ROOT_VARS = "html[data-theme=dark][data-color=logseq]{--ls-primary-background-color:"
CALENDAR = "html[data-theme=dark][data-color=logseq] .ui__calendar{--accent:"
MARK = "mark{background:var(--ls-page-mark-bg-color"
ACCENT = "html[data-theme=dark][data-color=logseq]"


def replace(old, new, count=1):
    def edit(text):
        found = text.count(old)
        if found != count:
            raise AssertionError(f"{old!r} occurs {found} times, expected {count}")
        return text.replace(old, new)

    return edit


def append(rule):
    return lambda text: text + "\n" + rule


def rename(pattern, new):
    return lambda text: re.sub(pattern, new, text)


def with_dead_variable(text):
    return replace(
        "  --ls-cloze-text-color:",
        "  --ls-dropped-test: #123456;\n  --ls-cloze-text-color:",
    )(text)


# (name, style edit, theme edit, must fail)
PIPELINE = [
    ("pinned app", None, None, False),
    (
        "root --accent turned literal",
        replace("--accent:var(--rx-gray-12-hsl)", "--accent:0 0% 98%", 2),
        None,
        False,
    ),
    (
        "full -hsl rename",
        rename(r"--rx-gray-(\d\d)-hsl", r"--rx-gray-\1-hsl-v2"),
        None,
        True,
    ),
    (
        "rename of step 04",
        rename(r"--rx-gray-04-hsl", "--rx-gray-04-hsl-v2"),
        None,
        True,
    ),
    (
        "rename leaving light reads",
        lambda t: (
            rename(r"--rx-gray-(\d\d)-hsl", r"--rx-gray-\1-hsl-v2")(t)
            + "".join(
                f"html[data-theme=light] .keep-{n}{{color:hsl(var(--rx-gray-{n}-hsl))}}"
                for n in ("02", "04", "05")
            )
        ),
        None,
        True,
    ),
    (
        "cloze read only under :is(light)",
        replace(
            CLOZE,
            ":is(html[data-theme=light]) .cloze,:is(html[data-theme=light]) .cloze-revealed{color:var(--ls-cloze-text-color)",
        ),
        None,
        True,
    ),
    (
        "cloze read only under :where(light)",
        replace(
            CLOZE,
            ".cloze:where([data-theme=light],[data-theme=light] *),.cloze-revealed:where([data-theme=light],[data-theme=light] *){color:var(--ls-cloze-text-color)",
        ),
        None,
        True,
    ),
    ("dead variable", None, with_dead_variable, True),
    (
        "dead alias of a dead variable",
        append(":root{--dead-alias:var(--ls-dropped-test)}"),
        with_dead_variable,
        True,
    ),
    (
        "painted alias of a variable",
        append(
            ":root{--dead-alias:var(--ls-dropped-test)} .x{color:var(--dead-alias)}"
        ),
        with_dead_variable,
        False,
    ),
    (
        "read under :where(light)",
        append(":where(html[data-theme=light]) .x{color:var(--ls-dropped-test)}"),
        with_dead_variable,
        True,
    ),
    (
        "read under [DATA-THEME = light]",
        append('html[ data-theme = "light" ] .x{color:var(--ls-dropped-test)}'),
        with_dead_variable,
        True,
    ),
    (
        "read under :not(light)",
        append("html:not([data-theme=light]) .x{color:var(--ls-dropped-test)}"),
        with_dead_variable,
        False,
    ),
    (
        "read under :has(light)",
        append(".x:has([data-theme=light]){color:var(--ls-dropped-test)}"),
        with_dead_variable,
        False,
    ),
    (
        "read under :is(light, other)",
        append(":is([data-theme=light],.y) .x{color:var(--ls-dropped-test)}"),
        with_dead_variable,
        False,
    ),
    (
        "read through VAR()",
        append(".x{color:VAR(--ls-dropped-test)}"),
        with_dead_variable,
        False,
    ),
    (
        "accent ::selection under :is()",
        append(":is(html[data-color=blue]) ::selection{background-color:red}"),
        None,
        True,
    ),
    (
        "accent ::selection in BACKGROUND-COLOR",
        append("html[data-color=blue] ::selection{BACKGROUND-COLOR:red}"),
        None,
        True,
    ),
    (
        "padded upper-case accent redeclaration",
        append('HTML[ DATA-COLOR = "logseq" ] .ui__new{--muted:1 1% 1%}'),
        None,
        True,
    ),
    (
        "! IMPORTANT accent redeclaration",
        append(f"{ACCENT} .ui__calendar{{--accent:196 100% 15% ! IMPORTANT}}"),
        None,
        True,
    ),
    (
        "layered accent redeclaration",
        append(f"@LAYER base{{{ACCENT} .ui__select-content.a.b{{--accent:1 1% 1%}}}}"),
        None,
        False,
    ),
    (
        "bare accent component paint",
        append("[data-color=logseq] .ui__popover-content{background:#002b36}"),
        None,
        True,
    ),
    (
        "bare accent redeclaration",
        append("[data-color=logseq] .ui__new{--muted:1 1% 1%}"),
        None,
        True,
    ),
    (
        "bare accent ::selection",
        append("[data-color=logseq] ::selection{background-color:red}"),
        None,
        True,
    ),
    (
        "PDF highlight redeclaration",
        append(".hls-text-region-item[data-color=yellow]{--muted:1 1% 1%}"),
        None,
        False,
    ),
    (
        "PDF container redeclaration",
        append(".extensions__pdf-container [data-color=blue]{--muted:1 1% 1%}"),
        None,
        False,
    ),
    (
        "PDF highlight paint",
        append(".hls-text-region-item[data-color=yellow]{background-color:#ff0}"),
        None,
        False,
    ),
    (
        "root background without html",
        replace(
            ROOT_BG, "[data-theme=dark][data-color=logseq]{background-color:#002b36"
        ),
        None,
        False,
    ),
    (
        "root background on :root",
        replace(
            ROOT_BG,
            ":root[data-theme=dark][data-color=logseq]{background-color:#002b36",
        ),
        None,
        True,
    ),
    (
        "root variables without html",
        replace(
            ROOT_VARS,
            "[data-theme=dark][data-color=logseq]{--ls-primary-background-color:",
        ),
        None,
        False,
    ),
    (
        "calendar token without html",
        replace(
            CALENDAR, "[data-theme=dark][data-color=logseq] .ui__calendar{--accent:"
        ),
        None,
        False,
    ),
    (
        "calendar token out-ranking the theme",
        replace(
            CALENDAR,
            "[data-theme=dark][data-color=logseq][data-x] .ui__calendar.ui__calendar{--accent:",
        ),
        None,
        True,
    ),
    (
        "root background out-ranking the theme",
        append(
            "[data-theme=dark][data-color=logseq][data-x]{background-color:#002b36}"
        ),
        None,
        True,
    ),
    ("named colour teal", append(f"{ACCENT} .ls-block{{color:teal}}"), None, True),
    ("named colour gray", append(f"{ACCENT} .ls-block{{color:gray}}"), None, True),
    ("hex colour", append(f"{ACCENT} .ls-block{{color:#808080}}"), None, True),
    (
        "colour word in a variable name",
        append(f"{ACCENT} .ls-block{{border:1px solid var(--rx-red-09)}}"),
        None,
        False,
    ),
    (
        "colour word in a url",
        append(f"{ACCENT} .ls-block{{background:url(red.png) no-repeat}}"),
        None,
        False,
    ),
    ("transparent", append(f"{ACCENT} .ls-block{{color:transparent}}"), None, False),
    (
        "mark reader on [data-highlight]",
        replace(MARK, "[data-highlight]{background:var(--ls-page-mark-bg-color"),
        None,
        False,
    ),
    (
        "mark reader on :is(mark,.ls-highlight):hover",
        replace(
            MARK, ":is(mark,.ls-highlight):hover{background:var(--ls-page-mark-bg-color"
        ),
        None,
        False,
    ),
    (
        "mark reader on .ls-highlight",
        replace(MARK, ".ls-highlight{background:var(--ls-page-mark-bg-color"),
        None,
        False,
    ),
    (
        "declared variable, named fallback",
        append(f"{ACCENT} .tippy-tooltip{{border-color:var(--rx-red-11,red)}}"),
        None,
        False,
    ),
    (
        "declared variable, hex fallback",
        append(f"{ACCENT} .tippy-tooltip{{border-color:var(--rx-red-11,#ff0000)}}"),
        None,
        False,
    ),
    (
        "undeclared variable, hex fallback",
        append(f"{ACCENT} .cp__foo{{color:var(--ls-foo-color,#586e75)}}"),
        None,
        True,
    ),
    ("hex control", append(f"{ACCENT} .cp__foo{{color:#586e75}}"), None, True),
    (
        "var() only in the alpha",
        append(
            f"{ACCENT} .cp__foo{{--tw-bg-opacity:1;background-color:rgb(255 255 255/var(--tw-bg-opacity,1))}}"
        ),
        None,
        True,
    ),
    (
        "var() only in the legacy alpha",
        append(
            f"{ACCENT} .cp__foo{{box-shadow:0 1px 2px rgba(0,0,0,var(--shadow-alpha))}}"
        ),
        None,
        True,
    ),
    (
        "currentColor mix",
        append(
            f"{ACCENT} .cp__foo{{background-color:color-mix(in srgb,currentColor 16%,transparent)}}"
        ),
        None,
        False,
    ),
    (
        "Tailwind bg-current/10",
        append(
            "html[data-color=logseq] .bg-current-10{background-color:color-mix(in oklab,currentcolor 10%,transparent)}"
        ),
        None,
        False,
    ),
    (
        "non-root attribute ancestor",
        append("[data-foo] .ls-block{color:gray}"),
        None,
        False,
    ),
    (
        "bare accent ancestor",
        append("[data-color=logseq] .ls-block{color:gray}"),
        None,
        True,
    ),
    (
        "relative colour from currentColor",
        append(
            f"{ACCENT} .cp__foo{{background-color:rgb(from currentColor r g b / 50%)}}"
        ),
        None,
        False,
    ),
    (
        "relative colour from an undeclared variable's fallback",
        append(
            f"{ACCENT} .cp__foo{{background-color:rgb(from var(--ls-foo,red) r g b)}}"
        ),
        None,
        True,
    ),
    (
        "Tailwind zero-alpha shadow reset",
        append(f"{ACCENT} .cp__foo{{box-shadow:0 0 #0000}}"),
        None,
        False,
    ),
    (
        "zero-alpha rgba",
        append(f"{ACCENT} .cp__foo{{background-color:rgba(0,0,0,0)}}"),
        None,
        False,
    ),
]
for name, style_edit, theme_edit, must_fail in PIPELINE:
    style = style_edit(STYLE) if style_edit else STYLE
    theme = theme_edit(THEME) if theme_edit else THEME
    result = cascade.problem(theme, style, JS)
    expect(f"pipeline {name!r} fails", result is not None, must_fail)

if failures:
    sys.exit("theme-plugin-cascade tests failed:\n  " + "\n  ".join(failures))
print(
    f"theme-plugin-cascade tests: {len(FIXED_COLOUR) + len(CAN_BE_ROOT) + len(LIGHT_ONLY) + len(IMPORTANT) + len(PIPELINE)} cases passed"
)
