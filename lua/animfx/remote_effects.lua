--- animfx.remote_effects — effects that shell out to another OS process,
--- rather than mutating Neovim's own UI (contrast with animfx.effects, which
--- is exclusively in-process). Kept separate so effects.lua's "no subprocess"
--- invariant stays true, and so this module's different failure mode
--- (missing binary, unreachable peer, ~200-400ms process-spawn latency)
--- doesn't leak into the timer/extmark bookkeeping shared by effects.lua.
---
--- Each constructor takes an `opts` table and returns a `function(data)`
--- ready to hand to `animfx.on`, exactly like `animfx.effects`.
local M = {}

--- Trigger a wiggle on whatever OS window currently has focus, via the
--- Hammerspoon `hs` CLI calling a `hammerspoon-window-mgmt` Spoon method:
--- `spoon.WindowMgmt:wiggleFocusedWindow()`. Meant for a build/test-failure
--- cue on the terminal window Neovim itself has no way to move or shake (see
--- `animfx.sources.on_build_failure`).
---
--- Fire-and-forget: does not wait for or report the outcome. If Hammerspoon
--- isn't running or `hs` isn't on `$PATH` this fails silently — `jobstart`
--- returns 0/-1 synchronously without raising for invalid args or a missing
--- executable, and with no `on_stdout`/`on_stderr`/`on_exit` registered, a
--- nonzero exit from a reachable-but-broken `hs` never reaches Neovim's UI
--- either. `detach = true` decouples the spawned `hs` process from this
--- Neovim's job lifecycle.
---@param opts? table Reserved for future options; unused today.
---@return fun(data: table)
function M.hammerspoon_wiggle(opts)
  opts = opts or {}
  return function()
    vim.fn.jobstart({ "hs", "-c", "spoon.WindowMgmt:wiggleFocusedWindow()" }, { detach = true })
  end
end

return M
