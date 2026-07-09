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

### Requirement: Harpoon source
The system SHALL provide `animfx.sources.on_harpoon(opts)` that hooks
harpoon.nvim's (v2) `ADD` extension and emits an animfx event (default
`"HarpoonAdd"`, overridable via `opts.event`) carrying `{ buf, value, idx }`
for the added item. When harpoon is not installed it SHALL no-op without error.

#### Scenario: Adding a file emits the event
- GIVEN harpoon is installed and `on_harpoon()` is active
- WHEN a file is added to a harpoon list
- THEN a `"HarpoonAdd"` event fires
- AND its data carries the added item's value

#### Scenario: No harpoon is a safe no-op
- GIVEN harpoon is not installed
- WHEN `on_harpoon()` is called
- THEN it does not raise

### Requirement: Build-failure source
The system SHALL provide `animfx.sources.on_build_failure(opts)` that, on
`QuickFixCmdPost` for any quickfix-populating command whose name contains
"make" (`:make`, `:lmake`, and build/test-runner plugins built on top of
them), emits an animfx event (default `"BuildFailed"`, overridable via
`opts.event`) carrying `{ count }` — the number of entries in the quickfix
list the command just populated. When that list is empty (the build
succeeded) it SHALL NOT emit. Re-calling it SHALL replace the previous
autocmd rather than stacking.

#### Scenario: Failed build emits with the error count
- GIVEN `on_build_failure()` is active
- WHEN a `:make`-style command populates the quickfix list with one or more
  entries
- THEN a `"BuildFailed"` event fires
- AND its data carries the number of quickfix entries

#### Scenario: Successful build does not emit
- GIVEN `on_build_failure()` is active
- WHEN a `:make`-style command completes with an empty quickfix list
- THEN no `"BuildFailed"` event fires
