-- Neovim half of scripts/verify.sh: theme, parsers, LSP servers attaching, formatters and the
-- Rust debugger. Exits with an error code on the first failure.
local dir = assert(vim.env.TEST_DIR, "TEST_DIR not set")

local function ok(msg)
  io.stdout:write("  \27[32mok\27[0m  " .. msg .. "\n")
end
local function fail(msg)
  io.stdout:write("  \27[31mFAIL\27[0m " .. msg .. "\n")
  vim.cmd("cquit 1")
end

local function check()
  if vim.g.colors_name ~= "onedark" then
    return fail("colorscheme is " .. tostring(vim.g.colors_name) .. ", not onedark")
  end
  ok("One Dark Pro theme")

  require("lazy").load({ plugins = { "nvim-treesitter" } })
  local wanted = LazyVim.opts("nvim-treesitter").ensure_installed
  local installed = {}
  for _, lang in ipairs(require("nvim-treesitter").get_installed("parsers")) do
    installed[lang] = true
  end
  local missing = vim.tbl_filter(function(lang)
    return not installed[lang]
  end, wanted)
  if #missing > 0 then
    return fail("treesitter parsers missing: " .. table.concat(missing, ", "))
  end
  ok("all " .. #wanted .. " treesitter parsers")

  local mason = require("lazy.core.config").plugins["mason.nvim"]
  if mason and mason._.loaded then
    return fail("Mason loaded; tools should come from mise")
  end

  -- each file should get its language server from mise
  local servers = {
    { "test.lua", "lua_ls" },
    { "test.md", "marksman" },
    { "test.ts", "vtsls" },
    { "test.yaml", "yamlls" },
    { "test.json", "jsonls" },
    { "test.toml", "taplo" },
    { "test.py", "basedpyright" },
    { "test.py", "ruff" },
    { "tailwind/index.html", "tailwindcss" },
  }
  for _, pair in ipairs(servers) do
    local file, server = pair[1], pair[2]
    vim.cmd.edit(dir .. "/" .. file)
    local buf = vim.api.nvim_get_current_buf()
    local attached = vim.wait(60000, function()
      return #vim.lsp.get_clients({ bufnr = buf, name = server }) > 0
    end, 200)
    if not attached then
      return fail(server .. " didn't attach to " .. file)
    end
    ok(server .. " attaches to " .. file)
  end

  -- formatters conform would run
  for file, formatter in pairs({ ["test.lua"] = "stylua", ["test.md"] = "prettier", ["test.ts"] = "prettier" }) do
    vim.cmd.edit(dir .. "/" .. file)
    local info = require("conform").get_formatter_info(formatter, vim.api.nvim_get_current_buf())
    if not info.available then
      return fail(formatter .. " not available for " .. file .. ": " .. tostring(info.available_msg))
    end
  end
  ok("stylua and prettier available to conform")

  local codelldb = vim.trim(vim.fn.system({ "mise", "where", "github:vadimcn/codelldb" })) .. "/extension/adapter/codelldb"
  if vim.fn.executable(codelldb) ~= 1 then
    return fail("codelldb not found at " .. codelldb)
  end
  ok("codelldb for Rust debugging")

  vim.cmd("qall!")
end

-- let LazyVim finish starting up first
vim.defer_fn(function()
  local ok_run, err = pcall(check)
  if not ok_run then
    fail(tostring(err))
  end
end, 1000)
