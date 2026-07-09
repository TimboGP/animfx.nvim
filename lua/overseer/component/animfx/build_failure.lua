--- overseer.nvim component: emits an animfx event when the task it's
--- attached to finishes with FAILURE status.
---
--- Not meant to be added by hand — `animfx.sources.on_overseer_failure()`
--- wires this onto every task template via `overseer.add_template_hook`, and
--- `opts.event` there controls the event name (passed through as this
--- component's own `event` param).
---
--- Namespaced under `animfx/` per overseer's own convention for third-party
--- components (`:help overseer-custom-components`): discoverable here as
--- `require("overseer.component.animfx.build_failure")`, referenced as
--- `"animfx.build_failure"`.
---@type overseer.ComponentFileDefinition
return {
  desc = "animfx: emit an event when this task fails",
  params = {
    event = { type = "string", optional = true, default = "BuildFailed" },
  },
  constructor = function(params)
    return {
      on_complete = function(_, task, status)
        if status == require("overseer").STATUS.FAILURE then
          require("animfx").emit(params.event, { task = task.name, status = status })
        end
      end,
    }
  end,
}
