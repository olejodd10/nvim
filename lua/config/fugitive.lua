-- Prefer git aliases that are reusable outside nvim rather than cool remaps.
-- Avoiding add and commit remaps to not mess things up with fast fingers.
-- We're not in _that_ much of a rush.

vim.keymap.set("n", "<leader>gs", ":vert Git<CR>")
vim.keymap.set("n", "<leader>gi", ":vert Git ")

vim.keymap.set("n", "<leader>gb", ":Git blame<CR>")
vim.keymap.set("n", "<leader>gv", ":Gvdiffsplit<CR>") -- Cool beans
vim.keymap.set("n", "<leader>gl", ":vert Git log<CR>")
vim.keymap.set("n", "<leader>gd", ":vert Git diff") -- No <CR> to leave access to aliases and args

vim.keymap.set("n", "<leader>gx", ":GBrowse<CR>")
