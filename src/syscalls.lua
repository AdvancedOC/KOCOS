---@type {[string]: fun(proc: KOCOS.Process, ...):...}
local syscalls = {}

-- File and socket syscalls

---@param path string
---@param mode "w"|"r"
function syscalls.open(proc, path, mode)
    assert(type(path) == "string", "invalid path")
    assert(mode == "w" or mode == "r", "invalid mode")

    assert(KOCOS.fs.exists(path), "not found")

    local f = assert(KOCOS.fs.open(path, mode))
    KOCOS.logAll("open", f.fd)

    ---@type KOCOS.FileResource
    local res = {
        kind = "file",
        file = f,
    }

    local ok, fd = pcall(KOCOS.process.moveResource, proc, res)
    if ok then
        return fd
    end

    KOCOS.fs.close(f)
    error(fd)
end

---@param path string
---@param permissions string
function syscalls.touch(proc, path, permissions)
    assert(type(path) == "string", "bad path")
    assert(permissions >= 0 and permissions < 2^16, "bad permissions")
    assert(not KOCOS.fs.exists(path), "already exists")

    assert(KOCOS.fs.touch(path, permissions))
end

---@param path string
---@param permissions string
function syscalls.mkdir(proc, path, permissions)
    assert(type(path) == "string", "bad path")
    assert(permissions >= 0 and permissions < 2^16, "bad permissions")
    assert(not KOCOS.fs.exists(path), "already exists")

    assert(KOCOS.fs.mkdir(path, permissions))
end

---@param path string
function syscalls.remove(proc, path)
    assert(type(path) == "string", "bad path")
    assert(KOCOS.fs.remove(path))
end

---@param mode "w"|"r"
---@param contents string
---@param limit integer
function syscalls.mopen(proc, mode, contents, limit)
    assert(mode == "w" or mode == "r", "invalid mode")
    assert(type(contents) == "string", "invalid contents")
    assert(type(limit) == "number", "invalid limit")

    local f = assert(KOCOS.fs.mopen(mode, contents, limit))
    -- theoretical OOM case here. TODO: fix it

    ---@type KOCOS.FileResource
    local res = {
        kind = "file",
        file = f,
    }

    local ok, fd = pcall(KOCOS.process.moveResource, proc, res)
    if ok then
        return fd
    end

    KOCOS.fs.close(f)
    error(fd)
end

---@param protocol string
---@param subprotocol string
function syscalls.socket(proc, protocol, subprotocol, config)
    assert(type(protocol) == "string", "bad protocol")
    assert(type(subprotocol) == "string", "bad subprotocol")
    config = table.copy(config)

    local s = assert(KOCOS.network.newSocket(protocol, subprotocol, config, proc))

    ---@type KOCOS.SocketResource
    local res = {
        kind = "socket",
        socket = s,
        rc = 1,
    }

    local ok, fd = pcall(KOCOS.process.moveResource, proc, res)
    if ok then
        return fd
    end

    KOCOS.network.close(res.socket)
    error(fd)
end

---@param fd integer
---@param address any
---@param options any
function syscalls.connect(proc, fd, address, options)
    local res = assert(proc.resources[fd], "bad file descriptor")
    assert(res.kind == "socket", "bad file descriptor")
    ---@cast res KOCOS.SocketResource
    KOCOS.network.connect(res.socket, address, options)
end

---@param fd integer
function syscalls.close(proc, fd)
    local res = proc.resources[fd]
    assert(res, "bad file descriptor")

    KOCOS.process.closeResource(res)
    proc.resources[fd] = nil
end

---@param fd integer
---@param limit integer
function syscalls.read(proc, fd, limit)
    assert(type(limit) == "number", "bad limit")
    local res = proc.resources[fd]
    assert(res, "bad file descriptor")

    if res.kind == "file" then
        ---@cast res KOCOS.FileResource
        local f = res.file
        local data, err = KOCOS.fs.read(f, limit)
        if err then error(err) end
        return data
    elseif res.kind == "socket" then
        ---@cast res KOCOS.SocketResource
        local s = res.socket
        local data, err = KOCOS.network.read(s, limit)
        if err then error(err) end
        return data
    end
    error("bad resource type")
end

---@param fd integer
---@param data string 
function syscalls.write(proc, fd, data)
    assert(type(data) == "string", "bad data")
    local res = proc.resources[fd]
    assert(res, "bad file descriptor")

    if res.kind == "file" then
        ---@cast res KOCOS.FileResource
        local f = res.file
        if f.kind == "disk" then
            KOCOS.logAll("FD", f.fd, debug.traceback())
        end
        assert(KOCOS.fs.write(f, data))
        return
    end
    error("bad resource type")
end

---@param fd integer
---@param whence "set"|"cur"|"end"
---@param off integer
function syscalls.seek(proc, fd, whence, off)
    assert(whence == "set" or whence == "cur" or whence == "end", "bad whence")
    assert(type(off) == "number", "bad offset")
    local res = proc.resources[fd]
    assert(res, "bad file descriptor")

    if res.kind == "file" then
        ---@cast res KOCOS.FileResource
        local f = res.file
        return assert(KOCOS.fs.seek(f, whence, off))
    end
    error("bad resource type")
