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

-- Repeating animation timers, tracked so any still in flight can be cancelled
-- on exit rather than leaking or firing a callback into a closing Neovim.
-- Cancellation and the shared tracking table now live in animfx.tween, so
-- hand-rolled effect timers here and tween-driven ones (see `shake`) are
-- cleaned up the same way, by the same VimLeavePre hook.
local tween = require("animfx.tween")
local managed_timer = tween.managed_timer
local release_timer = tween.release_timer

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
    local timer = managed_timer()
    timer:start(
      interval,
      interval,
      vim.schedule_wrap(function()
        frame = frame + 1
        if frame >= steps or not vim.api.nvim_buf_is_valid(buf) then
          release_timer(timer)
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

--- Flash an arbitrary buffer range, auto-clearing after `duration` ms.
---
--- Generalizes line_flash to a column-aware range. The range comes from `data`
--- (0-indexed, end-exclusive); if omitted it falls back to the `'[` / `']`
--- marks — the most recently changed or yanked text — which makes it compose
--- directly with `animfx.sources.on_yank`. Coordinates are clamped so an
--- out-of-range value never raises.
---
---@param opts? { hl?: string, duration?: integer }
---  hl       Highlight group to apply (default "IncSearch").
---  duration Milliseconds before clearing (default 150).
---@return fun(data: { buf?: integer, start_row?: integer, start_col?: integer, end_row?: integer, end_col?: integer })
function M.range_flash(opts)
  opts = opts or {}
  local hl = opts.hl or "IncSearch"
  local ms = opts.duration or 150
  local ns = vim.api.nvim_create_namespace("animfx_range_flash")

  return function(data)
    data = data or {}
    local buf = data.buf or vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end

    local sr, sc, er, ec
    local start_row = data.start_row
    if start_row then
      sr, sc = start_row, data.start_col or 0
      er, ec = data.end_row or start_row, data.end_col or (sc + 1)
    else
      local s = vim.api.nvim_buf_get_mark(buf, "[")
      local e = vim.api.nvim_buf_get_mark(buf, "]")
      sr, sc = (s[1] or 1) - 1, s[2] or 0
      er, ec = (e[1] or 1) - 1, (e[2] or 0) + 1 -- ']' column is inclusive; make it exclusive
    end

    -- Clamp into the buffer so a bad range can't raise.
    local last = vim.api.nvim_buf_line_count(buf) - 1
    local function line_len(row)
      return #(vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or "")
    end
    sr = math.max(0, math.min(sr, last))
    er = math.max(sr, math.min(er, last))
    sc = math.max(0, math.min(sc, line_len(sr)))
    ec = math.max(0, math.min(ec, line_len(er)))

    local ok, id = pcall(vim.api.nvim_buf_set_extmark, buf, ns, sr, sc, {
      end_row = er,
      end_col = ec,
      hl_group = hl,
    })
    if not ok then
      return
    end
    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_del_extmark, buf, ns, id)
      end
    end, ms)
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
    local timer = managed_timer()
    timer:start(
      interval,
      interval,
      vim.schedule_wrap(function()
        frame = frame + 1
        if frame >= steps or not vim.api.nvim_win_is_valid(win) then
          release_timer(timer)
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

--- An inverse pulse that homes in on the cursor: a floating box that starts
--- wide and faint, then contracts and solidifies onto the cursor position. Where
--- `cursor_beacon` expands and fades *out*, this converges and fades *in* — a
--- "here" cue that draws the eye to where the cursor just landed.
---
--- Dependency-free, same floating-window mechanism as `cursor_beacon`.
---
---@param opts? { hl?: string, width?: integer, duration?: integer, steps?: integer, blend?: integer }
---  hl       Highlight group for the pulse (default "Search").
---  width    Starting (widest) width in cells (default 20).
---  duration Total convergence time in ms (default 220).
---  steps    Animation frames (default 10).
---  blend    Starting winblend of the wide box, 0-100 (default 80); it lands at 0.
---@return fun(data: table)
function M.cursor_implode(opts)
  opts = opts or {}
  local hl = opts.hl or "Search"
  local width = math.max(opts.width or 20, 1)
  local ms = opts.duration or 220
  local steps = math.max(opts.steps or 10, 1)
  local start_blend = math.max(0, math.min(opts.blend or 80, 100))
  -- One reusable scratch buffer for every pulse this constructor makes.
  local scratch = vim.api.nvim_create_buf(false, true)

  -- Width and centering offset for a given frame: at frame 0 the box is full
  -- width and centered on the cursor; by the last frame it's a single cell
  -- sitting on the cursor column.
  local function geometry(frame)
    local p = frame / steps
    local w = math.max(1, math.floor(width * (1 - p) + 0.5))
    return w, -math.floor(w / 2)
  end

  return function()
    if not vim.api.nvim_buf_is_valid(scratch) then
      scratch = vim.api.nvim_create_buf(false, true)
    end
    local w0, col0 = geometry(0)
    local ok, win = pcall(vim.api.nvim_open_win, scratch, false, {
      relative = "cursor",
      row = 0,
      col = col0,
      width = w0,
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
    vim.wo[win].winblend = start_blend

    local frame = 0
    local interval = math.max(1, math.floor(ms / steps))
    local timer = managed_timer()
    timer:start(
      interval,
      interval,
      vim.schedule_wrap(function()
        frame = frame + 1
        if frame >= steps or not vim.api.nvim_win_is_valid(win) then
          release_timer(timer)
          if vim.api.nvim_win_is_valid(win) then
            pcall(vim.api.nvim_win_close, win, true)
          end
          return
        end
        local w, col = geometry(frame)
        -- Interpolate blend from start_blend toward 0 so the box solidifies as
        -- it converges — the "landing" cue.
        vim.wo[win].winblend = math.floor(start_blend * (1 - frame / steps))
        pcall(vim.api.nvim_win_set_config, win, {
          relative = "cursor",
          row = 0,
          col = col,
          width = w,
          height = 1,
        })
      end)
    )
  end
end

--- An expanding ripple at the cursor: a floating box that starts tight on the
--- cursor and grows outward while fading — a dissipating ring. The outward twin
--- of `cursor_implode` (which converges inward).
---
--- Dependency-free, same floating-window mechanism as `cursor_beacon`.
---
---@param opts? { hl?: string, width?: integer, duration?: integer, steps?: integer }
---  hl       Highlight group for the ripple (default "Search").
---  width    Final (widest) width in cells (default 24).
---  duration Total expansion time in ms (default 240).
---  steps    Animation frames (default 10).
---@return fun(data: table)
function M.cursor_ripple(opts)
  opts = opts or {}
  local hl = opts.hl or "Search"
  local width = math.max(opts.width or 24, 1)
  local ms = opts.duration or 240
  local steps = math.max(opts.steps or 10, 1)
  -- One reusable scratch buffer for every ripple this constructor makes.
  local scratch = vim.api.nvim_create_buf(false, true)

  -- Width and centering offset for a given frame: a single cell on the cursor
  -- at frame 0, growing to full width centered on the cursor by the last frame.
  local function geometry(frame)
    local p = frame / steps
    local w = math.max(1, math.floor(width * p + 0.5))
    return w, -math.floor(w / 2)
  end

  return function()
    if not vim.api.nvim_buf_is_valid(scratch) then
      scratch = vim.api.nvim_create_buf(false, true)
    end
    local w0, col0 = geometry(0)
    local ok, win = pcall(vim.api.nvim_open_win, scratch, false, {
      relative = "cursor",
      row = 0,
      col = col0,
      width = w0,
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
    local timer = managed_timer()
    timer:start(
      interval,
      interval,
      vim.schedule_wrap(function()
        frame = frame + 1
        if frame >= steps or not vim.api.nvim_win_is_valid(win) then
          release_timer(timer)
          if vim.api.nvim_win_is_valid(win) then
            pcall(vim.api.nvim_win_close, win, true)
          end
          return
        end
        local w, col = geometry(frame)
        -- Fade out as it grows — the ring dissipating outward.
        vim.wo[win].winblend = math.floor(100 * frame / steps)
        pcall(vim.api.nvim_win_set_config, win, {
          relative = "cursor",
          row = 0,
          col = col,
          width = w,
          height = 1,
        })
      end)
    )
  end
end

--- Flash a line's highlight on and off `times` times, then leave it cleared.
---
---@param opts? { hl?: string, times?: integer, interval?: integer }
---  hl       Highlight group (default "IncSearch").
---  times    Number of on-flashes (default 3).
---  interval Milliseconds per on/off phase (default 100).
---@return fun(data: { buf?: integer, line?: integer })
function M.blink(opts)
  opts = opts or {}
  local hl = opts.hl or "IncSearch"
  local times = opts.times or 3
  local interval = opts.interval or 100
  local ns = vim.api.nvim_create_namespace("animfx_blink")

  return function(data)
    data = data or {}
    local buf = data.buf or vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local line = clamp_line(buf, data.line or (vim.api.nvim_win_get_cursor(0)[1] - 1))

    local id
    local function set_on()
      id = vim.api.nvim_buf_set_extmark(buf, ns, line, 0, { line_hl_group = hl })
    end
    local function set_off()
      if id then
        pcall(vim.api.nvim_buf_del_extmark, buf, ns, id)
        id = nil
      end
    end

    set_on() -- start visible; subsequent states are toggled by the timer
    local fires, total = 0, times * 2 - 1
    local timer = managed_timer()
    timer:start(
      interval,
      interval,
      vim.schedule_wrap(function()
        if not vim.api.nvim_buf_is_valid(buf) then
          release_timer(timer)
          return
        end
        fires = fires + 1
        if fires % 2 == 1 then
          set_off()
        else
          set_on()
        end
        if fires >= total then
          release_timer(timer)
          set_off()
        end
      end)
    )
  end
end

--- Sweep a highlighted band across a line, left to right, then clear it — a
--- scanner-style wipe. The band is `opts.width` cells wide and travels from the
--- start of the line to past its end over `steps` frames.
---
---@param opts? { hl?: string, width?: integer, duration?: integer, steps?: integer }
---  hl       Highlight group for the band (default "Search").
---  width    Band width in cells (default 8).
---  duration Total sweep time in ms (default 240).
---  steps    Animation frames (default 12).
---@return fun(data: { buf?: integer, line?: integer })
function M.column_sweep(opts)
  opts = opts or {}
  local hl = opts.hl or "Search"
  local width = math.max(opts.width or 8, 1)
  local ms = opts.duration or 240
  local steps = math.max(opts.steps or 12, 1)
  local ns = vim.api.nvim_create_namespace("animfx_column_sweep")

  return function(data)
    data = data or {}
    local buf = data.buf or vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local line = clamp_line(buf, data.line or (vim.api.nvim_win_get_cursor(0)[1] - 1))
    local len = #(vim.api.nvim_buf_get_lines(buf, line, line + 1, false)[1] or "")
    if len == 0 then
      return
    end

    local id
    -- Position (or clear) the band between two columns, clamped to the line.
    local function place(sc, ec)
      sc = math.max(0, math.min(sc, len))
      ec = math.max(0, math.min(ec, len))
      if ec <= sc then
        if id then
          pcall(vim.api.nvim_buf_del_extmark, buf, ns, id)
          id = nil
        end
        return
      end
      local ok, new = pcall(vim.api.nvim_buf_set_extmark, buf, ns, line, sc, {
        id = id,
        end_col = ec,
        hl_group = hl,
      })
      if ok then
        id = new
      end
    end

    place(0, width)
    local frame = 0
    local interval = math.max(1, math.floor(ms / steps))
    local timer = managed_timer()
    timer:start(
      interval,
      interval,
      vim.schedule_wrap(function()
        frame = frame + 1
        if frame >= steps or not vim.api.nvim_buf_is_valid(buf) then
          release_timer(timer)
          if vim.api.nvim_buf_is_valid(buf) and id then
            pcall(vim.api.nvim_buf_del_extmark, buf, ns, id)
          end
          return
        end
        -- Leading edge marches from the start of the line to its end.
        local start = math.floor(len * frame / steps + 0.5)
        place(start, start + width)
      end)
    )
  end
end

--- Breathe a line's background: swell from Normal toward `hl`'s background and
--- recede back over `steps` frames — a soft in-and-out glow. Falls back to a
--- plain hold-then-clear flash when `hl` has no background color.
---
---@param opts? { hl?: string, duration?: integer, steps?: integer }
---  hl       Highlight group whose background to swell toward (default "Visual").
---  duration Total breathe time in ms (default 500).
---  steps    Animation frames (default 12).
---@return fun(data: { buf?: integer, line?: integer })
function M.breathe(opts)
  opts = opts or {}
  local hl = opts.hl or "Visual"
  local ms = opts.duration or 500
  local steps = math.max(opts.steps or 12, 2)
  local ns = vim.api.nvim_create_namespace("animfx_breathe")

  return function(data)
    data = data or {}
    local buf = data.buf or vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local line = clamp_line(buf, data.line or (vim.api.nvim_win_get_cursor(0)[1] - 1))

    local to = bg_of(hl)
    if not to then
      -- No background to blend: hold the plain highlight briefly, then clear.
      local id = vim.api.nvim_buf_set_extmark(buf, ns, line, 0, { line_hl_group = hl })
      vim.defer_fn(function()
        if vim.api.nvim_buf_is_valid(buf) then
          pcall(vim.api.nvim_buf_del_extmark, buf, ns, id)
        end
      end, ms)
      return
    end
    local from = bg_of("Normal") or 0x000000

    fade_seq = fade_seq + 1
    local fid = fade_seq
    -- Start invisible (alpha 0 == Normal) so the swell eases in from nothing.
    local group0 = ("AnimfxBreathe%d_0"):format(fid)
    vim.api.nvim_set_hl(0, group0, { bg = from })
    local id = vim.api.nvim_buf_set_extmark(buf, ns, line, 0, { line_hl_group = group0 })

    local frame = 0
    local interval = math.max(1, math.floor(ms / steps))
    local timer = managed_timer()
    timer:start(
      interval,
      interval,
      vim.schedule_wrap(function()
        frame = frame + 1
        if frame >= steps or not vim.api.nvim_buf_is_valid(buf) then
          release_timer(timer)
          if vim.api.nvim_buf_is_valid(buf) then
            pcall(vim.api.nvim_buf_del_extmark, buf, ns, id)
          end
          return
        end
        -- Triangular alpha: rises to 1 at the midpoint, falls back to 0.
        local t = frame / steps
        local alpha = 1 - math.abs(2 * t - 1)
        local group = ("AnimfxBreathe%d_%d"):format(fid, frame)
        vim.api.nvim_set_hl(0, group, { bg = blend(to, from, alpha) })
        pcall(vim.api.nvim_buf_set_extmark, buf, ns, line, 0, { id = id, line_hl_group = group })
      end)
    )
  end
end

--- Show `data.text` (or `data.msg`) as end-of-line virtual text on a line,
--- clearing it after `duration` ms.
---
---@param opts? { hl?: string, duration?: integer }
---  hl       Highlight group for the badge (default "Comment").
---  duration Milliseconds before clearing (default 1500).
---@return fun(data: { buf?: integer, line?: integer, text?: string, msg?: string })
function M.virt_badge(opts)
  opts = opts or {}
  local hl = opts.hl or "Comment"
  local ms = opts.duration or 1500
  local ns = vim.api.nvim_create_namespace("animfx_virt_badge")

  return function(data)
    data = data or {}
    local buf = data.buf or vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local text = data.text or data.msg or ""
    if text == "" then
      return
    end
    local line = clamp_line(buf, data.line or (vim.api.nvim_win_get_cursor(0)[1] - 1))

    local ok, id = pcall(vim.api.nvim_buf_set_extmark, buf, ns, line, 0, {
      virt_text = { { " " .. text .. " ", hl } },
      virt_text_pos = "eol",
    })
    if not ok then
      return
    end
    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_del_extmark, buf, ns, id)
      end
    end, ms)
  end
end

--- Shake a small floating cue at the cursor — a best-effort "shake" for
--- errors. Neovim can't move a non-floating window, so this jitters a
--- floating box instead. Optionally shows `opts.text`. Driven by
--- `animfx.tween`: a decaying sine wave oscillates the box horizontally
--- around the cursor and eases back to `col = 0` exactly as it finishes,
--- rather than snapping between two fixed offsets.
---
---@param opts? { hl?: string, text?: string, amplitude?: integer, times?: integer, interval?: integer, width?: integer, frequency?: number, fps?: number }
---  hl        Highlight group (default "ErrorMsg").
---  text      Optional label shown in the box (default none).
---  amplitude Horizontal jitter in columns (default 2).
---  times     Number of jitters (default 6); with `interval`, derives the
---            tween's total duration (`times * interval` ms).
---  interval  Milliseconds per jitter (default 30); with `times`, derives
---            duration, and alone derives the sine's default `frequency`.
---  width     Box width in cells (default 6).
---  frequency Oscillations per second (default derived from `interval`, so
---            the visual cadence roughly matches the old fixed-step jitter).
---  fps       Tween tick rate in Hz (default 60), independent of `interval`.
---@return fun(data: table)
function M.shake(opts)
  opts = opts or {}
  local hl = opts.hl or "ErrorMsg"
  local text = opts.text or ""
  local amplitude = opts.amplitude or 2
  local times = opts.times or 6
  local interval = opts.interval or 30
  local width = math.max(opts.width or 6, #text + 2)
  -- A full sine cycle (peak -> zero -> trough -> zero) spans two of the old
  -- fixed-step jitters, keeping the new continuous motion's cadence close to
  -- the old binary alternation's.
  local frequency = opts.frequency or 500 / interval
  local duration = (times * interval) / 1000
  local fps = opts.fps or 60
  local scratch = vim.api.nvim_create_buf(false, true)

  local function round(x)
    return x >= 0 and math.floor(x + 0.5) or -math.floor(-x + 0.5)
  end

  return function()
    if not vim.api.nvim_buf_is_valid(scratch) then
      scratch = vim.api.nvim_create_buf(false, true)
    end
    if text ~= "" then
      vim.api.nvim_buf_set_lines(scratch, 0, -1, false, { " " .. text .. " " })
    end
    local ok, win = pcall(vim.api.nvim_open_win, scratch, false, {
      relative = "cursor",
      row = 0,
      col = 0,
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

    -- Decaying sine: envelope `1 - t` reaches exactly 0 at t = 1, so the box
    -- always lands back at col = 0 smoothly instead of snapping there.
    local function progressFn(t)
      local envelope = 1 - t
      local theta = t * duration * frequency * 2 * math.pi
      return math.sin(theta) * envelope
    end

    local function setterFn(offset)
      if not vim.api.nvim_win_is_valid(win) then
        return false
      end
      return pcall(vim.api.nvim_win_set_config, win, {
        relative = "cursor",
        row = 0,
        col = round(amplitude * offset),
      })
    end

    tween.run({
      duration = duration,
      fps = fps,
      progressFn = progressFn,
      setterFn = setterFn,
      onComplete = function()
        if vim.api.nvim_win_is_valid(win) then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end,
    })
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
  local warned = false -- warn at most once per delegate effect, to avoid spam
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
      -- Module loaded but the target isn't callable: a real misconfiguration
      -- (usually a mistyped fn path), so surface it once instead of vanishing.
      if not warned then
        warned = true
        vim.notify(
          ("animfx.delegate: %s%s is not callable"):format(spec.module, spec.fn and ("." .. spec.fn) or ""),
          vim.log.levels.WARN
        )
      end
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

--- Test hook: number of live managed animation timers (delegates to
--- animfx.tween, which owns the shared timer table).
---@return integer
function M._active_timers()
  return tween._active_timers()
end

return M
