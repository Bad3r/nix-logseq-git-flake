"""Check theme.css against the pinned app's cascade in dark mode.

usage: theme-plugin-cascade.py THEME_CSS STYLE_CSS [JS ...]

Fails when the app redeclares a variable theme.css sets, on the root or in
an accent-scoped rule, to a value that does not start from a theme variable,
and theme.css does not out-rank it: that element and its subtree would keep
the app's colour. Also fails when an accent-scoped app rule paints a
property on an element theme.css paints that property on, or paints a colour
property with a literal colour no theme variable feeds, and theme.css does
not out-rank it. A rule is accent-scoped when it needs [data-color=...] on
the root element, where theme.cljs sets it: on a first compound that names
html or :root, or carries only attributes and pseudo-classes. [data-color]
on any other element (PDF highlights) is not an accent.

Also fails when theme.css sets a custom property whose value never reaches
a painted property in dark mode. A var() read in STYLE_CSS counts unless
every selector of its rule targets light mode (where a dark theme is not
loaded), it sits in the fallback of var(--x, ...) for an --x the theme sets,
or its declaration loses to a theme.css declaration of the same property on
the same element. A read inside a custom property declaration counts only
once that property is itself live, resolved to a fixpoint; reads in ordinary
properties and any var() in the JS bundles are live. theme.css custom
properties link chains too (their values reach the screen when the app
paints them), but theme.css's own painted reads never count. The numbered
steps of a scale (--rx-gray-01-hsl ... --rx-gray-12-hsl) pass together once
one step is live, so a restyle that moves a component to another step stays
themed. A selector needs light mode when a compound has a light simple
selector, or an :is() or :where() whose every argument needs light mode.

Also fails when theme.css reads a variable no dark-mode app rule or script
reads, out-ranked or not: its component tokens mirror app rules, and such a
mirror has gone stale.
This is what catches a rename the theme's own chains would otherwise keep
live.

This proves that some app rule or script consumes the value, not that the
element it selects is ever rendered.

The cascade model is deliberately narrow: a theme rule out-ranks an app rule
only when its ancestors are the dark-mode root (always true while the theme is
loaded), its subject compound is implied by the app rule's subject, and it is
at least as specific (theme.css loads later, unlayered) or the app rule sits
in a cascade layer.
"""

import re
import sys

# CSS keywords, at-rules, pseudo-classes, element and attribute names are
# ASCII case-insensitive; custom property names, classes, and attribute
# values are not.
VAR = re.compile(r"var\(\s*(--[A-Za-z0-9_-]+)", re.IGNORECASE)
IMPORTANT = re.compile(r"!\s*important\s*$", re.IGNORECASE)
ATTRIBUTE = re.compile(
    r"\[\s*([\w-]+)\s*(?:([~|^$*]?=)\s*"
    r"(?:\"([^\"]*)\"|'([^']*)'|([^\]\s]+))\s*([is])?\s*)?\]",
    re.IGNORECASE,
)
LIGHT = {"[data-theme=light]", ".white-theme", ".light-theme"}
# What holds on the root and body whenever a dark theme is loaded.
ROOT_CONTEXT = {"html", "[data-theme=dark]", "[data-theme]", "[data-color]"}
BODY_CONTEXT = {"body", ".dark-theme"}
ACCENT = re.compile(r"^\[data-color=")
SINGLE_COLON = re.compile(r"^:[^:]")
SIMPLE = re.compile(
    r"::[\w-]+(?:\([^)]*\))?"
    r"|:[\w-]+(?:\((?:[^()]|\([^()]*\))*\))?"
    r"|\[[^\]]*\]|#[\w-]+|\.(?:\\.|[\w-])+|\*|[A-Za-z][\w-]*"
)


class Declaration:
    def __init__(self, selectors, layered, prop, value):
        self.selectors = selectors
        self.layered = layered
        self.prop = prop
        self.value = value
        self.important = IMPORTANT.search(value) is not None


def split_top(text, separators):
    """Split at separators outside parentheses and brackets."""
    parts, depth, current = [], 0, []
    for ch in text:
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        if depth == 0 and ch in separators:
            parts.append("".join(current).strip())
            current = []
        else:
            current.append(ch)
    parts.append("".join(current).strip())
    return [part for part in parts if part]


