--- animfx — event-triggered animation registry.
---
--- Decouples "something happened" from "what visual effect plays". Call sites
--- emit named events; effects register against event names independently.
---
--- Rides on Neovim's built-in `User` autocmd so registrations stay
--- introspectable via `:au User` and interoperate with anything else that
--- listens for `User` events.
local M = {}

-- Shared augroup. clear = false so re-`require`ing the module (e.g. after a
-- config reload) does not wipe existing registrations out from under callers
-- that registered before the reload.
local augroup = vim.api.nvim_create_augroup("animfx", { clear = false })

--- Register an effect against an event name.
---
--- Multiple effects may be registered for the same event; each becomes its own
--- autocmd and they run in registration order. An effect that throws is caught
--- and reported, so one failing effect never blocks the others.
---
---@param event string           Event name (the `User` autocmd pattern).
---@param effect_fn fun(data:table) Effect to run; receives the emit payload.
---@return integer autocmd_id     Id from `nvim_create_autocmd`, for `M.off`.
function M.on(event, effect_fn)
  assert(type(event) == "string", "animfx.on: event must be a string")
  assert(type(effect_fn) == "function", "animfx.on: effect_fn must be a function")

  return vim.api.nvim_create_autocmd("User", {
    group = augroup,
    pattern = event,
    callback = function(args)
      local ok, err = pcall(effect_fn, args.data)
      if not ok then
        vim.notify(
          ("animfx: effect for %q errored: %s"):format(event, err),
          vim.log.levels.ERROR
        )
      end
    end,
  })
end

--- Remove a previously registered effect by its autocmd id.
---@param id integer The value returned from `M.on`.
function M.off(id)
  pcall(vim.api.nvim_del_autocmd, id)
end

--- Fire an event; every effect registered for it runs synchronously.
---@param event string Event name.
---@param data? table  Arbitrary payload passed through to each effect.
function M.emit(event, data)
  assert(type(event) == "string", "animfx.emit: event must be a string")
  vim.api.nvim_exec_autocmds("User", { pattern = event, data = data or {} })
end

return M
