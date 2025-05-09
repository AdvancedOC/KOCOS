---@diagnostic disable: duplicate-doc-alias, duplicate-doc-field
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

KOCOS.kelp = kelp

---@alias KOCOS.ObjectLoader fun(code: string): Build.KelpObject

---@type KOCOS.ObjectLoader[]
KOCOS.objectLoaders = {}

---@param loader KOCOS.ObjectLoader
function KOCOS.addObjectLoader(loader)
    table.insert(KOCOS.objectLoaders, loader)
end


-- TODO: clear it from time to time
local cache = {}

---@return Build.KelpObject?
function KOCOS.loadObject(code)
    if cache[code] then return cache[code] end
    for _, loader in ipairs(KOCOS.objectLoaders) do
        local ok, obj = pcall(loader, code)
        if ok then
            cache[code] = obj
            return obj
        end
    end
end

KOCOS.addObjectLoader(kelp.parse)

---@param proc KOCOS.Process
---@param obj Build.KelpObject
function KOCOS.linkInProcess(proc, obj)
    local loaded = {}
    ---@param o Build.KelpObject
    local function addModulesToProcess(o)
        for mod, data in pairs(o.modules) do
            assert((proc.modules[mod] or data) == data, "conflicting module " .. mod)
            proc.modules[mod] = data
        end
        for mod, source in pairs(o.sourceMaps) do
            -- conflicts dont matter much
            proc.sources[mod] = source
        end
        for _, dep in ipairs(o.dependencies) do
            if not KOCOS.fs.exists(dep) then error("Missing " .. dep) end
            if not loaded[dep] then
                loaded[dep] = true
                local code = KOCOS.readFileCached(dep)
                local depObj = assert(KOCOS.loadObject(code), "bad dependency: " .. dep)
                addModulesToProcess(depObj)
            end
        end
    end
    addModulesToProcess(obj)
end

KOCOS.process.addLoader({
    check = function(proc, path)
        if not KOCOS.fs.exists(path) then return false, nil end
        local code = KOCOS.readFile(path)
        local obj = KOCOS.loadObject(code)
        return obj ~= nil, obj
    end,
    load = function(proc, obj)
        ---@cast obj Build.KelpObject
        KOCOS.linkInProcess(proc, obj)
        local start = assert(proc.modules["_start"], "missing _start")
        local startFile = proc.sources["_start"] or "_start"
        local f = assert(load(start, "=" .. startFile, nil, proc.namespace))
        proc:attach(f, "main")
    end
})

KOCOS.log("Object loader loaded")
