return {
  {
    "Mofiqul/dracula.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      transparent_bg = true,
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "dracula",
    },
    init = function()
      local function apply()
        vim.api.nvim_set_hl(0, "NeoTreeDirectoryName", { fg = "#BD93F9" })
        vim.api.nvim_set_hl(0, "NeoTreeDirectoryIcon", { fg = "#BD93F9" })
        vim.api.nvim_set_hl(0, "NormalFloat", { bg = "NONE" })
        vim.api.nvim_set_hl(0, "FloatBorder", { bg = "NONE" })
      end
      local group = vim.api.nvim_create_augroup("LazyThemeOverrides", { clear = true })
      vim.api.nvim_create_autocmd("ColorScheme", { callback = apply, group = group })
      apply()
    end,
  },
}
