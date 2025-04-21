local lon = {}

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
            return string.format("%q", val) -- best worst escaper
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
            local fields = {}
            local done = {}
            for i=1,#val do
                done[i] = true
                table.insert(fields, rawEncode(val))
            end
            for k, field in pairs(val) do
                if not done[k] then
                    -- TODO: optimize for fields
                    table.insert(fields, string.format("[%s] = %s", rawEncode(k), rawEncode(field)))
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
