require("nvim-treesitter-textobjects").setup({
  select = {
    lookahead = true,
    selection_modes = { -- default is "v", charwise
      ["@function.outer"] = "V", -- linewise
      ["@conditional.outer"] = "V",
      ["@class.outer"] = "V",
    },
    include_surrounding_whitespace = true,
  },
  move = {
    set_jumps = false,
  },
})

local select = require("nvim-treesitter-textobjects.select")

vim.keymap.set({ "x", "o" }, "a,", function() select.select_textobject("@parameter.outer", "textobjects") end)
vim.keymap.set({ "x", "o" }, "i,", function() select.select_textobject("@parameter.inner", "textobjects") end)

vim.keymap.set({ "x", "o" }, "am", function() select.select_textobject("@function.outer", "textobjects") end)
vim.keymap.set({ "x", "o" }, "im", function() select.select_textobject("@function.inner", "textobjects") end)

-- enums, structs and classes
vim.keymap.set({ "x", "o" }, "ae", function() select.select_textobject("@class.outer", "textobjects") end)
vim.keymap.set({ "x", "o" }, "ie", function() select.select_textobject("@class.inner", "textobjects") end)

vim.keymap.set({ "x", "o" }, "ac", function() select.select_textobject("@comment.outer", "textobjects") end)
-- TODO: @comment.inner doesn't exist, fix that

vim.keymap.set({ "x", "o" }, "ai", function() select.select_textobject("@conditional.outer", "textobjects") end)
vim.keymap.set({ "x", "o" }, "ii", function() select.select_textobject("@conditional.inner", "textobjects") end)

local swap = require("nvim-treesitter-textobjects.swap")

-- TODO: <, and >, should be noop if on the first/last parameter in a parameter list
vim.keymap.set("n", "<,", function() swap.swap_previous "@parameter.inner" end)
vim.keymap.set("n", ">,", function() swap.swap_next "@parameter.inner" end)

vim.keymap.set("n", "<m", function() swap.swap_previous "@function.outer" end)
vim.keymap.set("n", ">m", function() swap.swap_next "@function.outer" end)

vim.keymap.set("n", "<e", function() swap.swap_previous "@class.outer" end)
vim.keymap.set("n", ">e", function() swap.swap_next "@class.outer" end)

vim.keymap.set("n", "<c", function() swap.swap_previous "@comment.outer" end)
vim.keymap.set("n", ">c", function() swap.swap_next "@comment.outer" end)

vim.keymap.set("n", "<i", function() swap.swap_previous "@conditional.outer" end)
vim.keymap.set("n", ">i", function() swap.swap_next "@conditional.outer" end)

local move = require("nvim-treesitter-textobjects.move")

vim.keymap.set({ "n", "x", "o" }, "[,", function() move.goto_previous_start("@parameter.inner", "textobjects") end)
vim.keymap.set({ "n", "x", "o" }, "],", function() move.goto_next_start("@parameter.inner", "textobjects") end)

vim.keymap.set({ "n", "x", "o" }, "[m", function() move.goto_previous_start("@function.outer", "textobjects") end)
vim.keymap.set({ "n", "x", "o" }, "]m", function() move.goto_next_start("@function.outer", "textobjects") end)
vim.keymap.set({ "n", "x", "o" }, "[M", function() move.goto_previous_end("@function.outer", "textobjects") end)
vim.keymap.set({ "n", "x", "o" }, "]M", function() move.goto_next_end("@function.outer", "textobjects") end)

vim.keymap.set({ "n", "x", "o" }, "[e", function() move.goto_previous_start("@class.outer", "textobjects") end)
vim.keymap.set({ "n", "x", "o" }, "]e", function() move.goto_next_start("@class.outer", "textobjects") end)
vim.keymap.set({ "n", "x", "o" }, "[E", function() move.goto_previous_end("@class.outer", "textobjects") end)
vim.keymap.set({ "n", "x", "o" }, "]E", function() move.goto_next_end("@class.outer", "textobjects") end)

vim.keymap.set({ "n", "x", "o" }, "[c", function() move.goto_previous_start("@comment.outer", "textobjects") end)
vim.keymap.set({ "n", "x", "o" }, "]c", function() move.goto_next_start("@comment.outer", "textobjects") end)
vim.keymap.set({ "n", "x", "o" }, "[C", function() move.goto_previous_end("@comment.outer", "textobjects") end)
vim.keymap.set({ "n", "x", "o" }, "]C", function() move.goto_next_end("@comment.outer", "textobjects") end)

vim.keymap.set({ "n", "x", "o" }, "[i", function() move.goto_previous_start("@conditional.outer", "textobjects") end)
vim.keymap.set({ "n", "x", "o" }, "]i", function() move.goto_next_start("@conditional.outer", "textobjects") end)
vim.keymap.set({ "n", "x", "o" }, "[I", function() move.goto_previous_end("@conditional.outer", "textobjects") end)
vim.keymap.set({ "n", "x", "o" }, "]I", function() move.goto_next_end("@conditional.outer", "textobjects") end)

local repeatable_move = require("nvim-treesitter-textobjects.repeatable_move")

-- Make the movements work with ; and ,
-- Absolute directions - moves are prev/next regardless of last direction
vim.keymap.set({ "n", "x", "o" }, ";", repeatable_move.repeat_last_move_next)
vim.keymap.set({ "n", "x", "o" }, ",", repeatable_move.repeat_last_move_previous)

-- Make it so f, t, F and T still work with ; and ,
-- Note that this overrides default behavior with absolute directions, which is fine
vim.keymap.set({ "n", "x", "o" }, "f", repeatable_move.builtin_f_expr, { expr = true })
vim.keymap.set({ "n", "x", "o" }, "F", repeatable_move.builtin_F_expr, { expr = true })
vim.keymap.set({ "n", "x", "o" }, "t", repeatable_move.builtin_t_expr, { expr = true })
vim.keymap.set({ "n", "x", "o" }, "T", repeatable_move.builtin_T_expr, { expr = true })
