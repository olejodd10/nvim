-- gdb_mi_broker_client: talks to an external, already-running GDB process
-- via the broker in ~/.config/nvim/gdb_mi_broker/broker.py, which fans a
-- single `new-ui mi4` channel out to any number of connected nvim
-- instances.
--
-- Commands:
--   :GdbMiConnect [gdb_pid]  - connect to a running broker
--   :GdbMiDisconnect         - disconnect
--   :GdbMiSendRaw <mi command> - send a raw MI command, e.g.
--                                :GdbMiSendRaw -break-insert main.c:10
--
-- M.GdbMiSendRaw(cmd, cb) is also the low-level API other modules (e.g.
-- gdb_mi_ops) build on top of to implement higher-level operations.

local M = {}

local uv = vim.loop
local parse = require("gdb_mi.parse")

M.client = nil -- { pipe, buf, pending, gdb_pid, cwd, exe }

M._stopped_callbacks = {}
M._breakpoint_callbacks = {}
M._running_callbacks = {}
M._connect_callbacks = {}
M._disconnect_callbacks = {}

-- bkpt id -> last known {file, line}, so a =breakpoint-deleted event (which
-- only carries an id) can still be reported to callbacks with a location,
-- letting a sign-column consumer remove the right sign without having to
-- track this mapping itself.
M._bkpt_locations = {}

-- Registers `fn` to be called whenever GDB stops execution (breakpoint
-- hit, step/next/until/finish completing, a signal, etc. -- any *stopped
-- MI record), regardless of which broker client (if any) caused it to
-- run in the first place.
--
-- Called as fn(file, pos, info) where:
--   file = the fullname (falls back to the possibly-relative "file"
--          field) of the source location GDB stopped at, or nil if GDB
--          didn't report one (e.g. stopped in a function without
--          debug info)
--   pos  = {line, 0} -- same shape as the second argument to
--          nvim_win_set_cursor(), so you can do:
--            vim.api.nvim_win_set_cursor(win, pos)
--   info = { reason = payload.reason, thread_id = payload["thread-id"],
--            raw = payload } for anything else you might need
function M.on_stopped(fn)
  table.insert(M._stopped_callbacks, fn)
end

-- Registers `fn` to be called whenever a breakpoint or watchpoint is
-- created, modified, deleted or disabled/enabled -- regardless of which
-- broker client (if any) caused the change, including changes made
-- directly at GDB's own terminal.
--
-- Called as fn(action, file, line, bkpt) where:
--   action = "created" | "modified" | "deleted"
--   file, line = the breakpoint's source location, mirroring the
--          bufnr/lnum pair nvim-dap's breakpoint list keys on (nil for
--          deleted breakpoints GDB never reported a location for, and
--          nil for plain watchpoints, which aren't tied to a line)
--   bkpt = the parsed MI breakpoint tuple (number, enabled, condition,
--          ...) for "created"/"modified"; for "deleted" only
--          bkpt.number is guaranteed to be set
function M.on_breakpoint(fn)
  table.insert(M._breakpoint_callbacks, fn)
end

-- Registers `fn` to be called whenever GDB resumes execution (continue,
-- next/step/until/finish starting, etc. -- any *running MI record). Use
-- this to know when there's no longer a well-defined "current line"
-- (e.g. to clear an execution-position sign while the program runs).
--
-- Called as fn(thread_id) where thread_id is payload["thread-id"]
-- ("all" or a specific thread id).
function M.on_running(fn)
  table.insert(M._running_callbacks, fn)
end

-- Registers `fn` to be called whenever this client disconnects from the
-- broker (explicit :GdbMiDisconnect, connection closed/lost, or
-- reconnecting elsewhere). Takes no arguments; useful for consumers that
-- need to reset their own state (e.g. clear signs) since gdb-side state
-- is no longer being observed.
function M.on_disconnect(fn)
  table.insert(M._disconnect_callbacks, fn)
end

-- Registers `fn` to be called whenever this client successfully connects
-- to a broker (right after the hello handshake). Takes no arguments;
-- useful for consumers that need to (re)initialize their own state from
-- gdb's current state -- e.g. call M.sync() to replay existing
-- breakpoints/execution position through on_breakpoint/on_stopped, so
-- connecting mid-session doesn't leave a consumer's view empty until
-- the next change.
function M.on_connect(fn)
  table.insert(M._connect_callbacks, fn)
end

local function runtime_dir()
  local base = os.getenv("XDG_RUNTIME_DIR")
  if base and base ~= "" then
    return base .. "/gdb-mi"
  end
  return "/tmp/gdb-mi-" .. tostring(vim.fn.getuid())
