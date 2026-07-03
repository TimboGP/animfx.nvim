-- Headless test runner. Run from the plugin root with:
--   make test          (nvim --clean -l tests/run.lua)
-- Exits non-zero on failure.
--
-- Spec-to-test traceability: every check() is tagged with the spec requirement
-- it covers, formatted "<capability>: <Requirement heading>" exactly as it
-- appears in openspec/specs/<capability>/spec.md. After the tests run, a
-- coverage gate cross-checks both directions:
--   * a test tagged with an unknown requirement fails (dangling reference)
--   * a requirement with no unit test and not on the integration allowlist
--     fails (uncovered)
-- See CONTRIBUTING.md.

vim.opt.runtimepath:prepend(vim.fn.getcwd())

local animfx = require("animfx")
local effects = require("animfx.effects")
local c = require("animfx.combinators")

local failed = 0
local covered = {} -- spec ref -> true, for the coverage gate

local function check(spec, name, cond)
  covered[spec] = true
  if cond then
    print(("  ok   - [%s] %s"):format(spec, name))
  else
    failed = failed + 1
    print(("  FAIL - [%s] %s"):format(spec, name))
  end
end

-- registry ----------------------------------------------------------------
do
  local got
  animfx.on("TestBasic", function(data)
    got = data.value
  end)
  animfx.emit("TestBasic", { value = 42 })
  check("registry: Register an effect against an event", "emit delivers payload to effect", got == 42)
end

do
  local ok = true
  animfx.on("TestNilData", function(data)
    ok = type(data) == "table"
  end)
  animfx.emit("TestNilData")
  check("registry: Emit runs every registered effect", "emit with no data yields a table", ok)
end

