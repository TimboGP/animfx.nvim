# Tween Specification

## Purpose

Shared progress/setter split for timer-driven animations, extracted from
`animfx.effects` (and ported from hammerspoon-animfx's `tween.lua`) so
effects don't hand-roll progress math inline in their timer callbacks.
`tween.run` turns real elapsed wall-clock time into a normalized `t` in
[0, 1], calls `progressFn(t)` to map that to a value, and hands the value to
`setterFn` to apply.

## Requirements

### Requirement: Elapsed-time progress
The system SHALL provide `tween.run(spec)` that computes progress `t` each
tick from real elapsed wall-clock time (`(now - start) / spec.duration`,
clamped to 1) using a monotonic clock, not an incremented tick counter, so a
delayed or dropped tick changes the tween's visual smoothness but not its
total duration.

#### Scenario: Progress reaches 1 and completes naturally
- GIVEN a tween with a short `duration` and a fast `fps`
- WHEN it is run to completion
- THEN `progressFn` is eventually called with `t = 1`
- AND `onComplete` fires with `cancelled = false`

### Requirement: Completion fires exactly once
The system SHALL call `spec.onComplete(cancelled)` exactly once per
`tween.run`, however the tween ends: reaching `t = 1` naturally
(`cancelled = false`), an explicit `cancel()` (`cancelled = true`), or
`setterFn` returning `false` (`cancelled = true`). Once finished, no further
`progressFn` / `setterFn` calls SHALL occur, and calling `cancel()` again
SHALL be a no-op.

#### Scenario: setterFn returning false cancels early
- GIVEN a tween whose `setterFn` returns `false` on some tick
- WHEN that tick runs
- THEN the tween stops immediately
- AND `onComplete` is called with `cancelled = true`

#### Scenario: cancel after natural completion is a no-op
- GIVEN a tween that has already finished naturally
- WHEN `cancel()` is called afterwards
- THEN `onComplete` is not called again

### Requirement: Cancellation stops the timer
The system SHALL provide `cancel()` on the handle returned by `tween.run`
that stops and releases the underlying timer immediately and marks the
tween finished, so `isRunning()` reports `false` from that point on.

#### Scenario: Cancel stops a running tween
- GIVEN a running tween
- WHEN `cancel()` is called
- THEN `isRunning()` returns `false`
- AND no further ticks occur

### Requirement: Timers are cancelled on exit
The system SHALL track every timer created by `tween.run` (alongside
`animfx.effects`'s hand-rolled animation timers, via the same shared table)
and cancel any still running when `VimLeavePre` fires.

#### Scenario: A live tween is cancelled on exit
- GIVEN a running tween with a long duration
- WHEN `VimLeavePre` fires
- THEN its timer is stopped and closed
- AND no tracked timers remain
