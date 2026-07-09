# animfx.nvim

[![test](https://github.com/TimboGP/animfx.nvim/actions/workflows/test.yml/badge.svg)](https://github.com/TimboGP/animfx.nvim/actions/workflows/test.yml)

Event-triggered animation registry for Neovim. Decouples *"something happened"*
from *"what visual effect plays."* Call sites emit named events; effects
register against event names independently.

Backend-agnostic: effects can be hand-rolled (a highlight flash) or delegate to
existing engines (`nvim-notify`, and — later — `mini.animate`, `pulsar.nvim`).

It rides on Neovim's built-in `User` autocmd, so every registration is
introspectable with `:au User` and interoperates with anything else listening
for `User` events. No new event plumbing.

## Why

`mini.animate`, `smear-cursor.nvim`, and `pulsar.nvim` cover Neovim's *own*
actions (cursor movement, scrolls, jumps). Nothing maps an **arbitrary custom
event name → effect**. This does exactly that, and nothing more — register an
effect against an event, emit the event, run the effect(s).

## What makes it different

Every other animation plugin bundles *the trigger, the animation, and the
target* into one fixed feature. animfx.nvim is the opposite: it's a **registry**
that owns none of those. It only routes named events to registered effects — the
trigger is your `emit` call, the effect is any function you register, the target
is whatever you put in the payload.

| | Other animation plugins | **animfx.nvim** |
|---|---|---|
| **Triggers** | Fixed, built-in Neovim actions (cursor move, scroll, jump, resize) | Any event you name and `emit` — Harpoon add, build failed, cross-layer signals |
| **Effects** | The one animation the plugin ships | Any `function(data)`; hand-rolled or delegating to another engine |
| **Coupling** | Trigger ⇄ effect welded together | Emit sites and effects register independently; neither knows the other |
| **Backend** | Its own engine, exclusively | Backend-agnostic — flash by hand, or wrap `nvim-notify` / `mini.animate` / `pulsar` |
| **Scope** | A feature | Plumbing — the missing "map arbitrary event → effect" layer |

So it doesn't *compete* with those plugins — it composes them. A `pulsar` pulse
or a `mini.animate` sequence can be wrapped as an animfx effect and fired from
the same registry as a hand-rolled flash, giving one consistent
"emit event → play effect" surface across every backend.

The shape is deliberately the same as hook-based enforcement (`PreToolUse`-style
guards): **emit an event, let independently-registered handlers decide what
happens** — applied to UI feedback instead of tool gating.

## Install

`lazy.nvim`:

```lua
{ "TimboGP/animfx.nvim", version = "*" }  -- pin to tagged releases
```

No `opts`/`setup()` — it's a library. `require` it where you wire things up.

## API

```lua
local animfx = require("animfx")

--- Declarative registration: map events to an effect or a list of them.
--- Re-running replaces what the previous setup() registered, leaving
--- on() registrations untouched.
animfx.setup({
  HarpoonAdd = { effects.line_flash({ hl = "IncSearch" }), effects.notify_toast({}) },
  BuildFailed = effects.cursor_beacon({ hl = "Error" }),
})

--- Register an effect against an event. Returns an autocmd id.
--- Multiple effects per event run in registration order; a throwing
--- effect is caught and reported, never blocking the others.
animfx.on(event, effect_fn)   -- effect_fn: function(data) ... end

--- Fire an event. Effects run synchronously by default; pass
--- { schedule = true } to run them on the next tick so a slow effect
--- never blocks the keymap that emitted.
animfx.emit(event, data, opts)  -- data: arbitrary table; opts: { schedule? }

--- Unregister by the id returned from on().
animfx.off(id)

--- Introspect: map of event name → number of effects registered.
animfx.list()

--- Recent emits (bounded ring buffer), oldest first: { event, at }.
animfx.history()

--- Global on/off switch. While disabled, events still fire (other User
--- listeners and introspection are unaffected) but effects no-op.
animfx.disable()
animfx.enable()
animfx.is_enabled()
```

By default effects are skipped while a macro is recording or replaying (so an
animation doesn't fire dozens of times during `@q`). Set
`vim.g.animfx_animate_in_macros = true` to opt back in.

### Commands

Because it rides `User` autocmds, registrations are visible with `:au User` —
plus these helpers for exercising and inspecting effects without editing config:

| Command | Does |
|---|---|
| `:AnimfxList` | List registered events and their effect counts |
| `:AnimfxEmit <Event>` | Fire an event by name (empty payload); completes on registered events |
| `:AnimfxHistory` | Show recent emits with timestamps |

## Effects

`require("animfx.effects")` provides constructors — each takes `opts` and
returns a `function(data)` ready for `animfx.on`.

```lua
local fx = require("animfx.effects")

-- Full-line highlight flash, auto-clears after `duration` ms.
-- With fade = true it steps the background toward Normal instead of a
-- hard clear — a real fade-out.
fx.line_flash({ hl = "IncSearch", duration = 150, fade = true, steps = 8 })
--   data: { buf?, line? }  — defaults to current buffer / cursor line

-- Highlight an arbitrary range; falls back to the '[ / '] change marks.
fx.range_flash({ hl = "IncSearch", duration = 150 })
--   data: { buf?, start_row?, start_col?, end_row?, end_col? }  (0-indexed)

-- Gutter sign flash — visible even when the line is scrolled off-screen.
fx.sign_flash({ text = "▐", hl = "IncSearch", duration = 300 })
--   data: { buf?, line? }

-- Cursor pulse — a small floating window that fades out. Dependency-free:
-- the same visual as pulsar/beacon, driven from this registry.
fx.cursor_beacon({ hl = "Search", width = 10, duration = 220 })
--   data: {}  (positions at the cursor)

-- Inverse pulse — a wide, faint box that contracts and solidifies onto the
-- cursor, honing in on where it just landed. The reverse of cursor_beacon.
fx.cursor_implode({ hl = "Search", width = 20, duration = 220 })
--   data: {}  (positions at the cursor)

-- Expanding ripple — a box that grows outward from the cursor while fading, a
-- dissipating ring. The outward twin of cursor_implode.
fx.cursor_ripple({ hl = "Search", width = 24, duration = 240 })
--   data: {}  (positions at the cursor)

-- Column sweep — a highlighted band that scans left→right across the line.
fx.column_sweep({ hl = "Search", width = 8, duration = 240 })
--   data: { buf?, line? }

-- Breathe — swell a line's background toward a color and recede: a soft glow.
fx.breathe({ hl = "Visual", duration = 500 })
--   data: { buf?, line? }

-- Flash a line on/off N times, then clear.
fx.blink({ hl = "IncSearch", times = 3, interval = 100 })
--   data: { buf?, line? }

-- End-of-line virtual-text badge that clears after `duration`.
fx.virt_badge({ hl = "Comment", duration = 1500 })
--   data: { buf?, line?, text }  (or `msg`)

-- Shake a floating cue at the cursor (best-effort; Neovim can't move the
-- real window). Good for error feedback.
fx.shake({ hl = "ErrorMsg", times = 6, amplitude = 2 })
--   data: {}  (positions at the cursor)

-- Animated toast via nvim-notify (falls back to vim.notify if absent).
fx.notify_toast({ title = "Harpoon", timeout = 2000 })
--   data: { msg?, level? }  — opts are merged over { animate = true }
```

### Delegating to other engines

`fx.delegate` wraps any other plugin's function as an animfx effect, degrading
gracefully when it isn't installed. This is the "composes, doesn't compete"
claim made concrete — one registry drives every backend:

```lua
-- Fire pulsar.nvim's pulse from the registry (no-op if pulsar isn't present).
animfx.on("CursorLanded", fx.delegate({ module = "pulsar", fn = "pulse" }))

-- Or delegate with custom args and a fallback.
animfx.on("BigJump", fx.delegate({
  module = "mini.animate",
  fn = "animate",
  args = function(data) return { data.steps, data.timing } end,
  fallback = fx.cursor_beacon({ hl = "Search" }),  -- used if mini.animate is absent
}))
```

## Event sources

`require("animfx.sources")` provides curated, opt-in adapters that emit animfx
events from common Neovim happenings — so effects work without wiring `emit`
yourself. These are deliberately specific (not a general autocmd wrapper).

```lua
local sources = require("animfx.sources")
sources.on_yank()        -- "Yank"       on TextYankPost     { buf, start_row, ... }
sources.on_diagnostic()  -- "Diagnostic" on DiagnosticChanged { buf, count }
sources.on_search()      -- "Search"     on n / N            { buf, line, col, pattern }
sources.on_harpoon()     -- "HarpoonAdd" on harpoon add      { buf, value, idx }
sources.on_build_failure() -- "BuildFailed" on :make-style QuickFixCmdPost { count }
sources.on_overseer_failure() -- "BuildFailed" on any overseer.nvim task FAILURE { task, status }
```

**Recipe — Harpoon add** (the motivating integration; see
[`examples/harpoon-add.lua`](examples/harpoon-add.lua)):

```lua
require("animfx.sources").on_harpoon()
animfx.on("HarpoonAdd", fx.line_flash({ hl = "IncSearch" }))
```

**Recipe — yank highlight** (reimplements `vim.highlight.on_yank` through the
registry):

```lua
local animfx = require("animfx")
local fx = require("animfx.effects")

require("animfx.sources").on_yank()          -- emits "Yank" with the yanked range
animfx.on("Yank", fx.range_flash({ hl = "IncSearch", duration = 150 }))
```

`on_yank({ event = "Yank" })` fires on every yank with
`{ buf, start_row, start_col, end_row, end_col }`; `range_flash` with no
explicit range picks up the `'[` / `']` marks, so the two compose directly.

**Recipe — Hammerspoon wiggle on build failure** (requires macOS, Hammerspoon,
and `hammerspoon-window-mgmt`'s `spoon.WindowMgmt:wiggleFocusedWindow()`; see
[`examples/hammerspoon-build-failure.lua`](examples/hammerspoon-build-failure.lua)):

```lua
require("animfx.sources").on_build_failure()     -- emits "BuildFailed" on :make with { count }
require("animfx.sources").on_overseer_failure()  -- emits "BuildFailed" on any failed overseer task
require("animfx").on("BuildFailed",
  require("animfx.combinators").debounce(300,
    require("animfx.remote_effects").hammerspoon_wiggle()))
```

`on_overseer_failure` is the overseer.nvim-specific twin of `on_build_failure`
(needed because overseer tasks don't run through `:make` and don't populate
the quickfix list by default, so `QuickFixCmdPost` never fires for them) — it
hooks every task template directly via `overseer.add_template_hook` and
no-ops if overseer isn't installed. Both emit the same `"BuildFailed"` event,
so wiring in either or both is safe.

## Combinators

`require("animfx.combinators")` composes effects — each takes effect
function(s) and returns a new one, so they nest freely.

```lua
local c = require("animfx.combinators")

c.chain(a, b, c)          -- run in sequence, same data
c.delay(ms, effect)       -- defer by ms
c.debounce(ms, effect)    -- trailing edge: one call after a burst, last data
c.throttle(ms, effect)    -- leading edge: fire, then ignore for ms
c.only_if(pred, effect)   -- run only when pred(data) is truthy
c.once(effect)            -- run at most once
```

Debounce is the clean fix for rapid re-triggers — e.g. spamming a Harpoon-add
keymap flashes once when the dust settles, not once per press:

```lua
animfx.on("HarpoonAdd", c.debounce(200, c.chain(
  fx.line_flash({ hl = "IncSearch" }),
  fx.notify_toast({ title = "Harpoon" })
)))
```

## Example: Harpoon add

```lua
local animfx = require("animfx")
local fx = require("animfx.effects")

animfx.on("HarpoonAdd", fx.line_flash({ hl = "IncSearch" }))
animfx.on("HarpoonAdd", fx.notify_toast({ title = "Harpoon" }))

vim.keymap.set("n", "<leader>H", function()
  require("harpoon"):list():add()
  animfx.emit("HarpoonAdd", { msg = "Added " .. vim.fn.expand("%:t") })
end, { desc = "Harpoon File" })
```

Both effects fire on one emit — the line flashes *and* a toast appears.

## Writing your own effect

An effect is just `function(data)`. Wrap it in a constructor if it takes config:

```lua
local function shake(opts)
  local times = (opts or {}).times or 3
  return function(data)
    -- ... use data, run your animation ...
  end
end

animfx.on("BuildFailed", shake({ times = 5 }))
animfx.emit("BuildFailed", { win = 0 })
```

## Cross-layer events (AeroSpace, tmux, …)

Neovim already speaks RPC over a socket, so external tools can emit into a
running instance — turning animfx into a sink for window-manager / multiplexer
events. Have Neovim listen:

```lua
require("animfx.remote").serve({ address = "/tmp/nvim-animfx.sock" })
require("animfx").on("WorkspaceSwitch",
  require("animfx.effects").cursor_beacon({ hl = "Search" }))
```

Then any process fires an event over the socket. Data travels as a JSON string
decoded Lua-side, so there's no Vim dict syntax to escape:

```sh
nvim --server /tmp/nvim-animfx.sock --remote-expr \
  "luaeval('require(\"animfx\").emit(_A[1], vim.json.decode(_A[2]))', \
           ['WorkspaceSwitch', '{\"workspace\": \"3\"}'])"
```

Ready-to-wire hook scripts are in [`examples/`](examples/) for AeroSpace
(`on-focus-changed`) and tmux (`pane-focus-in`). `remote.remote_expr(event, data)`
builds the expression string for you.

For the design of richer window-manager / OS-automation producers (AeroSpace,
Hammerspoon), see
[docs/cross-layer-integrations.md](docs/cross-layer-integrations.md) — a concept
doc, not yet a shipped/tested feature.

## Remote effects (Neovim → Hammerspoon, …)

The reverse direction from the above: `require("animfx.remote_effects")`
provides effects that shell out to another OS process instead of mutating
Neovim's own UI — useful for animating something Neovim itself can't reach,
like the real OS window running a tiled terminal.

```lua
require("animfx").on("BuildFailed",
  require("animfx.remote_effects").hammerspoon_wiggle())
```

`hammerspoon_wiggle(opts)` fires `hs -c "spoon.WindowMgmt:wiggleFocusedWindow()"`
(fire-and-forget; silently no-ops if Hammerspoon or the `hs` CLI isn't
present) — see the "Hammerspoon wiggle on build failure" recipe above.

## Health & tests

```vim
:checkhealth animfx
:help animfx      " full reference (doc/animfx.txt)
```

```sh
make test        # headless suite (nvim -l tests/run.lua); non-zero on failure
make fmt         # stylua format
make lint        # luacheck
```

CI runs the suite on Neovim stable and nightly. The suite enforces
spec-to-test traceability — every test is tagged with the `openspec/` requirement
it covers, and the build fails on any uncovered requirement. See
[CONTRIBUTING.md](CONTRIBUTING.md).

## Design notes

- **Multiple effects / ordering** — allowed, run in registration order (autocmd
  order). No dedup; register the same effect twice and it runs twice.
- **Error isolation** — each effect is `pcall`-wrapped in `on()`; a throw is
  reported via `vim.notify` and the remaining effects still run.
- **Cleanup** — `line_flash` uses one shared, idempotent namespace and deletes
  each flash's own extmark by id, so rapid re-triggers don't clear each other
  and nothing leaks.

## Deferred

- `pulsar.nvim` pulse reimplemented as an effect constructor for visual
  consistency once the cursor-jump indicator lands.
- Cross-layer events (AeroSpace workspace switch, tmux pane focus) piped into
  `animfx.emit()` over RPC/socket.
