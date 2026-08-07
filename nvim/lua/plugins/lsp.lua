return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        eslint = {
          filetypes = {
            "javascript",
            "javascriptreact",
            "typescript",
            "typescriptreact",
            "vue",
          },
          settings = {
            experimental = {
              useFlatConfig = true,
            },
            -- Especifica explícitamente el archivo de configuración
            options = {
              overrideConfigFile = "eslint.config.ts",
            },
            workingDirectories = { mode = "auto" },
            format = true,
            validate = "on",
          },
        },
      },
      setup = {
        eslint = function()
          vim.api.nvim_create_autocmd("LspAttach", {
            callback = function(args)
              local client = vim.lsp.get_client_by_id(args.data.client_id)
              if client and client.name == "eslint" then
                vim.api.nvim_create_autocmd("BufWritePre", {
                  buffer = args.buf,
                  callback = function()
                    vim.cmd("LspEslintFixAll")
                  end,
                })
              end
            end,
          })
        end,
      },
    },
  },
}
