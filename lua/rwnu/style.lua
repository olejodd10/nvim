local M = {}

M.word_nr_before = "WordNrBefore"
M.cursor_column_nr = "CursorColumnNr"
M.word_nr_after =  "WordNrAfter"

M.word_nr_before_overlay = "WordNrBeforeOverlay"
M.cursor_column_nr_overlay = "CursorColumnNrOverlay"
M.word_nr_after_overlay = "WordNrAfterOverlay"

local utf8 = require("rwnu.utf8")

local function stylize(str, style)
  return "%#" .. style .. "#" .. str .. "%*"
end

function M.stylize_number_line(number_line, cursor_display_start, cursor_display_width)
  local before, cursor, after = utf8.split_at_range(number_line, cursor_display_start, cursor_display_width)
  return stylize(before, M.word_nr_before)
    .. stylize(cursor, M.cursor_column_nr)
    .. stylize(after, M.word_nr_after)
end

-- TODO rename to stylize_number_line_overlay? The return styles leak internals anyway
function M.stylize_number_line_tuples(number_line, cursor_display_start, cursor_display_width)
  local before, cursor, after = utf8.split_at_range(number_line, cursor_display_start, cursor_display_width)
  return {
      {before, M.word_nr_before_overlay},
      {cursor, M.cursor_column_nr_overlay},
      {after, M.word_nr_after_overlay},
  }
end

function M.get_overlay_style(cursor_display_start, cursor_display_width, column)
    if column < cursor_display_start then
        return M.word_nr_before_overlay
    elseif column > (cursor_display_start + cursor_display_width - 1) then
        return M.word_nr_after_overlay
    else
        return M.cursor_column_nr_overlay
    end
end

return M
