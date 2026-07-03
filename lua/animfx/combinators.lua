--- animfx.combinators — compose effects.
---
--- Every combinator takes effect function(s) — the same `function(data)` shape
--- `animfx.on` expects — and returns a new one. They nest freely:
---
---   animfx.on("HarpoonAdd", c.debounce(200, c.chain(
---     fx.line_flash({ hl = "IncSearch" }),
---     fx.notify_toast({ title = "Harpoon" })
---   )))
local M = {}

--- Run effects in sequence, each with the same `data`.
---@param ... fun(data: table)
---@return fun(data: table)
function M.chain(...)
  local effects = { ... }
  return function(data)
    for _, effect in ipairs(effects) do
      effect(data)
    end
  end
end

--- Defer an effect by `ms` milliseconds.
---@param ms integer
---@param effect fun(data: table)
---@return fun(data: table)
function M.delay(ms, effect)
  return function(data)
    vim.defer_fn(function()
      effect(data)
    end, ms)
  end
end

--- Trailing-edge debounce: collapse a burst of calls into one, firing `ms`
--- after the last call with that call's `data`.
---@param ms integer
---@param effect fun(data: table)
---@return fun(data: table)
function M.debounce(ms, effect)
  local timer
  return function(data)
    if timer then
      pcall(function()
        timer:stop()
        timer:close()
      end)
    end
    timer = vim.defer_fn(function()
      timer = nil
      effect(data)
    end, ms)
  end
end

--- Leading-edge throttle: fire immediately, then ignore calls for `ms`.
---@param ms integer
---@param effect fun(data: table)
---@return fun(data: table)
function M.throttle(ms, effect)
  local blocked = false
  return function(data)
    if blocked then
      return
    end
    blocked = true
    effect(data)
    vim.defer_fn(function()
      blocked = false
    end, ms)
  end
end

--- Run `effect` only when `pred(data)` is truthy.
---@param pred fun(data: table): boolean
---@param effect fun(data: table)
---@return fun(data: table)
function M.only_if(pred, effect)
  return function(data)
    if pred(data) then
      effect(data)
    end
  end
end

--- Run `effect` at most once; subsequent calls are no-ops.
---@param effect fun(data: table)
---@return fun(data: table)
function M.once(effect)
  local done = false
  return function(data)
    if done then
      return
    end
    done = true
    effect(data)
  end
end

return M
