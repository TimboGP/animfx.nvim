--- `:checkhealth animfx`
local M = {}

function M.check()
  vim.health.start("animfx")
  vim.health.ok("core loaded")

  if pcall(require, "notify") then
    vim.health.ok("nvim-notify found — effects.notify_toast animates")
  else
    vim.health.warn(
      "nvim-notify not found — effects.notify_toast falls back to vim.notify",
      "Install rcarriga/nvim-notify to enable animated toasts."
    )
  end
end

return M
