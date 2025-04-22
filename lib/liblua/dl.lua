---@diagnostic disable: different-requires
local kelp = require("kelp")

local dl = {}

dl.cache = {}
dl.loaders = {}

function dl.addLoader(loader)
    table.insert(dl.loaders, loader)
end

dl.addLoader(kelp.parse)

---@return Build.KelpObject, boolean
function dl.open(path)
    local f = assert(io.open(path, "r"))
    f:setvbuf("no", math.huge)
    local code = f:read("a")
    io.close(f)

    for i=#dl.loaders,1,-1 do
        local loader = dl.loaders[i]
        local ok, obj = pcall(loader, code)
        if ok then
            local cold = not dl.cache[io.resolved(path)]
            dl.cache[io.resolved(path)] = obj
            return obj, cold
        end
    end
    error("missing loader")
end

function dl.forget(path)
    if not path then
        dl.cache = {}
        return
    end
    path = io.resolved(path)
    dl.cache[path] = nil
end

---@param obj Build.KelpObject
function dl.dependencies(obj)
    return obj.dependencies
end

---@param obj Build.KelpObject
function dl.sym(obj, module)
    return obj.modules[module], obj.sourceMaps[module]
end

---@param obj Build.KelpObject
function dl.link(obj)
    for module, _ in pairs(obj.modules) do
        local code, src = dl.sym(obj, module)
        package.modules[module] = {data = code, file = src or module}
    end
    for _, dep in ipairs(obj.dependencies) do
        -- this is just pointless
        if dep ~= "/lib/liblua.so" then
            local depObj, needsLink = dl.open(dep)
            if needsLink then dl.link(depObj) end
        end
    end
end

return dl
