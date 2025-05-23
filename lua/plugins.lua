-- This file can be loaded by calling `lua require('plugins')` from your init.vim

-- Only required if you have packer configured as `opt`
vim.cmd [[packadd packer.nvim]]

return require('packer').startup(function(use)
  -- Packer can manage itself
  use 'wbthomason/packer.nvim'

  use {
	  'nvim-telescope/telescope.nvim', tag = '0.1.2',
	  requires = { {'nvim-lua/plenary.nvim'} }
  }

  use 'zootedb0t/citruszest.nvim'

  use {
	  'nvim-treesitter/nvim-treesitter',
	  run = function()
		  local ts_update = require('nvim-treesitter.install').update({ with_sync = true })
		  ts_update()
	  end,
  }
  
  use 'mbbill/undotree'
  use 'tpope/vim-fugitive'
  

  use "numToStr/Comment.nvim"

  use {
      'kkoomen/vim-doge',
      run = ':call doge#install()'
  }

  use 'karb94/neoscroll.nvim'

  use {
      'nvim-tree/nvim-tree.lua',
      requires = {
          'nvim-tree/nvim-web-devicons', -- https://www.nerdfonts.com/font-downloads
      },
  }

  use 'nvim-treesitter/nvim-treesitter-context'


  -- LSP and autocomplete
  use 'neovim/nvim-lspconfig'
  use 'hrsh7th/nvim-cmp'
  use 'hrsh7th/cmp-nvim-lsp'
  use 'saadparwaiz1/cmp_luasnip'
  use { 'L3MON4D3/LuaSnip',
        requires = 'rafamadriz/friendly-snippets', -- https://github.com/folke/lazy.nvim/issues/266#issuecomment-1368271202
      }

end)
