-- pr_review.ui: Window layout, buffer management, and keymaps

local M = {}
local api = require('pr_review.api')
local comments_mod = require('pr_review.comments')

local function state()
  return require('pr_review.init').state
end

-- ─────────────────────────────────────────────────────────
-- ANSI passthrough via terminal emulation
-- range-diff content is rendered in a terminal buffer using
-- nvim_open_term so Neovim's built-in terminal emulator handles
-- all ANSI codes (reverse video, bold, compound codes, etc.) exactly
-- as a real terminal would.  No manual colour-map needed.
-- ─────────────────────────────────────────────────────────

-- Strip ANSI escape sequences from a line (used for logic/search, not display).
local function strip_ansi(line)
  return (line:gsub('\027%[[^m]*m', ''))
end

-- Monotonic counter so each terminal buffer gets a unique name and never
-- collides with an outgoing buffer that hasn't been wiped yet.
local _rd_seq = 0

-- Create a fresh terminal buffer for the range-diff pane, display it in `win`,
-- and stream `raw_lines` (with ANSI) into it.  Neovim's built-in terminal
-- emulator renders all escape codes natively.
-- Returns (buf, chan).
local function create_rd_term_buf(pr_number, win, raw_lines)
  _rd_seq = _rd_seq + 1
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  -- Put in window BEFORE nvim_open_term (terminal needs the window for sizing).
  -- This also triggers bufhidden=wipe on the outgoing buffer, freeing its name.
  vim.api.nvim_win_set_buf(win, buf)
  -- Name after the window swap so the outgoing buffer's name is already freed.
  pcall(vim.api.nvim_buf_set_name, buf,
    string.format('PR#%d//range-diff[%d]', pr_number, _rd_seq))
  local chan = vim.api.nvim_open_term(buf, {})
  -- Terminal buffers normally auto-enter insert mode; suppress that.
  vim.api.nvim_create_autocmd('TermOpen', {
    buffer = buf, once = true,
    callback = function() vim.cmd('stopinsert') end,
  })
  if raw_lines and #raw_lines > 0 then
    -- CR+LF required for terminal line endings
    vim.api.nvim_chan_send(chan, table.concat(raw_lines, '\r\n'))
  end
  return buf, chan
end

-- ─────────────────────────────────────────────────────────
-- Range-diff line parsing
-- ─────────────────────────────────────────────────────────

-- Parse a range-diff "meta line" (the commit correspondence line).
-- Returns table with fields: left_num, left_sha, marker, right_num, right_sha, message
-- OR nil if the line is not a meta line (e.g. inner diff content).
local function parse_meta_line(line)
  -- Normal: " N:  SHA  MARKER  N:  SHA  message"
  local ln, ls, mk, rn, rs, msg =
    line:match('^ *(%d+):  (%x+)%s+([!<>=])%s+(%d+):  (%x+)%s*(.*)')
  if ln then
    return {
      left_num = tonumber(ln), left_sha = ls,
      marker = mk,
      right_num = tonumber(rn), right_sha = rs,
      message = vim.trim(msg),
    }
  end
  -- New commit (no left): "-:  ----  >  N:  SHA  message"
  local rn2, rs2, msg2 = line:match('^ *%-:  %-+%s+>%s+(%d+):  (%x+)%s*(.*)')
  if rn2 then
    return {
      left_num = nil, left_sha = nil,
      marker = '>',
      right_num = tonumber(rn2), right_sha = rs2,
      message = vim.trim(msg2),
    }
  end
  -- Deleted commit (no right): "N:  SHA  <  -:  ----"
  local ln3, ls3 = line:match('^ *(%d+):  (%x+)%s+<%s+%-:  %-+')
  if ln3 then
    return {
      left_num = tonumber(ln3), left_sha = ls3,
      marker = '<',
      right_num = nil, right_sha = nil,
      message = '',
    }
  end
  return nil
end

-- Given a parsed meta line entry and the raw line text,
-- find the 1-indexed column ranges for left and right SHAs.
local function sha_column_ranges(line, entry)
  local positions = {}
  -- Find left SHA (searching from beginning)
  if entry.left_sha then
    local s, e = line:find(entry.left_sha, 1, true)
    if s then positions.left = { s, e } end
  end
  -- Find right SHA (searching after the marker to avoid false matches)
  if entry.right_sha then
    local search_from = 1
    if positions.left then
      search_from = positions.left[2] + 1
    end
    local s, e = line:find(entry.right_sha, search_from, true)
    if s then positions.right = { s, e } end
  end
  return positions
end

-- ─────────────────────────────────────────────────────────
-- Layout management
-- ─────────────────────────────────────────────────────────

function M.close_layout()
  local s = state()
  -- Clear the WinEnter augroup so stale autocmds don't fire after close
  vim.api.nvim_create_augroup('pr_review_winenter', { clear = true })
  for _, win in ipairs({ s.tips_win, s.range_diff_win, s.files_win, s.diff_win, s.log_win, s.comments_win }) do
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  for _, buf in ipairs({ s.tips_buf, s.range_diff_buf, s.files_buf, s.diff_buf, s.log_buf, s.comments_buf }) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
  s.tips_win = nil; s.range_diff_win = nil; s.files_win = nil; s.diff_win = nil; s.log_win = nil
  s.tips_buf = nil; s.range_diff_buf = nil; s.files_buf = nil; s.diff_buf = nil; s.log_buf = nil
  s.comments_win = nil; s.comments_buf = nil
end

local function make_buf(name, ft)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = false
  if ft then vim.bo[buf].filetype = ft end
  return buf
end

