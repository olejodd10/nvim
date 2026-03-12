local util = require("lspconfig.util")

local function project_root()
  local bufname = vim.api.nvim_buf_get_name(0)

  local root = util.root_pattern(
    ".git",
    "compile_commands.json",
    "CMakeLists.txt"
  )(bufname)

  if root then
    return root
  end

  return vim.uv.cwd()
end

local builtin = require('telescope.builtin')

local function project_find_files()
  builtin.find_files({
    cwd = project_root()
  })
end

local function project_live_grep()
  builtin.live_grep({
    cwd = project_root()
  })
end

vim.keymap.set('n', '<leader>ff', project_find_files, {})
vim.keymap.set('n', '<leader>fg', project_live_grep, {})
vim.keymap.set('n', '<leader>fb', builtin.buffers, {})
vim.keymap.set('n', '<leader>fh', builtin.help_tags, {})
vim.keymap.set('n', '<leader>fw', builtin.grep_string, {})
vim.keymap.set('n', '<leader>fs', builtin.git_files, {})
