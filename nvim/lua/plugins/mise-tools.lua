-- Language servers, formatters, linters and the Rust debugger come from mise (pinned and
-- checksum-locked in mise-global/), not Mason, so Mason is off. LazyVim then enables each LSP
-- server directly and finds its binary on PATH, the same way conform and nvim-lint find theirs.
return {
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },

  -- marksman is a .NET program and aborts on Linux boxes without libicu; it doesn't need
  -- locale-specific behaviour, so run it in .NET's invariant mode everywhere
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        marksman = { cmd_env = { DOTNET_SYSTEM_GLOBALIZATION_INVARIANT = "1" } },
      },
    },
  },

  -- without Mason, LazyVim doesn't set up codelldb for Rust debugging; point rustaceanvim at the
  -- copy mise installed
  {
    "mrcjkb/rustaceanvim",
    opts = function(_, opts)
      local dir = vim.trim(vim.fn.system({ "mise", "where", "github:vadimcn/codelldb" }))
      if vim.v.shell_error ~= 0 or dir == "" then
        return
      end
      local lib = dir .. "/extension/lldb/lib/liblldb" .. (vim.uv.os_uname().sysname == "Linux" and ".so" or ".dylib")
      opts.dap = {
        adapter = require("rustaceanvim.config").get_codelldb_adapter(dir .. "/extension/adapter/codelldb", lib),
      }
    end,
  },
}
