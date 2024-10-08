local function navshow()
    vim.cmd.buffers()
end
local function navprev()
    vim.cmd(":b#")
    navshow()
end
local function navright()
    vim.cmd.bnext()
    navshow()
end
local function navleft()
    vim.cmd.bprevious()
    navshow()
end
local function navdelete()
    vim.cmd.bdelete()
    navshow()
end
local function navindex(i)
    vim.cmd.bfirst()
    if (i ~= 0) then
        vim.cmd(string.format("bnext %d", i))
    end
    navshow()
end

vim.keymap.set("n", "<M-p>", navprev) 
vim.keymap.set("n", "<M-right>", navright) -- Consider just <right> and <left>
vim.keymap.set("n", "<M-left>", navleft)
vim.keymap.set("n", "<M-down>", navdelete)
vim.keymap.set("n", "<M-up>", navshow)

vim.keymap.set("n", "<M-1>", function() navindex(0) end)
vim.keymap.set("n", "<M-2>", function() navindex(1) end)
vim.keymap.set("n", "<M-3>", function() navindex(2) end)
vim.keymap.set("n", "<M-4>", function() navindex(3) end)
vim.keymap.set("n", "<M-5>", function() navindex(4) end)
vim.keymap.set("n", "<M-6>", function() navindex(5) end)
vim.keymap.set("n", "<M-7>", function() navindex(6) end)
vim.keymap.set("n", "<M-8>", function() navindex(7) end)
vim.keymap.set("n", "<M-9>", function() navindex(8) end)
vim.keymap.set("n", "<M-0>", function() navindex(9) end)