end

---@param path string
function syscalls.stat(proc, path)
    assert(type(path) == "string", "bad path")

    local info = {}
    info.type = KOCOS.fs.type(path)
    info.used = KOCOS.fs.spaceUsed(path)
    info.total = KOCOS.fs.spaceTotal(path)
    info.size = KOCOS.fs.size(path)
    info.mtime = 0
    info.uauth = 2^16-1
    local partition = KOCOS.fs.partitionOf(path)
    info.partition = partition.uuid
    info.driveType = partition.drive.type
    info.deviceName = partition.name
    info.driveName = partition.drive.getLabel() or "no label"
    return info
end

function syscalls.cstat(proc)
    local info = {}
    info.boot = computer.getBootAddress()
    info.tmp = computer.tmpAddress()
    info.uptime = computer.uptime()
    info.kernel = KOCOS.version
    info.memTotal = computer.totalMemory()
    info.memFree = computer.freeMemory()
    info.arch = computer.getArchitecture()
    info.energy = computer.energy()
    info.maxEnergy = computer.maxEnergy()
    info.isRobot = component.robot ~= nil
    info.users = {computer.users()}
    info.threadCount = #KOCOS.process.currentThreads
    return info
end

---@param fd integer
---@param action string
function syscalls.ioctl(proc, fd, action, ...)
    local res = proc.resources[fd]
    assert(res, "bad file descriptor")

    if res.kind == "file" then
        ---@cast res KOCOS.FileResource
        return KOCOS.fs.ioctl(res.file, action, ...)
    end
    if res.kind == "socket" then
        ---@cast res KOCOS.SocketResource
        return KOCOS.network.ioctl(res.socket, action, ...)
    end

    error("bad file descriptor")
end

---@param path string
function syscalls.ftype(proc, path)
    return KOCOS.fs.type(path)
end

---@param path string
function syscalls.list(proc, path)
    return assert(KOCOS.fs.list(path))
end

-- End of file and socket syscalls

-- Event syscalls

---@param res KOCOS.Resource
---@return KOCOS.EventSystem?
local function eventsOf(res)
    if res.kind == "file" then
        ---@cast res KOCOS.FileResource
        return res.file.events
    end
    if res.kind == "event" then
        ---@cast res KOCOS.EventResource
        return res.event
    end
end

function syscalls.queued(proc, fd, ...)
    local res = proc.resources[fd]
    assert(res, "bad file descriptor")

    local events = eventsOf(res)
    assert(events, "bad file descriptor")

    return events.queued(...)
end

function syscalls.pop(proc, fd, ...)
    local res = proc.resources[fd]
    assert(res, "bad file descriptor")

    local events = eventsOf(res)
    assert(events, "bad file descriptor")

    return events.pop(...)
end

function syscalls.popWhere(proc, fd, f)
    assert(type(f) == "function", "bad validator")

    local res = proc.resources[fd]
    assert(res, "bad file descriptor")

    local events = eventsOf(res)
    assert(events, "bad file descriptor")

    return events.popWhere(f)
end

function syscalls.clear(proc, fd)
    local res = proc.resources[fd]
    assert(res, "bad file descriptor")

    local events = eventsOf(res)
    assert(events, "bad file descriptor")

    events.clear()
    return true
end

---@param name string
function syscalls.push(proc, fd, name, ...)
    assert(type(name) == "string", "bad event")

    local res = proc.resources[fd]
    assert(res, "bad file descriptor")

    local events = eventsOf(res)
    assert(events, "bad file descriptor")

    return events.push(name, ...)
end

---@param name string
---@param f function
---@param id? string
function syscalls.listen(proc, name, f, id)
    assert(type(name) == "string", "bad event name")
    assert(type(f) == "function", "bad callback")
    assert(type(id) == "string" or id == nil, "bad id")
    return proc.events.listen(f, id)
end

---@param id string
function syscalls.forget(proc, id)
    assert(type(id) == "string", "bad id")
    proc.events.forget(id)
end

-- End of event syscalls

-- Thread syscalls

function syscalls.attach(proc, func, name)
    local thread = proc:attach(func, name)
    assert(thread, "failed")
    return thread.id
end

function syscalls.openlock(proc)
    local newLock = KOCOS.lock.create()

    ---@type KOCOS.LockResource
    local res = {
        kind = "lock",
        lock = newLock,
    }

    return proc:moveResource(res)
end

function syscalls.tryLock(proc, fd)
    local res = assert(proc.resources[fd], "bad file descriptor")
    if res.kind ~= "lock" then error("bad resource") end
    ---@cast res KOCOS.LockResource
    return res.lock:tryLock()
end

function syscalls.lock(proc, fd, timeout)
    assert(type(timeout) == "number", "bad timeout")
    local res = assert(proc.resources[fd], "bad file descriptor")
    if res.kind ~= "lock" then error("bad resource") end
    ---@cast res KOCOS.LockResource
    return res.lock:lock(timeout)
