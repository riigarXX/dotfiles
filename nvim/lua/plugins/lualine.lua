-- Configuración de Lualine para LazyVim con TypeScript y Vue
-- Guardar en: ~/.config/nvim/lua/plugins/lualine.lua

return {
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    opts = function(_, opts)
      -- Configuración personalizada para TypeScript/Vue

      -- Componentes personalizados
      local function get_typescript_server()
        local clients = vim.lsp.get_active_clients()
        for _, client in ipairs(clients) do
          if client.name == "volar" or client.name == "tsserver" or client.name == "vtsls" then
            return " " .. client.name
          end
        end
        return ""
      end

      local function get_vue_version()
        local buf_name = vim.api.nvim_buf_get_name(0)
        if buf_name:match("%.vue$") then
          return " Vue"
        end
        return ""
      end

      -- Iconos para diferentes tipos de archivo
      local function filetype_with_icon()
        local filetype = vim.bo.filetype
        local icon_ok, devicons = pcall(require, "nvim-web-devicons")

        if icon_ok then
          local icon = devicons.get_icon_by_filetype(filetype)
          if icon then
            return icon .. " " .. filetype
          end
        end
        return filetype
      end

      -- Diagnósticos con iconos personalizados
      local diagnostics = {
        "diagnostics",
        sources = { "nvim_diagnostic" },
        sections = { "error", "warn", "info", "hint" },
        symbols = {
          error = " ",
          warn = " ",
          info = " ",
          hint = " ",
        },
        colored = true,
        update_in_insert = false,
        always_visible = false,
      }

      -- Información de Git
      local diff = {
        "diff",
        symbols = {
          added = " ",
          modified = " ",
          removed = " ",
        },
        colored = true,
        diff_color = {
          added = { fg = "#98c379" },
          modified = { fg = "#e5c07b" },
          removed = { fg = "#e06c75" },
        },
      }

      -- Branch con icono
      local branch = {
        "branch",
        icons_enabled = true,
        icon = "",
      }

      -- Codificación del archivo
      local encoding = {
        "encoding",
        fmt = string.upper,
      }

      -- Formato de archivo
      local fileformat = {
        "fileformat",
        symbols = {
          unix = "LF",
          dos = "CRLF",
          mac = "CR",
        },
      }

      -- Progreso en el archivo
      local progress = {
        "progress",
        separator = { left = "", right = "" },
      }

      local location = {
        "location",
        padding = 0,
      }

      -- Espacios/tabs
      local spaces = function()
        local shiftwidth = vim.api.nvim_buf_get_option(0, "shiftwidth")
        return "spaces: " .. shiftwidth
      end

      -- LSP activo
      local lsp = {
        function()
          local msg = "No LSP"
          local buf_ft = vim.api.nvim_buf_get_option(0, "filetype")
          local clients = vim.lsp.get_active_clients()

          if next(clients) == nil then
            return msg
          end

          for _, client in ipairs(clients) do
            local filetypes = client.config.filetypes
            if filetypes and vim.fn.index(filetypes, buf_ft) ~= -1 then
              return "LSP: " .. client.name
            end
          end

          return msg
        end,
        icon = " ",
        color = { fg = "#61afef" },
      }

      -- Configurar secciones
      opts.sections = {
        lualine_a = { "mode" },
        lualine_b = { branch, diff },
        lualine_c = {
          {
            "filename",
            path = 1, -- 0 = solo nombre, 1 = ruta relativa, 2 = ruta absoluta
            symbols = {
              modified = " ●",
              readonly = " ",
              unnamed = "[Sin nombre]",
            },
          },
          get_vue_version,
        },
        lualine_x = {
          diagnostics,
          lsp,
          encoding,
          fileformat,
          filetype_with_icon,
        },
        lualine_y = { progress },
        lualine_z = { location },
      }

      -- Secciones inactivas
      opts.inactive_sections = {
        lualine_a = {},
        lualine_b = {},
        lualine_c = { "filename" },
        lualine_x = { "location" },
        lualine_y = {},
        lualine_z = {},
      }

      -- Extensiones para diferentes tipos de ventana
      opts.extensions = {
        "neo-tree",
        "lazy",
        "mason",
        "nvim-dap-ui",
        "toggleterm",
        "trouble",
      }

      -- Tema (puedes cambiarlo)
      opts.options = {
        theme = "auto", -- auto, tokyonight, catppuccin, gruvbox, etc.
        component_separators = { left = "", right = "" },
        section_separators = { left = "", right = "" },
        disabled_filetypes = {
          statusline = { "dashboard", "alpha", "starter" },
        },
        always_divide_middle = true,
        globalstatus = true,
      }

      return opts
    end,
  },

  -- Dependencias recomendadas para mejor experiencia
  {
    "nvim-tree/nvim-web-devicons",
    lazy = true,
  },
}
