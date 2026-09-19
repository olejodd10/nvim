local M = {}

local function is_breakpoint(bkpt)
    return bkpt.type and bkpt.type == "breakpoint"
end

local function is_watchpoint(bkpt)
    return bkpt.type and bkpt.type == "hw watchpoint"
end

local function format_breakpoint(bkpt)
    return string.format(
        "Breakpoint %s at %s:%s (hit %s times)%s%s",
        bkpt.number,
        bkpt.file,
        bkpt.line,
        bkpt.times,
        bkpt.cond and " (cond " .. bkpt.cond .. ")" or "",
        bkpt.disp == "del" and " (temp)" or ""
    )
end

local function format_watchpoint(wpt)
    return string.format(
        "Watchpoint %s at %s",
        wpt.number,
        wpt.exp
    )
end

local function format_watchpoint_from_bkpt_list(bkpt)
    return string.format(
        "Watchpoint %s at %s (hit %s times)%s%s",
        bkpt.number,
        bkpt.what,
        bkpt.times,
        bkpt.cond and " (cond " .. bkpt.cond .. ")" or "",
        bkpt.disp == "del" and " (temp)" or ""
    )
end

local function format_breakpoint_list(bkpt_list)
    local result = "\n"
    for _, v in ipairs(bkpt_list) do
        if v.key == "bkpt" and v.value then
            local bkpt = v.value
            if is_breakpoint(bkpt) then
                result = result .. format_breakpoint(bkpt) .. "\n"
            elseif is_watchpoint(bkpt) then
                result = result .. format_watchpoint_from_bkpt_list(bkpt) .. "\n"
            end
        end
    end
    return result
end

function M.format_response(payload)
    -- return vim.inspect(payload)
    if payload.bkpt then
        return format_breakpoint(payload.bkpt)
    elseif payload.wpt then
        return format_watchpoint(payload.wpt)
    elseif payload.BreakpointTable and payload.BreakpointTable.body then
        return format_breakpoint_list(payload.BreakpointTable.body)
    else
        return vim.inspect(payload)
    end
end

return M
