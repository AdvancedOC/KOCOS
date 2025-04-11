local kelp = {}

---@alias Build.KelpType "O"|"E"|"L"

---@class Build.KelpObject
---@field type Build.KelpType
---@field modules {[string]: string}
---@field sourceMaps {[string]: string}
---@field dependencies string[]

---@param t Build.KelpType
---@return Build.KelpObject
function kelp.empty(t)
    ---@type Build.KelpObject
    return {
        type = t,
        modules = {},
        dependencies = {},
        sourceMaps = {},
    }
end

function kelp.setModule(obj, module, data)
    obj.modules[module] = data
end

function kelp.addDependency(obj, dependency)
    for i=1,#obj.dependencies do
        if obj.dependencies[i] == dependency then return end
    end
    table.insert(obj.dependencies, dependency)
end

function kelp.mapSource(obj, module, source)
    obj.sourceMaps[module] = source
end

---@param n integer
local function toHex(n)
    local alpha = "0123456789ABCDEF"
    local s = ""
    while true do
        if n == 0 then break end
        local d = n % #alpha
        n = math.floor(n / #alpha)
        s = s .. alpha:sub(d+1, d+1)
    end
    if #s == 0 then s = "0" end
    return s:reverse()
end

---@param s string
---@param c string
---@return string[]
local function splitChar(s, c)
    local lines = {}
    for line in string.gmatch(s, "[^%" .. c .. "]+") do
        table.insert(lines, line)
    end
    return lines
end

---@param data string
---@return Build.KelpObject
function kelp.parse(data)
    assert(data:sub(1, 7) == "KELPv1\n", "bad header")
    local obj = kelp.empty(data:sub(8, 8))

    local _off = 9
    ---@param n integer
    local function read(n)
        local c = data:sub(_off, _off+n-1)
        _off = _off + n
        return c
    end

    local function readLine()
        local l = ""
        while true do
            local c = read(1)
            if c == "\n" or c == "" then break end
            l = l .. c
        end
        return l
    end

    ---@type {[string]: string}
    local moduleMap = {}

    while _off <= #data do
        local name = readLine()
        local dataSize = tonumber(readLine(), 16)
        local moduleData = read(dataSize)
        moduleMap[name] = moduleData
    end

    local deps = moduleMap["@deps"]
    if deps then
        local libs = splitChar(deps, "\n")
        for _, lib in ipairs(libs) do
            kelp.addDependency(obj, lib)
        end
    end

    local sourcemap = moduleMap["@sourcemap"]
    if sourcemap then
        local sources = splitChar(sourcemap, "\n")
        for _, source in ipairs(sources) do
            local parts = splitChar(source, "=")
            kelp.mapSource(obj, parts[1], parts[2])
        end
    end

    moduleMap["@deps"] = nil
    moduleMap["@sourcemap"] = nil

    for module, moduleData in pairs(moduleMap) do
        obj.modules[module] = moduleData
    end

    return obj
end

---@param object Build.KelpObject
---@return string
function kelp.encode(object)
    local s = "KELPv1\n"
    s = s .. object.type

    ---@type {[string]: string}
    local moduleMap = {}

    for module, data in pairs(object.modules) do
        moduleMap[module] = data
    end

    if #object.dependencies > 0 then
        moduleMap["@deps"] = table.concat(object.dependencies, "\n")
    end

    local sourceMap = {}
    for module, source in pairs(object.sourceMaps) do
        table.insert(sourceMap, module .. "=" .. source)
    end

    if #sourceMap > 0 then
        moduleMap["@sourcemap"] = table.concat(sourceMap, "\n")
    end

    for module, data in pairs(moduleMap) do
        s = s .. module .. "\n" .. toHex(#data) .. "\n" .. data
    end

    return s
end

return kelp
