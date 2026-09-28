local api = require "nvim-tree.api"

local function only_if_not_root(fn)
    return function()
        local node = api.tree.get_node_under_cursor()
        if node.name ~= ".." then
            fn()
        end
    end
end

local function open_then_close_if_file()
    local node = api.tree.get_node_under_cursor()
    api.node.open.edit()
    if not node.nodes then
        vim.cmd.NvimTreeClose()
    end
end

local function on_attach(bufnr)
  local function opts(desc)
    return { desc = "nvim-tree: " .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
  end

  api.config.mappings.default_on_attach(bufnr)

  vim.keymap.set('n', 'gn', api.tree.change_root_to_node, opts('CD'))
  vim.keymap.set('n', '<leader>r', only_if_not_root(api.node.open.vertical), opts('Open: Vertical Split'))
  vim.keymap.set('n', '<leader>t', only_if_not_root(api.node.open.tab), opts('Open: New Tab'))
  vim.keymap.set('n', '<leader><CR>', only_if_not_root(api.node.open.edit), opts('Open'))
  vim.keymap.set('n', '<CR>', only_if_not_root(open_then_close_if_file), opts('Open'))
  vim.keymap.set('n', 'o', only_if_not_root(open_then_close_if_file), opts('Open'))
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
    -- root_folder_label = false, -- TODO: Consider this and removing only_if_not_root
  },
  filters = {
    dotfiles = true,
  },
  on_attach = on_attach,
})

vim.keymap.set("n", "<leader>b", vim.cmd.NvimTreeToggle)
