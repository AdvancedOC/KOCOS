---@diagnostic disable: lowercase-global
component = {}
local sys = require("syscalls")

function component.list(type, exact)
    local tbl = {}
    for _, addr in ipairs(sys.clist()) do
        if type then
            local t = component.type(addr)
            if exact then
                if t == type then
                    tbl[addr] = t
                end
            else
                if string.match(t, type) then
                    tbl[addr] = t
                end
            end
        else
            tbl[addr] = component.type(addr)
        end
    end
    local key = nil
    return setmetatable(tbl, {
        __call = function()
            key = next(tbl, key)
            if key then
                return key, tbl[key]
            end
        end,
    })
end

---@return table
function component.proxy(addr)
    return assert(sys.cproxy(addr))
end

---@return string
function component.type(addr)
    return (sys.ctype(addr))
end

function component.invoke(addr, method, ...)
    local t = {sys.cinvoke(addr, method, ...)}
    if t[1] then error(t[1]) end
    return table.unpack(t, 2)
end

setmetatable(component, {
    __index = function(t, key)
        local x = sys.cprimary(key)
        if x then return component.proxy(x) end
    end,
})

return component
