local function navshow()
    vim.cmd.buffers()
end
local function navright()
    vim.cmd.bnext()
end
local function navleft()
    vim.cmd.bprevious()
end
local function navdelete()
    vim.cmd.bdelete()
end
local function navindex(i)
    vim.cmd.bfirst()
    if (i ~= 0) then
        vim.cmd(string.format("bnext %d", i))
    end
    navshow()
end

vim.keymap.set("", "<M-right>", navright) -- Consider just <right> and <left>
vim.keymap.set("", "<M-left>", navleft)
vim.keymap.set("", "<M-down>", navdelete)
vim.keymap.set("", "<M-up>", navshow)
vim.keymap.set("", "<M-l>", navright)
vim.keymap.set("", "<M-h>", navleft)
vim.keymap.set("", "<M-j>", navdelete)
vim.keymap.set("", "<M-k>", navshow)

vim.keymap.set("", "<M-1>", function() navindex(0) end)
vim.keymap.set("", "<M-2>", function() navindex(1) end)
vim.keymap.set("", "<M-3>", function() navindex(2) end)
vim.keymap.set("", "<M-4>", function() navindex(3) end)
vim.keymap.set("", "<M-5>", function() navindex(4) end)
vim.keymap.set("", "<M-6>", function() navindex(5) end)
vim.keymap.set("", "<M-7>", function() navindex(6) end)
vim.keymap.set("", "<M-8>", function() navindex(7) end)
vim.keymap.set("", "<M-9>", function() navindex(8) end)
vim.keymap.set("", "<M-0>", function() navindex(9) end)
