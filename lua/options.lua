vim.opt.termguicolors = true

vim.opt.nu = true
vim.opt.rnu = true

vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true

vim.opt.hlsearch = false
vim.opt.incsearch = true

vim.opt.scrolloff = 8

vim.opt.colorcolumn = "80"

vim.opt.ignorecase = true -- Needed for smartcase
vim.opt.smartcase = true

vim.opt.signcolumn = 'yes' -- Otherwise will shift screen annoyingly when there is something to display in the signcolumn

vim.opt.winborder = "rounded"

-- Current dependees: autocompletion, ...
vim.o.pumborder = "rounded"
vim.o.pumheight = 25

-- vim.cmd.lan("en_GB", true)
