{ cli, pkgs }:
pkgs.runCommand "logseq-cli-help-check" { } ''
  export HOME=$TMPDIR
  export XDG_CACHE_HOME=$TMPDIR/cache

  # Probe 1: --help exercises the help renderer's command-table namespace.
  help_status=0
  help_output=$(${cli}/bin/logseq-cli --help 2>&1) || help_status=$?
  if [ "$help_status" -ne 0 ]; then
    echo "logseq-cli --help exited $help_status" >&2
    echo "$help_output" >&2
    exit 1
  fi
  # `Usage:` and the `doctor` subcommand are stable substrings of the grouped
  # help table; require both so a future silent fallthrough that prints a
  # degenerate banner instead of the real command table is not rubber-stamped.
  if ! echo "$help_output" | ${pkgs.gnugrep}/bin/grep -q '^Usage:'; then
    echo "logseq-cli --help output missing expected 'Usage:' substring:" >&2
    echo "$help_output" >&2
    exit 1
  fi
  if ! echo "$help_output" | ${pkgs.gnugrep}/bin/grep -q 'doctor'; then
    echo "logseq-cli --help output missing expected 'doctor' command:" >&2
    echo "$help_output" >&2
    exit 1
  fi

  # Probe 2: `doctor` against an empty HOME forces the shadow-cljs release
  # runtime to load and locate the bundled db-worker-node.js, catching a broken
  # release build or a missing runtime asset. It is hermetic: no network, no
  # auth, only local file and root-dir checks.
  doctor_status=0
  doctor_output=$(${cli}/bin/logseq-cli doctor 2>&1) || doctor_status=$?
  if [ "$doctor_status" -ne 0 ]; then
    echo "logseq-cli doctor exited $doctor_status" >&2
    echo "$doctor_output" >&2
    exit 1
  fi
  if ! echo "$doctor_output" | ${pkgs.gnugrep}/bin/grep -qF 'Doctor: ok'; then
    echo "logseq-cli doctor output missing expected 'Doctor: ok' substring:" >&2
    echo "$doctor_output" >&2
    exit 1
  fi

  # Probe 3: spawn the db-worker. `doctor` only locates db-worker-node.js; it
  # never executes it, so a worker that aborts at startup (e.g. a missing native
  # binding such as keytar.node) passes while every db command is broken.
  # Creating a graph and listing its pages forces the worker to boot, acquire a
  # lock, and answer a query. Hermetic: no network, no auth, local files only.
  graph_root=$TMPDIR/graph
  worker_status=0
  worker_output=$(
    ${cli}/bin/logseq-cli graph create -g probe --root-dir "$graph_root" 2>&1 \
      && ${cli}/bin/logseq-cli list page -g probe --root-dir "$graph_root" 2>&1
  ) || worker_status=$?
  if [ "$worker_status" -ne 0 ]; then
    echo "logseq-cli db-worker probe exited $worker_status" >&2
    echo "$worker_output" >&2
    exit 1
  fi
  # server-start-timeout-orphan is upstream's worker startup symptom for a child
  # that dies before creating its lock; treat it as failure even if the exit code
  # is swallowed.
  if echo "$worker_output" | ${pkgs.gnugrep}/bin/grep -qF 'server-start-timeout-orphan'; then
    echo "logseq-cli db-worker failed to start (server-start-timeout-orphan):" >&2
    echo "$worker_output" >&2
    exit 1
  fi

  touch $out
''
