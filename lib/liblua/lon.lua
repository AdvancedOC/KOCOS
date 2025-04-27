local lon = {}

---@param s string
function lon.isValidIndentifier(s)
    if type(s) ~= "string" then return false end
    ---@param c string
    ---@param set string
    local function is(c, set)
        return set:find(c) ~= nil
    end

    if #s == 0 then return false end
    if not is(s:sub(1, 1), "_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ") then return false end
    for i=2,#s do
        if not is(s:sub(i, i), "_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789") then return false end
    end
    return true
end

---@param c string
local function isControl(c)
    local char = c:byte()
  return char < 0x20 or (char >= 0x7F and char <= 0x9F)
end

---@param n integer
local function hexChar(n)
    n=math.floor(n)
    local hexBase = "0123456789ABCDEF"
    return hexBase:sub(n+1,n+1)
end

---@param value table
function lon.hasCustomStringEncoder(value)
    local mt = getmetatable(value)
    if type(mt) ~= "table" then return end
    return mt.__tostring ~= nil
end

---@param c string
---@return string
function lon.escapedByte(c)
    local directEscapes = {
        ["\n"] = "\\n",
        ["\r"] = "\\r",
        ["\t"] = "\\t",
        -- ' not needed because strings are always wrapped in ""
        ["\""] = "\\\"",
        ["\a"] = "\\a",
        ["\b"] = "\\b",
        ["\f"] = "\\f",
        ["\v"] = "\\v",
        ["\\"] = "\\\\",
    }
    if directEscapes[c] then return directEscapes[c] end
    if isControl(c) then
        local n = c:byte()
        return "\\x" .. hexChar(n / 16) .. hexChar(n % 16)
    end
    return c
end

function lon.encode(v, pretty)
    local visited = {}
    local function rawEncode(val)
        if type(val) == "nil" then
            return "nil"
        elseif type(val) == "number" then
            if val == math.huge then
                return "1/0"
            elseif val == -math.huge then
                return "-1/0"
            elseif val ~= val then
                return "-(0/0)"
            end
            return tostring(val)
        elseif type(val) == "boolean" then
            return val and "true" or "false" -- saves ram
        elseif type(val) == "string" then
            local s = ""
            for i=1,#val do
                s = s .. lon.escapedByte(val:sub(i, i))
            end
            return '"' .. s .. '"'
        elseif type(val) == "table" then
            -- stuff
            if visited[val] then
                if pretty then
                    return "..."
                else
                    error("reference cycle")
                end
            end
            visited[val] = true
            if pretty and lon.hasCustomStringEncoder(val) then
                return tostring(val)
            end
            local fields = {}
            local done = {}
            for i=1,#val do
                done[i] = true
                table.insert(fields, rawEncode(val[i]))
            end
            for k, field in pairs(val) do
                if not done[k] then
                    if lon.isValidIndentifier(k) then
                        table.insert(fields, string.format("%s = %s", k, rawEncode(field)))
                    else
                        table.insert(fields, string.format("[%s] = %s", rawEncode(k), rawEncode(field)))
                    end
                end
            end
            return "{" .. table.concat(fields, pretty and ", " or ",") .. "}"
        else
            if pretty then return tostring(val) end
            error("bad type: " .. type(val))
        end
    end
    return rawEncode(v)
end

function lon.decode(s)
    return load("return " .. s, "=lon", nil, {})()
end

return lon
