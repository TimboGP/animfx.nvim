-- Hammerspoon → animfx bridge (CONCEPT — verify manually; requires macOS +
-- Hammerspoon). Drop into ~/.hammerspoon/init.lua (or require it from there).
--
-- Neovim side, once:
--   require("animfx.remote").serve({ address = "/tmp/nvim-animfx.sock" })
--   require("animfx").on("AppFocus",  require("animfx.effects").line_flash({}))
--   require("animfx").on("ScreenWake", require("animfx.effects").cursor_beacon({}))

local SOCK = "/tmp/nvim-animfx.sock"

-- Non-blocking emit into the serving Neovim. Data travels as JSON, decoded
-- Lua-side, so there's no Vim dict syntax to escape.
local function animfx_emit(event, data)
  local json = hs.json.encode(data or {})
  local expr = string.format(
    "luaeval('require(\"animfx\").emit(_A[1], vim.json.decode(_A[2]))', ['%s', %q])",
    event,
    json
  )
  hs.task.new("/usr/bin/env", nil, { "nvim", "--server", SOCK, "--remote-expr", expr }):start()
end

-- Set this to the terminal app that runs your Neovim.
local TERMINAL = "WezTerm"

-- Flash when you switch INTO the editor.
hs.application
  .watcher
  .new(function(name, event)
    if event == hs.application.watcher.activated and name == TERMINAL then
      animfx_emit("AppFocus", { app = name })
    end
  end)
  :start()

-- Reorient the cursor after the display wakes.
hs.caffeinate
  .watcher
  .new(function(ev)
    if ev == hs.caffeinate.watcher.screensDidWake then
      animfx_emit("ScreenWake", {})
    end
  end)
  :start()
