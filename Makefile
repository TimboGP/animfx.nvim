.PHONY: test test-integration fmt fmt-check lint typecheck docs

# Headless unit suite (--clean so results don't depend on the user's config).
test:
	nvim --clean -l tests/run.lua

# Backend-integration suite: installs real backends (nvim-notify) and exercises
# the adapters, the remote bridge, and the health check. Requires git + network.
test-integration:
	bash tests/integration/run.sh

# Format in place (requires stylua).
fmt:
	stylua lua/ plugin/ tests/

# Verify formatting without writing (used for local pre-commit).
fmt-check:
	stylua --check lua/ plugin/ tests/

# Static analysis (requires luacheck).
lint:
	luacheck lua/ plugin/

# Type-check LuaCATS annotations (requires lua-language-server on PATH).
typecheck:
	lua-language-server --check . --checklevel=Warning --logpath=.luals-log

# Regenerate help tags from doc/animfx.txt.
docs:
	nvim --clean --headless -c "helptags doc" -c "qa"
