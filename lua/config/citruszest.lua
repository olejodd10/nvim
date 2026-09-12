local palette = require("citruszest.palettes.colors")

local black = palette.background
local dark_gray = palette.visual
local gray = palette.bright_black
local light_gray = palette.white

require("citruszest").setup({
  style = {
    StatusLine = { fg = black, bg = light_gray },
    StatusLineNC = { fg = black, bg = gray },

    WinSeparator = { fg = light_gray, bg = black },
    NvimTreeWinSeparator = { fg = light_gray, bg = black },

    ColorColumn = { bg = dark_gray },

    CursorLineNr = { fg = light_gray },
  },
})

vim.cmd("colorscheme citruszest")
