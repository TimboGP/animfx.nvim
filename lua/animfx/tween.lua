--- animfx.tween — shared progress/setter split for timer-driven animations.
---
--- `M.run(spec)` owns a repeating `vim.uv` timer that turns real elapsed
--- wall-clock time into a normalized progress value `t` in [0, 1] via
--- `spec.progressFn`, then hands whatever that returns to `spec.setterFn` to
--- apply. Progress is computed from `vim.uv.hrtime()` each tick, not a step
--- counter, so a delayed or dropped tick changes visual smoothness, not the
--- effect's total duration.
---
--- Ported from hammerspoon-animfx's `tween.lua` (`vim.uv.new_timer()` +
--- `vim.uv.hrtime()` standing in for `hs.timer.doEvery` +
--- `hs.timer.secondsSinceEpoch()`). Also owns the timer-tracking machinery
--- shared with `animfx.effects`'s hand-rolled timers, so one table and one
--- `VimLeavePre` hook cover every repeating animation timer in the plugin.
local M = {}

-- Repeating animation timers, tracked so any still in flight can be cancelled
-- on exit rather than leaking or firing a callback into a closing Neovim.
local active_timers = {}

--- Create a `vim.uv` timer tracked for exit cleanup.
local function managed_timer()
  local timer = vim.uv.new_timer()
  active_timers[timer] = true
  return timer
end

--- Stop, close, and untrack a timer created by `managed_timer`.
local function release_timer(timer)
  if timer and not timer:is_closing() then
    timer:stop()
    timer:close()
  end
  active_timers[timer] = nil
end

M.managed_timer = managed_timer
M.release_timer = release_timer

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("animfx_tween_cleanup", { clear = true }),
  callback = function()
    for timer in pairs(active_timers) do
      pcall(release_timer, timer)
    end
  end,
})

--- Run a time-based tween: repeatedly compute progress from real elapsed
--- wall-clock time and apply it via a setter, until `spec.duration` elapses
--- or the setter signals it should stop.
---
---@class animfx.TweenSpec
---@field duration number Total tween time in seconds; must be > 0.
---@field progressFn fun(t: number): any Maps normalized time `t` in [0, 1] to
---  whatever value `setterFn` expects (an offset, alpha, ...).
---@field setterFn fun(value: any): boolean? Applies a value. Returning
---  `false` cancels the tween early (e.g. its target became invalid).
---@field fps? number Tick rate in Hz (default 60).
---@field onComplete? fun(cancelled: boolean) Called exactly once, however the
---  tween ends (finished, cancelled, or `setterFn` returning `false`).
---
---@param spec animfx.TweenSpec
---@return table handle `{ cancel = fun(), isRunning = fun(): boolean }`
function M.run(spec)
  assert(spec.duration and spec.duration > 0, "animfx: tween.run needs a positive duration")
  assert(type(spec.progressFn) == "function", "animfx: tween.run needs a progressFn")
  assert(type(spec.setterFn) == "function", "animfx: tween.run needs a setterFn")

  local duration = spec.duration
  local interval_ms = math.max(1, math.floor(1000 / (spec.fps or 60)))
  local start = vim.uv.hrtime()
  local finished = false
  local timer = managed_timer()

  local function finish(cancelled)
    if finished then
      return
    end
    finished = true
    release_timer(timer)
    if spec.onComplete then
      spec.onComplete(cancelled)
    end
  end

  timer:start(
    interval_ms,
    interval_ms,
    vim.schedule_wrap(function()
      if finished then
        return
      end
      local elapsed = (vim.uv.hrtime() - start) / 1e9
      local t = math.min(elapsed / duration, 1)
      local ok = spec.setterFn(spec.progressFn(t))
      if ok == false then
        finish(true)
        return
      end
      if t >= 1 then
        finish(false)
      end
    end)
  )

  return {
    cancel = function()
      finish(true)
    end,
    isRunning = function()
      return not finished
    end,
  }
end

--- Test hook: number of live managed animation timers (shared with
--- `animfx.effects`, which delegates its own `_active_timers()` here).
---@return integer
function M._active_timers()
  return vim.tbl_count(active_timers)
end

return M
