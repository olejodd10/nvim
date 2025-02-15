local ls = require("luasnip")

require("luasnip.loaders.from_vscode").load()

vim.keymap.set({ "i", "s" }, "<C-l>", function() if ls.expand_or_jumpable() then ls.expand_or_jump() end end, { silent = true })
vim.keymap.set({ "i", "s" }, "<C-h>", function() if ls.jumpable(-1) then ls.jump(-1) end end, { silent = true })

local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node

local fmt = require("luasnip.extras.fmt").fmt

ls.add_snippets("c", {
    s("funksjon",
        fmt("{} {}({}) {{\n\t{}\n}}", {i(1, "int"), i(2, "func"), i(3, "void"), i(0)})
    ),
    s("hvis",
        fmt("if ({}) {{\n\t{}\n}} else {{\n\t{}\n}}", {i(1, "condition"), i(2), i(0)})
    ),
    s("svitsj",
        fmt("switch ({}) {{\ncase {}:\n\t{}\n\tbreak;\ndefault:\n\tbreak;\n}}", {i(1, "condition"), i(2, "case"), i(0)})
    ),
})
