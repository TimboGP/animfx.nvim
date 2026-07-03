# Introspection Specification

## Purpose

Visibility into the registry: what is registered, what has recently fired, and
commands to inspect and exercise effects without editing configuration.

## Requirements

### Requirement: List registrations
The system SHALL provide `animfx.list()` returning a map of event name to the
number of effects registered for it, read back from the live `User` autocmds in
animfx's augroup.

#### Scenario: Counts effects per event
- GIVEN two effects registered for `"E"`
- WHEN `animfx.list()` is called
- THEN the result maps `"E"` to `2`

### Requirement: Emit history ring buffer
The system SHALL record recent emits in a bounded ring buffer (at most 100
entries), each entry capturing the event name and a timestamp, exposed oldest
first via `animfx.history()`.

#### Scenario: An emit is recorded
- GIVEN a fresh session
- WHEN `animfx.emit("E", {})` is called
- THEN `animfx.history()` contains an entry whose event is `"E"`

#### Scenario: History stays bounded
- GIVEN more than 100 emits have occurred
- WHEN `animfx.history()` is read
- THEN it contains at most 100 entries

### Requirement: Inspection and emit commands
The system SHALL register user commands `:AnimfxList` (show events and effect
counts), `:AnimfxEmit <Event>` (fire an event by name with an empty payload,
completing on registered events), and `:AnimfxHistory` (show recent emits with
timestamps). Command registration SHALL be guarded so sourcing twice is
harmless.

#### Scenario: Emit command fires an event
- GIVEN an effect registered for `"E"`
- WHEN `:AnimfxEmit E` is run
- THEN the effect runs

#### Scenario: Emit command completes registered events
- GIVEN events registered in the registry
- WHEN completion is requested for `:AnimfxEmit`
- THEN the registered event names matching the typed prefix are offered

### Requirement: Health check
The system SHALL provide `:checkhealth animfx` reporting that the core is loaded
and whether nvim-notify is available (affecting whether `notify_toast`
animates).

#### Scenario: Reports notify availability
- GIVEN nvim-notify is not installed
- WHEN `:checkhealth animfx` runs
- THEN it reports a warning that `notify_toast` falls back to `vim.notify`
