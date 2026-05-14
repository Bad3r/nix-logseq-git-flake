{ cli, pkgs }:
pkgs.runCommand "logseq-cli-help-check" { } ''
  export HOME=$TMPDIR
  export XDG_CACHE_HOME=$TMPDIR/cache

  # Probe 1: --help exercises the help renderer's namespace.
  help_status=0
  help_output=$(${cli}/bin/logseq-cli --help 2>&1) || help_status=$?
  if [ "$help_status" -ne 0 ]; then
    echo "logseq-cli --help exited $help_status" >&2
    echo "$help_output" >&2
    exit 1
  fi
  # `Usage:` and `mcp-server` are stable substrings of the help output
  # produced by the upstream CLI; require both so a future silent fallthrough
  # doesn't get rubber-stamped.
  if ! echo "$help_output" | ${pkgs.gnugrep}/bin/grep -q '^Usage:'; then
    echo "logseq-cli --help output missing expected 'Usage:' substring:" >&2
    echo "$help_output" >&2
    exit 1
  fi
  if ! echo "$help_output" | ${pkgs.gnugrep}/bin/grep -q 'mcp-server'; then
    echo "logseq-cli --help output missing expected 'mcp-server' substring:" >&2
    echo "$help_output" >&2
    exit 1
  fi

  # Probe 2: `list` against an empty HOME forces graph-discovery namespaces
  # to load and catches missing vendored nbb runtime sources.
  list_status=0
  list_output=$(${cli}/bin/logseq-cli list 2>&1) || list_status=$?
  if [ "$list_status" -ne 0 ]; then
    echo "logseq-cli list exited $list_status" >&2
    echo "$list_output" >&2
    exit 1
  fi
  if ! echo "$list_output" | ${pkgs.gnugrep}/bin/grep -qF 'database version'; then
    echo "logseq-cli list output missing expected 'database version' substring:" >&2
    echo "$list_output" >&2
    exit 1
  fi

  touch $out
''
