-- pr_review.api: Git and GitHub API operations

local M = {}

local function run(cmd)
  local result = vim.fn.system(cmd)
  return result, vim.v.shell_error
end

local function run_list(cmd)
  local result = vim.fn.systemlist(cmd)
  return result, vim.v.shell_error
end

local function parse_json(str)
  if not str or str == '' then return nil end
  local ok, decoded = pcall(vim.fn.json_decode, str)
  if not ok then return nil end
  return decoded
end

-- Parse newline-delimited JSON (one object per line)
local function parse_ndjson(str)
  local results = {}
  for line in (str or ''):gmatch('[^\n]+') do
    local trimmed = vim.trim(line)
    if trimmed:sub(1, 1) == '{' or trimmed:sub(1, 1) == '[' then
      local ok, decoded = pcall(vim.fn.json_decode, trimmed)
      if ok and decoded then
        table.insert(results, decoded)
      end
    end
  end
  return results
end

function M.get_repo_info()
  local out, code = run('gh repo view --json owner,name 2>/dev/null')
  if code ~= 0 then return nil, nil end
  local data = parse_json(out)
  if not data then return nil, nil end
  return data.owner.login, data.name
end

function M.get_pr_info(pr_number)
  local cmd
  if pr_number then
    cmd = string.format(
      'gh pr view %d --json number,title,headRefName,baseRefName,headRefOid,url 2>&1',
      pr_number
    )
  else
    cmd = 'gh pr view --json number,title,headRefName,baseRefName,headRefOid,url 2>&1'
  end
  local out, code = run(cmd)
  if code ~= 0 then return nil, vim.trim(out) end
  local data = parse_json(out)
  if not data then return nil, 'invalid JSON from gh: ' .. vim.trim(out) end
  return data, nil
end

-- Returns force-push events from PR timeline, each with {before, after, date}.
-- Uses GraphQL because the REST issue timeline omits commit SHAs for this event type.
function M.get_force_push_events(owner, repo, pr_number)
  local query = string.format(
    '{ repository(owner: "%s", name: "%s") { pullRequest(number: %d) { timelineItems(first: 100, itemTypes: [HEAD_REF_FORCE_PUSHED_EVENT]) { nodes { ... on HeadRefForcePushedEvent { beforeCommit { oid } afterCommit { oid } createdAt } } } } } }',
    owner, repo, pr_number
  )
  local cmd = 'gh api graphql -f query=' .. vim.fn.shellescape(query) .. ' 2>/dev/null'
  local out, code = run(cmd)
  if code ~= 0 then return {} end
  local data = parse_json(out)
  local nodes = data
    and data.data
    and data.data.repository
    and data.data.repository.pullRequest
    and data.data.repository.pullRequest.timelineItems
    and data.data.repository.pullRequest.timelineItems.nodes
  if not nodes then return {} end
  local events = {}
  for _, node in ipairs(nodes) do
    if node.beforeCommit and node.afterCommit then
      table.insert(events, {
        before = node.beforeCommit.oid,
        after  = node.afterCommit.oid,
        date   = node.createdAt,
      })
    end
  end
  return events
end

-- Returns all inline PR review comments
function M.get_comments(owner, repo, pr_number)
  -- Use --jq '.[]' so --paginate emits NDJSON (one object per line) instead of
  -- multiple raw JSON arrays that cannot be decoded as a single value.
  local cmd = string.format(
    "gh api '/repos/%s/%s/pulls/%d/comments' --paginate --jq '.[]' 2>/dev/null",
    owner, repo, pr_number
  )
  local out, code = run(cmd)
  if code ~= 0 then return {} end
  return parse_ndjson(out)
end

