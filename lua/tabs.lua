-- Important built-in tab commands to use together with this: gt, gT, g<Tab>
vim.keymap.set("n", "<M-l>", vim.cmd.tabnext)
vim.keymap.set("n", "<M-h>", vim.cmd.tabprevious)
vim.keymap.set("n", "<M-j>", vim.cmd.tabclose)
vim.keymap.set("n", "<M-k>", vim.cmd.tabs)
vim.keymap.set("n", "<leader>T", vim.cmd.tabnew)
