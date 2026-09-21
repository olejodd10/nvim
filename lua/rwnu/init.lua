local M = {}

local utf8 = require("rwnu.utf8")
local rwnu_line = require("rwnu.line")
local style = require("rwnu.style")

local in_subscript = false
local in_superscript = false

local enabled = true

local last_pos = nil
local row_diff_limit = 2 -- The minimum row movement required for drawing overlay

local winbar_enabled = true

local overlay_enabled = true
local overlay_extmark_ns = vim.api.nvim_create_namespace('rwnu')
local overlay_offset = 1

local function clear_winbar(win_id)
    vim.wo[win_id].winbar = ""
end

local function clear_overlay(buf_id)
    vim.api.nvim_buf_clear_namespace(buf_id, overlay_extmark_ns, 0, -1)
end

local function clear(win_id)
    if overlay_enabled then
        local buf_id = vim.api.nvim_win_get_buf(win_id)
        clear_overlay(buf_id)
    end
    if winbar_enabled then
        clear_winbar(win_id)
    end

    last_pos = nil
end

local function window_is_floating(win_id)
    return vim.api.nvim_win_get_config(win_id).relative ~= ""
end

local function clear_all()
  local win_ids = vim.api.nvim_list_wins()
  for _, win_id in ipairs(win_ids) do
      if not window_is_floating(win_id) then
          clear(win_id)
      end
  end
end

local function draw_winbar(win_id, number_line, cursor_display_start, cursor_display_width)
  local offset = vim.fn.getwininfo(win_id)[1].textoff

  -- Note that the cursor number is positioned using the display column of the cursor,
  -- but shows the character index, which may be different (think tabs).
  local padding = string.rep(" ", offset)
  local win_width = vim.api.nvim_win_get_width(win_id)
  local truncated_number_line = utf8.truncate_at(number_line, win_width - offset + 1) -- Truncate because winbar does not handle line wrapping well
  if truncated_number_line ~= "" then
      local stylized_number_line = style.stylize_number_line(truncated_number_line, cursor_display_start, cursor_display_width)
      vim.wo[win_id].winbar = padding .. stylized_number_line
  else
      vim.wo[win_id].winbar = padding
  end
end

-- row is 0-indexed here
local function row_in_buffer(buf_id, row)
    local buf_lines = vim.api.nvim_buf_line_count(buf_id)
    return row >= 0 and row < buf_lines
end

-- row is 0-indexed here
local function row_below_buffer(buf_id, row)
    local buf_lines = vim.api.nvim_buf_line_count(buf_id)
    return row >= buf_lines
end

local function draw_overlay_row_inline(number_line_table, cursor_display_start, cursor_display_width, buf_id, overlay_row)
    for k, v in pairs(number_line_table) do
        local char_style = style.get_overlay_style(cursor_display_start, cursor_display_width, k)
        local opts = {
            id = k,
            virt_text = {{v, char_style}},
            virt_text_win_col = k - 1,
        }

        vim.api.nvim_buf_set_extmark(buf_id, overlay_extmark_ns, overlay_row, 0, opts)
    end
end

local function draw_overlay_row_eof(number_line_table, cursor_display_start, cursor_display_width, buf_id, overlay_row)
    local number_line = rwnu_line.make_number_line_from_table(number_line_table)
    local virt_line = style.stylize_number_line_tuples(number_line, cursor_display_start, cursor_display_width)
    local opts = {
        id = overlay_row,
        virt_lines = {virt_line},
        virt_lines_above = true,
    }
    vim.api.nvim_buf_set_extmark(buf_id, overlay_extmark_ns, overlay_row, 0, opts)
end

local function diff(a, b)
    if a > b then
        return a - b
    else
        return b - a
    end
end

local function movement_qualifies_for_overlay(win_id, row)
    if not last_pos then
        -- On the initial movement we rarely want a word motion - skip
        return false
    elseif last_pos.win_id ~= win_id then
        -- When entering a window we rarely want a word motion - skip
        return false
    else
        -- We have moved within the window - check whether movement is significant
        return diff(last_pos.row, row) >= row_diff_limit
    end
end

local function draw_overlay(buf_id, row, number_line_table, cursor_display_start, cursor_display_width)
    local overlay_row = row - 1 + overlay_offset
    if row_in_buffer(buf_id, overlay_row) then
        draw_overlay_row_inline(number_line_table, cursor_display_start, cursor_display_width, buf_id, overlay_row)
    elseif row_below_buffer(buf_id, overlay_row) then
        local line_count = vim.api.nvim_buf_line_count(buf_id)
        overlay_row = math.max(1, math.min(line_count, overlay_row)) -- overlay_row will be zero if buffer is empty
        draw_overlay_row_eof(number_line_table, cursor_display_start, cursor_display_width, buf_id, overlay_row)
    end
