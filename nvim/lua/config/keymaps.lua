-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- close the current buffer (keeps the window layout); replaces Q's "replay last macro" (@@ still does that)
vim.keymap.set("n", "Q", function()
  Snacks.bufdelete()
end, { desc = "Delete Buffer" })
