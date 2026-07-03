-- Headless test runner. Run from the plugin root with:
--   nvim -l tests/run.lua
-- Exits non-zero on failure.

vim.opt.runtimepath:prepend(vim.fn.getcwd())

local animfx = require("animfx")
local effects = require("animfx.effects")
local c = require("animfx.combinators")

local failed = 0
local function check(name, cond)
  if cond then
    print("  ok   - " .. name)
  else
    failed = failed + 1
    print("  FAIL - " .. name)
  end
end

-- emit reaches a registered effect with the payload -----------------------
do
  local got
  animfx.on("TestBasic", function(data)
    got = data.value
  end)
  animfx.emit("TestBasic", { value = 42 })
  check("emit delivers payload to effect", got == 42)
end

-- multiple effects on one event all run, in order -------------------------
do
  local order = {}
  animfx.on("TestMulti", function()
    order[#order + 1] = "a"
  end)
  animfx.on("TestMulti", function()
    order[#order + 1] = "b"
  end)
  animfx.emit("TestMulti", {})
  check("all effects run in registration order", order[1] == "a" and order[2] == "b")
end

-- a throwing effect does not block later effects --------------------------
do
  local reached = false
  animfx.on("TestIsolation", function()
    error("boom")
  end)
  animfx.on("TestIsolation", function()
    reached = true
  end)
  animfx.emit("TestIsolation", {})
  check("error in one effect is isolated", reached == true)
end

-- off() unregisters -------------------------------------------------------
do
  local hits = 0
  local id = animfx.on("TestOff", function()
    hits = hits + 1
  end)
  animfx.emit("TestOff", {})
  animfx.off(id)
  animfx.emit("TestOff", {})
  check("off() removes the effect", hits == 1)
end

-- emit with no data passes an empty table (no nil crash) ------------------
do
  local ok = true
  animfx.on("TestNilData", function(data)
    ok = type(data) == "table"
  end)
  animfx.emit("TestNilData")
  check("emit with no data yields a table", ok)
end

-- line_flash sets an extmark on the target line ---------------------------
do
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two", "three" })
  local ns = vim.api.nvim_create_namespace("animfx_line_flash")
  effects.line_flash({ hl = "IncSearch", duration = 10 })({ buf = buf, line = 1 })
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
  check("line_flash places an extmark", #marks == 1)
end

-- combinators: chain runs in order with same data -------------------------
do
  local seen = {}
  local eff = c.chain(function(d)
    seen[#seen + 1] = "a" .. d.n
  end, function(d)
    seen[#seen + 1] = "b" .. d.n
  end)
  eff({ n = 1 })
  check("chain runs effects in order with same data", seen[1] == "a1" and seen[2] == "b1")
end

-- combinators: only_if gates on predicate ---------------------------------
do
  local ran = 0
  local eff = c.only_if(function(d)
    return d.ok
  end, function()
    ran = ran + 1
  end)
  eff({ ok = false })
  eff({ ok = true })
  check("only_if gates on predicate", ran == 1)
end

-- combinators: once fires at most once ------------------------------------
do
  local ran = 0
  local eff = c.once(function()
    ran = ran + 1
  end)
  eff({})
  eff({})
  check("once fires at most once", ran == 1)
end

-- combinators: debounce collapses a burst, keeps last data ----------------
do
  local ran, last = 0, nil
  local eff = c.debounce(20, function(d)
    ran = ran + 1
    last = d.n
  end)
  eff({ n = 1 })
  eff({ n = 2 })
  eff({ n = 3 })
  vim.wait(80, function()
    return ran > 0
  end)
  check("debounce collapses burst to one call with last data", ran == 1 and last == 3)
end

-- combinators: throttle fires leading edge, blocks the rest ----------------
do
  local ran = 0
  local eff = c.throttle(40, function()
    ran = ran + 1
  end)
  eff({})
  eff({})
  eff({})
  check("throttle fires only the leading call", ran == 1)
  vim.wait(70)
  eff({})
  check("throttle fires again after the window", ran == 2)
end

-- introspection: list() counts effects per event -------------------------
do
  animfx.on("TestListEv", function() end)
  animfx.on("TestListEv", function() end)
  local list = animfx.list()
  check("list() counts effects per event", list["TestListEv"] == 2)
end

-- introspection: history() records emits ----------------------------------
do
  animfx.emit("TestHistEv", {})
  local hist = animfx.history()
  local found = false
  for _, e in ipairs(hist) do
    if e.event == "TestHistEv" then
      found = true
    end
  end
  check("history() records the emit", found)
end

print(("\n%s (%d failure%s)"):format(failed == 0 and "PASS" or "FAILED", failed, failed == 1 and "" or "s"))
if failed > 0 then
  os.exit(1)
end
