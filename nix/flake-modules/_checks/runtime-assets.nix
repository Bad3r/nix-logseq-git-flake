{
  logseqSrc,
  payload,
  pkgs,
}:
pkgs.runCommand "logseq-runtime-assets-check"
  {
    nativeBuildInputs = [
      pkgs.asar
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
    ];
  }
  ''
    asar_path="${payload}/resources/app.asar"
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

    awk '
      /to: path\.join\(staticJsDir,/ {
        if (match($0, /staticJsDir,[[:space:]]*"[^"]+"/)) {
          pair = substr($0, RSTART, RLENGTH)
          match(pair, /"[^"]+"/)
          path = substr(pair, RSTART + 1, RLENGTH - 2)
          optional = 0
          in_pair = 1
        }
        next
      }
      in_pair && /optional: true/ {
        optional = 1
      }
      in_pair && /^[[:space:]]*}[,]?[[:space:]]*$/ {
        if (!optional) {
          print path
        }
        path = ""
        optional = 0
        in_pair = 0
      }
    ' "$prepare_script" > required-runtime-names

    sed -nE 's/.*fs\.rm\(path\.join\(staticDir, "([^"]+)".*/\/\1/p' \
      "$prepare_script" > forbidden-root-entries

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