def parse(css):
    """Flatten a stylesheet into declarations with their innermost rule."""
    declarations, blocks, text = [], [], []
    depth, i, n = 0, 0, len(css)

    def flush():
        chunk = "".join(text).strip()
        text.clear()
        rules = [prelude for prelude, at in blocks if not at]
        if not chunk or not rules or ":" not in chunk:
            return
        prop, value = chunk.split(":", 1)
        layered = any(
            at and prelude.lower().startswith("@layer") for prelude, at in blocks
        )
        selectors = split_top(rules[-1], ",")
        declarations.append(
            Declaration(selectors, layered, property_name(prop), value.strip())
        )

    while i < n:
        ch = css[i]
        if ch in "\"'":
            j = i + 1
            while j < n and css[j] != ch:
                j += 2 if css[j] == "\\" else 1
            text.append(css[i : j + 1])
            i = j + 1
            continue
        if css.startswith("/*", i):
            end = css.find("*/", i + 2)
            i = n if end < 0 else end + 2
            continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth = max(depth - 1, 0)
        if depth == 0 and ch == "{":
            prelude = "".join(text).strip()
            text.clear()
            blocks.append((prelude, prelude.startswith("@")))
        elif depth == 0 and ch == "}":
            flush()
            if blocks:
                blocks.pop()
        elif depth == 0 and ch == ";":
            flush()
        else:
            text.append(ch)
        i += 1
    return declarations


def compounds(selector):
    """Compound selectors of a complex selector, root first."""
    spaced = re.sub(r"\s*([>+~])\s*", r" \1 ", selector.strip())
    return [part for part in split_top(spaced, " ") if part not in (">", "+", "~")]


def property_name(prop):
    prop = prop.strip()
    return prop if prop.startswith("--") else prop.lower()


def canonical(simple):
    """One spelling per simple selector, so comparisons ignore case and quotes
    where CSS does."""
    if simple.startswith("["):
        match = ATTRIBUTE.fullmatch(simple)
        if not match:
            return simple
        name, operator, *quoted, flag = match.groups()
        if not operator:
            return f"[{name.lower()}]"
        value = next(v for v in quoted if v is not None)
        if flag and flag.lower() == "i":
            value = value.lower()
        return f"[{name.lower()}{operator}{value}]"
    if simple.startswith(":"):
        name, paren, args = simple.partition("(")
        return name.lower() + paren + args
    if simple[0].isalpha():
        return simple.lower()
    return simple


def simples(compound):
    return [canonical(simple) for simple in SIMPLE.findall(compound)]


def specificity(selector):
    total = [0, 0, 0]
    for compound in compounds(selector):
        for simple in simples(compound):
            if simple.startswith("::"):
                total[2] += 1
            elif simple.startswith(":"):
                name, _, args = simple[1:].partition("(")
                if name == "where":
                    continue
                if name in ("is", "not", "has", "matches"):
                    inner = [specificity(arg) for arg in split_top(args[:-1], ",")]
                    best = max(inner, default=(0, 0, 0))
                    total = [a + b for a, b in zip(total, best)]
                else:
                    total[1] += 1
            elif simple.startswith("#"):
                total[0] += 1
            elif simple.startswith((".", "[")):
                total[1] += 1
            elif simple != "*":
                total[2] += 1
    return tuple(total)


FORGIVING = {":is", ":where", ":matches", ":-webkit-any"}


def arguments(simple):
    """Selector list of :is() and its aliases, None for any other simple."""
    name, paren, args = simple.partition("(")
    if name not in FORGIVING or not paren:
        return None
    return split_top(args[:-1], ",")


def compound_facts(compound):
    """Simple selectors that hold on every element a compound matches,
    looking through :is() and :where() to what all their arguments share."""
    facts = set()
    for simple in simples(compound):
        args = arguments(simple)
        if args is None:
            facts.add(simple)
        elif args:
            facts |= set.intersection(*(compound_facts(compounds(a)[-1]) for a in args))
    return facts


def subject_facts(selector):
    """Simple selectors that hold on the element an app selector matches."""
    facts = compound_facts(compounds(selector)[-1])
    facts |= {re.sub(r"=.*\]$", "]", fact) for fact in facts if fact.startswith("[")}
    if "html" in facts or ":root" in facts:
        facts |= ROOT_CONTEXT
    if facts & BODY_CONTEXT:
        facts |= BODY_CONTEXT
    return facts


def prop_key(prop):
    return "background-color" if prop == "background" else prop


