local client = require("gdb_mi.broker_client")
client.setup()

require("gdb_mi.ops").setup()
require("gdb_mi.signs").setup()
require("gdb_mi.remap")

-- Most of the time this is nice, and running with no breakpoints is annoying.
-- Using Tbreak deletes breakpoint(s) when program is started, also if there
-- are duplicates.
client.on_connect(function() vim.cmd.GdbMiTbreak("main") end)

-- client.connect(nil) is tempting, but note that subsequent sync and goto_cursor
-- would make nvim jump to the debugged file even if nvim is opened as editor for
-- updating a commit message or anything else not related to the gdb session,
-- which is very annoying. A possible compromise is to disable cursor following
-- just for this initial connect. But re-enabling would require an on_connect
-- callback to be correctly timed. Just connect manually man.
