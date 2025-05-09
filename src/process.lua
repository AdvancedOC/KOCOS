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
    return t
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
    if KOCOS.logThreadEvents then
        KOCOS.logAll(self.name, msg, trace)
    end
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
    KOCOS.process.current = thread.process
    local ok, val = KOCOS.resume(self.coro)
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

---@alias KOCOS.ResourceKind "file"|"lock"|"event"|"socket"|"vm"|"tty"

---@class KOCOS.Resource
---@field kind KOCOS.ResourceKind

---@class KOCOS.FileResource: KOCOS.Resource
---@field kind "file"
---@field file KOCOS.File

---@class KOCOS.LockResource: KOCOS.Resource
---@field kind "lock"
---@field lock KOCOS.Lock

---@class KOCOS.EventResource: KOCOS.Resource
---@field kind "event"
---@field event KOCOS.EventSystem

---@class KOCOS.SocketResource: KOCOS.Resource
---@field kind "socket"
---@field rc integer
---@field socket KOCOS.NetworkSocket

---@class KOCOS.KVMResource: KOCOS.Resource
---@field kind "vm"
---@field rc integer
---@field vm KOCOS.KVM

---@class KOCOS.TTYResource: KOCOS.Resource
---@field kind "tty"
---@field tty KOCOS.TTY

---@class KOCOS.Process
---@field ring number
---@field cmdline string
---@field args {[number]: string}
---@field env {[string]: string}
---@field pid integer
---@field uid integer
---@field status integer
---@field events KOCOS.EventSystem
---@field namespace _G
---@field parent? integer
---@field threads {[integer]: KOCOS.Thread}
---@field children {[integer]: KOCOS.Process}
---@field modules {[string]: string}
---@field sources {[string]: string}
---@field resources {[integer]: KOCOS.Resource}
---@field traced boolean
local process = {}
process.__index = process

---@type {[integer]: KOCOS.Process}
process.procs = {}
process.current = 0
process.lpid = 0

---@type KOCOS.Thread[]
process.nextThreads = {}
---@type KOCOS.Thread[]
process.currentThreads = {}

---@class KOCOS.Loader
---@field check fun(proc: KOCOS.Process, path: string): boolean, any
---@field load fun(proc: KOCOS.Process, data: any)

---@type KOCOS.Loader[]
process.loaders = {}

---@param loader KOCOS.Loader
function process.addLoader(loader)
    table.insert(process.loaders, loader)
end

---@param err string
local function trimLoc(err)
    return err:gsub("[^:]+:[^:]+:%s", "", 1)
end

local shared = KOCOS.sharedStorage and {}

local _namespaceCache
---@return _G
local function getCoreNamespace()
    -- caching here is a security oversight we have accepted
    -- because RAM is more important than security for these people
    if _namespaceCache then return _namespaceCache end
    local namespace = {}

    if KOCOS.allowGreenThreads then
        namespace.coroutine = table.copy(coroutine)
    else
        namespace.coroutine = {
            yield = coroutine.yield,
        }
    end

    namespace._VERSION = _VERSION
    namespace._OSVERSION = _OSVERSION or "Unknown KOCOS"
    namespace._KVERSION = KOCOS.version
    namespace._SHARED = shared
    namespace.assert = assert
    namespace.error = error
    namespace.getmetatable = getmetatable
    namespace.ipairs = ipairs
    namespace.next = next
    namespace.pairs = pairs
    namespace.pcall = pcall
    namespace.rawequal = rawequal
    namespace.rawget = rawget
    namespace.rawset = rawset
    namespace.rawlen = rawlen
    namespace.select = select
    namespace.setmetatable = setmetatable
    namespace.tonumber = tonumber
    namespace.tostring = tostring
    namespace.type = type
    namespace.xpcall = xpcall
    namespace.bit32 = bit32
    namespace.table = table
    namespace.string = string
    namespace.math = math
    namespace.debug = debug
    namespace.os = os
    namespace.checkArg = checkArg
    namespace.unicode = unicode
    namespace.utf8 = utf8

    _namespaceCache = namespace
    return namespace
end

local function rawSpawn(init, config)
    config = config or {}

    local ring = math.floor(config.ring or 0)
    local cmdline = config.cmdline or init
    local args = config.args or {}
    local env = config.env or {}
    local uid = config.uid or 0
    local pid = process.lpid + 1

    ---@type KOCOS.Process
    local proc = setmetatable({}, process)
    proc.traced = not not config.traced

    local namespace = table.copy(getCoreNamespace())

    local syscall = function(name, ...)
        local sys = KOCOS.syscalls[name]
        if not sys then return "bad syscall" end
        local p = proc
        if not KOCOS.trulyIndependentSyscalls then
            p = process.procs[process.current]
            KOCOS.logAll("process.current", process.current)
            assert(p, "current process is corrupted")
        end
        local t = {xpcall(sys, KOCOS.syscallTraceback and debug.traceback or trimLoc, p, ...)}
        if t[1] then
            return nil, table.unpack(t, 2)
        else
            return t[2]
        end
    end
    -- Small optimization to do it like this
    if proc.traced then
        function namespace.syscall(name, ...)
            local tracer = process.procs[proc.parent or proc.pid]
            -- Should never happen though
            if not tracer then return syscall(name, ...) end
            local a = {...}
            tracer:raise("syscall", name, a)
            local r = {syscall(name, ...)}
            tracer:raise("sysret", name, a, r)
            return table.unpack(r)
        end
    else
        namespace.syscall = syscall
    end
    if ring <= 1 then
        namespace._K = KOCOS
    end
    if ring == 0 then
        namespace._OS = _G
    end
    namespace.arg = table.copy(args)
    namespace._G = namespace
    namespace.load = function(code, name, kind, _G)
        return load(code, name, kind, _G or namespace)
    end

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
    proc.sources = {}
    proc.resources = {}
    proc.uid = uid
    proc.status = 0

    if type(init) == "function" then
        proc:attach(init)
    elseif type(init) == "string" then
        proc:loadExecutable(init)
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

