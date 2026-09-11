local M = {}

local function split_chars(line)
  return vim.fn.split(line, "\\zs")
end

local function get_words(chars)
  local words = {}
  local current

  local function start_word(char_index, class)
    current = {
      char_start = char_index,
      char_finish = char_index,
      class = class,
    }
  end

  local function finish_word()
    table.insert(words, current)
    current = nil
  end

  for char_index, char in ipairs(chars) do
    local class = vim.fn.charclass(char)

    if not current then
      if class ~= 0 then
        start_word(char_index, class)
      end
    elseif current.class == class then
      current.char_finish = char_index
    else
      finish_word()

      if class ~= 0 then
        start_word(char_index, class)
      end
    end
  end

  if current then
    finish_word()
  end

  return words
end

-- Returns the 1-based display column at which each character starts.
--
-- For example, with tabstop=4:
--
--   chars:        \t   \t   a
--   display_col:  1   5   9
--
-- The character indices remain 1, 2, 3. Only their display positions change.
local function get_display_range(chars)
  local tabstop = vim.opt.tabstop:get()

  local starts = {}
  local widths = {}
  local display_col = 1
  for char_index, char in ipairs(chars) do
    starts[char_index] = display_col

    local width
    if char == "\t" then
      width = tabstop - ((display_col - 1) % tabstop)
    else
      width = vim.fn.strdisplaywidth(char)
    end
    display_col = display_col + width
    widths[char_index] = width
  end

  return starts, widths
end

local function get_cursor_word(words, cursor_char)
  for word_index, word in ipairs(words) do
    if cursor_char == word.char_start then
      return word_index, true
    elseif cursor_char < word.char_start then
      return word_index - 1, false
    end
  end

  return #words, false
end

local function relative_number(index, cursor_word, on_cursor)
  if index < cursor_word then
    return cursor_word - index + (on_cursor and 0 or 1)
  elseif index > cursor_word then
    return index - cursor_word
  else
    return on_cursor and 0 or 1
  end
end

local function saturating_sub(a, b)
    return math.max(0, a - b)
end

local function put_string(chars, str, start_col)
  for offset = 1, #str do
    chars[start_col + offset - 1] = str:sub(offset, offset)
  end
end

local function range_is_empty(chars, start_col, end_col)
  for col = start_col, end_col do
    if chars[col] and chars[col] ~= " " then
      return false
    end
  end

  return true
end

local function get_max_key(t)
    local max_key
    for k, _ in pairs(t) do
        if not max_key or k > max_key then
            max_key = k
        end
    end
    return max_key
end

local function fill_empty_positions(chars)
  local max_key = get_max_key(chars)
  for col = 1, max_key do
    if not chars[col] then
      chars[col] = " "
    end
  end
end

function M.make_number_line(line, cursor_char)
  local chars = split_chars(line)

  if #chars == 0 then
    return "", 1, 0
  end

  -- In insertion mode the cursor can be on a nonexistent char
  if cursor_char > #chars then
      cursor_char = #chars
  end

  local words = get_words(chars)
  if #words == 0 then
    return "", 1, 0
  end

  local char_display_starts, char_display_width = get_display_range(chars)

  -- The number to show for the cursor
  local cursor_number = tostring(cursor_char)
  -- Where to show it
  local cursor_display_start = char_display_starts[cursor_char] + char_display_width[cursor_char] - 1

  --
  -- The cursor column number has priority.
  --
  -- Put it into the output first. Word numbers are added afterwards and are
  -- simply skipped if they would collide with it.
  --
  local output = {}
  put_string(output, cursor_number, cursor_display_start)

  local cursor_word, cursor_on_word_start = get_cursor_word(words, cursor_char)
  for word_index, word in ipairs(words) do
    -- What to display
    local word_number = relative_number(word_index, cursor_word, cursor_on_word_start)
    local number = tostring(word_number)

    -- Where to display it
    local word_number_display_start = char_display_starts[word.char_start]
    local word_number_display_end = word_number_display_start + #number - 1

    if range_is_empty(output, saturating_sub(word_number_display_start, 1), word_number_display_end + 1) then
      put_string(output, number, word_number_display_start)
    end
  end

  fill_empty_positions(output)

  return table.concat(output), cursor_display_start, #cursor_number
end

-- byte_index is 0-indexed, return value is 1-indexed
function M.byte_to_char_index(line, byte_index)
    if byte_index == 0 then
        return 1
    end

    local prefix = line:sub(1, byte_index)
    return vim.fn.strchars(prefix) + 1
end

return M
