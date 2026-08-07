return {
  {
    "folke/snacks.nvim",
    opts = {
      dashboard = {
        enabled = true,
        width = 78,
        pane_gap = 4,

        preset = {
          header = [[
╔╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╦╗
╠╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╣
╠╬     ☠☠☠        ᚱ ᚢ ᚾ ᛖ ᛋ   ᛟ ᚠ   ᛏ ᚺ ᛖ   ᛟ ᛚ ᛞ        ☠☠☠                ╬╣
╠╬                                                                          ╬╣
╠╬   ██████╗  ██████╗ ██████╗ ███████╗    ████████╗██╗███╗   ███╗███████╗   ╬╣
╠╬  ██╔════╝ ██╔═══██╗██╔══██╗██╔════╝    ╚══██╔══╝██║████╗ ████║██╔════╝   ╬╣
╠╬  ██║      ██║   ██║██║  ██║█████╗         ██║   ██║██╔████╔██║█████╗     ╬╣
╠╬  ██║      ██║   ██║██║  ██║██╔══╝         ██║   ██║██║╚██╔╝██║██╔══╝     ╬╣
╠╬  ╚██████╗ ╚██████╔╝██████╔╝███████╗       ██║   ██║██║ ╚═╝ ██║███████╗   ╬╣
╠╬   ╚═════╝  ╚═════╝ ╚═════╝ ╚══════╝       ╚═╝   ╚═╝╚═╝     ╚═╝╚══════╝   ╬╣
╠╬                                                                          ╬╣
╠╬                     ☠  C O D E   T I M E  ☠                              ╬╣
╠╬                                                                          ╬╣
╠╬        🩸 The altar is awake. The wall remembers. 🩸                     ╬╣
╠╬                                                                          ╬╣
╚╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╩╝
          ]],

          keys = {
            { key = "f", desc = "Seek Relic", action = ":lua Snacks.dashboard.pick('files')" },
            { key = "g", desc = "Blood Search", action = ":lua Snacks.dashboard.pick('live_grep')" },
            { key = "r", desc = "Recall Memories", action = ":lua Snacks.dashboard.pick('oldfiles')" },
            {
              key = "c",
              desc = "Forbidden Config",
              action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})",
            },
            { key = "l", desc = "Summon Lazy", action = ":Lazy" },
            { key = "q", desc = "Leave the Realm", action = ":qa" },
          },
        },

        sections = {
          { section = "header" },
          { section = "keys", padding = 1 },

          -- ☠️ CHARACTER SELECTION (DEPENDS ON REPO)
          {
            pane = 1,
            title = "⚔ Chosen Aspect",
            section = "terminal",
            cmd = [[
root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$root" ]; then
  echo "☠ WANDERER"
  echo "No realm. No master. No history."
elif echo "$root" | grep -Ei "(nvim|dotfiles|config)" >/dev/null; then
  echo "🧙 SORCERER"
  echo "Weaver of runes. Master of configuration."
elif echo "$root" | grep -Ei "(frontend|ui|web)" >/dev/null; then
  echo "🗡 ASSASSIN"
  echo "Fast. Silent. Deadly motions."
elif echo "$root" | grep -Ei "(backend|api|server)" >/dev/null; then
  echo "⚔ KNIGHT"
  echo "Bearer of branches. Slayer of conflicts."
else
  echo "🩸 MERCENARY"
  echo "Adapt or perish."
fi
            ]],
            height = 8,
            padding = 1,
            indent = 2,
          },

          -- 📜 GIT CHRONICLE
          {
            pane = 2,
            title = "📜 Chronicle of Blood",
            section = "terminal",
            enabled = function()
              return Snacks.git.get_root() ~= nil
            end,
            cmd = [[
branch=$(git branch --show-current 2>/dev/null)
echo "Branch: $branch"
git status --short 2>/dev/null | head -6
git log --oneline -3 2>/dev/null
            ]],
            height = 16,
            padding = 1,
            indent = 2,
          },
        },
      },
    },
  },
}
