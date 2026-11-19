-- Keep Markdown rendered under the cursor in normal mode. By default render-markdown turns the
-- cursor line back into raw Markdown ("anti-conceal"), so moving through a table makes each row
-- in turn lose its borders, padding and formatting and the columns jump about. Raw Markdown still
-- shows in insert mode (rendering is off there), and <leader>um toggles rendering.
--
-- One case this can't fix: a row too wide for the window, which the plugin wraps into several
-- screen lines, always shows raw on the cursor line (render-markdown hard-codes it).
return {
  "MeanderingProgrammer/render-markdown.nvim",
  opts = {
    anti_conceal = { enabled = false },
    -- Also keep Neovim's own conceal (the ** and ` markers) hidden on the cursor line.
    win_options = { concealcursor = { rendered = "nc" } },
  },
}