end

local function notify(msg, level)
  vim.notify("[gdb_mi_broker_client] " .. msg, level or vim.log.levels.INFO)
end

function M.is_connected()
  return M.client ~= nil and not M.client.pipe:is_closing()
end

function M.disconnect()
  if M.client then
    if not M.client.pipe:is_closing() then
      M.client.pipe:close()
    end
    M.client = nil
    notify("disconnected")
    for _, fn in ipairs(M._disconnect_callbacks) do
      fn()
    end
  end
end

-- Discovers broker sockets. Returns a list of { path, gdb_pid }.
local function discover_sockets()
  local dir = runtime_dir()
  local results = {}
  local fd = uv.fs_scandir(dir)
  if not fd then return results end
  while true do
    local name, typ = uv.fs_scandir_next(fd)
    if not name then break end
    if typ == "socket" or name:match("%.sock$") then
      local pid = tonumber(name:match("^(%d+)%.sock$"))
      if pid then
        table.insert(results, { path = dir .. "/" .. name, gdb_pid = pid })
      end
    end
  end
  return results
end

local function on_line(line)
  if not M.client then return end
  if line:sub(1, 1) == "{" then
    local ok, decoded = pcall(vim.json.decode, line)
    if ok and decoded.type == "hello" then
      M.client.gdb_pid = decoded.gdb_pid
      M.client.cwd = decoded.cwd
      M.client.exe = decoded.exe
      notify(string.format(
        "connected to gdb pid=%s cwd=%s exe=%s",
        tostring(decoded.gdb_pid), tostring(decoded.cwd), tostring(decoded.exe)))
      for _, fn in ipairs(M._connect_callbacks) do
        fn()
      end
      return
    end
  end

  -- Result record: <token>^done|running|error[,...]
  local _, class, rest = line:match("^(%d*)%^(%a+),?(.*)$")
  if class then
    local payload = parse.parse_mi_results(rest)
    local cb = table.remove(M.client.pending, 1)
    if cb then cb(class, payload, line) end
    return
  end

  -- Async record: =event,... / *event,... / +event,...
  local _, event, arest = line:match("^([=%*%+])([%w%-]+),?(.*)$")
  if event then
    local payload = parse.parse_mi_results(arest)
    M.on_async(event, payload)
    return
  end

  -- Stream records (~"console", @"target", &"log") and the "(gdb)" prompt
  -- are ignored for now; uncomment to debug raw traffic:
  -- notify("raw: " .. line, vim.log.levels.DEBUG)
end

local function run_breakpoint_callbacks(action, file, line, bkpt)
  for _, fn in ipairs(M._breakpoint_callbacks) do
    fn(action, file, line, bkpt)
  end
end

local function run_stopped_callbacks(file, pos, info)
  for _, fn in ipairs(M._stopped_callbacks) do
    fn(file, pos, info)
  end
end

local function run_running_callbacks(thread_id)
  for _, fn in ipairs(M._running_callbacks) do
    fn(thread_id)
  end
end

function M.on_async(event, payload)
  if event == "breakpoint-created" or event == "breakpoint-modified" then
    local bkpt = payload.bkpt or {}
    if not bkpt.number then
      -- Shouldn't happen with real gdb output, but every consumer keys
      -- its own bookkeeping off bkpt.number (e.g. to know what to clean
      -- up on a later "deleted" event); firing without one would leak
      -- untrackable state, so just ignore the record.
      return
    end
    local file = bkpt.fullname or bkpt.file
    local line = tonumber(bkpt.line)
    M._bkpt_locations[bkpt.number] = { file = file, line = line }
    -- notify(string.format(
    --   "%s: #%s %s:%s", event, tostring(bkpt.number), tostring(file), tostring(line)))
    run_breakpoint_callbacks(event == "breakpoint-created" and "created" or "modified", file, line, bkpt)
  elseif event == "breakpoint-deleted" then
    local id = payload.id
    local loc = M._bkpt_locations[id] or {}
    M._bkpt_locations[id] = nil
    notify("breakpoint-deleted: #" .. tostring(id))
    run_breakpoint_callbacks("deleted", loc.file, loc.line, { number = id })
  elseif event == "stopped" then
    local frame = payload.frame or {}
    local file = frame.fullname or frame.file
    local line = tonumber(frame.line)
    if file and line then
      run_stopped_callbacks(file, { line, 0 }, {
        reason = payload.reason,
        thread_id = payload["thread-id"],
        raw = payload,
      })
    end
  elseif event == "running" then
    run_running_callbacks(payload["thread-id"])
  end
