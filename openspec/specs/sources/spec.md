# Sources Specification

## Purpose

Curated adapters that emit animfx events from common Neovim happenings, so
effects work without wiring `emit` by hand.

Each source is **specific and opt-in** — this is deliberately NOT a general
autocmd wrapper (see the project's non-goals). A source translates one
well-defined Neovim event into one animfx event carrying the relevant data;
it does not expose arbitrary autocmds as animfx events.

## Requirements

### Requirement: Yank source
The system SHALL provide `animfx.sources.on_yank(opts)` that, on
`TextYankPost`, emits an animfx event (default name `"Yank"`, overridable via
`opts.event`) carrying the yanked buffer and range as
`{ buf, start_row, start_col, end_row, end_col }` (0-indexed, end-exclusive),
so it composes directly with `animfx.effects.range_flash`. Re-calling it SHALL
replace the previous yank autocmd rather than stacking.

#### Scenario: Yank emits the range
- GIVEN `on_yank({ event = "Yank" })` is active
- WHEN text is yanked
- THEN a `"Yank"` event fires
- AND its data carries the buffer and the yanked range

#### Scenario: Composes with range_flash
- GIVEN `on_yank()` and `range_flash` registered for `"Yank"`
- WHEN text is yanked
- THEN the yanked range is highlighted
