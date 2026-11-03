"""Fail when theme.css sets a custom property the pinned app never reads live.

usage: theme-plugin-reads.py THEME_CSS STYLE_CSS [JS ...]

A var() read in STYLE_CSS counts unless it only matters in light mode (every
selector of its rule targets light mode, where a dark theme is not loaded) or
it sits in the fallback of var(--x, ...) for an --x the theme sets, whose value
then always wins. Any var() in the JS bundles counts. The numbered steps of a
scale (--rx-gray-01-hsl ... --rx-gray-12-hsl) pass together once one step is
read, so a restyle that moves a component to another step stays themed.
"""

import re
import sys

VAR = re.compile(r"var\(\s*(--[A-Za-z0-9_-]+)")
LIGHT = re.compile(r"\[data-theme=\"?light\"?\]|\.white-theme|\.light-theme")


def declared_by(theme_css):
    return set(re.findall(r"^  (--[A-Za-z0-9_-]+):", theme_css, re.MULTILINE))


def live_css_reads(css, declared):
    live = set()
    blocks = []  # preludes of the open { } blocks
    prelude = []  # text since the last ; { or }
    frames = []  # open parens: [var name or None, past its comma]
    i, n = 0, len(css)
    while i < n:
        ch = css[i]
        if ch in "\"'":
            j = i + 1
            while j < n and css[j] != ch:
                j += 2 if css[j] == "\\" else 1
            prelude.append(css[i : j + 1])
            i = j + 1
            continue
        if css.startswith("/*", i):
            end = css.find("*/", i + 2)
            i = n if end < 0 else end + 2
            continue
        match = VAR.match(css, i)
        if match:
            name = match.group(1)
            shadowed = any(fallback and outer in declared for outer, fallback in frames)
            rules = [block for block in blocks if not block.startswith("@")]
            light = bool(rules) and all(LIGHT.search(s) for s in rules[-1].split(","))
            if not shadowed and not light:
                live.add(name)
            frames.append([name, False])
            i = match.end()
            continue
        if ch == "(":
            frames.append([None, False])
        elif ch == ")":
            if frames:
                frames.pop()
        elif ch == "," and frames and frames[-1][0]:
            frames[-1][1] = True
        elif ch == "{":
            blocks.append("".join(prelude).strip())
            prelude, frames = [], []
        elif ch == "}":
            if blocks:
                blocks.pop()
            prelude, frames = [], []
        elif ch == ";" and not frames:
            prelude = []
        else:
            prelude.append(ch)
        i += 1
    return live


def scale_key(name):
    return re.sub(r"-[0-9]{2}(?=-|$)", "-NN", name)


def main():
    with open(sys.argv[1]) as handle:
        declared = declared_by(handle.read())
    if not declared:
        sys.exit("theme.css: declares no custom properties")
    with open(sys.argv[2]) as handle:
        live = live_css_reads(handle.read(), declared)
    for path in sys.argv[3:]:
        with open(path, errors="replace") as handle:
            live.update(VAR.findall(handle.read()))
    live_scales = {scale_key(name) for name in live}
    unread = sorted(name for name in declared if scale_key(name) not in live_scales)
    if unread:
        sys.exit(
            "theme.css: the pinned app never reads these in dark mode: "
            + " ".join(unread)
        )


main()