end

-- Re-queries current breakpoints and, if stopped, the current position,
-- replaying both through the normal on_breakpoint/on_stopped callbacks
-- so a client that (re)connects mid-session ends up in sync.
function M.sync()
  if not M.is_connected() then return end
  M.GdbMiSendRaw("-break-list", function(class, payload)
    if class ~= "done" then return end
    local body = (payload.BreakpointTable or {}).body or {}
    for _, entry in ipairs(body) do
      local bkpt = entry.value or entry
      if bkpt.number then
        local file = bkpt.fullname or bkpt.file
        local line = tonumber(bkpt.line)
        M._bkpt_locations[bkpt.number] = { file = file, line = line }
        run_breakpoint_callbacks("created", file, line, bkpt)
      end
    end
  end)
  M.GdbMiSendRaw("-stack-info-frame", function(class, payload)
    if class ~= "done" then return end
    local frame = payload.frame or {}
    local file = frame.fullname or frame.file
    local line = tonumber(frame.line)
    -- See https://sourceware.org/gdb/current/onlinedocs/gdb.html/GDB_002fMI-Frame-Information.html
    -- MI fram information does not contain col, only addr.
    -- "info line" gives some more information, but let's not jump into this rabbit hole.
    if file and line then
      run_stopped_callbacks(file, { line, 0 }, { reason = "sync", raw = payload })
    end
  end)
end

local function connect_to(entry)
  M.disconnect()
  local pipe = uv.new_pipe(false)
  local client = { pipe = pipe, buf = "", pending = {} }
  pipe:connect(entry.path, function(err)
    if err then
      vim.schedule(function() notify("connect failed: " .. err, vim.log.levels.ERROR) end)
      return
    end
    M.client = client
    pipe:read_start(function(rerr, data)
      if rerr then
        vim.schedule(function() notify("read error: " .. rerr, vim.log.levels.ERROR) end)
        return
      end
      if not data then
        vim.schedule(function()
          notify("connection closed by broker")
          M.disconnect()
        end)
        return
      end
      client.buf = client.buf .. data
      while true do
        local nl = client.buf:find("\n", 1, true)
        if not nl then break end
        local line = client.buf:sub(1, nl - 1):gsub("\r$", "")
        client.buf = client.buf:sub(nl + 1)
        vim.schedule(function() on_line(line) end)
      end
    end)
  end)
end

-- Sends a raw MI command (should start with '-'). If cb is given, it is
-- invoked as cb(result_class, payload_table, raw_line) once the matching
-- result record comes back. Only one in-flight request per call site is
-- tracked at a time (FIFO), matching the broker's routing model.
function M.GdbMiSendRaw(cmd, cb)
  if not M.is_connected() then
    notify("not connected, run :GdbMiConnect", vim.log.levels.WARN)
    return false
  end
  table.insert(M.client.pending, cb or function() end)
  M.client.pipe:write(cmd .. "\n")
  return true
end

function M.connect(gdb_pid)
  local sockets = discover_sockets()
  if #sockets == 0 then
    notify("no running gdb broker found in " .. runtime_dir(), vim.log.levels.INFO)
    return
  end
  if gdb_pid then
    for _, entry in ipairs(sockets) do
      if entry.gdb_pid == gdb_pid then
        connect_to(entry)
        return
      end
    end
    notify("no broker for gdb pid " .. gdb_pid, vim.log.levels.WARN)
    return
  end
  if #sockets == 1 then
    connect_to(sockets[1])
    return
  end
  local choices = {}
  for _, entry in ipairs(sockets) do
    table.insert(choices, string.format("gdb pid %d (%s)", entry.gdb_pid, entry.path))
  end
  vim.ui.select(choices, { prompt = "Select gdb session:" }, function(_, idx)
    if idx then connect_to(sockets[idx]) end
  end)
end

function M.setup()
  vim.api.nvim_create_user_command("GdbMiConnect", function(opts)
    local pid = tonumber(opts.args)
    M.connect(pid)
  end, { nargs = "?", desc = "Connect to a running external gdb mi4 broker" })

  vim.api.nvim_create_user_command("GdbMiDisconnect", function()
    M.disconnect()
  end, { desc = "Disconnect from the gdb mi4 broker" })

  vim.api.nvim_create_user_command("GdbMiSendRaw", function(opts)
    M.GdbMiSendRaw(opts.args, function(_class, _payload, raw)
      notify(raw)
    end)
  end, { nargs = "+", desc = "Send a raw MI command to the connected gdb session" })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function() M.disconnect() end,
  })
end

return M
