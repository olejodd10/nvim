-- pr_review.ui: Window layout, buffer management, and keymaps

local M = {}
local api = require('pr_review.api')
local comments_mod = require('pr_review.comments')

local function state()
  return require('pr_review.init').state
end

-- ─────────────────────────────────────────────────────────
-- ANSI colour rendering for the range-diff pane
-- range-diff content is kept in a regular (nofile) buffer so that
-- Neovim handles line-wrapping natively (one buffer line per logical
-- line, visually wrapped without creating extra buffer lines).
-- ANSI SGR colour codes emitted by git are parsed and applied as
-- extmark highlights so colours are preserved, including backgrounds.
-- ─────────────────────────────────────────────────────────

-- Strip ANSI escape sequences from a line (used for logic/search, not display).
local function strip_ansi(line)
  return (line:gsub('\027%[[^m]*m', ''))
end

-- Namespace for ANSI-derived highlights (separate from comment-icon namespace).
local rd_hl_ns = vim.api.nvim_create_namespace('pr_review_rangediff_hl')

-- Resolve a 4-bit ANSI colour index (0-15) to a hex string.
-- The key diff colours (red/green/yellow/cyan) are derived from the active
-- colorscheme's diff highlight groups so the range-diff pane matches the
-- diff pane to the right.  Other slots use a vivid fallback palette.
-- Cache is rebuilt on ColorScheme change.
local _ansi_cache = nil
local function ansi4(n)
  if not _ansi_cache then
    local function fg(group)
      local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
      return hl.fg and string.format('#%06x', hl.fg)
    end
    local red    = fg('diffRemoved') or '#ff5454'
    local green  = fg('diffAdded')   or '#00cc7a'
    local yellow = fg('diffChanged') or fg('@diff.delta') or '#ffff00'
    local cyan   = fg('diffLine')    or '#33ffff'
    _ansi_cache = {
      [0]='#1e1e2e', [1]=red,      [2]=green,    [3]=yellow,
      [4]='#6272a4', [5]='#ff79c6',[6]=cyan,     [7]='#bfbfbf',
      [8]='#555555', [9]=red,      [10]=green,   [11]=yellow,
      [12]='#d6acff',[13]='#ff92df',[14]=cyan,   [15]='#ffffff',
    }
  end
  return vim.g['pr_review_ansi_' .. n] or _ansi_cache[n] or '#ffffff'
end

-- Convert an xterm-256 colour index to hex.
local function xterm256(n)
  if n < 16 then return ansi4(n) end
  if n >= 232 then
    local v = 8 + (n - 232) * 10
    return string.format('#%02x%02x%02x', v, v, v)
  end
  n = n - 16
  local b = n % 6; n = math.floor(n / 6)
  local g = n % 6; n = math.floor(n / 6)
  local r = n % 6
  local function c(x) return x == 0 and 0 or 55 + x * 40 end
  return string.format('#%02x%02x%02x', c(r), c(g), c(b))
end

