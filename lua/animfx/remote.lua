--- animfx.remote — let external processes emit into a running Neovim.
---
--- Neovim already speaks RPC over a socket; this just makes it convenient to
--- turn animfx into a sink for cross-layer events (an AeroSpace workspace
--- switch, a tmux pane focus) without inventing new plumbing.
---
--- In your config:
---   require("animfx.remote").serve({ address = "/tmp/nvim-animfx.sock" })
---
--- Then from any shell (see examples/) — data travels as a JSON string,
--- decoded Lua-side, so there's no Vim dict syntax to escape:
---   nvim --server /tmp/nvim-animfx.sock --remote-expr \
---     "luaeval('require(\"animfx\").emit(_A[1], vim.json.decode(_A[2]))', \
---              ['WorkspaceSwitch', '{\"workspace\": \"3\"}'])"
local M = {}

--- Ensure this Neovim is listening on a server address, and return it.
---
--- If a `--listen` address (`v:servername`) already exists it's reused as-is;
--- pass `address` only to force an additional named socket (handy so external
--- tools can hardcode the path).
---@param opts? { address?: string }
---@return string address The server address external tools should target.
function M.serve(opts)
  opts = opts or {}
  if opts.address then
    -- serverstart errors if the address is already listening; treat that as fine.
    local ok, addr = pcall(vim.fn.serverstart, opts.address)
    if ok and addr ~= "" then
      return addr
    end
    return opts.address
  end
  if vim.v.servername ~= nil and vim.v.servername ~= "" then
    return vim.v.servername
  end
  return vim.fn.serverstart()
end

--- The luaeval expression an external `nvim --server ... --remote-expr` call
--- should evaluate to emit `event` with `data`. Data is JSON-encoded and
--- decoded Lua-side, so the caller never touches Vim dict syntax.
---@param event string
---@param data? table
---@return string expr
function M.remote_expr(event, data)
  local json = data and vim.fn.json_encode(data) or "{}"
  return ("luaeval('require(\"animfx\").emit(_A[1], vim.json.decode(_A[2]))', [%s, %s])"):format(
    vim.fn.string(event),
    vim.fn.string(json)
  )
end

return M
