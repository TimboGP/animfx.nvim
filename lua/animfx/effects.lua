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

-- Clamp a 0-indexed line into a buffer's valid range, so an out-of-range line
-- (e.g. the cursor line of a different, longer buffer) never raises.
local function clamp_line(buf, line)
  local last = vim.api.nvim_buf_line_count(buf) - 1
  return math.max(0, math.min(line, last))
end

-- Monotonic counter making each fade invocation's highlight groups unique, so
-- concurrent fades with different colors don't overwrite one another.
local fade_seq = 0

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
    local line = clamp_line(buf, data.line or (vim.api.nvim_win_get_cursor(0)[1] - 1))

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
    -- Group names are salted with a per-invocation id so two concurrent fades
    -- (e.g. different colors on different buffers) never clobber each other.
    local to = bg_of("Normal") or 0x000000
    local id = vim.api.nvim_buf_set_extmark(buf, ns, line, 0, { line_hl_group = hl })
    fade_seq = fade_seq + 1
    local fid = fade_seq
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
        local group = ("AnimfxFade%d_%d"):format(fid, frame)
        vim.api.nvim_set_hl(0, group, { bg = blend(from, to, alpha) })
        pcall(vim.api.nvim_buf_set_extmark, buf, ns, line, 0, { id = id, line_hl_group = group })
      end)
    )
  end
end

--- Flash a gutter sign, auto-clearing after `duration` ms.
---
--- Unlike line_flash this shows in the sign column, so it registers even when
--- the target line is scrolled off-screen. Each flash tracks its own extmark id.
---
---@param opts? { text?: string, hl?: string, duration?: integer }
---  text     Sign text, 1-2 cells (default "▐").
---  hl       Highlight group for the sign (default "IncSearch").
---  duration Milliseconds before clearing (default 300).
---@return fun(data: { buf?: integer, line?: integer })
function M.sign_flash(opts)
  opts = opts or {}
  local text = opts.text or "▐"
  local hl = opts.hl or "IncSearch"
  local ms = opts.duration or 300
  local ns = vim.api.nvim_create_namespace("animfx_sign_flash")

  return function(data)
    data = data or {}
    local buf = data.buf or vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local line = clamp_line(buf, data.line or (vim.api.nvim_win_get_cursor(0)[1] - 1))

    local id = vim.api.nvim_buf_set_extmark(buf, ns, line, 0, {
      sign_text = text,
      sign_hl_group = hl,
    })
    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_del_extmark, buf, ns, id)
      end
    end, ms)
  end
end

--- A pulse at the cursor: a small floating window that fades out. Dependency-free
--- (no pulsar/beacon needed) — the same visual, driven from this registry.
---
---@param opts? { hl?: string, width?: integer, duration?: integer, steps?: integer }
---  hl       Highlight group for the pulse (default "Search").
---  width    Pulse width in cells (default 10).
---  duration Total fade time in ms (default 220).
---  steps    Fade frames (default 10).
---@return fun(data: table)
function M.cursor_beacon(opts)
  opts = opts or {}
  local hl = opts.hl or "Search"
  local width = opts.width or 10
  local ms = opts.duration or 220
  local steps = opts.steps or 10
  -- One reusable scratch buffer for every pulse this constructor makes.
  local scratch = vim.api.nvim_create_buf(false, true)

  return function()
    if not vim.api.nvim_buf_is_valid(scratch) then
      scratch = vim.api.nvim_create_buf(false, true)
    end
    local ok, win = pcall(vim.api.nvim_open_win, scratch, false, {
      relative = "cursor",
      row = 0,
      col = 1,
      width = width,
      height = 1,
      style = "minimal",
      focusable = false,
      noautocmd = true,
      zindex = 200,
    })
    if not ok then
      return
    end
    vim.wo[win].winhl = "Normal:" .. hl
    vim.wo[win].winblend = 0

    local frame = 0
    local interval = math.max(1, math.floor(ms / steps))
    local timer = vim.uv.new_timer()
    timer:start(
      interval,
      interval,
      vim.schedule_wrap(function()
        frame = frame + 1
        if frame >= steps or not vim.api.nvim_win_is_valid(win) then
          timer:stop()
          timer:close()
          if vim.api.nvim_win_is_valid(win) then
            pcall(vim.api.nvim_win_close, win, true)
          end
          return
        end
        vim.wo[win].winblend = math.floor(100 * frame / steps)
      end)
    )
  end
end

--- Generic backend adapter: delegate to another plugin's function, degrading
--- gracefully when it isn't installed. This is how an existing engine
--- (pulsar.nvim, mini.animate, ...) becomes an animfx effect so one registry
--- drives every backend.
---
---   fx.delegate({ module = "pulsar", fn = "pulse" })
---   fx.delegate({ module = "mini.animate", fn = "animate",
---                 args = function(data) return { data.steps, data.timing } end })
---
---@class animfx.DelegateSpec
---@field module string Module to require.
---@field fn? string Dot-path to the callable within the module; omit if the module itself is callable.
---@field args? fun(data: table): any[] Build the argument list from `data` (default: `{ data }`).
---@field fallback? fun(data: table) Called with `data` when the module isn't available.
---
---@param spec animfx.DelegateSpec
---@return fun(data: table)
function M.delegate(spec)
  assert(type(spec) == "table" and type(spec.module) == "string", "delegate: spec.module required")
  local unpack = table.unpack or unpack
  return function(data)
    data = data or {}
    local ok, mod = pcall(require, spec.module)
    if not ok then
      if spec.fallback then
        spec.fallback(data)
      end
      return
    end
    local target = mod
    if spec.fn then
      for part in vim.gsplit(spec.fn, ".", { plain = true }) do
        target = target and target[part]
      end
    end
    if type(target) ~= "function" and not (getmetatable(target) or {}).__call then
      return
    end
    local args = spec.args and spec.args(data) or { data }
    pcall(target, unpack(args))
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
