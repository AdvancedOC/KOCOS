KOCOS = {}

---@generic T
---@param val any
---@param def T
---@return T
function KOCOS.default(val, def)
    if type(val) == "nil" then return def else return val end
end

---@type string
KOCOS.defaultRoot = KOCOS.default(KOCOS_CONFIG.rootfs, computer.getBootAddress())
KOCOS.allowGreenThreads = KOCOS.default(KOCOS_CONFIG.allowGreenThreads, true)
-- insecure will overwrite the ring to 0 for all processes
KOCOS.insecure = KOCOS.default(KOCOS_CONFIG.insecure, false)
KOCOS.init = KOCOS.default(KOCOS_CONFIG.init, "/sbin/init")
KOCOS.maxEventBacklog = KOCOS.default(KOCOS_CONFIG.maxEventBacklog, 256)

function KOCOS.logAll(...)
    return KOCOS.log("%s", table.concat({...}, " "))
end

function KOCOS.log(fmt, ...)
    local time = computer.uptime()
    local s = string.format(fmt, ...)
    KOCOS.event.push("klog", s, time)
    if component.ocelot then
        component.ocelot.log(s)
    end
end

local deferred = {}

function KOCOS.defer(func, prio)
    table.insert(deferred, {func = func, prio = prio})
    table.sort(deferred, function(a, b) return a.prio > b.prio end)
end

function KOCOS.runDeferred(timeout)
    local start = computer.uptime()

    while computer.uptime() < start + timeout do
        local f = table.remove(deferred, 1)
        if not f then break end
        f.func()
    end
    return #deferred > 0
end
