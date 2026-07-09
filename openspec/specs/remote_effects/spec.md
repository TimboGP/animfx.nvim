# Remote Effects Specification

## Purpose

Effects that shell out to another OS process — the outbound counterpart to
`animfx.remote` (which only lets external processes call *into* Neovim). Kept
in their own module/capability, separate from `animfx.effects` (exclusively
in-process UI mutation): a subprocess call has a fundamentally different
failure mode (missing binary, unreachable peer, hundreds of milliseconds of
spawn latency) than an extmark or floating window.

## Requirements

### Requirement: Hammerspoon window wiggle
The system SHALL provide `animfx.remote_effects.hammerspoon_wiggle(opts)`
returning a `function(data)` effect that, when called, spawns the `hs` CLI to
invoke `spoon.WindowMgmt:wiggleFocusedWindow()` — triggering a wiggle on the
OS window that currently has focus via a `hammerspoon-window-mgmt` Spoon. The
spawn SHALL be fire-and-forget (`detach = true`, no result awaited) and SHALL
NOT surface an error to the user when Hammerspoon is not running or the `hs`
CLI is not installed.

#### Scenario: Spawns hs with the expected argv
- GIVEN `hammerspoon_wiggle()` as an effect
- WHEN it is called
- THEN it spawns a job with argv `{ "hs", "-c",
  "spoon.WindowMgmt:wiggleFocusedWindow()" }`
- AND the job is detached

#### Scenario: Missing `hs` binary does not raise
- GIVEN the `hs` executable is not on `$PATH`
- WHEN `hammerspoon_wiggle()`'s effect is called
- THEN it does not raise an error
