-- gdb_mi_signs: sign-column UI, and optional cursor-follows-execution,
-- on top of gdb_mi_broker_client's on_breakpoint/on_stopped/on_running/
-- on_connect/on_disconnect callbacks. See M.setup() for options.
--
-- A freshly-connected client re-queries gdb's current breakpoints and
-- execution position (see gdb_mi_broker_client's M.sync()), so signs
-- and follow_cursor stay correct when connecting mid-session.

local M = {}

local client = require("gdb_mi.broker_client")

local GROUP = "gdb_mi_signs"

local SIGN_BREAKPOINT = "GdbMiBreakpoint"
local SIGN_EXECUTION = "GdbMiExecution"
local SIGN_EXEC_ON_BREAKPOINT = "GdbMiExecutionOnBreakpoint"

local PRIORITY_BREAKPOINT = 10
local PRIORITY_EXECUTION = 10
local PRIORITY_EXEC_ON_BREAKPOINT = 20

M._enabled = { breakpoints = false, execution = false, follow_cursor = false }

-- Set while we force-load a buffer so it can host a sign; if a stale
-- swapfile from a crashed session exists for that file, auto-chooses
-- "edit anyway" instead of blocking on a prompt.
local loading_for_signs = false

local function ensure_loaded(bufnr)
  if vim.api.nvim_buf_is_loaded(bufnr) then return end
  loading_for_signs = true
  pcall(vim.fn.bufload, bufnr)
  loading_for_signs = false
end

-- bkpt id -> last known {file, line}, so we know what to decrement when
-- a breakpoint moves (e.g. a pending breakpoint resolves) or is deleted.
local bp_by_id = {}
-- "file\0line" -> number of breakpoints at that location (more than one
-- is possible, e.g. distinct breakpoints at the same source line).
local bp_count = {}
-- current execution location ({file, line}), or nil if not stopped.
local current = nil

local function loc_key(file, line)
  return file .. "\0" .. line
end

-- TODO move, a pure signs module shouldn't do/expose this
function M.has_breakpoint(file, line)
  return file ~= nil and line ~= nil and (bp_count[loc_key(file, line)] or 0) > 0
end

-- Note that multiple breakpoints may have the same location. Get one of them
function M.get_bp_id(file, line)
    for id, bp in pairs(bp_by_id) do
        if bp.file == file and bp.line == line then
            return id
        end
    end
    return nil
end

local function is_current(file, line)
  return current ~= nil and current.file == file and current.line == line
end

-- Places or clears whichever sign belongs on file:line, based on the
-- current breakpoint/execution state. Safe to call redundantly.
local function refresh(file, line)
  if not file or not line then return end

  local bufnr = vim.fn.bufnr(file)
  if bufnr == -1 then
    -- Must be loaded (not just added), otherwise sign_place clamps
    -- lnum down to the empty placeholder buffer's line count.
    bufnr = vim.fn.bufadd(file)
  end
  if not bufnr or bufnr == 0 then return end
  ensure_loaded(bufnr)

  vim.fn.sign_unplace(GROUP, { buffer = bufnr, id = line })

  local bp = M._enabled.breakpoints and M.has_breakpoint(file, line)
  local exec = M._enabled.execution and is_current(file, line)

  local name, prio
  if bp and exec then
    name, prio = SIGN_EXEC_ON_BREAKPOINT, PRIORITY_EXEC_ON_BREAKPOINT
  elseif bp then
    name, prio = SIGN_BREAKPOINT, PRIORITY_BREAKPOINT
  elseif exec then
    name, prio = SIGN_EXECUTION, PRIORITY_EXECUTION
  else
    return
  end

  vim.fn.sign_place(line, GROUP, name, bufnr, { lnum = line, priority = prio })
end

local function on_breakpoint(action, file, line, bkpt)
  local id = bkpt and bkpt.number
  local old = id and bp_by_id[id]

  if old then
    local key = loc_key(old.file, old.line)
    bp_count[key] = (bp_count[key] or 1) - 1
    if bp_count[key] <= 0 then bp_count[key] = nil end
  end

  if action == "deleted" or not (file and line) then
    if id then bp_by_id[id] = nil end
  else
    bp_count[loc_key(file, line)] = (bp_count[loc_key(file, line)] or 0) + 1
    if id then bp_by_id[id] = { file = file, line = line } end
  end

  if old and (old.file ~= file or old.line ~= line) then
    refresh(old.file, old.line)
  end
  refresh(file, line)
end

local function goto_pos(file, pos)
  local bufnr = vim.fn.bufnr(file)
  if bufnr == -1 then bufnr = vim.fn.bufadd(file) end
  if not bufnr or bufnr == 0 then return end
  ensure_loaded(bufnr)
  vim.api.nvim_set_current_buf(bufnr)
  pcall(vim.api.nvim_win_set_cursor, 0, pos)
end

function M.goto_cursor()
  if not current then return end
  goto_pos(current.file, { current.line, 0 })
  vim.api.nvim_input("_") -- KISS
end

local function on_stopped(file, pos)
  local old = current
  current = (file and pos) and { file = file, line = pos[1] } or nil
  if old then refresh(old.file, old.line) end
  if current then refresh(current.file, current.line) end

  if M._enabled.follow_cursor then
    M.goto_cursor()
  end
end

local function on_running()
  local old = current
  current = nil
  if old then refresh(old.file, old.line) end
end

local function clear_all()
  vim.fn.sign_unplace(GROUP)
  bp_by_id = {}
  bp_count = {}
  current = nil
end

function M.setup(opts)
  opts = opts or {}
  M._enabled.breakpoints = opts.breakpoints ~= false
  M._enabled.execution = opts.execution ~= false
  M._enabled.follow_cursor = opts.follow_cursor ~= false

  vim.fn.sign_define(SIGN_BREAKPOINT, { text = "●" })
  vim.fn.sign_define(SIGN_EXECUTION, { text = "➜" })
  vim.fn.sign_define(SIGN_EXEC_ON_BREAKPOINT, { text = "󰆤" })

  if M._enabled.breakpoints then
    client.on_breakpoint(on_breakpoint)
  end
  if M._enabled.execution or M._enabled.follow_cursor then
    client.on_stopped(on_stopped)
    client.on_running(on_running)
  end
  if M._enabled.breakpoints or M._enabled.execution or M._enabled.follow_cursor then
    client.on_connect(client.sync)
    vim.api.nvim_create_autocmd("SwapExists", {
      callback = function()
        if loading_for_signs then vim.v.swapchoice = "e" end
      end,
    })
  end

  client.on_disconnect(clear_all)

  vim.api.nvim_create_user_command("GdbMiGotoCursor", M.goto_cursor, {})
end

return M
