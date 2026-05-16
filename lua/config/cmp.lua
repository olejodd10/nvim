local cmp = require 'cmp'

-- TODO: Can this be replaced by a simpler omnifunc setup in the future?

cmp.setup({
    snippet = {
        -- REQUIRED - you must specify a snippet engine
        expand = function(args)
            vim.snippet.expand(args.body) -- For native neovim snippets (Neovim v0.10+)
        end,
    },
    window = {
        completion = cmp.config.window.bordered(),
        documentation = cmp.config.window.bordered(),
    },
    mapping = cmp.mapping.preset.insert(), -- Use default preset
    -- Try to keep the sources minimalistic. A window that pops up too often is just annoying
    sources = cmp.config.sources({
        { name = 'nvim_lsp' },
    })
})

-- Use buffer source for `/` and `?` (if you enabled `native_menu`, this won't work anymore).
-- Do not confuse this with the cmp-cmdline plugin, that is just for sources
cmp.setup.cmdline({ '/', '?' }, {
    mapping = cmp.mapping.preset.cmdline(), -- Tab completion is not that important here since for / and ? we actually tend to use <CR> to finish anyways
    sources = {
        { name = 'buffer' },
    }
})
