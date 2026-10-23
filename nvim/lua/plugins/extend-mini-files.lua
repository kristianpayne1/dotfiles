return {
  {
    "nvim-mini/mini.files",
    lazy = false,
    keys = {
      {
        "<leader>e",
        function()
          require("mini.files").open(vim.api.nvim_buf_get_name(0), true)
        end,
        desc = "Open mini.files (directory of current file)",
      },
      {
        "<leader>E",
        function()
          require("mini.files").open(vim.uv.cwd(), true)
        end,
        desc = "Open mini.files (cwd)",
      },
      {
        "<leader>fm",
        function()
          require("mini.files").open(LazyVim.root(), true)
        end,
        desc = "Open mini.files (root)",
      },
    },
    opts = {
      options = {
        use_as_default_explorer = true,
      },
    },
    init = function()
      -- stretch the rightmost window to the edge of the screen when it previews a file
      vim.api.nvim_create_autocmd("User", {
        pattern = "MiniFilesWindowUpdate",
        callback = function(args)
          local state = MiniFiles.get_explorer_state()
          if not state then
            return
          end
          local last = state.windows[#state.windows]
          local win_id = args.data.win_id
          if
            not last
            or last.win_id ~= win_id
            or win_id == vim.api.nvim_get_current_win()
            or vim.fn.isdirectory(last.path) == 1
          then
            return
          end
          local config = vim.api.nvim_win_get_config(win_id)
          config.width = math.max(config.width, vim.o.columns - config.col - 2)
          vim.api.nvim_win_set_config(win_id, config)
        end,
      })
    end,
  },

  -- let mini.files (not the snacks explorer) open when nvim starts on a directory
  {
    "folke/snacks.nvim",
    opts = {
      explorer = { replace_netrw = false },
    },
  },
}
