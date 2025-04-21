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
package.loaded.sys = sys
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
    return "fail", "not found"
end

---@parma modname string
function require(modname)
    if package.loaded[modname] then return package.loaded[modname] end
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
        local f = package.searchpath(mod, package.path)
        if f then
            local fd = sys.open(f, "r")
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
    -- TODO: native libraries
}

-- TODO: get status and exit
local ok, err = xpcall(require, debug.traceback, "main")
if not ok then
    sys.write(2, err .. "\n")
    sys.exit(err)
end
sys.exit(err)