do
  local order = {}
  animfx.on("TestMulti", function()
    order[#order + 1] = "a"
  end)
  animfx.on("TestMulti", function()
    order[#order + 1] = "b"
  end)
  animfx.emit("TestMulti", {})
  check(
    "registry: Multiple effects run in registration order",
    "effects run in registration order",
    order[1] == "a" and order[2] == "b"
  )
end

do
  local reached = false
  animfx.on("TestIsolation", function()
    error("boom")
  end)
  animfx.on("TestIsolation", function()
    reached = true
  end)
  animfx.emit("TestIsolation", {})
  check("registry: Error isolation between effects", "error in one effect is isolated", reached == true)
end

do
  local hits = 0
  local id = animfx.on("TestOff", function()
    hits = hits + 1
  end)
  animfx.emit("TestOff", {})
  animfx.off(id)
  animfx.emit("TestOff", {})
  check("registry: Unregister an effect", "off() removes the effect", hits == 1)
end

do
  local ran = false
  animfx.on("TestSched", function()
    ran = true
  end)
  animfx.emit("TestSched", {}, { schedule = true })
  check("registry: Synchronous by default, optionally scheduled", "scheduled emit does not run synchronously", ran == false)
  vim.wait(50, function()
    return ran
  end)
  check("registry: Synchronous by default, optionally scheduled", "scheduled emit runs on the next tick", ran == true)
end

do
  local fired = false
  vim.api.nvim_create_autocmd("User", {
    pattern = "TestInterop",
    callback = function()
      fired = true
    end,
  })
  animfx.emit("TestInterop", {})
  check("registry: Interoperate with User autocmds", "external User listener receives the emit", fired)
end

do
  animfx.on("TestClearE", function() end)
  animfx.on("TestClearE", function() end)
  animfx.on("TestClearF", function() end)
  animfx.clear("TestClearE")
  local after = animfx.list()
  check(
    "registry: Clear registrations",
    "clear(event) removes only that event",
    after["TestClearE"] == nil and after["TestClearF"] == 1
  )
  animfx.clear()
  check("registry: Clear registrations", "clear() removes all registrations", next(animfx.list()) == nil)
end

-- effects -----------------------------------------------------------------
do
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two", "three" })
  local ns = vim.api.nvim_create_namespace("animfx_line_flash")
  effects.line_flash({ hl = "IncSearch", duration = 10 })({ buf = buf, line = 1 })
  check("effects: Line flash", "line_flash places an extmark", #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) == 1)

  local flash = effects.line_flash({ hl = "IncSearch", duration = 10 })
  for _ = 1, 200 do
    flash({ buf = buf, line = 0 })
  end
  vim.wait(120, function()
    return #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) == 0
  end)
  check("effects: Line flash", "200 rapid flashes leave zero extmarks", #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) == 0)
end

do
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two" })
  local ns = vim.api.nvim_create_namespace("animfx_line_flash")
  local ok = pcall(effects.line_flash({ duration = 10 }), { buf = buf, line = 100 })
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
  check(
    "effects: Line flash",
    "out-of-range line is clamped, not an error",
    ok and #marks == 1 and marks[1][2] == 1
  )
end

do
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "a", "b" })
  local ns = vim.api.nvim_create_namespace("animfx_line_flash")
  effects.line_flash({ hl = "IncSearch", duration = 40, fade = true, steps = 4 })({ buf = buf, line = 0 })
  vim.wait(200, function()
    return #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) == 0
  end)
  check("effects: Line flash fade-out", "fade cleans up its extmark", #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) == 0)
end

do
  -- Two fades started together on different buffers must not share highlight
  -- groups (regression: previously both used "AnimfxFade<frame>" globally).
  local ns = vim.api.nvim_create_namespace("animfx_line_flash")
  local function mkbuf()
    local b = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(b, 0, -1, false, { "x" })
    return b
  end
  local b1, b2 = mkbuf(), mkbuf()
  -- steps/duration chosen so a sample at 150ms lands both on frame 1 reliably.
  effects.line_flash({ hl = "IncSearch", fade = true, steps = 3, duration = 300 })({ buf = b1, line = 0 })
  effects.line_flash({ hl = "Search", fade = true, steps = 3, duration = 300 })({ buf = b2, line = 0 })
  vim.wait(150)
  local function group(b)
    local m = vim.api.nvim_buf_get_extmarks(b, ns, 0, -1, { details = true })
    return m[1] and m[1][4] and m[1][4].line_hl_group
  end
  local g1, g2 = group(b1), group(b2)
  check(
    "effects: Line flash fade-out",
    "concurrent fades use distinct highlight groups",
    g1 ~= nil and g2 ~= nil and g1 ~= g2
  )
end

do
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two" })
  local ns = vim.api.nvim_create_namespace("animfx_sign_flash")
  effects.sign_flash({ duration = 10 })({ buf = buf, line = 0 })
  local placed = #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
  vim.wait(80, function()
    return #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) == 0
  end)
  check(
    "effects: Sign flash",
    "sign_flash places then clears a sign",
    placed == 1 and #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) == 0
  )
end

do
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two" })
  local ns = vim.api.nvim_create_namespace("animfx_sign_flash")
  local ok = pcall(effects.sign_flash({ duration = 10 }), { buf = buf, line = 100 })
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
  check(
    "effects: Sign flash",
    "out-of-range line is clamped, not an error",
    ok and #marks == 1 and marks[1][2] == 1
  )
end

do
  local function floats()
    local n = 0
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(w).relative ~= "" then
        n = n + 1
      end
    end
    return n
  end
  local before = floats()
  effects.cursor_beacon({ duration = 30, steps = 3 })({})
  check("effects: Cursor beacon", "cursor_beacon opens a floating window", floats() == before + 1)
  vim.wait(120, function()
    return floats() == before
  end)
  check("effects: Cursor beacon", "cursor_beacon closes the float", floats() == before)
end

do
  -- With no nvim-notify (guaranteed under --clean), notify_toast must fall back.
  local captured
  local orig = vim.notify
  vim.notify = function(msg)
    captured = msg
  end
  effects.notify_toast({})({ msg = "hello" })
  vim.notify = orig
  check("effects: Notify toast", "notify_toast falls back to vim.notify", captured == "hello")
end

do
  local fellback = false
  effects.delegate({
    module = "definitely_not_a_real_module_xyz",
    fallback = function()
      fellback = true
    end,
  })({})
  check("effects: Delegate to an external backend", "delegate falls back when module absent", fellback)

  package.loaded["animfx_fake_backend"] = {
    boom = function(d)
      _G.__animfx_delegate_arg = d.v
    end,
  }
  effects.delegate({ module = "animfx_fake_backend", fn = "boom" })({ v = 7 })
  check("effects: Delegate to an external backend", "delegate calls the resolved target", _G.__animfx_delegate_arg == 7)

  -- Module loaded but fn path is wrong -> warn once across repeated calls.
  package.loaded["animfx_badfn"] = { real = function() end }
  local warns = 0
  local orig = vim.notify
  vim.notify = function()
    warns = warns + 1
  end
  local eff = effects.delegate({ module = "animfx_badfn", fn = "does_not_exist" })
  eff({})
  eff({})
  vim.notify = orig
  check("effects: Delegate to an external backend", "delegate warns once on an uncallable target", warns == 1)
end

do
  -- A long fade leaves a repeating timer live; VimLeavePre must cancel it.
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x" })
  effects.line_flash({ hl = "IncSearch", fade = true, steps = 50, duration = 5000 })({ buf = buf, line = 0 })
  check("effects: Animation timers are cancelled on exit", "fade registers a live timer", effects._active_timers() >= 1)
  vim.api.nvim_exec_autocmds("VimLeavePre", {})
  check("effects: Animation timers are cancelled on exit", "VimLeavePre cancels active timers", effects._active_timers() == 0)
end

-- combinators -------------------------------------------------------------
do
  local seen = {}
  c.chain(function(d)
    seen[#seen + 1] = "a" .. d.n
  end, function(d)
    seen[#seen + 1] = "b" .. d.n
  end)({ n = 1 })
  check("combinators: Chain effects in sequence", "chain runs effects in order with same data", seen[1] == "a1" and seen[2] == "b1")
end

do
  local ran = false
  c.delay(20, function()
    ran = true
  end)({})
  check("combinators: Delay an effect", "delay does not fire immediately", ran == false)
  vim.wait(60, function()
    return ran
  end)
  check("combinators: Delay an effect", "delay fires after the delay", ran == true)
end

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
  check("combinators: Debounce a burst", "debounce collapses burst to one call with last data", ran == 1 and last == 3)
end

do
  local ran = 0
  local eff = c.throttle(40, function()
    ran = ran + 1
  end)
  eff({})
  eff({})
  eff({})
  check("combinators: Throttle calls", "throttle fires only the leading call", ran == 1)
  vim.wait(70)
  eff({})
  check("combinators: Throttle calls", "throttle fires again after the window", ran == 2)
end

do
  local ran = 0
  local eff = c.only_if(function(d)
    return d.ok
  end, function()
    ran = ran + 1
  end)
  eff({ ok = false })
  eff({ ok = true })
  check("combinators: Conditional effect", "only_if gates on predicate", ran == 1)
end

do
  local ran = 0
  local eff = c.once(function()
    ran = ran + 1
  end)
  eff({})
  eff({})
  check("combinators: Run once", "once fires at most once", ran == 1)
end

-- introspection -----------------------------------------------------------
do
  animfx.on("TestListEv", function() end)
  animfx.on("TestListEv", function() end)
  check("introspection: List registrations", "list() counts effects per event", animfx.list()["TestListEv"] == 2)
end

do
  animfx.emit("TestHistEv", {})
  local found = false
  for _, e in ipairs(animfx.history()) do
    if e.event == "TestHistEv" then
      found = true
    end
  end
  check("introspection: Emit history ring buffer", "history() records the emit", found)

  for _ = 1, 150 do
    animfx.emit("TestBoundEv", {})
  end
  check("introspection: Emit history ring buffer", "history is bounded to 100 entries", #animfx.history() <= 100)

  for i = 1, 105 do
    animfx.emit("TO" .. i, {})
  end
  local h = animfx.history()
  check(
    "introspection: Emit history ring buffer",
    "history stays oldest-first after wraparound",
    #h == 100 and h[1].event == "TO6" and h[100].event == "TO105"
  )
end

do
  vim.cmd("runtime plugin/animfx.lua")
  local ran = false
  animfx.on("TestCmdEv", function()
    ran = true
  end)
  vim.cmd("AnimfxEmit TestCmdEv")
  check("introspection: Inspection and emit commands", ":AnimfxEmit fires the named event", ran)
end

-- remote ------------------------------------------------------------------
do
  local remote = require("animfx.remote")
  local addr = remote.serve({ address = vim.fn.tempname() })
  check("remote: Serve a socket address", "serve() returns a non-empty address", type(addr) == "string" and #addr > 0)
  pcall(vim.fn.serverstop, addr)
end

do
  local expr = require("animfx.remote").remote_expr("WorkspaceSwitch", { workspace = "3" })
  check(
    "remote: Build a remote emit expression",
    "remote_expr embeds event name and JSON-decodes data",
    expr:find("WorkspaceSwitch", 1, true) ~= nil and expr:find("json.decode", 1, true) ~= nil
  )
end

-- Spec-to-test coverage gate ----------------------------------------------
-- Requirements coverable only by tests/integration/run.sh (real backends,
-- multi-process, or checkhealth UI), not by this headless unit runner.
local integration_covered = {
  ["introspection: Health check"] = true,
  ["remote: External emit delivers to registered effects"] = true,
  ["remote: Graceful when no socket is present"] = true,
}

local valid = {}
local total = 0
for _, cap in ipairs(vim.fn.readdir("openspec/specs")) do
  local file = "openspec/specs/" .. cap .. "/spec.md"
  if vim.fn.filereadable(file) == 1 then
    for _, line in ipairs(vim.fn.readfile(file)) do
      local req = line:match("^### Requirement:%s*(.-)%s*$")
      if req then
        total = total + 1
        valid[cap .. ": " .. req] = true
      end
    end
  end
end

print("")
-- Dangling: a test (or the allowlist) references a requirement that doesn't exist.
for ref in pairs(covered) do
  if not valid[ref] then
    failed = failed + 1
    print("  DANGLING  - test references unknown requirement: " .. ref)
  end
end
for ref in pairs(integration_covered) do
  if not valid[ref] then
    failed = failed + 1
    print("  DANGLING  - integration allowlist references unknown requirement: " .. ref)
  end
end
-- Uncovered: a requirement no unit test covers and not on the integration allowlist.
local n_unit = 0
for ref in pairs(valid) do
  if covered[ref] then
    n_unit = n_unit + 1
  elseif not integration_covered[ref] then
    failed = failed + 1
    print("  UNCOVERED - no test for requirement: " .. ref)
  end
end

print(("\nSpec coverage: %d requirements — %d unit, %d integration"):format(total, n_unit, vim.tbl_count(integration_covered)))
print(("%s (%d failure%s)"):format(failed == 0 and "PASS" or "FAILED", failed, failed == 1 and "" or "s"))
if failed > 0 then
  os.exit(1)
end
