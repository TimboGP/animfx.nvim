# Cross-layer integrations (concept)

Status: **design / not yet shipped.** This documents how window-manager and
OS-automation layers can drive animfx effects, building on the existing
`animfx.remote` consumer. It is a concept doc, not a spec — nothing here is
tested or guaranteed yet.

## Architecture

animfx already has the **consumer** half: `animfx.remote.serve()` makes a
running Neovim listen on an RPC socket, and any process can emit into it:

```
external event  ──►  producer  ──►  nvim --server <sock> --remote-expr  ──►  animfx.emit(...)  ──►  effects
 (workspace       (WM/OS glue)        (one line of shell)                     (registry)          (flash, beacon,
  switch, app                                                                                       toast, ...)
  focus, ...)
```

The producers live in the user's WM / automation config, **not** in the plugin.
animfx's job is only to (a) listen and (b) ship example producers + a helper so
the wiring is copy-paste, not archaeology. `remote.remote_expr(event, data)`
already builds the `luaeval` string; data travels as JSON decoded Lua-side.

Neovim side, once:

```lua
require("animfx.remote").serve({ address = "/tmp/nvim-animfx.sock" })
require("animfx").on("WorkspaceSwitch",
  require("animfx.effects").cursor_beacon({ hl = "Search" }))
```

## Shared design decisions (both integrations)

These are the questions any cross-layer producer must answer; solving them once
in a helper is the main value animfx can add here.

1. **Socket discovery.** Which Neovim receives the event? Options:
   - *Well-known path* (simplest): `serve({ address = "/tmp/nvim-animfx.sock" })`
     and producers target that path. One "primary" Neovim. Good default.
   - *Per-instance*: each Neovim serves a unique socket; a producer broadcasts
     to all sockets matching a glob (`/tmp/nvim-animfx-*.sock`). Needed if
     several Neovims should all react.
   - *Focused-only*: the producer checks the frontmost app/window and only
     emits if Neovim is focused (avoids animating a background editor).
2. **Cost.** Each emit spawns `nvim --server`. That's cheap (~tens of ms) but
   not free — debounce high-frequency events (mouse-follow focus, rapid
   workspace flips). Debounce at the producer, or register the effect through
   `animfx.combinators.debounce` on the consumer.
3. **Failure is silent by design.** No socket (Neovim not running) → the
   producer exits 0 and does nothing. The example scripts already do this.
4. **Security.** Unix domain socket, local user only. Don't expose over TCP.

A future `animfx-emit` shell wrapper (or a documented function) could collapse
the verbose `--remote-expr` incantation to `animfx-emit WorkspaceSwitch '{"n":3}'`
— the single biggest ergonomic win for producers.

## AeroSpace

[AeroSpace](https://github.com/nikitabobko/AeroSpace) is a macOS tiling WM
configured in `~/.aerospace.toml`. It runs shell commands on lifecycle hooks —
`on-focus-changed`, `exec-on-workspace-change`, `on-window-detected` — which is
exactly the producer seam.

**Events worth emitting**

| AeroSpace hook | animfx event | payload | effect idea |
|---|---|---|---|
| `exec-on-workspace-change` | `WorkspaceSwitch` | `{ workspace, prev }` | `cursor_beacon` to reorient after the jump |
| `on-focus-changed` | `WindowFocus` | `{ app }` | `line_flash` / `notify_toast` when Neovim regains focus |
| `on-window-detected` | `WindowOpen` | `{ app }` | subtle badge |

**Wiring** — `~/.aerospace.toml`:

```toml
exec-on-workspace-change = ['/bin/bash', '-c',
  '/path/to/examples/aerospace-on-workspace-change.sh']
```

The producer script (`examples/aerospace-on-workspace-change.sh`, already in the
repo) reads `$AEROSPACE_FOCUSED_WORKSPACE` and emits `WorkspaceSwitch`. The
concept extends it to also pass the previous workspace and to guard on Neovim
being frontmost.

**Limits.** AeroSpace only exposes the hooks it defines — workspace/window/focus.
For anything else (battery, display wake, app-specific triggers) you need a more
general OS watcher — which is where Hammerspoon comes in.

## Hammerspoon

[Hammerspoon](https://www.hammerspoon.org/) is a macOS automation tool scripted
in Lua, with watchers for a huge surface: application activation, window
create/move/focus, screen (display) changes, caffeinate/wake, battery, wifi,
USB, and arbitrary hotkeys. It's a **general OS-event → animfx bridge** — a
superset of what AeroSpace can source.

Because Hammerspoon is itself Lua, the producer is a watcher callback that shells
out to Neovim (via `hs.task` — non-blocking, preferred over `hs.execute`):

```lua
-- ~/.hammerspoon/init.lua  (see examples/hammerspoon.lua)
local SOCK = "/tmp/nvim-animfx.sock"

local function animfx_emit(event, data)
  local json = hs.json.encode(data or {})
  hs.task.new("/usr/bin/env", nil, {
    "nvim", "--server", SOCK, "--remote-expr",
    ("luaeval('require(\"animfx\").emit(_A[1], vim.json.decode(_A[2]))', ['%s', %q])")
      :format(event, json),
  }):start()
end

-- App focus: flash when you switch INTO the terminal running Neovim.
hs.application.watcher.new(function(name, event)
  if event == hs.application.watcher.activated and name == "WezTerm" then
    animfx_emit("AppFocus", { app = name })
  end
end):start()

-- Display wake: reorient after the screen comes back.
hs.caffeinate.watcher.new(function(ev)
  if ev == hs.caffeinate.watcher.screensDidWake then
    animfx_emit("ScreenWake", {})
  end
end):start()
```

**Events Hammerspoon can source that AeroSpace can't**

| Watcher | animfx event | effect idea |
|---|---|---|
| `hs.application.watcher` (activated) | `AppFocus` | flash on switching into the editor |
| `hs.caffeinate.watcher` (screensDidWake) | `ScreenWake` | `cursor_beacon` to find the cursor again |
| `hs.battery.watcher` (low) | `BatteryLow` | `shake` + `notify_toast` |
| `hs.hotkey` (a chord) | any custom event | anything — manual trigger |
| `hs.screen.watcher` (layout change) | `DisplayChange` | badge |

**Trade-offs.** Hammerspoon is strictly more capable than the AeroSpace hooks
(it can watch nearly anything macOS emits), at the cost of a dependency and Lua
config. The `hs.task` producer is non-blocking, so high-frequency watchers won't
stall Hammerspoon — but still debounce mouse-follow-focus-style firehoses.

## Suggested build order (when these graduate from concept)

1. **`animfx-emit` CLI helper** — one small script; removes the `--remote-expr`
   boilerplate every producer otherwise copies. Unlocks both integrations.
2. **AeroSpace**: promote the existing example to emit prev-workspace + a
   focused-guard; document the `.toml` hooks. Testable via the same
   two-process pattern as the remote suite.
3. **Hammerspoon**: ship `examples/hammerspoon.lua`, document socket discovery.
   Hard to CI (needs macOS + Hammerspoon), so verify manually and keep it in
   examples, not the tested surface.
```
