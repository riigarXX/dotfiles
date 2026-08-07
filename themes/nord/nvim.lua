return {
  {
    "shaunsingh/nord.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      vim.g.nord_disable_background = true
      vim.cmd.colorscheme("nord")
    end,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "nord",
    },
    init = function()
      local function apply()
        vim.api.nvim_set_hl(0, "NeoTreeDirectoryName", { fg = "#81A1C1" })
        vim.api.nvim_set_hl(0, "NeoTreeDirectoryIcon", { fg = "#81A1C1" })
        vim.api.nvim_set_hl(0, "NormalFloat", { bg = "NONE" })
        vim.api.nvim_set_hl(0, "FloatBorder", { bg = "NONE" })
      end
      local group = vim.api.nvim_create_augroup("LazyThemeOverrides", { clear = true })
      vim.api.nvim_create_autocmd("ColorScheme", { callback = apply, group = group })
      apply()
    end,
  },
}
