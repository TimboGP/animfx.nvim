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
- AND the error from the first is surfaced to the user

### Requirement: Unregister an effect
The system SHALL remove a registration via `animfx.off(id)` using the id
returned from `animfx.on`.

#### Scenario: Removed effect stops firing
- GIVEN an effect registered for `"E"` with id `id`
- WHEN `animfx.off(id)` is called and `"E"` is emitted
- THEN the effect does not run

### Requirement: Clear registrations
The system SHALL provide `animfx.clear(event)` that removes all effects
registered for `event`, or, when called with no argument, all animfx
registrations. It affects only registrations made through animfx, not other
`User` autocmds.

#### Scenario: Clear one event
- GIVEN two effects registered for `"E"` and one for `"F"`
- WHEN `animfx.clear("E")` is called
- THEN `animfx.list()` no longer lists `"E"`
- AND `"F"` remains registered

#### Scenario: Clear everything
- GIVEN effects registered for several events
- WHEN `animfx.clear()` is called with no argument
- THEN `animfx.list()` is empty

### Requirement: Declarative setup
The system SHALL provide `animfx.setup(config)` that registers effects
declaratively: `config` maps event names to an effect function or a list of
effect functions. Re-calling `setup` SHALL replace the registrations it made on
a previous call, without affecting effects registered directly via `on()`.

#### Scenario: Setup registers effects
- GIVEN `animfx.setup({ E = fn })`
- WHEN `"E"` is emitted
- THEN `fn` runs

#### Scenario: Setup accepts a single effect or a list
- GIVEN `animfx.setup({ E = { a, b } })`
- WHEN `"E"` is emitted
- THEN both `a` and `b` run

#### Scenario: Re-running setup replaces only its own registrations
- GIVEN an effect registered for `"F"` via `on()`, then two `setup()` calls
- WHEN the second `setup` runs
- THEN the first setup's effects are gone
- AND the `on()` registration for `"F"` remains

### Requirement: Global toggle and macro guard
The system SHALL provide `animfx.disable()` and `animfx.enable()` to turn all
animfx effects off and back on, and `animfx.is_enabled()` to report the toggle
state. While disabled, emitting an event SHALL still fire (so other `User`
listeners and introspection are unaffected) but animfx effects SHALL NOT run.
By default animfx effects SHALL also be skipped while a macro is being recorded
or replayed; setting `vim.g.animfx_animate_in_macros` truthy opts back in.

#### Scenario: Disable suppresses effects
- GIVEN an effect registered for `"E"`
- WHEN `animfx.disable()` is called and `"E"` is emitted
- THEN the effect does not run
- AND `animfx.is_enabled()` is false

#### Scenario: Enable restores effects
- GIVEN animfx was disabled
- WHEN `animfx.enable()` is called and `"E"` is emitted
- THEN the effect runs

#### Scenario: Effects are skipped during a macro
- GIVEN an effect registered for `"E"` and a macro being recorded
- WHEN `"E"` is emitted
- THEN the effect does not run
- AND setting `vim.g.animfx_animate_in_macros` truthy lets it run

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
