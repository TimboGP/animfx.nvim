# Contributing to animfx.nvim

animfx.nvim is spec-driven: behavior is described in `openspec/specs/` before it
is implemented, and every requirement is traceable to a test. This keeps the
specs honest — they describe what the code actually does, enforced by CI.

## Setup

```sh
git clone https://github.com/TimboGP/animfx.nvim
cd animfx.nvim
make test        # headless unit suite (Neovim required)
```

No build step, no Lua package manager. `make test` runs the suite with
`nvim --clean`, so results never depend on your personal config or plugins.

Optional local tooling:

```sh
make fmt         # stylua format
make lint        # luacheck
```

## The spec-driven loop

1. **Describe the behavior first.** Add or change a requirement in
   `openspec/specs/<capability>/spec.md`. Each requirement uses an RFC 2119
   keyword (SHALL / MUST / SHOULD) and has at least one `#### Scenario:` in
   GIVEN-WHEN-THEN form. The capabilities are `registry`, `effects`,
   `combinators`, `introspection`, `remote`, `remote_effects`, `sources`,
   `tween`.

2. **Validate the specs:**

   ```sh
   npx -y @fission-ai/openspec@latest validate --specs --strict
   ```

3. **Implement** in the matching module (`lua/animfx/...`).

4. **Add a traceable test** (see below) and run `make test`.

For larger changes you can drive the loop with the OpenSpec workflow commands
(`/opsx:propose`, `/opsx:apply`, `/opsx:archive`) — see
[OpenSpec tooling](#openspec-tooling).

## Spec-to-test traceability

Every `check()` in `tests/run.lua` is tagged with the requirement it covers,
written **exactly** as the requirement heading appears in the spec, prefixed
with the capability:

```lua
check(
  "registry: Error isolation between effects",     -- spec ref
  "error in one effect is isolated",               -- test description
  reached == true                                  -- assertion
)
```

After the tests run, a coverage gate cross-checks both directions and **fails
the build** on either problem:

- **Dangling reference** — a test (or the integration allowlist) names a
  requirement that doesn't exist in any spec. Usually a typo or a renamed
  requirement; fix the tag.
- **Uncovered requirement** — a requirement that no unit test covers and that
  isn't on the integration allowlist. Add a test, or list it as integration-only.

This means: **adding a requirement without a test breaks CI**, and renaming a
requirement without updating its test breaks CI. The specs stay enforceable.

### Integration-only requirements

Some requirements can't be exercised by the headless unit runner — they need a
real backend plugin, multiple processes, or the `:checkhealth` UI. These are
listed in the `integration_covered` allowlist at the bottom of `tests/run.lua`
and are verified by the integration suite instead:

```sh
make test-integration     # requires git + network
```

It installs a real backend (nvim-notify) into a temp directory and asserts the
adapters actually resolve and call it, drives the cross-process remote bridge
end-to-end, checks `:checkhealth animfx`, and runs an example hook against a
missing socket. If you add an integration-only requirement, add it to the
`integration_covered` allowlist **and** add a matching assertion in
`tests/integration/` so the gate stays green for a real reason, not a forgotten
one.

## OpenSpec tooling

The specs in `openspec/` (and `openspec/config.yaml`) are the committed source
of truth. The OpenSpec **editor integration** — slash commands and skills, e.g.
`.claude/` for Claude Code — is per-contributor and tool-specific, so it is
**not** committed (it's gitignored). Generate it for your editor with:

```sh
npx -y @fission-ai/openspec@latest init --tools <your-tool>
```

`<your-tool>` is e.g. `claude`, `cursor`, `codex`, or `windsurf` — run
`npx -y @fission-ai/openspec@latest init --help` for the full list. This writes
the workflow commands (`/opsx:propose`, `/opsx:apply`, `/opsx:archive`, …) into
your editor's config and leaves `openspec/` untouched.

You don't need this to contribute: the specs are plain Markdown you can edit
directly and validate with `openspec validate --specs --strict`. The tooling
just automates the propose → apply → archive loop.

## Style

- `stylua` for formatting (`stylua.toml`), `luacheck` for linting
  (`.luacheckrc`). Run `make fmt lint` before opening a PR.
- LuaCATS annotations are type-checked with `lua-language-server`
  (`.luarc.json`). CI runs `lua-language-server --check` at Warning level and
  fails on any problem, so keep `---@param` / `---@class` annotations accurate.
  Run `make typecheck` locally if you have luals installed.
- Effects are `function(data)`; constructors take `opts` and return one.
- Effect execution is `pcall`-isolated — never let one effect's failure block
  another.

## Pull requests

- Keep specs, implementation, and tests in the same PR.
- CI must be green: it runs `make test` (with the coverage gate) and the
  backend-integration suite on Neovim stable and nightly.
- Add a note under `## [Unreleased]` in `CHANGELOG.md`.

## Releasing

1. Move the `## [Unreleased]` entries into a new `## [x.y.z] - YYYY-MM-DD`
   section and update the compare/link references at the bottom.
2. Commit, then tag: `git tag -a vX.Y.Z -m "vX.Y.Z" && git push --follow-tags`.
3. The `release` workflow fires on the `v*` tag, extracts that version's
   changelog section, and publishes a GitHub release from it. No manual
   `gh release create` needed.
