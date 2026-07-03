# Remote Specification

## Purpose

Let external processes emit into a running Neovim over its RPC socket, turning
animfx into a sink for cross-layer events (an AeroSpace workspace switch, a tmux
pane focus) without inventing new plumbing.

## Requirements

### Requirement: Serve a socket address
The system SHALL provide `animfx.remote.serve(opts)` that ensures Neovim is
listening on a server address and returns it. When `opts.address` is given it
SHALL start (or reuse) that named socket; otherwise it SHALL reuse the existing
`v:servername` if set, or start a new server.

#### Scenario: Returns a listening address
- GIVEN a call to `serve({ address = path })`
- WHEN it completes
- THEN it returns a non-empty address string that external tools can target

### Requirement: Build a remote emit expression
The system SHALL provide `animfx.remote.remote_expr(event, data)` returning the
`luaeval` expression string for an external `nvim --server ... --remote-expr`
call to emit `event`, with `data` JSON-encoded and decoded on the Lua side so
callers never write Vim dict syntax.

#### Scenario: Expression carries event and JSON data
- GIVEN `remote_expr("WorkspaceSwitch", { workspace = "3" })`
- WHEN the returned string is inspected
- THEN it contains the event name `WorkspaceSwitch`
- AND it JSON-decodes the payload (references `json.decode`)

### Requirement: External emit delivers to registered effects
The system SHALL allow a separate process to emit an event, with payload, into a
serving Neovim over the socket, such that the payload reaches effects registered
for that event.

#### Scenario: Emit over the socket reaches the effect
- GIVEN a Neovim serving on a socket with an effect registered for
  `"WorkspaceSwitch"`
- WHEN another process runs the remote emit for `"WorkspaceSwitch"` with
  `{ workspace = "ws3" }`
- THEN the registered effect runs with `data.workspace == "ws3"`

### Requirement: Graceful when no socket is present
The provided example hook scripts SHALL exit without error when the expected
socket does not exist (Neovim not running or not serving).

#### Scenario: No serving Neovim
- GIVEN the socket path does not exist
- WHEN an example hook script runs
- THEN it exits successfully without attempting the emit
