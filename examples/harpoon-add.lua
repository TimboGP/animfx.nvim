-- Feedback when you add a file to Harpoon, wired through the animfx registry.
-- The original motivating integration: "emit an event, let effects decide."
--
-- Requires harpoon.nvim (v2). Drop this in your config (or `require` it) after
-- harpoon is set up.

local animfx = require("animfx")
local fx = require("animfx.effects")

require("animfx.sources").on_harpoon() -- emits "HarpoonAdd" with { buf, value, idx }

-- Flash the current line...
animfx.on("HarpoonAdd", fx.line_flash({ hl = "IncSearch" }))

-- ...and toast the added file's name.
animfx.on("HarpoonAdd", function(data)
  fx.notify_toast({ title = "Harpoon" })({
    msg = "Added " .. vim.fn.fnamemodify(data.value or "", ":t"),
  })
end)
