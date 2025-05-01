---@diagnostic disable: inject-field
local sys = {}

function sys.open(path, mode)
    local err, fd = syscall("open", path, mode)
    return fd, err
end

function sys.touch(path, permissions)
    local err = syscall("touch", path, permissions)
    return err == nil, err
end

function sys.chown(path, permissions)
    local err = syscall("chown", path, permissions)
    return err == nil, err
end

function sys.mkdir(path, permissions)
    local err = syscall("mkdir", path, permissions)
    return err == nil, err
end

function sys.remove(path)
    local err = syscall("remove", path)
    return err == nil, err
end

function sys.stat(path)
    local err, info = syscall("stat", path)
    return info, err
end

function sys.cstat(path)
    local err, info = syscall("cstat", path)
    return info, err
end

function sys.mopen(mode, contents, limit)
    local err, fd = syscall("mopen", mode, contents, limit)
    return fd, err
end

function sys.mkpipe(inFD, outFD)
    local err, fd = syscall("mkpipe", inFD, outFD)
    return fd, err
end

function sys.mkstream(vtable)
    local err, fd = syscall("mkstream", vtable)
    return fd, err
end

function sys.kvmopen(name)
    local err, fd = syscall("kvmopen", name)
    return fd, err
end

function sys.close(fd)
    local err = syscall("close", fd)
    return err == nil, err
end

function sys.write(fd, data)
    local err = syscall("write", fd, data)
    return err == nil, err
end

function sys.read(fd, len)
    local err, data = syscall("read", fd, len)
    return data, err
end

function sys.seek(fd, whence, off)
    local err, pos = syscall("seek", fd, whence, off)
    return pos, err
end

function sys.ioctl(fd, action, ...)
    local t = {syscall("ioctl", fd, action, ...)}
    if t[1] then
        return nil, t[1]
    end
    return table.unpack(t, 2)
end

function sys.ftype(path)
    local err, t = syscall("ftype", path)
    return t, err
end

function sys.list(path)
    local err, l = syscall("list", path)
    return l, err
end

function sys.exit(status)
    local err = syscall("exit", status)
    return err == nil, err
end

function sys.getenv(env)
    local err, val = syscall("getenv", env)
    return val, err
end

function sys.getenvs()
    local err, vals = syscall("getenvs")
    return vals, err
end

function sys.setenv(env, val)
    local err = syscall("setenv", env, val)
    return err == nil, err
end

function sys.pself()
    local err, pid = syscall("pself")
    return pid, err
end

function sys.pnext(pid)
    local err, npid = syscall("pnext", pid)
    return npid, err
end

function sys.pawait(pid)
    local err = syscall("pawait", pid)
    return err == nil, err
end

function sys.pwait(pid)
    local err = syscall("pwait", pid)
    return err == nil, err
end

function sys.pinfo(pid)
    local err, info = syscall("pinfo", pid)
    return info, err
end

function sys.pstatus(pid, status)
    local err = syscall("pstatus", pid, status)
    return err == nil, err
end

function sys.pexit(pid)
    local err = syscall("pexit", pid)
    return err == nil, err
end

function sys.pspawn(init, conf)
    local err, pid = syscall("pspawn", init, conf)
    return pid, err
end

function sys.psignal(pid, event, ...)
    local err = syscall("psignal", pid, event, ...)
    return err == nil, err
end

function sys.cprimary(type)
    local err, p = syscall("cprimary", type)
    return p, err
end

function sys.cproxy(addr)
    local err, p = syscall("cproxy", addr)
    return p, err
end

function sys.ctype(addr)
    local err, t = syscall("ctype", addr)
    return t, err
end

function sys.clist(all)
    local err, l = syscall("clist", all)
    return l, err
end

function sys.cinvoke(addr, method, ...)
    return syscall("cinvoke", addr, method, ...)
end

-- If hostname is nil, it just returns
-- If hostname is not nil, it will set the name and return
-- the new name
function sys.hostname(hostname)
    local err, name = syscall("hostname", hostname)
    return name, err
