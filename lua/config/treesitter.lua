local parsers = {
    'bash',

    'lua',
    'vim',

    'rust',
    'toml',

    'python',
    'requirements',

    'c',
    'cmake',
    'cpp',
    'devicetree',
    'kconfig',
    'linkerscript',
    'make',

    'css',
    'html',
    'javascript',

    'dockerfile',
    'yaml',

    'diff',
    'git_rebase',
    'gitcommit',
    'gitignore',

    'bitbake',
    'csv',
    'json',
    'markdown',
    'rst',
    'ssh_config',
    'xml',

    'comment',
    'printf',
    'regex',
}

require('nvim-treesitter').install(parsers):wait(300000) -- wait max. 5 minutes

vim.api.nvim_create_autocmd('FileType', {
    callback = function(args)
        local lang = vim.treesitter.language.get_lang(args.match)
        if not lang then
            return
        end

        if lang ~= 'NvimTree' and not vim.treesitter.language.add(lang) then
            vim.notify('No treesitter parser for ' .. lang)
            return
        end

        if vim.treesitter.query.get(lang, 'highlights') then
            vim.treesitter.start()
        end

        if vim.treesitter.query.get(lang, 'folds') then
            vim.wo[0][0].foldexpr = 'v:lua.vim.treesitter.foldexpr()'
            vim.wo[0][0].foldmethod = 'expr' -- Disables manual zf-folding
            vim.cmd('normal! zR') -- Open all folds
            vim.cmd('normal! zi') -- Hide all folds
        end

        -- Treesitter-based indentation is considered experimental
    end,
})
