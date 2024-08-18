local function my_on_attach(bufnr)
    local api = require "nvim-tree.api"

    local function opts(desc)
        return { desc = "nvim-tree: " .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
    end

    -- default mappings
    api.config.mappings.default_on_attach(bufnr)

    -- custom mappings
    vim.keymap.set('n', 'gn', api.tree.change_root_to_node, opts('CD'))
    vim.keymap.set('n', '<leader>r', api.node.open.vertical, opts('Open: Vertical Split'))
    vim.keymap.set('n', '<leader>t', api.node.open.tab, opts('Open: New Tab'))
    vim.keymap.set('n', '<CR>', function()
        local node = api.tree.get_node_under_cursor()
        api.node.open.edit()
        if node.name ~= ".." and not node.nodes then -- If cursor is over a file
            vim.cmd.NvimTreeClose()
        end
    end, opts('Open'))
end

require("nvim-tree").setup({
    disable_netrw = true,
    sort = {
        sorter = "case_sensitive",
    },
    view = {
        width = 30,
        number = true,
        relativenumber = true,
    },
    renderer = {
        group_empty = true,
    },
    filters = {
        dotfiles = true,
    },
    on_attach = my_on_attach,
})

vim.keymap.set("n", "<leader>b", vim.cmd.NvimTreeToggle)
