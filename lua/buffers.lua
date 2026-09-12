local function navshow()
    vim.cmd.buffers()
end
local function navprev()
    vim.cmd(":b#")
end
local function navright()
    vim.cmd.bnext()
    navshow()
end
local function navleft()
    vim.cmd.bprevious()
    navshow()
end
local function navdelete()
    vim.cmd.bdelete()
    navshow()
end

vim.keymap.set("n", "<M-p>", navprev) 
vim.keymap.set("n", "<M-right>", navright) -- Consider just <right> and <left>
vim.keymap.set("n", "<M-left>", navleft)
vim.keymap.set("n", "<M-down>", navdelete)
vim.keymap.set("n", "<M-up>", navshow)
