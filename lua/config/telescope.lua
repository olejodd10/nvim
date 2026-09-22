local telescope = require('telescope')

telescope.setup({
    defaults = {
        mappings = {
            i = {
                ['<C-u>'] = 'results_scrolling_up',
                ['<C-d>'] = 'results_scrolling_down',
                ['<PageUp>'] = 'preview_scrolling_up',
                ['<PageDown>'] = 'preview_scrolling_down',
            },
            n = {
                ['<C-u>'] = 'results_scrolling_up',
                ['<C-d>'] = 'results_scrolling_down',
                ['<PageUp>'] = 'preview_scrolling_up',
                ['<PageDown>'] = 'preview_scrolling_down',
            },
        },
    },
})

local util = require('lspconfig.util')

local function project_root()
  local bufname = vim.api.nvim_buf_get_name(0)
  local root = util.root_pattern(
    '.git',
    'compile_commands.json',
    'CMakeLists.txt'
  )(bufname)
  if root then
    return root
  end
  return vim.uv.cwd()
end

local function from_project_root(func)
  return function ()
    func({ cwd = project_root() })
  end
end

local function with_default(func)
  return function()
    vim.cmd('noau normal! "zy')
    local selection = vim.fn.getreg('z')
    func({ cwd = project_root(), default_text = selection })
  end
end

local builtin = require('telescope.builtin')

vim.keymap.set('n', '<leader>ff', from_project_root(builtin.find_files))
vim.keymap.set('n', '<leader>fg', from_project_root(builtin.live_grep))
vim.keymap.set('n', '<leader>fb', from_project_root(builtin.buffers))
vim.keymap.set('n', '<leader>fh', from_project_root(builtin.help_tags)) -- Path probably doesn't matter
vim.keymap.set('n', '<leader>fw', from_project_root(builtin.grep_string))
vim.keymap.set('n', '<leader>fs', from_project_root(builtin.git_files))
vim.keymap.set('n', '<leader>fo', from_project_root(builtin.vim_options))
vim.keymap.set('n', '<leader>fk', from_project_root(builtin.keymaps))
vim.keymap.set('n', '<leader>fc', from_project_root(builtin.commands))
vim.keymap.set('n', '<leader>fø', from_project_root(builtin.command_history)) -- Tenk qø
vim.keymap.set('n', '<leader>fæ', from_project_root(builtin.search_history)) -- Tenk qæ

vim.keymap.set('x', '<leader>fg', with_default(builtin.live_grep))
vim.keymap.set('x', '<leader>ff', with_default(builtin.find_files))
vim.keymap.set('x', '<leader>fb', with_default(builtin.buffers))
vim.keymap.set('x', '<leader>fh', with_default(builtin.help_tags))
vim.keymap.set('x', '<leader>fw', from_project_root(builtin.grep_string)) -- grep_string kinda does with_default by default
vim.keymap.set('x', '<leader>fs', with_default(builtin.git_files))
vim.keymap.set('x', '<leader>fo', with_default(builtin.vim_options))
vim.keymap.set('x', '<leader>fk', with_default(builtin.keymaps))
vim.keymap.set('x', '<leader>fc', with_default(builtin.commands))
vim.keymap.set('x', '<leader>fø', with_default(builtin.command_history))
vim.keymap.set('x', '<leader>fæ', with_default(builtin.search_history))
