# Effects Specification

## Purpose

Reusable effect constructors in `animfx.effects`. Each takes an `opts` table and
returns a `function(data)` ready to hand to `animfx.on`. Effects are
backend-agnostic: some are hand-rolled, one delegates to arbitrary external
plugins.

## Requirements

### Requirement: Line flash
The system SHALL provide `line_flash(opts)` that highlights a full buffer line
and clears it after `duration` milliseconds (default highlight `IncSearch`,
default duration 150). It SHALL default `data.buf` to the current buffer and
`data.line` to the current cursor line, SHALL no-op safely when the target
buffer is invalid, and SHALL clamp `data.line` into the buffer's line range so
an out-of-range line never raises an error.

#### Scenario: Flash places then clears a highlight
- GIVEN `line_flash({ hl = "IncSearch", duration = 150 })`
- WHEN the effect is called for a valid buffer and line
- THEN an extmark highlight is applied to that line
- AND it is removed after the duration elapses

#### Scenario: Rapid re-triggers do not leak
- GIVEN many flashes fired in quick succession on the same line
- WHEN all their durations have elapsed
- THEN no flash extmarks remain in the buffer

#### Scenario: Out-of-range line is clamped, not an error
- GIVEN a buffer with `data.line` past its last line (e.g. the cursor line of
  another, longer buffer)
- WHEN the effect is called
- THEN it does not raise
- AND a highlight extmark is placed on the buffer's last line

### Requirement: Line flash fade-out
The system SHALL, when `line_flash` is given `fade = true`, step the line
background from the highlight's background toward Normal's over `steps` frames
(default 8) instead of a hard clear, and SHALL fall back to the plain flash when
the highlight has no background color. Each fade invocation SHALL use its own
distinct highlight groups so concurrent fades do not overwrite one another's
colors.

#### Scenario: Fade cleans up after completing
- GIVEN `line_flash({ fade = true, steps = 4, duration = 40 })`
- WHEN the fade completes
- THEN the flash extmark is removed

#### Scenario: Concurrent fades do not share highlight groups
- GIVEN two fades started together on different buffers with different colors
- WHEN a mid-fade frame is sampled
- THEN each buffer's fade extmark references a different highlight group

### Requirement: Sign flash
The system SHALL provide `sign_flash(opts)` that places a sign-column mark
(default text `▐`, highlight `IncSearch`, duration 300) and clears it after the
duration, so the cue is visible even when the target line is scrolled off
screen. It SHALL clamp `data.line` into the buffer's line range so an
out-of-range line never raises an error.

#### Scenario: Sign appears then clears
- GIVEN `sign_flash({ duration = 300 })`
- WHEN the effect is called for a valid buffer and line
- THEN a sign extmark is placed
- AND it is removed after the duration

#### Scenario: Out-of-range line is clamped, not an error
- GIVEN a buffer with `data.line` past its last line
- WHEN the effect is called
- THEN it does not raise
- AND a sign extmark is placed on the buffer's last line

### Requirement: Cursor beacon
The system SHALL provide `cursor_beacon(opts)` that opens a small floating
window at the cursor and fades it out over `steps` frames before closing it,
with no dependency on any external animation plugin.

#### Scenario: Beacon opens then closes
- GIVEN `cursor_beacon({ duration = 220, steps = 10 })`
- WHEN the effect is called
- THEN a floating window relative to the cursor is opened
- AND it is closed after the fade completes

### Requirement: Notify toast
The system SHALL provide `notify_toast(opts)` that shows a message via
nvim-notify with `opts` merged over `{ animate = true }`, using `data.msg`
(default empty) and `data.level` (default `"info"`), and SHALL fall back to
`vim.notify` when nvim-notify is not installed.

#### Scenario: Falls back without nvim-notify
- GIVEN nvim-notify is not available
- WHEN the effect is called with `{ msg = "hi" }`
- THEN the message is shown via `vim.notify` at the mapped level

### Requirement: Delegate to an external backend
The system SHALL provide `delegate(spec)` that requires `spec.module`, resolves
`spec.fn` as a dot-path within it, and calls it with arguments built by
`spec.args(data)` (default `{ data }`). When the module is absent it SHALL call
`spec.fallback(data)` if provided and otherwise no-op. When the module resolves
but the target is not callable (e.g. a mistyped `fn` path), it SHALL warn once
via `vim.notify` rather than silently no-op, so the misconfiguration is
diagnosable.

#### Scenario: Target is called when present
- GIVEN `delegate({ module = "m", fn = "pulse" })` and module `m` is loaded
- WHEN the effect is called with `data`
- THEN `m.pulse` is invoked with `data`

#### Scenario: Fallback runs when module is absent
- GIVEN `delegate({ module = "missing", fallback = fb })`
- WHEN the effect is called
- THEN `fb` is invoked with `data`
- AND no error is raised

#### Scenario: Uncallable target warns once
- GIVEN `delegate({ module = "m", fn = "does_not_exist" })` and module `m` is loaded
- WHEN the effect is called several times
- THEN `vim.notify` is called exactly once with a warning
- AND no error is raised