end

local function on_movement(win_id)
    if window_is_floating(win_id) then
        return
    end

    local buf_id = vim.api.nvim_win_get_buf(win_id)

    local row, col = unpack(vim.api.nvim_win_get_cursor(win_id))
    local line = vim.api.nvim_buf_get_lines(
      vim.api.nvim_win_get_buf(win_id),
      row - 1,
      row,
      false
    )[1] or ""

    -- col is 0-indexed, cursor_char is 1-indexed
    local cursor_char = utf8.byte_to_char_index(line, col)

    -- Note that the cursor number is positioned using the display column of the cursor,
    -- but shows the character index, which may be different (think tabs).

    clear_overlay(buf_id)

    if overlay_enabled and movement_qualifies_for_overlay(win_id, row) then
        local number_line_table, cursor_display_start, cursor_display_width = rwnu_line.make_number_line_table(line, cursor_char, in_subscript, in_superscript)
        draw_overlay(buf_id, row, number_line_table, cursor_display_start, cursor_display_width)
    end

    if winbar_enabled then
        -- A bit wasteful to not reuse the number line table here,
        -- but we do it to avoid sub-/superscript in winbar
        local number_line, cursor_display_start, cursor_display_width = rwnu_line.make_number_line(line, cursor_char, false, false)
        draw_winbar(win_id, number_line, cursor_display_start, cursor_display_width)
    end

    last_pos = {
        row = row,
        win_id = win_id,
    }
end

local function draw_all()
  local win_ids = vim.api.nvim_list_wins()
  for _, win_id in ipairs(win_ids) do
      -- Not ideal but quite close to what we want
      on_movement(win_id)
  end
end

local function link_styles()
  vim.api.nvim_set_hl(0, style.word_nr_before, { link = "LineNrAbove", })
  vim.api.nvim_set_hl(0, style.cursor_column_nr, { link = "CursorLineNr", })
  vim.api.nvim_set_hl(0, style.word_nr_after, { link = "LineNrBelow", })

  vim.api.nvim_set_hl(0, style.word_nr_before_overlay, { link = "LineNrAbove", })
  vim.api.nvim_set_hl(0, style.cursor_column_nr_overlay, { link = "CursorLineNr", })
  vim.api.nvim_set_hl(0, style.word_nr_after_overlay, { link = "LineNrBelow", })
end

function M.enable()
  local group = vim.api.nvim_create_augroup(
    "RelativeWordNumbers",
    { clear = true }
  )

  link_styles()

  vim.api.nvim_create_autocmd({
    "CursorMoved",
    "CursorMovedI",
  }, {
    group = group,
    callback = function()
        local current_win = vim.api.nvim_get_current_win()
        on_movement(current_win)
    end,
  })

  enabled = true
  draw_all()
end

function M.disable()
  vim.api.nvim_del_augroup_by_name("RelativeWordNumbers")
  enabled = false
  clear_all()
end

function M.toggle()
  if enabled then
    M.disable()
  else
    M.enable()
  end
end

local function is_integer(n)
    return n and n == math.floor(n)
end

function M.setup(opts)
  opts = opts or {}

  vim.api.nvim_create_user_command(
    "RelativeWordNumbersToggle",
    M.toggle,
    {}
  )

  vim.api.nvim_create_user_command(
    "RelativeWordNumbersEnable",
    M.enable,
    {}
  )

  vim.api.nvim_create_user_command(
    "RelativeWordNumbersDisable",
    M.disable,
    {}
  )

  -- Disable if explicitly disabled
  if opts.winbar_enabled == false then
    winbar_enabled = false
  end

  -- Disable unless explicitly enabled
  if opts.overlay_enabled ~= true then
    overlay_enabled = false
  end

  if is_integer(opts.overlay_offset) then
    overlay_offset = opts.overlay_offset
  end

  -- Superscript unless explicitly disabled or subscript is enabled
  if opts.in_subscript == true then
      in_subscript = true
  elseif opts.in_superscript ~= false then
      in_superscript = true
  end

  if is_integer(opts.row_diff_limit) then
      row_diff_limit = opts.row_diff_limit
  end

  -- Disable if explicitly disabled
  if opts.enabled == false then
    enabled = false
  else
    M.enable()
  end

end

return M
