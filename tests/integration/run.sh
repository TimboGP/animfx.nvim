#!/usr/bin/env bash
# Real backend-integration tests. Installs nvim-notify and verifies the adapters
# actually resolve and call it, exercises the cross-process remote bridge, and
# checks the health report. Requires git + network to fetch the backend.
#
# Covers the integration-only requirements on tests/run.lua's
# integration_covered allowlist:
#   - introspection: Health check
#   - remote: External emit delivers to registered effects
#   - remote: Graceful when no socket is present
#
# Override the Neovim binary with NVIM=/path/to/nvim (default: nvim).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NVIM_BIN="${NVIM:-nvim}"
DEPS="$(mktemp -d)"
trap 'rm -rf "$DEPS"' EXIT

fail=0
pass() { echo "  ok   - $1"; }
die() {
  echo "  FAIL - $1"
  fail=1
}

echo "Fetching backends into $DEPS ..."
git clone --depth 1 -q https://github.com/rcarriga/nvim-notify "$DEPS/nvim-notify" ||
  { echo "could not clone nvim-notify (network required)"; exit 1; }

export ANIMFX_ROOT="$ROOT"
export ANIMFX_DEPS="$DEPS/nvim-notify"

echo "== adapter resolution against real nvim-notify =="
if "$NVIM_BIN" --clean -l "$ROOT/tests/integration/backends_spec.lua"; then
  pass "backends_spec.lua"
else
  die "backends_spec.lua"
fi

echo "== :checkhealth reports nvim-notify (introspection: Health check) =="
HOUT="$(mktemp)"
"$NVIM_BIN" --clean --headless \
  --cmd "set runtimepath^=$ROOT" --cmd "set runtimepath+=$DEPS/nvim-notify" \
  -c "checkhealth animfx" -c "w! $HOUT" -c "qa!" >/dev/null 2>&1
if grep -q "nvim-notify found" "$HOUT"; then
  pass "checkhealth animfx reports nvim-notify found"
else
  die "checkhealth animfx did not report nvim-notify found"
  cat "$HOUT"
fi
rm -f "$HOUT"

echo "== remote: external emit over socket (remote: External emit ...) =="
SOCK="$(mktemp -u "$DEPS/e2e-XXXX.sock")"
OUT="$(mktemp)"
"$NVIM_BIN" --clean --headless --cmd "set runtimepath^=$ROOT" \
  -c "lua require('animfx.remote').serve({address='$SOCK'})" \
  -c "lua require('animfx').on('WorkspaceSwitch', function(d) local f=io.open('$OUT','w'); f:write(tostring(d.workspace)); f:close() end)" \
  >/dev/null 2>&1 &
SRV=$!
for _ in $(seq 1 50); do
  [ -S "$SOCK" ] && break
  sleep 0.1
done
if [ -S "$SOCK" ]; then
  "$NVIM_BIN" --server "$SOCK" --remote-expr \
    "luaeval('require(\"animfx\").emit(_A[1], vim.json.decode(_A[2]))', ['WorkspaceSwitch', '{\"workspace\": \"ws3\"}'])" \
    >/dev/null 2>&1
  sleep 0.3
  if [ "$(cat "$OUT" 2>/dev/null)" = "ws3" ]; then
    pass "external emit delivered the payload to the registered effect"
  else
    die "external emit did not deliver (got: '$(cat "$OUT" 2>/dev/null)')"
  fi
else
  die "server socket never appeared"
fi
kill "$SRV" 2>/dev/null
rm -f "$OUT"

echo "== remote: graceful when no socket (remote: Graceful when no socket ...) =="
if NVIM_ANIMFX_SOCK="$DEPS/does-not-exist.sock" bash "$ROOT/examples/tmux-pane-focus.sh" pane1; then
  pass "example hook exits 0 when the socket is absent"
else
  die "example hook errored when the socket was absent"
fi

echo ""
if [ "$fail" -eq 0 ]; then
  echo "PASS"
else
  echo "FAILED"
  exit 1
fi
