require('gitsigns').setup()

vim.keymap.set({'o', 'x'}, 'ih', '<Cmd>Gitsigns select_hunk<CR>')
vim.keymap.set({'o', 'x'}, 'ah', '<Cmd>Gitsigns select_hunk<CR>')

-- TODO: Would be nice if these worked with ; and ,
vim.keymap.set({'n', 'o', 'x'}, '[h', '<Cmd>Gitsigns prev_hunk<CR>')
vim.keymap.set({'n', 'o', 'x'}, ']h', '<Cmd>Gitsigns next_hunk<CR>')

vim.keymap.set("n", "<leader>gb", ":Gitsigns blame<CR>")
vim.keymap.set("n", "<leader>gK", ":Gitsigns blame_line<CR>")

vim.keymap.set("n", "<leader>gu", ":Gitsigns reset_hunk<CR>")
