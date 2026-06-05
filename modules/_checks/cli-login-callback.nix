{ cli, pkgs }:
# Regression check for the patches/logseq-cli-auth-bind-ipv4-loopback.patch
# behavior: `logseq-cli login` must serve its OAuth callback on the IPv4
# loopback literal. Upstream binds the resolver's first "localhost" address
# (often ::1 only), which IPv4-only browsers cannot reach. The probe stays
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
  export HOME=$TMPDIR
  export XDG_CACHE_HOME=$TMPDIR/cache

  mkdir -p "$TMPDIR/bin"
  ln -s ${openerStub} "$TMPDIR/bin/xdg-open"
  ln -s ${openerStub} "$TMPDIR/bin/open"
  export PATH="$TMPDIR/bin:$PATH"

  ${cli}/bin/logseq-cli login >"$TMPDIR/login-output" 2>&1 &
  login_pid=$!

  # The authorize URL is written only after the callback server's listen
  # callback resolved, so its presence means the server is accepting
  # connections.
  tries=0
  while [ ! -s "$TMPDIR/authorize-url" ]; do
    tries=$((tries + 1))
    if [ "$tries" -gt 120 ]; then
      echo "logseq-cli login did not produce an authorize URL within 120s" >&2
      cat "$TMPDIR/login-output" >&2
      kill "$login_pid" 2>/dev/null || true
      exit 1
    fi
    if ! kill -0 "$login_pid" 2>/dev/null; then
      echo "logseq-cli login exited before opening the browser:" >&2
      cat "$TMPDIR/login-output" >&2
      exit 1
    fi
    sleep 1
  done

  authorize_url="$(cat "$TMPDIR/authorize-url")"
  state="$(printf '%s' "$authorize_url" | ${pkgs.gnused}/bin/sed -n 's/.*[?&]state=\([^&]*\).*/\1/p')"
  if [ -z "$state" ]; then
    echo "authorize URL is missing the OAuth state parameter:" >&2
    printf '%s\n' "$authorize_url" >&2
    kill "$login_pid" 2>/dev/null || true
    exit 1
  fi

  # The probe under test: an IPv4-only client must reach the callback server.
  # A connection failure here is the exact regression this check pins down
  # (server bound to ::1 only).
  http_status=0
  if ! http_status="$(${pkgs.curl}/bin/curl --silent --show-error --max-time 10 \
    --output "$TMPDIR/callback-body" --write-out '%{http_code}' \
    "http://127.0.0.1:8765/auth/callback?code=probe&state=mismatch-$state")"; then
    echo "callback probe could not connect to 127.0.0.1:8765; the login server is not bound on the IPv4 loopback" >&2
    cat "$TMPDIR/login-output" >&2
    kill "$login_pid" 2>/dev/null || true
    exit 1
  fi

  if [ "$http_status" != "400" ]; then
    echo "expected HTTP 400 for a state-mismatch callback, got $http_status" >&2
    cat "$TMPDIR/callback-body" >&2
    kill "$login_pid" 2>/dev/null || true
    exit 1
  fi
  if ! ${pkgs.gnugrep}/bin/grep -q 'state mismatch' "$TMPDIR/callback-body"; then
    echo "callback response body missing the expected state-mismatch message:" >&2
    cat "$TMPDIR/callback-body" >&2
    kill "$login_pid" 2>/dev/null || true
    exit 1
  fi

  # The rejected callback must settle the login promise: the CLI exits
  # nonzero instead of waiting for the five-minute login timeout.
  tries=0
  while kill -0 "$login_pid" 2>/dev/null; do
    tries=$((tries + 1))
    if [ "$tries" -gt 30 ]; then
      echo "logseq-cli login still running 30s after the rejected callback" >&2
      cat "$TMPDIR/login-output" >&2
      kill "$login_pid" 2>/dev/null || true
      exit 1
    fi
    sleep 1
  done
  login_status=0
  wait "$login_pid" || login_status=$?
  if [ "$login_status" -eq 0 ]; then
    echo "logseq-cli login exited 0 after a state-mismatch callback" >&2
    cat "$TMPDIR/login-output" >&2
    exit 1
  fi
  if ! ${pkgs.gnugrep}/bin/grep -Eq 'invalid-callback-state|state mismatch' "$TMPDIR/login-output"; then
    echo "logseq-cli login output missing the state-mismatch error:" >&2
    cat "$TMPDIR/login-output" >&2
    exit 1
  fi

  touch $out
''
