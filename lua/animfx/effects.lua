--- animfx.effects — reusable effect constructors.
---
--- Each constructor takes an `opts` table and returns a `function(data)` ready
--- to hand to `animfx.on`. `data` is the arbitrary payload from `animfx.emit`.
local M = {}

-- Read a highlight group's background as a 24-bit integer, following links.
local function bg_of(name)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  if not ok then
    return nil
  end
  return hl.bg
end

-- Linear-interpolate two 24-bit colors; alpha 1 = a, 0 = b.
local function blend(a, b, alpha)
  local function ch(c, shift)
    return math.floor(c / shift) % 256
  end
  local function mix(sa, sb)
    return math.floor(sa * alpha + sb * (1 - alpha) + 0.5)
  end
  local r = mix(ch(a, 65536), ch(b, 65536))
  local g = mix(ch(a, 256), ch(b, 256))
  local bl = mix(ch(a, 1), ch(b, 1))
  return r * 65536 + g * 256 + bl
end

--- Flash a full-line highlight, auto-clearing after `duration` ms.
---
--- Uses a single shared namespace and tracks each flash's extmark id, so rapid
--- re-triggers on the same line don't clear one another prematurely and nothing
--- leaks across triggers.
---
--- With `fade = true`, the line's background is stepped from `hl`'s background
--- toward Normal's over `steps` frames instead of a hard clear — a real
--- fade-out. Falls back to the plain flash if `hl` has no background color.
---
---@param opts? { hl?: string, duration?: integer, fade?: boolean, steps?: integer }
---  hl       Highlight group to apply (default "IncSearch").
---  duration Milliseconds before clearing / total fade time (default 150).
---  fade     Fade the background out instead of a hard clear (default false).
---  steps    Fade frames (default 8); ignored unless `fade`.
---@return fun(data: { buf?: integer, line?: integer })
---  data.buf  Buffer to flash (default: current buffer).
---  data.line 0-indexed line (default: current cursor line).
function M.line_flash(opts)
  opts = opts or {}
  local hl = opts.hl or "IncSearch"
  local ms = opts.duration or 150
  local fade = opts.fade or false
  local steps = opts.steps or 8
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

    local from = fade and bg_of(hl) or nil
    if not fade or not from then
      -- Plain flash: hold the highlight, then clear.
      local id = vim.api.nvim_buf_set_extmark(buf, ns, line, 0, { line_hl_group = hl })
      vim.defer_fn(function()
        if vim.api.nvim_buf_is_valid(buf) then
          pcall(vim.api.nvim_buf_del_extmark, buf, ns, id)
        end
      end, ms)
      return
    end

    -- Fade: step a per-frame highlight group from `hl` bg toward Normal bg.
    local to = bg_of("Normal") or 0x000000
    local id = vim.api.nvim_buf_set_extmark(buf, ns, line, 0, { line_hl_group = hl })
    local frame = 0
    local interval = math.max(1, math.floor(ms / steps))
    local timer = vim.uv.new_timer()
    timer:start(
      interval,
      interval,
      vim.schedule_wrap(function()
        frame = frame + 1
        if frame >= steps or not vim.api.nvim_buf_is_valid(buf) then
          timer:stop()
          timer:close()
          if vim.api.nvim_buf_is_valid(buf) then
            pcall(vim.api.nvim_buf_del_extmark, buf, ns, id)
          end
          return
        end
        local alpha = 1 - frame / steps
        local group = "AnimfxFade" .. frame
        vim.api.nvim_set_hl(0, group, { bg = blend(from, to, alpha) })
        pcall(vim.api.nvim_buf_set_extmark, buf, ns, line, 0, { id = id, line_hl_group = group })
      end)
    )
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
