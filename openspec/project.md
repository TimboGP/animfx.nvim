# animfx.nvim

## Purpose

A small Neovim plugin that decouples *"something happened"* from *"what visual
effect plays."* Call sites emit named events; effects register against event
names independently. Backend-agnostic — effects can be hand-rolled or delegate
to existing animation engines (nvim-notify, pulsar.nvim, mini.animate).

It is deliberately narrow: register effect ↔ event, emit event, run effect(s).
It is **not** a general autocmd wrapper and does not replace mini.animate,
smear-cursor.nvim, or pulsar.nvim for the built-in actions they already cover.

## Tech stack

- Language: Lua (LuaJIT), targeting Neovim stable and nightly (0.10+).
- Transport: rides Neovim's built-in `User` autocmd
  (`nvim_create_autocmd` / `nvim_exec_autocmds`), so registrations stay
  introspectable via `:au User` and interoperate with other `User` listeners.
- No runtime dependencies. nvim-notify is optional (graceful fallback).

## Conventions

- Effects are `function(data)`; constructors take `opts` and return one.
- Effect execution is `pcall`-isolated: one failing effect never blocks others.
- Modules: `animfx` (registry), `animfx.effects`, `animfx.combinators`,
  `animfx.remote`, `animfx.health`.

## Testing

- Headless suite in `tests/run.lua`, run with `make test` (`nvim -l`), no
  plenary. CI runs it on Neovim stable and nightly.
- `stylua` + `luacheck` for local formatting and linting.

## Spec organization

These specs were written retroactively to document v0.1.0's shipped behavior.
Capabilities map to modules: `registry`, `effects`, `combinators`,
`introspection`, `remote`.
