{ cli, pkgs }:
# Regression check for the patches/logseq-cli-auth-bind-loopback-address-families.patch
# behavior: `logseq-cli login` must serve its OAuth callback on both explicit
# loopback address families when the host supports them. Upstream binds the
# resolver's first "localhost" address only, so browser address-family policy
# can choose a callback address that the CLI never bound. The probe stays
# hermetic: the browser opener is stubbed to capture the authorize URL, and a
# deliberate state mismatch makes the CLI reject the callback before any
# token-exchange network traffic.
let
  # login! spawns `xdg-open <url>` on Linux and `open <url>` on Darwin via
  # PATH lookup; capture the URL instead of opening a browser. The temp file
  # plus mv keeps readers from seeing a partially written URL.
  openerStub = pkgs.writeShellScript "browser-opener-stub" ''
    printf '%s\n' "$1" >"$TMPDIR/authorize-url.tmp"
    mv "$TMPDIR/authorize-url.tmp" "$TMPDIR/authorize-url"
  '';
in
pkgs.runCommand "logseq-cli-login-callback-check" { } ''
  set -euo pipefail

  extract_state() {
    printf '%s' "$1" | ${pkgs.gnused}/bin/sed -n 's/^.*[?&]state=\([^&]*\).*$/\1/p' | ${pkgs.coreutils}/bin/tr -d '\r'
  }

  wait_for_authorize_url() {
    dir="$1"
    pid="$2"
    tries=0
    while [ ! -s "$dir/authorize-url" ]; do
      tries=$((tries + 1))
      if [ "$tries" -gt 120 ]; then
        echo "logseq-cli login did not produce an authorize URL within 120s" >&2
        cat "$dir/login-output" >&2
        return 1
      fi
      if ! kill -0 "$pid" 2>/dev/null; then
        echo "logseq-cli login exited before opening the browser:" >&2
        cat "$dir/login-output" >&2
        return 1
      fi
      sleep 1
    done
  }

  probe_family() {
    family="$1"
    callback_base="$2"
    dir="$TMPDIR/$family"
    login_pid=""
    trap 'if [ -n "$login_pid" ]; then kill "$login_pid" 2>/dev/null || true; wait "$login_pid" 2>/dev/null || true; login_pid=""; fi' EXIT

    mkdir -p "$dir/bin" "$dir/home" "$dir/cache"
    ln -s ${openerStub} "$dir/bin/xdg-open"
    ln -s ${openerStub} "$dir/bin/open"

    HOME="$dir/home" \
      TMPDIR="$dir" \
      XDG_CACHE_HOME="$dir/cache" \
      PATH="$dir/bin:$PATH" \
      ${cli}/bin/logseq-cli login >"$dir/login-output" 2>&1 &
    login_pid=$!

    # The authorize URL is written only after the callback server's listen
    # callback resolved, so its presence means the server is accepting
    # connections.
    wait_for_authorize_url "$dir" "$login_pid"

    authorize_url="$(cat "$dir/authorize-url")"
    state="$(extract_state "$authorize_url")"
    if [ -z "$state" ]; then
      echo "$family: authorize URL is missing the OAuth state parameter:" >&2
      printf '%s\n' "$authorize_url" >&2
      exit 1
    fi

    http_status=0
    if ! http_status="$(${pkgs.curl}/bin/curl --silent --show-error --noproxy '*' --max-time 10 \
      --output "$dir/callback-body" --write-out '%{http_code}' \
      "$callback_base?code=probe&state=mismatch-$state")"; then
      echo "$family: callback probe could not connect to $callback_base" >&2
      cat "$dir/login-output" >&2
      exit 1
    fi

    if [ "$http_status" != "400" ]; then
      echo "$family: expected HTTP 400 for a state-mismatch callback, got $http_status" >&2
      cat "$dir/callback-body" >&2
      exit 1
    fi
    if ! ${pkgs.gnugrep}/bin/grep -q 'state mismatch' "$dir/callback-body"; then
      echo "$family: callback response body missing the expected state-mismatch message:" >&2
      cat "$dir/callback-body" >&2
      exit 1
    fi

    # The rejected callback must settle the login promise: the CLI exits
    # nonzero instead of waiting for the five-minute login timeout.
    tries=0
    while kill -0 "$login_pid" 2>/dev/null; do
      tries=$((tries + 1))
      if [ "$tries" -gt 30 ]; then
        echo "$family: logseq-cli login still running 30s after the rejected callback" >&2
        cat "$dir/login-output" >&2
        exit 1
      fi
      sleep 1
    done
    login_status=0
    wait "$login_pid" || login_status=$?
    login_pid=""
    if [ "$login_status" -eq 0 ]; then
      echo "$family: logseq-cli login exited 0 after a state-mismatch callback" >&2
      cat "$dir/login-output" >&2
      exit 1
    fi
    if ! ${pkgs.gnugrep}/bin/grep -Eq 'invalid-callback-state|state mismatch' "$dir/login-output"; then
      echo "$family: logseq-cli login output missing the state-mismatch error:" >&2
      cat "$dir/login-output" >&2
      exit 1
    fi
  }

  (
    set -euo pipefail
    probe_family ipv4 "http://127.0.0.1:8765/auth/callback"
  )

  ipv6_probe_status=0
  ${pkgs.nodejs}/bin/node <<'EOF' || ipv6_probe_status=$?
  const net = require("net");
  const server = net.createServer();
  server.once("error", (error) => {
    if (error && (error.code === "EAFNOSUPPORT" || error.code === "EADDRNOTAVAIL")) {
      process.exit(42);
    }
    console.error(error);
    process.exit(1);
  });
  server.listen(0, "::1", () => server.close(() => process.exit(0)));
  EOF
  if [ "$ipv6_probe_status" -eq 0 ]; then
    (
      set -euo pipefail
      probe_family ipv6 "http://[::1]:8765/auth/callback"
    )
  elif [ "$ipv6_probe_status" -eq 42 ]; then
    echo "skipping IPv6 loopback probe because ::1 is unavailable in this build sandbox" >&2
  else
    echo "failed to determine IPv6 loopback availability" >&2
    exit "$ipv6_probe_status"
  fi

  touch $out
''
