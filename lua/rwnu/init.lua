local M = {}

local rwnu_line = require("rwnu.line")
local style = require("rwnu.style")

local enabled = true

local function update(win_id)
  local offset = vim.fn.getwininfo(win_id)[1].textoff

  local row, cursor_byte = unpack(vim.api.nvim_win_get_cursor(win_id))
  local line = vim.api.nvim_buf_get_lines(
    vim.api.nvim_win_get_buf(win_id),
    row - 1,
    row,
    false
  )[1] or ""

  -- cursor_byte is 0-indexed, cursor_char is 1-indexed
  local cursor_char = rwnu_line.byte_to_char_index(line, cursor_byte)

  -- Note that the cursor number is positioned using the display column of the cursor,
  -- but shows the character index, which may be different (think tabs).
  local padding = string.rep(" ", offset)
  local number_line, cursor_display_start, cursor_display_width = rwnu_line.make_number_line(line, cursor_char)
  if number_line ~= "" then
      local stylized_number_line = style.stylize_number_line(number_line, cursor_display_start, cursor_display_width)
      vim.wo[win_id].winbar = padding .. stylized_number_line
  else
      vim.wo[win_id].winbar = padding
  end
end

local function window_is_floating(win_id)
    return vim.api.nvim_win_get_config(win_id).relative ~= ""
end

local function update_all()
  local win_ids = vim.api.nvim_list_wins()
  for _, win_id in ipairs(win_ids) do
      if not window_is_floating(win_id) then
          update(win_id)
      end
  end
end

local function clear(win_id)
    vim.wo[win_id].winbar = ""
end

local function clear_all()
  local win_ids = vim.api.nvim_list_wins()
  for _, win_id in ipairs(win_ids) do
      if not window_is_floating(win_id) then
          clear(win_id)
      end
  end
end

function M.enable()
  local group = vim.api.nvim_create_augroup(
    "RelativeWordNumbers",
    { clear = true }
  )

  vim.api.nvim_set_hl(0, style.word_nr_before, { link = "LineNrAbove", })
  vim.api.nvim_set_hl(0, style.cursor_column_nr, { link = "CursorLineNr", })
  vim.api.nvim_set_hl(0, style.word_nr_after, { link = "LineNrBelow", })

  vim.api.nvim_create_autocmd({
    "CursorMoved",
    "CursorMovedI",
    "BufEnter",
    "WinEnter",
    "WinScrolled",
    "VimResized",
  }, {
    group = group,
    callback = function()
        local current_win = vim.api.nvim_get_current_win()
        if not window_is_floating(current_win) then
            update(current_win)
        end
    end,
  })

  enabled = true
  update_all()
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

  if opts.enabled ~= false then
    M.enable()
  end
end

return M
