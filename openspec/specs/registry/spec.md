# Registry Specification

## Purpose

The core event↔effect registry: register effects against named events, emit
events, and run the registered effects. Built on Neovim's `User` autocmd so the
mapping is introspectable and interoperable with other `User` listeners.

## Requirements

### Requirement: Register an effect against an event
The system SHALL register an effect function against an event name via
`animfx.on(event, effect_fn)`, creating a `User` autocmd whose pattern is the
event name, and SHALL return an identifier that can later remove that
registration.

#### Scenario: Effect runs on matching emit
- GIVEN an effect registered with `animfx.on("HarpoonAdd", fn)`
- WHEN `animfx.emit("HarpoonAdd", data)` is called
- THEN `fn` is invoked with `data`

#### Scenario: Invalid arguments are rejected
- GIVEN a call to `animfx.on`
- WHEN `event` is not a string or `effect_fn` is not a function
- THEN the call raises an assertion error

### Requirement: Emit runs every registered effect
The system SHALL, on `animfx.emit(event, data)`, run every effect registered
for that event and pass `data` through unchanged to each.

#### Scenario: Payload is delivered
- GIVEN an effect registered for `"E"`
- WHEN `animfx.emit("E", { value = 42 })` is called
- THEN the effect receives a table whose `value` is `42`

#### Scenario: Emit with no data yields a table
- GIVEN an effect registered for `"E"`
- WHEN `animfx.emit("E")` is called with no data argument
- THEN the effect receives an empty table, never `nil`

### Requirement: Multiple effects run in registration order
The system SHALL support multiple effects registered against the same event and
SHALL run them in the order they were registered. No deduplication is performed.

#### Scenario: Two effects fire in order
- GIVEN effects `A` then `B` registered for `"E"`
- WHEN `"E"` is emitted
- THEN `A` runs before `B`

### Requirement: Error isolation between effects
The system MUST isolate effect failures: an effect that raises an error SHALL
NOT prevent other effects on the same event from running, and the error SHALL
be surfaced to the user.

#### Scenario: A throwing effect does not block the next
- GIVEN a throwing effect and a second effect both registered for `"E"`
- WHEN `"E"` is emitted
- THEN the second effect still runs
- AND the error from the first is reported via `vim.notify`

### Requirement: Unregister an effect
The system SHALL remove a registration via `animfx.off(id)` using the id
returned from `animfx.on`.

#### Scenario: Removed effect stops firing
- GIVEN an effect registered for `"E"` with id `id`
- WHEN `animfx.off(id)` is called and `"E"` is emitted
- THEN the effect does not run

### Requirement: Synchronous by default, optionally scheduled
The system SHALL run effects synchronously by default so callers observe them
before `emit` returns, and SHALL defer them to the next event-loop tick when
`emit` is called with `{ schedule = true }`.

#### Scenario: Default emit is synchronous
- GIVEN an effect registered for `"E"`
- WHEN `animfx.emit("E", {})` is called
- THEN the effect has run by the time `emit` returns

#### Scenario: Scheduled emit defers
- GIVEN an effect registered for `"E"`
- WHEN `animfx.emit("E", {}, { schedule = true })` is called
- THEN the effect has not run when `emit` returns
- AND it runs on a subsequent tick

### Requirement: Interoperate with User autocmds
The system SHALL emit through `nvim_exec_autocmds("User", ...)` so that the
registry is introspectable via `:au User` and any other `User` listener for the
same pattern also receives the event.

#### Scenario: External User listener receives the emit
- GIVEN a plain `nvim_create_autocmd("User", { pattern = "E" })` listener
- WHEN `animfx.emit("E", {})` is called
- THEN that external listener also fires
