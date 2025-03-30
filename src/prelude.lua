local config = ...

KOCOS = {}
KOCOS_CONFIG = config

---@generic T
---@param val any
---@param def T
---@return T
function KOCOS.default(val, def)
    if type(val) == "nil" then return def else return val end
end

---@type string
KOCOS.defaultRoot = KOCOS.default(KOCOS_CONFIG.rootfs, computer.getBootAddress())
---@type string?
KOCOS.rootPart = KOCOS.default(KOCOS_CONFIG.rootfsPartition, nil)
KOCOS.allowGreenThreads = KOCOS.default(KOCOS_CONFIG.allowGreenThreads, true)
-- insecure will overwrite the ring to 0 for all processes
KOCOS.insecure = KOCOS.default(KOCOS_CONFIG.insecure, false)
---@type string?
KOCOS.init = KOCOS.default(KOCOS_CONFIG.init, "/sbin/init.lua")
KOCOS.maxEventBacklog = KOCOS.default(KOCOS_CONFIG.maxEventBacklog, 256)
KOCOS.rebootOnCrash = KOCOS.default(KOCOS_CONFIG.rebootOnCrash, true)
KOCOS.logThreadEvents = KOCOS.default(KOCOS_CONFIG.logThreadEvents, false)
KOCOS.selfTest = KOCOS.default(KOCOS_CONFIG.selfTest, computer.totalMemory() >= 2^19)

function KOCOS.logAll(...)
    local t = {...}
    for i=1,#t do t[i] = tostring(t[i]) end
    return KOCOS.log("%s", table.concat(t, " "))
end

local function oceLog(s)
    if component.ocelot then
        component.ocelot.log(s)
    end
end

function KOCOS.log(fmt, ...)
    local time = computer.uptime()
    local s = string.format(fmt, ...)
    KOCOS.event.push("klog", s, time)
    oceLog(s)
end

function KOCOS.logPanic(fmt, ...)
    local time = computer.uptime()
    local s = string.format(fmt, ...)
    KOCOS.event.push("kpanic", s, time)
    oceLog("PANIC: " .. s)
end

local deferred = {}

function KOCOS.defer(func, prio)
    table.insert(deferred, {func = func, prio = prio})
    table.sort(deferred, function(a, b) return a.prio > b.prio end)
end

function KOCOS.hasDeferred()
    return #deferred > 0
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

function KOCOS.pcall(f, ...)
    local ok, err = pcall(f, ...)
    if not ok then
        pcall(computer.beep)
        pcall(KOCOS.event.push, "kpanic", err, computer.uptime())
        pcall(oceLog, err)
    end
    return ok
end

function KOCOS.bsod()
    local panics = {}
    while KOCOS.event.queued("kpanic") do
        local _, msg, time = KOCOS.event.pop("kpanic")
        table.insert(panics, string.format("%.2f %s", time, msg))
    end
    local gpu = component.gpu
    for _, screen in component.list("screen") do
        gpu.bind(screen)
        gpu.setForeground(0xFFFFFF)
        gpu.setBackground(0x0000FF)
        gpu.setResolution(gpu.maxResolution())
        local w, h = gpu.getResolution()

        gpu.fill(1, 1, w, h, " ")
        local start = math.max(1, #panics - h + 1)

        for i=start,#panics do
            gpu.set(1, i - start + 1, panics[i])
        end
    end
    local start = computer.uptime()
    while computer.uptime() - start < 5 do
        coroutine.yield(start + 5 - computer.uptime())
    end
end

function KOCOS.loop()
    local lastPanicked = false
    while true do
        local panicked = false
        panicked = panicked or not KOCOS.pcall(KOCOS.event.process, 0.05)
        panicked = panicked or not KOCOS.pcall(KOCOS.process.run)
        panicked = panicked or not KOCOS.pcall(KOCOS.runDeferred, 0.05)
        if lastPanicked and panicked then
            assert(pcall(KOCOS.bsod))
            if KOCOS.rebootOnCrash then
                computer.shutdown(true)
            else
                computer.shutdown()
            end
        end
        lastPanicked = panicked
    end
end

-- For autocomplete
if 1<0 then
    _K = KOCOS
    _OS = _G

    ---@param sys string
    ---@return ...
    function syscall(sys, ...) end
end

if KOCOS.init then
    KOCOS.defer(function()
        KOCOS.log("Running " .. KOCOS.init)
        assert(KOCOS.process.spawn(KOCOS.init))
    end, 0)
end
