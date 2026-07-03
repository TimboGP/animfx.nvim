.PHONY: test fmt fmt-check lint

# Headless unit suite (--clean so results don't depend on the user's config).
test:
	nvim --clean -l tests/run.lua

# Format in place (requires stylua).
fmt:
	stylua lua/ plugin/ tests/

# Verify formatting without writing (used for local pre-commit).
fmt-check:
	stylua --check lua/ plugin/ tests/

# Static analysis (requires luacheck).
lint:
	luacheck lua/ plugin/
