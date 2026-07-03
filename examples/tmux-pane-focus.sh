#!/usr/bin/env bash
# Emit an animfx event into a running Neovim when a tmux pane gains focus.
#
# In your Neovim config:
#   require("animfx.remote").serve({ address = "/tmp/nvim-animfx.sock" })
#   require("animfx").on("PaneFocus",
#     require("animfx.effects").line_flash({ hl = "IncSearch", fade = true }))
#
# In ~/.tmux.conf:
#   set-hook -g pane-focus-in 'run-shell "/path/to/tmux-pane-focus.sh #{pane_id}"'
set -euo pipefail

SOCK="${NVIM_ANIMFX_SOCK:-/tmp/nvim-animfx.sock}"
PANE="${1:-?}"

[ -S "$SOCK" ] || exit 0

# Data travels as a JSON string, decoded Lua-side — no Vim dict syntax to escape.
nvim --server "$SOCK" --remote-expr \
  "luaeval('require(\"animfx\").emit(_A[1], vim.json.decode(_A[2]))', ['PaneFocus', '{\"pane\": \"$PANE\"}'])" \
  >/dev/null 2>&1 || true
