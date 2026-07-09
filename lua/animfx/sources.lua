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

--- Emit an animfx event when a buffer's diagnostics change, carrying
--- `{ buf, count }`. Re-calling replaces the previous autocmd.
---@param opts? { event?: string } event name to emit (default "Diagnostic").
function M.on_diagnostic(opts)
  opts = opts or {}
  local event = opts.event or "Diagnostic"
  local group = vim.api.nvim_create_augroup("animfx_source_diagnostic", { clear = true })
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = group,
    desc = "animfx: emit " .. event .. " on diagnostics change",
    callback = function(args)
      require("animfx").emit(event, {
        buf = args.buf,
        count = #vim.diagnostic.get(args.buf),
      })
    end,
  })
end

--- Map the search navigation keys so each performs its normal motion and then
--- emits an animfx event carrying the landing `{ buf, line, col, pattern }`.
--- Respects a preceding count. Note: this overrides the given keys — scope with
--- `opts.keys` if you already map them.
---@param opts? { event?: string, keys?: string[] }
---  event  Event name to emit (default "Search").
---  keys   Normal-mode keys to wrap (default { "n", "N" }).
function M.on_search(opts)
  opts = opts or {}
  local event = opts.event or "Search"
  local keys = opts.keys or { "n", "N" }
  for _, key in ipairs(keys) do
    vim.keymap.set("n", key, function()
      pcall(vim.cmd, "normal! " .. vim.v.count1 .. key)
      local pos = vim.api.nvim_win_get_cursor(0)
      require("animfx").emit(event, {
        buf = vim.api.nvim_get_current_buf(),
        line = pos[1] - 1,
        col = pos[2],
        pattern = vim.fn.getreg("/"),
      })
    end, { desc = "animfx: emit " .. event .. " on " .. key })
  end
end

--- Emit an animfx event when a file is added to a harpoon list (harpoon.nvim
--- v2), carrying `{ buf, value, idx }`. No-ops if harpoon is not installed.
---@param opts? { event?: string } event name to emit (default "HarpoonAdd").
function M.on_harpoon(opts)
  opts = opts or {}
  local event = opts.event or "HarpoonAdd"
  local ok, harpoon = pcall(require, "harpoon")
  if not ok then
    return -- harpoon not installed: graceful no-op
  end
  harpoon:extend({
    ADD = function(cx)
      local item = cx and cx.item
      require("animfx").emit(event, {
        buf = vim.api.nvim_get_current_buf(),
        value = item and item.value,
        idx = cx and cx.idx,
      })
    end,
  })
end

--- Emit an animfx event when a `:make`-style command populates the quickfix
--- list with at least one entry, carrying `{ count }` — the number of
--- entries. Fires on |QuickFixCmdPost| for any quickfix-populating command
--- whose name contains "make" (`:make`, `:lmake`, and most build/test-runner
--- plugins built on top of them). Does nothing when the resulting list is
--- empty (the build succeeded). Re-calling it replaces the previous autocmd.
---@param opts? { event?: string } event name to emit (default "BuildFailed").
function M.on_build_failure(opts)
  opts = opts or {}
  local event = opts.event or "BuildFailed"
  local group = vim.api.nvim_create_augroup("animfx_source_build_failure", { clear = true })
  vim.api.nvim_create_autocmd("QuickFixCmdPost", {
    group = group,
    pattern = "*make*",
    desc = "animfx: emit " .. event .. " when :make populates quickfix with errors",
    callback = function()
      -- getqflist({what}) only returns the keys explicitly requested in
      -- `what` — omitting `items` here would leave `.items` nil and make
      -- `#nil` raise inside this autocmd. `items = 0` is the getqflist(){what}
      -- idiom for "include the real items list".
      local qf = vim.fn.getqflist({ nr = "$", items = 0 })
      if #qf.items == 0 then
        return -- quickfix list is empty: build succeeded, nothing to signal
      end
      require("animfx").emit(event, { count = #qf.items })
    end,
  })
end

return M
