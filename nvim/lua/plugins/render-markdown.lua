-- Keep Markdown rendered under the cursor in normal mode. By default render-markdown turns the
-- cursor line back into raw Markdown ("anti-conceal"), so moving through a table makes each row
-- in turn lose its borders, padding and formatting and the columns jump about. Raw Markdown still
-- shows in insert mode (rendering is off there), and <leader>um toggles rendering.
--
-- This only helps tables that fit the window. A wider table has its columns shrunk and its rows
-- redrawn as wrapped virtual lines, and render-markdown always shows such a row raw on the cursor
-- line. Turning off pipe_table.wrap would stop that, but long rows would then soft-wrap into an
-- unreadable mess, so wide tables keep the flip.
return {
  "MeanderingProgrammer/render-markdown.nvim",
  opts = {
    anti_conceal = { enabled = false },
    -- Also keep Neovim's own conceal (the ** and ` markers) hidden on the cursor line.
    win_options = { concealcursor = { rendered = "nc" } },
  },
}
