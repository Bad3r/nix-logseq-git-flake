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
    copy_to_static_js = re.compile(
        r"to\s*:\s*path\.join\(\s*staticJsDir\s*,\s*" + js_string + r"\s*\)",
        re.DOTALL,
    )
    remove_from_static_root = re.compile(
        r"fs\.rm\(\s*path\.join\(\s*staticDir\s*,\s*" + js_string + r"\s*\)",
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

    required_runtime_names = []
    for match in copy_to_static_js.finditer(source):
        object_start = source.rfind("{", 0, match.start())
        object_end = source.find("}", match.end())
        object_source = source[object_start:object_end] if object_start != -1 and object_end != -1 else ""
        if not optional_true.search(object_source):
            required_runtime_names.append(js_string_value(match))

    forbidden_root_entries = [
        "/" + js_string_value(match).lstrip("/")
        for match in remove_from_static_root.finditer(source)
    ]

    Path("required-runtime-names").write_text(
        "".join(f"{name}\n" for name in unique(required_runtime_names))
    )
    Path("forbidden-root-entries").write_text(
        "".join(f"{path}\n" for path in unique(forbidden_root_entries))
    )
    PY

    if [ ! -s required-runtime-names ]; then
      echo "could not derive required runtime entries from $prepare_script" >&2
      exit 1
    fi
    if [ ! -s forbidden-root-entries ]; then
      echo "could not derive removed root runtime entries from $prepare_script" >&2
      exit 1
    fi

    status=0
    while IFS= read -r name; do
      static_entry="/js/$name"
      root_entry="/$name"
      if ! grep -qxF "$static_entry" entries && ! grep -qxF "$root_entry" entries; then
        echo "missing required ASAR runtime entry derived from prepare-desktop-runtime-js.mjs: $static_entry or $root_entry" >&2
        status=1
      fi
    done < required-runtime-names

    while IFS= read -r path; do
      name="''${path#/}"
      if grep -qxF "/js/$name" entries && grep -qxF "$path" entries; then
        echo "stale root-level ASAR runtime entry duplicates staged static/js entry: $path" >&2
        status=1
      fi
    done < forbidden-root-entries

    if [ "$status" -ne 0 ]; then
      echo "expected runtime entries in current static/js or legacy root layout:" >&2
      while IFS= read -r name; do
        echo "  /js/$name or /$name" >&2
      done < required-runtime-names
      echo "root-level runtime entries checked for duplicate cleanup:" >&2
      sed 's/^/  /' forbidden-root-entries >&2
      echo "matching runtime entries found in ASAR:" >&2
      while IFS= read -r name; do
        grep -xF "/$name" entries >&2 || true
        grep -xF "/js/$name" entries >&2 || true
      done < required-runtime-names
      exit 1
    fi

    touch $out
  ''
