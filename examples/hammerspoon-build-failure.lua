-- Wiggle the focused OS window (e.g. a tiled terminal) when a build/test run
-- fails — either a synchronous :make or an overseer.nvim task. CONCEPT —
-- verify manually; requires macOS, Hammerspoon running, and
-- hammerspoon-window-mgmt's `spoon.WindowMgmt:wiggleFocusedWindow()` (see
-- that repo's WISHLIST.md).
--
-- Drop this in your Neovim config after animfx loads.

require("animfx.sources").on_build_failure() -- emits "BuildFailed" with { count } on :make
require("animfx.sources").on_overseer_failure() -- emits "BuildFailed" on any failed overseer task; no-ops if overseer isn't installed

require("animfx").on(
  "BuildFailed",
  require("animfx.combinators").debounce(300, require("animfx.remote_effects").hammerspoon_wiggle())
)
