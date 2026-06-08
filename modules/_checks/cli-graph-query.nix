{ cli, pkgs }:
# Real-graph query check: drives the db-worker's @sqlite.org/sqlite-wasm path
# end-to-end. Probe 3 in cli-help.nix boots the worker and lists an empty graph
# but never writes a row, so a broken sqlite-wasm insert/select path still passes
# green. This check writes a unique marker block and reads it back with a
# Datascript query, so the bytes must survive a real WASM-sqlite round-trip on
# disk for the check to pass.
#
# Hermetic: no network, no auth, no secret service. It deliberately excludes
# keychain operations (login/logout/sync auth need a live secret service) and the
# other prebuilt addons (lightningcss, rolldown, zvec), which are not on the CLI
# query path.
pkgs.runCommand "logseq-cli-graph-query-check" { } ''
  export HOME=$TMPDIR
  export XDG_CACHE_HOME=$TMPDIR/cache

  graph_root=$TMPDIR/graph
  # Unique marker so a hit proves this write round-tripped, not a pre-existing
  # default page or block.
  marker="sqlite-wasm-roundtrip-marker-4711"
  # Datascript :find/:where over :block/title; the substring guard keeps the
  # assertion independent of how upstream normalizes stored block content. The
  # \" escapes survive the Nix indented string verbatim, so the worker receives
  # a real EDN string literal.
  query="[:find ?content :where [?b :block/title ?content] [(clojure.string/includes? ?content \"$marker\")]]"

  fail() {
    echo "$1" >&2
    printf '%s\n' "$2" >&2
    exit 1
  }

  # 1. Create the graph: boots the db-worker and initializes the sqlite-wasm store.
  create_status=0
  create_output=$(${cli}/bin/logseq-cli graph create -g probe --root-dir "$graph_root" 2>&1) || create_status=$?
  [ "$create_status" -eq 0 ] || fail "logseq-cli graph create exited $create_status" "$create_output"
  # server-start-timeout-orphan is upstream's worker-boot failure symptom; treat
  # it as failure even if the exit code is swallowed.
  if echo "$create_output" | ${pkgs.gnugrep}/bin/grep -qF 'server-start-timeout-orphan'; then
    fail "logseq-cli db-worker failed to start during graph create (server-start-timeout-orphan)" "$create_output"
  fi

  # 2. Negative control: the marker must NOT match before it is written. A hit
  #    here would mean the query is not actually filtering stored rows, which
  #    would make the read-back below a false positive.
  pre_status=0
  pre_output=$(${cli}/bin/logseq-cli query -g probe --root-dir "$graph_root" -o json --query "$query" 2>&1) || pre_status=$?
  [ "$pre_status" -eq 0 ] || fail "logseq-cli pre-write control query exited $pre_status" "$pre_output"
  if ! echo "$pre_output" | ${pkgs.gnugrep}/bin/grep -qF '"result":[]'; then
    fail "pre-write control query returned a non-empty result (marker leaked or query does not filter)" "$pre_output"
  fi

  # 3. Write a real block through the worker: the sqlite-wasm insert path.
  #    --target-page creates the page on demand, so no separate upsert page step.
  write_status=0
  write_output=$(${cli}/bin/logseq-cli upsert block -g probe --root-dir "$graph_root" --target-page ProbePage -c "$marker" 2>&1) || write_status=$?
  [ "$write_status" -eq 0 ] || fail "logseq-cli upsert block exited $write_status" "$write_output"

  # 4. Read it back via the Datascript query: the sqlite-wasm select path. The
  #    marker round-tripping through the on-disk store is the end-to-end proof.
  read_status=0
  read_output=$(${cli}/bin/logseq-cli query -g probe --root-dir "$graph_root" -o json --query "$query" 2>&1) || read_status=$?
  [ "$read_status" -eq 0 ] || fail "logseq-cli read-back query exited $read_status" "$read_output"
  if ! echo "$read_output" | ${pkgs.gnugrep}/bin/grep -qF '"status":"ok"'; then
    fail "read-back query did not report status ok" "$read_output"
  fi
  if ! echo "$read_output" | ${pkgs.gnugrep}/bin/grep -qF "$marker"; then
    fail "read-back query did not return the marker block; sqlite-wasm round-trip failed" "$read_output"
  fi

  touch $out
''
