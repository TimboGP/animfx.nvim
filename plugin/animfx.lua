-- User commands for inspecting and exercising the registry.
-- Guarded so sourcing twice (e.g. reload) is harmless.
if vim.g.loaded_animfx then
  return
end
vim.g.loaded_animfx = true

-- :AnimfxList — show every registered event and how many effects it has.
vim.api.nvim_create_user_command("AnimfxList", function()
  local list = require("animfx").list()
  local events = vim.tbl_keys(list)
  table.sort(events)
  if #events == 0 then
    vim.notify("animfx: no effects registered", vim.log.levels.INFO)
    return
  end
  local lines = { "animfx registrations:" }
  for _, event in ipairs(events) do
    lines[#lines + 1] = ("  %s  (%d effect%s)"):format(event, list[event], list[event] == 1 and "" or "s")
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end, { desc = "List animfx event registrations" })

-- :AnimfxEmit <Event> — fire an event by name (empty payload). Handy for
-- testing effects without editing config. Completes on registered events.
vim.api.nvim_create_user_command("AnimfxEmit", function(o)
  require("animfx").emit(o.args, {})
end, {
  nargs = 1,
  desc = "Emit an animfx event by name",
  complete = function(arglead)
    return vim.tbl_filter(function(name)
      return name:find(arglead, 1, true) == 1
    end, vim.tbl_keys(require("animfx").list()))
  end,
})

-- :AnimfxHistory — show recent emits.
vim.api.nvim_create_user_command("AnimfxHistory", function()
  local hist = require("animfx").history()
  if #hist == 0 then
    vim.notify("animfx: no emits recorded yet", vim.log.levels.INFO)
    return
  end
  local lines = { "animfx recent emits:" }
  for _, e in ipairs(hist) do
    lines[#lines + 1] = ("  %s  %s"):format(os.date("%H:%M:%S", e.at), e.event)
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end, { desc = "Show recent animfx emits" })
