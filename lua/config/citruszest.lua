local background = "#121212"
local subtle_gray = "#2a2a2a"
local bright_black = "#767C77"
local a_lighter_bg = bright_black
local a_darker_fg_to_contrast_with_it = background

require("citruszest").setup({
  style = {
    StatusLine = { fg = a_darker_fg_to_contrast_with_it, bg = a_lighter_bg },
    WinSeparator = { fg = a_lighter_bg, bg = a_darker_fg_to_contrast_with_it },
    NvimTreeWinSeparator = { fg = a_lighter_bg, bg = a_darker_fg_to_contrast_with_it },
    ColorColumn = { bg = subtle_gray },
  },
})
vim.cmd("colorscheme citruszest")
