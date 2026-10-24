vim.g.mapleader = " "

vim.keymap.set("x", "<leader>p", "\"_dP")
vim.keymap.set("n", "<leader>d", "\"_d")
vim.keymap.set("v", "<leader>d", "\"_d")
vim.keymap.set("n", "<leader>D", "\"_D")

vim.keymap.set("n", "<leader>y", "\"+y")
vim.keymap.set("v", "<leader>y", "\"+y")
vim.keymap.set("n", "<leader>Y", "\"+Y")

vim.keymap.set("i", "<C-c>", "<Esc>")

-- <C-i> maps to <Tab> by default (see :help ctrl-i and :map <C-i> resulting
-- from the below). The default mapping is also recursive. Because of this,
-- <C-i> is mapped onwards to any <Tab> mapping, for example the default
-- Open Preview in nvim-tree. Make the mapping non-recursive, so it always
-- jumps forward in the jump list instead of causing chaos.
vim.keymap.set('n', '<C-i>', '<C-i>', { noremap = true })

vim.keymap.set("i", "{<CR>", "{<CR>}<C-o>O")
vim.keymap.set("i", "(<CR>", "(<CR>)<C-o>O")
vim.keymap.set("i", "[<CR>", "[<CR>]<C-o>O")
vim.keymap.set("i", "<<CR>", "<<CR>><C-o>O")

-- Intuitive insert mode stuff
vim.keymap.set("i", "<C-BS>", "<C-w>")
vim.keymap.set("i", "<C-H>", "<C-w>") -- <C-H> is what most terminals send for Ctrl+Backspace
vim.keymap.set("i", "<C-DEL>", "<Esc>ldwi") -- Delete word behind the cursor
vim.keymap.set("i", "<C-v>", "<C-r>+")

vim.keymap.set("n", "<leader>c", ":bel hor te ")
vim.keymap.set("x", "<leader>c", [["zy:bel hor te <C-r>z]])
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
vim.keymap.set("n", "æ", ":noh<CR>/")
vim.keymap.set("x", "æ", "/", {remap = true}) -- Recursive to trigger visual mode "/" remap. Avoid :noh<CR> because it fails in visual mode and is meaningless when we start a search just after it.
vim.keymap.set("o", "æ", "f/")

vim.keymap.set({ "n", "x" }, "ø", ":")
vim.keymap.set("o", "ø", "f:")

vim.keymap.set({ "n", "x" }, "qæ", "q/")
vim.keymap.set({ "n", "x" }, "qø", "q:")

vim.keymap.set({ "n", "x", "o" }, "Ø", "[", {remap = true})
vim.keymap.set({ "n", "x", "o" }, "Æ", "]", {remap = true})
vim.keymap.set({ "n", "x", "o" }, "ØØ", "[[", {remap = true})
vim.keymap.set({ "n", "x", "o" }, "ÆÆ", "]]", {remap = true})
vim.keymap.set({ "n", "x", "o" }, "ØÆ", "[]", {remap = true})
vim.keymap.set({ "n", "x", "o" }, "ÆØ", "][", {remap = true})
vim.keymap.set({ "x", "o" }, "aØ", "a[")
vim.keymap.set({ "x", "o" }, "iØ", "i[")
vim.keymap.set({ "x", "o" }, "aÆ", "a]")
vim.keymap.set({ "x", "o" }, "iÆ", "i]")

vim.keymap.set({ "n", "x", "o" }, "å", "$")
vim.keymap.set({ "n", "x", "o" }, "Å", "_")

-- ¤ Scarab zone ¤
-- This seems redundant when the : register stores the last executed command,
-- but by using "x" we keep the stored command if executing something else
local function store_and_execute()
    local cmdline = vim.fn.getcmdline()
    vim.fn.setreg("x", cmdline)
    vim.fn.feedkeys(vim.keycode("<CR>"))
end

vim.keymap.set("x", "¤", [["xy]])
vim.keymap.set("n", "¤", ":<C-r>x")
vim.keymap.set("c", "¤", store_and_execute)
vim.keymap.set("t", "¤", [[<C-\><C-N>:q<CR>]])

-- From ThePrimeagen
vim.keymap.set("n", "<leader>*", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gIc<Left><Left><Left><Left>]])
vim.keymap.set("n", "J", "mzJ'z")
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")