end

function syscalls.unlock(proc, fd)
    local res = assert(proc.resources[fd], "bad file descriptor")
    if res.kind ~= "lock" then error("bad resource") end
    ---@cast res KOCOS.LockResource
    return res.lock:unlock()
end

-- End of thread syscalls

-- Process syscalls

function syscalls.pself(proc)
    return proc.pid
end

---@param pid? integer
function syscalls.pnext(proc, pid)
    assert(type(pid) == "number" or pid == nil, "bad pid")
    return next(KOCOS.process.procs, pid)
end

---@param pid integer
function syscalls.pinfo(proc, pid)
    assert(type(pid) == "number", "bad pid")

    local requested = KOCOS.process.byPid(pid)
    assert(requested, "bad pid")

    local data = {
        args = requested.args,
        env = requested.env,
        cmdline = requested.cmdline,
        ring = requested.ring,
        parent = requested.parent,
        status = requested.status,
        children = {},
        threads = {},
    }

    for child, _ in pairs(requested.children) do
        table.insert(data.children, child)
    end

    for thread, _ in pairs(requested.threads) do
        table.insert(data.threads, thread)
    end

    local safe = table.copy(data) -- Get rid of references to kernel memory

    if proc.ring < 2 then
        -- Add references to kernel memory for trusted processes
        data.namespace = requested.namespace
    end

    return safe
end

---@param pid integer
function syscalls.pawait(_, pid)
    assert(type(pid) == "number", "bad pid")

    while true do
        local proc = KOCOS.process.byPid(pid)
        if not proc then error("process terminated") end
        if not next(proc.threads) then break end
        coroutine.yield()
    end
end

---@param pid integer
function syscalls.pwait(_, pid)
    assert(type(pid) == "number", "bad pid")

    while KOCOS.process.byPid(pid) do coroutine.yield() end
end

---@param status integer
function syscalls.pstatus(proc, status)
    assert(type(status) == "number", "bad pid")
    proc.status = status
end

---@param pid integer
function syscalls.pexit(proc, pid)
    assert(type(pid) == "number", "bad pid")

    local other = KOCOS.process.byPid(pid)
    assert(other, "bad pid")
    if pid == proc.pid or proc:isDescendant(pid) or proc.ring < 2 then
        other:kill()
    else
        error("permission denied")
    end
end

function syscalls.pspawn(proc, init, config)
    assert(type(init) == "string", "bad init path")
    assert(type(config) == "table", "bad config")
    local data = {
        ring = config.ring or proc.ring,
        cmdline = config.cmdline or init,
        args = table.copy(config.args) or {[0]=init},
        env = table.copy(config.env or proc.env),
        parent = proc.pid,
    }
    local fdMap = table.copy(config.fdMap) or {
        -- Passing through stdout, stdin, stderr.
        -- Field is the fd for the child process.
        [0] = 0,
        [1] = 1,
        [2] = 2,
    }
    assert(type(data.ring) == "number", "bad ring")
    assert(data.ring >= proc.ring, "permission denied")
    assert(type(data.cmdline) == "string", "bad cmdline")
    assert(type(data.args) == "table", "bad args")
    data.args[0] = data.args[0] or init
    for i, arg in pairs(data.args) do
        assert(type(i) == "number", "args is not array")
        assert(i >= 0 and i <= #arg, "args is not array")
        assert(type(arg) == "string", "args are not strings")
    end
    assert(type(data.env) == "table", "bad env")
    for k, v in pairs(data.env) do
        assert(type(k) == "string", "env name is not string")
        assert(type(v) == "string", "env value is not string")
    end
    assert(type(fdMap) == "table", "bad fdmap")
    for childFd, parentFd in pairs(fdMap) do
        assert(type(childFd) == "number", "corrupt fdmap")
        assert(type(parentFd) == "number", "corrupt fdmap")
        assert(proc.resources[parentFd], "bad file descriptor in fdmap")
    end
    local child = assert(KOCOS.process.spawn(init, data))
    for childFd, parentFd in pairs(fdMap) do
        local res = proc.resources[parentFd]
        -- Pcalled in case of OOM
        local ok, err = pcall(rawset, child.resources, childFd, res)
        if not ok then
            child:kill() -- badly initialized process. Kill it.
            error(err)
        end
        KOCOS.process.retainResource(res)
    end
    proc.children[child.pid] = child
    return child.pid
end

---@param pid integer
---@param event string
function syscalls.psignal(proc, pid, event, ...)
    -- we allow shared memory like this btw
    -- also shared functions
    -- can be used to optimize a lot
    assert(type(pid) == "integer", "bad pid")
    assert(type(event) == "string", "bad event name")
    local target = KOCOS.process.procs[pid]
    assert(target, "bad pid")

    if target.ring < proc.ring then
        error("permission denied")
    end

    target.events.push(event, ...)
end

-- End of process syscalls

KOCOS.syscalls = syscalls
