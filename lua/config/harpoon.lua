local harpoon = require("harpoon")

harpoon:setup()

-- e for edit
vim.keymap.set("n", "<leader>fe", function() harpoon.ui:toggle_quick_menu(harpoon:list()) end)

vim.keymap.set("n", "<leader>el", function() harpoon:list():add() end)
vim.keymap.set("n", "<leader>eq", function() harpoon:list():remove() end)

vim.keymap.set("n", "<leader>ej", function() harpoon:list():next() end)
vim.keymap.set("n", "<leader>ek", function() harpoon:list():prev() end)

vim.keymap.set("n", "<leader>e1", function() harpoon:list():select(1)  end)
vim.keymap.set("n", "<leader>e2", function() harpoon:list():select(2)  end)
vim.keymap.set("n", "<leader>e3", function() harpoon:list():select(3)  end)
vim.keymap.set("n", "<leader>e4", function() harpoon:list():select(4)  end)
vim.keymap.set("n", "<leader>e5", function() harpoon:list():select(5)  end)
vim.keymap.set("n", "<leader>e6", function() harpoon:list():select(6)  end)
vim.keymap.set("n", "<leader>e7", function() harpoon:list():select(7)  end)
vim.keymap.set("n", "<leader>e8", function() harpoon:list():select(8)  end)
vim.keymap.set("n", "<leader>e9", function() harpoon:list():select(9)  end)
vim.keymap.set("n", "<leader>e0", function() harpoon:list():select(10) end)
