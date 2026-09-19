local client = require("gdb_mi.broker_client")
local signs = require("gdb_mi.signs")

local function connect_and_run()
    if client.is_connected() then
        vim.cmd.GdbMiRun()
    else
        vim.cmd.GdbMiConnect()
        -- Do not run immediately, because we may want to set breakpoints first
    end
end

local function get_current_location()
    local win_id = vim.api.nvim_get_current_win()
    local buf_id = vim.api.nvim_win_get_buf(win_id)
    local file = vim.api.nvim_buf_get_name(buf_id)
    local line = vim.api.nvim_win_get_cursor(win_id)[1]
    return file, line
end

local function get_current_bp()
    local file, line = get_current_location()
    return signs.get_bp_id(file, line)
end

local function cond_autofill()
    local bp_id = get_current_bp()
    local autofill = ":GdbMiCond "
    if bp_id then
        autofill = autofill .. tostring(bp_id) .. " "
    end
    vim.api.nvim_input(autofill)
end

local function format_location(file, line)
    return string.format("%s:%s", file, line)
end

local function set_bp(file, line, temp)
    local location = format_location(file, line)
    if (temp) then
        vim.cmd.GdbMiTbreak(location)
    else
        vim.cmd.GdbMiBreak(location)
    end
end

local function delete_bp(file, line)
    local bp_id = signs.get_bp_id(file, line)
    if bp_id then
        vim.cmd.GdbMiDelete(tostring(bp_id))
    end
end

local function toggle_bp_at_current_location(temp)
    local file, line = get_current_location()
    if not signs.has_breakpoint(file, line) then
        set_bp(file, line, temp)
    else
        delete_bp(file, line)
    end
end

local function until_current_location()
    local file, line = get_current_location()
    local location = format_location(file, line)
    vim.cmd.GdbMiUntil(location)
end

-- Many of the "function() ... end" blocks below are not needed, but keeping them makes editing easier

-- Execution
vim.keymap.set("n", "<F5>", function() connect_and_run() end)

-- Think hjkl but using the function keys
vim.keymap.set("n", "<F11>", function() vim.cmd.GdbMiContinue() end) -- TODO only continue if there are no breakpoints or watchpoints, infolog otherwise. But this needs watchpoint tracking. Copilot food
vim.keymap.set("n", "<F10>", function() vim.cmd.GdbMiNext() end)
vim.keymap.set("n", "<F12>", function() vim.cmd.GdbMiStep() end)
vim.keymap.set("n", "<F9>", function() vim.cmd.GdbMiFinish() end)

-- Breakpoints
vim.keymap.set("n", "<leader>gpp", function() toggle_bp_at_current_location(false) end)
vim.keymap.set("x", "<leader>gpp", [["zy:GdbMiBreak <C-r>z<CR>]])

vim.keymap.set("n", "<leader>gpt", function() toggle_bp_at_current_location(true) end)
vim.keymap.set("x", "<leader>gpt", [["zy:GdbMiTbreak <C-r>z<CR>]])

vim.keymap.set("n", "<leader>gpu", function() until_current_location() end)
vim.keymap.set("x", "<leader>gpu", [["zy:GdbMiUntil <C-r>z<CR>]])

vim.keymap.set("n", "<leader>gpw", ":GdbMiWatch <C-r><C-w>") -- No <CR> in case the word is not what is wanted
vim.keymap.set("x", "<leader>gpw", [["zy:GdbMiWatch <C-r>z<CR>]])

-- Misc
vim.keymap.set("n", "<leader>gpg", function() vim.cmd.GdbMiGotoCursor() end)
vim.keymap.set("n", "<leader>gpl", function() vim.cmd.GdbMiInfoBreakpoints() end)
vim.keymap.set("n", "<leader>gpd", ":GdbMiDelete ")
vim.keymap.set("n", "<leader>gpc", function() cond_autofill() end)
vim.keymap.set("n", "<leader>gpr", ":GdbMiSendRaw ")

-- TODO zone
-- vim.keymap.set("n", "<leader>gpq", function() vim.cmd.GdbMiDelete() end) -- Delete all breakpoints. TODO this causes problems for breakpoint signs, fix that before uncommenting
-- vim.keymap.set("n", "<leader>gpi", function() vim.cmd.GdbMiInterrupt("-a") end) -- -a flag stops all threads. Think of this as ctrl+c in the gdb client -- TODO does not work as expected
-- TODO <leader>fp - list of breakpoints, selecting one jumps to it
