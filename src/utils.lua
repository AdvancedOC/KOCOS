---@generic T
---@param t T
---@return T
function table.copy(t)
    if type(t) == "table" then
        local nt = {}
        for k, v in pairs(t) do nt[k] = table.copy(v) end
        return nt
    else
        return t
    end
end

---@param inputstr string
---@param sep string
---@return string[]
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

---@param s string
---@param prefix string
function string.startswith(s, prefix)
    return s:sub(1, #prefix) == prefix
end

---@param s string
---@param suffix string
function string.endswith(s, suffix)
    return s:sub(-#suffix) == suffix
end

---@param s string
---@param l integer
---@param c? string
--- We assure you this will not break npm
function string.leftpad(s, l, c)
    if #s > l then return s end
    c = c or " "
    return string.rep(c, l - #s) .. s
end

---@param s string
---@param l integer
---@param c? string
function string.rightpad(s, l, c)
    if #s > l then return s end
    c = c or "\0"
    return s .. string.rep(c, l - #s)
end

---@param x number
---@param min number
---@param max number
function math.clamp(x, min, max)
    return math.min(max, math.max(x, min))
end

---@param x number
---@param min1 number
---@param max1 number
---@param min2 number
---@param max2 number
function math.map(x, min1, max1, min2, max2)
    return min2 + ((x - min1) / (max1 - min1)) * (max2 - min2)
end

---@class mail
---@field buffer string[]
---@field len integer
---@field limit integer
mail = {}
mail.__index = mail

function mail.create(limit)
    limit = limit or math.huge
    return setmetatable({
        buffer = {},
        len = 0,
        limit = limit,
    }, mail)
end

function mail:empty()
    return #self.buffer == 0
end

---@return string?
function mail:pop()
    local msg = table.remove(self.buffer, 1)
    if not msg then return end
    self.len = self.len - #msg
    return msg
end

---@param msg string
function mail:push(msg)
    table.insert(self.buffer, msg)
    self.len = self.len + #msg
    while self.len > self.limit do
        self:pop()
    end
end

-- Take in a binary and turn it into a GUID
-- Bin can be above 16 bytes.
-- If bin is less than 16 bytes, it is padded with 0s
---@param bin string
function BinToUUID_direct(bin)
    local digits4 = "0123456789abcdef"

    local base16d = ""
    for i=1,16 do
        local byte = string.byte(bin, i, i)
        if not byte then byte = 0 end
        local upper = math.floor(byte / 16) + 1
        local lower = byte % 16 + 1
        base16d = base16d .. digits4:sub(upper, upper) .. digits4:sub(lower, lower)
    end

    local guid = base16d:sub(1, 8) .. "-"
        .. base16d:sub(9, 12) .. "-"
        .. base16d:sub(13, 16) .. "-"
        .. base16d:sub(17, 20) .. "-"
        .. base16d:sub(21)

    return guid
end