-- Determine the git remote that corresponds to the PR's head repository.
-- Tries, in order:
--   1. The tracking remote of the local branch with that name
--   2. A remote whose URL contains owner/repo
--   3. Falls back to 'origin'
function M.get_pr_remote(head_ref_name, owner, repo)
  -- Check if the branch exists locally and has a configured remote
  local out, code = run('git config branch.' .. head_ref_name .. '.remote 2>/dev/null')
  if code == 0 and vim.trim(out) ~= '' then
    return vim.trim(out)
  end
  -- Scan remotes for one whose URL matches the repo
  local remotes, _ = run('git remote -v 2>/dev/null')
  for remote, url in remotes:gmatch('(%S+)%s+(%S+)%s+%(fetch%)') do
    if url:match(vim.pesc(owner) .. '/' .. vim.pesc(repo)) then
      return remote
    end
  end
  return 'origin'
end

-- Try to make a SHA available locally by fetching it from the given remote.
function M.ensure_sha_available(sha, remote)
  local _, code = run('git cat-file -t ' .. sha .. ' 2>/dev/null')
  if code == 0 then return true end
  local r = remote or 'origin'
  local _, fetch_code = run('git fetch ' .. r .. ' ' .. sha .. ' 2>/dev/null')
  if fetch_code == 0 then return true end
  return false
end

-- Get merge base via GitHub's compare API — always matches what GitHub shows.
-- base_ref: branch name (e.g. "develop"), head_sha: commit SHA
function M.get_merge_base(owner, repo, base_ref, head_sha)
  local cmd = string.format(
    'gh api repos/%s/%s/compare/%s...%s --jq .merge_base_commit.sha 2>&1',
    owner, repo, base_ref, head_sha
  )
  local out, code = run(cmd)
  if code ~= 0 then return nil end
  local sha = vim.trim(out)
  if sha == '' or #sha < 10 then return nil end
  return sha
end

-- Run git range-diff between two tip commits relative to a common base.
-- Emits ANSI color codes so the caller can map them to highlight groups.
function M.range_diff(base, old_tip, new_tip)
  local cmd = string.format(
    'git range-diff --color=always --abbrev=9 %s %s %s 2>/dev/null',
    base, old_tip, new_tip
  )
  local lines, code = run_list(cmd)
  if code ~= 0 then return nil end
  return lines
end

-- Get full diff+metadata for a commit
function M.show_commit(sha)
  local cmd = 'git show --no-color ' .. sha .. ' 2>/dev/null'
  local lines, code = run_list(cmd)
  if code ~= 0 then return nil end
  return lines
end

-- Get timeline events for a PR (reviews, deployments, issue comments).
-- Returns raw NDJSON-decoded objects; callers filter by .event field.
function M.get_pr_log(owner, repo, pr_number)
  local cmd = string.format(
    "gh api '/repos/%s/%s/issues/%d/timeline' --paginate --jq '.[]' 2>/dev/null",
    owner, repo, pr_number
  )
  local out, code = run(cmd)
  if code ~= 0 then return {} end
  return parse_ndjson(out)
end

-- Get one-line log for commits in base..tip range (with git log colors)
function M.log_range(base, tip)
  local cmd = string.format(
    "git log --color=always --reverse --abbrev=9 --format='%%C(yellow)%%h%%Creset %%s' %s..%s 2>/dev/null",
    base, tip
  )
  local lines, code = run_list(cmd)
  if code ~= 0 then return {} end
  return lines
end

-- Get subject line of a commit
function M.commit_subject(sha)
  local out, code = run('git log -1 --format=%s ' .. sha .. ' 2>/dev/null')
  if code ~= 0 then return nil end
  return vim.trim(out)
end

-- Get date of a commit
function M.commit_date(sha)
  local out, code = run('git log -1 --format=%ci ' .. sha .. ' 2>/dev/null')
  if code ~= 0 then return '' end
  return vim.trim(out):sub(1, 16)
end

-- Return list of {status, path} for all files changed in base..tip.
function M.get_changed_files(base, tip)
  local lines, code = run_list(
    'git diff --name-status ' .. base .. '..' .. tip .. ' 2>/dev/null')
  if code ~= 0 then return {} end
  local result = {}
  for _, line in ipairs(lines) do
    local status, path = line:match('^([A-Z%d]+)%s+(.+)$')
    if status and path then
      table.insert(result, { status = status, path = path })
    end
  end
  return result
end

