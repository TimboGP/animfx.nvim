# Combinators Specification

## Purpose

Composition helpers in `animfx.combinators`. Each takes effect function(s) — the
same `function(data)` shape the registry expects — and returns a new one, so
they nest freely (e.g. `debounce(200, chain(a, b))`).

## Requirements

### Requirement: Chain effects in sequence
The system SHALL provide `chain(...)` that runs the given effects in order,
passing the same `data` to each.

#### Scenario: Effects run in order with the same data
- GIVEN `chain(A, B)`
- WHEN the result is called with `data`
- THEN `A` runs with `data`, then `B` runs with the same `data`

### Requirement: Delay an effect
The system SHALL provide `delay(ms, effect)` that defers the effect by `ms`
milliseconds.

#### Scenario: Effect fires after the delay
- GIVEN `delay(20, effect)`
- WHEN the result is called
- THEN `effect` runs approximately 20 ms later

### Requirement: Debounce a burst
The system SHALL provide `debounce(ms, effect)` with trailing-edge semantics:
a burst of calls collapses into a single invocation that fires `ms` after the
last call, using that last call's `data`.

#### Scenario: Burst collapses to one call with last data
- GIVEN `debounce(20, effect)`
- WHEN it is called three times in quick succession with data `1`, `2`, `3`
- THEN `effect` runs exactly once
- AND it receives the data from the third call

### Requirement: Throttle calls
The system SHALL provide `throttle(ms, effect)` with leading-edge semantics:
the first call fires immediately, then further calls are ignored for `ms`.

#### Scenario: Only the leading call fires within the window
- GIVEN `throttle(40, effect)`
- WHEN it is called three times immediately
- THEN `effect` runs exactly once
- AND calling again after the window fires it a second time

### Requirement: Conditional effect
The system SHALL provide `only_if(pred, effect)` that runs `effect` only when
`pred(data)` is truthy.

#### Scenario: Gate blocks and allows
- GIVEN `only_if(pred, effect)`
- WHEN called with data for which `pred` is false, then data for which it is true
- THEN `effect` runs only once — for the second call

### Requirement: Run once
The system SHALL provide `once(effect)` that runs `effect` at most once;
subsequent calls are no-ops.

#### Scenario: Second call is a no-op
- GIVEN `once(effect)`
- WHEN it is called twice
- THEN `effect` runs exactly once
