--- animfx.sources — curated adapters that emit animfx events from common
--- Neovim happenings, so effects work without wiring `emit` by hand.
---
--- Each source is deliberately specific and opt-in. This is NOT a general
--- autocmd wrapper (see the project non-goals): a source translates one
--- well-defined Neovim event into one animfx event carrying the relevant data.
local M = {}

--- Emit an animfx event on every yank, carrying the yanked buffer and range as
--- `{ buf, start_row, start_col, end_row, end_col }` (0-indexed, end-exclusive),
--- plus `regtype`/`operator` from |TextYankPost|. Composes with
--- `animfx.effects.range_flash`. Re-calling replaces the previous yank autocmd.
---@param opts? { event?: string } event name to emit (default "Yank").
function M.on_yank(opts)
  opts = opts or {}
  local event = opts.event or "Yank"
  local group = vim.api.nvim_create_augroup("animfx_source_yank", { clear = true })
  vim.api.nvim_create_autocmd("TextYankPost", {
    group = group,
    desc = "animfx: emit " .. event .. " on yank",
    callback = function()
      local buf = vim.api.nvim_get_current_buf()
      local s = vim.api.nvim_buf_get_mark(buf, "[")
      local e = vim.api.nvim_buf_get_mark(buf, "]")
      require("animfx").emit(event, {
        buf = buf,
        start_row = (s[1] or 1) - 1,
        start_col = s[2] or 0,
        end_row = (e[1] or 1) - 1,
        end_col = (e[2] or 0) + 1, -- ']' column is inclusive; make it exclusive
        regtype = vim.v.event.regtype,
        operator = vim.v.event.operator,
      })
    end,
  })
end

return M
