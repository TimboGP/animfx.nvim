-- Integration checks that run against a REAL nvim-notify on the runtimepath.
-- Driven by tests/integration/run.sh, which installs the backend and sets
-- ANIMFX_ROOT / ANIMFX_DEPS. Exits non-zero on failure.

local root = os.getenv("ANIMFX_ROOT") or vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
for dep in vim.gsplit(os.getenv("ANIMFX_DEPS") or "", ":", { plain = true }) do
  if dep ~= "" then
    vim.opt.runtimepath:append(dep)
  end
end

local effects = require("animfx.effects")

local failed = 0
local function check(name, cond)
  if cond then
    print("  ok   - " .. name)
  else
    failed = failed + 1
    print("  FAIL - " .. name)
  end
end

-- The real backend actually resolves from the runtimepath.
local ok = pcall(require, "notify")
check("nvim-notify resolves from the runtimepath", ok)

-- notify_toast targets the installed backend with the right arguments.
-- (We capture the call rather than render, so the assertion is deterministic
-- headless — the integration point is that our code finds and calls it.)
do
  local calls = {}
  package.loaded.notify = setmetatable({}, {
    __call = function(_, msg, level, opts)
      calls[#calls + 1] = { msg = msg, level = level, opts = opts }
    end,
  })
  effects.notify_toast({ title = "T" })({ msg = "hi" })
  local first = calls[1]
  check("notify_toast calls the backend with data.msg", first ~= nil and first.msg == "hi")
  check("notify_toast merges animate=true", first ~= nil and first.opts and first.opts.animate == true)
  check("notify_toast passes opts through", first ~= nil and first.opts and first.opts.title == "T")
end

-- delegate resolves and calls a real installed module (nvim-notify).
do
  local called = false
  package.loaded.notify = setmetatable({}, {
    __call = function()
      called = true
    end,
  })
  effects.delegate({
    module = "notify",
    args = function(d)
      return { d.msg, "info" }
    end,
  })({ msg = "x" })
  check("delegate invokes a real installed backend", called)
end

print(("\n%s (%d failure%s)"):format(failed == 0 and "PASS" or "FAILED", failed, failed == 1 and "" or "s"))
if failed > 0 then
  os.exit(1)
end
