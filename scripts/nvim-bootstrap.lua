-- Run by install.sh after `Lazy! restore`: install the Mason tools and LSP servers, wait for them,
-- then quit. mason-lspconfig skips its ensure_installed when headless, so it's triggered here.
require("lazy").load({ plugins = { "nvim-lspconfig" } })
require("mason-lspconfig.features.ensure_installed")()

local registry = require("mason-registry")
local to_package = require("mason-lspconfig.mappings").get_mason_map().lspconfig_to_package
local wanted = vim.deepcopy(LazyVim.opts("mason.nvim").ensure_installed or {})
for _, server in ipairs(require("mason-lspconfig.settings").current.ensure_installed) do
  wanted[#wanted + 1] = to_package[server] or server
end

local function state()
  local installing, missing = false, {}
  for _, name in ipairs(wanted) do
    local ok, pkg = pcall(registry.get_package, name)
    if ok then
      installing = installing or pkg:is_installing()
      if not pkg:is_installed() then
        missing[#missing + 1] = name
      end
    end
  end
  return installing, missing
end

-- done when everything is installed, or nothing has been installing for a while (a failure)
local start = vim.uv.now()
vim.wait(20 * 60 * 1000, function()
  local installing, missing = state()
  return #missing == 0 or (not installing and vim.uv.now() - start > 60 * 1000)
end, 1000)

local _, missing = state()
if #missing > 0 then
  io.stdout:write("Mason packages not installed: " .. table.concat(missing, ", ") .. "\n")
end
vim.cmd("qa!")
