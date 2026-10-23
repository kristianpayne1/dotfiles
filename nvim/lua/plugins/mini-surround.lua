-- vim-surround style mappings: ys{motion}{char}, ds{char}, cs{old}{new}, visual S{char}
return {
  "nvim-mini/mini.surround",
  keys = {
    { "S", desc = "Add Surrounding", mode = "x" },
    { "yss", desc = "Add Surrounding (line)" },
  },
  opts = {
    mappings = {
      add = "ys",
      delete = "ds",
      find = "",
      find_left = "",
      highlight = "",
      replace = "cs",
      update_n_lines = "",
      suffix_last = "",
      suffix_next = "",
    },
    search_method = "cover_or_next",
  },
  config = function(_, opts)
    require("mini.surround").setup(opts)
    -- `ys` in visual mode would make `y` wait; use `S` instead
    vim.keymap.del("x", "ys")
    vim.keymap.set("x", "S", [[:<C-u>lua MiniSurround.add('visual')<CR>]], { silent = true, desc = "Add Surrounding" })
    vim.keymap.set("n", "yss", "ys_", { remap = true, desc = "Add Surrounding (line)" })
  end,
}
