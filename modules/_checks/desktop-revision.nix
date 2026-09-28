# Verifies the desktop payload stamps the same upstream revision the Nix CLI
# does. logseq.cli.server compares a running db-worker's revision against the
# requester's by exact string equality and, on a mismatch, stops and restarts it
# through stop-version-mismatched-server!, which passes allow-cross-owner? true.
# The Electron app (owner-source :electron) and logseq-cli (owner-source :cli)
# share ~/logseq/graphs/<graph>/db-worker.lock, so two differing stamps make any
# CLI command that touches an open graph evict the app's worker.
#
# Two stamping mechanisms have to agree, so both are probed: cli/vite.config.mjs
# defines LOGSEQ_CLI_REVISION for the bundled CLI, and the shadow-cljs
# build-metadata hook defines logseq.common.version/REVISION for the electron
# and db-worker-node builds. Each reads LOGSEQ_REVISION first and otherwise
# falls back to git on the checkout, which the workflow's patch step leaves
# dirty; only a build that honours LOGSEQ_REVISION carries the plain 40-char
# manifest.logseqRev that logseq-cli/build.nix stamps.
{
  logseqNodejs,
  logseqRev,
  logseqTree,
  pkgs,
}:
let
  # Read the normalized tree, not the raw payload: tree.nix globs the Darwin
  # bundle as `*.app` and renames it, so an upstream productName change keeps
  # working here instead of turning into a path-not-found with no explanation.
  asarPath =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "${logseqTree}/Logseq.app/Contents/Resources/app.asar"
    else
      "${logseqTree}/share/logseq/resources/app.asar";
in
pkgs.runCommand "logseq-desktop-revision-check"
  {
    nativeBuildInputs = [
      pkgs.asar
      pkgs.gnugrep
      logseqNodejs
    ];
  }
  ''
    # The CLI validates a readable/writable root-dir before it prints --version.
    export HOME=$TMPDIR
    export XDG_CACHE_HOME=$TMPDIR/cache

    asar_path="${asarPath}"
    if [ ! -f "$asar_path" ]; then
      echo "missing desktop ASAR at $asar_path" >&2
      exit 1
    fi

    drift_help() {
      echo "the desktop build dropped LOGSEQ_REVISION; see build-desktop.yml's Compile Logseq assets step" >&2
    }

    # Probe 1: the bundled CLI prints its define, so compare it exactly. This is
    # the vite side (LOGSEQ_CLI_REVISION).
    asar extract-file "$asar_path" js/logseq-cli.js

    version_status=0
    version_output=$(node ./logseq-cli.js --version 2>&1) || version_status=$?
    if [ "$version_status" -ne 0 ]; then
      echo "bundled desktop CLI --version exited $version_status" >&2
      echo "$version_output" >&2
      exit 1
    fi

    stamped=$(printf '%s\n' "$version_output" | sed -n 's/^Revision: //p')
    if [ -z "$stamped" ]; then
      echo "bundled desktop CLI --version printed no 'Revision:' line:" >&2
      echo "$version_output" >&2
      exit 1
    fi
    if [ "$stamped" != "${logseqRev}" ]; then
      echo "desktop payload's bundled CLI stamps revision '$stamped'" >&2
      echo "manifest.logseqRev (what logseq-cli stamps) is '${logseqRev}'" >&2
      drift_help
      exit 1
    fi

    # Probe 2: the shadow-cljs side. db-worker-node is the process the app spawns
    # and the CLI arbitrates over; electron.js is the app bundle that stops
    # workers it considers outdated. Neither runs standalone here, so assert the
    # define is present as a literal: a git-fallback build embeds the abbreviated
    # `-dirty` hash instead and cannot contain the full rev.
    for entry in electron.js js/db-worker-node.js; do
      asar extract-file "$asar_path" "$entry"
      bundle="$(basename "$entry")"
      if ! grep -qF "${logseqRev}" "$bundle"; then
        echo "desktop payload's $entry does not embed manifest.logseqRev '${logseqRev}'" >&2
        echo "the shadow-cljs build-metadata hook fell back to git describe" >&2
        drift_help
        exit 1
      fi
    done

    touch $out
  ''
