return {
  {
    "akinsho/toggleterm.nvim",
    keys = {
      { "<C-/>", "<cmd>ToggleTerm direction=float<cr>", desc = "Terminal (float)", mode = { "n", "t" } },
      { "<leader>ft", "<cmd>ToggleTerm direction=float<cr>", desc = "Terminal (float)" },
    },
    opts = {
      open_mapping = [[<C-/>]],
      direction = "float",
      float_opts = {
        border = "curved",
        width = math.floor(vim.o.columns * 0.8),
        height = math.floor(vim.o.lines * 0.8),
      },
      -- Evita que se abra en otros modos
      on_open = function(term)
        vim.api.nvim_buf_set_keymap(term.bufnr, "t", "<C-/>", "<cmd>ToggleTerm<cr>", { noremap = true, silent = true })
      end,
    },
  },
}
