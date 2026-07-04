-- Integration check for animfx.sources.on_harpoon against real harpoon.nvim v2.
-- Driven by tests/integration/run.sh, which installs harpoon + plenary and sets
-- ANIMFX_ROOT / ANIMFX_HARPOON_DEPS. Exits non-zero on failure.

local root = os.getenv("ANIMFX_ROOT") or vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
for dep in vim.gsplit(os.getenv("ANIMFX_HARPOON_DEPS") or "", ":", { plain = true }) do
  if dep ~= "" then
    vim.opt.runtimepath:append(dep)
  end
end

local failed = 0
local function check(name, cond)
  if cond then
    print("  ok   - " .. name)
  else
    failed = failed + 1
    print("  FAIL - " .. name)
  end
end

local hok, harpoon = pcall(require, "harpoon")
check("harpoon resolves from the runtimepath", hok)

if hok then
  harpoon:setup()
  require("animfx.sources").on_harpoon({ event = "HarpoonAdd" })

  local got
  require("animfx").on("HarpoonAdd", function(d)
    got = d
  end)

  vim.cmd("edit " .. vim.fn.tempname()) -- a named buffer to add
  harpoon:list():add()
  vim.wait(1000, function()
    return got ~= nil
  end)

  check("on_harpoon emits HarpoonAdd on add", got ~= nil)
  check("event carries the added item's value", got ~= nil and type(got.value) == "string" and got.value ~= "")
end

print(("\n%s (%d failure%s)"):format(failed == 0 and "PASS" or "FAILED", failed, failed == 1 and "" or "s"))
if failed > 0 then
  os.exit(1)
end
