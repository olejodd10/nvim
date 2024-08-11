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
})

vim.keymap.set("n", "<leader>b", vim.cmd.NvimTreeToggle)