---@param init string
function process:loadExecutable(init)
    local loaded = false
    for i=#process.loaders, 1, -1 do
        local loader = process.loaders[i]
        local ok, data = loader.check(self, init)
        if ok then
            loader.load(self, data)
            loaded = true
            break
        end
    end
    assert(loaded, "missing loader")
end

function process:attach(func, name)
    local id = 1
    while self.threads[id] do id = id + 1 end
    name = name or tostring("thread #" .. id)

    local t = thread.create(func, name, self.pid, id)
    self.threads[id] = t
    return t
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

function process:kill()
    for _, thread in pairs(self.threads) do
        thread:kill("process terminated", "")
    end

    for _, resource in pairs(self.resources) do
        process.closeResource(resource)
    end

    if self.parent then
        local parent = process.byPid(self.parent)
        if parent then
            parent.children[self.pid] = nil
        end
    end
    process.procs[self.pid] = nil
end

---@param resource KOCOS.Resource
---@param n? integer
function process.retainResource(resource, n)
    n = n or 1
    if resource.kind == "file" then
        ---@cast resource KOCOS.FileResource
        KOCOS.fs.retain(resource.file, n)
    elseif resource.kind == "socket" then
        ---@cast resource KOCOS.SocketResource
        resource.rc = resource.rc + n
    end
end

---@return integer
function process:newFD()
    local fd = #self.resources
    while self.resources[fd] do fd = fd + 1 end
    return fd
end

---@param resource KOCOS.Resource
---@return integer
function process:moveResource(resource)
    local fd = self:newFD()
    self.resources[fd] = resource
    return fd
end

---@param resource KOCOS.Resource
---@return integer
function process:giveResource(resource)
    -- if OOM, we're still good!!!!
    local fd = self:moveResource(resource)
    local ok, err = pcall(process.retainResource, resource)
    if not ok then
        self.resources[fd] = nil -- Nope, bye
        error(err)
    end
    return fd
end

---@param pid integer
---@return boolean
function process:isDescendant(pid)
    if self.children[pid] then return true end

    for _, child in pairs(self.children) do
        if child:isDescendant(pid) then return true end
    end

    return false
end

---@param resource KOCOS.Resource
function process.closeResource(resource)
    if resource.kind == "file" then
        ---@cast resource KOCOS.FileResource
        KOCOS.fs.close(resource.file)
    elseif resource.kind == "socket" then
        ---@cast resource KOCOS.SocketResource
        resource.rc = resource.rc - 1
        if resource.rc <= 0 then
            KOCOS.network.close(resource.socket)
        end
    elseif resource.kind == "vm" then
        ---@cast resource KOCOS.KVMResource
        resource.rc = resource.rc - 1
        if resource.rc <= 0 then
            KOCOS.kvm.close(resource.vm)
        end
    end
end

function process.run()
    if #process.currentThreads == 0 then
        process.currentThreads = process.nextThreads
        process.nextThreads = {}
    end
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

-- Raw lua file runner
process.addLoader({
    check = function (proc, path)
        local data = KOCOS.readFile(path)
        local fun = load(data, "=" .. (proc.args[0] or path), "bt", proc.namespace)
        return fun ~= nil, fun
    end,
    load = function (proc, data)
        proc:attach(function()
            return data(table.unpack(proc.args))
        end, "main")
    end,
})

-- Shebang runner
process.addLoader({
    check = function (proc, path)
        local fs = KOCOS.fs
        local f = fs.open(path, "r")
        if not f then return false end -- nah
        local data = ""
        while true do
            if #data > 1024 then
                fs.close(f)
                return false
            end
            local chunk = fs.read(f, 64)
            if not chunk then
                fs.close(f)
                return false
            end
            data = data .. chunk
            if string.find(chunk, "\n") then
                break
            end
        end
        fs.close(f)
        local term = assert(string.find(data, "\n"))
        local line = string.sub(data, 1, term)
        if line:sub(1, 2) ~= "#!" then return false end
        line = line:sub(3)
        local parts = {}
        for part in string.gmatch(line, "[^%s]+") do
            table.insert(parts, part)
        end
        table.insert(parts, fs.canonical(path))
        return true, parts
    end,
    load = function (proc, data)
        KOCOS.logAll(table.unpack(data))
        local init = table.remove(data, 1)
        if not KOCOS.fs.exists(init) then
            error("Missing interpreter: " .. init)
        end
        for i=1,#data do
            -- this works because yes.
            table.insert(proc.args, i, data[i])
        end
        proc.args[0] = init
        proc.namespace.arg = proc.args
        KOCOS.logAll(table.unpack(proc.namespace.arg))
        proc:loadExecutable(init) -- can stackoverflow but fuck off now
    end,
})

KOCOS.process = process

-- In case syscalls are deleted, technically allowed!
KOCOS.syscalls = {}
