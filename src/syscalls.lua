---@type {[string]: fun(proc: KOCOS.Process, ...):...}
local syscalls = {}

-- File syscalls

---@param path string
---@param mode "w"|"r"
function syscalls.open(proc, path, mode)
    assert(type(path) == "string", "invalid path")
    assert(mode == "w" or mode == "r", "invalid mode")

    local f = assert(KOCOS.fs.open(path, mode))

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

---@param fd integer
---@param action string
function syscalls.ioctl(proc, fd, action, ...)
    local res = proc.resources[fd]
    assert(res, "bad file descriptor")

    if res.kind == "file" then
        ---@cast res KOCOS.FileResource
        return KOCOS.fs.ioctl(res.file, action, ...)
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

-- End of file syscalls

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
    if pid == proc.pid or proc:isDescendant(pid) then
        other:kill()
    else
        error("permission denied")
    end
end

-- End of process syscalls

KOCOS.syscalls = syscalls
