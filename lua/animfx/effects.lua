--- animfx.effects — reusable effect constructors.
---
--- Each constructor takes an `opts` table and returns a `function(data)` ready
--- to hand to `animfx.on`. `data` is the arbitrary payload from `animfx.emit`.
local M = {}

--- Flash a full-line highlight, auto-clearing after `duration` ms.
---
--- Uses a single shared namespace and tracks each flash's extmark id, so rapid
--- re-triggers on the same line don't clear one another prematurely and nothing
--- leaks across triggers.
---
---@param opts? { hl?: string, duration?: integer }
---  hl       Highlight group to apply (default "IncSearch").
---  duration Milliseconds before clearing (default 150).
---@return fun(data: { buf?: integer, line?: integer })
---  data.buf  Buffer to flash (default: current buffer).
---  data.line 0-indexed line (default: current cursor line).
function M.line_flash(opts)
  opts = opts or {}
  local hl = opts.hl or "IncSearch"
  local ms = opts.duration or 150
  -- Idempotent: create_namespace returns the same id for a given name, so this
  -- doesn't accumulate namespaces no matter how often the effect fires.
  local ns = vim.api.nvim_create_namespace("animfx_line_flash")

  return function(data)
    data = data or {}
    local buf = data.buf or vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local line = data.line or (vim.api.nvim_win_get_cursor(0)[1] - 1)

    local id = vim.api.nvim_buf_set_extmark(buf, ns, line, 0, { line_hl_group = hl })
    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_del_extmark, buf, ns, id)
      end
    end, ms)
  end
end

--- Animated toast via nvim-notify, falling back to `vim.notify` when it's absent.
---
---@param opts? table Passed through to notify() config (title, timeout, animate, ...).
---@return fun(data: { msg?: string, level?: string })
---  data.msg   Message body (default "").
---  data.level Log level string for notify (default "info").
function M.notify_toast(opts)
  opts = opts or {}
  return function(data)
    data = data or {}
    local msg = data.msg or ""
    local level = data.level or "info"

    local ok, notify = pcall(require, "notify")
    if not ok then
      -- Graceful degradation: still surface the message without the animation.
      vim.notify(msg, vim.log.levels[level:upper()] or vim.log.levels.INFO)
      return
    end
    notify(msg, level, vim.tbl_extend("force", { animate = true }, opts))
  end
end

return M
