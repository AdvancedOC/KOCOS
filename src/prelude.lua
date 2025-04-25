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
KOCOS.init = KOCOS.default(KOCOS_CONFIG.init, "/bin/init")
KOCOS.maxEventBacklog = KOCOS.default(KOCOS_CONFIG.maxEventBacklog, 256)
KOCOS.rebootOnCrash = KOCOS.default(KOCOS_CONFIG.rebootOnCrash, true)
KOCOS.logThreadEvents = KOCOS.default(KOCOS_CONFIG.logThreadEvents, false)
KOCOS.selfTest = KOCOS.default(KOCOS_CONFIG.selfTest, computer.totalMemory() >= 2^19)
KOCOS.syscallTraceback = KOCOS.default(KOCOS_CONFIG.syscallTraceback, false)
KOCOS.hostname = KOCOS.default(KOCOS_CONFIG.hostname, "computer")
KOCOS.loggingTTY = KOCOS.default(KOCOS_CONFIG.loggingTTY, true)

KOCOS.eventOnLog = KOCOS.default(KOCOS_CONFIG.eventOnLog, false)
KOCOS.eventOnPanic = KOCOS.default(KOCOS_CONFIG.eventOnPanic, false)

-- Not working lmao
KOCOS.sharedStorage = KOCOS.default(KOCOS_CONFIG.sharedStorage, false)
KOCOS.trulyIndependentSyscalls = KOCOS.default(KOCOS_CONFIG.trulyIndependentSyscalls, not KOCOS.sharedStorage)

KOCOS.version = "KOCOS incomplete"

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

do
    local ocelot = component.list("ocelot")()
    if ocelot then
        component.invoke(ocelot, "clearLog")
    end
end

local tty

function KOCOS.log(fmt, ...)
    local time = computer.uptime()
    local s = string.format(fmt, ...)
    if KOCOS.eventOnLog then
        KOCOS.event.push("klog", s, time)
    end
    oceLog(s)
    if tty then
        tty:print("[LOG   %3.2f] %s\n", time, s)
    end
end

function KOCOS.logPanic(fmt, ...)
    local time = computer.uptime()
    local s = string.format(fmt, ...)
    if KOCOS.eventOnPanic then
        KOCOS.event.push("kpanic", s, time)
    end
    oceLog("PANIC: " .. s)
    if tty then
        tty:print("[\x1b[31mPANIC\x1b[0m %3.2f] %s\n", time, s)
    end
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

local looped = {}

function KOCOS.runOnLoop(func)
    table.insert(looped, func)
end

function KOCOS.runLoopedFuncs()
    for i=1,#looped do
        looped[i]()
    end
end

function KOCOS.pcall(f, ...)
    local ok, err = xpcall(f, debug.traceback, ...)
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
    local allPanicsText = "KERNEL CRASH\n" .. table.concat(panics, "\n") .. "\nPRESS ANY KEY TO REBOOT"
    if KOCOS.rebootOnCrash then
        allPanicsText = allPanicsText .. "\nSYSTEM WILL REBOOT AUTOMATICALLY"
    end
    local gpu = component.gpu
    for _, screen in component.list("screen") do
        gpu.bind(screen)
        gpu.setForeground(0xFFFFFF)
        if gpu.getDepth() > 1 then
            gpu.setBackground(0x0000FF)
        else
            gpu.setBackground(0x000000)
        end
        gpu.setResolution(gpu.maxResolution())
        local w, h = gpu.getResolution()

        gpu.fill(1, 1, w, h, " ")
        local i = 1
        for line in allPanicsText:gmatch("[^\n]+") do
            line = line:gsub("%\t", "    ")
            gpu.set(1, i, line)
            i = i + 1
            if i > h then
                i = h
                gpu.copy(1, 2, w, h - 1, 0, -1)
                gpu.fill(1, h, w, 1, " ")
            end
        end
    end
    local start = computer.uptime()
    if KOCOS.rebootOnCrash then
        while computer.uptime() - start < 5 do
            local event = computer.pullSignal(start + 5 - computer.uptime())
            if event == "key_down" then break end
        end
        computer.shutdown(true)
    else
        repeat
            local event = computer.pullSignal()
        until event == "key_down"
    end
end

function KOCOS.loop()
    local lastPanicked = false
    local function processEvents()
        KOCOS.event.process(0.05)
    end
    local function runProcesses()
        KOCOS.process.run()
    end
    local function reportCrash()
        KOCOS.event.push("kcrash", computer.uptime())
    end
    while true do
        local panicked = false
        panicked = panicked or not KOCOS.pcall(processEvents)
        panicked = panicked or not KOCOS.pcall(KOCOS.runLoopedFuncs)
        panicked = panicked or not KOCOS.pcall(runProcesses)
        panicked = panicked or not KOCOS.pcall(KOCOS.runDeferred, 0.05)
        if lastPanicked and panicked then
            pcall(reportCrash)
            pcall(KOCOS.bsod) -- LETS HOPE IT DOES NOT
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
    _OSVERSION = "Unknown KOCOS"
    _KVERSION = KOCOS.version
    _SHARED = {}

    ---@param sys string
    ---@return ...
    function syscall(sys, ...) end
end

if KOCOS.loggingTTY then
    KOCOS.defer(function()
        tty = KOCOS.tty.create(component.gpu, "no keyboard")
        tty:clear()
    end, math.huge)
end

if KOCOS.init then
    KOCOS.defer(function()
        if tty then
            KOCOS.log("Clearing log TTY")
            tty:clear()
            tty = nil
        end
        KOCOS.log("Running " .. KOCOS.init)
        assert(KOCOS.process.spawn(KOCOS.init, {
            traced = true,
        }))
    end, -math.huge)
end

KOCOS._og_coro = {}
for k, v in pairs(coroutine) do
    KOCOS._og_coro[k] = v
end

local resume = coroutine.resume

local sysYieldObj = {}

function KOCOS.yield(...)
    return coroutine.yield(sysYieldObj, ...)
end

function coroutine.resume(co, ...)
    while true do
        local t = {resume(co, ...)}
        if not t[1] then
            return table.unpack(t)
        end
        if t[2] ~= sysYieldObj then
            return true, table.unpack(t, 2)
        end
        KOCOS.yield(table.unpack(t, 3))
    end
end

function KOCOS.resume(co, ...)
    local t = {resume(co, ...)}
    if not t[1] then
        return table.unpack(t)
    end
    if t[2] == sysYieldObj then
        return true, table.unpack(t, 3)
    end
    return true, table.unpack(t, 2)
end
