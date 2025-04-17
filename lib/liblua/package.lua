local function loadModule(module)
    local _, code = syscall("psymbol", module)
    if not code then return nil, "missing module" end
    local _, file = syscall("psource", module)
    file = file or module

    return load(code, "=" .. file)
end

package = {}
package.loaded = {
    package = package,
}
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

function require(modname)

end
package.searchers = {}
