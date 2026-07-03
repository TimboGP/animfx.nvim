-- Neovim runs LuaJIT and injects the `vim` global.
std = "luajit"
globals = { "vim" }
max_line_length = 120

-- Effect functions intentionally accept a `data` arg they may not use.
unused_args = false

-- tests/run.lua stashes state on _G to survive across do-blocks.
files["tests/run.lua"] = {
  globals = { "_G" },
}
