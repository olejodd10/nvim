-- pr_review: GitHub PR review tool for Neovim
-- Usage: :PRReview [pr_number]

local M = {}

-- Global state shared across submodules
M.state = {
  -- PR info
  pr_number = nil,
  owner = nil,
  repo = nil,
  pr_url = nil,
  pr_remote = nil,
  base_ref = nil,
  head_sha = nil,

  -- Tips: ordered newest first
  -- [{sha, short_sha, date, subject, is_current, is_initial}]
  tips = {},
  current_tip_idx = 1,

  -- Comments: all PR inline review comments
  all_comments = {},

  -- PR timeline: reviews, deployments, issue comments (from /issues/{n}/timeline)
  pr_log = {},

  -- Window/buffer IDs
  tips_buf = nil,
  tips_win = nil,
  range_diff_buf = nil,
  range_diff_win = nil,
  files_buf = nil,
  files_win = nil,
  diff_buf = nil,
  diff_win = nil,
  log_buf = nil,
  log_win = nil,

  -- files pane: 1-indexed line → {status, path}
  files_lines = {},

  -- Log pane: 1-indexed line number → entry table {at, icon, user, body, state?}
  log_line_entries = {},

  -- Caches
  range_diff_cache = {},  -- "prev_sha:tip_sha" -> lines
  show_cache = {},        -- sha -> lines
  merge_base_cache = {},  -- sha -> base_sha
}

function M.setup()
  vim.api.nvim_create_user_command('PRReview', function(opts)
    local args = vim.split(opts.args, '%s+', { trimempty = true })
    local pr_number = args[1] and tonumber(args[1]) or nil
    require('pr_review.ui').open(pr_number)
  end, {
    nargs = '*',
    desc = 'Open GitHub PR review. Usage: PRReview [pr_number]',
  })
end

return M
