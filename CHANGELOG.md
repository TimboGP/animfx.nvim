# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- OpenSpec specs under `openspec/` documenting v0.1.0 behavior across five
  capabilities (registry, effects, combinators, introspection, remote).
- Spec-to-test traceability: every test is tagged with the requirement it
  covers, and a coverage gate fails the build on dangling references or
  uncovered requirements.
- `CONTRIBUTING.md` describing the spec-driven loop and traceability rule.
- Backend-integration suite (`make test-integration`) that installs a real
  nvim-notify and verifies the adapters, the remote bridge end-to-end, and the
  health check.
- This changelog and a release workflow that cuts a GitHub release from the
  matching changelog section on tag push.
- lua-language-server type-checking of the LuaCATS annotations (`.luarc.json`,
  `make typecheck`, CI job); `delegate`'s spec is now a typed
  `animfx.DelegateSpec` class.
- `animfx.clear(event)` removes all effects for an event, or every animfx
  registration when called with no argument.
- Vim help documentation (`:help animfx`, `doc/animfx.txt`).

### Changed
- The unit suite now runs with `nvim --clean` so results don't depend on the
  user's config.

### Fixed
- `line_flash`/`sign_flash` now clamp an out-of-range `data.line` into the
  buffer instead of raising (e.g. when `data.buf` is set but `data.line` falls
  back to a longer buffer's cursor line).
- Concurrent `line_flash({ fade = true })` invocations no longer share global
  highlight groups, so overlapping fades with different colors don't overwrite
  one another mid-animation.
- `delegate` now warns once (via `vim.notify`) when the module loads but the
  `fn` path isn't callable, instead of silently doing nothing.
- Animated effects (`line_flash` fade, `cursor_beacon`) now cancel their
  repeating timers on `VimLeavePre`, so none leak or fire a callback into a
  closing Neovim.

## [0.1.0] - 2026-07-03

### Added
- Core registry (`animfx`): `on` / `emit` / `off`, built on Neovim's `User`
  autocmd. Effects are `pcall`-isolated; multiple effects per event run in
  registration order. `emit(event, data, { schedule = true })` defers effects
  to the next tick.
- Effects (`animfx.effects`): `line_flash` (with `fade`), `sign_flash`,
  `cursor_beacon` (dependency-free pulse), `notify_toast` (nvim-notify with
  `vim.notify` fallback), and `delegate` (wrap any plugin's function as an
  effect with graceful fallback).
- Combinators (`animfx.combinators`): `chain`, `delay`, `debounce`, `throttle`,
  `only_if`, `once`.
- Introspection: `list()`, `history()` ring buffer, and the `:AnimfxList`,
  `:AnimfxEmit`, `:AnimfxHistory` commands. `:checkhealth animfx`.
- Cross-layer bridge (`animfx.remote`): `serve()` / `remote_expr()` plus
  ready-to-wire AeroSpace and tmux example hooks in `examples/`.
- Headless test suite and CI on Neovim stable + nightly; stylua / luacheck
  config.

[Unreleased]: https://github.com/TimboGP/animfx.nvim/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/TimboGP/animfx.nvim/releases/tag/v0.1.0
