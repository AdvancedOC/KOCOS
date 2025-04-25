---@diagnostic disable: duplicate-set-field
local function loadModule(module)
    local _, code = syscall("psymbol", module)
    if not code then return nil, "missing module" end
    local _, file = syscall("psource", module)
    file = file or module

    return load(code, "=" .. file)
end

package = {}
---@type {[string]: any}
package.loaded = {
    package = package,
}
---@module "lib.liblua.syscalls"
local sys = assert(loadModule("syscalls"))()
package.loaded.sys = sys -- can't be shared

---@type {[string]: {data: string, file: string}}
package.modules = {}
package.preload = {}
package.config = [[/
;
?
!
-]]

package.path = "/lib/?.lua;/lib/lib?.lua;/usr/lib/?.lua;/usr/lib/lib?.lua;?.lua;lib?.lua"
package.cpath = "/lib/?.so;/lib/lib?.so;/usr/lib/?.so;/usr/lib/lib?.so;?.so;lib?.so"

---@param name string
---@param path string
---@param sep? string
---@param rep? string
function package.searchpath(name, path, sep, rep)
    sep = sep or '.'
    rep = rep or '/'

    local paths = string.split(path, ';')
    name = name:gsub(sep:gsub(".", function(x) return "%" .. x end), rep)
    for _, path in ipairs(paths) do
        local toCheck = path:gsub("?", name)
        local f = sys.open(toCheck, "r")
        if f then
            sys.close(f)
            return toCheck
        end
    end
    return nil, "not found"
end

local allowDupes = {
    base = true,
}

---@parma modname string
function require(modname)
    if package.loaded[modname] and not allowDupes[modname] then return package.loaded[modname] end
    for _, searcher in ipairs(package.searchers) do
        local loader, data = searcher(modname)
        if loader then
            local t = loader(modname, data)
            if t == nil then t = true end
            package.loaded[modname] = t
            return t, data
        end
    end
    error("module not found: " .. modname)
end
package.searchers = {
    function(mod)
        return package.preload[mod], ':preload:'
    end,
    function(mod)
        local module = package.modules[mod]
        if module then
            return load(module.data, "=" .. module.file), ':module:'
        end
    end,
    function(mod)
        return loadModule(mod), ':module:'
    end,
    function(mod)
        local f = package.searchpath(mod, package.path)
        if f then
            local fd = assert(sys.open(f, "r"))
            local data = ""
            while true do
                local chunk, err = sys.read(fd, math.huge)
                if err then sys.close(fd) error(err) end
                if not chunk then break end
                data = data .. chunk
            end
            sys.close(f)
            return load(data, "=" .. f), f
        end
    end,
}

local dl = require("dl")
table.insert(package.searchers, function(mod)
    -- Lua all-in-one Loader lol
    local dot = mod:find("%.")
    local lib = mod
    if dot then
        lib = mod:sub(1, dot-1)
    end

    local libf = package.searchpath(lib, package.cpath)
    if libf then
        local obj = dl.open(libf)
        dl.link(obj)
        local code, src = dl.sym(obj, mod)
        assert(code, "missing " .. mod .. " in " .. libf)
        src = src or mod
        return load(code, "=" .. src)
    end
end)

-- The entire runtime
require("base")
io=require("io")
os=require("os")
component=require("component")

local f = assert(loadModule("main"))

local ok, err = xpcall(f, debug.traceback, ...)
if not ok then
    if _K then
        _K.log("Error: %s\n", err)
    end
    sys.write(2, err .. "\n")
    sys.exit(1)
end
sys.exit(err or 0)