function M.setup_layout()
  local s = state()
  M.close_layout()

  -- Open a new tab for the review
  vim.cmd('tabnew')

  -- Create the six buffers
  local pr = s.pr_number
  s.diff_buf       = make_buf(string.format('PR#%d//detail', pr), 'diff')
  s.range_diff_buf = make_buf(string.format('PR#%d//range-diff', pr), '')
  s.files_buf      = make_buf(string.format('PR#%d//files', pr))
  s.tips_buf       = make_buf(string.format('PR#%d//tips', pr))
  s.log_buf        = make_buf(string.format('PR#%d//log', pr))
  s.comments_buf   = make_buf(string.format('PR#%d//comments', pr))

  -- Step 1: create three full-height columns via vertical splits.
  -- Starting window becomes diff (rightmost).
  s.diff_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(s.diff_win, s.diff_buf)

  -- Middle column (range-diff / files)
  vim.cmd('leftabove vsplit')
  local mid_win = vim.api.nvim_get_current_win()

  -- Left column (tips / log)
  vim.cmd('leftabove vsplit')
  local left_win = vim.api.nvim_get_current_win()

  -- Step 2: split each column horizontally.
  -- Left column → tips (top 15%) + comments (middle 35%) + log (bottom)
  vim.api.nvim_set_current_win(left_win)
  s.tips_win = left_win
  vim.api.nvim_win_set_buf(s.tips_win, s.tips_buf)
  vim.cmd('belowright split')
  s.comments_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(s.comments_win, s.comments_buf)
  vim.cmd('belowright split')
  s.log_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(s.log_win, s.log_buf)

  -- Middle column → range-diff (top 65%) + files (bottom 35%)
  vim.api.nvim_set_current_win(mid_win)
  s.range_diff_win = mid_win
  vim.api.nvim_win_set_buf(s.range_diff_win, s.range_diff_buf)
  vim.cmd('belowright split')
  s.files_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(s.files_win, s.files_buf)

  -- Step 3: set column widths; heights
  local total_cols = vim.o.columns
  vim.api.nvim_win_set_width(s.tips_win, math.floor(total_cols * 0.18))
  vim.api.nvim_win_set_width(s.range_diff_win, math.floor(total_cols * 0.30))

  local usable_lines = vim.o.lines - 3
  vim.api.nvim_win_set_height(s.tips_win, math.floor(usable_lines * 0.15))
  vim.api.nvim_win_set_height(s.comments_win, math.floor(usable_lines * 0.35))
  vim.api.nvim_win_set_height(s.range_diff_win, math.floor(usable_lines * 0.65))

  -- Window options on all panes
  for _, win in ipairs({ s.tips_win, s.range_diff_win, s.files_win, s.diff_win, s.log_win, s.comments_win }) do
    vim.wo[win].wrap = true
    vim.wo[win].number = true
    vim.wo[win].relativenumber = true
    vim.wo[win].signcolumn = 'no'
    vim.wo[win].cursorline = true
  end

  -- Disable colorcolumn in all panes except the detail/diff pane (let global settings apply there)
  for _, win in ipairs({ s.tips_win, s.range_diff_win, s.files_win, s.log_win, s.comments_win }) do
    vim.wo[win].colorcolumn = ''
  end

  vim.api.nvim_set_current_win(s.tips_win)
end

-- ─────────────────────────────────────────────────────────
-- Comment → tip assignment
-- ─────────────────────────────────────────────────────────

