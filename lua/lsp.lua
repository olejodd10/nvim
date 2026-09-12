-- Unmap defaults so gr executes immediately
vim.keymap.del('n', 'gra')
vim.keymap.del('n', 'gri')
vim.keymap.del('n', 'grn')
vim.keymap.del('n', 'grr')
vim.keymap.del('n', 'grt')
vim.keymap.del('n', 'grx') -- Default is vim.lsp.codelens.run(). Only one that is not mapped below

-- Generic LSP keybindings. Specialized ones can be put in lsp/clangd.lua, for instance
-- Inspired by https://lsp-zero.netlify.app/docs/getting-started.html
vim.api.nvim_create_autocmd('LspAttach', {
  desc = 'LSP actions',
  callback = function(event)
    local opts = {buffer = event.buf}
    vim.keymap.set('n', 'K', '<cmd>lua vim.lsp.buf.hover()<cr>', opts)
    vim.keymap.set('n', 'gd', '<cmd>lua vim.lsp.buf.definition()<cr>', opts)
    vim.keymap.set('n', 'gD', '<cmd>lua vim.lsp.buf.declaration()<cr>', opts)
    vim.keymap.set('n', 'gi', '<cmd>lua vim.lsp.buf.implementation()<cr>', opts)
    vim.keymap.set('n', 'gt', '<cmd>lua vim.lsp.buf.type_definition()<cr>', opts)
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
vim.lsp.enable('rust_analyzer')

local capabilities = require('cmp_nvim_lsp').default_capabilities()

vim.lsp.config('clangd', { capabilities = capabilities })
vim.lsp.config('rust_analyzer', { capabilities = capabilities })

-- As suggested by nvim-lspconfig for Neovim development
vim.lsp.config('lua_ls', {
    capabilities = capabilities,
    on_init = function(client)
        if client.workspace_folders then
            local path = client.workspace_folders[1].name
            if
                path ~= vim.fn.stdpath('config')
                and (vim.uv.fs_stat(path .. '/.luarc.json') or vim.uv.fs_stat(path .. '/.luarc.jsonc'))
                then
                    return
                end
            end

            client.config.settings.Lua = vim.tbl_deep_extend('force', client.config.settings.Lua, {
                runtime = {
                    -- Tell the language server which version of Lua you're using (most
                    -- likely LuaJIT in the case of Neovim)
                    version = 'LuaJIT',
                    -- Tell the language server how to find Lua modules same way as Neovim
                    -- (see `:h lua-module-load`)
                    path = {
                        'lua/?.lua',
                        'lua/?/init.lua',
                    },
                },
                -- Make the server aware of Neovim runtime files
                workspace = {
                    checkThirdParty = false,
                    library = {
                        vim.env.VIMRUNTIME,
                        -- For LSP Settings Type Annotations: https://github.com/neovim/nvim-lspconfig#lsp-settings-type-annotations
                        vim.api.nvim_get_runtime_file("lua/lspconfig", false)[1],
                    },
                    -- Or pull in all of 'runtimepath'.
                    -- NOTE: this is a lot slower and will cause issues when working on
                    -- your own configuration.
                    -- See https://github.com/neovim/nvim-lspconfig/issues/3189
                    -- library = vim.api.nvim_get_runtime_file('', true),
                },
            })
        end,
        settings = {
            Lua = {},
        },
    })
