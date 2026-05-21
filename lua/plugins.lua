return {
  -- Colorscheme
  {
    'zootedb0t/citruszest.nvim',
    lazy = false,
    priority = 1000,
    config = function() require('config.citruszest') end,
  },

  -- Treesitter
  {
    'nvim-treesitter/nvim-treesitter',
    lazy = false,
    build = ':TSUpdate',
    config = function() require('config.treesitter') end,
  },

  'nvim-treesitter/nvim-treesitter-context',

  -- LSP
  'neovim/nvim-lspconfig',

  -- Telescope
  {
    'nvim-telescope/telescope.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    config = function() require('config.telescope') end,
  },

  -- Git
  {
    'tpope/vim-fugitive',
    config = function() require('config.fugitive') end,
  },

  -- Comments
  {
    'numToStr/Comment.nvim',
    config = function() require('config.comment') end,
  },

  -- Documentation generator
  {
    'kkoomen/vim-doge',
    build = ':call doge#install()'
  },

  -- Smooth scrolling
  {
    'karb94/neoscroll.nvim',
    config = function() require('config.neoscroll') end,
  },

  -- File explorer
  {
    'nvim-tree/nvim-tree.lua',
    dependencies = {
      'nvim-tree/nvim-web-devicons',
    },
    config = function() require('config.nvimtree') end,
  },

  -- Copilot
  {
    'github/copilot.vim',
    init = function() vim.g.copilot_no_tab_map = true end,
    config = function() require('config.copilot') end,
  },

  -- Alignment
  {
    'junegunn/vim-easy-align',
    config = function() require('config.align') end,
  },

  -- Surrounding
  'tpope/vim-surround',

  -- Function argument navigation and text objects
  'PeterRincker/vim-argumentative',
}
