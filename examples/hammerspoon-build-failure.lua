-- Wiggle the focused OS window (e.g. a tiled terminal) when a synchronous
-- :make-style build/test run fails. CONCEPT — verify manually; requires
-- macOS, Hammerspoon running, and hammerspoon-window-mgmt's
-- `spoon.WindowMgmt:wiggleFocusedWindow()` (see that repo's WISHLIST.md).
--
-- Drop this in your Neovim config after animfx loads.

require("animfx.sources").on_build_failure() -- emits "BuildFailed" with { count }

require("animfx").on(
  "BuildFailed",
  require("animfx.combinators").debounce(300, require("animfx.remote_effects").hammerspoon_wiggle())
)
