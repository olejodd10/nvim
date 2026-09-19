-- gdb_mi_ops: thin, uniform wrappers around common gdb execution/breakpoint
-- MI commands, built on top of gdb_mi_broker_client's raw MI channel
-- (GdbMiSendRaw). Each :GdbMi<Name> command does nothing but prefix
-- whatever you typed with the corresponding MI command and send it
-- verbatim -- no argument reformatting, no extra commands issued, no
-- friendly-name-to-MI-command translation. So ":GdbMiNext 3" sends
-- "-exec-next 3", ":GdbMiTbreak main.c:10" sends "-break-insert -t
-- main.c:10", etc. -- if you know the gdb command you want, you already
-- know what to type. See COMMANDS below for the full list.
--
-- On ^done/^running we vim.inspect() the parsed payload table; on ^error
-- we show the error message.

local M = {}

local client = require("gdb_mi.broker_client")
local format = require("gdb_mi.format")

local function notify(msg, level)
  vim.notify("[gdb_mi_ops] " .. msg, level or vim.log.levels.INFO)
end

-- name -> MI command prefix. The command's args (if any) are appended
-- verbatim, separated by a single space.
local COMMANDS = {
  Next = "-exec-next",
  Step = "-exec-step",
  Run = "-exec-run",
  Continue = "-exec-continue",
  Until = "-exec-until",
  Finish = "-exec-finish",
  Interrupt = "-exec-interrupt",
  Break = "-break-insert",
  Tbreak = "-break-insert -t",
  Cond = "-break-condition",
  Watch = "-break-watch",
  InfoBreakpoints = "-break-list", -- weird naming in MI
  Delete = "-break-delete",
}

local function send(mi_prefix, args)
  local cmd = mi_prefix
  if args and args ~= "" then cmd = cmd .. " " .. args end
  client.GdbMiSendRaw(cmd, function(class, payload, raw)
    if class == "error" then
      notify(payload.msg or raw, vim.log.levels.ERROR)
    else
      notify(format.format_response(payload))
    end
  end)
end

function M.setup()
  for name, mi_prefix in pairs(COMMANDS) do
    vim.api.nvim_create_user_command("GdbMi" .. name, function(opts)
      send(mi_prefix, opts.args)
    end, { nargs = "*" })
  end
end

return M