-- Mutates each comment to set comment._tip_sha (full SHA of the tip it
-- belongs to). A comment belongs to the tip that was HEAD when it was made:
--   1. commit_id matches a tip SHA directly → that tip
--   2. commit_id is an individual commit SHA → newest tip that contains it
--      (git merge-base --is-ancestor, cached in api)
--   3. Fall back to the current HEAD tip
local function assign_comments_to_tips(comments, tips, head_sha)
  for _, c in ipairs(comments) do
    local cid = c.commit_id or ''
    local owner = nil
    local is_files_changed = false

    -- 1. Prefix match against tip SHAs
    for _, tip in ipairs(tips) do
      local min_len = math.min(#cid, #tip.sha)
      if min_len >= 7 and cid:sub(1, min_len) == tip.sha:sub(1, min_len) then
        owner = tip.sha
        -- Mark as "files changed" only when the path is NOT in the tip commit's
        -- own diff. If the path IS touched by the tip commit, commit_id = tip SHA
        -- is ambiguous (could be from "Files Changed" OR from reviewing the tip
        -- commit directly on the Commits tab) — default to commit-specific so
        -- that tip-targeted reviews appear alongside that commit.
        local path = c.path or ''
        local tip_files = api.files_in_commit(tip.sha)
        is_files_changed = (path ~= '' and not tip_files[path])
        break
      end
    end

    -- 2. Ancestry check for individual commit SHAs → commit-specific comment
    if not owner and #cid >= 7 then
      for i = #tips, 1, -1 do
        if api.is_ancestor(cid, tips[i].sha) then
          owner = tips[i].sha
          is_files_changed = false
          break
        end
      end
    end

    c._tip_sha = owner or head_sha
    c._is_files_changed = is_files_changed
  end
end

-- ─────────────────────────────────────────────────────────
-- Populate tips pane
-- ─────────────────────────────────────────────────────────

function M.populate_tips()
  local s = state()
  local lines = {}

  -- Pre-build set: which tips have at least one comment assigned?
  local tips_with_comments = {}
  for _, c in ipairs(s.all_comments) do
    if c._tip_sha then tips_with_comments[c._tip_sha] = true end
  end

  for i, tip in ipairs(s.tips) do
    local tag = ''
    if tip.is_current then tag = ' (current)'
    elseif tip.is_initial then tag = ' (initial)'
    end
    local comment_icon = tips_with_comments[tip.sha] and ' 💬' or ''
    local date_str = tip.date or ''
    local subject = (tip.subject or ''):sub(1, 30)
    lines[i] = string.format('[%d] %s%s%s  %s  %s',
      i, tip.short_sha, tag, comment_icon, date_str, subject)
  end

  vim.bo[s.tips_buf].modifiable = true
  vim.api.nvim_buf_set_lines(s.tips_buf, 0, -1, false, lines)
  vim.bo[s.tips_buf].modifiable = false
end

-- ─────────────────────────────────────────────────────────
-- Populate log pane (PR timeline: reviews, deployments, issue comments)
-- ─────────────────────────────────────────────────────────

function M.populate_log()
  local s = state()
  local entries = {}

  for _, item in ipairs(s.pr_log) do
    local event = item.event
    local entry

    if event == 'reviewed' then
      local state_str = (item.state or ''):upper()
      local icon = state_str == 'APPROVED' and '✓'
                or state_str == 'CHANGES_REQUESTED' and '✗'
                or '💬'
      entry = {
        at       = item.submitted_at or '',
        icon     = icon,
        user     = (item.user and item.user.login) or '?',
        body     = item.body or '',
        state    = state_str,
        html_url = item.html_url,
      }

    elseif event == 'deployed' then
      local env = (item.deployment and item.deployment.environment) or 'unknown'
      entry = {
        at       = item.created_at or '',
        icon     = '🚀',
        user     = (item.actor and item.actor.login) or '?',
        body     = 'deployed to ' .. env,
        html_url = nil,
      }

    elseif not event and item.body and item.user then
      -- General PR comment (not file-specific)
      entry = {
        at       = item.created_at or '',
        icon     = '💬',
        user     = (item.user and item.user.login) or '?',
        body     = item.body or '',
        html_url = item.html_url,
      }
    end

    if entry then table.insert(entries, entry) end
  end

  local lines = {}
  s.log_line_entries = {}

  if #entries == 0 then
    table.insert(lines, '  (no reviews or comments)')
  else
    for _, entry in ipairs(entries) do
      local date = (entry.at or ''):sub(1, 16):gsub('T', ' ')
      local state_tag = (entry.state and entry.state ~= '' and entry.state ~= 'COMMENTED')
                        and ('  [' .. entry.state .. ']') or ''
      table.insert(lines, string.format('%s %s @%s%s', date, entry.icon, entry.user, state_tag))
      s.log_line_entries[#lines] = entry
    end
  end

  vim.bo[s.log_buf].modifiable = true
  vim.api.nvim_buf_set_lines(s.log_buf, 0, -1, false, lines)
  vim.bo[s.log_buf].modifiable = false
end

-- ─────────────────────────────────────────────────────────
-- Populate comments pane (threaded PR inline code review comments)
-- ─────────────────────────────────────────────────────────

local function set_detail_content(lines, ft)
  local s = state()
  comments_mod.clear_comments(s.diff_buf)
  vim.bo[s.diff_buf].modifiable = true
  vim.api.nvim_buf_set_lines(s.diff_buf, 0, -1, false, lines)
  vim.bo[s.diff_buf].modifiable = false
  if ft ~= nil then
    vim.bo[s.diff_buf].filetype = ft
  end
  if vim.api.nvim_win_is_valid(s.diff_win) then
    vim.api.nvim_win_set_cursor(s.diff_win, { 1, 0 })
  end
end

function M.populate_comments_pane()
  local s = state()
  if not s.comments_buf or not vim.api.nvim_buf_is_valid(s.comments_buf) then return end

  -- Build threads from all_comments (sort by created_at first for stability)
  local sorted = {}
  for _, c in ipairs(s.all_comments) do table.insert(sorted, c) end
  table.sort(sorted, function(a, b) return (a.created_at or '') < (b.created_at or '') end)

  local threads = {}
  local id_to_thread_idx = {}

  -- First pass: root comments
  for _, c in ipairs(sorted) do
    if not c.in_reply_to_id then
      table.insert(threads, {
        path = c.path,
        line = tonumber(c.line) or tonumber(c.original_line),
        is_outdated = (tonumber(c.line) == nil and tonumber(c.original_line) ~= nil),
        tip_sha = c._tip_sha,
        is_files_changed = c._is_files_changed,
        comments = { c },
      })
      id_to_thread_idx[c.id] = #threads
    end
  end

  -- Second pass: replies
  for _, c in ipairs(sorted) do
    if c.in_reply_to_id then
      local ti = id_to_thread_idx[c.in_reply_to_id]
      if ti then
        table.insert(threads[ti].comments, c)
        id_to_thread_idx[c.id] = ti
      else
        -- Orphan reply: start its own thread
        table.insert(threads, {
          path = c.path,
          line = tonumber(c.line) or tonumber(c.original_line),
          is_outdated = (tonumber(c.line) == nil and tonumber(c.original_line) ~= nil),
          tip_sha = c._tip_sha,
          is_files_changed = c._is_files_changed,
          comments = { c },
        })
        id_to_thread_idx[c.id] = #threads
      end
    end
  end

  s.comment_threads = threads

  -- Find tip index for a SHA
  local function tip_idx_for_sha(sha)
    for i, tip in ipairs(s.tips) do
      if tip.sha == sha then return i end
    end
    return nil
  end

  local lines = {}
  s.comments_lines = {}

  if #threads == 0 then
    table.insert(lines, '  (no code review comments)')
  else
    for i, thread in ipairs(threads) do
      local tip_i = tip_idx_for_sha(thread.tip_sha)
      local tip_tag = tip_i and string.format('[%d] ', tip_i) or ''
      local author = (thread.comments[1].user and thread.comments[1].user.login) or '?'
      local short_path = ''
      if thread.path then
        local outdated_tag = thread.is_outdated and '⚠ ' or ''
        short_path = outdated_tag
                     .. (thread.path:match('([^/]+)$') or thread.path)
                     .. (thread.line and (':' .. thread.line) or '')
                     .. '  '
      end
      local body_preview = vim.trim((thread.comments[1].body or ''):gsub('\r?\n', ' ')):sub(1, 50)
      local reply_tag = #thread.comments > 1 and string.format(' [+%d]', #thread.comments - 1) or ''
      table.insert(lines, string.format('%s@%s  %s%s%s', tip_tag, author, short_path, body_preview, reply_tag))
      s.comments_lines[#lines] = i
    end
  end

  vim.bo[s.comments_buf].modifiable = true
  vim.api.nvim_buf_set_lines(s.comments_buf, 0, -1, false, lines)
  vim.bo[s.comments_buf].modifiable = false
end

function M.update_detail_pane_for_log()
  local s = state()
  if not s.diff_buf or not vim.api.nvim_buf_is_valid(s.diff_buf) then return end
  if not s.log_win or not vim.api.nvim_win_is_valid(s.log_win) then return end

  local row = vim.api.nvim_win_get_cursor(s.log_win)[1]
  local entry = s.log_line_entries[row]
  if not entry then return end

  local content_key = 'log:' .. (entry.at or '') .. ':' .. (entry.user or '') .. ':' .. row
  if content_key == last_diff_key then return end
  last_diff_key = content_key

  local lines = {}
  local date = (entry.at or ''):sub(1, 16):gsub('T', ' ')
  local state_tag = (entry.state and entry.state ~= '' and entry.state ~= 'COMMENTED')
                    and ('  [' .. entry.state .. ']') or ''
  table.insert(lines, string.format('%s  %s  @%s%s', date, entry.icon, entry.user, state_tag))
  if entry.html_url then
    table.insert(lines, entry.html_url)
  end
  table.insert(lines, string.rep('─', 60))
  table.insert(lines, '')

  local body = ''
  if type(entry.body) == 'string' then
    body = vim.trim(entry.body:gsub('\r\n', '\n'):gsub('\r', '\n'))
  end
  if body ~= '' then
    for body_line in (body .. '\n'):gmatch('([^\n]*)\n') do
      table.insert(lines, body_line)
    end
  else
    table.insert(lines, '(no body)')
  end

  set_detail_content(lines, 'markdown')
end

function M.update_detail_pane_for_comment()
  local s = state()
  if not s.diff_buf or not vim.api.nvim_buf_is_valid(s.diff_buf) then return end
  if not s.comments_win or not vim.api.nvim_win_is_valid(s.comments_win) then return end

  local row = vim.api.nvim_win_get_cursor(s.comments_win)[1]
  local thread_idx = s.comments_lines[row]
  if not thread_idx then return end

  local content_key = 'comment:' .. thread_idx
  if content_key == last_diff_key then return end
  last_diff_key = content_key

  local thread = s.comment_threads[thread_idx]
  if not thread then return end

  local lines = {}
  local path_info = thread.path
    and (thread.path .. (thread.line and (':' .. thread.line) or ''))
    or '(unknown file)'
  local tip_i = nil
  for i, tip in ipairs(s.tips) do
    if tip.sha == thread.tip_sha then tip_i = i; break end
  end
  local tip_tag = tip_i and ('Tip [' .. tip_i .. ']  ') or ''
  local fc_tag = thread.is_files_changed and 'Files Changed' or 'Commit'
  local outdated_tag = thread.is_outdated and '  ⚠ outdated' or ''
  table.insert(lines, string.format('%s%s  —  %s%s', tip_tag, fc_tag, path_info, outdated_tag))
  table.insert(lines, string.rep('─', 60))
  table.insert(lines, '')

  for i, comment in ipairs(thread.comments) do
    if i > 1 then
      table.insert(lines, '')
      table.insert(lines, string.rep('┄', 40))
      table.insert(lines, '')
    end
    local author = (comment.user and comment.user.login) or 'unknown'
    local date = (comment.created_at or ''):gsub('T', ' '):gsub('Z', ' UTC')
    table.insert(lines, string.format('@%s  ·  %s', author, date))
    table.insert(lines, '')
    for body_line in (comment.body or ''):gmatch('[^\n]*') do
      table.insert(lines, body_line)
    end
  end

  set_detail_content(lines, 'markdown')
end

-- ─────────────────────────────────────────────────────────
-- Files changed pane
-- ─────────────────────────────────────────────────────────

-- Populate the files pane with all files changed in base..tip.
-- Stores {status, path} per line in s.files_lines.
function M.populate_files_pane(tip_idx)
  local s = state()
  if not s.files_buf or not vim.api.nvim_buf_is_valid(s.files_buf) then return end
  local tip = s.tips[tip_idx]
  if not tip then return end

  s.files_lines = {}

  local base = s.merge_base_cache[tip.sha]
  if not base then
    base = api.get_merge_base(s.owner, s.repo, s.base_ref, tip.sha)
    if base then api.ensure_sha_available(base, s.pr_remote) end
    s.merge_base_cache[tip.sha] = base
  end

  local lines = {}
  if not base then
    table.insert(lines, '  (could not determine merge base)')
  else
    local files = api.get_changed_files(base, tip.sha)
    if #files == 0 then
      table.insert(lines, '  (no changed files)')
    else
      -- Build set of files with comments for this tip (files-changed view only)
      local files_with_comments = {}
      for _, c in ipairs(s.all_comments) do
        if c._tip_sha == tip.sha and c.path and c._is_files_changed then
          files_with_comments[c.path] = true
        end
      end
      for i, f in ipairs(files) do
        s.files_lines[i] = { status = f.status, path = f.path, base = base, tip_sha = tip.sha }
        local comment_icon = files_with_comments[f.path] and ' 💬' or ''
        table.insert(lines, string.format('%s  %s%s', f.status, f.path, comment_icon))
      end
    end
  end

  vim.bo[s.files_buf].modifiable = true
  vim.api.nvim_buf_set_lines(s.files_buf, 0, -1, false, lines)
  vim.bo[s.files_buf].modifiable = false
end

-- Show the full diff for the file under cursor in the diff pane.
function M.update_diff_pane_for_file()
  local s = state()
  if not s.files_win or not vim.api.nvim_win_is_valid(s.files_win) then return end
  local row = vim.api.nvim_win_get_cursor(s.files_win)[1]
  local entry = s.files_lines[row]
  if not entry then return end

  local content_key = 'file:' .. entry.base .. ':' .. entry.tip_sha .. ':' .. entry.path
  if content_key == last_diff_key then return end
  last_diff_key = content_key

  local lines = api.diff_file(entry.base, entry.tip_sha, entry.path)
  set_detail_content(lines, 'diff')

  if #s.all_comments > 0 then
    local tip = s.tips[s.current_tip_idx]
    local tip_sha = tip and tip.sha or s.head_sha
    comments_mod.attach_comments(s.diff_buf, nil, s.all_comments, tip_sha, entry.path)
  end
end



-- namespace for range-diff comment icons
local rd_ns = vim.api.nvim_create_namespace('pr_review_rangediff')

local function annotate_range_diff_comments(buf, all_comments, current_tip_sha)
  vim.api.nvim_buf_clear_namespace(buf, rd_ns, 0, -1)
  -- Pre-filter to comments belonging to this tip
  local tip_comments = {}
  for _, c in ipairs(all_comments) do
    if c._tip_sha == current_tip_sha then
      table.insert(tip_comments, c)
    end
  end
  if #tip_comments == 0 then return end

  local lines = state().range_diff_lines or {}
  for i, line in ipairs(lines) do
    local sha
    local entry = parse_meta_line(line)
    if entry then
      sha = entry.right_sha or entry.left_sha
    else
      local candidate = line:match('^([0-9a-f]+) ')
      if candidate and #candidate >= 7 then
        sha = candidate
      end
    end
    if sha then
      local files_set = api.files_in_commit(sha)
      if comments_mod.has_comments_for_sha(sha, tip_comments, current_tip_sha, files_set) then
        vim.api.nvim_buf_set_extmark(buf, rd_ns, i - 1, 0, {
          virt_text = { { ' 💬', 'DiagnosticInfo' } },
          virt_text_pos = 'eol',
        })
      end
    end
  end
end

-- Buffer-local keymaps for range-diff terminal buffers.
-- Called on each new terminal buffer since the buffer is recreated per tip.
local function setup_rd_buf_keymaps(buf)
  local o = { noremap = true, silent = true }
  vim.keymap.set('n', 'q', function() M.close_layout() end,
    vim.tbl_extend('force', o, { buffer = buf, desc = 'PR review: close' }))
  vim.keymap.set('n', '<leader>gx', function()
    local url = M.get_browse_url()
    if not url then
      vim.notify('pr_review: nothing to browse', vim.log.levels.WARN)
      return
    end
    vim.ui.open(url)
  end, vim.tbl_extend('force', o, { buffer = buf, desc = 'PR review: open in GitHub' }))
  vim.keymap.set('n', '<CR>', function()
    vim.api.nvim_set_current_win(state().diff_win)
  end, vim.tbl_extend('force', o, { buffer = buf, desc = 'PR review: go to diff' }))
  vim.api.nvim_create_autocmd('CursorMoved', {
    buffer = buf,
    callback = function() M.update_diff_pane() end,
  })
end


local range_diff_cursor_pending = false

local function find_first_content_line()
  local s = state()
  local lines = s.range_diff_lines or {}
  for i, line in ipairs(lines) do
    if parse_meta_line(line) then return i end
    local sha = line:match('^%s*([0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]+)%s')
    if sha then return i end
  end
  return 1
end

-- Return the 0-indexed column of the right SHA on the meta line at `row`,
-- or 0 if the line has no right SHA (e.g. inner diff content).
local function right_sha_col_for_row(row)
  local s = state()
  local lines = s.range_diff_lines or {}
  local line = lines[row]
  if not line then return 0 end
  local entry = parse_meta_line(line)
  if not entry then return 0 end
  local pos = sha_column_ranges(line, entry)
  if pos.right then
    return pos.right[1] - 1  -- sha_column_ranges is 1-indexed; nvim_win_set_cursor col is 0-indexed
  end
  return 0
end

function M.update_range_diff(tip_idx)
  local s = state()
  s.current_tip_idx = tip_idx
  s.range_diff_lines = {}  -- clear while computing
  last_diff_key = nil  -- force diff pane refresh

  local tip = s.tips[tip_idx]
  if not tip then return end

  -- Resolve merge-base via GitHub API (cached); this matches exactly what GitHub shows
  if not s.merge_base_cache[tip.sha] then
    local base = api.get_merge_base(s.owner, s.repo, s.base_ref, tip.sha)
    -- Ensure the merge-base commit is available locally for git range-diff
    if base then api.ensure_sha_available(base, s.pr_remote) end
    s.merge_base_cache[tip.sha] = base
  end
  local base = s.merge_base_cache[tip.sha]

  local raw_lines
  if not base then
    raw_lines = {
      '  Error: could not find merge-base for ' .. tip.short_sha,
      '  (GitHub API call failed — check gh auth status)',
    }
  elseif s.tips[tip_idx - 1] then
    -- Range diff between previous tip and selected tip
    local prev_tip = s.tips[tip_idx - 1]
    local cache_key = prev_tip.sha .. ':' .. tip.sha
    if not s.range_diff_cache[cache_key] then
      api.ensure_sha_available(prev_tip.sha, s.pr_remote)
      api.ensure_sha_available(tip.sha, s.pr_remote)
      local result = api.range_diff(base, prev_tip.sha, tip.sha)
      s.range_diff_cache[cache_key] = result
        or { '  Error running git range-diff', '', '  Are both SHAs available locally?' }
    end
    raw_lines = s.range_diff_cache[cache_key]
  else
    -- Initial tip: show commits in range (no previous to compare against)
    local header = string.format(
      '  Initial tip %s — no previous tip for range-diff',
      tip.short_sha
    )
    local commit_lines = api.log_range(base, tip.sha)
    if #commit_lines == 0 then
      commit_lines = { '  (no commits in range ' .. base:sub(1, 7) .. '..' .. tip.short_sha .. ')' }
    end
    raw_lines = { header, '' }
    vim.list_extend(raw_lines, commit_lines)
  end

  -- Store stripped lines for all logic (cursor context, annotations, navigation)
  s.range_diff_lines = vim.tbl_map(strip_ansi, raw_lines)

  -- Display in a fresh terminal buffer for native ANSI rendering.
  -- nvim_win_set_buf (inside create_rd_term_buf) will trigger bufhidden=wipe
  -- on the outgoing buffer, so no explicit delete needed here.
  s.range_diff_buf, s.range_diff_chan = create_rd_term_buf(
    s.pr_number, s.range_diff_win, raw_lines)
  setup_rd_buf_keymaps(s.range_diff_buf)

  -- Annotate comment icons on the new buffer (reads s.range_diff_lines)
  annotate_range_diff_comments(s.range_diff_buf, s.all_comments, tip.sha)

  -- Mark cursor as needing reset on next entry into the range-diff window.
  range_diff_cursor_pending = true
  -- If the range-diff window is already focused, position the cursor immediately.
  if vim.api.nvim_win_is_valid(s.range_diff_win)
      and vim.api.nvim_get_current_win() == s.range_diff_win then
    range_diff_cursor_pending = false
    local row = find_first_content_line()
    vim.api.nvim_win_set_cursor(s.range_diff_win, { row, right_sha_col_for_row(row) })
  end

  M.populate_files_pane(tip_idx)
  M.update_diff_pane()
end

-- ─────────────────────────────────────────────────────────
-- Cursor context detection in range-diff pane
-- ─────────────────────────────────────────────────────────

-- Returns a context table describing what the cursor is on:
--   {type='left_sha',  sha, entry, meta_line_idx}
--   {type='right_sha', sha, entry, meta_line_idx}
--   {type='entry',         entry, meta_line_idx}  -- cursor on meta line, not on a SHA
--   {type='inner_diff',    entry, meta_line_idx}  -- cursor on inner diff content
--   nil if nothing useful
function M.get_range_diff_cursor_context()
  local s = state()
  if not s.range_diff_win or not vim.api.nvim_win_is_valid(s.range_diff_win) then
    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(s.range_diff_win)
  local cur_row = cursor[1]  -- 1-indexed
  local cur_col = cursor[2] + 1  -- 1-indexed

  local lines = s.range_diff_lines or {}
  local line = lines[cur_row]
  if not line then return nil end

  -- Is the cursor on a meta line?
  local entry = parse_meta_line(line)
  if entry then
    local pos = sha_column_ranges(line, entry)
    if pos.left and cur_col >= pos.left[1] and cur_col <= pos.left[2] then
      return { type = 'left_sha', sha = entry.left_sha, entry = entry, meta_line_idx = cur_row }
    elseif pos.right and cur_col >= pos.right[1] and cur_col <= pos.right[2] then
      return { type = 'right_sha', sha = entry.right_sha, entry = entry, meta_line_idx = cur_row }
    else
      return { type = 'entry', entry = entry, meta_line_idx = cur_row }
    end
  end

  -- Cursor is on inner diff content — find the owning meta line
  for i = cur_row - 1, 1, -1 do
    local e = parse_meta_line(lines[i])
    if e then
      return { type = 'inner_diff', entry = e, meta_line_idx = i }
    end
    -- If we hit a non-indented, non-blank line that isn't an inner diff, stop
    local l = lines[i]
    if l and l ~= '' and not l:match('^    ') and not l:match('^%s*$') then
      break
    end
  end

  -- Fallback: check if we're on an initial-view commit line ("FULLSHA subject text")
  local sha_candidate = line:match('^([0-9a-f]+) ')
  if sha_candidate and #sha_candidate >= 7 then
    return { type = 'initial_commit', sha = sha_candidate }
  end

  return nil
end

-- ─────────────────────────────────────────────────────────
-- Diff pane
-- ─────────────────────────────────────────────────────────

local function cached_show(sha)
  local s = state()
  if not s.show_cache[sha] then
    local result = api.show_commit(sha)
    s.show_cache[sha] = result or { 'Error: could not show commit ' .. sha }
  end
  return s.show_cache[sha]
end

-- Get the inner diff lines for a range-diff entry (strips 4-space indent)
local function get_inner_diff_lines(meta_line_idx, entry)
  local s = state()
  local lines = s.range_diff_lines or {}
  local result = {}

  -- Header showing the commit correspondence
  local header = string.format(
    'range-diff: %s %s %s  %s',
    entry.left_sha or '---------',
    entry.marker,
    entry.right_sha or '---------',
    entry.message
  )
  table.insert(result, header)
  table.insert(result, string.rep('─', math.min(#header, 80)))
  table.insert(result, '')

  -- Inner diff lines follow the meta line and are indented 4 spaces
  for i = meta_line_idx + 1, #lines do
    local l = lines[i]
    if l:match('^    ') or l == '' then
      -- Strip the 4-space indent (range-diff inner diff marker)
      table.insert(result, l:sub(5))
    else
      -- Next meta line or unindented content → end of this entry's inner diff
      break
    end
  end

  if #result == 3 then  -- Only header, no actual diff
    if entry.marker == '=' then
      table.insert(result, '(commits are identical)')
    else
      table.insert(result, '(no diff to show)')
    end
  end

  return result
end

function M.update_diff_pane()
  local s = state()
  if not s.diff_buf or not vim.api.nvim_buf_is_valid(s.diff_buf) then return end

  local ctx = M.get_range_diff_cursor_context()
  if not ctx then
    -- Nothing selected — show placeholder
    if last_diff_key ~= '__empty__' then
      last_diff_key = '__empty__'
      vim.bo[s.diff_buf].modifiable = true
      vim.api.nvim_buf_set_lines(s.diff_buf, 0, -1, false,
        { '  Navigate the range-diff pane to view commit diffs.' })
      vim.bo[s.diff_buf].modifiable = false
    end
    return
  end

  local lines, sha_for_comments, content_key

  if ctx.type == 'left_sha' and ctx.sha then
    content_key = 'left:' .. ctx.sha
    sha_for_comments = ctx.sha
    lines = cached_show(ctx.sha)

  elseif ctx.type == 'right_sha' and ctx.sha then
    content_key = 'right:' .. ctx.sha
    sha_for_comments = ctx.sha
    lines = cached_show(ctx.sha)

  elseif ctx.type == 'initial_commit' and ctx.sha then
    content_key = 'initial:' .. ctx.sha
    sha_for_comments = ctx.sha
    lines = cached_show(ctx.sha)

  elseif ctx.type == 'entry' or ctx.type == 'inner_diff' then
    local sha = ctx.entry.right_sha or ctx.entry.left_sha
    content_key = 'inner:' .. ctx.meta_line_idx
    sha_for_comments = sha
    if sha then
      lines = cached_show(sha)
    else
      lines = get_inner_diff_lines(ctx.meta_line_idx, ctx.entry)
    end

  else
    return
  end

  -- Avoid redundant redraws
  if content_key == last_diff_key then return end
  last_diff_key = content_key

  set_detail_content(lines, 'diff')

  if sha_for_comments and #s.all_comments > 0 then
    local current_tip = s.tips[s.current_tip_idx]
    local tip_sha = current_tip and current_tip.sha or s.head_sha
    comments_mod.attach_comments(s.diff_buf, sha_for_comments, s.all_comments, tip_sha)
  end
end

-- ─────────────────────────────────────────────────────────
-- GBrowse / URL helpers
-- ─────────────────────────────────────────────────────────

-- Construct a GitHub URL for the current context
function M.get_browse_url()
  local s = state()
  local cur_win = vim.api.nvim_get_current_win()
  local base_url = string.format('https://github.com/%s/%s', s.owner, s.repo)

  if cur_win == s.tips_win then
    local row = vim.api.nvim_win_get_cursor(s.tips_win)[1]
    local tip = s.tips[row]
    if tip then
      return base_url .. '/commit/' .. tip.sha
    end
    return s.pr_url

  elseif cur_win == s.range_diff_win then
    local ctx = M.get_range_diff_cursor_context()
    if ctx then
      if ctx.type == 'left_sha' and ctx.sha then
        return base_url .. '/commit/' .. ctx.sha
      elseif ctx.type == 'right_sha' and ctx.sha then
        return base_url .. '/commit/' .. ctx.sha
      elseif ctx.entry then
        local sha = ctx.entry.right_sha or ctx.entry.left_sha
        if sha then return base_url .. '/commit/' .. sha end
      end
    end
    return s.pr_url

  elseif cur_win == s.diff_win then
    local row = vim.api.nvim_win_get_cursor(s.diff_win)[1]
    -- Check for a comment URL on this line; rewrite to /changes#r{id} form
    local url = comments_mod.get_comment_url(s.diff_buf, row)
    if url then
      -- GitHub's Files-changed deep-link format: .../pull/N/changes#r{id}
      url = url:gsub('/pull/(%d+)#discussion_r(%d+)', '/pull/%1/changes#r%2')
      return url
    end
    -- Fall back: parse commit SHA from diff header
    local header_lines = vim.api.nvim_buf_get_lines(s.diff_buf, 0, 5, false)
    for _, l in ipairs(header_lines) do
      local sha = l:match('^commit (%x+)')
      if sha then return base_url .. '/commit/' .. sha end
    end
    return s.pr_url
  elseif cur_win == s.files_win then
    -- Link to the PR's files-changed tab
    return s.pr_url .. '/files'
  elseif cur_win == s.log_win then
    local row = vim.api.nvim_win_get_cursor(s.log_win)[1]
    local entry = s.log_line_entries[row]
    if entry and entry.html_url then
      return entry.html_url
    end
    return s.pr_url

  elseif cur_win == s.comments_win then
    local row = vim.api.nvim_win_get_cursor(s.comments_win)[1]
    local thread_idx = s.comments_lines[row]
    if thread_idx then
      local thread = s.comment_threads[thread_idx]
      if thread and thread.comments[1] and thread.comments[1].html_url then
        return thread.comments[1].html_url
      end
    end
    return s.pr_url

  end

  return s.pr_url
end

-- ─────────────────────────────────────────────────────────
-- Keymaps
-- ─────────────────────────────────────────────────────────

function M.setup_keymaps()
  local s = state()
  -- range_diff_buf is excluded here — its keymaps are managed by setup_rd_buf_keymaps()
  -- which is called on each new terminal buffer in update_range_diff().
  local bufs = { s.tips_buf, s.files_buf, s.diff_buf, s.log_buf, s.comments_buf }
  local o = { noremap = true, silent = true }

  -- ── Close review ────────────────────────────────────────
  for _, buf in ipairs(bufs) do
    vim.keymap.set('n', 'q', function()
      M.close_layout()
    end, vim.tbl_extend('force', o, { buffer = buf, desc = 'PR review: close' }))
  end

  -- ── GBrowse integration (<leader>gx) ────────────────────
  for _, buf in ipairs(bufs) do
    vim.keymap.set('n', '<leader>gx', function()
      local url = M.get_browse_url()
      if not url then
        vim.notify('pr_review: nothing to browse', vim.log.levels.WARN)
        return
      end
      -- vim.ui.open handles cross-platform opening without shell-escaping issues
      -- (fnameescape would mangle # fragment anchors in GitHub URLs)
      vim.ui.open(url)
    end, vim.tbl_extend('force', o, { buffer = buf, desc = 'PR review: open in GitHub' }))
  end

  -- Also apply range-diff keymaps to the initial (pre-terminal) range-diff buf.
  -- They'll be re-applied to each new terminal buf in update_range_diff().
  setup_rd_buf_keymaps(s.range_diff_buf)

  -- ── Comment popup (K) ─ in diff pane ───────────────────
  vim.keymap.set('n', 'K', function()
    local shown = comments_mod.show_popup(s.diff_buf)
    if not shown then
      vim.notify('No comment on this line', vim.log.levels.INFO)
    end
  end, vim.tbl_extend('force', o, { buffer = s.diff_buf, desc = 'PR review: show comment popup' }))

  -- ── CursorMoved: tips → update range-diff + files pane ─────
  vim.api.nvim_create_autocmd('CursorMoved', {
    buffer = s.tips_buf,
    callback = function()
      local row = vim.api.nvim_win_get_cursor(s.tips_win)[1]
      M.update_range_diff(row)
    end,
  })

  -- ── CursorMoved: files pane → update diff pane ──────────
  vim.api.nvim_create_autocmd('CursorMoved', {
    buffer = s.files_buf,
    callback = function()
      M.update_diff_pane_for_file()
    end,
  })

  -- ── CursorMoved: log pane → update detail pane ──────────
  vim.api.nvim_create_autocmd('CursorMoved', {
    buffer = s.log_buf,
    callback = function()
      M.update_detail_pane_for_log()
    end,
  })

  -- ── CursorMoved: comments pane → update detail pane ─────
  vim.api.nvim_create_autocmd('CursorMoved', {
    buffer = s.comments_buf,
    callback = function()
      M.update_detail_pane_for_comment()
    end,
  })

  -- ── WinEnter: range-diff → position cursor at right SHA column ──
  -- On initial load (range_diff_cursor_pending) also jump to the first commit row.
  -- On every subsequent entry (e.g. Ctrl+W navigation) keep the current row but
  -- move the column to the right-side SHA (second commit column).
  -- WinEnter fires reliably on every window focus change (unlike BufEnter which
  -- may not fire when switching to a window whose buffer is already current).
  -- Uses a named augroup so it can be cleared in close_layout().
  local aug = vim.api.nvim_create_augroup('pr_review_winenter', { clear = true })
  vim.api.nvim_create_autocmd('WinEnter', {
    group = aug,
    callback = function()
      local cs = state()
      if not (cs.range_diff_win
          and vim.api.nvim_win_is_valid(cs.range_diff_win)
          and vim.api.nvim_get_current_win() == cs.range_diff_win) then
        return
      end
      -- Schedule to ensure the terminal has rendered before we move the cursor
      vim.schedule(function()
        if not vim.api.nvim_win_is_valid(cs.range_diff_win) then return end
        local row
        if range_diff_cursor_pending then
          range_diff_cursor_pending = false
          row = find_first_content_line()
        else
          row = vim.api.nvim_win_get_cursor(cs.range_diff_win)[1]
        end
        vim.api.nvim_win_set_cursor(cs.range_diff_win, { row, right_sha_col_for_row(row) })
      end)
    end,
  })

  -- ── Enter in tips: jump to range-diff pane ──────────────
  vim.keymap.set('n', '<CR>', function()
    vim.api.nvim_set_current_win(s.range_diff_win)
  end, vim.tbl_extend('force', o, { buffer = s.tips_buf, desc = 'PR review: go to range-diff' }))

  -- ── Enter in files pane: jump to diff pane ──────────────
  vim.keymap.set('n', '<CR>', function()
    M.update_diff_pane_for_file()
    vim.api.nvim_set_current_win(s.diff_win)
  end, vim.tbl_extend('force', o, { buffer = s.files_buf, desc = 'PR review: show file diff' }))

  -- ── Enter in comments pane: jump to detail pane ─────────
  vim.keymap.set('n', '<CR>', function()
    M.update_detail_pane_for_comment()
    vim.api.nvim_set_current_win(s.diff_win)
  end, vim.tbl_extend('force', o, { buffer = s.comments_buf, desc = 'PR review: show comment thread' }))

  -- ── Enter in log pane: jump to detail pane ──────────────
  vim.keymap.set('n', '<CR>', function()
    M.update_detail_pane_for_log()
    vim.api.nvim_set_current_win(s.diff_win)
  end, vim.tbl_extend('force', o, { buffer = s.log_buf, desc = 'PR review: show log entry' }))
end

-- ─────────────────────────────────────────────────────────
-- PR picker (shown when :PRReview is called with no argument)
-- ─────────────────────────────────────────────────────────

function M.show_pr_picker()
  if vim.fn.executable('gh') == 0 then
    vim.notify('pr_review: GitHub CLI (gh) not found', vim.log.levels.ERROR)
    return
  end

  local owner, repo = api.get_repo_info()
  if not owner then
    vim.notify('pr_review: cannot determine GitHub repo from current directory', vim.log.levels.ERROR)
    return
  end

  vim.notify('pr_review: fetching open PRs…', vim.log.levels.INFO)
  local prs = api.list_open_prs(owner, repo)
  if #prs == 0 then
    vim.notify('pr_review: no open PRs found', vim.log.levels.INFO)
    return
  end

  -- Format lines and keep parallel number/url tables
  local lines = {}
  local pr_numbers = {}
  local pr_urls = {}
  for _, pr in ipairs(prs) do
    local author = (pr.author and pr.author.login) or '?'
    table.insert(lines, string.format('#%-5d  %-20s  %s', pr.number, '@' .. author, pr.title or ''))
    table.insert(pr_numbers, pr.number)
    table.insert(pr_urls, pr.url)
  end

  -- Floating picker window
  local width  = math.min(100, vim.o.columns - 4)
  local height = math.min(#lines, math.floor(vim.o.lines * 0.7))
  local row    = math.floor((vim.o.lines - height) / 2)
  local col    = math.floor((vim.o.columns - width) / 2)

  local picker_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[picker_buf].buftype    = 'nofile'
  vim.bo[picker_buf].bufhidden  = 'wipe'
  vim.bo[picker_buf].modifiable = true
  vim.api.nvim_buf_set_lines(picker_buf, 0, -1, false, lines)
  vim.bo[picker_buf].modifiable = false

  local picker_win = vim.api.nvim_open_win(picker_buf, true, {
    relative   = 'editor',
    row        = row,
    col        = col,
    width      = width,
    height     = height,
    style      = 'minimal',
    border     = 'rounded',
    title      = string.format(' Open PRs — %s/%s  (<CR> open · q close) ', owner, repo),
    title_pos  = 'center',
  })
  vim.wo[picker_win].cursorline = true
  vim.wo[picker_win].number     = false

  local o = { noremap = true, silent = true, buffer = picker_buf }

  local function close()
    if vim.api.nvim_win_is_valid(picker_win) then
      vim.api.nvim_win_close(picker_win, true)
    end
  end

  vim.keymap.set('n', '<CR>', function()
    local idx = vim.api.nvim_win_get_cursor(picker_win)[1]
    local pr_num = pr_numbers[idx]
    close()
    if pr_num then
      M.open(pr_num)
    end
  end, o)

  vim.keymap.set('n', '<leader>gx', function()
    local idx = vim.api.nvim_win_get_cursor(picker_win)[1]
    local url = pr_urls[idx]
    if url then
      vim.ui.open(url)
    end
  end, o)

  vim.keymap.set('n', 'q',   close, o)
  vim.keymap.set('n', '<Esc>', close, o)
end

-- ─────────────────────────────────────────────────────────
-- Entry point
-- ─────────────────────────────────────────────────────────

function M.open(pr_number)
  if vim.fn.executable('gh') == 0 then
    vim.notify('pr_review: GitHub CLI (gh) not found', vim.log.levels.ERROR)
    return
  end

  -- No PR number: show the interactive picker
  if not pr_number then
    M.show_pr_picker()
    return
  end

  local s = state()

  -- Repo info
  local owner, repo = api.get_repo_info()
  if not owner then
    vim.notify('pr_review: cannot determine GitHub repo from current directory', vim.log.levels.ERROR)
    return
  end

  -- PR info
  local pr, pr_err = api.get_pr_info(pr_number)
  if not pr then
    vim.notify(
      'pr_review: cannot fetch PR — ' .. (pr_err or 'unknown error') .. '\n'
        .. 'Tip: run :PRReview <number>, or check `gh auth status`',
      vim.log.levels.ERROR
    )
    return
  end

  -- Initialise state
  s.pr_number = pr.number
  s.owner = owner
  s.repo = repo
  s.pr_url = pr.url
  s.base_ref = pr.baseRefName
  s.head_sha = pr.headRefOid
  s.pr_remote = api.get_pr_remote(pr.headRefName, owner, repo)
  s.show_cache = {}
  s.merge_base_cache = {}
  s.log_line_entries = {}
  s.files_lines = {}
  s.comment_threads = {}
  s.comments_lines = {}

  vim.notify(string.format('pr_review: loading PR #%d "%s"…', pr.number, pr.title),
    vim.log.levels.INFO)

  -- Fetch comments and PR log
  s.all_comments = api.get_comments(owner, repo, pr.number)
  s.pr_log = api.get_pr_log(owner, repo, pr.number)

  -- Build tips list (force-push history, newest first)
  local events = api.get_force_push_events(owner, repo, pr.number)
  -- Sort chronologically so init_sha = events[1].before is always the true initial SHA
  table.sort(events, function(a, b) return (a.date or '') < (b.date or '') end)

  -- Collect all unique SHAs in chronological order:
  --   initial push before[0], then after[0], after[1], … (latest last)
  local ordered_shas = {}
  if #events > 0 then
    -- Initial SHA is the "before" of the very first force-push event
    local init_sha = events[1].before
    if init_sha and init_sha ~= '' then
      table.insert(ordered_shas, { sha = init_sha, is_initial = true })
    end
    for _, ev in ipairs(events) do
      local sha = ev.after or ev.sha
      if sha and sha ~= '' then
        table.insert(ordered_shas, { sha = sha })
      end
    end
  end

  -- Always ensure the current head is included
  local head = pr.headRefOid
  if #ordered_shas == 0 or ordered_shas[#ordered_shas].sha ~= head then
    table.insert(ordered_shas, { sha = head, is_current = true })
  else
    ordered_shas[#ordered_shas].is_current = true
  end
  if #ordered_shas > 0 then
    ordered_shas[1].is_initial = ordered_shas[1].is_initial or true
  end

  -- Deduplicate SHAs while preserving order and merging flags
  local seen_shas = {}
  local deduped = {}
  for _, entry in ipairs(ordered_shas) do
    if not seen_shas[entry.sha] then
      seen_shas[entry.sha] = true
      table.insert(deduped, entry)
    end
  end
  ordered_shas = deduped

  -- Resolve short SHAs, dates, and subjects (fetch if needed), oldest first
  local tips = {}
  for i = 1, #ordered_shas do
    local entry = ordered_shas[i]
    local sha = entry.sha
    api.ensure_sha_available(sha, s.pr_remote)
    local date = api.commit_date(sha)
    local subject = api.commit_subject(sha) or ''
    table.insert(tips, {
      sha = sha,
      short_sha = sha:sub(1, 7),
      date = date,
      subject = subject,
      files = api.files_in_commit(sha),
      is_current = entry.is_current,
      is_initial = (i == 1),
    })
  end

  s.tips = tips

  -- Pre-assign each comment to exactly one tip based on its commit_id
  assign_comments_to_tips(s.all_comments, s.tips, s.head_sha)

  if #s.tips == 0 then
    vim.notify('pr_review: no tips found for PR #' .. s.pr_number, vim.log.levels.ERROR)
    return
  end

  -- Build UI
  M.setup_layout()
  M.populate_tips()
  M.populate_log()
  M.setup_keymaps()
  M.populate_comments_pane()

  -- Start cursor on the newest (bottom) tip and show its range-diff
  local newest_idx = #s.tips
  if vim.api.nvim_win_is_valid(s.tips_win) then
    vim.api.nvim_win_set_cursor(s.tips_win, { newest_idx, 0 })
  end
  M.update_range_diff(newest_idx)

  vim.notify(
    string.format('pr_review: PR #%d loaded — %d tip(s), %d comment(s)',
      s.pr_number, #s.tips, #s.all_comments),
    vim.log.levels.INFO
  )
end

return M
