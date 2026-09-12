local harpoon = require("harpoon")

harpoon:setup()

-- e for edit
vim.keymap.set("n", "<M-e>", function() harpoon:list():add() end)
vim.keymap.set("n", "<M-q>", function() harpoon:list():remove() end)
vim.keymap.set("n", "<leader>fe", function() harpoon.ui:toggle_quick_menu(harpoon:list()) end)

vim.keymap.set("n", "<M-p>", function() harpoon:list():prev() end)
vim.keymap.set("n", "<M-n>", function() harpoon:list():next() end)

vim.keymap.set("n", "<M-1>", function() harpoon:list():select(1)  end)
vim.keymap.set("n", "<M-2>", function() harpoon:list():select(2)  end)
vim.keymap.set("n", "<M-3>", function() harpoon:list():select(3)  end)
vim.keymap.set("n", "<M-4>", function() harpoon:list():select(4)  end)
vim.keymap.set("n", "<M-5>", function() harpoon:list():select(5)  end)
vim.keymap.set("n", "<M-6>", function() harpoon:list():select(6)  end)
vim.keymap.set("n", "<M-7>", function() harpoon:list():select(7)  end)
vim.keymap.set("n", "<M-8>", function() harpoon:list():select(8)  end)
vim.keymap.set("n", "<M-9>", function() harpoon:list():select(9)  end)
vim.keymap.set("n", "<M-0>", function() harpoon:list():select(10) end)
