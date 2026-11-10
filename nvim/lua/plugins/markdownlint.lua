-- Lint Markdown against nvim/.markdownlint-cli2.yaml (turns off MD013, line length)
-- instead of markdownlint's defaults. A project's own .markdownlint* config still wins.
return {
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = {
      linters = {
        ["markdownlint-cli2"] = {
          args = { "--config", vim.fn.stdpath("config") .. "/.markdownlint-cli2.yaml", "-" },
        },
      },
    },
  },
}
