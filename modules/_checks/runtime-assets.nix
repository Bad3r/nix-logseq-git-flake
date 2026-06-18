# Verifies the desktop ASAR ships the runtime JS the app loads at startup. Derives
# the required entries from upstream scripts/prepare-desktop-runtime-js.mjs: every
# non-optional copyPairs destination under static/js/ must appear in the ASAR as
# /js/<name>.
{
  logseqSrc,
  payload,
  pkgs,
}:
let
  asarPath =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "${payload}/Logseq.app/Contents/Resources/app.asar"
    else
      "${payload}/resources/app.asar";
in
pkgs.runCommand "logseq-runtime-assets-check"
  {
    nativeBuildInputs = [
      pkgs.asar
      pkgs.gnugrep
      pkgs.python3
    ];
  }
  ''
    asar_path="${asarPath}"
    prepare_script="${logseqSrc}/scripts/prepare-desktop-runtime-js.mjs"
    if [ ! -f "$asar_path" ]; then
      echo "missing desktop ASAR at $asar_path" >&2
      exit 1
    fi
    if [ ! -f "$prepare_script" ]; then
      echo "missing upstream desktop runtime staging script: $prepare_script" >&2
      exit 1
    fi

    asar list "$asar_path" > entries

    PREPARE_SCRIPT="$prepare_script" python3 <<'PY'
    import os
    import re
    from pathlib import Path

    prepare_script = Path(os.environ["PREPARE_SCRIPT"])
    source = prepare_script.read_text()

    js_string = r"""(?:"(?P<dq>(?:\\.|[^"\\])*)"|'(?P<sq>(?:\\.|[^'\\])*)'|`(?P<bq>(?:\\.|[^`\\])*)`)"""
    const_string = re.compile(
        r"const\s+(?P<name>[A-Za-z_$][\w$]*)\s*=\s*" + js_string + r"\s*;",
        re.DOTALL,
    )
    to_static_js_literal = re.compile(
        r"to\s*:\s*path\.join\(\s*staticJsDir\s*,\s*" + js_string + r"\s*\)",
        re.DOTALL,
    )
    to_repo_root_spread = re.compile(
        r"to\s*:\s*path\.join\(\s*repoRoot\s*,\s*\.\.\.\s*(?P<ident>[A-Za-z_$][\w$]*)\s*\.split\(",
        re.DOTALL,
    )
    optional_true = re.compile(r"\boptional\s*:\s*true\b")

    def js_string_value(match):
        for group in ("dq", "sq", "bq"):
            value = match.group(group)
            if value is not None:
                return re.sub(r"\\([\"'`\\])", r"\1", value)
        raise ValueError("matched JavaScript string without a value")

    def unique(items):
        seen = set()
        result = []
        for item in items:
            if item not in seen:
                seen.add(item)
                result.append(item)
        return result

    def is_optional(match):
        object_start = source.rfind("{", 0, match.start())
        object_end = source.find("}", match.end())
        object_source = source[object_start:object_end] if object_start != -1 and object_end != -1 else ""
        return bool(optional_true.search(object_source))

    string_consts = {}
    for match in const_string.finditer(source):
        string_consts[match.group("name")] = js_string_value(match)

    # copyPairs destinations reach static/js/ either as path.join(staticJsDir,
    # "<name>") or path.join(repoRoot, ...<const>.split("/")) where <const> is a
    # "static/js/..." path string.
    required_runtime_names = []
    for match in to_static_js_literal.finditer(source):
        if not is_optional(match):
            required_runtime_names.append(js_string_value(match))
    for match in to_repo_root_spread.finditer(source):
        if is_optional(match):
            continue
        ident = match.group("ident")
        dest = string_consts.get(ident)
        if dest is None:
            raise SystemExit(
                "prepare-desktop-runtime-js.mjs: could not resolve string const "
                f"{ident!r} referenced by a non-optional copyPairs spread; "
                "update the parser in runtime-assets.nix"
            )
        parts = dest.split("/")
        if parts[:2] == ["static", "js"] and parts[-1]:
            required_runtime_names.append(parts[-1])

    Path("required-runtime-names").write_text(
        "".join(f"{name}\n" for name in unique(required_runtime_names))
    )
    PY

    if [ ! -s required-runtime-names ]; then
      echo "could not derive required runtime entries from $prepare_script" >&2
      exit 1
    fi

    status=0
    while IFS= read -r name; do
      if ! grep -qxF "/js/$name" entries; then
        echo "missing required ASAR runtime entry: /js/$name" >&2
        status=1
      fi
    done < required-runtime-names

    if [ "$status" -ne 0 ]; then
      echo "runtime entries required from prepare-desktop-runtime-js.mjs:" >&2
      sed 's:^:  /js/:' required-runtime-names >&2
      exit 1
    fi

    touch $out
  ''
