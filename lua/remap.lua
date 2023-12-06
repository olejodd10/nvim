vim.g.mapleader = " "

vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")

vim.keymap.set("x", "<leader>p", "\"_dP")
vim.keymap.set("n", "<leader>d", "\"_d")
vim.keymap.set("v", "<leader>d", "\"_d")
vim.keymap.set("n", "<leader>D", "\"_D")

vim.keymap.set("n", "<leader>y", "\"+y")
vim.keymap.set("v", "<leader>y", "\"+y")
vim.keymap.set("n", "<leader>Y", "\"+Y")

vim.keymap.set("i", "<C-c>", "<Esc>")

vim.keymap.set("i", "(<CR>", "()<left><CR>")
vim.keymap.set("i", "[<CR>", "[]<left><CR>")
vim.keymap.set("i", "<<CR>", "<><left><CR>")
vim.keymap.set("i", "{<CR>", "{}<left><CR>")

vim.keymap.set("i", "<C-h>", "<C-w>") -- Also remaps <C-BS>
vim.keymap.set("i", "<C-l>", "<Esc>ldwi") -- Delete word behind the cursor

vim.keymap.set("i", "<C-v>", "<C-r>+")
vim.keymap.set("i", "<S-Tab>", "<C-d>")

vim.keymap.set("n", "<leader>c", ":!")
vim.keymap.set("n", "<leader>r", vim.cmd.vsp)

vim.keymap.set("c", "<C-g>", [[\(.*\)]])

-- From ThePrimeagen
vim.keymap.set("n", "<leader>*", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gIc<Left><Left><Left><Left>]])

vim.keymap.set("n", "æ", "/")
vim.keymap.set("n", "ø", ":")
vim.keymap.set("", "å", "$")
