function table.copy(t)
    if type(t) == "table" then
        local nt = {}
        for k, v in pairs(t) do nt[k] = table.copy(v) end
        return nt
    else
        return t
    end
end

function string.split(inputstr, sep)
  if sep == nil then
    sep = "%s"
  end
  local t = {}
  for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
    table.insert(t, str)
  end
  return t
end

local memunits = {"B", "KiB", "MiB", "GiB", "TiB"}
---@param amount number
---@param spacing? string
function string.memformat(amount, spacing)
    spacing = spacing or ""
    local unit = 1
    local factor = 1024
    while unit < #memunits and amount >= factor do
        unit = unit + 1
        amount = amount / factor
    end

    return string.format("%.2f%s%s", amount, spacing, memunits[unit])
end

function string.startswith(s, prefix)
    return s:sub(1, #prefix) == prefix
end

function string.endswith(s, suffix)
    return s:sub(-#suffix) == suffix
end

local bit32Code = [[
bit32 = {}

function bit32.arshift(x, disp)
    return x >> disp
end

function bit32.band(...)
    local t = -1
    local n = select("#", ...)
    for i=1,n do
        local m = select(i, ...)
        t = t & m
    end
    return t
end

function bit32.bnot(x)
    return ~x
end

function bit32.bor(...)
    local t = 0
    local n = select("#", ...)
    for i=1,n do
        local m = select(i, ...)
        t = t | m
    end
    return t
end

function bit32.btest(...)
    return bit32.band(...) ~= 0
end
]]

if not bit32 then
    load(bit32Code, "=bit32")()
end
