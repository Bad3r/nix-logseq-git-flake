#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

if [ -f .env ]; then
  had_nounset=0
  case "$-" in
  *u*)
    had_nounset=1
    set +u
    ;;
  esac
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
  if [ "$had_nounset" -eq 1 ]; then
    set -u
  fi
fi

login_timeout_ms="${LOGSEQ_CLI_LOGIN_TIMEOUT_MS:-120000}"

if [ -n "${LOGSEQ_CLI_BIN:-}" ]; then
  cli=("$LOGSEQ_CLI_BIN")
elif [ -n "${LOGSEQ_CLI_OUT:-}" ] && [ -x "$LOGSEQ_CLI_OUT/bin/logseq-cli" ]; then
  cli=("$LOGSEQ_CLI_OUT/bin/logseq-cli")
else
  logseq_cli_out="$(nix build --no-link --print-out-paths .#logseq-cli)"
  cli=("$logseq_cli_out/bin/logseq-cli")
fi

make_opener_stub() {
  local stub="$1"

  cat >"$stub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$1" >"$TMPDIR/authorize-url.tmp"
mv "$TMPDIR/authorize-url.tmp" "$TMPDIR/authorize-url"
EOF
  chmod +x "$stub"
}

wait_for_authorize_url() {
  local dir="$1"
  local pid="$2"
  local tries

  tries=0
  while [ ! -s "$dir/authorize-url" ]; do
    tries=$((tries + 1))
    if [ "$tries" -gt 120 ]; then
      echo "logseq-cli login did not produce an authorize URL within 120s" >&2
      cat "$dir/login-output" >&2
      kill "$pid" 2>/dev/null || true
      return 1
    fi

    if ! kill -0 "$pid" 2>/dev/null; then
      echo "logseq-cli login exited before opening the browser" >&2
      cat "$dir/login-output" >&2
      return 1
    fi

    sleep 1
  done
}

extract_state() {
  sed -n 's/^.*[?&]state=\([^&]*\).*$/\1/p' "$1" | tr -d '\r'
}

probe_family() {
  local family="$1"
  local curl_resolve="$2"
  local test_root="$3"
  local dir="$test_root/$family"
  local authorize_url
  local state
  local callback_url
  local http_status
  local login_status

  mkdir -p "$dir/bin" "$dir/home" "$dir/cache"
  make_opener_stub "$dir/bin/xdg-open"
  ln -s xdg-open "$dir/bin/open"

  HOME="$dir/home" \
    TMPDIR="$dir" \
    XDG_CACHE_HOME="$dir/cache" \
    PATH="$dir/bin:$PATH" \
    LOGSEQ_CLI_LOGIN_TIMEOUT_MS="$login_timeout_ms" \
    "${cli[@]}" login >"$dir/login-output" 2>&1 &
  login_pid=$!

  if ! wait_for_authorize_url "$dir" "$login_pid"; then
    return 1
  fi

  authorize_url="$(cat "$dir/authorize-url")"
  state="$(extract_state "$dir/authorize-url")"
  if [ -z "$state" ]; then
    echo "$family: authorize URL is missing the OAuth state parameter" >&2
    printf '%s\n' "$authorize_url" >&2
    return 1
  fi

  callback_url="http://localhost:8765/auth/callback?code=probe&state=mismatch-$state"

  if ! http_status="$(curl --silent --show-error --noproxy '*' --max-time 10 \
    --resolve "$curl_resolve" \
    --output "$dir/callback-body" \
    --write-out '%{http_code}' \
    "$callback_url")"; then
    echo "$family: callback could not connect through $curl_resolve" >&2
    cat "$dir/login-output" >&2
    return 1
  fi

  if [ "$http_status" != "400" ]; then
    echo "$family: expected HTTP 400 for a state-mismatch callback, got $http_status" >&2
    cat "$dir/callback-body" >&2
    return 1
  fi

  if ! grep -q 'state mismatch' "$dir/callback-body"; then
    echo "$family: callback body did not contain the expected state-mismatch message" >&2
    cat "$dir/callback-body" >&2
    return 1
  fi

  login_status=0
  wait "$login_pid" || login_status=$?
  login_pid=""
  if [ "$login_status" -eq 0 ]; then
    echo "$family: login exited 0 after a state-mismatch callback" >&2
    cat "$dir/login-output" >&2
    return 1
  fi

  if ! grep -Eq 'invalid-callback-state|state mismatch' "$dir/login-output"; then
    echo "$family: login output did not contain the expected state-mismatch error" >&2
    cat "$dir/login-output" >&2
    return 1
  fi

  echo "$family: callback server reachable through $curl_resolve"
}

run_probe_family() {
  local probe_status

  set +e
  (
    set -e
    login_pid=""
    trap 'if [ -n "${login_pid:-}" ]; then kill "$login_pid" 2>/dev/null || true; wait "$login_pid" 2>/dev/null || true; login_pid=""; fi' EXIT
    probe_family "$@"
  )
  probe_status=$?
  set -e

  if [ "$probe_status" -ne 0 ]; then
    status=1
  fi
}

test_root="$(mktemp -d "${TMPDIR:-/tmp}/logseq-cli-loopback-test.XXXXXXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT
status=0

echo "test root: $test_root"
echo "cli: ${cli[*]}"

run_probe_family ipv4 'localhost:8765:127.0.0.1' "$test_root"
run_probe_family ipv6 'localhost:8765:[::1]' "$test_root"

if [ "$status" -ne 0 ]; then
  echo "one or more loopback callback probes failed" >&2
else
  echo "both loopback callback probes passed"
fi

exit "$status"
