local M = {}

function M.split_chars(str)
  return vim.fn.split(str, "\\zs")
end

-- byte_index is 0-indexed, char_index is 1-indexed

function M.byte_to_char_index(str, byte_index)
    if byte_index == 0 then
        return 1
    end

    local prefix = str:sub(1, byte_index)
    return vim.fn.strchars(prefix) + 1
end

function M.char_to_byte_index(str, char_index)
    if char_index == 1 then
        return 0
    end
    local chars = M.split_chars(str)
    if char_index > #chars then
        return table.concat(chars, ""):len()
    end
    local substr = chars and table.concat(chars, "", 1, char_index - 1) or ""
    return substr:len()
end

-- Input arguments have unit chars
function M.split_at_range(str, range_start, range_width)
    local range_start_byte = M.char_to_byte_index(str, range_start) + 1
    local range_stop_byte = M.char_to_byte_index(str, range_start + range_width + 1) + 1
    local before = str:sub(1, range_start_byte - 1)
    local range = str:sub(range_start_byte, range_stop_byte - 1)
    local after = str:sub(range_stop_byte)
    return before, range, after
end

function M.truncate_at(str, char_index)
    local byte_index = M.char_to_byte_index(str, char_index) + 1
    return str:sub(1, byte_index - 1)
end

return M