-- List open PRs for the repo via GraphQL (needed for totalCommentsCount,
-- which is not available in `gh pr list --json`).
-- Returns [{number, title, author, url, createdAt, updatedAt, isDraft, state,
--           labels, assignees, totalCommentsCount, totalCommitsCount, statusCheckRollup}]
-- with shapes compatible with the rest of the codebase.
function M.list_open_prs(owner, repo)
  local query = string.format(
    '{ repository(owner: "%s", name: "%s") {'
    .. ' pullRequests(first: 100, states: OPEN, orderBy: {field: UPDATED_AT, direction: DESC}) {'
    .. ' nodes { number title url createdAt updatedAt isDraft state totalCommentsCount'
    .. ' author { login }'
    .. ' labels(first: 20) { nodes { name } }'
    .. ' assignees(first: 10) { nodes { login } }'
    .. ' commitCount: commits { totalCount }'
    .. ' latestCommit: commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }'
    .. ' } } } }',
    owner, repo
  )
  local cmd = 'gh api graphql -f query=' .. vim.fn.shellescape(query) .. ' 2>/dev/null'
  local out, code = run(cmd)
  if code ~= 0 then return {} end
  local data = parse_json(out)
  local nodes = data
    and data.data
    and data.data.repository
    and data.data.repository.pullRequests
    and data.data.repository.pullRequests.nodes
  if not nodes then return {} end

  local result = {}
  for _, node in ipairs(nodes) do
    -- Flatten nested GraphQL connection types to simple arrays.
    local labels    = (node.labels    and node.labels.nodes)    or {}
    local assignees = (node.assignees and node.assignees.nodes) or {}

    -- statusCheckRollup comes as a single {state} object; wrap in array so
    -- rollup_symbol() can iterate it without changes.
    local checks = {}
    local cn = node.latestCommit and node.latestCommit.nodes and node.latestCommit.nodes[1]
    local rollup = cn and cn.commit and cn.commit.statusCheckRollup
    if type(rollup) == 'table' then
      table.insert(checks, { state = rollup.state })
    end

    table.insert(result, {
      number             = node.number,
      title              = node.title,
      url                = node.url,
      createdAt          = node.createdAt,
      updatedAt          = node.updatedAt,
      isDraft            = node.isDraft,
      state              = node.state,
      author             = node.author,
      labels             = labels,
      assignees          = assignees,
      totalCommentsCount = node.totalCommentsCount or 0,
      totalCommitsCount  = (node.commitCount and node.commitCount.totalCount) or 0,
      statusCheckRollup  = checks,
    })
  end
  return result
end

-- Return diff lines for a single file across base..tip.
function M.diff_file(base, tip, path)
  local lines, code = run_list(
    'git diff ' .. base .. '..' .. tip .. ' -- ' .. vim.fn.shellescape(path) .. ' 2>/dev/null')
  if code ~= 0 then return { 'Error: could not diff ' .. path } end
  if #lines == 0 then return { '(no changes for ' .. path .. ')' } end
  return lines
end

-- Return a set (table with path keys = true) of files changed by a commit.
-- Results are cached for the lifetime of the process.
local files_in_commit_cache = {}
function M.files_in_commit(sha)
  if files_in_commit_cache[sha] then return files_in_commit_cache[sha] end
  local lines, code = run_list('git diff-tree --no-commit-id -r --name-only ' .. sha .. ' 2>/dev/null')
  local set = {}
  if code == 0 then
    for _, f in ipairs(lines) do
      local trimmed = vim.trim(f)
      if trimmed ~= '' then set[trimmed] = true end
    end
  end
  files_in_commit_cache[sha] = set
  return set
end

-- Return true if commit is an ancestor of tip (i.e. commit is in tip's history).
-- Results are cached.
local is_ancestor_cache = {}
function M.is_ancestor(commit, tip)
  local key = commit .. '..' .. tip
  if is_ancestor_cache[key] ~= nil then return is_ancestor_cache[key] end
  vim.fn.system('git merge-base --is-ancestor ' .. commit .. ' ' .. tip .. ' 2>/dev/null')
  local result = (vim.v.shell_error == 0)
  is_ancestor_cache[key] = result
  return result
end

return M
