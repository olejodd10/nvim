-- Generic LSP keybindings. Specialized ones can be put in lsp/clangd.lua, for instance
-- Taken from https://lsp-zero.netlify.app/docs/getting-started.html
vim.api.nvim_create_autocmd('LspAttach', {
  desc = 'LSP actions',
  callback = function(event)
    local opts = {buffer = event.buf}
    vim.keymap.set('n', 'K', '<cmd>lua vim.lsp.buf.hover()<cr>', opts)
    vim.keymap.set('n', 'gd', '<cmd>lua vim.lsp.buf.definition()<cr>', opts)
    vim.keymap.set('n', 'gD', '<cmd>lua vim.lsp.buf.declaration()<cr>', opts)
    vim.keymap.set('n', 'gi', '<cmd>lua vim.lsp.buf.implementation()<cr>', opts)
    vim.keymap.set('n', 'go', '<cmd>lua vim.lsp.buf.type_definition()<cr>', opts)
    vim.keymap.set('n', 'gr', '<cmd>lua vim.lsp.buf.references()<cr>', opts)
    vim.keymap.set('n', 'gs', '<cmd>lua vim.lsp.buf.signature_help()<cr>', opts)
    vim.keymap.set('n', '<F2>', '<cmd>lua vim.lsp.buf.rename()<cr>', opts)
    vim.keymap.set({'n', 'x'}, '<F3>', '<cmd>lua vim.lsp.buf.format({async = true})<cr>', opts)
    vim.keymap.set('n', '<F4>', '<cmd>lua vim.lsp.buf.code_action()<cr>', opts)
  end,
})

-- Zephyr places compile_commands.json here, from which clangd can get include paths
local function get_clangd_cmd()
  local cwd = vim.loop.cwd()
  local project = vim.fn.fnamemodify(cwd, ":t")
  local build_dir = cwd .. "/build/" .. project

  if vim.fn.isdirectory(build_dir) == 1 then
    return { "clangd", "--compile-commands-dir=" .. build_dir }
  else
    return { "clangd" }
  end
end

vim.lsp.config('clangd', {
  cmd = get_clangd_cmd(),
})

-- Loads config from nvim-lspconfig. See :checkhealth vim.lsp when attached

-- https://neovim.io/doc/user/lsp.html#lsp-config
-- vim.lsp.config('clangd', {on_attach = ...}) would overwrite nvim-lspconfig default, but I want to extend it
-- ...so therefore I add an autocmd on top
vim.api.nvim_create_autocmd('LspAttach', {
  callback = function(args)
    local client = assert(vim.lsp.get_client_by_id(args.data.client_id))
    if client.name == 'clangd' then
        vim.keymap.set('n', 'gh', '<cmd>LspClangdSwitchSourceHeader<cr>', opts) -- default for gh is select mode, i.e. not useful
    end
  end,
})

vim.lsp.enable('clangd')
vim.lsp.enable('lua_ls')
