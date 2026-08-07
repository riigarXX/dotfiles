return {
  {
    "navarasu/onedark.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      transparent = true,
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "onedark",
    },
    init = function()
      local function apply()
        vim.api.nvim_set_hl(0, "NeoTreeDirectoryName", { fg = "#61AFEF" })
        vim.api.nvim_set_hl(0, "NeoTreeDirectoryIcon", { fg = "#61AFEF" })
        vim.api.nvim_set_hl(0, "NormalFloat", { bg = "NONE" })
        vim.api.nvim_set_hl(0, "FloatBorder", { bg = "NONE" })
      end
      local group = vim.api.nvim_create_augroup("LazyThemeOverrides", { clear = true })
      vim.api.nvim_create_autocmd("ColorScheme", { callback = apply, group = group })
      apply()
    end,
  },
}
