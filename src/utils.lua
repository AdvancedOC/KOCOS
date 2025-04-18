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

function math.clamp(x, min, max)
    return math.min(max, math.max(x, min))
end

function math.map(x, min1, max1, min2, max2)
    return min2 + ((x - min1) / (max1 - min1)) * (max2 - min2)
end
