# animfx.nvim wishlist

Features discussed and deliberately deferred rather than built. Preserved
here as concrete specs so they can be picked up without re-deriving the
design. (Convention borrowed from the sibling project
[hammerspoon-window-mgmt](https://github.com/TimboGP/hammerspoon-windowmanagement)'s
own `WISHLIST.md`.)

---

## Adopt a shared tween abstraction, learned from building hammerspoon-animfx

Discussed 2026-07-08, right after building
[hammerspoon-animfx](https://github.com/TimboGP/hammerspoon-animfx) — a
sibling animation engine for Hammerspoon, deliberately architected as "the
same idea as animfx.nvim" (an event registry decoupled from effects). A
few things fell out of that port that are worth backporting here:

**1. A real progress/setter split.** Every effect in `effects.lua` today
interleaves progress math and the UI-mutating call inline inside its own
timer callback — e.g. `M.shake` (`effects.lua:731`) computes `step % 2`
and calls `nvim_win_set_config` in the same breath, no shared drivers.
hammerspoon-animfx's `tween.lua` separates these into
`tween.run({ duration, fps, progressFn(t)->value, setterFn(value)->ok,
onComplete(cancelled) })`, and every effect there is a two-line
`progressFn`/`setterFn` pair. Porting the same shape here (as
`lua/animfx/tween.lua`, built on `vim.uv.new_timer` instead of
`hs.timer.doEvery`) would let effects stop hand-rolling their own timer
bookkeeping (`managed_timer()`/`active_timers`, `effects.lua:29-52`) and
make it trivial to add real easing curves later (there currently are
none anywhere in this plugin — `blend()` at `effects.lua:55` only does
linear interpolation).

**2. Elapsed-time-based progress, not step-counting.** `shake` and others
compute progress as `step/steps` (an integer tick counter), which drifts
under system load if the timer's actual interval slips. hammerspoon-animfx's
tween computes `t = (secondsSinceEpoch() - startTime) / duration` every
tick — real elapsed wall-clock time, so a dropped or delayed tick doesn't
change the effect's total duration, just its visual smoothness. `vim.uv`
has an equivalent monotonic clock (`vim.uv.hrtime()`) that could back the
same approach here.

**3. A genuinely continuous shake, not a binary jitter.** `M.shake`
(`effects.lua:731-784`) alternates a floating window between offset `0`
and a fixed `amplitude` a fixed number of times — a workaround for
Neovim not being able to move a *real* window, so it jitters a floating
box instead (see the comment at `effects.lua` right above the function).
That constraint doesn't force a binary jitter though — a tween-based
`progressFn` doing `sin(t) * amplitude * (1 - t)` (a decaying sine, like
hammerspoon-animfx's `wiggle`) could drive the *same* floating window
continuously instead, landing back at `col = 0` smoothly rather than
snapping. Worth trying once (1) exists, since it'd be a drop-in
`setterFn` swap.

None of this is urgent — the plugin works as-is — but if `shake` or a new
effect is touched again, this is the shape to reach for instead of
copying the existing step-counted pattern.

---

## Hook: trigger a Hammerspoon window wiggle from Neovim (e.g. on build failure)

Discussed 2026-07-08, same session as above. This is the **reverse**
direction from [docs/cross-layer-integrations.md](docs/cross-layer-integrations.md)
(2026-07-04): that doc designs Hammerspoon/AeroSpace → Neovim (OS/WM events
driving animfx effects *inside* Neovim, via `animfx.remote.serve()` +
`nvim --server ... --remote-expr`). This entry is Neovim → Hammerspoon
instead — a Neovim-side event driving an animation on a *real OS window*
that Neovim itself has no way to touch. The two are complementary, not
overlapping; a full "Neovim ↔ Hammerspoon" story eventually wants both.

Motivation: visually surface
a failed build/test run by shaking the *actual OS window* running the
terminal/tmux pane — not just an in-editor animation — which matters most
when that terminal is a tiled member of a `hammerspoon-window-mgmt`
workspace (a window an in-editor-only animation can't reach, and which a
naive `hs.window:setFrame` shake would otherwise get fought by that
workspace's resettle watcher — see `hammerspoon-window-mgmt`'s
`workspace.lua`).

The receiving side already covers most of this:
`hammerspoon-animfx`'s `AnimFX:wiggle(window, opts)` is public, and
`hammerspoon-window-mgmt` has its own tiling-aware `j` wiggle hotkey
(`wiggle.lua`) — but that hotkey's logic isn't reachable from outside
Hammerspoon yet. See `hammerspoon-window-mgmt`'s own `WISHLIST.md` entry
("Public, externally-triggerable wiggle entry point") for the small
`wiggleWindow`/`wiggleFocusedWindow` extraction needed there first — this
entry is the Neovim-side half, and depends on that one landing first.

Sketch, once that exists:

```lua
-- lua/animfx/sources.lua: a new adapter, alongside the existing
-- yank/diagnostics/search/harpoon ones. Fires on any non-zero-exit
-- QuickFixCmdPost (covers :make and most build/test runner plugins that
-- populate the quickfix list), debounced via the existing combinators.lua
-- (`M.debounce`) so a flurry of errors doesn't spawn a wiggle per line.
vim.api.nvim_create_autocmd("QuickFixCmdPost", {
  pattern = "*make*",
  callback = function()
    if #vim.fn.getqflist({ nr = "$" }).items == 0 then return end -- no errors, don't shake
    require("animfx").emit("BuildFailed", {})
  end,
})
```

```lua
-- lua/animfx/effects.lua (or a new lua/animfx/remote_effects.lua, to keep
-- the "shells out to another process" effects visually separate from the
-- pure-Neovim ones): fire-and-forget, matching the async style
-- remote.lua already uses elsewhere in this plugin.
local function hammerspoon_wiggle(opts)
  vim.fn.jobstart({ "hs", "-c", "spoon.WindowMgmt:wiggleFocusedWindow()" }, { detach = true })
end
-- exact registration API TBD - mirror however M.shake etc. are registered/looked up
```

Open questions to resolve when this is actually built, not now:

- **Which window gets shaken.** The sketch above shakes whatever has OS
  focus at the moment the build fails, which is only correct if the
  terminal running the build still has focus (true for a synchronous
  `:make`, not necessarily true for an async job that finishes while
  you've since switched windows). A more precise version would need
  Hammerspoon-side window *identification* (e.g. by matching the
  terminal app's bundle ID via `hs.window.filter`), not just
  "whatever's focused" — more moving parts, only worth it if the simple
  version proves unsatisfying in practice.
- **Process-spawn latency.** `vim.fn.jobstart({"hs", "-c", ...})` spawns a
  fresh `hs` CLI process per call; this session's own testing saw
  roughly 200-400ms of connection overhead per invocation, which is fine
  for an occasional "build failed" ping but would feel laggy for
  anything more frequent. If that becomes a problem, a small persistent
  local socket listener in `hammerspoon-animfx` (mirroring the
  `vdisplay-helper` sibling daemon's Unix-socket pattern used by
  `hammerspoon-window-mgmt`) would remove the per-call spawn cost — not
  worth building until the simple version is proven insufficient.
- **Failure/timeout behavior.** If Hammerspoon isn't running, or the `hs`
  CLI isn't installed, `jobstart` should fail silently (or log once, not
  per build) rather than surface an error in Neovim for what's meant to
  be a cosmetic notification.