-- Parse an SGR parameter string (e.g. '1;32', '48;5;196', '38;2;255;0;0')
-- into a highlight-attribute table, or nil for a reset code.
-- _fg_idx / _bg_idx track the original 4-bit colour index (0-7) so that
-- rd_hl_for can apply the terminal "bold = bright" promotion.
local function parse_sgr(codes)
  if codes == '' or codes == '0' then return nil end
  local params = {}
  for s in (codes .. ';'):gmatch('([^;]*);') do
    params[#params + 1] = tonumber(s) or 0
  end
  local a, i = {}, 1
  while i <= #params do
    local v = params[i]
    if     v == 0   then return nil
    elseif v == 1   then a.bold      = true
    elseif v == 3   then a.italic    = true
    elseif v == 4   then a.underline = true
    elseif v == 7   then a.reverse   = true
    elseif v >= 30  and v <= 37  then a.fg = ansi4(v - 30); a._fg_idx = v - 30
    elseif v >= 40  and v <= 47  then a.bg = ansi4(v - 40); a._bg_idx = v - 40
    elseif v >= 90  and v <= 97  then a.fg = ansi4(v - 90 + 8)
    elseif v >= 100 and v <= 107 then a.bg = ansi4(v - 100 + 8)
    elseif v == 38  and params[i+1] == 5 and params[i+2] then
      a.fg = xterm256(params[i+2]); i = i + 2
    elseif v == 48  and params[i+1] == 5 and params[i+2] then
      a.bg = xterm256(params[i+2]); i = i + 2
    elseif v == 38  and params[i+1] == 2 then
      a.fg = string.format('#%02x%02x%02x', params[i+2] or 0, params[i+3] or 0, params[i+4] or 0)
      i = i + 4
    elseif v == 48  and params[i+1] == 2 then
      a.bg = string.format('#%02x%02x%02x', params[i+2] or 0, params[i+3] or 0, params[i+4] or 0)
      i = i + 4
    end
    i = i + 1
  end
  return next(a) ~= nil and a or nil
end

-- Derive a deterministic highlight-group name from an attr table, creating the
-- group if it does not yet exist.  Groups are recreated on ColorScheme change
-- by clearing _rd_dyn_groups so ansi4() picks up the new terminal colours.
local _rd_dyn_groups = {}
vim.api.nvim_create_autocmd('ColorScheme', {
  callback = function() _rd_dyn_groups = {}; _ansi_cache = nil end,
})

local function rd_hl_for(attrs)
  -- Mimic terminal "bold = bright": bold + standard 4-bit colour (0-7) → use
  -- the bright variant (index+8).  This matches how terminal emulators render
  -- ESC[1;32m as bright green rather than bold-weight soft green.
  local fg = attrs.fg
  local bg = attrs.bg
  if attrs.bold and attrs._fg_idx then fg = ansi4(attrs._fg_idx + 8) end
  if attrs.bold and attrs._bg_idx then bg = ansi4(attrs._bg_idx + 8) end

  local parts = {}
  if fg         then parts[#parts+1] = 'f' .. fg:sub(2) end
  if bg         then parts[#parts+1] = 'b' .. bg:sub(2) end
  if attrs.bold      then parts[#parts+1] = 'B' end
  if attrs.italic    then parts[#parts+1] = 'I' end
  if attrs.underline then parts[#parts+1] = 'U' end
  if attrs.reverse   then parts[#parts+1] = 'R' end
  if #parts == 0 then return nil end
  local name = 'PRRd_' .. table.concat(parts)
  if not _rd_dyn_groups[name] then
    vim.api.nvim_set_hl(0, name, {
      fg        = fg,
      bg        = bg,
      bold      = attrs.bold,
      italic    = attrs.italic,
      underline = attrs.underline,
      reverse   = attrs.reverse,
    })
    _rd_dyn_groups[name] = true
  end
  return name
end

-- Parse ANSI SGR codes in `raw_lines` and apply the resulting colours as
-- extmarks on `buf`.  `stripped_lines` provides the plain-text line lengths
-- needed to correctly clamp trailing spans to end-of-line.
local function apply_rd_ansi_highlights(buf, raw_lines, stripped_lines)
  vim.api.nvim_buf_clear_namespace(buf, rd_hl_ns, 0, -1)
  for lnum, raw_line in ipairs(raw_lines) do
    local pos       = 1    -- position in raw_line (1-indexed)
    local spos      = 0    -- byte position in the stripped equivalent (0-indexed)
    local hl        = nil  -- currently active highlight group name
    local hl_s      = 0    -- byte start of the current HL span
    local cur_attrs = {}   -- accumulated SGR state (reset clears this)

    local function close_span(end_col)
      if hl and end_col > hl_s then
        vim.api.nvim_buf_set_extmark(buf, rd_hl_ns, lnum - 1, hl_s, {
          end_row  = lnum - 1,
          end_col  = end_col,
          hl_group = hl,
          priority = 90,
        })
        hl = nil
      end
    end

    while pos <= #raw_line do
      local esc_s, esc_e, codes = raw_line:find('\027%[([^m]*)m', pos)
      if not esc_s then
        spos = spos + #raw_line:sub(pos)
        break
      end
      spos = spos + (esc_s - pos)   -- plain-text bytes before this escape
      close_span(spos)
      local delta = parse_sgr(codes)
      if delta == nil then
        cur_attrs = {}   -- ESC[0m or ESC[m: full reset
      else
        -- If fg/bg colour changes, clear the old 4-bit index (it belongs to
        -- the previous colour and must not promote the new one incorrectly).
        if delta.fg then cur_attrs._fg_idx = nil end
        if delta.bg then cur_attrs._bg_idx = nil end
        for k, v in pairs(delta) do cur_attrs[k] = v end
      end
      hl   = next(cur_attrs) ~= nil and rd_hl_for(cur_attrs) or nil
      hl_s = spos
      pos  = esc_e + 1
    end
    close_span(#(stripped_lines[lnum] or ''))
  end
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
-- PR picker helpers
-- ─────────────────────────────────────────────────────────

-- Returns a human-readable "time ago" string from an ISO 8601 timestamp.
local function time_ago(iso_str)
  if not iso_str or iso_str == '' then return '' end
  local y, mo, d, h, m, s = iso_str:match('(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)')
  if not y then return '' end
  -- os.time() has no UTC mode: it treats the table fields as local time.
  -- GitHub timestamps are UTC, so we must correct for the local UTC offset.
  local t_as_local = os.time({
    year = tonumber(y), month = tonumber(mo), day = tonumber(d),
    hour = tonumber(h), min   = tonumber(m),  sec = tonumber(s),
    isdst = false,
  })
  local now = os.time()
  local utc_fields = os.date('!*t', now)
  utc_fields.isdst = false
  local utc_offset = now - os.time(utc_fields)  -- seconds east of UTC
  local t    = t_as_local - utc_offset
  local diff = os.difftime(now, t)
  if diff < 60   then return 'just now'
  elseif diff < 3600  then return math.floor(diff / 60)   .. 'm ago'
  elseif diff < 86400 then return math.floor(diff / 3600) .. 'h ago'
  end
  local days = math.floor(diff / 86400)
  if days == 1        then return '1d ago'
  elseif days < 30    then return days                    .. 'd ago'
  elseif days < 365   then return math.floor(days / 30)  .. 'mo ago'
  else                     return math.floor(days / 365) .. 'y ago'
  end
end

-- Reduces a statusCheckRollup array to a single symbol: ✓ / ✗ / ~ / -
local function rollup_symbol(checks)
  if not checks or type(checks) ~= 'table' or #checks == 0 then return '-' end
  local has_fail, has_pending = false, false
  for _, c in ipairs(checks) do
    local s = ((c.state or c.conclusion or c.status or '')):upper()
    if s == 'FAILURE' or s == 'ERROR' or s == 'FAILED' then
      has_fail = true
    elseif s == 'PENDING' or s == 'IN_PROGRESS' or s == 'QUEUED' or s == 'WAITING' then
      has_pending = true
    end
  end
  if has_fail    then return '✗' end
  if has_pending then return '~' end
  return '✓'
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

-- Buffer-local keymaps and autocmds for the range-diff pane.
-- Called once from setup_layout; the buffer persists across tip changes.
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

  -- Populate the range-diff buffer (a regular nofile buffer) with plain text
  -- and apply ANSI-derived extmark highlights.  Using a regular buffer means
  -- Neovim wraps lines visually (one buffer line = one logical line), so line
  -- numbers, extmarks and cursor row all correspond to logical lines directly.
  local buf = s.range_diff_buf
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, s.range_diff_lines)
  vim.bo[buf].modifiable = false
  apply_rd_ansi_highlights(buf, raw_lines, s.range_diff_lines)

  -- Annotate comment icons (reads s.range_diff_lines)
  annotate_range_diff_comments(buf, s.all_comments, tip.sha)

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
  local cur_row = cursor[1]  -- 1-indexed terminal row (may include wrap-continuation rows)
  local cur_col = cursor[2] + 1  -- 1-indexed

  -- Buffer row == logical line index (regular buffer, visual wrap only).
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
        local url = thread.comments[1].html_url
        -- Use the Files-changed deep-link for inline review comments
        if thread.is_files_changed then
          url = url:gsub('/pull/(%d+)#discussion_r(%d+)', '/pull/%1/changes#r%2')
        end
        return url
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

  local width = math.min(200, vim.o.columns - 4)

  -- Truncate s to at most max_len bytes, appending '...' if cut.
  -- If max_len < min_len the string is returned unchanged ("give up").
  local function trunc(s, max_len, min_len)
    min_len = min_len or 6
    if #s <= max_len then return s end
    if max_len < min_len then return s end
    if max_len <= 3 then return s:sub(1, max_len) end
    return s:sub(1, max_len - 3) .. '...'
  end

  -- ── Pass 1: extract field data, detect which optional columns are needed ──
  local data = {}
  local any_cmt, any_labels, any_assignees = false, false, false
  for _, pr in ipairs(prs) do
    local n_cmt = pr.totalCommentsCount or 0

    local label_parts = {}
    if type(pr.labels) == 'table' then
      for _, lbl in ipairs(pr.labels) do
        table.insert(label_parts, '[' .. (type(lbl)=='string' and lbl or lbl.name or '?') .. ']')
      end
    end
    local labels_str = table.concat(label_parts, ' ')

    local assignee_parts = {}
    if type(pr.assignees) == 'table' then
      for _, a in ipairs(pr.assignees) do
        table.insert(assignee_parts, '@' .. (type(a)=='string' and a or a.login or '?'))
      end
    end
    local assignees_str = table.concat(assignee_parts, ' ')

    if n_cmt     > 0 then any_cmt       = true end
    if labels_str   ~= '' then any_labels    = true end
    if assignees_str~= '' then any_assignees = true end

    table.insert(data, {
      number    = pr.number,
      url       = pr.url or '',
      author    = (pr.author and pr.author.login) or '?',
      title     = pr.title or '',
      state     = pr.isDraft and 'draft' or 'open',
      checks    = rollup_symbol(pr.statusCheckRollup),
      n_cmt     = n_cmt,
      labels    = labels_str,
      assignees = assignees_str,
      updated   = time_ago(pr.updatedAt),
      created   = time_ago(pr.createdAt),
    })
  end

  -- ── Column widths ──────────────────────────────────────────────────────────
  -- All widths are in display columns (= bytes for ASCII; UTF-8 handled below).
  local SEP         = '  '           -- separator between every column
  local W_NUM       = 9              -- 'PR number' (header) / '#NNNNN  ' (content)
  local W_STATE     = 5              -- 'open ' / 'draft'
  local W_CHECKS    = 2              -- symbol (1 col) + 1 padding space
  local W_CMT       = 8              -- 'Comments' (header) / up to '9999'
  local W_UPDATED   = 8              -- 'just now'
  local W_CREATED   = 8              -- 'just now'
  local W_AUTHOR    = math.max(6,  math.min(18, math.floor(width * 0.11)))
  local W_LABELS    = math.max(8,  math.min(30, math.floor(width * 0.13)))
  local W_ASSIGNEES = math.max(8,  math.min(24, math.floor(width * 0.11)))

  -- Overhead = everything except title + the separators around it.
  local S = #SEP
  local overhead = W_NUM + S
    + W_AUTHOR + S
    + S + W_STATE + S       -- sep before title absorbed here as: ...author SEP title SEP state...
    + W_CHECKS + S
    + (any_cmt       and (W_CMT       + S) or 0)
    + (any_labels    and (W_LABELS    + S) or 0)
    + (any_assignees and (W_ASSIGNEES + S) or 0)
    + W_UPDATED + S
    + W_CREATED               -- last column: no trailing separator
  local W_TITLE = math.max(15, width - overhead)

  -- col(s, w): truncate then left-pad to exactly w bytes.
  -- For the give-up case (w < min_len), the string is not padded either.
  local function col(s, w, min_w)
    local t = trunc(s, w, min_w or 6)
    if #t >= w then return t end
    return string.format('%-' .. w .. 's', t)
  end

  -- The checks symbol is 1 display-column wide but may be 3 UTF-8 bytes.
  -- Appending a literal space makes it consistently W_CHECKS (= 2) display cols.
  local function checks_col(sym) return sym .. ' ' end

  -- ── Pass 2: build header + content lines ──────────────────────────────────
  local function build_row(num_s, author_s, title_s, state_s, checks_s,
                           cmt_s, labels_s, assignees_s, updated_s, created_s)
    local parts = {
      col(num_s,    W_NUM,    1),
      col(author_s, W_AUTHOR),
      col(title_s,  W_TITLE),
      col(state_s,  W_STATE,  1),
      checks_s,  -- already W_CHECKS display cols
    }
    if any_cmt       then table.insert(parts, col(cmt_s,       W_CMT,       1)) end
    if any_labels    then table.insert(parts, col(labels_s,    W_LABELS))       end
    if any_assignees then table.insert(parts, col(assignees_s, W_ASSIGNEES))    end
    table.insert(parts, col(updated_s, W_UPDATED, 1))
    table.insert(parts, created_s)          -- last column: no padding needed
    return table.concat(parts, SEP)
  end

  local header_line = build_row(
    'PR number', 'Author', 'Title', 'State', 'CI',
    'Comments', 'Labels', 'Assignees', 'Updated', 'Created'
  )

  -- Content lines start at display line 2 (line 1 = header).
  local lines      = { header_line }
  local pr_numbers = {}
  local pr_urls    = {}
  for i, d in ipairs(data) do
    local cmt_str = d.n_cmt > 0 and tostring(d.n_cmt) or '-'
    table.insert(lines, build_row(
      string.format('#%d', d.number),
      '@' .. d.author,
      d.title,
      d.state,
      checks_col(d.checks),
      cmt_str,
      d.labels,
      d.assignees,
      d.updated,
      d.created
    ))
    pr_numbers[i] = d.number
    pr_urls[i]    = d.url
  end

  local height = math.min(#lines, math.floor(vim.o.lines * 0.8))
  local row    = math.floor((vim.o.lines - height) / 2)
  local c      = math.floor((vim.o.columns - width) / 2)

  local picker_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[picker_buf].buftype    = 'nofile'
  vim.bo[picker_buf].bufhidden  = 'wipe'
  vim.bo[picker_buf].modifiable = true
  vim.api.nvim_buf_set_lines(picker_buf, 0, -1, false, lines)
  -- Highlight the header line so it stands out from the PR rows.
  vim.api.nvim_buf_add_highlight(picker_buf, -1, 'Title', 0, 0, -1)
  vim.bo[picker_buf].modifiable = false

  local picker_win = vim.api.nvim_open_win(picker_buf, true, {
    relative  = 'editor',
    row       = row,
    col       = c,
    width     = width,
    height    = height,
    style     = 'minimal',
    border    = 'rounded',
    title     = string.format(' Open PRs — %s/%s  (<CR> open · K details · q close) ', owner, repo),
    title_pos = 'center',
  })
  vim.wo[picker_win].cursorline = true
  vim.wo[picker_win].number     = false
  -- Start on first PR, not the header.
  vim.api.nvim_win_set_cursor(picker_win, { 2, 0 })

  local o = { noremap = true, silent = true, buffer = picker_buf }

  local function close()
    if vim.api.nvim_win_is_valid(picker_win) then
      vim.api.nvim_win_close(picker_win, true)
    end
  end

  -- Line 1 = header (non-navigable); PR index = cursor_line - 1.
  local function pr_idx_at_cursor()
    local line = vim.api.nvim_win_get_cursor(picker_win)[1]
    local idx  = line - 1
    return (idx >= 1 and idx <= #prs) and idx or nil
  end

  vim.keymap.set('n', '<CR>', function()
    local idx = pr_idx_at_cursor()
    close()
    if idx then M.open(pr_numbers[idx]) end
  end, o)

  vim.keymap.set('n', '<leader>gx', function()
    local idx = pr_idx_at_cursor()
    if idx and pr_urls[idx] then vim.ui.open(pr_urls[idx]) end
  end, o)

  -- K: floating popup with full untruncated PR metadata (wrapping OK).
  vim.keymap.set('n', 'K', function()
    local idx = pr_idx_at_cursor()
    if not idx then return end
    local d = data[idx]
    local popup_lines = {
      string.format('**#%d** — %s', d.number, d.title),
      '',
      string.format('**Author:**    @%s', d.author),
      string.format('**State:**     %s',  d.state),
      string.format('**Checks:**    %s',  d.checks),
    }
    if d.n_cmt > 0 then
      table.insert(popup_lines, string.format('**Comments:**  %d', d.n_cmt))
    end
    if d.labels ~= '' then
      table.insert(popup_lines, string.format('**Labels:**    %s', d.labels))
    end
    if d.assignees ~= '' then
      table.insert(popup_lines, string.format('**Assignees:** %s', d.assignees))
    end
    if d.updated ~= '' then
      table.insert(popup_lines, string.format('**Updated:**   %s', d.updated))
    end
    if d.created ~= '' then
      table.insert(popup_lines, string.format('**Created:**   %s', d.created))
    end
    if d.url ~= '' then
      table.insert(popup_lines, '')
      table.insert(popup_lines, d.url)
    end

    local float_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, popup_lines)
    vim.bo[float_buf].filetype   = 'markdown'
    vim.bo[float_buf].modifiable = false

    local fw = math.min(72, vim.o.columns - 6)
    local fh = math.min(#popup_lines, math.floor(vim.o.lines * 0.5))
    local float_win = vim.api.nvim_open_win(float_buf, false, {
      relative  = 'cursor',
      row       = 1,
      col       = 0,
      width     = fw,
      height    = fh,
      style     = 'minimal',
      border    = 'rounded',
      title     = string.format(' PR #%d ', d.number),
      title_pos = 'center',
      zindex    = 100,
    })
    vim.wo[float_win].wrap      = true
    vim.wo[float_win].linebreak = true

    vim.schedule(function()
      local aug = vim.api.nvim_create_augroup('pr_picker_popup', { clear = true })
      vim.api.nvim_create_autocmd({ 'CursorMoved', 'BufLeave' }, {
        group    = aug,
        buffer   = picker_buf,
        once     = true,
        callback = function()
          if vim.api.nvim_win_is_valid(float_win) then
            vim.api.nvim_win_close(float_win, true)
          end
          if vim.api.nvim_buf_is_valid(float_buf) then
            vim.api.nvim_buf_delete(float_buf, { force = true })
          end
        end,
      })
    end)
  end, o)

  -- Snap cursor off the header line (e.g. after gg or mouse click).
  vim.api.nvim_create_autocmd('CursorMoved', {
    buffer = picker_buf,
    callback = function()
      if vim.api.nvim_win_is_valid(picker_win)
        and vim.api.nvim_win_get_cursor(picker_win)[1] == 1
      then
        vim.api.nvim_win_set_cursor(picker_win, { 2, 0 })
      end
    end,
  })

  vim.keymap.set('n', 'q',     close, o)
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
