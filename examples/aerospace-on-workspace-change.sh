#!/usr/bin/env bash
# Emit an animfx event into a running Neovim on every AeroSpace workspace change.
#
# In your Neovim config:
#   require("animfx.remote").serve({ address = "/tmp/nvim-animfx.sock" })
#   require("animfx").on("WorkspaceSwitch",
#     require("animfx.effects").cursor_beacon({ hl = "Search" }))
#
# In ~/.aerospace.toml:
#   on-focus-changed = ['exec-and-forget /path/to/aerospace-on-workspace-change.sh']
set -euo pipefail

SOCK="${NVIM_ANIMFX_SOCK:-/tmp/nvim-animfx.sock}"
WORKSPACE="${AEROSPACE_FOCUSED_WORKSPACE:-?}"

# No socket yet (Neovim not running / not serving) → nothing to do.
[ -S "$SOCK" ] || exit 0

# Data travels as a JSON string, decoded Lua-side — no Vim dict syntax to escape.
nvim --server "$SOCK" --remote-expr \
  "luaeval('require(\"animfx\").emit(_A[1], vim.json.decode(_A[2]))', ['WorkspaceSwitch', '{\"workspace\": \"$WORKSPACE\"}'])" \
  >/dev/null 2>&1 || true
