-- Configuraciones adicionales para TypeScript y Vue
-- Guardar en: ~/.config/nvim/lua/config/options.lua (agregar al final)

-- Opciones específicas para desarrollo web
vim.opt.tabstop = 2 -- Tamaño de tab visual
vim.opt.shiftwidth = 2 -- Espacios para indentación
vim.opt.softtabstop = 2 -- Espacios al presionar tab
vim.opt.expandtab = true -- Convertir tabs a espacios

-- Mejor rendimiento para archivos grandes
vim.opt.updatetime = 250 -- Tiempo para CursorHold y swap file
vim.opt.timeoutlen = 300 -- Tiempo para secuencias de teclas

-- Mostrar caracteres invisibles útiles
vim.opt.list = true
vim.opt.listchars = {
  tab = "→ ",
  trail = "·",
  extends = "›",
  precedes = "‹",
  nbsp = "␣",
}

-- Números de línea relativos (útil para movimientos)
vim.opt.number = true
vim.opt.relativenumber = true

-- Resaltado de línea actual
vim.opt.cursorline = true

-- Mejor manejo de archivos .vue
vim.filetype.add({
  extension = {
    vue = "vue",
  },
})

-- Auto-comandos para TypeScript/Vue
local augroup = vim.api.nvim_create_augroup("TypeScriptVueSetup", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
  group = augroup,
  pattern = { "typescript", "typescriptreact", "vue" },
  callback = function()
    vim.opt_local.shiftwidth = 2
    vim.opt_local.tabstop = 2
    vim.opt_local.softtabstop = 2
  end,
})

-- Formateo automático al guardar (opcional, descomenta si lo deseas)
-- vim.api.nvim_create_autocmd("BufWritePre", {
--   group = augroup,
--   pattern = { "*.ts", "*.tsx", "*.vue", "*.js", "*.jsx" },
--   callback = function()
--     vim.lsp.buf.format({ async = false })
--   end,
-- })
