---
name: create-theme
description: "Creates a new theme for the dotfiles theme system (theme.sh). Generates all required files under themes/<name>/ (ghostty.conf, starship.toml, zsh.sh, nvim.lua) following the repo conventions, verifies them, and applies the theme. Use when the user asks to add or create a new theme, port a palette (e.g. 'nuevo tema', 'agrega el tema X', 'create theme', 'add a colorscheme'), or change to a theme that does not exist yet in this repo."
---

# Create a new theme for the dotfiles theme system

This repo has a custom theming system driven by `./theme.sh`. Every theme is a
directory `themes/<name>/` containing exactly 4 files. There is no registry:
`theme.sh` discovers themes by listing directories under `themes/`.

## How the system works

| File (in `themes/<name>/`) | Target when applied | Purpose |
|---|---|---|
| `ghostty.conf` | copied to `ghostty/theme.conf` | Terminal colors (bg/fg/cursor/selection + 16-color ANSI palette) |
| `starship.toml` | copied to repo-root `starship.toml` (symlinked to `~/.config/starship.toml`) | Shell prompt segments + palette |
| `zsh.sh` | copied to `~/.config/zsh-colors.sh` (sourced by `.zshrc`) | `LS_COLORS` for lsd/rg/bat colors |
| `nvim.lua` | copied to `nvim/lua/plugins/colorscheme.lua` | Neovim colorscheme plugin spec + LazyVim integration |

`./theme.sh apply <name>` also **generates** `opencode/themes/<name>.json`
from the ghostty.conf palette and sets `opencode/tui.json` theme. Do NOT
create those files manually — `apply` owns them.

Existing themes (reference implementations): `gruvbox`, `dracula`,
`catppuccin`, `nord`, `tokyonight`, `monokai`.

## Workflow

### 1. Gather requirements — ask the user first

Ask (one `question` call) for anything not already specified:

1. **Theme name** — kebab-case, lowercase, no spaces (e.g. `kanagawa`).
2. **Palette source** — user-provided hex values, or a known theme (Kanagawa,
   Material, Solarized, etc.). A vendored ghostty-themes collection lives at
   `ghostty/themes/themes/` (same `background = #…` / `palette = N=#…`
   format) — reuse those hex values when the user names a theme found there.
3. **Neovim colorscheme plugin** — REQUIRED: the `nvim.lua` references a real,
   installable nvim colorscheme plugin whose palette matches the terminal
   theme. Existing ones: `ellisonleao/gruvbox.nvim`, `Mofiqul/dracula.nvim`,
   `catppuccin/nvim`, `shaunsingh/nord.nvim`, `folke/tokyonight.nvim`,
   `loctvl842/monokai-pro.nvim`. If the requested theme has no exact nvim
   port, recommend the closest available plugin (or a well-known one with a
   matching palette) instead of inventing one.

This whole stack assumes a **dark background**. For light themes, either pick
a dark variant or tell the user the prompt/terminal will look wrong.

### 2. Create the 4 files

Copy the structure of an existing theme (`themes/dracula/` is the most
up-to-date) and replace the palette values. Keep every other config identical
so the 6 themes stay consistent.

#### `themes/<name>/ghostty.conf`

```ini
# <Display Name>
background = #1A1B26
foreground = #C0CAF5
cursor-color = #C0CAF5
selection-background = #364A82

palette = 0=#1A1B26
palette = 1=#F7768E
palette = 2=#9ECE6A
palette = 3=#E0AF68
palette = 4=#7AA2F7
palette = 5=#BB9AF7
palette = 6=#7DCFFF
palette = 7=#C0CAF5
palette = 8=#565F89
palette = 9=#FF9E64
palette = 10=#9ECE6A
palette = 11=#E0AF68
palette = 12=#7AA2F7
palette = 13=#BB9AF7
palette = 14=#7DCFFF
palette = 15=#FFFFFF
```

(example above is tokyonight night). Uppercase hex, one `palette = N=#…` line
per entry, blank line between the header block and the palette.

#### `themes/<name>/starship.toml`

Copy `themes/<existing>/starship.toml` **verbatim** and change only:

- `palette = '<existing>'` → `palette = '<name>'`
- the `[palettes.<existing>]` block → `[palettes.<name>]` with these 9 keys:

```toml
[palettes.<name>]
color_fg0 = '<foreground>'
color_bg1 = '<background>'
color_bg3 = '<selection-background or ANSI 8>'
color_blue = '<ANSI 4>'
color_aqua = '<ANSI 6>'
color_green = '<ANSI 2>'
color_orange = '<ANSI 3 or a warm bright (9/11) tone>'
color_purple = '<ANSI 5>'
color_red = '<ANSI 1>'
color_yellow = '<ANSI 3>'
```

Do not touch the `format` string or any module (`[os]`, `[directory]`,
`[git_branch]`, …) — they are identical across all themes. Segment text
convention (already baked into the files, keep it): light segments
(orange/yellow/aqua/blue) use dark text `fg:color_bg1`; dark segments
(bg1/bg3, e.g. `$time`, `$pixi`) use `fg:color_fg0`.

