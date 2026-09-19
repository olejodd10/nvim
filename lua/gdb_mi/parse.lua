local M = {}

-- Minimal MI value parser: handles quoted strings, tuples {k=v,...} and
-- lists [v,v,...] (which may themselves contain bare values or k=v pairs).
function M.parse_mi_value(s, i)
  local c = s:sub(i, i)
  if c == '"' then
    local out = {}
    i = i + 1
    while true do
      local ch = s:sub(i, i)
      if ch == "" then break end
      if ch == "\\" then
        local nxt = s:sub(i + 1, i + 1)
        local map = { n = "\n", t = "\t", ['"'] = '"', ["\\"] = "\\" }
        table.insert(out, map[nxt] or nxt)
        i = i + 2
      elseif ch == '"' then
        i = i + 1
        break
      else
        table.insert(out, ch)
        i = i + 1
      end
    end
    return table.concat(out), i
  elseif c == "{" then
    local tbl = {}
    i = i + 1
    while s:sub(i, i) ~= "}" and i <= #s do
      local key, val
      local eq = s:find("=", i, true)
      local brace = s:find("[{\"]", i)
      if eq and (not brace or eq < brace) then
        key = s:sub(i, eq - 1)
        i = eq + 1
        val, i = M.parse_mi_value(s, i)
      else
        val, i = M.parse_mi_value(s, i)
      end
      if key then tbl[key] = val else table.insert(tbl, val) end
      if s:sub(i, i) == "," then i = i + 1 end
    end
    return tbl, i + 1
  elseif c == "[" then
    local arr = {}
    i = i + 1
    while s:sub(i, i) ~= "]" and i <= #s do
      local key, val
      local eq = s:find("=", i, true)
      local brace = s:find("[{\"%[]", i)
      if eq and (not brace or eq < brace) then
        key = s:sub(i, eq - 1)
        i = eq + 1
      end
      val, i = M.parse_mi_value(s, i)
      if key then
        table.insert(arr, { key = key, value = val })
      else
        table.insert(arr, val)
      end
      if s:sub(i, i) == "," then i = i + 1 end
    end
    return arr, i + 1
  else
    -- bare token (e.g. inside a list without braces); read until , ] }
    local j = i
    while j <= #s and not s:sub(j, j):match("[,%]}]") do
      j = j + 1
    end
    return s:sub(i, j - 1), j
  end
end

-- Parses the "key=value,key=value,..." payload following a record class
-- character (^, =, *, +) and the record name, e.g. the part after
-- "done," or "breakpoint-created,".
function M.parse_mi_results(s)
  local tbl = {}
  local i = 1
  while i <= #s do
    local eq = s:find("=", i, true)
    if not eq then break end
    local key = s:sub(i, eq - 1)
    i = eq + 1
    local val
    val, i = M.parse_mi_value(s, i)
    tbl[key] = val
    if s:sub(i, i) == "," then i = i + 1 end
  end
  return tbl
end

return M
