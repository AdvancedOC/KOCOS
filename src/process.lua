---@class KOCOS.Lock
---@field locked boolean

local lock = {}
lock.__index = lock

function lock.create()
    return setmetatable({locked = false}, lock)
end

function lock:lock()
    while self.locked do
        coroutine.yield()
    end
    self.locked = true
end

function lock:unlock()
    self.locked = false
end

KOCOS.lock = lock

---@class KOCOS.Thread
---@field process integer
---@field coro thread
---@field mode "alive"|"suspended"|"dead"
---@field name string
---@field nextTime integer
---@field id integer
local thread = {}
thread.__index = thread

function thread.create(func, name, process, id)
    local t = setmetatable({
        process = process,
        coro = coroutine.create(func),
        mode = "alive",
        name = name,
        id = id,
        nextTime = 0,
    }, thread)
    table.insert(KOCOS.process.nextThreads, t)
end

function thread:dead()
    return self.mode == "dead"
end

function thread:suspended()
    return self.mode == "suspended"
end

function thread:suspend()
    if not self:dead() then self.mode = "suspended" end
end

function thread:resume()
    if not self:dead() then self.mode = "alive" end
end

function thread:status()
    return self.mode, coroutine.status(self.coro)
end

function thread:kill(msg, trace)
    if self:dead() then return end
    msg = msg or "thread killed"
    trace = trace or debug.traceback(self.coro)
    self.mode = "dead" -- End game

    if coroutine.close then coroutine.close(self.coro) end

    local proc = KOCOS.process.procs[self.process]
    if not proc then return end -- Process died before us???

    proc:raise("thread_killed", self.id, msg, trace)

    proc.threads[self.id] = nil -- bye bye
    if next(proc.threads) then return end
    if not proc.parent then return end

    local parent = KOCOS.process.procs[proc.parent]
    if not parent then return end
    parent:raise("child_terminated", proc.pid)
end

function thread:tick()
    if thread:dead() then return end
    if thread:suspended() then return end
    if computer.uptime() < self.nextTime then return end
    local ok, val = coroutine.resume(self.coro)
    if ok then
        if type(val) == "number" then
            self.nextTime = computer.uptime() + val
        end
    elseif not ok then
        self:kill(val, debug.traceback(self.coro))
    end
    if coroutine.status(self.coro) == "dead" then
        self:kill("terminated", "")
    end
end

KOCOS.thread = thread

---@class KOCOS.Process
---@field ring number
---@field cmdline string
---@field args {[number]: string}
---@field env {[string]: string}
---@field pid integer
---@field status integer
---@field events KOCOS.EventSystem
---@field namespace _G
---@field parent? integer
---@field threads {[integer]: KOCOS.Thread}
---@field children {[integer]: KOCOS.Process}
---@field modules {[string]: string}
local process = {}
process.__index = process

---@type {[integer]: KOCOS.Process}
process.procs = {}
process.lpid = 0

---@type KOCOS.Thread[]
process.nextThreads = {}
---@type KOCOS.Thread[]
process.currentThreads = {}

local function rawSpawn(init, config)
    config = config or {}

    local ring = config.ring or 0
    local cmdline = config.cmdline or ""
    local args = config.args or {}
    local env = config.env or {}
    local pid = process.lpid + 1

    local proc = setmetatable({}, process)

    local namespace = {}

    if KOCOS.allowGreenThreads then
        namespace.coroutine = table.copy(coroutine)
    else
        namespace.coroutine = {
            yield = coroutine.yield,
        }
    end
    namespace.syscall = function(name, ...)
        local sys = KOCOS.syscall[name]
        if not sys then return "bad syscall" end
        local t = {pcall(sys, ...)}
        if t[1] then
            return nil, table.unpack(t, 2)
        else
            return t[2]
        end
    end
    if ring <= 1 then
        namespace._K = KOCOS
    end
    if ring == 0 then
        namespace._OS = _G
    end
    namespace.table = table.copy(table)
    namespace.string = table.copy(string)
    namespace.math = table.copy(math)

    proc.pid = pid
    proc.parent = config.parent
    proc.children = {}
    proc.events = KOCOS.event.create(KOCOS.maxEventBacklog)
    proc.args = table.copy(args)
    proc.env = table.copy(env)
    proc.ring = ring
    proc.cmdline = cmdline
    proc.namespace = namespace
    proc.threads = {}
    proc.modules = {}

    if type(init) == "function" then
        proc:attach(init)
    elseif type(init) == "string" then
        error("loading executables not yet handled")
    end

    process.procs[pid] = proc
    process.lpid = pid
    return proc
end

function process.spawn(init, config)
    local ok, val = pcall(rawSpawn, init, config)
    if ok then
        return val
    end
    return nil, val
end

function process:attach(func, name)
    local id = 1
    while self.threads[id] do id = id + 1 end
    name = name or tostring("thread #" .. id)

    local t = thread.create(func, name, self.pid, id)
    self.threads[id] = t
end

function process:raise(name, ...)
    self.events.push(name, ...)
end

function process:define(module, data)
    self.modules[module] = data
end

function process.byPid(pid)
    return process.procs[pid]
end

function process.kill(proc)
    -- TODO: implement
end

function process.run()
    for i=1,#process.currentThreads do
        local thread = process.currentThreads[i]
        thread:tick()
        if not thread:dead() then
            table.insert(process.nextThreads, thread)
        end
    end

    process.currentThreads = process.nextThreads
    process.nextThreads = {}
end

KOCOS.process = process
