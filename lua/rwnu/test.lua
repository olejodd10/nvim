local rwnu_line = require("rwnu.line")

local function test_input_output(input, cursor_char, expected)
    local actual = rwnu_line.make_number_line(input, cursor_char)
    if actual ~= expected then
        print("FAIL:     \"" .. input .. "\" (char " .. tostring(cursor_char) .. ")")
        print("Result:   \"" .. actual .. "\"")
        print("Expected: \"" .. expected .. "\"")
    else
        print("PASS")
    end
end

local input

input =                        " hei alle sammen"
test_input_output(input, 1,    "1    2    3")
test_input_output(input, 2,    " 2   1    2")
test_input_output(input, 3,    "  3  1    2")
test_input_output(input, 4,    " 1 4 1    2")
test_input_output(input, 5,    " 1  5     2")
test_input_output(input, 6,    " 1   6    1")
test_input_output(input, 16,   " 3   2    1    16")

-- Tab tests
input =                        " hei	alle sammen"
test_input_output(input, 1,    "1       2    3")
test_input_output(input, 2,    " 2      1    2")
test_input_output(input, 3,    "  3     1    2")
test_input_output(input, 4,    " 1 4    1    2")
test_input_output(input, 5,    " 1     5     2")
test_input_output(input, 6,    " 1      6    1")
test_input_output(input, 16,   " 3      2    1    16")

test_input_output("", 1, "")

input = "    "
test_input_output(input, 1, "")
test_input_output(input, 2, "")
test_input_output(input, 3, "")
test_input_output(input, 4, "")

input = "	"
test_input_output(input, 1, "")
test_input_output(input, 2, "")
test_input_output(input, 3, "")
test_input_output(input, 4, "")

input =                     "   ✗ init.lua"
test_input_output(input, 1, "1 1 2 3   4")
test_input_output(input, 2, " 2  2 3   4")
test_input_output(input, 3, "  3 1 2   3")
test_input_output(input, 4, "   4  2   3")
test_input_output(input, 5, "  1 5 1   2")
test_input_output(input, 6, "  2  6    2")
test_input_output(input, 7, "  2 1 7   1")
