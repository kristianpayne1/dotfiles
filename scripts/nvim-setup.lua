-- Run by install.sh after `Lazy! restore`. LazyVim builds its treesitter parsers in the background
-- once nvim-treesitter loads; wait for that build (up to 10 minutes) so the install is complete.
require("lazy").load({ plugins = { "nvim-treesitter" } })

local wanted = LazyVim.opts("nvim-treesitter").ensure_installed
local function missing()
  local installed = {}
  for _, lang in ipairs(require("nvim-treesitter").get_installed("parsers")) do
    installed[lang] = true
  end
  return vim.tbl_filter(function(lang)
    return not installed[lang]
  end, wanted)
end

vim.wait(10 * 60 * 1000, function()
  return #missing() == 0
end, 1000)
if #missing() > 0 then
  io.stdout:write("treesitter parsers not built: " .. table.concat(missing(), ", ") .. "\n")
end
vim.cmd("qall!")