def root_facts(selector):
    """Simple selectors on the root compound, when the selector can start there.

    The first compound can match the root element when it names html or
    :root, or carries nothing that excludes it: only attributes and
    pseudo-classes, as in a bare `[data-color=logseq] .x`. A compound with a
    class, id, other element name, or pseudo-element is never the root.
    """
    facts = compound_facts(compounds(selector)[0])
    bare = all(f == "*" or f.startswith("[") or SINGLE_COLON.match(f) for f in facts)
    return facts if facts & {"html", ":root"} or (facts and bare) else set()


def accent_scoped(selector):
    """Whether the selector needs an accent on the root element, where
    theme.cljs sets data-color; [data-color] on any other element (PDF
    highlights) is not an accent."""
    return any(ACCENT.match(fact) for fact in root_facts(selector))


def anchored(selector):
    """Accent attributes a theme selector's root needs beyond dark mode.

    None when its ancestors are not just the root: the rule then reaches
    elements this model cannot place.
    """
    parts = compounds(selector)
    if len(parts) > 2 or re.search(r"[>+~]", selector):
        return None
    if len(parts) == 1:
        return set()
    extra = set(simples(parts[0])) - ROOT_CONTEXT
    return extra if all(ACCENT.match(fact) for fact in extra) else None


class Theme:
    def __init__(self, css):
        self.declarations = parse(css)
        self.custom = {d.prop for d in self.declarations if d.prop.startswith("--")}
        self.rules = {}
        for declaration in self.declarations:
            for selector in declaration.selectors:
                required = anchored(selector)
                if required is not None:
                    key = prop_key(declaration.prop)
                    self.rules.setdefault(key, []).append((selector, required))

    def targets(self, prop, selector):
        """Theme selectors for `prop` that match what `selector` matches."""
        facts = subject_facts(selector)
        pseudo = {fact for fact in facts if fact.startswith("::")}
        for theme_selector, required in self.rules.get(prop_key(prop), []):
            subject = set(simples(compounds(theme_selector)[-1]))
            if {
                s for s in subject if s.startswith("::")
            } == pseudo and subject <= facts:
                yield theme_selector, required

    def outranks(self, declaration, selector):
        """Whether theme.css wins `declaration` on what `selector` matches."""
        if declaration.important:
            return False
        root = root_facts(selector)
        for theme_selector, required in self.targets(declaration.prop, selector):
            if required <= root and (
                declaration.layered
                or specificity(theme_selector) >= specificity(selector)
            ):
                return True
        return False


def light_only(selector):
    """Whether a selector needs light mode on some compound. :is() and
    :where() need it when every argument does; :not() and :has() never
    make a selector light-only."""
    for compound in compounds(selector):
        for simple in simples(compound):
            args = arguments(simple)
            if simple in LIGHT or (args and all(light_only(a) for a in args)):
                return True
    return False


def dark_selectors(declaration):
    return [s for s in declaration.selectors if not light_only(s)]


def applies(declaration, theme):
    """Whether a declaration can still win somewhere in dark mode."""
    return any(not theme.outranks(declaration, s) for s in dark_selectors(declaration))


def reads(value, theme):
    """Variables a value reads, minus fallbacks of a variable the theme sets."""
    found, frames, i = set(), [], 0
    while i < len(value):
        match = VAR.match(value, i)
        if match:
            if not any(past and outer in theme.custom for outer, past in frames):
                found.add(match.group(1))
            frames.append([match.group(1), False])
            i = match.end()
            continue
        ch = value[i]
        if ch == "(":
            frames.append([None, False])
        elif ch == ")" and frames:
            frames.pop()
        elif ch == "," and frames and frames[-1][0]:
            frames[-1][1] = True
        i += 1
    return found


def live_variables(app, theme, js_reads):
    """Variables whose value reaches a painted property.

    Reads in ordinary properties and in the JS bundles are live. A read in a
    custom property declaration is live only once that property is, so an
    alias nothing reads keeps its inputs dead. theme.css custom property
    declarations add chain edges, since their value reaches the screen when
    the app paints that property, but theme.css's own painted reads are not
    the app consuming anything. A rename the theme's chains would hide is
    caught by the stale-read check in main().
    """
    painted, chains = set(js_reads), {}
    own = [d for d in theme.declarations if d.prop.startswith("--")]
    for declaration in [d for d in app if applies(d, theme)] + own:
        found = reads(declaration.value, theme)
        if declaration.prop.startswith("--"):
            chains.setdefault(declaration.prop, set()).update(found)
        else:
            painted |= found
    live, pending = set(), list(painted)
    while pending:
        name = pending.pop()
        if name not in live:
            live.add(name)
            pending.extend(chains.get(name, ()))
    return live


