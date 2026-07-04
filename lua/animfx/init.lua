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

-- Bounded ring buffer of recent emits, for debugging "did my event fire?".
-- Fixed slots written round-robin so recording is O(1) (no array shift).
local TRACE_MAX = 100
local trace = {}
local trace_count = 0 -- total emits; write slot derives from this

-- Autocmd ids created by the most recent M.setup(), so a re-run can replace
-- just those without touching effects registered directly via M.on().
local setup_ids = {}

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

--- Register effects declaratively. `config` maps an event name to an effect
--- function or a list of them. Re-running replaces the registrations the
--- previous `setup` made, leaving effects registered via `on()` untouched.
---@param config table<string, fun(data: table)|(fun(data: table))[]>
function M.setup(config)
  assert(type(config) == "table", "animfx.setup: config must be a table")

  for _, id in ipairs(setup_ids) do
    M.off(id)
  end
  setup_ids = {}

  for event, effects in pairs(config) do
    if type(effects) == "function" then
      effects = { effects }
    end
    assert(type(effects) == "table", "animfx.setup: " .. event .. " must be a function or a list of functions")
    for _, effect_fn in ipairs(effects) do
      setup_ids[#setup_ids + 1] = M.on(event, effect_fn)
    end
  end
end

--- Remove all effects for `event`, or every animfx registration when called
--- with no argument. Only touches registrations made through animfx.
---@param event? string Event name; omit to clear all.
function M.clear(event)
  local opts = { group = augroup, event = "User" }
  if event ~= nil then
    assert(type(event) == "string", "animfx.clear: event must be a string or nil")
    opts.pattern = event
  end
  vim.api.nvim_clear_autocmds(opts)
end

--- Fire an event; every effect registered for it runs.
---
--- Effects run synchronously by default, so a slow effect blocks whatever
--- emitted (usually a keymap). Pass `{ schedule = true }` to run them on the
--- next event-loop tick instead, decoupling the UI feedback from the action.
---@param event string  Event name.
---@param data? table   Arbitrary payload passed through to each effect.
---@param opts? { schedule?: boolean }
function M.emit(event, data, opts)
  assert(type(event) == "string", "animfx.emit: event must be a string")

  trace_count = trace_count + 1
  trace[(trace_count - 1) % TRACE_MAX + 1] = { event = event, at = os.time() }

  local fire = function()
    vim.api.nvim_exec_autocmds("User", { pattern = event, data = data or {} })
  end
  if opts and opts.schedule then
    vim.schedule(fire)
  else
    fire()
  end
end

--- Introspect registrations: a map of event name → number of effects bound.
--- Reads back the live `User` autocmds in animfx's augroup.
---@return table<string, integer>
function M.list()
  local counts = {}
  for _, au in ipairs(vim.api.nvim_get_autocmds({ group = augroup, event = "User" })) do
    counts[au.pattern] = (counts[au.pattern] or 0) + 1
  end
  return counts
end

--- Recent emits (oldest first), for debugging. Each entry: { event, at }.
---@return { event: string, at: integer }[]
function M.history()
  local n = math.min(trace_count, TRACE_MAX)
  -- Before wrap the oldest slot is 1; after wrap it's the slot just past the
  -- most recent write.
  local oldest = trace_count <= TRACE_MAX and 0 or (trace_count % TRACE_MAX)
  local out = {}
  for i = 0, n - 1 do
    out[i + 1] = vim.deepcopy(trace[(oldest + i) % TRACE_MAX + 1])
  end
  return out
end

return M
