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

-- Intuitive insert mode stuff
vim.keymap.set("i", "<C-BS>", "<C-w>")
vim.keymap.set("i", "<C-H>", "<C-w>") -- <C-H> is what most terminals send for Ctrl+Backspace
vim.keymap.set("i", "<C-DEL>", "<Esc>ldwi") -- Delete word behind the cursor
vim.keymap.set("i", "<C-v>", "<C-r>+")

vim.keymap.set("n", "<leader>c", ":!")
vim.keymap.set("n", "<leader>r", vim.cmd.vsp)

vim.keymap.set("n", "<leader>s", [[:%s///g<Left><Left><Left>]])
vim.keymap.set("x", "<leader>s", [["zy:%s/<C-r>z/<C-r>z/gIc<Left><Left><Left><Left>]])

vim.keymap.set("x", "/", [["zy/<C-r>z<CR>]])
vim.keymap.set("x", "?", [["zy?<C-r>z<CR>]])

vim.keymap.set("c", "<C-g>", [[\(.*\)]])

vim.keymap.set("n", "L", vim.diagnostic.open_float)

-- Save one keystroke when editing stuff separated with - and _
vim.keymap.set("o", "-", "f-")
vim.keymap.set("o", "_", "f_")
vim.keymap.set("o", "q", "f_") -- Faster

-- Resembles tmux resizing
-- Ctrl-s because it is close to Ctrl-w (moving between windows)
-- and can be remembered as "s for size"
vim.keymap.set("n", "<C-s>l", ":vertical resize +5<CR><C-s>", {remap = true})
vim.keymap.set("n", "<C-s>h", ":vertical resize -5<CR><C-s>", {remap = true})
vim.keymap.set("n", "<C-s>j", ":horizontal resize +5<CR><C-s>", {remap = true})
vim.keymap.set("n", "<C-s>k", ":horizontal resize -5<CR><C-s>", {remap = true})
vim.keymap.set("n", "<C-s>s", "<C-c>") -- Can exit with s as well as <C-c>

-- Powerful Norwegian remaps
vim.keymap.set({ "n", "x" }, "æ", "/", {remap = true})
vim.keymap.set("n", "ø", ":")
vim.keymap.set("", "å", "$")

vim.keymap.set("n", "Ø", "[")
vim.keymap.set("n", "Æ", "]")
vim.keymap.set("", "Å", "_")

-- From ThePrimeagen
vim.keymap.set("n", "<leader>*", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gIc<Left><Left><Left><Left>]])
vim.keymap.set("n", "J", "mzJ'z")
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")
