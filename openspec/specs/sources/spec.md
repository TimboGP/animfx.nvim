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

### Requirement: Diagnostic source
The system SHALL provide `animfx.sources.on_diagnostic(opts)` that, on
`DiagnosticChanged`, emits an animfx event (default `"Diagnostic"`, overridable
via `opts.event`) carrying `{ buf, count }` where `count` is the number of
diagnostics for the buffer. Re-calling it SHALL replace the previous autocmd.

#### Scenario: Diagnostics change emits the count
- GIVEN `on_diagnostic()` is active
- WHEN diagnostics are set on a buffer
- THEN a `"Diagnostic"` event fires
- AND its data carries the buffer and diagnostic count

### Requirement: Search source
The system SHALL provide `animfx.sources.on_search(opts)` that maps the search
navigation keys (default `n` and `N`, overridable via `opts.keys`) so each
performs its normal motion and then emits an animfx event (default `"Search"`,
overridable via `opts.event`) carrying `{ buf, line, col, pattern }` for the
landing position. It respects a preceding count.

#### Scenario: Navigating emits the landing position
- GIVEN `on_search()` is active and a search pattern is set
- WHEN `n` is pressed
- THEN the cursor moves to the next match
- AND a `"Search"` event fires carrying that position and the pattern
