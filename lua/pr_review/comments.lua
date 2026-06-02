-- pr_review.comments: Comment display and popup management

local M = {}

-- Store comment maps per buffer (buf_id -> {line_nr -> [comments]})
-- Keyed by buffer handle (integer)
M.buf_comment_maps = {}

local ns_id = vim.api.nvim_create_namespace('pr_review_comments')

-- Parse a git show/diff output to build a map of:
--   file_path -> { new_file_line_number -> buf_line_number }
-- buf_line_number is 1-indexed (the line in `lines` table)
local function parse_diff_line_map(lines)
  local map = {}
  local current_file = nil
  local new_file_line = 0

  for buf_line, line in ipairs(lines) do
    -- New file in diff ("+++ b/path")
    local file = line:match('^%+%+%+ b/(.-)%s*$')
    if file then
      current_file = file
      if not map[current_file] then
        map[current_file] = {}
      end
      new_file_line = 0
    end

    if current_file then
      -- Hunk header: @@ -old_start[,count] +new_start[,count] @@
      local new_start = line:match('^@@[^+]*%+(%d+)')
      if new_start then
        new_file_line = tonumber(new_start) - 1  -- will be incremented on first line
      elseif line:sub(1, 1) == '+' and line:sub(1, 3) ~= '+++' then
        -- Added line: counts in new file
        new_file_line = new_file_line + 1
        map[current_file][new_file_line] = buf_line
      elseif line:sub(1, 1) == ' ' then
        -- Context line: counts in both files
        new_file_line = new_file_line + 1
        map[current_file][new_file_line] = buf_line
      end
      -- '-' lines: only in old file, don't advance new_file_line
    end
  end

  return map
end

