local background = "#121212"
local bright_black = "#767C77"

local a_lighter_bg = bright_black
local a_darker_fg_to_contrast_with_it = background

require("citruszest").setup({
    style = {
        StatusLine = { fg = a_darker_fg_to_contrast_with_it, bg = a_lighter_bg },
        WinSeparator = { fg = a_lighter_bg, bg = a_darker_fg_to_contrast_with_it }, -- "|" is used between windows, i.e. fg
        NvimTreeWinSeparator = { fg = a_lighter_bg, bg = a_darker_fg_to_contrast_with_it },
    },
})

vim.cmd("colorscheme citruszest")
