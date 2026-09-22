vim.opt.termguicolors = true

vim.opt.nu = true
vim.opt.rnu = true

-- Situation                           | Option
-- ------------------------------------|-------------
-- >> and <<                           | shiftwidth
-- Automatic indentation               | shiftwidth
-- <Tab> while inserting indentation   | shiftwidth
-- <Tab> after non-whitespace text     | softtabstop
-- Width/display of literal \t         | tabstop
-- Whether new indentation uses spaces | expandtab
vim.opt.tabstop = 8
vim.opt.softtabstop = 2
vim.opt.shiftwidth = 4
vim.opt.expandtab = true

vim.opt.hlsearch = true
vim.opt.incsearch = true

vim.opt.scrolloff = 8

vim.opt.colorcolumn = "80"

vim.opt.cursorlineopt = "number"
vim.opt.cursorline = true

vim.opt.ignorecase = true -- Needed for smartcase
vim.opt.smartcase = true

vim.opt.signcolumn = 'yes' -- Otherwise will shift screen annoyingly when there is something to display in the signcolumn

vim.opt.foldcolumn = "1"

vim.opt.winborder = "rounded"
