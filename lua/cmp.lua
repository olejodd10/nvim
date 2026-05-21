vim.o.autocomplete = true
vim.o.complete = 'o,.^2,w^2,b^2,u^2,t^2' -- limit everything except omnifunc to two suggestions. Can also limit with vim.o.pumheight
vim.opt.completeopt = { 'menuone', 'noinsert', 'popup', 'fuzzy' }
