local M = {}

M.word_nr_before = "WordNrBefore"
M.cursor_column_nr = "CursorColumnNr"
M.word_nr_after =  "WordNrAfter"

local function stylize(str, style)
  return "%#" .. style .. "#" .. str .. "%*"
end

function M.stylize_number_line(number_line, cursor_display_start, cursor_display_width)
  local before = number_line:sub(1, cursor_display_start - 1)
  local cursor = number_line:sub(cursor_display_start, cursor_display_start + cursor_display_width - 1)
  local after = number_line:sub(cursor_display_start + cursor_display_width)

  return stylize(before, M.word_nr_before)
    .. stylize(cursor, M.cursor_column_nr)
    .. stylize(after, M.word_nr_after)
end

return M