def unbeaten_redeclarations(app, theme):
    """App rules that pin a theme variable to a value the palette cannot reach.

    A redeclaration below the root beats the theme's root value by
    inheritance, so each one whose value does not start from a theme variable
    needs a theme rule that out-ranks it. That covers root and body rules and
    rules scoped to an accent ([data-color=...]); a component rule that
    applies under every accent is a fixed colour the app keeps whatever the
    accent (.primary-green), and the theme keeps it too.
    """
    for declaration in app:
        if declaration.prop not in theme.custom:
            continue
        first = VAR.search(declaration.value)
        if first and first.group(1) in theme.custom:
            continue
        for selector in dark_selectors(declaration):
            root = subject_facts(selector) & ({"html", ":root"} | BODY_CONTEXT)
            if not root and not accent_scoped(selector):
                continue
            if not theme.outranks(declaration, selector):
                yield f"{selector} {{ {declaration.prop}: {declaration.value} }}"


COLOUR_PROPERTY = re.compile(
    r"^(color|background(-color)?|border(-(top|right|bottom|left))?(-color)?"
    r"|outline(-color)?|box-shadow|fill|stroke|caret-color"
    r"|text-decoration(-color)?|accent-color|scrollbar-color)$"
)
COLOUR_LITERAL = re.compile(
    r"#[0-9a-f]{3,8}\b|\b(rgba?|hsla?|hwb|lab|lch|oklab|oklch|color)\(", re.IGNORECASE
)


def fixed_colour(declaration, theme):
    """A colour property set to a literal colour no theme variable feeds."""
    return (
        COLOUR_PROPERTY.match(declaration.prop) is not None
        and COLOUR_LITERAL.search(declaration.value) is not None
        and not reads(declaration.value, theme) & theme.custom
    )


def unbeaten_overrides(app, theme):
    """Accent-scoped app rules that paint over the palette: a property
    theme.css paints itself, or a fixed colour no theme variable feeds."""
    for declaration in app:
        if declaration.prop.startswith("--"):
            continue
        for selector in dark_selectors(declaration):
            if not accent_scoped(selector):
                continue
            claimed = any(theme.targets(declaration.prop, selector))
            if not claimed and not fixed_colour(declaration, theme):
                continue
            if not theme.outranks(declaration, selector):
                yield f"{selector} {{ {declaration.prop}: {declaration.value} }}"


def scale_key(name):
    return re.sub(r"-[0-9]{2}(?=-|$)", "-NN", name)


def main():
    with open(sys.argv[1]) as handle:
        theme = Theme(handle.read())
    if not theme.custom:
        sys.exit("theme.css: declares no custom properties")
    with open(sys.argv[2]) as handle:
        app = parse(handle.read())
    if not app:
        sys.exit("style.css: no declarations parsed")

    unbeaten = sorted(
        set(unbeaten_redeclarations(app, theme)) | set(unbeaten_overrides(app, theme))
    )
    if unbeaten:
        sys.exit(
            "theme.css: no rule out-ranks these app redeclarations:\n  "
            + "\n  ".join(unbeaten)
        )

    js_reads = set()
    for path in sys.argv[3:]:
        with open(path, errors="replace") as handle:
            js_reads.update(VAR.findall(handle.read()))
    # The component tokens mirror app rules the theme out-ranks; each variable
    # they read must still be one the app reads in a dark-mode rule (out-ranked
    # or not), or the mirror is stale.
    app_reads = js_reads | {
        name for d in app if dark_selectors(d) for name in VAR.findall(d.value)
    }
    theme_reads = set()
    for declaration in theme.declarations:
        theme_reads |= reads(declaration.value, theme)
    stale = sorted(theme_reads - app_reads)
    if stale:
        sys.exit(
            "theme.css: reads variables no dark-mode app rule reads: " + " ".join(stale)
        )

    live = live_variables(app, theme, js_reads)
    live_scales = {scale_key(name) for name in live}
    unread = sorted(n for n in theme.custom if scale_key(n) not in live_scales)
    if unread:
        sys.exit(
            "theme.css: the pinned app never reads these in dark mode: "
            + " ".join(unread)
        )


main()