#### `themes/<name>/zsh.sh`

Copy the shape of an existing `zsh.sh` (single `LS_COLORS` export, decimal
RGB in `38;2;R;G;B` form). Color mapping used by the existing themes:

| Entry | ANSI slot |
|---|---|
| `di` (dirs) | 4 (blue) |
| `ln` (links) | 6 (cyan/aqua) |
| `ex`, `*.sh` | 2 (green) |
| `*.tar`, `*.gz`, `*.zip` | 1 (red) |
| `*.md`, `*.markdown`, `*.txt` | 3 (yellow/orange) |
| `*.png`, `*.jpg`, `*.jpeg`, `*.svg`, `*.gif` | 5 (purple) |

Example line:
`export LS_COLORS="di=38;2;122;162;247:ln=38;2;125;207;255:ex=38;2;158;206;106:*.tar=38;2;247;118;142:*.gz=38;2;247;118;142:*.zip=38;2;247;118;142:*.md=38;2;224;175;104:*.markdown=38;2;224;175;104:*.txt=38;2;224;175;104:*.png=38;2;187;154;247:*.jpg=38;2;187;154;247:*.jpeg=38;2;187;154;247:*.svg=38;2;187;154;247:*.gif=38;2;187;154;247:*.sh=38;2;158;206;106:fi=0"`

First line: `# Colores del tema <name> (generado por theme.sh)`.

#### `themes/<name>/nvim.lua`

Template (see `themes/dracula/nvim.lua` and `themes/catppuccin/nvim.lua` for
working examples):

```lua
return {
  {
    "<colorscheme-plugin>",
    lazy = false,
    priority = 1000,
    opts = {
      -- per-plugin transparency option (see table below)
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "<colorscheme-name>",
    },
    init = function()
      local function apply()
        vim.api.nvim_set_hl(0, "NeoTreeDirectoryName", { fg = "#<ANSI 4>" })
        vim.api.nvim_set_hl(0, "NeoTreeDirectoryIcon", { fg = "#<ANSI 4>" })
        vim.api.nvim_set_hl(0, "NormalFloat", { bg = "NONE" })
        vim.api.nvim_set_hl(0, "FloatBorder", { bg = "NONE" })
      end
      local group = vim.api.nvim_create_augroup("LazyThemeOverrides", { clear = true })
      vim.api.nvim_create_autocmd("ColorScheme", { callback = apply, group = group })
      apply()
    end,
  },
}
```

Transparency option per plugin:

| Plugin | Option |
|---|---|
| gruvbox.nvim | `transparent_mode = true` (plus `overrides` for SignColumn/signs, see `themes/gruvbox/nvim.lua`) |
| dracula.nvim | `transparent_bg = true` |
| catppuccin/nvim | `transparent_background = true` — REQUIRES the `config` re-apply (see below) |
| nord.nvim | `vim.g.nord_disable_background = true` inside `config` |
| tokyonight.nvim | `transparent = true` |
| monokai-pro.nvim | `transparent_background = true` |

**Known pitfall — catppuccin only**: LazyVim applies the colorscheme during
spec collection, before any plugin is configured, so catppuccin compiles its
color cache with default (opaque) options. Fix: give catppuccin an explicit
`config` that runs setup with the real opts and re-applies the colorscheme:

```lua
config = function(_, opts)
  require("catppuccin").setup(opts)
  vim.cmd.colorscheme("catppuccin")
end,
```

### 3. Verify

1. `./theme.sh list` → the new theme must appear.
2. `./theme.sh preview <name>` → renders a terminal mockup (prompt segments,
   nvim buffer, full palette). Check segment text contrast against the
   mockup's own `seg_text` logic — text must be dark on light segments.
3. Confirm the colorscheme actually loads: run
   `nvim --headless "+lua print(vim.g.colors_name)" +qa` — it must print the
   colorscheme name (first run installs the plugin, retry once if it prints
   nothing). If nvim errors, the plugin name or spec is wrong — fix before
   applying.

### 4. Apply

Run `./theme.sh apply <name>`. It copies all 4 files to their targets,
generates `opencode/themes/<name>.json`, sets `opencode/tui.json`, and runs
the nvim plugin sync. Then tell the user:

- `source ~/.zshrc` (starship/zsh colors)
- restart ghostty (Cmd+Q) — its palette does not hot-reload
- restart opencode (the TUI theme)

## Rules

- All 4 files are mandatory; `apply` fails without any of them.
- Never edit `ghostty/theme.conf`, the repo-root `starship.toml`,
  `nvim/lua/plugins/colorscheme.lua`, `opencode/tui.json`, or
  `opencode/themes/*.json` directly — always go through `./theme.sh apply`.
- Keep the new theme's starship.toml structure byte-identical to the others
  except palette name + values.
- Do not add wallpapers or touch `ghostty/config` (transparency/opacity is
  global, not per-theme).
- If the user asks for a theme that already exists, just run
  `./theme.sh apply <name>` instead of creating files.
