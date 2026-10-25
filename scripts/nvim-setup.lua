-- Run by install.sh after `Lazy! restore`: make sure every treesitter parser LazyVim wants is built.
-- LazyVim starts building missing parsers in the background when nvim-treesitter loads. Install
-- the missing ones here too and wait: languages LazyVim is already building are just waited for,
-- and `force` rebuilds languages left half-installed (queries but no parser) by an interrupted run.
require("lazy").load({ plugins = { "nvim-treesitter" } })

local TS = require("nvim-treesitter")
local wanted = LazyVim.opts("nvim-treesitter").ensure_installed
local function missing()
  local installed = {}
  for _, lang in ipairs(TS.get_installed("parsers")) do
    installed[lang] = true
  end
  return vim.tbl_filter(function(lang)
    return not installed[lang]
  end, wanted)
end

if #missing() > 0 then
  TS.install(missing(), { force = true }):wait(20 * 60 * 1000)
end
if #missing() > 0 then
  io.stdout:write("treesitter parsers not built: " .. table.concat(missing(), ", ") .. "\n")
end
vim.cmd("qall!")