-- Check if any of the pre-filtered tip_comments apply to individual commit sha.
-- tip_comments should already be filtered to the relevant tip.
-- tip_sha: the tip's full SHA, used to detect tip-level "remap" comments
--   (GitHub stamps commit_id = tip_sha for comments from the combined Files
--    changed view; these are remapped to whichever individual commit shows
--    the file).
-- files_set: set of file paths changed by commit sha (for remap).
function M.has_comments_for_sha(sha, tip_comments, tip_sha, files_set)
  for _, c in ipairs(tip_comments) do
    local cid = c.commit_id or ''
    -- Direct match: commit_id is this individual commit's SHA
    if cid:sub(1, #sha) == sha or sha:sub(1, #cid) == cid then
      return true
    end
    -- Tip-level remap: commit_id is the tip SHA and this commit touches the file
    if tip_sha and files_set then
      local ts = tip_sha
      if (cid:sub(1, #ts) == ts or ts:sub(1, #cid) == cid) and files_set[c.path] then
        return true
      end
    end
  end
  return false
end

-- Attach inline comments to a diff buffer as virtual text indicators.
-- Comments are grouped by file+line and shown as extmarks.
-- Stores line->comments mapping in M.buf_comment_maps[buf].
-- tip_sha: the full SHA of the tip currently being reviewed. Only comments
--   pre-assigned to this tip (_tip_sha == tip_sha) are considered. Comments
--   whose commit_id matches the tip SHA (rather than an individual commit) are
--   remapped to whichever individual commit shows their file in this diff.
-- sha: the individual commit SHA being shown (nil = file-view, include all
--   tip comments that match the files visible in the diff)
function M.attach_comments(buf, sha, all_comments, tip_sha, _file_hint)
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
  M.buf_comment_maps[buf] = {}

  -- Build line map first so we know which files are visible in this diff
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local line_map = parse_diff_line_map(lines)

  local files_in_diff = {}
  for path, _ in pairs(line_map) do
    files_in_diff[path] = true
  end

  local ts = tip_sha or ''
  local commit_comments = {}
  for _, comment in ipairs(all_comments) do
    -- Only consider comments pre-assigned to this tip
    if comment._tip_sha and comment._tip_sha ~= tip_sha then goto continue end
    local cid = comment.commit_id or ''
    local path = comment.path or ''
    local include = false
    if sha then
      -- Commit view: direct SHA match or tip-level remap
      local matches_sha = (cid:sub(1, #sha) == sha or sha:sub(1, #cid) == cid)
      local tip_remap = (ts ~= '' and (cid:sub(1, #ts) == ts or ts:sub(1, #cid) == cid)
                         and files_in_diff[path])
      include = matches_sha or tip_remap
    else
      -- File view: include all comments for this tip whose file is in the diff
      include = files_in_diff[path]
    end
    if include then
      table.insert(commit_comments, comment)
    end
    ::continue::
  end
  if #commit_comments == 0 then return end

  -- Group comments by file:line
  local groups = {}  -- "file\0line" -> {file, line, comments=[]}
  for _, comment in ipairs(commit_comments) do
    local path = comment.path or ''
    local line_nr = comment.line or comment.original_line
    if path ~= '' and line_nr then
      local key = path .. '\0' .. tostring(line_nr)
      if not groups[key] then
        groups[key] = { file = path, line = line_nr, comments = {} }
      end
      table.insert(groups[key].comments, comment)
    end
  end

  -- Place extmarks and build line->comments map
  for _, group in pairs(groups) do
    local file_map = line_map[group.file]
    if file_map then
      local buf_line = file_map[group.line]
      if buf_line then
        local count = #group.comments
        local label = string.format(' 💬 %d comment%s', count, count > 1 and 's' or '')
        vim.api.nvim_buf_set_extmark(buf, ns_id, buf_line - 1, 0, {
          virt_text = { { label, 'DiagnosticInfo' } },
          virt_text_pos = 'eol',
        })
        M.buf_comment_maps[buf][buf_line] = group.comments
      end
    end
  end
end

-- Show a floating popup with comments for the line under cursor in buf.
-- Returns true if a popup was shown.
function M.show_popup(buf)
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local comment_map = M.buf_comment_maps[buf]
  if not comment_map then return false end

  local comments = comment_map[cursor_line]
  if not comments or #comments == 0 then return false end

  -- Build popup content
  local popup_lines = {}
  for i, comment in ipairs(comments) do
    if i > 1 then
      table.insert(popup_lines, string.rep('─', 60))
    end
    local author = (comment.user and comment.user.login) or 'unknown'
    local date = (comment.created_at or ''):gsub('T', ' '):gsub('Z', ' UTC')
    table.insert(popup_lines, string.format('**@%s** · %s', author, date))
    if comment.path and comment.line then
      table.insert(popup_lines, string.format('*%s:%d*', comment.path, comment.line))
    end
    table.insert(popup_lines, '')
    -- Split comment body into lines
    for body_line in (comment.body or ''):gmatch('[^\n]*') do
      table.insert(popup_lines, body_line)
    end
    -- Show reply count
    if comment.in_reply_to_id then
      table.insert(popup_lines, '')
      table.insert(popup_lines, string.format('*(reply to comment #%d)*', comment.in_reply_to_id))
    end
  end

  -- Open float
  local float_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, popup_lines)
  vim.bo[float_buf].filetype = 'markdown'
  vim.bo[float_buf].modifiable = false

  local win_width = math.min(82, vim.o.columns - 6)
  local win_height = math.min(#popup_lines + 2, math.floor(vim.o.lines * 0.6))

  local float_win = vim.api.nvim_open_win(float_buf, false, {
    relative = 'cursor',
    row = 1,
    col = 0,
    width = win_width,
    height = win_height,
    style = 'minimal',
    border = 'rounded',
    title = string.format(' PR Comments (%d) ', #comments),
    title_pos = 'center',
  })
  vim.wo[float_win].wrap = true
  vim.wo[float_win].linebreak = true

  -- Close on cursor movement or leaving the originating buffer
  local augroup = vim.api.nvim_create_augroup('pr_review_comment_popup', { clear = true })
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'BufLeave', 'InsertEnter' }, {
    group = augroup,
    buffer = buf,
    once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(float_win) then
        vim.api.nvim_win_close(float_win, true)
      end
      if vim.api.nvim_buf_is_valid(float_buf) then
        vim.api.nvim_buf_delete(float_buf, { force = true })
      end
    end,
  })

  return true
end

-- Return the GitHub URL for a comment on the given buf line, or nil
function M.get_comment_url(buf, line_nr)
  local comment_map = M.buf_comment_maps[buf]
  if not comment_map then return nil end
  local comments = comment_map[line_nr]
  if comments and comments[1] then
    return comments[1].html_url
  end
  return nil
end

return M