end

function sys.socket(protocol, subprotocol, config)
    local err, fd = syscall("socket", protocol, subprotocol, config)
    return fd, err
end

function sys.getaddrinfo(address, protocol)
    local err, info = syscall("getaddrinfo", address, protocol)
    return info, err
end

function sys.connect(fd, address, options)
    local err = syscall("connect", fd, address, options)
    return err == nil, err
end

function sys.aio_connect(fd, address, options)
    local err, packet = syscall("aio_connect", fd, address, options)
    return packet, err
end

function sys.serve(fd, options)
    local err = syscall("serve", fd, options)
    return err == nil, err
end

function sys.accept(fd)
    local err, client = syscall("accept", fd)
    return client, err
end

function sys.queued(fd, ...)
    local err, res = syscall("queued", fd, ...)
    return res, err
end

function sys.pop(fd, ...)
    local t = {syscall("pop", fd, ...)}
    if t[1] then
        return nil, t[1]
    else
        return table.unpack(t, 2)
    end
end

function sys.popWhere(fd, f)
    local t = {syscall("popWhere", fd, f)}
    if t[1] then
        return nil, t[1]
    else
        return table.unpack(t, 2)
    end
end

function sys.clear(fd, ...)
    local err = syscall("clear", fd, ...)
    return err == nil, err
end

function sys.push(fd, name, ...)
    local err = syscall("push", fd, name, ...)
    return err == nil, err
end

function sys.listen(callback, id)
    local err, lid = syscall("listen", callback, id)
    return lid, err
end

function sys.forget(id)
    local err = syscall("forget", id)
    return err == nil, err
end

function sys.aio_read(fd, len)
    local err, packet = syscall("aio_read", fd, len)
    return packet, err
end

function sys.aio_write(fd, data)
    local err, packet = syscall("aio_write", fd, data)
    return packet, err
end

function sys.ttyopen(graphics, keyboard)
    local err, fd = syscall("ttyopen", graphics, keyboard)
    return fd, err
end

function sys.attach(func, name)
    local err, tid = syscall("attach", func, name)
    return tid, err
end

function sys.openlock()
    local err, fd = syscall("openlock")
    return fd, err
end

function sys.tryLock(fd)
    local err, locked = syscall("tryLock", fd)
    return locked, err
end

function sys.lock(fd, timeout)
    local err, locked = syscall("lock", fd, timeout)
    return locked, err
end

function sys.unlock(fd, timeout)
    local err, locked = syscall("lock", fd, timeout)
    return locked, err
end

function sys.tkill(tid, msg, trace)
    local err = syscall("tkill", tid, msg, trace)
    return err == nil, err
end

function sys.tjoin(tid)
    local err = syscall("tjoin", tid)
    return err == nil, err
end

function sys.tstatus(tid)
    local err, status = syscall("tstatus", tid)
    return status, err
end

function sys.tsuspend(tid)
    local err = syscall("tsuspend", tid)
    return err == nil, err
end

function sys.tresume(tid)
    local err = syscall("tresume", tid)
    return err == nil, err
end

function sys.psymbol(symbol)
    local err, data = syscall("psymbol", symbol)
    return data, err
end

function sys.psource(symbol)
    local err, data = syscall("psource", symbol)
    return data, err
end

function sys.login(user, ring, password)
    local err = syscall("login", user, ring, password)
    return err == nil, err
end

function sys.uinfo(user)
    local err, info = syscall("uinfo", user)
    return info, err
end

function sys.uginfo(group)
    local err, info = syscall("uginfo", group)
    return info, err
end

function sys.ulist(group)
    local err, list = syscall("ulist", group)
    return list, err
end

function sys.ugroups()
    local err, list = syscall("ugroups")
    return list, err
end

function sys.ufindUser(name)
    local err, uid = syscall("ufindUser", name)
    return uid, err
end

function sys.ufindGroup(name)
    local err, uid = syscall("ufindGroup", name)
    return uid, err
end

return sys
