-- Yank highlight through the animfx registry — a drop-in alternative to
-- vim.highlight.on_yank, wired from a curated source and a reusable effect.
--
-- Drop this in your config (or `require` it). The source emits "Yank" on every
-- yank; the effect flashes the yanked range and clears after `duration` ms.

local animfx = require("animfx")
local fx = require("animfx.effects")

require("animfx.sources").on_yank() -- emits "Yank" with { buf, start_row, ... }

animfx.on("Yank", fx.range_flash({ hl = "IncSearch", duration = 150 }))
