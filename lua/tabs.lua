-- Nice default tab commands: gt, gT, g<Tab>/<C-Tab>
vim.keymap.set("n", "<M-l>", vim.cmd.tabnext)
vim.keymap.set("n", "<M-h>", vim.cmd.tabprevious)
vim.keymap.set("n", "<M-j>", vim.cmd.tabclose)
vim.keymap.set("n", "<M-k>", vim.cmd.tabs)
vim.keymap.set("n", "<leader>t", vim.cmd.tabnew)

vim.keymap.set("n", "<M-1>", function() vim.cmd.tabnext(1)  end)
vim.keymap.set("n", "<M-2>", function() vim.cmd.tabnext(2)  end)
vim.keymap.set("n", "<M-3>", function() vim.cmd.tabnext(3)  end)
vim.keymap.set("n", "<M-4>", function() vim.cmd.tabnext(4)  end)
vim.keymap.set("n", "<M-5>", function() vim.cmd.tabnext(5)  end)
vim.keymap.set("n", "<M-6>", function() vim.cmd.tabnext(6)  end)
vim.keymap.set("n", "<M-7>", function() vim.cmd.tabnext(7)  end)
vim.keymap.set("n", "<M-8>", function() vim.cmd.tabnext(8)  end)
vim.keymap.set("n", "<M-9>", function() vim.cmd.tabnext(9)  end)
vim.keymap.set("n", "<M-0>", function() vim.cmd.tabnext(10) end)

-- Workaround for vim.cmd.tabmove(n) having
-- no effect if current tab is n+1
local function tabmove(n)
    vim.cmd.tabmove(0)
    if n > 0 then
        vim.cmd.tabmove("+" .. tostring(n))
    end
end

vim.keymap.set("n", "<M-S-1>", function() tabmove(0) end)
vim.keymap.set("n", "<M-S-2>", function() tabmove(1) end)
vim.keymap.set("n", "<M-S-3>", function() tabmove(2) end)
vim.keymap.set("n", "<M-S-4>", function() tabmove(3) end)
vim.keymap.set("n", "<M-S-5>", function() tabmove(4) end)
vim.keymap.set("n", "<M-S-6>", function() tabmove(5) end)
vim.keymap.set("n", "<M-S-7>", function() tabmove(6) end)
vim.keymap.set("n", "<M-S-8>", function() tabmove(7) end)
vim.keymap.set("n", "<M-S-9>", function() tabmove(8) end)
vim.keymap.set("n", "<M-S-0>", function() tabmove(9) end)
